--!strict
-- Service central analytics phase 1 : sessions en mémoire, envoi via sink injectable.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnalyticsConfig = require(Shared.AnalyticsConfig)
local ZoneDefs = require(Shared.ZoneDefs)

export type CoinEconomyContext = {
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string,
}

export type SessionTotals = {
	normalPops: number,
	specialPops: number,
	popsGameRoom: number,
	popsSummerZone: number,
	toolUses: number,
	salesCount: number,
	coinsFromSales: number,
	zoneSeconds: { Lobby: number, GameRoom: number, SummerZone: number },
	zoneChanges: number,
}

export type PlayerSession = {
	sessionId: string,
	joinClock: number,
	isInitialProfileSession: boolean,
	onboardingActive: boolean,
	onboardingObserved: { [string]: boolean },
	summerObserved: { [string]: boolean },
	summerFunnelVersionFieldSent: boolean,
	profile: any,
	sessionTotals: SessionTotals,
	lastFlushedTotals: SessionTotals,
	currentArea: string?,
	areaEnteredAt: number?,
	sessionFirstBubbleSent: boolean,
	sessionFirstSaleSent: boolean,
	lastProgressionLevelReported: number?,
	-- Gates SecondsToFirst* (session initiale) : jamais renvoyés deux fois
	firstTimingSent: { [string]: boolean },
}

export type AnalyticsSink = {
	logOnboarding: (player: Player, step: number, stepName: string, fields: any?) -> (),
	logFunnel: (player: Player, funnelName: string, sessionId: string, step: number, stepName: string, fields: any?) -> (),
	logCustom: (player: Player, name: string, value: number?, fields: any?) -> (),
	logEconomy: (
		player: Player,
		flowType: any,
		currencyType: string,
		amount: number,
		endingBalance: number,
		transactionType: string,
		itemSku: string?,
		fields: any?
	) -> (),
	logProgressionComplete: (player: Player, path: string, level: number, levelName: string, fields: any?) -> (),
}

local GameAnalyticsService = {}

local sessions: { [Player]: PlayerSession } = {}
local sink: AnalyticsSink? = nil
local warnHandler: (...any) -> () = warn
local started = false
local flushLoopStarted = false
local flushLoopSpawnCount = 0
local flushIntervalOverride: number? = nil

local ANALYTICS_TEMPLATE = {
	OnboardingVersion = 1,
	SummerZoneVersion = 1,
	SummerZoneFunnelSessionId = "",
	OnboardingStarted = false,
	OnboardingCompleted = false,
	Onboarding = {},
	SummerZone = {},
	BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 },
	LastProgressionLevel = 0,
	Lifetime = { FirstSpecialBubble = false },
}

local function deepCopyTable(src: any): any
	if type(src) ~= "table" then
		return src
	end
	local out = {}
	for k, v in pairs(src) do
		out[k] = deepCopyTable(v)
	end
	return out
end

local function ensureAnalytics(profile: any)
	if type(profile) ~= "table" then
		return
	end
	if type(profile.Analytics) ~= "table" then
		profile.Analytics = deepCopyTable(ANALYTICS_TEMPLATE)
		return
	end
	local analytics = profile.Analytics
	for key, templateValue in pairs(ANALYTICS_TEMPLATE) do
		if analytics[key] == nil then
			analytics[key] = if type(templateValue) == "table" then deepCopyTable(templateValue) else templateValue
		elseif type(templateValue) == "table" and type(analytics[key]) == "table" then
			if key == "Onboarding" or key == "SummerZone" then
				continue
			end
			for nestedKey, nestedValue in pairs(templateValue) do
				if analytics[key][nestedKey] == nil then
					analytics[key][nestedKey] = nestedValue
				end
			end
		end
	end
	if type(analytics.Onboarding) ~= "table" then
		analytics.Onboarding = {}
	end
	if type(analytics.SummerZone) ~= "table" then
		analytics.SummerZone = {}
	end
end

local function emptyZoneSeconds(): { Lobby: number, GameRoom: number, SummerZone: number }
	return { Lobby = 0, GameRoom = 0, SummerZone = 0 }
end

local function createEmptyTotals(): SessionTotals
	return {
		normalPops = 0,
		specialPops = 0,
		popsGameRoom = 0,
		popsSummerZone = 0,
		toolUses = 0,
		salesCount = 0,
		coinsFromSales = 0,
		zoneSeconds = emptyZoneSeconds(),
		zoneChanges = 0,
	}
end

local function copyTotals(src: SessionTotals): SessionTotals
	return {
		normalPops = src.normalPops,
		specialPops = src.specialPops,
		popsGameRoom = src.popsGameRoom,
		popsSummerZone = src.popsSummerZone,
		toolUses = src.toolUses,
		salesCount = src.salesCount,
		coinsFromSales = src.coinsFromSales,
		zoneSeconds = {
			Lobby = src.zoneSeconds.Lobby,
			GameRoom = src.zoneSeconds.GameRoom,
			SummerZone = src.zoneSeconds.SummerZone,
		},
		zoneChanges = src.zoneChanges,
	}
end

local ZONE_SECONDS_EVENT_NAMES = {
	Lobby = "SessionZoneSecondsLobby",
	GameRoom = "SessionZoneSecondsGameRoom",
	SummerZone = "SessionZoneSecondsSummerZone",
}

local function mapAreaToTracked(area: string?): string?
	if area == "Lobby" or area == "GameRoom" or area == "SummerZone" then
		return area
	end
	if area == nil then
		return nil
	end
	return "Lobby"
end

