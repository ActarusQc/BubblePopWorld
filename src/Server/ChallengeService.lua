--!strict
-- Serveur autoritaire : défis quotidiens/hebdo, featured event, classement daily pops.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChallengeConfig = require(Shared.ChallengeConfig)
local ChallengeLogic = require(Shared.ChallengeLogic)
local Remotes = require(Shared.Remotes)
local ZoneDefs = require(Shared.ZoneDefs)

local DataService = require(script.Parent.DataService)

local ChallengeService = {}

type ChallengesState = ChallengeLogic.ChallengesState

local started = false
local playerStates: { [Player]: ChallengesState } = {}
local lastPushAt: { [Player]: number } = {}
local pendingLbScores: { [number]: number } = {}
local lastLbWriteAt: { [number]: number } = {}
local lbFlushScheduled: { [number]: boolean } = {}
local playerByUserId: { [number]: Player } = {}
local topCache: { entries: { any }, dailyKey: string, fetchedAt: number }? = nil
local periodLoopToken = 0
local lbRefreshToken = 0

local SPECIAL_RARITIES: { [string]: boolean } = {
	Rare = true,
	Golden = true,
	Diamond = true,
	Legendary = true,
}

local function isMainBubbleZone(zoneId: string): boolean
	return zoneId == "ClassicZone" or zoneId == "GameRoom"
end

local function isRealSpecialBubble(rarityId: string): boolean
	return rarityId ~= "Normal" and SPECIAL_RARITIES[rarityId] == true
end

local function nowUnix(): number
	return os.time()
end

local function softGas(method: string, player: Player?, ctx: any?)
	pcall(function()
		local GAS = require(script.Parent.GameAnalyticsService)
		local fn = GAS[method]
		if type(fn) == "function" then
			fn(player, ctx)
		end
	end)
end

local function hasSummerAccess(player: Player): boolean
	local level = DataService.GetPlayerLevel(player)
	if ZoneDefs.CanLevelEnter then
		return ZoneDefs.CanLevelEnter(level, "SummerZone") == true
	end
	return level >= 5
end

local function playerCtx(player: Player): ChallengeLogic.PlayerContext
	local featured = ChallengeLogic.FeaturedEventForDay(ChallengeLogic.DailyKey(nowUnix()))
	local enabled: { [string]: boolean } = {}
	pcall(function()
		local MiniEventConfig = require(Shared.MiniEventConfig)
		for _, id in ipairs(MiniEventConfig.ListEnabledEvents()) do
			enabled[id] = true
		end
	end)
	return {
		hasSummerAccess = hasSummerAccess(player),
		featuredEventType = featured,
		enabledEvents = enabled,
	}
end

local function ensureProfileBag(profile: any): any
	if type(profile.Challenges) ~= "table" then
		profile.Challenges = {}
	end
	return profile.Challenges
end

local function persistState(player: Player, state: ChallengesState)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.Challenges = {
		Version = state.Version,
		DailyKey = state.DailyKey,
		WeeklyKey = state.WeeklyKey,
		DailyBubblePops = state.DailyBubblePops,
		Daily = state.Daily,
		Weekly = state.Weekly,
		TrackedId = state.TrackedId,
		MilestoneNotified = state.MilestoneNotified,
	}
	profile.__dirty = true
end

local function getOrderedStore(dailyKey: string): OrderedDataStore?
	local name = ChallengeConfig.DailyLeaderboardStoreName(dailyKey)
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if ok then
		return storeOrErr
	end
	return nil
end

local function publicLeaderboardPayload(player: Player?, state: ChallengesState): any
	local entries = {}
	local dailyKey = state.DailyKey
	if topCache and topCache.dailyKey == dailyKey then
		entries = topCache.entries
	end
	local myPops = state.DailyBubblePops
	local myRank: number? = nil
	if player then
		for _, e in ipairs(entries) do
			if e.UserId == player.UserId then
				myRank = e.Rank
				break
			end
		end
	end
	return {
		Entries = entries,
		YourPops = myPops,
		YourRank = myRank,
		DailyKey = dailyKey,
	}
end

