--!strict
-- Classement Weekly Best Score (OrderedDataStore par semaine ISO) + ancrage centre Tripo.
-- Métrique : plus haut total de coins du joueur pendant la semaine (max profile.Coins).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local LeaderboardUtil = require(Shared.LeaderboardUtil)
local WeeklyBestLogic = require(Shared.WeeklyBestLogic)
local HubDisplaysLogic = require(Shared.HubDisplaysLogic)
local HubDisplaysLayout = require(Shared.HubDisplaysLayout)
local HubBoardGui = require(Shared.HubBoardGui)
local DataService = require(script.Parent.DataService)

local WeeklyBestService = {}

local TOP_N = WeeklyBestLogic.TOP_N
local WRITE_THROTTLE = Config.Data.LeaderboardWriteThrottle or 45
local REFRESH_INTERVAL = Config.Data.LeaderboardRefreshInterval or 60
local FETCH_TIMEOUT_SEC = 8

local lastValidEntries: { WeeklyBestLogic.BoardEntry }? = nil
local hasValidSnapshot = false
local boardWarned = false
local nameCache: { [number]: { Name: string, Expires: number } } = {}
local pending: { [number]: number } = {}
local lastWriteAt: { [number]: number } = {}
local flushScheduled: { [number]: boolean } = {}
local playerByUserId: { [number]: Player } = {}
local currentWeekKey = ""
local refreshLoopStarted = false

local function log(...: any)
	print("[WeeklyBestBoard]", ...)
end

local function warnOnceBoard(msg: string)
	if not boardWarned then
		boardWarned = true
		warn("[WeeklyBestBoard]", msg)
	end
end

local function ensureProfileBag(profile: any): { WeekKey: string, Score: number }
	if type(profile.WeeklyBest) ~= "table" then
		profile.WeeklyBest = { WeekKey = "", Score = 0 }
	end
	return profile.WeeklyBest
end

local function getStore(weekKey: string): OrderedDataStore?
	local name = WeeklyBestLogic.StoreName(weekKey)
	log("datastore name/scope:", name)
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		return storeOrErr
	end
	warn("[WeeklyBestBoard] datastore error:", tostring(storeOrErr))
	return nil
end

local function findDisplaySurface(): BasePart?
	local okHub, HubDisplaysService = pcall(function()
		return require(script.Parent.HubDisplaysService)
	end)
	if okHub and HubDisplaysService and type(HubDisplaysService.FindAnchor) == "function" then
		local anchor = HubDisplaysService.FindAnchor("WeeklyBest")
		if HubDisplaysLogic.AsBasePart(anchor) then
			return anchor
		end
	end
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	if hub then
		local named = hub:FindFirstChild("CenterLeaderboardAnchor", true)
		return HubDisplaysLogic.AsBasePart(named)
	end
	return nil
end

local function resolveName(userId: number): string
	local now = os.clock()
	local cached = nameCache[userId]
	if cached and cached.Expires > now then
		return cached.Name
	end
	local online = playerByUserId[userId] or Players:GetPlayerByUserId(userId)
	if online then
		local display = online.DisplayName
		local chosen = if display and display ~= "" then display else online.Name
		nameCache[userId] = { Name = chosen, Expires = now + 600 }
		return chosen
	end
	return LeaderboardUtil.FallbackName(userId)
end

local function weekSubtitle(): string
	local label = L10n.WeekLabel or "Week"
	return label .. " " .. currentWeekKey .. " · Top 10"
end