local function accumulateZoneTime(session: PlayerSession)
	local area = session.currentArea
	local enteredAt = session.areaEnteredAt
	if not area or not enteredAt then
		return
	end
	local tracked = mapAreaToTracked(area)
	if not tracked then
		return
	end
	local elapsed = math.max(0, os.clock() - enteredAt)
	session.sessionTotals.zoneSeconds[tracked] += elapsed
	session.areaEnteredAt = os.clock()
end

local function createDefaultSink(): AnalyticsSink
	local AnalyticsService = game:GetService("AnalyticsService")
	return {
		logOnboarding = function(player, step, stepName, fields)
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, fields)
		end,
		logFunnel = function(player, funnelName, sessionId, step, stepName, fields)
			AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName, fields)
		end,
		logCustom = function(player, name, value, fields)
			AnalyticsService:LogCustomEvent(player, name, value, fields)
		end,
		logEconomy = function(player, flowType, currencyType, amount, endingBalance, transactionType, itemSku, fields)
			AnalyticsService:LogEconomyEvent(
				player,
				flowType,
				currencyType,
				amount,
				endingBalance,
				transactionType,
				itemSku,
				fields
			)
		end,
		logProgressionComplete = function(player, path, level, levelName, fields)
			AnalyticsService:LogProgressionCompleteEvent(player, path, level, levelName, fields)
		end,
	}
end

-- Sink lazy : InitPlayer peut tourner avant Start() (ordre de démarrage serveur).
local function getSink(): AnalyticsSink
	if not sink then
		sink = createDefaultSink()
	end
	return sink
end

local function invokeSink(methodName: string, fn: () -> ()): boolean
	local ok, err = pcall(fn)
	if not ok then
		if AnalyticsConfig.DebugEnabled then
			warn("[GameAnalytics] sink error:", methodName, err)
		end
	elseif AnalyticsConfig.DebugEnabled then
		print("[GameAnalytics] sink ok:", methodName)
	end
	return ok
end

local function _logOnboarding(player: Player, step: number, stepName: string, fields: any?): boolean
	return invokeSink("logOnboarding", function()
		getSink().logOnboarding(player, step, stepName, fields)
	end)
end

local function _logFunnel(
	player: Player,
	funnelName: string,
	sessionId: string,
	step: number,
	stepName: string,
	fields: any?
): boolean
	return invokeSink("logFunnel", function()
		getSink().logFunnel(player, funnelName, sessionId, step, stepName, fields)
	end)
end

local function _logCustom(player: Player, name: string, value: number?, fields: any?): boolean
	return invokeSink("logCustom", function()
		getSink().logCustom(player, name, value, fields)
	end)
end

local function flushScalarDelta(
	player: Player,
	eventName: string,
	total: number,
	lastValue: number,
	onSuccess: (newLast: number) -> ()
)
	local delta = total - lastValue
	if delta <= 0 then
		return
	end
	local emitValue = math.floor(delta)
	if emitValue <= 0 then
		return
	end
	if _logCustom(player, eventName, emitValue, nil) then
		onSuccess(total)
	end
end

local function flushDeltas(player: Player)
	local session = sessions[player]
	if not session then
		return
	end

	accumulateZoneTime(session)

	local totals = session.sessionTotals
	local last = session.lastFlushedTotals

	flushScalarDelta(player, "SessionNormalPops", totals.normalPops, last.normalPops, function(v)
		last.normalPops = v
	end)
	flushScalarDelta(player, "SessionSpecialPops", totals.specialPops, last.specialPops, function(v)
		last.specialPops = v
	end)
	flushScalarDelta(player, "SessionPopsGameRoom", totals.popsGameRoom, last.popsGameRoom, function(v)
		last.popsGameRoom = v
	end)
	flushScalarDelta(player, "SessionPopsSummerZone", totals.popsSummerZone, last.popsSummerZone, function(v)
		last.popsSummerZone = v
	end)
	flushScalarDelta(player, "SessionToolUses", totals.toolUses, last.toolUses, function(v)
		last.toolUses = v
	end)
	flushScalarDelta(player, "SessionSalesCount", totals.salesCount, last.salesCount, function(v)
		last.salesCount = v
	end)
	flushScalarDelta(player, "SessionCoinsFromSales", totals.coinsFromSales, last.coinsFromSales, function(v)
		last.coinsFromSales = v
	end)
	flushScalarDelta(player, "SessionZoneChanges", totals.zoneChanges, last.zoneChanges, function(v)
		last.zoneChanges = v
	end)

	for zoneKey, eventName in pairs(ZONE_SECONDS_EVENT_NAMES) do
		local totalSeconds = totals.zoneSeconds[zoneKey]
		local lastSeconds = last.zoneSeconds[zoneKey]
		local delta = totalSeconds - lastSeconds
		if delta > 0 then
			local emitValue = math.floor(delta)
			if emitValue > 0 and _logCustom(player, eventName, emitValue, nil) then
				last.zoneSeconds[zoneKey] = totalSeconds
			end
		end
	end
end

local function startFlushLoop()
	if flushLoopStarted then
		return
	end
	flushLoopStarted = true
	flushLoopSpawnCount += 1
	task.spawn(function()
		while flushLoopStarted do
			local interval = flushIntervalOverride or AnalyticsConfig.FlushIntervalSeconds
			task.wait(interval)
			if not flushLoopStarted then
				break
			end
			for trackedPlayer in pairs(sessions) do
				pcall(flushDeltas, trackedPlayer)
			end
		end
	end)
end