local function pushState(player: Player, force: boolean?)
	local state = playerStates[player]
	if not state then
		return
	end
	local t = os.clock()
	if not force and lastPushAt[player] and (t - lastPushAt[player]) < ChallengeConfig.ClientStateThrottleSeconds then
		return
	end
	lastPushAt[player] = t
	local featured = ChallengeLogic.FeaturedEventForDay(state.DailyKey)
	local payload = ChallengeLogic.SerializePublicState(
		state,
		nowUnix(),
		publicLeaderboardPayload(player, state),
		featured
	)
	pcall(function()
		Remotes.Event("ChallengeState"):FireClient(player, payload)
	end)
end

local function loadOrCreateState(player: Player): ChallengesState?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local bag = ensureProfileBag(profile)
	local state, changed = ChallengeLogic.ReconcileState(bag, nowUnix(), playerCtx(player))
	if not state.TrackedId or state.TrackedId == "" then
		state.TrackedId = ChallengeLogic.DefaultTrackedId(state)
	end
	playerStates[player] = state
	persistState(player, state)
	if changed then
		for _, ch in ipairs(state.Daily) do
			softGas("OnChallengeAssigned", player, {
				challengeId = ch.Id,
				challengeType = "Daily",
				dailyKey = state.DailyKey,
				target = ch.Target,
			})
		end
		if state.Weekly then
			softGas("OnChallengeAssigned", player, {
				challengeId = state.Weekly.Id,
				challengeType = "Weekly",
				weeklyKey = state.WeeklyKey,
				target = state.Weekly.Target,
			})
		end
	end
	return state
end

local function refreshPeriodForPlayer(player: Player)
	local state = loadOrCreateState(player)
	if state then
		pushState(player, true)
	end
end

local function notifyMilestones(player: Player, state: ChallengesState, challengeId: string, before: number, after: number, target: number)
	local crossed = ChallengeLogic.CrossedMilestones(
		challengeId,
		before,
		after,
		target,
		state.MilestoneNotified
	)
	if #crossed == 0 then
		return
	end
	state.MilestoneNotified = ChallengeLogic.MarkMilestones(
		state.MilestoneNotified or {},
		challengeId,
		crossed
	)
	for _, m in ipairs(crossed) do
		softGas("OnChallengeProgressMilestone", player, {
			challengeId = challengeId,
			progress = after,
			target = target,
			milestone = m,
			dailyKey = state.DailyKey,
		})
		if m >= 1 then
			local ch = ChallengeLogic.FindChallenge(state, challengeId)
			local ctype = if ch and ch.Slot == "Weekly" then "Weekly" else "Daily"
			softGas("OnChallengeCompleted", player, {
				challengeId = challengeId,
				challengeType = ctype,
				dailyKey = state.DailyKey,
				weeklyKey = state.WeeklyKey,
			})
			if ctype == "Weekly" then
				softGas("OnWeeklyChallengeCompleted", player, {
					challengeId = challengeId,
					weeklyKey = state.WeeklyKey,
				})
			end
			pcall(function()
				Remotes.Event("ChallengeNotify"):FireClient(player, {
					kind = "completed",
					challengeId = challengeId,
				})
			end)
		else
			pcall(function()
				Remotes.Event("ChallengeNotify"):FireClient(player, {
					kind = "milestone",
					challengeId = challengeId,
					milestone = m,
				})
			end)
		end
	end
end

local function applyEvents(player: Player, events: { ChallengeLogic.GameplayEvent })
	if not ChallengeConfig.Enabled then
		return
	end
	local state = playerStates[player] or loadOrCreateState(player)
	if not state then
		return
	end
	-- Soft reconcile if day rolled while online
	local dailyKey = ChallengeLogic.DailyKey(nowUnix())
	local weeklyKey = ChallengeLogic.WeeklyKey(nowUnix())
	if state.DailyKey ~= dailyKey or state.WeeklyKey ~= weeklyKey then
		state = loadOrCreateState(player)
		if not state then
			return
		end
	end

	local beforeProgress: { [string]: number } = {}
	for _, ch in ipairs(state.Daily) do
		beforeProgress[ch.Id] = ch.Progress
	end
	if state.Weekly then
		beforeProgress[state.Weekly.Id] = state.Weekly.Progress
	end

	local _, deltas = ChallengeLogic.ApplyProgress(state, events)
	if #deltas == 0 then
		return
	end

	for _, d in ipairs(deltas) do
		local before = beforeProgress[d.challengeId] or 0
		notifyMilestones(player, state, d.challengeId, before, d.progress, d.target)
	end

	persistState(player, state)
	-- Toujours forcer un push dès qu’un défi vient d’être terminé (évite throttle silent).
	local anyCompleted = false
	for _, d in ipairs(deltas) do
		if d.completed == true then
			anyCompleted = true
			break
		end
	end
	pushState(player, anyCompleted)
