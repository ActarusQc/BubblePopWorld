--!strict
-- Classement mondial Highest Levels (OrderedDataStore versionné) + panneau vert.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local LeaderboardUtil = require(Shared.LeaderboardUtil)
local HubDisplaysLogic = require(Shared.HubDisplaysLogic)
local HubDisplaysLayout = require(Shared.HubDisplaysLayout)
local HubBoardGui = require(Shared.HubBoardGui)
local DataService = require(script.Parent.DataService)

local LevelLeaderboardService = {}

local ORDERED_STORE_NAME = Config.Data.GlobalLevelsLeaderboardStore or HubDisplaysLogic.LEVELS_STORE
local TOP_N = HubDisplaysLogic.TOP_N
local WRITE_THROTTLE = Config.Data.LeaderboardWriteThrottle or 45
local REFRESH_INTERVAL = Config.Data.LeaderboardRefreshInterval or 60
local FETCH_TIMEOUT_SEC = 8

local orderedStore: OrderedDataStore? = nil
local lastValidEntries: { LeaderboardUtil.BoardEntry }? = nil
local hasValidSnapshot = false
local boardWarned = false
local nameCache: { [number]: { Name: string, Expires: number } } = {}
local pending: { [number]: number } = {}
local lastWriteAt: { [number]: number } = {}
local flushScheduled: { [number]: boolean } = {}
local playerByUserId: { [number]: Player } = {}
local refreshLoopStarted = false
local knownBest: { [number]: number } = {}

local function log(...: any)
	print("[HighestLevels]", ...)
end

local function getStore(): OrderedDataStore?
	if orderedStore then
		return orderedStore
	end
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetOrderedDataStore(ORDERED_STORE_NAME)
	end)
	if ok then
		orderedStore = storeOrErr
		return orderedStore
	end
	warn("[HighestLevels] datastore error:", tostring(storeOrErr))
	return nil
end

local function findDisplaySurface(): BasePart?
	local HubDisplaysService = require(script.Parent.HubDisplaysService)
	local anchor = HubDisplaysService.FindAnchor("Levels")
	if anchor then
		return anchor
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

local function paintBoard(entries: { LeaderboardUtil.BoardEntry }?, mode: "loading" | "empty" | "ready" | "unavailable")
	local surface = findDisplaySurface()
	if not surface then
		if not boardWarned then
			boardWarned = true
			warn("[HighestLevels] board not found (RightLeaderboardAnchor)")
		end
		return
	end
	local spec = HubDisplaysLayout.SpecByRole("Levels")
	if not spec then
		return
	end
	local theme = HubBoardGui.ThemeFromSpec(spec)
	local title = L10n.HighestLevelsTitle or "HIGHEST LEVELS"
	local n = HubBoardGui.PaintAnchor(
		surface,
		spec.GuiName,
		title,
		entries,
		mode,
		"Levels",
		theme,
		"Global · Top 10",
		L10n.NoLevelRankingsYet or "No level rankings yet",
		L10n.LevelLeaderboardUnavailable or L10n.LeaderboardUnavailable
	)
	log("UI updated mode=", mode, "rows=", n, "entries=", if entries then #entries else 0)
end

local function fetchTop(): (boolean, { LeaderboardUtil.BoardEntry }?, string?)
	local store = getStore()
	if not store then
		return false, nil, "store nil"
	end

	local finished = false
	local resultOk = false
	local resultEntries: { LeaderboardUtil.BoardEntry }? = nil
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
			local value = HubDisplaysLogic.SanitizeLevel(entry.value)
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
		resultEntries = HubDisplaysLogic.TakeTop(raw, TOP_N)
	end)

	local t0 = os.clock()
	while not finished and (os.clock() - t0) < FETCH_TIMEOUT_SEC do
		task.wait(0.1)
	end
	if not finished then
		finished = true
		return false, nil, "GetSortedAsync timeout"
	end
	return resultOk, resultEntries, resultErr
end

local function publish(entries: { LeaderboardUtil.BoardEntry })
	pcall(function()
		Remotes.Event("LeaderboardUpdate"):FireAllClients({
			Levels = {
				Entries = entries,
			},
		})
	end)
end