local function _logEconomy(
	player: Player,
	flowType: any,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
	fields: any?
): boolean
	return invokeSink("logEconomy", function()
		getSink().logEconomy(
			player,
			flowType,
			currencyType,
			amount,
			endingBalance,
			transactionType,
			itemSku,
			fields
		)
	end)
end

local function _logProgressionComplete(
	player: Player,
	path: string,
	level: number,
	levelName: string,
	fields: any?
): boolean
	return invokeSink("logProgressionComplete", function()
		getSink().logProgressionComplete(player, path, level, levelName, fields)
	end)
end

local function getEconomyFlowType(flowName: "Source" | "Sink"): string
	return flowName
end

local function getGameplayTransactionType(): string
	return "Gameplay"
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function warnEconomyDrop(player: Player, apiName: string, reason: string)
	warnHandler("[GameAnalytics] economy drop:", player.Name, apiName, reason)
end

local function validateCoinEconomyContext(player: Player, ctx: CoinEconomyContext, apiName: string): boolean
	if not sessions[player] then
		GameAnalyticsService.WarnNoSession(player, apiName)
		return false
	end
	if type(ctx) ~= "table" then
		warnEconomyDrop(player, apiName, "invalid ctx")
		return false
	end
	if not isFiniteNumber(ctx.amount) then
		warnEconomyDrop(player, apiName, "invalid amount")
		return false
	end
	local amount = math.floor(ctx.amount)
	if amount <= 0 then
		warnEconomyDrop(player, apiName, "amount <= 0")
		return false
	end
	if not isFiniteNumber(ctx.endingBalance) then
		warnEconomyDrop(player, apiName, "invalid endingBalance")
		return false
	end
	if ctx.endingBalance < 0 then
		warnEconomyDrop(player, apiName, "negative endingBalance")
		return false
	end
	if type(ctx.transactionType) ~= "string" or ctx.transactionType == "" then
		warnEconomyDrop(player, apiName, "invalid transactionType")
		return false
	end
	if type(ctx.itemSku) ~= "string" or ctx.itemSku == "" then
		warnEconomyDrop(player, apiName, "invalid itemSku")
		return false
	end
	if not AnalyticsConfig.IsEconomySkuAllowed(ctx.itemSku) then
		warnEconomyDrop(player, apiName, "sku not allowed")
		return false
	end
	return true
end

local function secondsSinceJoin(session: PlayerSession): number
	return math.max(0, math.floor(os.clock() - session.joinClock))
end

-- SecondsToFirst* : best-effort après succès funnel ; gate pour ne jamais renvoyer.
local function tryFirstTiming(player: Player, session: PlayerSession, stepName: string)
	if not session.isInitialProfileSession then
		return
	end
	local timingName = AnalyticsConfig.FirstTimingByStep[stepName]
	if not timingName or session.firstTimingSent[timingName] == true then
		return
	end
	if _logCustom(player, timingName, secondsSinceJoin(session), nil) then
		session.firstTimingSent[timingName] = true
	end
end

-- SessionSecondsTo* : best-effort ; n'interrompt jamais le drain / le marquage funnel.
local function trySessionSeconds(player: Player, session: PlayerSession, stepName: string)
	if stepName == "PoppedFirstBubble" and not session.sessionFirstBubbleSent then
		if _logCustom(player, "SessionSecondsToFirstBubble", secondsSinceJoin(session), nil) then
			session.sessionFirstBubbleSent = true
		end
	elseif stepName == "SoldFirstBackpack" and not session.sessionFirstSaleSent then
		if _logCustom(player, "SessionSecondsToFirstSale", secondsSinceJoin(session), nil) then
			session.sessionFirstSaleSent = true
		end
	end
end

local function drainOnboarding(player: Player)
	local session = sessions[player]
	if not session or not session.onboardingActive then
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then
		return
	end
	local onboarding = profile.Analytics.Onboarding
	if type(onboarding) ~= "table" then
		profile.Analytics.Onboarding = {}
		onboarding = profile.Analytics.Onboarding
	end

	for _, step in ipairs(AnalyticsConfig.OnboardingSteps) do
		local name = step.name
		if onboarding[name] == true then
			-- Étape déjà validée : retenter seulement les timings non encore gated.
			tryFirstTiming(player, session, name)
			trySessionSeconds(player, session, name)
			continue
		end
		if not session.onboardingObserved[name] then
			return
		end

		local ok = _logOnboarding(player, step.step, name, nil)
		if not ok then
			-- Funnel échoué : rien marquer, aucun timing lié.
			return
		end

		-- Succès funnel → marquage immédiat (indépendant des timings).
		onboarding[name] = true
		profile.__dirty = true
		if name == "PurchasedFirstUpgrade" then
			profile.Analytics.OnboardingCompleted = true
			session.onboardingActive = false
			profile.__dirty = true
		end

		tryFirstTiming(player, session, name)
		trySessionSeconds(player, session, name)

		if not session.onboardingActive then
			return
		end
	end
end