end

local function scheduleLbFlush(userId: number)
	if lbFlushScheduled[userId] then
		return
	end
	lbFlushScheduled[userId] = true
	task.delay(2, function()
		lbFlushScheduled[userId] = false
		ChallengeService.FlushLeaderboardScore(userId)
	end)
end

function ChallengeService.FlushLeaderboardScore(userId: number)
	local score = pendingLbScores[userId]
	if score == nil then
		return
	end
	local player = playerByUserId[userId]
	local state = player and playerStates[player]
	local dailyKey = if state then state.DailyKey else ChallengeLogic.DailyKey(nowUnix())
	local store = getOrderedStore(dailyKey)
	if not store then
		return
	end
	local last = lastLbWriteAt[userId] or 0
	if os.clock() - last < ChallengeConfig.LeaderboardWriteIntervalSeconds and player then
		scheduleLbFlush(userId)
		return
	end

	local attempts = 0
	local key = tostring(userId)
	while attempts < ChallengeConfig.LeaderboardMaxWriteAttempts do
		attempts += 1
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				return ChallengeLogic.MergeLeaderboardScore(old, score)
			end)
		end)
		if ok then
			lastLbWriteAt[userId] = os.clock()
			softGas("OnDailyLeaderboardScoreUpdated", player, {
				score = score,
				dailyKey = dailyKey,
			})
			return
		end
		task.wait(math.min(8, 2 ^ attempts))
		if attempts == ChallengeConfig.LeaderboardMaxWriteAttempts then
			warn("[ChallengeService] LB write fail:", tostring(err))
		end
	end
end

local function addDailyPop(player: Player, amount: number)
	local state = playerStates[player] or loadOrCreateState(player)
	if not state then
		return
	end
	local dailyKey = ChallengeLogic.DailyKey(nowUnix())
	if state.DailyKey ~= dailyKey then
		state = loadOrCreateState(player)
		if not state then
			return
		end
	end
	local before = state.DailyBubblePops
	state.DailyBubblePops = math.max(0, state.DailyBubblePops + math.max(0, amount))
	pendingLbScores[player.UserId] = state.DailyBubblePops
	persistState(player, state)

	-- Score hebdo (Weekly Best) = pops valides, même métrique que le daily LB.
	pcall(function()
		require(script.Parent.WeeklyBestService).RecordPops(player, amount)
	end)

	-- Top 10 entry detection via cache
	if topCache and topCache.dailyKey == state.DailyKey then
		local tenth = topCache.entries[ChallengeConfig.LeaderboardTopN]
		local wasIn = false
		for _, e in ipairs(topCache.entries) do
			if e.UserId == player.UserId then
				wasIn = true
				break
			end
		end
		local threshold = if tenth then tenth.Pops else 0
		if not wasIn and before <= threshold and state.DailyBubblePops > threshold then
			softGas("OnDailyLeaderboardTop10Entered", player, {
				score = state.DailyBubblePops,
				dailyKey = state.DailyKey,
			})
			pcall(function()
				Remotes.Event("ChallengeNotify"):FireClient(player, { kind = "top10" })
			end)
		end
	end

	scheduleLbFlush(player.UserId)
end

function ChallengeService.RefreshTopCache()
	local dailyKey = ChallengeLogic.DailyKey(nowUnix())
	local store = getOrderedStore(dailyKey)
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, ChallengeConfig.LeaderboardTopN)
	end)
	if not ok or not pages then
		return
	end
	local pageOk, data = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not pageOk or type(data) ~= "table" then
		return
	end
	local entries = {}
	for i, item in ipairs(data) do
		local userId = tonumber(item.key)
		local pops = math.max(0, math.floor(tonumber(item.value) or 0))
		local name = "Player"
		if userId then
			local p = Players:GetPlayerByUserId(userId)
			if p then
				name = p.DisplayName
			else
				local okN, n = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				if okN and type(n) == "string" then
					name = n
				end
			end
		end
		table.insert(entries, {
			Rank = i,
			UserId = userId or 0,
			Name = name,
			Pops = pops,
		})
	end
	topCache = {
		entries = entries,
		dailyKey = dailyKey,
		fetchedAt = os.clock(),
	}
