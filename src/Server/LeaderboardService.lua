--!strict
-- Classement mondial Top 10 Coins (OrderedDataStore) + panneau lobby existant.
-- Source de vérité : profile.Coins (DataService), jamais leaderstats seuls.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)
local LeaderboardUtil = require(Shared.LeaderboardUtil)
local HubDisplaysLogic = require(Shared.HubDisplaysLogic)
local HubDisplaysLayout = require(Shared.HubDisplaysLayout)
local HubBoardGui = require(Shared.HubBoardGui)
local DataService = require(script.Parent.DataService)

local ORDERED_STORE_NAME = Config.Data.GlobalCoinsLeaderboardStore or "GlobalCoinsLeaderboard_v1"
local TOP_N = 10
-- Nombre de lignes réellement affichées sur le panneau monde. Le hub central demande
-- un aperçu TOP 3 (attribut BPW_Rows) ; le cache et le classement restent en TOP 10.
local displayRows = TOP_N
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
	ArchBg = Color3.fromRGB(6, 12, 26),
	ArchMetal = Color3.fromRGB(72, 80, 94),
	ArchCyan = Color3.fromRGB(70, 210, 255),
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

local function compact(n: number): string
	return LeaderboardUtil.FormatCompact(n)
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
	-- Priorité : ancrage Tripo HubDisplays (LeftLeaderboardAnchor).
	local okHub, HubDisplaysService = pcall(function()
		return require(script.Parent.HubDisplaysService)
	end)
	if okHub and HubDisplaysService and type(HubDisplaysService.FindAnchor) == "function" then
		local anchor = HubDisplaysService.FindAnchor("Coins")
		if HubDisplaysLogic.AsBasePart(anchor) then
			print("[TopCoinsBoard] found via HubDisplays LeftLeaderboardAnchor")
			return anchor
		end
	end

	-- Tag unifié (ancrage uniquement)
	for _, inst in ipairs(CollectionService:GetTagged("BPW_TopCoinsBoard")) do
		local part = HubDisplaysLogic.AsBasePart(inst)
		if part and part.Name == "LeftLeaderboardAnchor" then
			print("[TopCoinsBoard] found via tag LeftLeaderboardAnchor:", instancePath(part))
			return part
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged("BPW_TopCoinsBoard")) do
		local part = HubDisplaysLogic.AsBasePart(inst)
		if part and part:GetAttribute("BPW_LeaderboardRole") == "Coins" then
			print("[TopCoinsBoard] found via tag role Coins:", instancePath(part))
			return part
		end
	end

	local hubRoot = workspace:FindFirstChild("BubblePopWorld")
	local hub = hubRoot and hubRoot:FindFirstChild("CentralHub")
	if hub then
		local named = hub:FindFirstChild("LeftLeaderboardAnchor", true)
		local left = HubDisplaysLogic.AsBasePart(named)
		if left then
			print("[TopCoinsBoard] found via name LeftLeaderboardAnchor")
			return left
		end
		for _, d in ipairs(hub:GetDescendants()) do
			if d:IsA("BasePart") and (
				d:GetAttribute("BPW_TopCoinsBoard") == true
				or d:GetAttribute("BPW_HubLeaderboard") == true
			) and d.Name ~= "CenterLeaderboardAnchor"
				and d.Name ~= "RightLeaderboardAnchor"
			then
				-- Ignore anciens panneaux flottants si ancrages existent ailleurs
				if d:FindFirstAncestor("HubDisplays") or d.Name == "LeftLeaderboardAnchor" then
					print("[TopCoinsBoard] found via attribute:", instancePath(d))
					return d
				end
			end
		end
	end

	-- Hub actif : ne jamais peindre Top5Face / panneaux Studio orphelins.
	if Config.Hub and Config.Hub.Enabled == true then
		print("[TopCoinsBoard] hub panel not found yet (skip legacy hosts)")
		return nil
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