local function drainSummer(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then
		return
	end
	local analytics = profile.Analytics
	local summerZone = analytics.SummerZone
	if type(summerZone) ~= "table" then
		analytics.SummerZone = {}
		summerZone = analytics.SummerZone
	end
	local funnelSessionId = analytics.SummerZoneFunnelSessionId
	if type(funnelSessionId) ~= "string" or funnelSessionId == "" then
		return
	end

	for _, step in ipairs(AnalyticsConfig.SummerSteps) do
		local name = step.name
		if summerZone[name] == true then
			continue
		end
		if not session.summerObserved[name] then
			return
		end
		local fields: any? = nil
		if not session.summerFunnelVersionFieldSent then
			local version = tonumber(analytics.SummerZoneVersion) or AnalyticsConfig.SummerZoneAnalyticsVersion
			fields = AnalyticsConfig.VersionCustomField(version)
		end
		local ok = _logFunnel(
			player,
			AnalyticsConfig.FunnelSummer,
			funnelSessionId,
			step.step,
			name,
			fields
		)
		if not ok then
			return
		end
		session.summerFunnelVersionFieldSent = true
		summerZone[name] = true
		profile.__dirty = true
	end
end

function GameAnalyticsService.SetSink(nextSink: AnalyticsSink?)
	sink = nextSink
end

function GameAnalyticsService.SetWarnHandler(handler: ((...any) -> ())?)
	warnHandler = handler or warn
end

function GameAnalyticsService.Start()
	if started then
		return
	end
	started = true
	if not sink then
		sink = createDefaultSink()
	end
	startFlushLoop()
end

local function reduceBagExcess(bag: any, excess: number)
	local unk = math.max(0, math.floor(tonumber(bag.Unknown) or 0))
	local sz = math.max(0, math.floor(tonumber(bag.SummerZone) or 0))
	local gr = math.max(0, math.floor(tonumber(bag.GameRoom) or 0))
	local take = math.min(unk, excess)
	unk -= take
	excess -= take
	take = math.min(sz, excess)
	sz -= take
	excess -= take
	take = math.min(gr, excess)
	gr -= take
	bag.Unknown = unk
	bag.SummerZone = sz
	bag.GameRoom = gr
end

-- Après stabilisation : sum(BagValueByZone) == PendingSellValue (Case A : sac conservé).
function GameAnalyticsService.EnsureBagValueCoverage(profile: any)
	if type(profile) ~= "table" then
		return
	end
	if type(profile.Analytics) ~= "table" then
		return
	end
	local bag = profile.Analytics.BagValueByZone
	if type(bag) ~= "table" then
		profile.Analytics.BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 }
		bag = profile.Analytics.BagValueByZone
	end
	bag.GameRoom = math.max(0, math.floor(tonumber(bag.GameRoom) or 0))
	bag.SummerZone = math.max(0, math.floor(tonumber(bag.SummerZone) or 0))
	bag.Unknown = math.max(0, math.floor(tonumber(bag.Unknown) or 0))
	local pending = math.max(0, math.floor(tonumber(profile.PendingSellValue) or 0))
	local sum = bag.GameRoom + bag.SummerZone + bag.Unknown
	if pending <= 0 then
		if sum > 0 then
			bag.GameRoom = 0
			bag.SummerZone = 0
			bag.Unknown = 0
			profile.__dirty = true
		end
		return
	end
	if pending > sum then
		bag.Unknown += pending - sum
		profile.__dirty = true
	elseif sum > pending then
		reduceBagExcess(bag, sum - pending)
		profile.__dirty = true
	end
end

function GameAnalyticsService.SumBagValueByZone(profile: any): number
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then
		return 0
	end
	local bag = profile.Analytics.BagValueByZone
	if type(bag) ~= "table" then
		return 0
	end
	return math.max(0, math.floor(tonumber(bag.GameRoom) or 0))
		+ math.max(0, math.floor(tonumber(bag.SummerZone) or 0))
		+ math.max(0, math.floor(tonumber(bag.Unknown) or 0))
end

function GameAnalyticsService.RebindProfile(player: Player, profile: any)
	local session = sessions[player]
	if not session or type(profile) ~= "table" then
		return
	end
	session.profile = profile
end

function GameAnalyticsService.RecordPop(
	player: Player,
	info: { zoneId: string?, isSpecial: boolean? }?
)
	local session = sessions[player]
	if not session then
		return
	end
	local totals = session.sessionTotals
	if info and info.isSpecial == true then
		totals.specialPops += 1
	else
		totals.normalPops += 1
	end
	local zoneId = info and info.zoneId
	if zoneId == "GameRoom" then
		totals.popsGameRoom += 1
	elseif zoneId == "SummerZone" then
		totals.popsSummerZone += 1
	end
end

function GameAnalyticsService.RecordToolUse(player: Player, _toolId: string?)
	local session = sessions[player]
	if not session then
		return
	end
	session.sessionTotals.toolUses += 1
end

function GameAnalyticsService.RecordZoneChange(player: Player, newArea: string)
	local session = sessions[player]
	if not session then
		return
	end

	accumulateZoneTime(session)

	local trackedNew = mapAreaToTracked(newArea)
	if not trackedNew then
		return
	end

	local trackedCurrent = mapAreaToTracked(session.currentArea)
	if trackedCurrent ~= trackedNew then
		session.sessionTotals.zoneChanges += 1
	end

	session.currentArea = trackedNew
	session.areaEnteredAt = os.clock()
end

function GameAnalyticsService.RecordSale(player: Player, coinsEarned: number?)
	local session = sessions[player]
	if not session then
		return
	end
	session.sessionTotals.salesCount += 1
	local coins = math.max(0, math.floor(tonumber(coinsEarned) or 0))
	session.sessionTotals.coinsFromSales += coins
end

function GameAnalyticsService.ObserveOnboarding(player: Player, stepName: string)
	local session = sessions[player]
	if not session then
		GameAnalyticsService.WarnNoSession(player, "ObserveOnboarding:" .. stepName)
		return
	end
	if not session.onboardingActive then
		return
	end
	session.onboardingObserved[stepName] = true
	drainOnboarding(player)
end