end

function ChallengeService.GetFeaturedEventType(): string
	return ChallengeLogic.FeaturedEventForDay(ChallengeLogic.DailyKey(nowUnix()))
end

function ChallengeService.OnBubblePopped(player: Player, ctx: any)
	if not ChallengeConfig.Enabled or not player then
		return
	end
	if type(ctx) ~= "table" then
		ctx = {}
	end
	local rarityId = if type(ctx.rarityId) == "string" then ctx.rarityId else "Normal"
	local zoneId = if type(ctx.zoneId) == "string" then ctx.zoneId else "ClassicZone"
	-- Types spéciaux = BubbleTypes Rare/Golden/Diamond/Legendary (jamais la couleur).
	local isSpecial = isRealSpecialBubble(rarityId)
	local isGolden = ctx.isGoldenWave == true
	local isColor = ctx.isColorRushMatch == true
	local isSummer = zoneId == "SummerZone"

	local valid = ChallengeLogic.IsValidDailyBubblePop({
		serverAccepted = true,
		isTutorial = ctx.isTutorial == true,
		isGiantHit = false,
		isGiantBody = false,
	})
	if valid then
		addDailyPop(player, 1)
	end

	local featured = ChallengeService.GetFeaturedEventType()
	local events: { ChallengeLogic.GameplayEvent } = {
		{ metric = "PopBubbles", amount = 1 },
	}
	-- Pop Special Bubbles : bulles spéciales de la zone principale uniquement.
	if isSpecial and isMainBubbleZone(zoneId) then
		table.insert(events, { metric = "PopSpecial", amount = 1 })
	end
	if isSummer then
		table.insert(events, { metric = "PopSummer", amount = 1 })
	end
	if isGolden then
		table.insert(events, { metric = "PopGoldenWave", amount = 1 })
	end
	if isColor then
		table.insert(events, { metric = "PopColorRush", amount = 1 })
	end
	local _ = featured
	applyEvents(player, events)
end

function ChallengeService.OnGiantHit(player: Player, hits: number?)
	local amt = math.max(1, math.floor(tonumber(hits) or 1))
	applyEvents(player, { { metric = "GiantHits", amount = amt } })
end

function ChallengeService.OnGiantCompleted(player: Player)
	applyEvents(player, { { metric = "GiantComplete", amount = 1 } })
end

function ChallengeService.OnMiniEventJoined(player: Player, eventType: string)
	local featured = ChallengeService.GetFeaturedEventType()
	applyEvents(player, {
		{ metric = "MiniEventJoin", amount = 1 },
		{
			metric = "FeaturedEventJoin",
			amount = 1,
			eventType = eventType,
			featuredEventType = featured,
		},
	})
	if eventType == featured then
		softGas("OnFeaturedEventParticipated", player, {
			eventType = eventType,
			dailyKey = ChallengeLogic.DailyKey(nowUnix()),
		})
	end
end

function ChallengeService.OnMiniEventCompleted(player: Player, _eventType: string?)
	applyEvents(player, { { metric = "MiniEventComplete", amount = 1 } })
end

function ChallengeService.OnBackpackSold(player: Player, ctx: any)
	if type(ctx) ~= "table" then
		ctx = {}
	end
	local sold = math.max(0, math.floor(tonumber(ctx.sold) or 0))
	local bagValue = math.max(0, math.floor(tonumber(ctx.bagValue) or 0))
	local capacity = math.max(0, math.floor(tonumber(ctx.capacity) or 0))
	local events: { ChallengeLogic.GameplayEvent } = {}
	if bagValue > 0 then
		table.insert(events, { metric = "SellValue", amount = bagValue })
	end
	if capacity > 0 and sold >= capacity then
		table.insert(events, { metric = "SellFullBackpack", amount = 1 })
	end
	if #events > 0 then
		applyEvents(player, events)
	end
end

