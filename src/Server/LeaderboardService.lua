--!strict
-- Classement mondial Top 10 Coins (OrderedDataStore) + panneau lobby.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local ORDERED_STORE_NAME = Config.Data.GlobalCoinsLeaderboardStore or "GlobalCoinsLeaderboard_v1"
local TOP_N = 10
local WRITE_THROTTLE_SEC = Config.Data.LeaderboardWriteThrottle or 45
local REFRESH_INTERVAL_SEC = Config.Data.LeaderboardRefreshInterval or 60
local NAME_CACHE_TTL_SEC = 600
local MAX_SCORE = 2 ^ 31 - 1

local COLORS = {
	Bg = Color3.fromRGB(14, 22, 42),
	HeaderBg = Color3.fromRGB(18, 30, 55),
	RowA = Color3.fromRGB(22, 34, 58),
	RowB = Color3.fromRGB(18, 28, 50),
	Text = Color3.fromRGB(235, 242, 255),
	Muted = Color3.fromRGB(150, 170, 205),
	Accent = Color3.fromRGB(90, 170, 255),
	Gold = Color3.fromRGB(255, 205, 72),
	Silver = Color3.fromRGB(200, 210, 230),
	Bronze = Color3.fromRGB(210, 140, 70),
	Stroke = Color3.fromRGB(40, 70, 120),
}

local LeaderboardService = {}

local orderedStore: OrderedDataStore? = nil
local storeInitWarned = false

local cache: { [string]: any } = {}
local lastValidEntries: { any }? = nil
local hasValidSnapshot = false

local nameCache: { [number]: { Name: string, Expires: number } } = {}
local pendingScores: { [number]: number } = {}
local lastWriteAt: { [number]: number } = {}
local flushScheduled: { [number]: boolean } = {}
local playerByUserId: { [number]: Player } = {}

local boardWarned = false
local refreshLoopStarted = false
local lastRefreshWarnAt = 0
local lastWriteWarnAt = 0
local statusMode: "loading" | "empty" | "ready" | "unavailable" = "loading"

type StatusMode = "loading" | "empty" | "ready" | "unavailable"
type BoardEntry = {
	Rank: number,
	UserId: number,
	Name: string,
	Value: number,
}

local function sanitizeCoins(value: any): number?
	local n = tonumber(value)
	if type(n) ~= "number" then
		return nil
	end
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return math.clamp(math.floor(n), 0, MAX_SCORE)
end