local function buildHubTop5Rows(parent: Frame): Frame
	local existing = parent:FindFirstChild("Rows")
	if existing then
		existing:Destroy()
	end

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Size = UDim2.fromScale(1, 0.72)
	rows.Position = UDim2.fromScale(0, 0.2)
	rows.BackgroundTransparency = 1
	rows.ClipsDescendants = true
	rows.LayoutOrder = 3
	rows.Parent = parent

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0.015, 0)
	rowsLayout.Parent = rows

	local rowScale = 1 / displayRows
	for i = 1, displayRows do
		local row = Instance.new("Frame")
		row.Name = ("Row%02d"):format(i)
		row.Size = UDim2.new(1, 0, rowScale - 0.015, 0)
		row.BackgroundColor3 = if i % 2 == 0 then COLORS.RowB else COLORS.RowA
		row.BackgroundTransparency = 0.25
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.ZIndex = 1
		row.Parent = rows

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 10)
		rowCorner.Parent = row

		local rank = makeLabel(row, "Rank", {
			Size = UDim2.fromScale(0.12, 0.85),
			Position = UDim2.fromScale(0.02, 0.075),
			Text = tostring(i),
			TextColor3 = rankAccent(i),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBlack,
			ZIndex = 3,
		}, false)
		rank.TextScaled = true

		local player = makeLabel(row, "Player", {
			Size = UDim2.fromScale(0.52, 0.8),
			Position = UDim2.fromScale(0.16, 0.1),
			Text = "—",
			TextColor3 = COLORS.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Enum.Font.GothamMedium,
			ZIndex = 3,
		}, false)
		player.TextScaled = true

		local coins = makeLabel(row, "Coins", {
			Size = UDim2.fromScale(0.28, 0.8),
			Position = UDim2.fromScale(0.7, 0.1),
			Text = "—",
			TextColor3 = if i <= 3 then rankAccent(i) else COLORS.Accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Enum.Font.GothamBold,
			ZIndex = 3,
		}, false)
		coins.TextScaled = true
	end

	return rows
end

local function buildHubTop5Screen(surfaceGui: SurfaceGui): (Frame, TextLabel)
	for _, child in ipairs(surfaceGui:GetChildren()) do
		child:Destroy()
	end

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = COLORS.ArchBg
	root.BackgroundTransparency = 0.12
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = surfaceGui
	root:SetAttribute("BPW_ArchScreen", 2)

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 18)
	rootCorner.Parent = root

	local metal = Instance.new("UIStroke")
	metal.Name = "MetalStroke"
	metal.Color = COLORS.ArchMetal
	metal.Thickness = 3
	metal.Transparency = 0.15
	metal.Parent = root

	local cyanRim = Instance.new("Frame")
	cyanRim.Name = "CyanRim"
	cyanRim.Size = UDim2.fromScale(1, 1)
	cyanRim.BackgroundTransparency = 1
	cyanRim.BorderSizePixel = 0
	cyanRim.Parent = root
	local cyanCorner = Instance.new("UICorner")
	cyanCorner.CornerRadius = UDim.new(0, 18)
	cyanCorner.Parent = cyanRim
	local cyan = Instance.new("UIStroke")
	cyan.Color = COLORS.ArchCyan
	cyan.Thickness = 1.5
	cyan.Transparency = 0.4
	cyan.Parent = cyanRim

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.035, 0)
	padding.PaddingBottom = UDim.new(0.035, 0)
	padding.PaddingLeft = UDim.new(0.045, 0)
	padding.PaddingRight = UDim.new(0.045, 0)
	padding.Parent = root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.18)
	header.BackgroundColor3 = COLORS.HeaderBg
	header.BackgroundTransparency = 0.2
	header.BorderSizePixel = 0
	header.LayoutOrder = 1
	header.Parent = root

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 12)
	headerCorner.Parent = header

	local title = makeLabel(header, "Title", {
		Size = UDim2.fromScale(0.92, 0.78),
		Position = UDim2.fromScale(0.04, 0.11),
		Text = L10n.HubTopTitle,
		Font = Enum.Font.GothamBlack,
		TextColor3 = COLORS.ArchCyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	}, false)
	title.TextScaled = true

	buildHubTop5Rows(root)

	local status = makeLabel(root, "StatusLabel", {
		Size = UDim2.fromScale(1, 0.06),
		Position = UDim2.fromScale(0, 0.93),
		Text = L10n.LoadingLeaderboard,
		TextColor3 = COLORS.Muted,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		ZIndex = 2,
	}, false)
	status.TextScaled = true

	return root, status
end