local function claimReward(player: Player, challengeId: string): (boolean, string)
	if type(challengeId) ~= "string" or challengeId == "" then
		return false, "bad_id"
	end
	local state = playerStates[player] or loadOrCreateState(player)
	if not state then
		return false, "no_state"
	end
	local ch = ChallengeLogic.FindChallenge(state, challengeId)
	if not ch then
		return false, "not_found"
	end
	local okClaim, code = ChallengeLogic.TryClaim(ch)
	if not okClaim then
		return false, code
	end
	if ch.RewardType == "SellBonus" and ch.RewardAmount > 0 then
		local profile = DataService.Get(player)
		if profile then
			profile.PendingSellBonus = math.max(0, math.floor(tonumber(profile.PendingSellBonus) or 0))
				+ ch.RewardAmount
			profile.__dirty = true
			DataService.Push(player)
		end
	end
	persistState(player, state)
	pushState(player, true)
	local ctype = if ch.Slot == "Weekly" then "Weekly" else "Daily"
	softGas("OnChallengeRewardClaimed", player, {
		challengeId = challengeId,
		challengeType = ctype,
		rewardType = ch.RewardType,
		rewardAmount = ch.RewardAmount,
		dailyKey = state.DailyKey,
		weeklyKey = state.WeeklyKey,
	})
	pcall(function()
		Remotes.Event("ChallengeNotify"):FireClient(player, {
			kind = "claimed",
			challengeId = challengeId,
			rewardAmount = ch.RewardAmount,
		})
	end)
	return true, "ok"
end