local function comma(n: number): string
	local s = tostring(math.floor(math.max(0, n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function getStore(): OrderedDataStore?
	if orderedStore then
		return orderedStore
	end
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetOrderedDataStore(ORDERED_STORE_NAME)
	end)
	if ok and storeOrErr then
		orderedStore = storeOrErr
		return orderedStore
	end
	if not storeInitWarned then
		storeInitWarned = true
		warn("[LeaderboardService] OrderedDataStore indisponible:", tostring(storeOrErr))
	end
	return nil
end

local function findDisplaySurface(): BasePart?
	local root = workspace:FindFirstChild("BubblePopWorld")
	if not root then
		return nil
	end
	local lobby = root:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end

	local candidates = {
		lobby:FindFirstChild("GlobalLeaderboardBoard", true),
		lobby:FindFirstChild("LeaderboardBoard", true),
	}
	local decor = lobby:FindFirstChild("LobbyDecor")
	if decor then
		table.insert(candidates, 1, decor:FindFirstChild("GlobalLeaderboardBoard"))
		table.insert(candidates, 2, decor:FindFirstChild("LeaderboardBoard"))
		table.insert(candidates, 3, decor:FindFirstChild("DisplaySurface"))
	end

	for _, inst in ipairs(candidates) do
		if inst and inst:IsA("BasePart") then
			return inst
		elseif inst and inst:IsA("Model") then
			local surface = inst:FindFirstChild("DisplaySurface", true)
			if surface and surface:IsA("BasePart") then
				return surface
			end
			local part = inst:FindFirstChildWhichIsA("BasePart", true)
			if part then
				return part
			end
		end
	end
	return nil
end

local function ensureTextConstraint(label: TextLabel, minSize: number, maxSize: number)
	local existing = label:FindFirstChildOfClass("UITextSizeConstraint")
	if existing then
		existing.MinTextSize = minSize
		existing.MaxTextSize = maxSize
		return
	end
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
end

local function makeLabel(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = COLORS.Text
	label.TextScaled = true
	for key, value in pairs(props) do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function rankAccent(rank: number): Color3
	if rank == 1 then
		return COLORS.Gold
	elseif rank == 2 then
		return COLORS.Silver
	elseif rank == 3 then
		return COLORS.Bronze
	end
	return COLORS.Muted
end

local function ensureBoardGui(surface: BasePart): (Frame, TextLabel)
	local gui = surface:FindFirstChild("GlobalLeaderboardGui")
	if not (gui and gui:IsA("SurfaceGui")) then
		local legacy = surface:FindFirstChild("LeaderboardGui")
		if legacy then
			legacy:Destroy()
		end
		gui = Instance.new("SurfaceGui")
		gui.Name = "GlobalLeaderboardGui"
		gui.Parent = surface
	end

	local surfaceGui = gui :: SurfaceGui
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 40
	surfaceGui.LightInfluence = 0
	surfaceGui.Brightness = 1
	surfaceGui.AlwaysOnTop = false
	surfaceGui.ClipsDescendants = true
	surfaceGui.ZOffset = 1

	local root = surfaceGui:FindFirstChild("Root")
	if not (root and root:IsA("Frame")) then
		for _, child in ipairs(surfaceGui:GetChildren()) do
			child:Destroy()
		end
		root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundColor3 = COLORS.Bg
		root.BorderSizePixel = 0
		root.Parent = surfaceGui

		local rootCorner = Instance.new("UICorner")
		rootCorner.CornerRadius = UDim.new(0, 10)
		rootCorner.Parent = root

		local rootStroke = Instance.new("UIStroke")
		rootStroke.Color = COLORS.Stroke
		rootStroke.Thickness = 2
		rootStroke.Transparency = 0.35
		rootStroke.Parent = root

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = root

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = root

		local header = Instance.new("Frame")
		header.Name = "Header"
		header.Size = UDim2.new(1, 0, 0, 70)
		header.BackgroundColor3 = COLORS.HeaderBg
		header.BorderSizePixel = 0
		header.LayoutOrder = 1
		header.Parent = root

		local headerCorner = Instance.new("UICorner")
		headerCorner.CornerRadius = UDim.new(0, 8)
		headerCorner.Parent = header

		local title = makeLabel(header, "Title", {
			Size = UDim2.new(1, -16, 0, 38),
			Position = UDim2.new(0, 8, 0, 6),
			Text = "TOP COIN COLLECTORS",
			Font = Enum.Font.GothamBlack,
			TextColor3 = COLORS.Text,
			ZIndex = 2,
		})
		ensureTextConstraint(title, 18, 34)

		local subtitle = makeLabel(header, "Subtitle", {
			Size = UDim2.new(1, -16, 0, 22),
			Position = UDim2.new(0, 8, 0, 42),
			Text = "GLOBAL LEADERBOARD",
			Font = Enum.Font.GothamMedium,
			TextColor3 = COLORS.Accent,
			ZIndex = 2,
		})
		ensureTextConstraint(subtitle, 12, 18)

		local columnHeader = Instance.new("Frame")
		columnHeader.Name = "ColumnHeader"
		columnHeader.Size = UDim2.new(1, 0, 0, 28)
		columnHeader.BackgroundTransparency = 1
		columnHeader.LayoutOrder = 2
		columnHeader.Parent = root

		local rankHeader = makeLabel(columnHeader, "RankHeader", {
			Size = UDim2.new(0, 56, 1, 0),
			Text = "RANK",
			TextColor3 = COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			ZIndex = 2,
		})
		ensureTextConstraint(rankHeader, 10, 16)

		local playerHeader = makeLabel(columnHeader, "PlayerHeader", {
			Size = UDim2.new(1, -190, 1, 0),
			Position = UDim2.new(0, 60, 0, 0),
			Text = "PLAYER",
			TextColor3 = COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			ZIndex = 2,
		})
		ensureTextConstraint(playerHeader, 10, 16)

		local coinsHeader = makeLabel(columnHeader, "CoinsHeader", {
			Size = UDim2.new(0, 120, 1, 0),
			Position = UDim2.new(1, -120, 0, 0),
			Text = "COINS",
			TextColor3 = COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Enum.Font.GothamBold,
			ZIndex = 2,
		})
		ensureTextConstraint(coinsHeader, 10, 16)

		local rows = Instance.new("Frame")
		rows.Name = "Rows"
		rows.Size = UDim2.new(1, 0, 0, 400)
		rows.BackgroundTransparency = 1
		rows.LayoutOrder = 3
		rows.Parent = root

		local rowsLayout = Instance.new("UIListLayout")
		rowsLayout.FillDirection = Enum.FillDirection.Vertical
		rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowsLayout.Padding = UDim.new(0, 4)
		rowsLayout.Parent = rows

		for i = 1, TOP_N do
			local row = Instance.new("Frame")
			row.Name = ("Row%02d"):format(i)
			row.Size = UDim2.new(1, 0, 0, 36)
			row.BackgroundColor3 = if i % 2 == 0 then COLORS.RowB else COLORS.RowA
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.ZIndex = 1
			row.Parent = rows

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 6)
			rowCorner.Parent = row

			local accent = Instance.new("Frame")
			accent.Name = "Accent"
			accent.Size = UDim2.new(0, 4, 1, -8)
			accent.Position = UDim2.new(0, 4, 0, 4)
			accent.BackgroundColor3 = rankAccent(i)
			accent.BorderSizePixel = 0
			accent.ZIndex = 2
			accent.Parent = row

			local accentCorner = Instance.new("UICorner")
			accentCorner.CornerRadius = UDim.new(0, 2)
			accentCorner.Parent = accent

			local rank = makeLabel(row, "Rank", {
				Size = UDim2.new(0, 48, 1, 0),
				Position = UDim2.new(0, 12, 0, 0),
				Text = tostring(i),
				TextColor3 = rankAccent(i),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamBlack,
				ZIndex = 3,
			})
			ensureTextConstraint(rank, 12, 20)

			local player = makeLabel(row, "Player", {
				Size = UDim2.new(1, -190, 1, 0),
				Position = UDim2.new(0, 60, 0, 0),
				Text = "—",
				TextColor3 = COLORS.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Font = Enum.Font.GothamMedium,
				ZIndex = 3,
			})
			ensureTextConstraint(player, 11, 18)

			local coins = makeLabel(row, "Coins", {
				Size = UDim2.new(0, 120, 1, 0),
				Position = UDim2.new(1, -126, 0, 0),
				Text = "—",
				TextColor3 = if i <= 3 then rankAccent(i) else COLORS.Accent,
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Enum.Font.GothamBold,
				ZIndex = 3,
			})
			ensureTextConstraint(coins, 11, 18)
		end

		local status = makeLabel(root, "StatusLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Text = "Loading leaderboard...",
			TextColor3 = COLORS.Muted,
			Font = Enum.Font.Gotham,
			LayoutOrder = 4,
			ZIndex = 2,
		})
		ensureTextConstraint(status, 10, 16)
	end

	local rootFrame = root :: Frame
	local statusLabel = rootFrame:FindFirstChild("StatusLabel")
	if not (statusLabel and statusLabel:IsA("TextLabel")) then
		statusLabel = makeLabel(rootFrame, "StatusLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Text = "Loading leaderboard...",
			TextColor3 = COLORS.Muted,
			Font = Enum.Font.Gotham,
			LayoutOrder = 4,
			ZIndex = 2,
		})
		ensureTextConstraint(statusLabel, 10, 16)
	end

	return rootFrame, statusLabel :: TextLabel