local function paintBoard(entries: { WeeklyBestLogic.BoardEntry }?, mode: "loading" | "empty" | "ready" | "unavailable")
	local surface = findDisplaySurface()
	if not surface then
		warnOnceBoard("board not found (CenterLeaderboardAnchor)")
		return
	end
	log("board found:", surface:GetFullName(), "mode:", mode, "entries:", if entries then #entries else 0)

	local spec = HubDisplaysLayout.SpecByRole("WeeklyBest")
	if not spec then
		return
	end
	local theme = HubBoardGui.ThemeFromSpec(spec)
	local title = L10n.HubWeeklyBestTitle or "WEEKLY BEST"
	local n = HubBoardGui.PaintAnchor(
		surface,
		spec.GuiName,
		title,
		entries,
		mode,
		"WeeklyBest",
		theme,
		weekSubtitle(),
		L10n.NoWeeklyScoresYet,
		L10n.WeeklyLeaderboardUnavailable or L10n.LeaderboardUnavailable
	)
	log("UI updated mode=", mode, "rows=", n)
end

local function fetchTop(weekKey: string): (boolean, { WeeklyBestLogic.BoardEntry }?, string?)
	local store = getStore(weekKey)
	if not store then
		return false, nil, "store nil"
	end

	local finished = false
	local resultOk = false
	local resultEntries: { WeeklyBestLogic.BoardEntry }? = nil
	local resultErr: string? = nil

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
			return
		end
		local raw: { LeaderboardUtil.RawEntry } = {}
		for _, entry in ipairs(pageOrErr) do
			local userId = LeaderboardUtil.ParseUserIdKey(entry.key)
			local value = WeeklyBestLogic.SanitizeScore(entry.value)
			if userId and value ~= nil then
				table.insert(raw, {
					UserId = userId,
					Name = resolveName(userId),
					Value = value,
				})
			end
		end
		finished = true
		resultOk = true
		resultEntries = WeeklyBestLogic.TakeTop(raw, TOP_N)
	end)

	local t0 = os.clock()
	while not finished and (os.clock() - t0) < FETCH_TIMEOUT_SEC do
		task.wait(0.1)
	end
	if not finished then
		finished = true
		log("datastore error: GetSortedAsync timeout")
		return false, nil, "GetSortedAsync timeout"
	end
	if resultOk and resultEntries then
		log("received", #resultEntries, "entries")
	elseif resultErr then
		log("datastore error:", resultErr)
	end
	return resultOk, resultEntries, resultErr
end

local function publish(entries: { WeeklyBestLogic.BoardEntry })
	pcall(function()
		Remotes.Event("LeaderboardUpdate"):FireAllClients({
			WeeklyBest = {
				WeekKey = currentWeekKey,
				Entries = entries,
			},
		})
	end)
end

local function buildLocalPreview(): { WeeklyBestLogic.BoardEntry }
	local raw: { LeaderboardUtil.RawEntry } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local profile = DataService.Get(p)
		local bag = if profile then ensureProfileBag(profile) else nil
		local st = WeeklyBestLogic.RollWeekState(bag, os.time())
		local score = st.Score
		if score <= 0 and profile and profile.__loaded then
			score = math.max(0, math.floor(tonumber(profile.Coins) or 0))
		end
		if score > 0 then
			table.insert(raw, {
				UserId = p.UserId,
				Name = if p.DisplayName ~= "" then p.DisplayName else p.Name,
				Value = score,
			})
		end
	end
	return WeeklyBestLogic.TakeTop(raw, TOP_N)
end

local function refresh()
	currentWeekKey = WeeklyBestLogic.WeekKey(os.time())
	log("current week:", currentWeekKey)
	local ok, entries, err = fetchTop(currentWeekKey)
	if not ok or not entries then
		if hasValidSnapshot and lastValidEntries then
			log("datastore error — keep snapshot:", tostring(err))
			paintBoard(lastValidEntries, "unavailable")
		elseif RunService:IsStudio() then
			local preview = buildLocalPreview()
			log("Studio preview entries:", #preview)
			if #preview == 0 then
				paintBoard(nil, "unavailable")
			else
				paintBoard(preview, "ready")
			end
			publish(preview)
		else
			paintBoard(nil, "unavailable")
		end
		return
	end

	lastValidEntries = entries
	hasValidSnapshot = true
	if #entries == 0 then
		if RunService:IsStudio() then
			local preview = buildLocalPreview()
			if #preview > 0 then
				paintBoard(preview, "ready")
				publish(preview)
				return
			end
		end
		paintBoard({}, "empty")
	else
		paintBoard(entries, "ready")
	end
	publish(entries)
end

local function writeScore(userId: number, score: number, force: boolean)
	local weekKey = WeeklyBestLogic.WeekKey(os.time())
	local store = getStore(weekKey)
	if not store then
		return
	end
	local now = os.clock()
	local last = lastWriteAt[userId]
	if not force and last and (now - last) < WRITE_THROTTLE then
		pending[userId] = score
		if not flushScheduled[userId] then
			flushScheduled[userId] = true
			task.delay(WRITE_THROTTLE - (now - (last or 0)), function()
				flushScheduled[userId] = false
				local s = pending[userId]
				if s then
					pending[userId] = nil
					writeScore(userId, s, true)
				end
			end)
		end
		return
	end
	lastWriteAt[userId] = now
	pending[userId] = nil
	local key = tostring(userId)
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			return WeeklyBestLogic.MergeScore(old, score)
		end)
	end)
	if ok then
		log("score updated for userId", userId, "score=", score, "week=", weekKey)
	else
		warn("[WeeklyBestBoard] write fail userId=", userId, err)
	end