function ChallengeService.Start()
	if started then
		return
	end
	started = true
	if not ChallengeConfig.Enabled then
		return
	end

	Remotes.Event("ChallengeRequestState").OnServerEvent:Connect(function(player: Player)
		refreshPeriodForPlayer(player)
	end)

	Remotes.Event("ChallengeClaim").OnServerEvent:Connect(function(player: Player, challengeId: any)
		if type(challengeId) ~= "string" then
			return
		end
		claimReward(player, challengeId)
	end)

	Remotes.Event("ChallengeTrack").OnServerEvent:Connect(function(player: Player, challengeId: any)
		if type(challengeId) ~= "string" then
			return
		end
		local state = playerStates[player] or loadOrCreateState(player)
		if not state then
			return
		end
		if ChallengeLogic.FindChallenge(state, challengeId) then
			state.TrackedId = challengeId
			persistState(player, state)
			pushState(player, true)
			softGas("OnChallengePinned", player, {
				challengeId = challengeId,
				dailyKey = state.DailyKey,
			})
		end
	end)

	Remotes.Event("ChallengePanelOpened").OnServerEvent:Connect(function(player: Player)
		softGas("OnChallengesPanelOpened", player, {
			dailyKey = ChallengeLogic.DailyKey(nowUnix()),
		})
	end)

	local function onPlayerReady(player: Player)
		playerByUserId[player.UserId] = player
		task.defer(function()
			-- Attendre profil DataService
			for _ = 1, 50 do
				if DataService.Get(player) then
					break
				end
				task.wait(0.1)
			end
			if not player.Parent then
				return
			end
			refreshPeriodForPlayer(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerReady)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerReady(p)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		ChallengeService.FlushLeaderboardScore(player.UserId)
		playerStates[player] = nil
		lastPushAt[player] = nil
		playerByUserId[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			ChallengeService.FlushLeaderboardScore(p.UserId)
		end
	end)

	-- Flush périodique scores LB en mémoire
	task.spawn(function()
		while started do
			task.wait(ChallengeConfig.LeaderboardWriteIntervalSeconds)
			for userId, _ in pairs(pendingLbScores) do
				ChallengeService.FlushLeaderboardScore(userId)
			end
		end
	end)

	-- Refresh top 10
	lbRefreshToken += 1
	local refreshTok = lbRefreshToken
	task.spawn(function()
		while started and refreshTok == lbRefreshToken do
			ChallengeService.RefreshTopCache()
			-- re-push leaderboard snippet to online players
			for p, st in pairs(playerStates) do
				if p.Parent then
					pushState(p, false)
				end
			end
			task.wait(ChallengeConfig.LeaderboardRefreshIntervalSeconds)
		end
	end)

	-- Watch period rollover for online players
	periodLoopToken += 1
	local periodTok = periodLoopToken
	task.spawn(function()
		while started and periodTok == periodLoopToken do
			task.wait(15)
			local dk = ChallengeLogic.DailyKey(nowUnix())
			local wk = ChallengeLogic.WeeklyKey(nowUnix())
			for p, st in pairs(playerStates) do
				if p.Parent and (st.DailyKey ~= dk or st.WeeklyKey ~= wk) then
					refreshPeriodForPlayer(p)
				end
			end
		end
	end)

	if RunService:IsStudio() then
		_G.ChallengesShowState = function(player: Player?)
			local p = player or Players:GetPlayers()[1]
			if not p then
				print("[Challenges] no player")
				return
			end
			local st = playerStates[p] or loadOrCreateState(p)
			print("[Challenges] state for", p.Name, st and st.DailyKey, st and st.WeeklyKey)
			if st then
				for i, ch in ipairs(st.Daily) do
					print(
						("  Daily[%d] %s %d/%d completed=%s claimed=%s"):format(
							i,
							ch.Id,
							ch.Progress,
							ch.Target,
							tostring(ch.Completed),
							tostring(ch.Claimed)
						)
					)
				end
				if st.Weekly then
					print(
						("  Weekly %s %d/%d"):format(st.Weekly.Id, st.Weekly.Progress, st.Weekly.Target)
					)
				end
				print("  DailyBubblePops", st.DailyBubblePops)
				print("  Featured", ChallengeService.GetFeaturedEventType())
			end
		end

		_G.ChallengesForceDailyReset = function(player: Player?)
			local p = player or Players:GetPlayers()[1]
			if not p or not playerStates[p] then
				refreshPeriodForPlayer(p :: Player)
			end
			local st = playerStates[p :: Player]
			if st then
				st.DailyKey = ""
				persistState(p :: Player, st)
				refreshPeriodForPlayer(p :: Player)
			end
		end

		_G.ChallengesForceWeeklyReset = function(player: Player?)
			local p = player or Players:GetPlayers()[1]
			if not p then
				return
			end
			local st = playerStates[p] or loadOrCreateState(p)
			if st then
				st.WeeklyKey = ""
				persistState(p, st)
				refreshPeriodForPlayer(p)
			end
		end

		_G.ChallengesSetProgress = function(challengeId: string, progress: number, player: Player?)
			local p = player or Players:GetPlayers()[1]
			if not p then
				return
			end
			local st = playerStates[p] or loadOrCreateState(p)
			if not st then
				return
			end
			local ch = ChallengeLogic.FindChallenge(st, challengeId)
			if not ch then
				print("[Challenges] not found", challengeId)
				return
			end
			ch.Progress = math.clamp(math.floor(progress), 0, ch.Target)
			ch.Completed = ch.Progress >= ch.Target
			persistState(p, st)
			pushState(p, true)
		end

		_G.ChallengesComplete = function(challengeId: string, player: Player?)
			local p = player or Players:GetPlayers()[1]
			if not p then
				return
			end
			local st = playerStates[p] or loadOrCreateState(p)
			if not st then
				return
			end
			local ch = ChallengeLogic.FindChallenge(st, challengeId)
			if ch then
				ch.Progress = ch.Target
				ch.Completed = true
				persistState(p, st)
				pushState(p, true)
			end
		end

		_G.ChallengesClearCurrentPeriod = function(player: Player?)
			local p = player or Players:GetPlayers()[1]
			if not p then
				return
			end
			playerStates[p] = nil
			local profile = DataService.Get(p)
			if profile then
				profile.Challenges = {}
			end
			refreshPeriodForPlayer(p)
		end

		_G.ChallengesRefreshLeaderboard = function()
			ChallengeService.RefreshTopCache()
			for p, _ in pairs(playerStates) do
				pushState(p, true)
			end
		end

		_G.ChallengesSetLowTargets = function(enabled: boolean)
			ChallengeConfig.Studio.ForceLowTargets = enabled == true
		end

		print("[ChallengeService] Studio commands: ChallengesShowState, ChallengesForceDailyReset, ChallengesForceWeeklyReset, ChallengesSetProgress, ChallengesComplete, ChallengesClearCurrentPeriod, ChallengesRefreshLeaderboard, ChallengesSetLowTargets")
	end

	print("[ChallengeService] démarré. Featured:", ChallengeService.GetFeaturedEventType())
end

return ChallengeService
