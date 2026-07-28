--!strict
-- Classement mondial Top 10 Coins (OrderedDataStore) + panneau lobby existant.
-- Source de vérité : profile.Coins (DataService), jamais leaderstats seuls.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)
local LeaderboardUtil = require(Shared.LeaderboardUtil)
local DataService = require(script.Parent.DataService)

local ORDERED_STORE_NAME = Config.Data.GlobalCoinsLeaderboardStore or "GlobalCoinsLeaderboard_v1"
local TOP_N = 10
local WRITE_THROTTLE_SEC = Config.Data.LeaderboardWriteThrottle or 45
local REFRESH_INTERVAL_SEC = Config.Data.LeaderboardRefreshInterval or 60
local NAME_CACHE_TTL_SEC = 600
local WRITE_MAX_ATTEMPTS = 4

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
local studioApiWarned = false

local cache: { [string]: any } = {}
local lastValidEntries: { any }? = nil
local hasValidSnapshot = false
local usingStudioPreview = false

local nameCache: { [number]: { Name: string, Expires: number } } = {}
local pendingScores: { [number]: number } = {}
local lastWriteAt: { [number]: number } = {}
local flushScheduled: { [number]: boolean } = {}
local writeAttempts: { [number]: number } = {}
local playerByUserId: { [number]: Player } = {}

local boardWarned = false
local refreshLoopStarted = false
local lastRefreshWarnAt = 0
local lastWriteWarnAt = 0
local refreshSoonToken = 0
local statusMode: "loading" | "empty" | "ready" | "unavailable" = "loading"

type StatusMode = "loading" | "empty" | "ready" | "unavailable"
type BoardEntry = LeaderboardUtil.BoardEntry

local function dbg(...: any)
	print("[LeaderboardDebug]", ...)
end

local function instancePath(inst: Instance?): string
	if not inst then
		return "(nil)"
	end
	local parts: { string } = {}
	local cur: Instance? = inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

local function sanitizeCoins(value: any): number?
	return LeaderboardUtil.SanitizeCoins(value)
end

local function comma(n: number): string
	return LeaderboardUtil.Comma(n)
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
		if RunService:IsStudio() then
			warn("[LeaderboardService] Activez Game Settings > Security > Enable Studio Access to API Services pour le classement mondial.")
		end
	end
	return nil
end

local function findDisplaySurface(): BasePart?
	-- 1) Panneau physique existant portant le titre TOP COIN COLLECTORS
	local needle = "TOP COIN COLLECTORS"
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") then
			local text = string.upper(tostring((desc :: TextLabel).Text))
			if string.find(text, needle, 1, true) then
				local gui = desc:FindFirstAncestorWhichIsA("SurfaceGui")
				if gui and gui.Parent and gui.Parent:IsA("BasePart") then
					dbg("Found title panel model/part:", instancePath(gui.Parent))
					dbg("Found title TextLabel:", instancePath(desc))
					return gui.Parent :: BasePart
				end
			end
		end
	end

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

local function makeLabel(parent: Instance, name: string, props: { [string]: any }, localize: boolean?): TextLabel
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
	if localize == false then
		L10nUtil.markNoLocalize(label)
	else
		label.AutoLocalize = true
	end
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

