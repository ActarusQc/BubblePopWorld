--!strict
-- Service central analytics phase 1 : sessions en mémoire, envoi via sink injectable.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnalyticsConfig = require(Shared.AnalyticsConfig)

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
	sessionTotals: SessionTotals,
	lastFlushedTotals: SessionTotals,
	currentArea: string?,
	areaEnteredAt: number?,
	sessionFirstBubbleSent: boolean,
	sessionFirstSaleSent: boolean,
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

local function getSink(): AnalyticsSink?
	if sink then
		return sink
	end
	if started then
		sink = createDefaultSink()
		return sink
	end
	return nil
end

local function invokeSink(methodName: string, fn: () -> ())
	local activeSink = getSink()
	if not activeSink then
		return
	end
	local ok, err = pcall(fn)
	if not ok then
		if AnalyticsConfig.DebugEnabled then
			warn("[GameAnalytics] sink error:", methodName, err)
		end
	elseif AnalyticsConfig.DebugEnabled then
		print("[GameAnalytics] sink ok:", methodName)
	end
end

local function _logOnboarding(player: Player, step: number, stepName: string, fields: any?)
	invokeSink("logOnboarding", function()
		local activeSink = getSink()
		if activeSink then
			activeSink.logOnboarding(player, step, stepName, fields)
		end
	end)
end

local function _logFunnel(
	player: Player,
	funnelName: string,
	sessionId: string,
	step: number,
	stepName: string,
	fields: any?
)
	invokeSink("logFunnel", function()
		local activeSink = getSink()
		if activeSink then
			activeSink.logFunnel(player, funnelName, sessionId, step, stepName, fields)
		end
	end)
end

local function _logCustom(player: Player, name: string, value: number?, fields: any?)
	invokeSink("logCustom", function()
		local activeSink = getSink()
		if activeSink then
			activeSink.logCustom(player, name, value, fields)
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
)
	invokeSink("logEconomy", function()
		local activeSink = getSink()
		if activeSink then
			activeSink.logEconomy(
				player,
				flowType,
				currencyType,
				amount,
				endingBalance,
				transactionType,
				itemSku,
				fields
			)
		end
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
		local activeSink = getSink()
		if activeSink then
			activeSink.logProgressionComplete(player, path, level, levelName, fields)
		end
	end)
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

function GameAnalyticsService.InitPlayer(player: Player, profile: any, isNewProfile: boolean)
	local emptyTotals = createEmptyTotals()
	local session: PlayerSession = {
		sessionId = HttpService:GenerateGUID(false),
		joinClock = os.clock(),
		isInitialProfileSession = isNewProfile == true,
		-- provisoire Task 2 ; Task 4 remplacera par OnboardingStarted/Completed
		onboardingActive = isNewProfile == true,
		onboardingObserved = {},
		summerObserved = {},
		sessionTotals = emptyTotals,
		lastFlushedTotals = copyTotals(emptyTotals),
		currentArea = nil,
		areaEnteredAt = nil,
		sessionFirstBubbleSent = false,
		sessionFirstSaleSent = false,
	}
	sessions[player] = session
	GameAnalyticsService.EnsureBagValueCoverage(profile)
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