end

function WeeklyBestService.SyncCoins(player: Player, coins: number?)
	playerByUserId[player.UserId] = player
	local profile = DataService.Get(player)
	if not profile or profile.__loaded ~= true then
		return
	end
	local value = coins
	if value == nil then
		value = tonumber(profile.Coins) or 0
	end
	local sanitized = WeeklyBestLogic.SanitizeScore(value)
	if sanitized == nil or sanitized <= 0 then
		return
	end
	local bag = ensureProfileBag(profile)
	local rolled = WeeklyBestLogic.RollWeekState(bag, os.time())
	local nextScore = WeeklyBestLogic.MergeScore(rolled.Score, sanitized)
	profile.WeeklyBest = {
		WeekKey = rolled.WeekKey,
		Score = nextScore,
	}
	profile.__dirty = true
	pending[player.UserId] = nextScore
	writeScore(player.UserId, nextScore, false)
end

function WeeklyBestService.RecordPops(player: Player, amount: number)
	local add = math.max(0, math.floor(tonumber(amount) or 0))
	if add <= 0 then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local bag = ensureProfileBag(profile)
	local nextState = WeeklyBestLogic.AddLocalScore(bag, add, os.time())
	local coins = math.max(0, math.floor(tonumber(profile.Coins) or 0))
	nextState.Score = WeeklyBestLogic.MergeScore(nextState.Score, coins)
	profile.WeeklyBest = nextState
	profile.__dirty = true
	pending[player.UserId] = nextState.Score
	writeScore(player.UserId, nextState.Score, false)
end

function WeeklyBestService.ForceRefresh()
	refresh()
end

function WeeklyBestService.Start()
	currentWeekKey = WeeklyBestLogic.WeekKey(os.time())
	log("Start week=", currentWeekKey, "prefix=", WeeklyBestLogic.STORE_PREFIX)
	-- Loading immédiat, indépendant des DataStores.
	pcall(function()
		paintBoard(nil, "loading")
	end)

	DataService.OnCoinsChanged(function(player: Player, coins: number)
		WeeklyBestService.SyncCoins(player, coins)
	end)

	Players.PlayerAdded:Connect(function(player)
		playerByUserId[player.UserId] = player
		task.defer(function()
			for _ = 1, 40 do
				local profile = DataService.Get(player)
				if profile and profile.__loaded then
					WeeklyBestService.SyncCoins(player, profile.Coins)
					break
				end
				task.wait(0.25)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local score = pending[player.UserId]
		if score then
			writeScore(player.UserId, score, true)
		end
		playerByUserId[player.UserId] = nil
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		playerByUserId[p.UserId] = p
		task.defer(function()
			WeeklyBestService.SyncCoins(p)
		end)
	end

	if not refreshLoopStarted then
		refreshLoopStarted = true
		task.spawn(function()
			task.wait(2.2)
			pcall(refresh)
			while true do
				task.wait(REFRESH_INTERVAL)
				pcall(refresh)
			end
		end)
	end
end

return WeeklyBestService