function GameAnalyticsService.ObserveSummer(player: Player, stepName: string)
	local session = sessions[player]
	if not session then
		GameAnalyticsService.WarnNoSession(player, "ObserveSummer:" .. stepName)
		return
	end
	session.summerObserved[stepName] = true
	drainSummer(player)
end

function GameAnalyticsService.OnSummerRequiredLevelReached(player: Player)
	GameAnalyticsService.ObserveSummer(player, "ReachedRequiredLevel")
end

function GameAnalyticsService.OnReachedMainBubbleRoom(player: Player, zoneId: string?)
	if zoneId == "GameRoom" then
		GameAnalyticsService.ObserveOnboarding(player, "ReachedMainBubbleRoom")
	end
end

function GameAnalyticsService.OnBubblePopped(
	player: Player,
	ctx: { zoneId: string?, rarityId: string?, isSpecial: boolean? }?
)
	GameAnalyticsService.ObserveOnboarding(player, "PoppedFirstBubble")

	if ctx and ctx.zoneId == "SummerZone" then
		GameAnalyticsService.OnSummerBubblePopped(player)
	end

	local session = sessions[player]
	if session then
		GameAnalyticsService.RecordPop(player, ctx)
	end
	if not session then
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then
		return
	end
	if not ctx or ctx.isSpecial ~= true then
		return
	end
	local lifetime = profile.Analytics.Lifetime
	if type(lifetime) ~= "table" or lifetime.FirstSpecialBubble == true then
		return
	end
	if _logCustom(player, "FirstSpecialBubble", 1, nil) then
		lifetime.FirstSpecialBubble = true
		profile.__dirty = true
	end
end

function GameAnalyticsService.OnBackpackBecameFull(player: Player, _ctx: { zoneId: string? }?)
	GameAnalyticsService.ObserveOnboarding(player, "BackpackFullFirstTime")
end

function GameAnalyticsService.OnReturnedToLobby(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then
		return
	end
	local onboarding = profile.Analytics.Onboarding
	if session.onboardingObserved.BackpackFullFirstTime or (type(onboarding) == "table" and onboarding.BackpackFullFirstTime == true) then
		GameAnalyticsService.ObserveOnboarding(player, "ReturnedToLobbyAfterFullBackpack")
	end
end

function GameAnalyticsService.OnBubblesAddedToBag(
	player: Player,
	ctx: {
		storageAdded: number?,
		sellValueAdded: number?,
		zoneId: string?,
		becameFull: boolean?,
		wasBelowCapacity: boolean?,
	}?
)
	local session = sessions[player]
	if not session then
		GameAnalyticsService.WarnNoSession(player, "OnBubblesAddedToBag")
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" then
		return
	end
	if type(ctx) ~= "table" then
		return
	end
	local sellValueAdded = math.floor(tonumber(ctx.sellValueAdded) or 0)
	if sellValueAdded <= 0 then
		return
	end

	ensureAnalytics(profile)
	local bag = profile.Analytics.BagValueByZone
	if type(bag) ~= "table" then
		profile.Analytics.BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 }
		bag = profile.Analytics.BagValueByZone
	end

	-- AddBubbles a déjà augmenté PendingSellValue : synchroniser sur l'état AVANT cet ajout
	-- (pending - sellValueAdded), puis créditer la portion zone. Évite double-comptage Unknown.
	local pending = math.max(0, math.floor(tonumber(profile.PendingSellValue) or 0))
	local priorPending = math.max(0, pending - sellValueAdded)
	bag.GameRoom = math.max(0, math.floor(tonumber(bag.GameRoom) or 0))
	bag.SummerZone = math.max(0, math.floor(tonumber(bag.SummerZone) or 0))
	bag.Unknown = math.max(0, math.floor(tonumber(bag.Unknown) or 0))
	local sum = bag.GameRoom + bag.SummerZone + bag.Unknown
	if priorPending <= 0 then
		if sum > 0 then
			bag.GameRoom = 0
			bag.SummerZone = 0
			bag.Unknown = 0
		end
	elseif priorPending > sum then
		bag.Unknown += priorPending - sum
	elseif sum > priorPending then
		reduceBagExcess(bag, sum - priorPending)
	end

	local zoneId = ctx.zoneId
	local key = "Unknown"
	if zoneId == "GameRoom" or zoneId == "SummerZone" then
		key = zoneId
	end
	bag[key] = math.max(0, math.floor(tonumber(bag[key]) or 0)) + sellValueAdded
	profile.__dirty = true

	if ctx.becameFull == true and ctx.wasBelowCapacity == true then
		GameAnalyticsService.ObserveOnboarding(player, "BackpackFullFirstTime")
		if zoneId == "SummerZone" then
			GameAnalyticsService.OnSummerBackpackFilled(player)
		end
	end
end

function GameAnalyticsService.OnBackpackSold(
	player: Player,
	ctx: { sold: number?, earned: number?, endingBalance: number? }?
)
	local session = sessions[player]
	if not session then
		GameAnalyticsService.WarnNoSession(player, "OnBackpackSold")
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" then
		return
	end
	if type(ctx) ~= "table" then
		return
	end
	local earned = math.floor(tonumber(ctx.earned) or 0)
	local endingBalance = ctx.endingBalance
	if earned <= 0 or not isFiniteNumber(endingBalance) or (endingBalance :: number) < 0 then
		return
	end

	ensureAnalytics(profile)
	GameAnalyticsService.LogBackpackSaleEconomy(player, profile, {
		earned = earned,
		endingBalance = endingBalance,
	})
	GameAnalyticsService.ObserveOnboarding(player, "SoldFirstBackpack")
	GameAnalyticsService.OnBackpackSoldAnalytics(player, {
		sold = ctx.sold,
		earned = earned,
		coinsEarned = earned,
		endingBalance = endingBalance,
	})