end

local function setStatus(statusLabel: TextLabel, mode: StatusMode, detail: string?)
	statusMode = mode
	if mode == "loading" then
		statusLabel.Text = "Loading leaderboard..."
		statusLabel.TextColor3 = COLORS.Muted
	elseif mode == "empty" then
		statusLabel.Text = "No rankings yet"
		statusLabel.TextColor3 = COLORS.Muted
	elseif mode == "unavailable" then
		statusLabel.Text = detail or "Leaderboard temporarily unavailable"
		statusLabel.TextColor3 = COLORS.Bronze
	else
		statusLabel.Text = ""
		statusLabel.TextColor3 = COLORS.Muted
	end
end

local function paintRows(root: Frame, entries: { BoardEntry }?, showPlaceholders: boolean)
	local rows = root:FindFirstChild("Rows")
	if not (rows and rows:IsA("Frame")) then
		return
	end

	for i = 1, TOP_N do
		local row = rows:FindFirstChild(("Row%02d"):format(i))
		if not (row and row:IsA("Frame")) then
			continue
		end
		local rankLabel = row:FindFirstChild("Rank")
		local playerLabel = row:FindFirstChild("Player")
		local coinsLabel = row:FindFirstChild("Coins")
		local accent = row:FindFirstChild("Accent")
		local entry = if entries then entries[i] else nil

		if accent and accent:IsA("Frame") then
			accent.BackgroundColor3 = rankAccent(i)
			accent.Visible = entry ~= nil or showPlaceholders
		end

		if entry then
			if rankLabel and rankLabel:IsA("TextLabel") then
				rankLabel.Text = tostring(entry.Rank)
				rankLabel.TextColor3 = rankAccent(entry.Rank)
			end
			if playerLabel and playerLabel:IsA("TextLabel") then
				playerLabel.Text = entry.Name
				playerLabel.TextColor3 = COLORS.Text
			end
			if coinsLabel and coinsLabel:IsA("TextLabel") then
				coinsLabel.Text = comma(entry.Value)
				coinsLabel.TextColor3 = if entry.Rank <= 3 then rankAccent(entry.Rank) else COLORS.Accent
			end
		elseif showPlaceholders then
			if rankLabel and rankLabel:IsA("TextLabel") then
				rankLabel.Text = tostring(i)
				rankLabel.TextColor3 = rankAccent(i)
			end
			if playerLabel and playerLabel:IsA("TextLabel") then
				playerLabel.Text = "—"
				playerLabel.TextColor3 = COLORS.Muted
			end
			if coinsLabel and coinsLabel:IsA("TextLabel") then
				coinsLabel.Text = "—"
				coinsLabel.TextColor3 = COLORS.Muted
			end
		end
	end
