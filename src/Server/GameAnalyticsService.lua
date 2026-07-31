--!strict
-- Service central analytics phase 1 : sessions en mémoire, envoi via sink injectable.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnalyticsConfig = require(Shared.AnalyticsConfig)
local ZoneDefs = require(Shared.ZoneDefs)

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

local ANALYTICS_TEMPLATE = {
	OnboardingVersion = 1,
	SummerZoneVersion = 1,
	SummerZoneFunnelSessionId = "",
	OnboardingStarted = false,
	OnboardingCompleted = false,
	Onboarding = {},
	SummerZone = {},
	BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 },
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

-- Sink lazy : InitPlayer peut tourner avant Start() (ordre DataService actuel jusqu'à Task 9).
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

local function _logEconomy(
	player: Player,
	flowType: any,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
	fields: any?
)
	invokeSink("logEconomy", function()
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
)
	invokeSink("logProgressionComplete", function()
		getSink().logProgressionComplete(player, path, level, levelName, fields)
	end)
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
end

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
	bag.GameRoom = bag.GameRoom or 0
	bag.SummerZone = bag.SummerZone or 0
	bag.Unknown = bag.Unknown or 0
	local pending = math.max(0, math.floor(tonumber(profile.PendingSellValue) or 0))
	local sum = (bag.GameRoom or 0) + (bag.SummerZone or 0) + (bag.Unknown or 0)
	if pending > sum then
		bag.Unknown = (bag.Unknown or 0) + (pending - sum)
		profile.__dirty = true
	end
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

	local session = sessions[player]
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

function GameAnalyticsService.OnBackpackSold(player: Player, _ctx: any?)
	GameAnalyticsService.ObserveOnboarding(player, "SoldFirstBackpack")
end

function GameAnalyticsService.OnUpgradePurchased(player: Player, _ctx: any?)
	GameAnalyticsService.ObserveOnboarding(player, "PurchasedFirstUpgrade")
end

function GameAnalyticsService.OnLevelReached(player: Player, level: number)
	if level >= ZoneDefs.GetRequiredLevel("SummerZone") then
		GameAnalyticsService.OnSummerRequiredLevelReached(player)
	end
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
	-- full delta flush in later task
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

return GameAnalyticsService