end

function GameAnalyticsService.OnUpgradePurchased(player: Player, ctx: any?)
	if type(ctx) ~= "table" then
		warnEconomyDrop(player, "OnUpgradePurchased", "invalid ctx")
		return
	end
	local upgradeId = ctx.upgradeId
	if type(upgradeId) ~= "string" or upgradeId == "" then
		warnEconomyDrop(player, "OnUpgradePurchased", "invalid upgradeId")
		return
	end

	-- SKU = id upgrade brut (GameConfig / BuildEconomySkuSet), pas Upgrade_<id>.
	if not AnalyticsConfig.IsEconomySkuAllowed(upgradeId) then
		warnEconomyDrop(player, "OnUpgradePurchased", "sku not allowed")
		return
	end

	-- Achat shop déjà réussi + id config valide → onboarding même si le sink échoue ensuite.
	GameAnalyticsService.ObserveOnboarding(player, "PurchasedFirstUpgrade")

	GameAnalyticsService.LogCoinSink(player, {
		amount = ctx.amount,
		endingBalance = ctx.endingBalance,
		transactionType = "Shop",
		itemSku = upgradeId,
	})
end

function GameAnalyticsService.LogCoinSource(player: Player, ctx: CoinEconomyContext): boolean
	if not validateCoinEconomyContext(player, ctx, "LogCoinSource") then
		return false
	end
	local amount = math.floor(ctx.amount)
	return _logEconomy(
		player,
		getEconomyFlowType("Source"),
		AnalyticsConfig.CurrencyType,
		amount,
		ctx.endingBalance,
		ctx.transactionType,
		ctx.itemSku,
		nil
	)
end

function GameAnalyticsService.LogCoinSink(player: Player, ctx: CoinEconomyContext): boolean
	if not validateCoinEconomyContext(player, ctx, "LogCoinSink") then
		return false
	end
	local amount = math.floor(ctx.amount)
	return _logEconomy(
		player,
		getEconomyFlowType("Sink"),
		AnalyticsConfig.CurrencyType,
		amount,
		ctx.endingBalance,
		ctx.transactionType,
		ctx.itemSku,
		nil
	)
end

-- Économie vente sac uniquement. Après vente réussie, appeler aussi
-- OnBackpackSold (onboarding) et OnBackpackSoldAnalytics (session + summer).
-- ctx optionnel : { earned, endingBalance } — si earned fourni, réconcilie les portions.
function GameAnalyticsService.LogBackpackSaleEconomy(player: Player, profile: any, ctx: any?)
	if type(profile) ~= "table" then
		return
	end
	ensureAnalytics(profile)
	local bag = profile.Analytics.BagValueByZone
	if type(bag) ~= "table" then
		return
	end

	-- Ne pas appeler EnsureBagValueCoverage ici : doSell met PendingSellValue à 0 avant
	-- OnBackpackSold ; la couverture viderait les portions avant l'économie.
	if type(ctx) ~= "table" or not isFiniteNumber(ctx.earned) then
		GameAnalyticsService.EnsureBagValueCoverage(profile)
	end

	local endingBalance: number
	if type(ctx) == "table" and isFiniteNumber(ctx.endingBalance) then
		endingBalance = math.max(0, math.floor(ctx.endingBalance))
	else
		endingBalance = math.max(0, math.floor(tonumber(profile.Coins) or 0))
	end

	local earned: number? = nil
	if type(ctx) == "table" and isFiniteNumber(ctx.earned) then
		earned = math.max(0, math.floor(ctx.earned))
	end

	if earned ~= nil then
		local gr = math.max(0, math.floor(tonumber(bag.GameRoom) or 0))
		local sz = math.max(0, math.floor(tonumber(bag.SummerZone) or 0))
		local unk = math.max(0, math.floor(tonumber(bag.Unknown) or 0))
		local sum = gr + sz + unk
		bag.GameRoom = gr
		bag.SummerZone = sz
		bag.Unknown = unk
		if sum < earned then
			bag.Unknown += earned - sum
		elseif sum > earned then
			local excess = sum - earned
			warnHandler(
				"[GameAnalytics] BagValueByZone sum exceeds earned; correcting",
				player.Name,
				"excess=" .. tostring(excess),
				"earned=" .. tostring(earned)
			)
			reduceBagExcess(bag, excess)
		end
	end

	local transactionType = getGameplayTransactionType()
	local portions = {
		{ key = "GameRoom", sku = "BubbleSale_GameRoom" },
		{ key = "SummerZone", sku = "BubbleSale_SummerZone" },
		{ key = "Unknown", sku = "BubbleSale_Mixed" },
	}

	local hadAny = false
	for _, portion in ipairs(portions) do
		local amount = math.max(0, math.floor(tonumber(bag[portion.key]) or 0))
		if amount > 0 then
			hadAny = true
			GameAnalyticsService.LogCoinSource(player, {
				amount = amount,
				endingBalance = endingBalance,
				transactionType = transactionType,
				itemSku = portion.sku,
			})
		end
	end

	if hadAny then
		bag.GameRoom = 0
		bag.SummerZone = 0
		bag.Unknown = 0
		profile.__dirty = true
	end
end