end

local function resolveNames(userIds: { number }): { [number]: string }
	local resolved: { [number]: string } = {}
	local missing: { number } = {}
	local now = os.clock()

	for _, userId in ipairs(userIds) do
		local cached = nameCache[userId]
		if cached and cached.Expires > now then
			resolved[userId] = cached.Name
		else
			table.insert(missing, userId)
		end
	end

	if #missing == 0 then
		return resolved
	end

	-- Batch API (Roblox) quand disponible.
	local batchOk = false
	local getInfos = (Players :: any).GetUserInfosByUserIdsAsync
	if typeof(getInfos) == "function" then
		local ok, infos = pcall(function()
			return getInfos(Players, missing)
		end)
		if ok and type(infos) == "table" then
			batchOk = true
			for _, info in ipairs(infos) do
				local id = tonumber(info.Id or info.UserId)
				if id then
					local display = tostring(info.DisplayName or "")
					local username = tostring(info.Username or info.Name or "")
					local chosen = if display ~= "" then display elseif username ~= "" then username else ("Player " .. tostring(id))
					resolved[id] = chosen
					nameCache[id] = { Name = chosen, Expires = now + NAME_CACHE_TTL_SEC }
				end
			end
		end
	end

	for _, userId in ipairs(missing) do
		if resolved[userId] then
			continue
		end
		local online = playerByUserId[userId] or Players:GetPlayerByUserId(userId)
		if online then
			local display = online.DisplayName
			local chosen = if display and display ~= "" then display else online.Name
			resolved[userId] = chosen
			nameCache[userId] = { Name = chosen, Expires = now + NAME_CACHE_TTL_SEC }
			continue
		end

		local username = nil
		local ok, nameOrErr = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if ok and type(nameOrErr) == "string" and nameOrErr ~= "" then
			username = nameOrErr
		end

		local chosen = username or ("Player " .. tostring(userId))
		-- Si le batch a échoué, on n'a pas de DisplayName hors ligne : username reste le meilleur fallback.
		if not batchOk and not username then
			chosen = "Player " .. tostring(userId)
		end
		resolved[userId] = chosen
		nameCache[userId] = { Name = chosen, Expires = now + math.min(120, NAME_CACHE_TTL_SEC) }
	end

	return resolved