local function buildRowsFrame(parent: Frame): Frame
	local existing = parent:FindFirstChild("Rows")
	if existing then
		existing:Destroy()
	end

	-- Aperçu court (hub) : lignes hautes et texte plus grand, sinon rien ne remplit
	-- le panneau. Classement complet : lignes compactes historiques.
	local compact = displayRows > 3
	local rowHeight = if compact then 36 else 84
	local textScale = if compact then 1 else 1.7

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Size = UDim2.new(1, 0, 0, displayRows * (rowHeight + 4))
	rows.BackgroundTransparency = 1
	rows.LayoutOrder = 3
	rows.Parent = parent

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, 4)
	rowsLayout.Parent = rows

	for i = 1, displayRows do
		local row = Instance.new("Frame")
		row.Name = ("Row%02d"):format(i)
		row.Size = UDim2.new(1, 0, 0, rowHeight)
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
		ensureTextConstraint(rank, 12, math.floor(20 * textScale))

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
		ensureTextConstraint(player, 11, math.floor(18 * textScale))

		local coins = makeLabel(row, "Coins", {
			Size = UDim2.new(0, 120, 1, 0),
			Position = UDim2.new(1, -126, 0, 0),
			Text = "—",
			TextColor3 = if i <= 3 then rankAccent(i) else COLORS.Accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Enum.Font.GothamBold,
			ZIndex = 3,
		}, false)
		ensureTextConstraint(coins, 11, math.floor(18 * textScale))
	end

	return rows
end

local function ensureBoardGui(surface: BasePart): (Frame, TextLabel)
	-- Validations strictes : jamais FindFirstChild sur non-Instance.
	if typeof(surface) ~= "Instance" or not surface:IsA("BasePart") then
		error("[LeaderboardService] ensureBoardGui: surface is not a BasePart")
	end

	local spec = HubDisplaysLayout.SpecByRole("Coins")
	local guiName = if spec then spec.GuiName else "CoinsLeaderboardGui"
	local title = L10n.TopCoinCollectors or L10n.HubTopTitle or "TOP COIN COLLECTORS"
	local theme = if spec then HubBoardGui.ThemeFromSpec(spec) else nil
	local dual = HubBoardGui.EnsureDualBoard(
		surface,
		guiName,
		title,
		theme,
		"Global · Top 10"
	)
	return dual.Roots[1], dual.Statuses[1]
end

local function setStatus(statusLabel: TextLabel, mode: StatusMode, detail: string?)
	statusMode = mode
	statusLabel.AutoLocalize = false
	if mode == "loading" then
		statusLabel.Text = L10n.LoadingLeaderboard or "Loading..."
		statusLabel.TextColor3 = COLORS.Muted
	elseif mode == "empty" then
		statusLabel.Text = L10n.NoRankingsYet or "No rankings yet"
		statusLabel.TextColor3 = COLORS.Muted
	elseif mode == "unavailable" then
		statusLabel.Text = detail or L10n.LeaderboardUnavailable or "Leaderboard unavailable"
		statusLabel.TextColor3 = COLORS.Bronze
	else
		statusLabel.Text = if detail and detail ~= "" then detail else ""
		statusLabel.TextColor3 = COLORS.Muted
	end
end