function GameAnalyticsService.OnLevelReached(player: Player, level: number)
	local session = sessions[player]
	if not session then
		GameAnalyticsService.WarnNoSession(player, "OnLevelReached")
		return
	end
	if not isFiniteNumber(level) then
		return
	end
	level = math.floor(level)
	if level < 1 then
		return
	end

	local profile = session.profile
	if type(profile) ~= "table" then
		return
	end
	ensureAnalytics(profile)

	session.lastProgressionLevelReported = session.lastProgressionLevelReported or 0
	local persistedLast = tonumber(profile.Analytics.LastProgressionLevel) or 0
	local lastReported = math.max(session.lastProgressionLevelReported, persistedLast)
	if level <= lastReported then
		return
	end

	local progressionOk = _logProgressionComplete(
		player,
		AnalyticsConfig.ProgressionPath,
		level,
		"Level_" .. tostring(level),
		nil
	)
	local customOk = _logCustom(player, "PlayerLevelReached", level, nil)

	if progressionOk or customOk then
		session.lastProgressionLevelReported = level
		profile.Analytics.LastProgressionLevel = math.max(persistedLast, level)
		profile.__dirty = true
	end

	if level >= ZoneDefs.GetRequiredLevel("SummerZone") then
		GameAnalyticsService.OnSummerRequiredLevelReached(player)
	end
end

function GameAnalyticsService.OnSawSummerZoneRequirement(player: Player)
	local session = sessions[player]
	if not session then
		GameAnalyticsService.WarnNoSession(player, "OnSawSummerZoneRequirement")
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then
		return
	end
	local summerZone = profile.Analytics.SummerZone
	if type(summerZone) ~= "table" then
		profile.Analytics.SummerZone = {}
		summerZone = profile.Analytics.SummerZone
	end
	if summerZone.SawSummerZoneRequirement == true then
		return
	end
	local version = tonumber(profile.Analytics.SummerZoneVersion) or AnalyticsConfig.SummerZoneAnalyticsVersion
	if _logCustom(player, "SawSummerZoneRequirement", 1, AnalyticsConfig.VersionCustomField(version)) then
		summerZone.SawSummerZoneRequirement = true
		profile.__dirty = true
	end
end

function GameAnalyticsService.OnOpenedBubbleTransit(player: Player)
	if not sessions[player] then
		GameAnalyticsService.WarnNoSession(player, "OnOpenedBubbleTransit")
		return
	end
	_logCustom(player, "OpenedBubbleTransit", 1, nil)
end

function GameAnalyticsService.OnSelectedSummerZone(player: Player)
	if not sessions[player] then
		GameAnalyticsService.WarnNoSession(player, "OnSelectedSummerZone")
		return
	end
	_logCustom(player, "SelectedSummerZone", 1, nil)
end

function GameAnalyticsService.OnArrivedAtSummerBridge(player: Player)
	GameAnalyticsService.ObserveSummer(player, "ArrivedAtSummerBridge")
end

function GameAnalyticsService.OnSummerBubblePopped(player: Player)
	GameAnalyticsService.ObserveSummer(player, "PoppedFirstSummerBubble")
end

function GameAnalyticsService.OnSummerBackpackFilled(player: Player)
	local session = sessions[player]
	if not session then
		GameAnalyticsService.WarnNoSession(player, "OnSummerBackpackFilled")
		return
	end
	GameAnalyticsService.ObserveSummer(player, "FilledFirstSummerBackpack")
	local profile = session.profile
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then
		return
	end
	local summerZone = profile.Analytics.SummerZone
	if type(summerZone) ~= "table" then
		profile.Analytics.SummerZone = {}
		summerZone = profile.Analytics.SummerZone
	end
	summerZone.pendingSummerFullBackpackSale = true
	profile.__dirty = true
end

-- Appeler uniquement après une vente réussie ; ne pas appeler si la vente a échoué.
function GameAnalyticsService.OnBackpackSoldAnalytics(player: Player, _ctx: any?)
	local session = sessions[player]
	if not session then
		GameAnalyticsService.WarnNoSession(player, "OnBackpackSoldAnalytics")
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then
		return
	end
	local summerZone = profile.Analytics.SummerZone
	if type(summerZone) ~= "table" then
		profile.Analytics.SummerZone = {}
		summerZone = profile.Analytics.SummerZone
	end

	local coinsEarned: number? = nil
	if type(_ctx) == "table" then
		coinsEarned = _ctx.coinsEarned or _ctx.earned or _ctx.coins or _ctx.amount
	end
	GameAnalyticsService.RecordSale(player, coinsEarned)

	if summerZone.SoldFirstSummerBackpack == true then
		if summerZone.pendingSummerFullBackpackSale == true then
			summerZone.pendingSummerFullBackpackSale = nil
			profile.__dirty = true
		end
		return
	end

	if summerZone.pendingSummerFullBackpackSale ~= true then
		return
	end

	GameAnalyticsService.ObserveSummer(player, "SoldFirstSummerBackpack")
	if summerZone.SoldFirstSummerBackpack == true then
		summerZone.pendingSummerFullBackpackSale = nil
		profile.__dirty = true
	end
end

function GameAnalyticsService.OnBackpackReset(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local profile = session.profile
	if type(profile) ~= "table" then
		return
	end
	ensureAnalytics(profile)
	local bag = profile.Analytics.BagValueByZone
	if type(bag) ~= "table" then
		profile.Analytics.BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 }
		bag = profile.Analytics.BagValueByZone
	end
	bag.GameRoom = 0
	bag.SummerZone = 0
	bag.Unknown = 0
	local summerZone = profile.Analytics.SummerZone
	if type(summerZone) == "table" and summerZone.pendingSummerFullBackpackSale == true then
		summerZone.pendingSummerFullBackpackSale = nil
	end
	profile.__dirty = true