local function buildLocalPreview(): { LeaderboardUtil.BoardEntry }
	local raw: { LeaderboardUtil.RawEntry } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local profile = DataService.Get(p)
		if profile and profile.__loaded then
			local level = HubDisplaysLogic.SanitizeLevel(profile.Level)
			if level then
				table.insert(raw, {
					UserId = p.UserId,
					Name = if p.DisplayName ~= "" then p.DisplayName else p.Name,
					Value = level,
				})
			end
		end
	end
	return HubDisplaysLogic.TakeTop(raw, TOP_N)
end

local function refresh()
	local ok, entries, err = fetchTop()
	if not ok or not entries then
		if hasValidSnapshot and lastValidEntries then
			paintBoard(lastValidEntries, "unavailable")
		elseif RunService:IsStudio() then
			local preview = buildLocalPreview()
			if #preview == 0 then
				paintBoard(nil, "unavailable")
			else
				paintBoard(preview, "ready")
			end
			publish(preview)
		else
			paintBoard(nil, "unavailable")
		end
		if err then
			log("refresh fail:", err)
		end
		return
	end
	lastValidEntries = entries
	hasValidSnapshot = true
	if #entries == 0 and RunService:IsStudio() then
		local preview = buildLocalPreview()
		if #preview > 0 then
			paintBoard(preview, "ready")
			publish(preview)
			return
		end
	end
	if #entries == 0 then
		paintBoard({}, "empty")
	else
		paintBoard(entries, "ready")
	end
	publish(entries)
end

local function writeLevel(userId: number, level: number, force: boolean)
	local store = getStore()
	if not store then
		return
	end
	local sanitized = HubDisplaysLogic.SanitizeLevel(level)
	if sanitized == nil then
		return
	end
	-- Garde locale : ne jamais écrire moins que le meilleur connu.
	local previousBest = knownBest[userId]
	local mergedLocal = HubDisplaysLogic.MergeHighestLevel(previousBest, sanitized)
	if mergedLocal == nil then
		return
	end
	if previousBest and mergedLocal < previousBest then
		return
	end
	knownBest[userId] = mergedLocal

	local now = os.clock()
	local last = lastWriteAt[userId]
	if not force and last and (now - last) < WRITE_THROTTLE then
		pending[userId] = mergedLocal
		if not flushScheduled[userId] then
			flushScheduled[userId] = true
			task.delay(WRITE_THROTTLE - (now - (last or 0)), function()
				flushScheduled[userId] = false
				local s = pending[userId]
				if s then
					pending[userId] = nil
					writeLevel(userId, s, true)
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
			return HubDisplaysLogic.MergeHighestLevel(old, mergedLocal)
		end)
	end)
	if ok then
		log("level updated userId", userId, "level=", mergedLocal)
	else
		warn("[HighestLevels] write fail", userId, err)
	end
end

function LevelLeaderboardService.SyncLevel(player: Player, level: number?)
	playerByUserId[player.UserId] = player
	local profile = DataService.Get(player)
	if not profile or profile.__loaded ~= true then
		return
	end
	local value = level
	if value == nil then
		value = tonumber(profile.Level) or 0
	end
	local sanitized = HubDisplaysLogic.SanitizeLevel(value)
	if sanitized == nil then
		return
	end
	writeLevel(player.UserId, sanitized, false)
end

function LevelLeaderboardService.ForceRefresh()
	refresh()
end

function LevelLeaderboardService.Start()
	getStore()
	log("Start store=", ORDERED_STORE_NAME)
	pcall(function()
		paintBoard(nil, "loading")
	end)

	DataService.OnLevelChanged(function(player: Player, level: number)
		LevelLeaderboardService.SyncLevel(player, level)
	end)

	Players.PlayerAdded:Connect(function(player)
		playerByUserId[player.UserId] = player
		task.defer(function()
			for _ = 1, 40 do
				local profile = DataService.Get(player)
				if profile and profile.__loaded then
					LevelLeaderboardService.SyncLevel(player, profile.Level)
					break
				end
				task.wait(0.25)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local lvl = pending[player.UserId]
		if lvl then
			writeLevel(player.UserId, lvl, true)
		end
		playerByUserId[player.UserId] = nil
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		playerByUserId[p.UserId] = p
		task.defer(function()
			LevelLeaderboardService.SyncLevel(p)
		end)
	end

	if not refreshLoopStarted then
		refreshLoopStarted = true
		task.spawn(function()
			task.wait(2.5)
			pcall(refresh)
			while true do
				task.wait(REFRESH_INTERVAL)
				pcall(refresh)
			end
		end)
	end
end

return LevelLeaderboardService