end

local function writeScore(userId: number, coins: number, force: boolean): boolean
	local store = getStore()
	if not store then
		return false
	end

	local now = os.clock()
	local last = lastWriteAt[userId]
	if not force and last and (now - last) < WRITE_THROTTLE_SEC then
		pendingScores[userId] = coins
		if not flushScheduled[userId] then
			flushScheduled[userId] = true
			local delaySec = math.max(0.5, WRITE_THROTTLE_SEC - (now - last))
			task.delay(delaySec, function()
				flushScheduled[userId] = nil
				local pending = pendingScores[userId]
				if pending == nil then
					return
				end
				pendingScores[userId] = nil
				writeScore(userId, pending, true)
			end)
		end
		return true
	end

	pendingScores[userId] = nil
	local ok, err = pcall(function()
		store:SetAsync(tostring(userId), coins)
	end)
	if ok then
		lastWriteAt[userId] = os.clock()
		return true
	end

	-- Remet en file pour un nouvel essai ; ne casse pas le gameplay.
	pendingScores[userId] = coins
	if not flushScheduled[userId] then
		flushScheduled[userId] = true
		task.delay(8, function()
			flushScheduled[userId] = nil
			local pending = pendingScores[userId]
			if pending ~= nil then
				pendingScores[userId] = nil
				writeScore(userId, pending, true)
			end
		end)
	end
	if os.clock() - lastWriteWarnAt > 30 then
		lastWriteWarnAt = os.clock()
		warn("[LeaderboardService] écriture échouée pour", userId, err)
	end
	return false
end

local function queuePlayerCoins(player: Player, force: boolean?)
	local profile = DataService.Get(player)
	if not profile or not profile.__loaded then
		return
	end
	local coins = sanitizeCoins(profile.Coins)
	if coins == nil then
		return
	end
	playerByUserId[player.UserId] = player
	local display = player.DisplayName
	local chosen = if display and display ~= "" then display else player.Name
	nameCache[player.UserId] = { Name = chosen, Expires = os.clock() + NAME_CACHE_TTL_SEC }
	writeScore(player.UserId, coins, force == true)
end

local function flushAllPending(force: boolean)
	for userId, coins in pairs(pendingScores) do
		pendingScores[userId] = nil
		writeScore(userId, coins, force)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		queuePlayerCoins(player, force)
	end
end