end

function GameAnalyticsService.InitPlayer(player: Player, profile: any, isNewProfile: boolean)
	ensureAnalytics(profile)

	local emptyTotals = createEmptyTotals()
	local session: PlayerSession = {
		sessionId = HttpService:GenerateGUID(false),
		joinClock = os.clock(),
		isInitialProfileSession = false,
		onboardingActive = false,
		onboardingObserved = {},
		summerObserved = {},
		summerFunnelVersionFieldSent = false,
		profile = profile,
		sessionTotals = emptyTotals,
		lastFlushedTotals = copyTotals(emptyTotals),
		currentArea = nil,
		areaEnteredAt = nil,
		sessionFirstBubbleSent = false,
		sessionFirstSaleSent = false,
		lastProgressionLevelReported = tonumber(profile.Analytics.LastProgressionLevel) or 0,
		firstTimingSent = {},
	}
	sessions[player] = session

	profile.Analytics.OnboardingVersion = AnalyticsConfig.OnboardingAnalyticsVersion

	if isNewProfile == true then
		profile.Analytics.OnboardingStarted = true
		profile.__dirty = true
		session.isInitialProfileSession = true
		session.onboardingActive = profile.Analytics.OnboardingCompleted ~= true
		GameAnalyticsService.ObserveOnboarding(player, "JoinedGame")
	else
		session.isInitialProfileSession = false
	end

	session.onboardingActive = profile.Analytics.OnboardingStarted == true
		and profile.Analytics.OnboardingCompleted ~= true

	if session.onboardingActive then
		local sentOnboarding = profile.Analytics.Onboarding
		if type(sentOnboarding) == "table" then
			for stepName, sent in pairs(sentOnboarding) do
				if sent == true then
					session.onboardingObserved[stepName] = true
				end
			end
		end
		drainOnboarding(player)
	end

	local summerVersion = tonumber(profile.Analytics.SummerZoneVersion) or 0
	if summerVersion < AnalyticsConfig.SummerZoneAnalyticsVersion then
		profile.Analytics.SummerZone = {}
		profile.Analytics.SummerZoneFunnelSessionId = HttpService:GenerateGUID(false)
		profile.Analytics.SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion
		profile.__dirty = true
	elseif profile.Analytics.SummerZoneFunnelSessionId == nil
		or profile.Analytics.SummerZoneFunnelSessionId == "" then
		profile.Analytics.SummerZoneFunnelSessionId = HttpService:GenerateGUID(false)
		profile.__dirty = true
	end

	local sentSummer = profile.Analytics.SummerZone
	if type(sentSummer) == "table" then
		for _, step in ipairs(AnalyticsConfig.SummerSteps) do
			if sentSummer[step.name] == true then
				session.summerObserved[step.name] = true
			end
		end
	end

	GameAnalyticsService.EnsureBagValueCoverage(profile)

	local level = profile.Level or 1
	if level >= ZoneDefs.GetRequiredLevel("SummerZone") then
		GameAnalyticsService.OnSummerRequiredLevelReached(player)
	end
end

function GameAnalyticsService.FlushAndRemovePlayer(player: Player)
	local session = sessions[player]
	if not session then
		return
	end

	accumulateZoneTime(session)
	flushDeltas(player)

	if session.isInitialProfileSession then
		_logCustom(player, "FirstSessionDuration", secondsSinceJoin(session), nil)
	end

	sessions[player] = nil
end

function GameAnalyticsService.FlushAllPlayers()
	local players: { Player } = {}
	for trackedPlayer in pairs(sessions) do
		table.insert(players, trackedPlayer)
	end
	for _, trackedPlayer in ipairs(players) do
		GameAnalyticsService.FlushAndRemovePlayer(trackedPlayer)
	end
end

function GameAnalyticsService.DumpPlayerState(player: Player): string
	local session = sessions[player]
	if not session then
		return "no session"
	end
	local totals = session.sessionTotals
	return string.format(
		"sessionId=%s onboardingActive=%s isInitialProfileSession=%s "
			.. "normalPops=%d specialPops=%d salesCount=%d zoneChanges=%d",
		session.sessionId,
		tostring(session.onboardingActive),
		tostring(session.isInitialProfileSession),
		totals.normalPops,
		totals.specialPops,
		totals.salesCount,
		totals.zoneChanges
	)
end

function GameAnalyticsService.WarnNoSession(player: Player, context: string)
	warnHandler("[GameAnalytics] no session for", player.Name, context)
end

function GameAnalyticsService.HasSession(player: Player): boolean
	return sessions[player] ~= nil
end

function GameAnalyticsService.GetSessionForTests(player: Player): PlayerSession?
	return sessions[player]
end

function GameAnalyticsService.DebugEmitCustom(player: Player, name: string, value: number?)
	if not sessions[player] then
		GameAnalyticsService.WarnNoSession(player, name)
		return
	end
	_logCustom(player, name, value, nil)
end

function GameAnalyticsService.FlushSessionDeltasForTests(player: Player)
	flushDeltas(player)
end

function GameAnalyticsService.StopFlushLoopForTests()
	flushLoopStarted = false
	-- Permet le vrai Start() après les suites destructives (avant DataService).
	started = false
end

function GameAnalyticsService.SetFlushIntervalForTests(seconds: number?)
	flushIntervalOverride = seconds
end

function GameAnalyticsService.GetFlushLoopStartedForTests(): boolean
	return flushLoopStarted
end

function GameAnalyticsService.GetFlushLoopSpawnCountForTests(): number
	return flushLoopSpawnCount
end

return GameAnalyticsService