local function countUiRows(root: Frame): number
	local rows = HubDisplaysLogic.SafeFindFirstChild(root, "Rows")
	if not HubDisplaysLogic.AsFrame(rows) then
		return 0
	end
	local n = 0
	for i = 1, displayRows do
		if HubDisplaysLogic.SafeFindFirstChild(rows, ("Row%02d"):format(i)) then
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
	local mode: StatusMode = if showPlaceholders and (not entries or #entries == 0)
		then "empty"
		elseif entries and #entries > 0
		then "ready"
		else statusMode
	local spec = HubDisplaysLayout.SpecByRole("Coins")
	local theme = if spec then HubBoardGui.ThemeFromSpec(spec) else nil
	local status = HubDisplaysLogic.SafeFindFirstChild(root, "StatusLabel")
	local statusLabel = if status and status:IsA("TextLabel") then status else nil
	if statusLabel then
		HubBoardGui.Paint(
			root,
			statusLabel,
			entries,
			if mode == "loading" then "loading" elseif mode == "empty" then "empty" elseif mode == "unavailable" then "unavailable" else "ready",
			"Coins",
			L10n.NoRankingsYet,
			L10n.LeaderboardUnavailable,
			theme
		)
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
		print("[TopCoinsBoard] datastore error: store unavailable")
		dbg("fetchTopEntries: store is nil")
		return false, nil, "DataStore unavailable"
	end

	print("[TopCoinsBoard] requesting leaderboard store=", ORDERED_STORE_NAME)
	dbg("Before GetSortedAsync(false,", TOP_N, ") store=", ORDERED_STORE_NAME)

	-- Timeout : GetSortedAsync peut bloquer indéfiniment (Studio / API off).
	local FETCH_TIMEOUT_SEC = 8
	local resultOk = false
	local resultEntries: { BoardEntry }? = nil
	local resultErr: string? = nil
	local finished = false

	task.spawn(function()
		local ok, pagesOrErr = pcall(function()
			return store:GetSortedAsync(false, TOP_N)
		end)
		if finished then
			return
		end
		if not ok or not pagesOrErr then
			finished = true
			resultOk = false
			resultErr = tostring(pagesOrErr)
			print("[TopCoinsBoard] datastore error:", resultErr)
			return
		end
		local pageOk, pageOrErr = pcall(function()
			return pagesOrErr:GetCurrentPage()
		end)
		if finished then
			return
		end
		if not pageOk or type(pageOrErr) ~= "table" then
			finished = true
			resultOk = false
			resultErr = tostring(pageOrErr)
			print("[TopCoinsBoard] datastore error:", resultErr)
			return
		end

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
		finished = true
		resultOk = true
		resultEntries = entries
		print("[TopCoinsBoard] received", #entries, "entries")
	end)

	local t0 = os.clock()
	while not finished and (os.clock() - t0) < FETCH_TIMEOUT_SEC do
		task.wait(0.1)
	end
	if not finished then
		finished = true
		print("[TopCoinsBoard] datastore error: GetSortedAsync timeout after", FETCH_TIMEOUT_SEC, "s")
		return false, nil, "GetSortedAsync timeout"
	end
	return resultOk, resultEntries, resultErr
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
		if not boardWarned then
			boardWarned = true
			warn("[TopCoinsBoard] board not found (LeftLeaderboardAnchor / HubDisplays)")
		end
		return
	end

	print("[TopCoinsBoard] board found:", instancePath(surface))
	print("[TopCoinsBoard] updating mode=", mode, "entries=", if entries then #entries else "nil")

	displayRows = TOP_N
	if surface:GetAttribute("BPW_DisplaySurface") ~= true then
		surface:SetAttribute("BPW_DisplaySurface", true)
	end

	local paintMode: StatusMode = mode
	local paintEntries = entries

	if mode == "loading" and hasValidSnapshot and lastValidEntries and not usingStudioPreview then
		paintEntries = lastValidEntries
		paintMode = "ready"
	elseif entries then
		paintEntries = entries
		if #entries == 0 then
			paintMode = "empty"
		elseif mode == "unavailable" then
			paintMode = "unavailable"
		else
			paintMode = "ready"
		end
	elseif hasValidSnapshot and lastValidEntries then
		paintEntries = lastValidEntries
		paintMode = "unavailable"
	else
		-- Rien encore : garder Loading tant que la fetch n'a pas échoué.
		paintEntries = nil
		paintMode = if mode == "loading" then "loading" else mode
	end

	statusMode = paintMode
	local spec = HubDisplaysLayout.SpecByRole("Coins")
	local theme = if spec then HubBoardGui.ThemeFromSpec(spec) else nil
	local guiName = if spec then spec.GuiName else "CoinsLeaderboardGui"
	local title = L10n.TopCoinCollectors or L10n.HubTopTitle or "TOP COIN COLLECTORS"
	local n = HubBoardGui.PaintAnchor(
		surface,
		guiName,
		title,
		paintEntries,
		paintMode,
		"Coins",
		theme,
		"Global · Top 10",
		L10n.NoRankingsYet,
		detail or L10n.LeaderboardUnavailable
	)
	print("[TopCoinsBoard] UI updated mode=", paintMode, "rows=", n, "dualFaces=2")
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
	-- Toujours publier pour le client TopCoinsBoardController.
	publishCache(localEntries, true)
	if #localEntries == 0 then
		updateWorldBoard({}, "unavailable", L10n.LeaderboardUnavailableStudio)
	else
		updateWorldBoard(localEntries, "ready", L10n.LeaderboardStudioPreview)
	end
end

local function RefreshLeaderboard()
	print("[TopCoinsBoard] requesting leaderboard")
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
	-- Studio / ODS vide : encore aucune écriture mondiale → aperçu local des joueurs présents.
	if #entries == 0 and RunService:IsStudio() then
		applyStudioPreview("empty store")
		dbg("RefreshLeaderboard END (empty store → studio preview)")
		return
	end
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
	-- Ne pas forcer "Loading" bloquant : rafraîchir directement (timeout dans fetch).
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
	-- Loading immédiat même si le panel n'a pas encore de données.
	pcall(function()
		updateWorldBoard(nil, "loading", nil)
	end)

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