local function fetchTopEntries(): (boolean, { BoardEntry }?, string?)
	local store = getStore()
	if not store then
		return false, nil, "DataStore unavailable"
	end

	local ok, pagesOrErr = pcall(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok or not pagesOrErr then
		return false, nil, tostring(pagesOrErr)
	end

	local page = pagesOrErr:GetCurrentPage()
	local userIds: { number } = {}
	local raw: { { UserId: number, Value: number, Rank: number } } = {}

	for rank, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		local value = sanitizeCoins(entry.value)
		if userId and userId > 0 and value ~= nil then
			table.insert(userIds, userId)
			table.insert(raw, { UserId = userId, Value = value, Rank = rank })
		end
	end

	local names = resolveNames(userIds)
	local entries: { BoardEntry } = {}
	for _, item in ipairs(raw) do
		table.insert(entries, {
			Rank = item.Rank,
			UserId = item.UserId,
			Name = names[item.UserId] or ("Player " .. tostring(item.UserId)),
			Value = item.Value,
		})
	end
	return true, entries, nil
end

local function publishCache(entries: { BoardEntry })
	cache = {
		Coins = {
			Label = "Coins",
			Entries = entries,
		},
	}
	pcall(function()
		Remotes.Event("LeaderboardUpdate"):FireAllClients(cache)
	end)
end

local function updateWorldBoard(entries: { BoardEntry }?, mode: StatusMode, detail: string?)
	local surface = findDisplaySurface()
	if not surface then
		if not boardWarned then
			boardWarned = true
			warn("[LeaderboardService] panneau introuvable (attendu: BubblePopWorld.Lobby.LobbyDecor.GlobalLeaderboardBoard)")
		end
		return
	end

	if surface.Name == "LeaderboardBoard" then
		surface.Name = "GlobalLeaderboardBoard"
	end
	if surface:GetAttribute("BPW_DisplaySurface") ~= true then
		surface:SetAttribute("BPW_DisplaySurface", true)
	end

	local root, statusLabel = ensureBoardGui(surface)
	if mode == "loading" and hasValidSnapshot and lastValidEntries then
		paintRows(root, lastValidEntries, false)
		setStatus(statusLabel, "ready", nil)
		return
	end

	if entries then
		paintRows(root, entries, #entries == 0)
		if #entries == 0 then
			setStatus(statusLabel, "empty", nil)
		else
			setStatus(statusLabel, "ready", nil)
		end
	elseif hasValidSnapshot and lastValidEntries then
		paintRows(root, lastValidEntries, false)
		setStatus(statusLabel, "unavailable", detail)
	else
		paintRows(root, nil, true)
		setStatus(statusLabel, mode, detail)
	end
end

local function refresh()
	updateWorldBoard(nil, "loading", nil)

	local ok, entries, err = fetchTopEntries()
	if not ok or not entries then
		if RunService:IsStudio() and not hasValidSnapshot then
			updateWorldBoard({}, "empty", nil)
		else
			updateWorldBoard(nil, "unavailable", "Leaderboard temporarily unavailable")
			if err and os.clock() - lastRefreshWarnAt > 60 then
				lastRefreshWarnAt = os.clock()
				warn("[LeaderboardService] refresh échoué:", err)
			end
		end
		return
	end

	lastValidEntries = entries
	hasValidSnapshot = true
	publishCache(entries)
	updateWorldBoard(entries, if #entries == 0 then "empty" else "ready", nil)
end

function LeaderboardService.GetCache()
	return cache
end

function LeaderboardService.RemoveEntry(userId: number)
	local store = getStore()
	if not store then
		return
	end
	local ok, err = pcall(function()
		store:RemoveAsync(tostring(userId))
	end)
	if not ok then
		warn("[LeaderboardService] retrait impossible pour", userId, err)
	end
	pendingScores[userId] = nil
	lastWriteAt[userId] = nil
	nameCache[userId] = nil
end

function LeaderboardService.QueueUpdate(player: Player, force: boolean?)
	queuePlayerCoins(player, force)
end

function LeaderboardService.RefreshWorldBoard()
	updateWorldBoard(lastValidEntries, if hasValidSnapshot then "ready" else "loading", nil)
	if not hasValidSnapshot then
		task.spawn(refresh)
	end
end

function LeaderboardService.Start()
	getStore()

	DataService.OnCoinsChanged(function(player: Player, _coins: number)
		queuePlayerCoins(player, false)
	end)

	Players.PlayerAdded:Connect(function(player)
		playerByUserId[player.UserId] = player
		task.defer(function()
			-- Attend la fin du chargement DataService.
			for _ = 1, 40 do
				local profile = DataService.Get(player)
				if profile and profile.__loaded then
					queuePlayerCoins(player, true)
					break
				end
				task.wait(0.25)
			end
			pcall(function()
				Remotes.Event("LeaderboardUpdate"):FireClient(player, cache)
			end)
			LeaderboardService.RefreshWorldBoard()
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		queuePlayerCoins(player, true)
		playerByUserId[player.UserId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		playerByUserId[player.UserId] = player
		task.defer(function()
			for _ = 1, 40 do
				local profile = DataService.Get(player)
				if profile and profile.__loaded then
					queuePlayerCoins(player, true)
					break
				end
				task.wait(0.25)
			end
		end)
	end

	if not refreshLoopStarted then
		refreshLoopStarted = true
		task.spawn(function()
			task.wait(2)
			pcall(refresh)
			while true do
				task.wait(REFRESH_INTERVAL_SEC)
				pcall(refresh)
			end
		end)
	end

	game:BindToClose(function()
		flushAllPending(true)
		task.wait(2)
	end)
end

return LeaderboardService