local function buildRowsFrame(parent: Frame): Frame
	local existing = parent:FindFirstChild("Rows")
	if existing then
		existing:Destroy()
	end

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Size = UDim2.new(1, 0, 0, 400)
	rows.BackgroundTransparency = 1
	rows.LayoutOrder = 3
	rows.Parent = parent

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
		}, false)
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
		}, false)
		ensureTextConstraint(player, 11, 18)

		local coins = makeLabel(row, "Coins", {
			Size = UDim2.new(0, 120, 1, 0),
			Position = UDim2.new(1, -126, 0, 0),
			Text = "—",
			TextColor3 = if i <= 3 then rankAccent(i) else COLORS.Accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Enum.Font.GothamBold,
			ZIndex = 3,
		}, false)
		ensureTextConstraint(coins, 11, 18)
	end

	return rows
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
	surfaceGui.Enabled = true

	local root = surfaceGui:FindFirstChild("Root")
	local needsFullBuild = not (root and root:IsA("Frame"))
	if needsFullBuild then
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
			Text = L10n.TopCoinCollectors,
			Font = Enum.Font.GothamBlack,
			TextColor3 = COLORS.Text,
			ZIndex = 2,
		})
		ensureTextConstraint(title, 18, 34)

		local subtitle = makeLabel(header, "Subtitle", {
			Size = UDim2.new(1, -16, 0, 22),
			Position = UDim2.new(0, 8, 0, 42),
			Text = L10n.GlobalLeaderboard,
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
			Text = L10n.Rank,
			TextColor3 = COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			ZIndex = 2,
		})
		ensureTextConstraint(rankHeader, 10, 16)

		local playerHeader = makeLabel(columnHeader, "PlayerHeader", {
			Size = UDim2.new(1, -190, 1, 0),
			Position = UDim2.new(0, 60, 0, 0),
			Text = L10n.Player,
			TextColor3 = COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
			ZIndex = 2,
		})
		ensureTextConstraint(playerHeader, 10, 16)

		local coinsHeader = makeLabel(columnHeader, "CoinsHeader", {
			Size = UDim2.new(0, 120, 1, 0),
			Position = UDim2.new(1, -120, 0, 0),
			Text = L10n.Coins,
			TextColor3 = COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Enum.Font.GothamBold,
			ZIndex = 2,
		})
		ensureTextConstraint(coinsHeader, 10, 16)

		buildRowsFrame(root :: Frame)

		local status = makeLabel(root, "StatusLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Text = L10n.LoadingLeaderboard,
			TextColor3 = COLORS.Muted,
			Font = Enum.Font.Gotham,
			LayoutOrder = 4,
			ZIndex = 2,
		})
		ensureTextConstraint(status, 10, 16)
	else
		local rootFrame = root :: Frame
		local rows = rootFrame:FindFirstChild("Rows")
		if not (rows and rows:IsA("Frame") and rows:FindFirstChild("Row01")) then
			buildRowsFrame(rootFrame)
		end
	end

	local rootFrame = root :: Frame
	local statusLabel = rootFrame:FindFirstChild("StatusLabel")
	if not (statusLabel and statusLabel:IsA("TextLabel")) then
		statusLabel = makeLabel(rootFrame, "StatusLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Text = L10n.LoadingLeaderboard,
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
		L10nUtil.localize(statusLabel, L10n.LoadingLeaderboard)
		statusLabel.TextColor3 = COLORS.Muted
	elseif mode == "empty" then
		L10nUtil.localize(statusLabel, L10n.NoRankingsYet)
		statusLabel.TextColor3 = COLORS.Muted
	elseif mode == "unavailable" then
		L10nUtil.localize(statusLabel, detail or L10n.LeaderboardUnavailable)
		statusLabel.TextColor3 = COLORS.Bronze
	else
		if detail and detail ~= "" then
			L10nUtil.localize(statusLabel, detail)
		else
			L10nUtil.dynamic(statusLabel, "")
		end
		statusLabel.TextColor3 = COLORS.Muted
	end
end

local function countUiRows(root: Frame): number
	local rows = root:FindFirstChild("Rows")
	if not (rows and rows:IsA("Frame")) then
		return 0
	end
	local n = 0
	for i = 1, TOP_N do
		if rows:FindFirstChild(("Row%02d"):format(i)) then
			n += 1
		end
	end
	return n
end

local function logPresentPlayers()
	local list = Players:GetPlayers()
	dbg("Players present:", #list)
	for _, player in ipairs(list) do
		local profile = DataService.Get(player)
		local loaded = profile ~= nil and profile.__loaded == true
		local profileCoins = if profile then tostring(profile.Coins) else "(no profile)"
		local lsCoins = "(none)"
		local ls = player:FindFirstChild("leaderstats")
		if ls then
			local coinsVal = ls:FindFirstChild("Coins")
			if coinsVal and coinsVal:IsA("IntValue") then
				lsCoins = tostring(coinsVal.Value)
			elseif coinsVal then
				lsCoins = tostring((coinsVal :: any).Value)
			end
		end
		dbg(
			"Player:",
			player.Name,
			"| UserId:",
			player.UserId,
			"| profileLoaded:",
			loaded,
			"| profile.Coins:",
			profileCoins,
			"| leaderstats.Coins:",
			lsCoins
		)
	end
end

local function paintRows(root: Frame, entries: { BoardEntry }?, showPlaceholders: boolean)
	local rows = root:FindFirstChild("Rows")
	if not (rows and rows:IsA("Frame")) then
		dbg("paintRows: Rows frame missing under", instancePath(root))
		return
	end

	local uiRowCount = countUiRows(root)
	dbg("UI rows found before fill:", uiPropCount)
	dbg("paintRows entries:", if entries then #entries else 0, "| showPlaceholders:", showPlaceholders)

	-- Nettoyage : pas de lignes dynamiques parasites hors Row01..Row10
	for _, child in ipairs(rows:GetChildren()) do
		if child:IsA("Frame") and not string.match(child.Name, "^Row%d%d$") then
			child:Destroy()
		end
	end

	for i = 1, TOP_N do
		local row = rows:FindFirstChild(("Row%02d"):format(i))
		if not (row and row:IsA("Frame")) then
			dbg("paintRows: missing", ("Row%02d"):format(i))
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
			dbg("Filling rank", entry.Rank, "using", instancePath(row))
			if rankLabel and rankLabel:IsA("TextLabel") then
				rankLabel.Visible = true
				rankLabel.TextTransparency = 0
				L10nUtil.dynamic(rankLabel, tostring(entry.Rank))
				rankLabel.TextColor3 = rankAccent(entry.Rank)
			end
			if playerLabel and playerLabel:IsA("TextLabel") then
				playerLabel.Visible = true
				playerLabel.TextTransparency = 0
				L10nUtil.dynamic(playerLabel, entry.Name)
				playerLabel.TextColor3 = COLORS.Text
			end
			if coinsLabel and coinsLabel:IsA("TextLabel") then
				coinsLabel.Visible = true
				coinsLabel.TextTransparency = 0
				L10nUtil.dynamic(coinsLabel, comma(entry.Value))
				coinsLabel.TextColor3 = if entry.Rank <= 3 then rankAccent(entry.Rank) else COLORS.Accent
			end
			dbg("Filled row", i, "| rank:", entry.Rank, "| name:", entry.Name, "| coins:", entry.Value)
		elseif showPlaceholders then
			if rankLabel and rankLabel:IsA("TextLabel") then
				L10nUtil.dynamic(rankLabel, tostring(i))
				rankLabel.TextColor3 = rankAccent(i)
			end
			if playerLabel and playerLabel:IsA("TextLabel") then
				L10nUtil.dynamic(playerLabel, "—")
				playerLabel.TextColor3 = COLORS.Muted
			end
			if coinsLabel and coinsLabel:IsA("TextLabel") then
				L10nUtil.dynamic(coinsLabel, "—")
				coinsLabel.TextColor3 = COLORS.Muted
			end
			dbg("Placeholder row", i)
		end
	end
end

-- Résolution synchrone non-bloquante : cache + joueurs en ligne uniquement.
-- Jamais GetNameFromUserIdAsync / GetUserInfosByUserIdsAsync ici (peuvent yield indéfiniment).
local function resolveNamesImmediate(userIds: { number }): { [number]: string }
	local resolved: { [number]: string } = {}
	local now = os.clock()
	for _, userId in ipairs(userIds) do
		local cached = nameCache[userId]
		if cached and cached.Expires > now then
			resolved[userId] = cached.Name
			continue
		end
		local online = playerByUserId[userId] or Players:GetPlayerByUserId(userId)
		if online then
			local display = online.DisplayName
			local chosen = if display and display ~= "" then display else online.Name
			resolved[userId] = chosen
			nameCache[userId] = { Name = chosen, Expires = now + NAME_CACHE_TTL_SEC }
		else
			resolved[userId] = LeaderboardUtil.FallbackName(userId)
		end
	end
	return resolved
end

-- Remplace les fallbacks par de vrais noms en arrière-plan (timeout 2.5s / id).
local function resolveNamesAsync(entries: { BoardEntry }, onNameReady: (BoardEntry) -> ())
	for _, entry in ipairs(entries) do
		local userId = entry.UserId
		local isFallback = entry.Name == LeaderboardUtil.FallbackName(userId)
			or string.match(entry.Name, "^Player %d+$") ~= nil
		if not isFallback then
			continue
		end

		task.spawn(function()
			local online = playerByUserId[userId] or Players:GetPlayerByUserId(userId)
			if online then
				local display = online.DisplayName
				local chosen = if display and display ~= "" then display else online.Name
				nameCache[userId] = { Name = chosen, Expires = os.clock() + NAME_CACHE_TTL_SEC }
				entry.Name = chosen
				onNameReady(entry)
				return
			end

			dbg("Before GetNameFromUserIdAsync", userId)
			local finished = false

			task.spawn(function()
				local ok, nameOrErr = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				if finished then
					return
				end
				finished = true
				if ok and type(nameOrErr) == "string" and nameOrErr ~= "" then
					dbg("After GetNameFromUserIdAsync", userId, "=>", nameOrErr)
					nameCache[userId] = { Name = nameOrErr, Expires = os.clock() + NAME_CACHE_TTL_SEC }
					entry.Name = nameOrErr
					onNameReady(entry)
				else
					warn("[LeaderboardDebug] GetNameFromUserIdAsync error", userId, tostring(nameOrErr))
				end
			end)

			task.delay(2.5, function()
				if finished then
					return
				end
				finished = true
				warn("[LeaderboardDebug] GetNameFromUserIdAsync timeout", userId)
			end)
		end)
	end
end

local function scheduleRefreshSoon(delaySec: number?)
	refreshSoonToken += 1
	local token = refreshSoonToken
	task.delay(delaySec or 3, function()
		if token ~= refreshSoonToken then
			return
		end
		pcall(function()
			LeaderboardService.ForceRefresh()
		end)
	end)
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
		writeAttempts[userId] = nil
		scheduleRefreshSoon(4)
		return true
	end

	local attempts = (writeAttempts[userId] or 0) + 1
	writeAttempts[userId] = attempts
	pendingScores[userId] = coins

	if attempts <= WRITE_MAX_ATTEMPTS and not flushScheduled[userId] then
		flushScheduled[userId] = true
		local delaySec = math.min(30, 2 ^ attempts)
		task.delay(delaySec, function()
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
		warn("[LeaderboardService] écriture échouée pour", userId, err, ("attempt %d/%d"):format(attempts, WRITE_MAX_ATTEMPTS))
		if RunService:IsStudio() and not studioApiWarned then
			studioApiWarned = true
			warn("[LeaderboardService] DataStore inaccessible en Studio — activez Enable Studio Access to API Services.")
		end
	end
	return false
end

-- Synchronisation unique : total actuel profile.Coins → OrderedDataStore.
local function queuePlayerCoins(player: Player, force: boolean?)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	-- Ne jamais écrire dans l'ODS si le profil n'a pas chargé (évite d'écraser avec 0).
	if profile.__loaded ~= true then
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

local function buildLocalStudioEntries(): { BoardEntry }
	local raw: { LeaderboardUtil.RawEntry } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.Get(player)
		local coins = sanitizeCoins(if profile then profile.Coins else 0) or 0
		local display = player.DisplayName
		local chosen = if display and display ~= "" then display else player.Name
		table.insert(raw, {
			UserId = player.UserId,
			Name = chosen,
			Value = coins,
		})
	end
	return LeaderboardUtil.TakeTop(raw, TOP_N)
end

local function fetchTopEntries(): (boolean, { BoardEntry }?, string?)
	local store = getStore()
	if not store then
		dbg("fetchTopEntries: store is nil")
		return false, nil, "DataStore unavailable"
	end

	dbg("Before GetSortedAsync(false,", TOP_N, ") store=", ORDERED_STORE_NAME)
	local ok, pagesOrErr = pcall(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok or not pagesOrErr then
		dbg("GetSortedAsync pcall FAILED:", tostring(pagesOrErr))
		return false, nil, tostring(pagesOrErr)
	end
	dbg("GetSortedAsync pcall OK")

	local pageOk, pageOrErr = pcall(function()
		return pagesOrErr:GetCurrentPage()
	end)
	if not pageOk or type(pageOrErr) ~= "table" then
		dbg("GetCurrentPage pcall FAILED:", tostring(pageOrErr))
		return false, nil, tostring(pageOrErr)
	end

	dbg("After GetSortedAsync / GetCurrentPage entries received:", #pageOrErr)

	local userIds: { number } = {}
	local raw: { { UserId: number, Value: number, Rank: number } } = {}

	for rank, entry in ipairs(pageOrErr) do
		local userId = LeaderboardUtil.ParseUserIdKey(entry.key)
		local value = sanitizeCoins(entry.value)
		if userId and value ~= nil then
			table.insert(userIds, userId)
			table.insert(raw, { UserId = userId, Value = value, Rank = rank })
		end
	end

	-- Immédiat : fallback Player <UserId> / cache / online — jamais d'API bloquante ici.
	local names = resolveNamesImmediate(userIds)
	local entries: { BoardEntry } = {}
	for _, item in ipairs(raw) do
		table.insert(entries, {
			Rank = item.Rank,
			UserId = item.UserId,
			Name = names[item.UserId] or LeaderboardUtil.FallbackName(item.UserId),
			Value = item.Value,
		})
	end
	dbg("Entries prepared for rendering:", #entries)
	return true, entries, nil
end

local function publishCache(entries: { BoardEntry }, preview: boolean?)
	cache = {
		Coins = {
			Label = "Coins",
			Entries = entries,
			StudioPreview = preview == true,
		},
	}
	pcall(function()
		Remotes.Event("LeaderboardUpdate"):FireAllClients(cache)
	end)
end

local function updateWorldBoard(entries: { BoardEntry }?, mode: StatusMode, detail: string?)
	local surface = findDisplaySurface()
	if not surface then
		warn("[LeaderboardDebug] SurfaceGui host NOT FOUND")
		if not boardWarned then
			boardWarned = true
			warn("[LeaderboardService] panneau introuvable (attendu: BubblePopWorld.Lobby.LobbyDecor.GlobalLeaderboardBoard)")
		end
		return
	end

	dbg("Panel part path:", instancePath(surface))

	if surface.Name == "LeaderboardBoard" then
		surface.Name = "GlobalLeaderboardBoard"
	end
	if surface:GetAttribute("BPW_DisplaySurface") ~= true then
		surface:SetAttribute("BPW_DisplaySurface", true)
	end

	local root, statusLabel = ensureBoardGui(surface)
	local gui = surface:FindFirstChildWhichIsA("SurfaceGui")
	dbg("SurfaceGui path:", instancePath(gui))
	dbg("Root path:", instancePath(root))
	dbg("updateWorldBoard mode:", mode, "| detail:", tostring(detail), "| entries:", if entries then #entries else "nil")

	if mode == "loading" and hasValidSnapshot and lastValidEntries and not usingStudioPreview then
		paintRows(root, lastValidEntries, false)
		setStatus(statusLabel, "ready", nil)
		return
	end

	if entries then
		paintRows(root, entries, #entries == 0)
		if #entries == 0 then
			setStatus(statusLabel, "empty", nil)
		else
			setStatus(statusLabel, mode == "unavailable" and "unavailable" or "ready", detail)
		end
	elseif hasValidSnapshot and lastValidEntries then
		paintRows(root, lastValidEntries, false)
		setStatus(statusLabel, "unavailable", detail)
	else
		paintRows(root, nil, true)
		setStatus(statusLabel, mode, detail)
	end
end

local function applyStudioPreview(err: string?)
	usingStudioPreview = true
	dbg("applyStudioPreview err:", tostring(err))
	if not studioApiWarned then
		studioApiWarned = true
		warn("[LeaderboardService] Classement mondial indisponible en Studio (", tostring(err), ").")
		warn("[LeaderboardService] Activez Game Settings > Security > Enable Studio Access to API Services.")
		warn("[LeaderboardService] Affichage d'un aperçu local des joueurs présents (ne remplace pas le classement publié).")
	end
	local localEntries = buildLocalStudioEntries()
	dbg("Studio local preview entries:", #localEntries)
	for _, e in ipairs(localEntries) do
		dbg("Studio local entry:", e.Rank, e.Name, e.Value)
	end
	publishCache(localEntries, true)
	if #localEntries == 0 then
		updateWorldBoard({}, "unavailable", L10n.LeaderboardUnavailableStudio)
	else
		updateWorldBoard(localEntries, "unavailable", L10n.LeaderboardStudioPreview)
	end
end

local function RefreshLeaderboard()
	dbg("RefreshLeaderboard called")
	dbg("RunService:IsStudio() =", RunService:IsStudio())
	logPresentPlayers()

	local ok, entries, err = fetchTopEntries()
	dbg("fetchTopEntries ok=", ok, "| err=", tostring(err), "| entries=", if entries then #entries else "nil")
	if not ok or not entries then
		if RunService:IsStudio() then
			dbg("Branch: Studio fallback preview")
			applyStudioPreview(err)
		else
			usingStudioPreview = false
			dbg("Branch: published unavailable")
			updateWorldBoard(nil, "unavailable", L10n.LeaderboardUnavailable)
			if err and os.clock() - lastRefreshWarnAt > 60 then
				lastRefreshWarnAt = os.clock()
				warn("[LeaderboardService] refresh échoué:", err)
			end
		end
		dbg("RefreshLeaderboard END (fail/fallback path)")
		return
	end

	usingStudioPreview = false
	lastValidEntries = entries
	hasValidSnapshot = true
	publishCache(entries, false)
	updateWorldBoard(entries, if #entries == 0 then "empty" else "ready", nil)

	resolveNamesAsync(entries, function(updated)
		if lastValidEntries then
			for _, e in ipairs(lastValidEntries) do
				if e.UserId == updated.UserId then
					e.Name = updated.Name
					break
				end
			end
		end
		publishCache(lastValidEntries or entries, false)
		updateWorldBoard(lastValidEntries or entries, "ready", nil)
	end)

	dbg("RefreshLeaderboard END (success path, count=", #entries, ")")
end

function LeaderboardService.GetCache()
	return cache
end

function LeaderboardService.ForceRefresh()
	RefreshLeaderboard()
end

function LeaderboardService.RefreshLeaderboard()
	RefreshLeaderboard()
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
	writeAttempts[userId] = nil
	nameCache[userId] = nil
end

function LeaderboardService.QueueUpdate(player: Player, force: boolean?)
	queuePlayerCoins(player, force)
	if force and RunService:IsStudio() and usingStudioPreview then
		scheduleRefreshSoon(0.5)
	end
end

function LeaderboardService.RefreshWorldBoard()
	updateWorldBoard(lastValidEntries, if hasValidSnapshot then "ready" else "loading", nil)
	task.spawn(RefreshLeaderboard)
end

local function waitProfileThenRefresh(player: Player)
	dbg("waitProfileThenRefresh begin for", player.Name)
	playerByUserId[player.UserId] = player
	local loaded = false
	for _ = 1, 40 do
		local profile = DataService.Get(player)
		if profile and profile.__loaded then
			loaded = true
			dbg("Profile loaded for", player.Name, "Coins=", tostring(profile.Coins))
			queuePlayerCoins(player, true)
			break
		end
		task.wait(0.25)
	end
	if not loaded then
		dbg("Profile NOT loaded within timeout for", player.Name)
	end
	pcall(function()
		Remotes.Event("LeaderboardUpdate"):FireClient(player, cache)
	end)
	dbg("Mandatory RefreshLeaderboard after player/profile wait:", player.Name)
	RefreshLeaderboard()
end

function LeaderboardService.Start()
	getStore()
	print("[LeaderboardService] Start — store:", ORDERED_STORE_NAME)
	dbg("Start() IsStudio=", RunService:IsStudio())

	DataService.OnCoinsChanged(function(player: Player, _coins: number)
		queuePlayerCoins(player, false)
		if usingStudioPreview then
			scheduleRefreshSoon(1)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			waitProfileThenRefresh(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		queuePlayerCoins(player, true)
		playerByUserId[player.UserId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			waitProfileThenRefresh(player)
		end)
	end

	if not refreshLoopStarted then
		refreshLoopStarted = true
		task.spawn(function()
			dbg("Refresh loop starting (initial wait 2s, then every", REFRESH_INTERVAL_SEC, "s)")
			task.wait(2)
			dbg("Refresh loop: initial tick")
			pcall(RefreshLeaderboard)
			while true do
				task.wait(REFRESH_INTERVAL_SEC)
				dbg("Refresh loop: periodic tick")
				pcall(RefreshLeaderboard)
			end
		end)
	end

	game:BindToClose(function()
		flushAllPending(true)
		task.wait(2)
	end)
end

return LeaderboardService
