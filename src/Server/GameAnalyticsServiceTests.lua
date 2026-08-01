--!strict
-- Tests GameAnalyticsService : socle + InitPlayer onboarding/Summer (Task 4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local AnalyticsConfig = require(Shared.AnalyticsConfig)
local ZoneDefs = require(Shared.ZoneDefs)
local GameAnalyticsService = require(script.Parent.GameAnalyticsService)

local GameAnalyticsServiceTests = {}

local function fakePlayer(name: string, userId: number): any
	return { Name = name, UserId = userId }
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = deepCopy(child)
	end
	return out
end

local function buildAnalyticsProfile(overrides: { [string]: any }?): any
	local profile = {
		Level = 1,
		PendingSellValue = 0,
		Analytics = deepCopy({
			OnboardingVersion = AnalyticsConfig.OnboardingAnalyticsVersion,
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZoneFunnelSessionId = "",
			OnboardingStarted = false,
			OnboardingCompleted = false,
			Onboarding = {},
			SummerZone = {},
			BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 },
			LastProgressionLevel = 0,
			Lifetime = { FirstSpecialBubble = false },
		}),
	}
	if overrides then
		for key, value in pairs(overrides) do
			if key == "Analytics" and type(value) == "table" then
				for analyticsKey, analyticsValue in pairs(value) do
					profile.Analytics[analyticsKey] = deepCopy(analyticsValue)
				end
			else
				profile[key] = deepCopy(value)
			end
		end
	end
	return profile
end

type EconomyEntry = {
	flowType: any,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
}

type ProgressionEntry = {
	path: string,
	level: number,
	levelName: string,
}

type RecordingSink = {
	onboarding: { { step: number, stepName: string } },
	funnel: { { funnelName: string, sessionId: string, step: number, stepName: string, fields: any? } },
	custom: { { name: string, value: number? } },
	economy: { EconomyEntry },
	progression: { ProgressionEntry },
}

local function newRecordingSink(): RecordingSink
	return {
		onboarding = {},
		funnel = {},
		custom = {},
		economy = {},
		progression = {},
	}
end

local function attachRecordingSink(recording: RecordingSink)
	GameAnalyticsService.SetSink({
		logOnboarding = function(_player, step, stepName, _fields)
			table.insert(recording.onboarding, { step = step, stepName = stepName })
		end,
		logFunnel = function(_player, funnelName, sessionId, step, stepName, fields)
			table.insert(recording.funnel, {
				funnelName = funnelName,
				sessionId = sessionId,
				step = step,
				stepName = stepName,
				fields = fields,
			})
		end,
		logCustom = function(_player, name, value, _fields)
			table.insert(recording.custom, { name = name, value = value })
		end,
		logEconomy = function(_player, flowType, currencyType, amount, endingBalance, transactionType, itemSku, _fields)
			table.insert(recording.economy, {
				flowType = flowType,
				currencyType = currencyType,
				amount = amount,
				endingBalance = endingBalance,
				transactionType = transactionType,
				itemSku = itemSku,
			})
		end,
		logProgressionComplete = function(_player, path, level, levelName, _fields)
			table.insert(recording.progression, {
				path = path,
				level = level,
				levelName = levelName,
			})
		end,
	})
end

local function countOnboarding(recording: RecordingSink, stepName: string): number
	local count = 0
	for _, entry in ipairs(recording.onboarding) do
		if entry.stepName == stepName then
			count += 1
		end
	end
	return count
end

local function hasCustom(recording: RecordingSink, name: string): boolean
	for _, entry in ipairs(recording.custom) do
		if entry.name == name then
			return true
		end
	end
	return false
end

local function countCustom(recording: RecordingSink, name: string): number
	local count = 0
	for _, entry in ipairs(recording.custom) do
		if entry.name == name then
			count += 1
		end
	end
	return count
end

local function sumCustomValues(recording: RecordingSink, name: string): number
	local sum = 0
	for _, entry in ipairs(recording.custom) do
		if entry.name == name then
			sum += entry.value or 0
		end
	end
	return sum
end

local function countFunnel(recording: RecordingSink, stepName: string): number
	local count = 0
	for _, entry in ipairs(recording.funnel) do
		if entry.stepName == stepName then
			count += 1
		end
	end
	return count
end

local function funnelStepNames(recording: RecordingSink): { string }
	local names: { string } = {}
	for _, entry in ipairs(recording.funnel) do
		table.insert(names, entry.stepName)
	end
	return names
end

local function countEconomy(recording: RecordingSink, itemSku: string?): number
	local count = 0
	for _, entry in ipairs(recording.economy) do
		if itemSku == nil or entry.itemSku == itemSku then
			count += 1
		end
	end
	return count
end

local function countProgression(recording: RecordingSink, level: number): number
	local count = 0
	for _, entry in ipairs(recording.progression) do
		if entry.level == level then
			count += 1
		end
	end
	return count
end

local function economyFlowName(value: any): string
	if type(value) == "string" then
		return value
	end
	local ok, name = pcall(function()
		return (value :: any).Name
	end)
	return if ok then tostring(name) else tostring(value)
end

local function onboardingStepNames(recording: RecordingSink): { string }
	local names: { string } = {}
	for _, entry in ipairs(recording.onboarding) do
		table.insert(names, entry.stepName)
	end
	return names
end

function GameAnalyticsServiceTests.Run(): boolean
	local ok = true
	local passCount = 0
	local failCount = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[GameAnalyticsServiceTests] FAIL:", msg)
			ok = false
			failCount += 1
		else
			print("[GameAnalyticsServiceTests] PASS:", msg)
			passCount += 1
		end
	end

	local caseSeq = 0
	local warnCalls: { { any } } = {}
	local recording = newRecordingSink()
	local playerA: any = fakePlayer("TestPlayer", 1)
	local playerB: any = fakePlayer("OtherPlayer", 2)

	local function beginIsolatedCase()
		caseSeq += 1
		GameAnalyticsService.FlushAllPlayers()
		warnCalls = {}
		GameAnalyticsService.SetWarnHandler(function(...)
			table.insert(warnCalls, { ... })
		end)
		recording = newRecordingSink()
		attachRecordingSink(recording)
		playerA = fakePlayer("GasA_" .. tostring(caseSeq), 100000 + caseSeq)
		playerB = fakePlayer("GasB_" .. tostring(caseSeq), 200000 + caseSeq)
		check(not GameAnalyticsService.HasSession(playerA), "isolation: playerA sans session")
		check(not GameAnalyticsService.HasSession(playerB), "isolation: playerB sans session")
	end

	GameAnalyticsService.FlushAllPlayers()
	GameAnalyticsService.SetSink(nil)
	GameAnalyticsService.SetWarnHandler(nil)
	GameAnalyticsService.Start()

	-- Task 2 socle — session + dump
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), true)
	check(GameAnalyticsService.HasSession(playerA), "InitPlayer crée une session")
	local dumpA = GameAnalyticsService.DumpPlayerState(playerA)
	check(dumpA ~= "no session", "DumpPlayerState contient une session")
	check(string.find(dumpA, "sessionId=") ~= nil, "Dump contient sessionId")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 2 — DebugEmitCustom sans session (isolation stricte : pas de FirstSessionDuration résiduel)
	beginIsolatedCase()
	check(not GameAnalyticsService.HasSession(playerA), "DebugEmitCustom setup → aucune session")
	local customBefore = #recording.custom
	GameAnalyticsService.DebugEmitCustom(playerA, "TestEvent", 1)
	check(#warnCalls == 1, "DebugEmitCustom sans session appelle le warn handler")
	check(#recording.custom == customBefore, "DebugEmitCustom sans session n'appelle pas le sink")
	check(#recording.custom == 0, "DebugEmitCustom sans session → sink custom vide")

	-- Task 2 — sink en erreur
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	local okCall = pcall(function()
		GameAnalyticsService.SetSink({
			logOnboarding = function()
				error("boom onboarding")
			end,
			logFunnel = function()
				error("boom funnel")
			end,
			logCustom = function()
				error("boom custom")
			end,
			logEconomy = function()
				error("boom economy")
			end,
			logProgressionComplete = function()
				error("boom progression")
			end,
		})
		GameAnalyticsService.DebugEmitCustom(playerA, "ResilientEvent", 42)
	end)
	check(okCall, "sink en erreur : DebugEmitCustom ne propage pas l'exception")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 4 — cas 1 : nouveau profil
	beginIsolatedCase()

	local newProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, newProfile, true)
	check(newProfile.Analytics.OnboardingStarted == true, "isNewProfile → OnboardingStarted true")
	check(
		#recording.onboarding == 1
			and recording.onboarding[1].step == 1
			and recording.onboarding[1].stepName == "JoinedGame",
		"isNewProfile → sink reçoit logOnboarding step 1 JoinedGame"
	)
	check(newProfile.Analytics.Onboarding.JoinedGame == true, "JoinedGame persisté dans le profil")
	local newSession = GameAnalyticsService.GetSessionForTests(playerA)
	check(newSession ~= nil and newSession.isInitialProfileSession == true, "isInitialProfileSession true")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 4 — cas 2 : profil reconcilié existant
	beginIsolatedCase()
	local reconciled = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, reconciled, false)
	check(reconciled.Analytics.OnboardingStarted == false, "isNewProfile=false → OnboardingStarted reste false")
	check(#recording.onboarding == 0, "isNewProfile=false → aucun appel onboarding sink")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 4 — cas 3 : reconnexion onboarding en cours
	beginIsolatedCase()
	local reconnectProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = false,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
			},
			SummerZoneFunnelSessionId = "stable-guid-123",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, reconnectProfile, false)
	local reconnectSession = GameAnalyticsService.GetSessionForTests(playerA)
	check(reconnectSession ~= nil and reconnectSession.onboardingActive == true, "reconnexion → onboardingActive true")
	check(
		reconnectSession.onboardingObserved.JoinedGame == true
			and reconnectSession.onboardingObserved.ReachedMainBubbleRoom == true,
		"reconnexion → onboardingObserved re-seedé depuis le profil"
	)
	check(#recording.onboarding == 0, "reconnexion → pas de re-envoi des étapes déjà envoyées")
	GameAnalyticsService.ObserveOnboarding(playerA, "PoppedFirstBubble")
	check(
		#recording.onboarding == 1 and recording.onboarding[1].stepName == "PoppedFirstBubble",
		"reconnexion → prochaine étape observée s'envoie"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 4 — cas 4 : onboarding terminé
	beginIsolatedCase()
	local completedProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = true,
			Onboarding = { JoinedGame = true, PurchasedFirstUpgrade = true },
			SummerZoneFunnelSessionId = "stable-guid-456",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, completedProfile, false)
	local completedSession = GameAnalyticsService.GetSessionForTests(playerA)
	check(completedSession ~= nil and completedSession.onboardingActive == false, "OnboardingCompleted → onboardingActive false")
	GameAnalyticsService.ObserveOnboarding(playerA, "PoppedFirstBubble")
	check(#recording.onboarding == 0, "ObserveOnboarding no-op après OnboardingCompleted")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 4 — cas 5 : bump Summer version
	beginIsolatedCase()
	local summerBumpProfile = buildAnalyticsProfile({
		Analytics = {
			SummerZoneVersion = 0,
			SummerZoneFunnelSessionId = "old-guid",
			SummerZone = {
				SawSummerZoneRequirement = true,
				pendingSummerFullBackpackSale = true,
				ReachedRequiredLevel = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, summerBumpProfile, false)
	check(
		next(summerBumpProfile.Analytics.SummerZone) == nil,
		"Summer bump → SummerZone vidé (flags effacés)"
	)
	check(
		type(summerBumpProfile.Analytics.SummerZoneFunnelSessionId) == "string"
			and summerBumpProfile.Analytics.SummerZoneFunnelSessionId ~= ""
			and summerBumpProfile.Analytics.SummerZoneFunnelSessionId ~= "old-guid",
		"Summer bump → nouveau GUID non vide"
	)
	check(
		summerBumpProfile.Analytics.SummerZoneVersion == AnalyticsConfig.SummerZoneAnalyticsVersion,
		"Summer bump → SummerZoneVersion alignée config"
	)
	local firstGuid = summerBumpProfile.Analytics.SummerZoneFunnelSessionId
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	GameAnalyticsService.InitPlayer(playerA, summerBumpProfile, false)
	check(
		summerBumpProfile.Analytics.SummerZoneFunnelSessionId == firstGuid,
		"reconnexion sans bump → même GUID Summer"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 4 — cas 6 : niveau Summer déjà atteint
	beginIsolatedCase()
	local summerLevel = ZoneDefs.GetRequiredLevel("SummerZone")
	local levelProfile = buildAnalyticsProfile({
		Level = summerLevel,
		Analytics = {
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZoneFunnelSessionId = "level-guid",
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, levelProfile, false)
	check(
		#recording.funnel == 1
			and recording.funnel[1].stepName == "ReachedRequiredLevel"
			and recording.funnel[1].funnelName == AnalyticsConfig.FunnelSummer,
		"Level ≥ seuil Summer → ReachedRequiredLevel via logFunnel"
	)
	check(
		levelProfile.Analytics.SummerZone.ReachedRequiredLevel == true,
		"ReachedRequiredLevel persisté dans SummerZone"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	GameAnalyticsService.InitPlayer(playerA, levelProfile, false)
	check(
		#recording.funnel == 1,
		"second InitPlayer → pas de doublon ReachedRequiredLevel"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- EnsureBagValueCoverage
	beginIsolatedCase()
	local bagProfile = buildAnalyticsProfile({
		PendingSellValue = 50,
		Analytics = {
			BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 },
			SummerZoneFunnelSessionId = "",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, bagProfile, false)
	check(
		bagProfile.Analytics.BagValueByZone.Unknown == 50,
		"EnsureBagValueCoverage : PendingSellValue 50 → Unknown 50"
	)
	check(
		type(bagProfile.Analytics.SummerZoneFunnelSessionId) == "string"
			and bagProfile.Analytics.SummerZoneFunnelSessionId ~= "",
		"SummerZoneFunnelSessionId généré si vide"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	GameAnalyticsService.InitPlayer(playerB, buildAnalyticsProfile(), true)
	check(GameAnalyticsService.HasSession(playerA) and GameAnalyticsService.HasSession(playerB), "deux sessions actives")
	GameAnalyticsService.FlushAllPlayers()
	check(not GameAnalyticsService.HasSession(playerA), "FlushAllPlayers purge playerA")
	check(not GameAnalyticsService.HasSession(playerB), "FlushAllPlayers purge playerB")

	-- Task 5 — cas 1 : out of order (pop avant main room)
	beginIsolatedCase()
	local outOfOrderProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, outOfOrderProfile, true)
	check(#recording.onboarding == 1 and recording.onboarding[1].stepName == "JoinedGame", "out-of-order init → JoinedGame seul")
	GameAnalyticsService.OnBubblePopped(playerA, { zoneId = "GameRoom" })
	check(
		countOnboarding(recording, "PoppedFirstBubble") == 0,
		"out-of-order → PoppedFirstBubble observé mais pas envoyé sans ReachedMainBubbleRoom"
	)
	GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "GameRoom")
	local outOfOrderNames = onboardingStepNames(recording)
	check(
		outOfOrderNames[2] == "ReachedMainBubbleRoom" and outOfOrderNames[3] == "PoppedFirstBubble",
		"out-of-order → drain envoie ReachedMainBubbleRoom puis PoppedFirstBubble"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 5 — cas 2 : lobby avant sac plein
	beginIsolatedCase()
	local lobbyProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = false,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
			},
			SummerZoneFunnelSessionId = "lobby-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, lobbyProfile, false)
	GameAnalyticsService.OnReturnedToLobby(playerA)
	check(
		countOnboarding(recording, "ReturnedToLobbyAfterFullBackpack") == 0,
		"lobby avant sac plein → ReturnedToLobby ignoré"
	)
	GameAnalyticsService.OnBackpackBecameFull(playerA, { zoneId = "GameRoom" })
	GameAnalyticsService.OnReturnedToLobby(playerA)
	local lobbyNames = onboardingStepNames(recording)
	check(
		lobbyNames[1] == "BackpackFullFirstTime" and lobbyNames[2] == "ReturnedToLobbyAfterFullBackpack",
		"lobby après sac plein → étapes 4 puis 5"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 5 — cas 3 : seconde session sans First timing
	beginIsolatedCase()
	local secondSessionProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = false,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
			},
			SummerZoneFunnelSessionId = "second-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, secondSessionProfile, false)
	local secondSession = GameAnalyticsService.GetSessionForTests(playerA)
	check(secondSession ~= nil and secondSession.isInitialProfileSession == false, "seconde session → isInitialProfileSession false")
	GameAnalyticsService.OnBubblePopped(playerA, { zoneId = "GameRoom" })
	check(not hasCustom(recording, "SecondsToFirstBubble"), "seconde session → pas de SecondsToFirstBubble")
	check(hasCustom(recording, "SessionSecondsToFirstBubble"), "seconde session → SessionSecondsToFirstBubble autorisé")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 5 — cas 4 : OnLevelReached n'ajoute pas d'onboarding
	beginIsolatedCase()
	local levelOnlyProfile = buildAnalyticsProfile({
		Level = 5,
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = false,
			Onboarding = { JoinedGame = true },
			SummerZoneFunnelSessionId = "level-only-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, levelOnlyProfile, false)
	local onboardingBeforeLevel = #recording.onboarding
	GameAnalyticsService.OnLevelReached(playerA, 5)
	check(#recording.onboarding == onboardingBeforeLevel, "OnLevelReached → aucune étape onboarding")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 5 — cas 5 : duplicate observe
	beginIsolatedCase()
	local dupProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = false,
			Onboarding = { JoinedGame = true, ReachedMainBubbleRoom = true },
			SummerZoneFunnelSessionId = "dup-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, dupProfile, false)
	GameAnalyticsService.OnBubblePopped(playerA, nil)
	local firstPopCount = countOnboarding(recording, "PoppedFirstBubble")
	GameAnalyticsService.OnBubblePopped(playerA, nil)
	check(
		countOnboarding(recording, "PoppedFirstBubble") == firstPopCount,
		"duplicate Observe → pas de second sink onboarding pour PoppedFirstBubble"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 5 — cas 6a : sink fail onboarding
	beginIsolatedCase()
	GameAnalyticsService.SetSink({
		logOnboarding = function()
			error("onboarding fail")
		end,
		logFunnel = function() end,
		logCustom = function() end,
		logEconomy = function() end,
		logProgressionComplete = function() end,
	})
	local failProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = false,
			Onboarding = { JoinedGame = true, ReachedMainBubbleRoom = true },
			SummerZoneFunnelSessionId = "fail-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, failProfile, false)
	GameAnalyticsService.OnBubblePopped(playerA, nil)
	check(failProfile.Analytics.Onboarding.PoppedFirstBubble ~= true, "sink fail onboarding → flag PoppedFirstBubble non persisté")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 5 — cas 6b : First timing échoue → étape quand même marquée ; pas de rejeu funnel
	beginIsolatedCase()
	GameAnalyticsService.SetSink({
		logOnboarding = function(_player, _step, stepName, _fields)
			table.insert(recording.onboarding, { step = _step, stepName = stepName })
		end,
		logFunnel = function() end,
		logCustom = function(_player, name, value, _fields)
			if name == "SecondsToFirstBubble" then
				error("timing fail")
			end
			table.insert(recording.custom, { name = name, value = value })
		end,
		logEconomy = function() end,
		logProgressionComplete = function() end,
	})
	local timingFailProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, timingFailProfile, true)
	GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "GameRoom")
	GameAnalyticsService.OnBubblePopped(playerA, nil)
	check(
		timingFailProfile.Analytics.Onboarding.PoppedFirstBubble == true,
		"sink fail First timing → PoppedFirstBubble quand même marqué"
	)
	local popsAfterFail = countOnboarding(recording, "PoppedFirstBubble")
	check(popsAfterFail == 1, "sink fail First timing → un seul envoi funnel PoppedFirstBubble")
	GameAnalyticsService.OnBubblePopped(playerA, nil)
	check(
		countOnboarding(recording, "PoppedFirstBubble") == popsAfterFail,
		"après fail First timing → pas de rejeu funnel au prochain drain"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	attachRecordingSink(recording)

	-- Task 5 — cas 6c : SessionSeconds échoue → étape persistée ; pas de rejeu funnel ni First
	beginIsolatedCase()
	local firstTimingAttempts = 0
	GameAnalyticsService.SetSink({
		logOnboarding = function(_player, _step, stepName, _fields)
			table.insert(recording.onboarding, { step = _step, stepName = stepName })
		end,
		logFunnel = function() end,
		logCustom = function(_player, name, value, _fields)
			if name == "SessionSecondsToFirstBubble" then
				error("session timing fail")
			end
			if name == "SecondsToFirstBubble" then
				firstTimingAttempts += 1
			end
			table.insert(recording.custom, { name = name, value = value })
		end,
		logEconomy = function() end,
		logProgressionComplete = function() end,
	})
	local sessionTimingFailProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, sessionTimingFailProfile, true)
	GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "GameRoom")
	GameAnalyticsService.OnBubblePopped(playerA, nil)
	check(
		sessionTimingFailProfile.Analytics.Onboarding.PoppedFirstBubble == true,
		"SessionSeconds fail → étape PoppedFirstBubble persistée"
	)
	check(firstTimingAttempts == 1, "SessionSeconds fail → First timing envoyé une fois")
	local funnelPops = countOnboarding(recording, "PoppedFirstBubble")
	check(funnelPops == 1, "SessionSeconds fail → un seul envoi funnel")
	GameAnalyticsService.OnBubblePopped(playerA, nil)
	check(
		countOnboarding(recording, "PoppedFirstBubble") == funnelPops,
		"SessionSeconds fail → pas de rejeu funnel au prochain drain"
	)
	check(firstTimingAttempts == 1, "SessionSeconds fail → pas de renvoi SecondsToFirstBubble")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	attachRecordingSink(recording)

	-- Task 5 — cas 7 : FirstSpecialBubble
	beginIsolatedCase()
	local specialProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = false,
			Onboarding = { JoinedGame = true, ReachedMainBubbleRoom = true },
			SummerZoneFunnelSessionId = "special-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, specialProfile, false)
	local onboardingBeforeSpecial = #recording.onboarding
	GameAnalyticsService.OnBubblePopped(playerA, { isSpecial = true })
	check(countCustom(recording, "FirstSpecialBubble") == 1, "FirstSpecialBubble envoyé une fois")
	check(specialProfile.Analytics.Lifetime.FirstSpecialBubble == true, "FirstSpecialBubble persisté")
	GameAnalyticsService.OnBubblePopped(playerA, { isSpecial = true })
	check(countCustom(recording, "FirstSpecialBubble") == 1, "second special → pas de doublon FirstSpecialBubble")
	check(
		countOnboarding(recording, "PoppedFirstBubble") == 1,
		"special seul → une seule étape onboarding PoppedFirstBubble"
	)
	check(
		#recording.onboarding == onboardingBeforeSpecial + 1,
		"special seul → funnel onboarding inchangé hors première bulle"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 5 — cas 8 : OnReachedMainBubbleRoom zone filter
	beginIsolatedCase()
	local zoneProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, zoneProfile, true)
	GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "SummerZone")
	check(
		countOnboarding(recording, "ReachedMainBubbleRoom") == 0,
		"OnReachedMainBubbleRoom SummerZone → pas d'étape 2"
	)
	GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "GameRoom")
	check(
		countOnboarding(recording, "ReachedMainBubbleRoom") == 1,
		"OnReachedMainBubbleRoom GameRoom → observe étape 2"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 5 — timing initial sur nouvelle session
	beginIsolatedCase()
	local timingProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, timingProfile, true)
	local timingSession = GameAnalyticsService.GetSessionForTests(playerA)
	if timingSession then
		timingSession.joinClock = os.clock() - 5
	end
	GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "GameRoom")
	GameAnalyticsService.OnBubblePopped(playerA, nil)
	local timingValue: number? = nil
	for _, entry in ipairs(recording.custom) do
		if entry.name == "SecondsToFirstBubble" then
			timingValue = entry.value
		end
	end
	check(timingValue ~= nil and timingValue >= 0, "session initiale → SecondsToFirstBubble >= 0")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 6 — cas 1 : out of order summer (pop avant arrivée)
	beginIsolatedCase()
	local summerOutOfOrder = buildAnalyticsProfile({
		Level = summerLevel,
		Analytics = {
			SummerZoneFunnelSessionId = "summer-oof-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, summerOutOfOrder, false)
	check(
		countFunnel(recording, "ReachedRequiredLevel") == 1,
		"Task6 out-of-order → ReachedRequiredLevel envoyé à l'init"
	)
	GameAnalyticsService.OnSummerBubblePopped(playerA)
	check(
		countFunnel(recording, "PoppedFirstSummerBubble") == 0,
		"Task6 out-of-order → pop avant arrivée n'envoie pas step 3"
	)
	GameAnalyticsService.OnArrivedAtSummerBridge(playerA)
	local summerOofNames = funnelStepNames(recording)
	local arrivedIdx: number? = nil
	local popIdx: number? = nil
	for i, name in ipairs(summerOofNames) do
		if name == "ArrivedAtSummerBridge" then
			arrivedIdx = i
		elseif name == "PoppedFirstSummerBubble" then
			popIdx = i
		end
	end
	check(
		arrivedIdx ~= nil and popIdx ~= nil and arrivedIdx < popIdx,
		"Task6 out-of-order → après arrivée drain envoie step 2 puis 3"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 6 — cas 2 : Saw une fois par version
	beginIsolatedCase()
	local sawProfile = buildAnalyticsProfile({
		Analytics = {
			SummerZoneFunnelSessionId = "saw-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, sawProfile, false)
	GameAnalyticsService.OnSawSummerZoneRequirement(playerA)
	GameAnalyticsService.OnSawSummerZoneRequirement(playerA)
	check(countCustom(recording, "SawSummerZoneRequirement") == 1, "Task6 Saw → un seul custom")
	check(sawProfile.Analytics.SummerZone.SawSummerZoneRequirement == true, "Task6 Saw → flag persisté")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	sawProfile.Analytics.SummerZoneVersion = 0
	sawProfile.Analytics.SummerZone = { SawSummerZoneRequirement = true }
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, sawProfile, false)
	check(next(sawProfile.Analytics.SummerZone) == nil, "Task6 Saw bump → SummerZone vidé")
	GameAnalyticsService.OnSawSummerZoneRequirement(playerA)
	check(countCustom(recording, "SawSummerZoneRequirement") == 1, "Task6 Saw bump → peut refire après bump")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 6 — cas 3 : pending persiste reconnect + vente efface
	beginIsolatedCase()
	local pendingProfile = buildAnalyticsProfile({
		Level = summerLevel,
		Analytics = {
			SummerZoneFunnelSessionId = "pending-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, pendingProfile, false)
	GameAnalyticsService.OnArrivedAtSummerBridge(playerA)
	GameAnalyticsService.OnSummerBubblePopped(playerA)
	GameAnalyticsService.OnSummerBackpackFilled(playerA)
	check(
		pendingProfile.Analytics.SummerZone.pendingSummerFullBackpackSale == true,
		"Task6 pending → OnSummerBackpackFilled met pending true"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	GameAnalyticsService.InitPlayer(playerA, pendingProfile, false)
	check(
		pendingProfile.Analytics.SummerZone.pendingSummerFullBackpackSale == true,
		"Task6 pending → survit FlushAndRemove + reconnect"
	)
	local funnelBeforeSale = #recording.funnel
	GameAnalyticsService.OnBackpackSoldAnalytics(playerA)
	check(
		countFunnel(recording, "SoldFirstSummerBackpack") == 1,
		"Task6 pending → OnBackpackSoldAnalytics envoie SoldFirstSummerBackpack"
	)
	check(
		pendingProfile.Analytics.SummerZone.pendingSummerFullBackpackSale ~= true,
		"Task6 pending → effacé après Sold marqué"
	)
	check(
		pendingProfile.Analytics.SummerZone.SoldFirstSummerBackpack == true,
		"Task6 pending → SoldFirstSummerBackpack persisté"
	)
	check(funnelBeforeSale < #recording.funnel, "Task6 pending → au moins un funnel émis à la vente")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 6 — cas 4 : vente sans étapes summer → pending conservé
	beginIsolatedCase()
	local earlySaleProfile = buildAnalyticsProfile({
		Analytics = {
			SummerZoneFunnelSessionId = "early-sale-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, earlySaleProfile, false)
	GameAnalyticsService.OnSummerBackpackFilled(playerA)
	check(
		earlySaleProfile.Analytics.SummerZone.pendingSummerFullBackpackSale == true,
		"Task6 early sale → pending true après fill"
	)
	GameAnalyticsService.OnBackpackSoldAnalytics(playerA)
	check(
		countFunnel(recording, "SoldFirstSummerBackpack") == 0,
		"Task6 early sale → Sold pas envoyé sans étapes préalables"
	)
	check(
		earlySaleProfile.Analytics.SummerZone.pendingSummerFullBackpackSale == true,
		"Task6 early sale → pending conservé si Sold non marqué"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 6 — cas 5 : OnBackpackReset efface pending
	beginIsolatedCase()
	local resetProfile = buildAnalyticsProfile({
		Analytics = {
			SummerZoneFunnelSessionId = "reset-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, resetProfile, false)
	GameAnalyticsService.OnSummerBackpackFilled(playerA)
	GameAnalyticsService.OnBackpackReset(playerA)
	check(
		resetProfile.Analytics.SummerZone.pendingSummerFullBackpackSale ~= true,
		"Task6 reset → pending effacé"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 6 — cas 6 : Selected custom répétable ; Arrived funnel
	beginIsolatedCase()
	local selectProfile = buildAnalyticsProfile({
		Level = summerLevel,
		Analytics = {
			SummerZoneFunnelSessionId = "select-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = { ReachedRequiredLevel = true },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, selectProfile, false)
	local customBeforeSelect = #recording.custom
	GameAnalyticsService.OnSelectedSummerZone(playerA)
	GameAnalyticsService.OnSelectedSummerZone(playerA)
	check(
		countCustom(recording, "SelectedSummerZone") == 2,
		"Task6 Selected → custom session à chaque appel"
	)
	GameAnalyticsService.OnArrivedAtSummerBridge(playerA)
	check(
		countFunnel(recording, "ArrivedAtSummerBridge") == 1,
		"Task6 Arrived → funnel ObserveSummer"
	)
	check(#recording.custom == customBeforeSelect + 2, "Task6 Selected → n'ajoute pas de funnel")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 6 — cas 7 : Selected sans Arrived → pas d'étape Arrived
	beginIsolatedCase()
	local selectOnlyProfile = buildAnalyticsProfile({
		Analytics = {
			SummerZoneFunnelSessionId = "select-only-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, selectOnlyProfile, false)
	GameAnalyticsService.OnSelectedSummerZone(playerA)
	check(
		countFunnel(recording, "ArrivedAtSummerBridge") == 0,
		"Task6 Selected seul → pas d'étape Arrived"
	)
	check(countCustom(recording, "SelectedSummerZone") == 1, "Task6 Selected seul → custom envoyé")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 6 — cas 8 : champ version sur premier emit funnel summer
	beginIsolatedCase()
	local versionProfile = buildAnalyticsProfile({
		Level = summerLevel,
		Analytics = {
			SummerZoneFunnelSessionId = "version-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, versionProfile, false)
	check(#recording.funnel >= 1, "Task6 version → au moins un funnel summer")
	local firstFields = recording.funnel[1].fields
	check(
		type(firstFields) == "table"
			and firstFields.CustomField1 == "v" .. tostring(AnalyticsConfig.SummerZoneAnalyticsVersion),
		"Task6 version → CustomField1 sur premier emit funnel summer"
	)
	GameAnalyticsService.OnArrivedAtSummerBridge(playerA)
	local versionFieldCount = 0
	for _, entry in ipairs(recording.funnel) do
		if type(entry.fields) == "table" and entry.fields.CustomField1 ~= nil then
			versionFieldCount += 1
		end
	end
	check(versionFieldCount == 1, "Task6 version → champ version une seule fois")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 7 — cas 1 : RecordPop + flush deltas
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.FlushSessionDeltasForTests(playerA)
	check(sumCustomValues(recording, "SessionNormalPops") == 3, "Task7 RecordPop x3 → SessionNormalPops 3")
	local popsAfterFirstFlush = countCustom(recording, "SessionNormalPops")
	GameAnalyticsService.FlushSessionDeltasForTests(playerA)
	check(
		countCustom(recording, "SessionNormalPops") == popsAfterFirstFlush,
		"Task7 second flush sans activité → pas de re-emit SessionNormalPops"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 7 — cas 2 : delta incrémental
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.FlushSessionDeltasForTests(playerA)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.FlushSessionDeltasForTests(playerA)
	check(sumCustomValues(recording, "SessionNormalPops") == 5, "Task7 flush delta → total pops 5")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 7 — cas 3 : zone seconds
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	local zoneSession = GameAnalyticsService.GetSessionForTests(playerA)
	check(zoneSession ~= nil, "Task7 zone session exists")
	if zoneSession then
		zoneSession.currentArea = "Lobby"
		zoneSession.areaEnteredAt = os.clock() - 10
	end
	GameAnalyticsService.RecordZoneChange(playerA, "GameRoom")
	GameAnalyticsService.FlushSessionDeltasForTests(playerA)
	check(sumCustomValues(recording, "SessionZoneSecondsLobby") >= 10, "Task7 zone change → SessionZoneSecondsLobby > 0")
	local lobbyEmitCount = countCustom(recording, "SessionZoneSecondsLobby")
	GameAnalyticsService.FlushSessionDeltasForTests(playerA)
	check(
		countCustom(recording, "SessionZoneSecondsLobby") == lobbyEmitCount,
		"Task7 second zone flush → pas de re-emit lobby seconds"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 7 — cas 4 : Start idempotent
	local spawnCount = GameAnalyticsService.GetFlushLoopSpawnCountForTests()
	GameAnalyticsService.Start()
	check(
		GameAnalyticsService.GetFlushLoopSpawnCountForTests() == spawnCount,
		"Task7 Start twice → une seule boucle flush"
	)
	check(GameAnalyticsService.GetFlushLoopStartedForTests() == true, "Task7 flush loop actif")

	-- Task 7 — cas 5 : sink fail sur SessionNormalPops
	beginIsolatedCase()
	local failNormalPops = true
	GameAnalyticsService.SetSink({
		logOnboarding = function() end,
		logFunnel = function() end,
		logCustom = function(_player, name, value, _fields)
			if name == "SessionNormalPops" and failNormalPops then
				error("normal pops fail")
			end
			table.insert(recording.custom, { name = name, value = value })
		end,
		logEconomy = function() end,
		logProgressionComplete = function() end,
	})
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.RecordToolUse(playerA, "pin")
	local flushOk = pcall(function()
		GameAnalyticsService.FlushSessionDeltasForTests(playerA)
	end)
	check(flushOk, "Task7 sink fail SessionNormalPops → flush ne propage pas")
	check(countCustom(recording, "SessionToolUses") == 1, "Task7 sink fail normal pops → SessionToolUses émis")
	check(countCustom(recording, "SessionNormalPops") == 0, "Task7 sink fail → SessionNormalPops non flushé")
	local sessionAfterFail = GameAnalyticsService.GetSessionForTests(playerA)
	check(
		sessionAfterFail ~= nil and sessionAfterFail.lastFlushedTotals.normalPops == 0,
		"Task7 sink fail → lastFlushed normalPops inchangé"
	)
	failNormalPops = false
	GameAnalyticsService.FlushSessionDeltasForTests(playerA)
	check(countCustom(recording, "SessionNormalPops") == 1, "Task7 retry flush → SessionNormalPops émis")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	attachRecordingSink(recording)

	-- Task 7 — cas 6 : FlushAndRemovePlayer + FirstSessionDuration
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), true)
	local initialSession = GameAnalyticsService.GetSessionForTests(playerA)
	if initialSession then
		initialSession.joinClock = os.clock() - 30
	end
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.RecordPop(playerA, nil)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	check(sumCustomValues(recording, "SessionNormalPops") == 2, "Task7 FlushAndRemovePlayer → deltas restants")
	check(hasCustom(recording, "FirstSessionDuration"), "Task7 FlushAndRemovePlayer initial → FirstSessionDuration")
	check(not GameAnalyticsService.HasSession(playerA), "Task7 FlushAndRemovePlayer → session supprimée")

	-- Task 8 — cas 1 : LogCoinSource valide
	beginIsolatedCase()
	local economyProfile = buildAnalyticsProfile({ Coins = 150 })
	GameAnalyticsService.InitPlayer(playerA, economyProfile, false)
	local sourceOk = GameAnalyticsService.LogCoinSource(playerA, {
		amount = 25,
		endingBalance = 150,
		transactionType = "Gameplay",
		itemSku = "BubbleSale_GameRoom",
	})
	check(sourceOk, "Task8 LogCoinSource valide → retourne true")
	check(#recording.economy == 1, "Task8 LogCoinSource → un emit economy")
	local economyEntry = recording.economy[1]
	check(
		economyFlowName(economyEntry.flowType) == "Source"
			and economyEntry.currencyType == AnalyticsConfig.CurrencyType
			and economyEntry.amount == 25
			and economyEntry.endingBalance == 150
			and economyEntry.itemSku == "BubbleSale_GameRoom",
		"Task8 LogCoinSource → Source, Coins, amount, endingBalance, sku"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 8 — cas 2 : validations LogCoinSource
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	GameAnalyticsService.LogCoinSource(playerA, {
		amount = 10,
		endingBalance = 10,
		transactionType = "Gameplay",
		itemSku = "NotAllowedSku",
	})
	GameAnalyticsService.LogCoinSource(playerA, {
		amount = 0,
		endingBalance = 10,
		transactionType = "Gameplay",
		itemSku = "BubbleSale_GameRoom",
	})
	GameAnalyticsService.LogCoinSource(playerA, {
		amount = 10,
		endingBalance = -1,
		transactionType = "Gameplay",
		itemSku = "BubbleSale_GameRoom",
	})
	check(#recording.economy == 0, "Task8 invalid sku/amount/ending → aucun emit economy")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 8 — cas 3 : LogCoinSink
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile({ Coins = 80 }), false)
	local sinkOk = GameAnalyticsService.LogCoinSink(playerA, {
		amount = 15,
		endingBalance = 80,
		transactionType = "Gameplay",
		itemSku = "Chest",
	})
	check(sinkOk, "Task8 LogCoinSink valide → retourne true")
	check(#recording.economy == 1, "Task8 LogCoinSink → un emit economy")
	check(
		economyFlowName(recording.economy[1].flowType) == "Sink"
			and recording.economy[1].itemSku == "Chest",
		"Task8 LogCoinSink → Sink flow et sku Chest"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 8 — cas 4 : LogBackpackSaleEconomy portions + reset
	beginIsolatedCase()
	local saleProfile = buildAnalyticsProfile({
		Coins = 200,
		PendingSellValue = 18,
		CurrentBubbles = 3,
		Analytics = {
			BagValueByZone = { GameRoom = 10, SummerZone = 5, Unknown = 3 },
			SummerZoneFunnelSessionId = "sale-economy-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleProfile, false)
	GameAnalyticsService.LogBackpackSaleEconomy(playerA, saleProfile)
	check(countEconomy(recording, "BubbleSale_GameRoom") == 1, "Task8 sale → BubbleSale_GameRoom")
	check(countEconomy(recording, "BubbleSale_SummerZone") == 1, "Task8 sale → BubbleSale_SummerZone")
	check(countEconomy(recording, "BubbleSale_Mixed") == 1, "Task8 sale → BubbleSale_Mixed")
	check(#recording.economy == 3, "Task8 sale → trois emits source")
	check(
		saleProfile.Analytics.BagValueByZone.GameRoom == 0
			and saleProfile.Analytics.BagValueByZone.SummerZone == 0
			and saleProfile.Analytics.BagValueByZone.Unknown == 0,
		"Task8 sale → BagValueByZone remis à zéro"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 8 — cas 5 : OnLevelReached dedup + nouveaux niveaux
	beginIsolatedCase()
	local progressionProfile = buildAnalyticsProfile({
		Level = 1,
		Analytics = {
			LastProgressionLevel = 0,
			SummerZoneFunnelSessionId = "progression-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, progressionProfile, false)
	GameAnalyticsService.OnLevelReached(playerA, 2)
	check(countProgression(recording, 2) == 1, "Task8 OnLevelReached(2) → progression une fois")
	check(countCustom(recording, "PlayerLevelReached") == 1, "Task8 OnLevelReached(2) → custom une fois")
	local levelReachedValue: number? = nil
	for _, entry in ipairs(recording.custom) do
		if entry.name == "PlayerLevelReached" then
			levelReachedValue = entry.value
		end
	end
	check(levelReachedValue == 2, "Task8 OnLevelReached(2) → PlayerLevelReached value 2")
	local progressionAfter2 = #recording.progression
	local customAfter2 = countCustom(recording, "PlayerLevelReached")
	GameAnalyticsService.OnLevelReached(playerA, 2)
	check(#recording.progression == progressionAfter2, "Task8 second OnLevelReached(2) → pas de doublon progression")
	check(
		countCustom(recording, "PlayerLevelReached") == customAfter2,
		"Task8 second OnLevelReached(2) → pas de doublon custom"
	)
	GameAnalyticsService.OnLevelReached(playerA, 3)
	check(countProgression(recording, 3) == 1, "Task8 OnLevelReached(3) → nouveau progression")
	check(countCustom(recording, "PlayerLevelReached") == 2, "Task8 OnLevelReached(3) → second custom")
	check(progressionProfile.Analytics.LastProgressionLevel == 3, "Task8 progression → LastProgressionLevel persisté")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 8 — cas 6 : OnLevelReached n'ajoute pas d'onboarding
	beginIsolatedCase()
	local levelOnboardingProfile = buildAnalyticsProfile({
		Level = 2,
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = false,
			Onboarding = { JoinedGame = true },
			LastProgressionLevel = 0,
			SummerZoneFunnelSessionId = "level-onboarding-guid",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
		},
	})
	GameAnalyticsService.InitPlayer(playerA, levelOnboardingProfile, false)
	local onboardingBeforeProgression = #recording.onboarding
	GameAnalyticsService.OnLevelReached(playerA, 2)
	check(
		#recording.onboarding == onboardingBeforeProgression,
		"Task8 OnLevelReached → aucune étape onboarding"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 8 — cas 7 : sink economy throw → LogCoinSource false sans throw
	beginIsolatedCase()
	GameAnalyticsService.SetSink({
		logOnboarding = function() end,
		logFunnel = function() end,
		logCustom = function() end,
		logEconomy = function()
			error("economy fail")
		end,
		logProgressionComplete = function() end,
	})
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	local throwOk, throwResult = pcall(function()
		return GameAnalyticsService.LogCoinSource(playerA, {
			amount = 5,
			endingBalance = 5,
			transactionType = "Gameplay",
			itemSku = "BubbleSale_GameRoom",
		})
	end)
	check(throwOk, "Task8 sink economy throw → pas d'exception vers l'appelant")
	check(throwResult == false, "Task8 sink economy throw → LogCoinSource retourne false")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	--------------------------------------------------------------------
	-- Task 11 — Bag provenance / full / sell
	--------------------------------------------------------------------

	local function sumEconomyAmounts(rec: RecordingSink): number
		local sum = 0
		for _, entry in ipairs(rec.economy) do
			sum += entry.amount
		end
		return sum
	end

	local function economySkuAmount(rec: RecordingSink, sku: string): number
		local sum = 0
		for _, entry in ipairs(rec.economy) do
			if entry.itemSku == sku then
				sum += entry.amount
			end
		end
		return sum
	end

	-- Task11-1 : ajout GameRoom
	beginIsolatedCase()
	local bagAddProfile = buildAnalyticsProfile({ Coins = 0 })
	GameAnalyticsService.InitPlayer(playerA, bagAddProfile, true)
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 12,
		zoneId = "GameRoom",
		becameFull = false,
		wasBelowCapacity = true,
	})
	check(bagAddProfile.Analytics.BagValueByZone.GameRoom == 12, "Task11 ajout GameRoom → BagValueByZone.GameRoom +12")
	check(bagAddProfile.__dirty == true, "Task11 ajout GameRoom → __dirty")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-2 : ajout SummerZone
	beginIsolatedCase()
	local bagSummerProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, bagSummerProfile, false)
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 20,
		zoneId = "SummerZone",
		becameFull = false,
		wasBelowCapacity = true,
	})
	check(bagSummerProfile.Analytics.BagValueByZone.SummerZone == 20, "Task11 ajout SummerZone → BagValueByZone.SummerZone +20")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-3 : zone inconnue / ClassicZone → Unknown
	beginIsolatedCase()
	local bagUnknownProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, bagUnknownProfile, false)
	bagUnknownProfile.PendingSellValue = 7
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 7,
		zoneId = "ClassicZone",
		becameFull = false,
		wasBelowCapacity = true,
	})
	bagUnknownProfile.PendingSellValue = 10
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 3,
		zoneId = "SomewhereElse",
		becameFull = false,
		wasBelowCapacity = true,
	})
	check(bagUnknownProfile.Analytics.BagValueByZone.Unknown == 10, "Task11 zone inconnue → BagValueByZone.Unknown")
	check(bagUnknownProfile.Analytics.BagValueByZone.GameRoom == 0, "Task11 ClassicZone → pas de clé GameRoom directe")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-4 : sellValue <= 0 → no-op
	beginIsolatedCase()
	local bagZeroProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, bagZeroProfile, false)
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 0,
		zoneId = "GameRoom",
		becameFull = false,
		wasBelowCapacity = true,
	})
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = -5,
		zoneId = "GameRoom",
		becameFull = false,
		wasBelowCapacity = true,
	})
	check(
		bagZeroProfile.Analytics.BagValueByZone.GameRoom == 0
			and bagZeroProfile.Analytics.BagValueByZone.SummerZone == 0
			and bagZeroProfile.Analytics.BagValueByZone.Unknown == 0,
		"Task11 sellValue <= 0 → aucun changement BagValueByZone"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-5 : transition vers sac plein → BackpackFullFirstTime une fois
	beginIsolatedCase()
	local fullProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, fullProfile, true)
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 5,
		zoneId = "GameRoom",
		becameFull = true,
		wasBelowCapacity = true,
	})
	local sessionFull = GameAnalyticsService.GetSessionForTests(playerA)
	check(
		sessionFull ~= nil and sessionFull.onboardingObserved.BackpackFullFirstTime == true,
		"Task11 transition plein → BackpackFullFirstTime observé"
	)
	check(countOnboarding(recording, "BackpackFullFirstTime") == 1, "Task11 transition plein → onboarding émis une fois")
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 5,
		zoneId = "GameRoom",
		becameFull = true,
		wasBelowCapacity = true,
	})
	check(countOnboarding(recording, "BackpackFullFirstTime") == 1, "Task11 second full → pas de double onboarding")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-6 : déjà plein (wasBelowCapacity false) → aucun nouveau full
	beginIsolatedCase()
	local alreadyFullProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, alreadyFullProfile, true)
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 4,
		zoneId = "GameRoom",
		becameFull = true,
		wasBelowCapacity = false,
	})
	local sessionAlready = GameAnalyticsService.GetSessionForTests(playerA)
	check(
		sessionAlready ~= nil and sessionAlready.onboardingObserved.BackpackFullFirstTime ~= true,
		"Task11 déjà plein → BackpackFullFirstTime non observé"
	)
	check(countOnboarding(recording, "BackpackFullFirstTime") == 0, "Task11 déjà plein → aucun onboarding full")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-7 : sac plein Summer → Filled + pending
	beginIsolatedCase()
	local summerFullProfile = buildAnalyticsProfile({
		Level = ZoneDefs.GetRequiredLevel("SummerZone"),
		Analytics = {
			SummerZoneFunnelSessionId = "task11-summer-full",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {
				ReachedRequiredLevel = true,
				ArrivedAtSummerBridge = true,
				PoppedFirstSummerBubble = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, summerFullProfile, false)
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 9,
		zoneId = "SummerZone",
		becameFull = true,
		wasBelowCapacity = true,
	})
	check(countFunnel(recording, "FilledFirstSummerBackpack") == 1, "Task11 sac plein Summer → FilledFirstSummerBackpack")
	check(
		summerFullProfile.Analytics.SummerZone.pendingSummerFullBackpackSale == true,
		"Task11 sac plein Summer → pending true"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-8 : vente GameRoom
	beginIsolatedCase()
	local saleGrProfile = buildAnalyticsProfile({
		Coins = 100,
		PendingSellValue = 40,
		CurrentBubbles = 5,
		Analytics = {
			BagValueByZone = { GameRoom = 40, SummerZone = 0, Unknown = 0 },
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleGrProfile, true)
	saleGrProfile.PendingSellValue = 0 -- doSell vide avant analytics
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 5, earned = 40, endingBalance = 140 })
	check(countEconomy(recording, "BubbleSale_GameRoom") == 1, "Task11 vente GameRoom → BubbleSale_GameRoom")
	check(economySkuAmount(recording, "BubbleSale_GameRoom") == 40, "Task11 vente GameRoom → amount 40")
	check(#recording.economy == 1, "Task11 vente GameRoom → un seul emit")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-9 : vente Summer
	beginIsolatedCase()
	local saleSzProfile = buildAnalyticsProfile({
		Coins = 50,
		PendingSellValue = 25,
		CurrentBubbles = 3,
		Analytics = {
			BagValueByZone = { GameRoom = 0, SummerZone = 25, Unknown = 0 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleSzProfile, false)
	saleSzProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 3, earned = 25, endingBalance = 75 })
	check(countEconomy(recording, "BubbleSale_SummerZone") == 1, "Task11 vente Summer → BubbleSale_SummerZone")
	check(economySkuAmount(recording, "BubbleSale_SummerZone") == 25, "Task11 vente Summer → amount 25")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-10 : vente mixte
	beginIsolatedCase()
	local saleMixProfile = buildAnalyticsProfile({
		Coins = 10,
		PendingSellValue = 30,
		CurrentBubbles = 8,
		Analytics = {
			BagValueByZone = { GameRoom = 10, SummerZone = 15, Unknown = 5 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleMixProfile, false)
	saleMixProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 8, earned = 30, endingBalance = 40 })
	check(countEconomy(recording, "BubbleSale_GameRoom") == 1, "Task11 vente mixte → GameRoom")
	check(countEconomy(recording, "BubbleSale_SummerZone") == 1, "Task11 vente mixte → SummerZone")
	check(countEconomy(recording, "BubbleSale_Mixed") == 1, "Task11 vente mixte → Mixed")
	check(sumEconomyAmounts(recording) == 30, "Task11 vente mixte → somme = earned")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-11 : portion Unknown → BubbleSale_Mixed
	beginIsolatedCase()
	local saleUnkProfile = buildAnalyticsProfile({
		Coins = 0,
		PendingSellValue = 18,
		CurrentBubbles = 2,
		Analytics = {
			BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 18 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleUnkProfile, false)
	saleUnkProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 2, earned = 18, endingBalance = 18 })
	check(countEconomy(recording, "BubbleSale_Mixed") == 1, "Task11 Unknown → BubbleSale_Mixed")
	check(economySkuAmount(recording, "BubbleSale_Mixed") == 18, "Task11 Unknown → amount 18")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-12 : somme provenance < earned → différence en Mixed
	beginIsolatedCase()
	local saleShortProfile = buildAnalyticsProfile({
		Coins = 0,
		PendingSellValue = 10,
		CurrentBubbles = 4,
		Analytics = {
			BagValueByZone = { GameRoom = 10, SummerZone = 0, Unknown = 0 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleShortProfile, false)
	saleShortProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 4, earned = 15, endingBalance = 15 })
	check(economySkuAmount(recording, "BubbleSale_GameRoom") == 10, "Task11 shortfall → GameRoom 10")
	check(economySkuAmount(recording, "BubbleSale_Mixed") == 5, "Task11 shortfall → Mixed +5")
	check(sumEconomyAmounts(recording) == 15, "Task11 shortfall → somme = earned")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-13 : vente réussie → salesCount / coinsFromSales
	beginIsolatedCase()
	local saleCountProfile = buildAnalyticsProfile({
		Coins = 0,
		PendingSellValue = 22,
		CurrentBubbles = 2,
		Analytics = {
			BagValueByZone = { GameRoom = 22, SummerZone = 0, Unknown = 0 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleCountProfile, false)
	saleCountProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 2, earned = 22, endingBalance = 22 })
	local sessionSale = GameAnalyticsService.GetSessionForTests(playerA)
	check(
		sessionSale ~= nil and sessionSale.sessionTotals.salesCount == 1,
		"Task11 vente réussie → salesCount +1"
	)
	check(
		sessionSale ~= nil and sessionSale.sessionTotals.coinsFromSales == 22,
		"Task11 vente réussie → coinsFromSales += earned"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-14 : deuxième vente → SessionSecondsToFirstSale non répété
	beginIsolatedCase()
	local saleTwiceProfile = buildAnalyticsProfile({
		Coins = 0,
		PendingSellValue = 10,
		CurrentBubbles = 1,
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
			},
			BagValueByZone = { GameRoom = 10, SummerZone = 0, Unknown = 0 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleTwiceProfile, true)
	saleTwiceProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 1, earned = 10, endingBalance = 10 })
	check(countCustom(recording, "SessionSecondsToFirstSale") == 1, "Task11 première vente → SessionSecondsToFirstSale")
	saleTwiceProfile.Analytics.BagValueByZone = { GameRoom = 8, SummerZone = 0, Unknown = 0 }
	saleTwiceProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 1, earned = 8, endingBalance = 18 })
	check(countCustom(recording, "SessionSecondsToFirstSale") == 1, "Task11 deuxième vente → SessionSecondsToFirstSale non répété")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-15 : crédit échoué (ctx invalide) → aucun hook économie / sale
	beginIsolatedCase()
	local saleFailProfile = buildAnalyticsProfile({
		Coins = 0,
		PendingSellValue = 10,
		CurrentBubbles = 1,
		Analytics = {
			BagValueByZone = { GameRoom = 10, SummerZone = 0, Unknown = 0 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleFailProfile, false)
	local invalidEndingCtx: any = { sold = 1, earned = 10 }
	GameAnalyticsService.OnBackpackSold(playerA, invalidEndingCtx)
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 1, earned = 0, endingBalance = 10 })
	check(#recording.economy == 0, "Task11 crédit/ctx invalide → aucun economy")
	local sessionFail = GameAnalyticsService.GetSessionForTests(playerA)
	check(
		sessionFail ~= nil and sessionFail.sessionTotals.salesCount == 0,
		"Task11 crédit/ctx invalide → salesCount inchangé"
	)
	check(saleFailProfile.Analytics.BagValueByZone.GameRoom == 10, "Task11 crédit/ctx invalide → bag intact")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-16 : reset sans vente
	beginIsolatedCase()
	local resetBagProfile = buildAnalyticsProfile({
		PendingSellValue = 17,
		CurrentBubbles = 3,
		Analytics = {
			BagValueByZone = { GameRoom = 11, SummerZone = 4, Unknown = 2 },
			SummerZoneFunnelSessionId = "task11-reset",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = { pendingSummerFullBackpackSale = true },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, resetBagProfile, false)
	local economyBeforeReset = #recording.economy
	GameAnalyticsService.OnBackpackReset(playerA)
	check(
		resetBagProfile.Analytics.BagValueByZone.GameRoom == 0
			and resetBagProfile.Analytics.BagValueByZone.SummerZone == 0
			and resetBagProfile.Analytics.BagValueByZone.Unknown == 0,
		"Task11 reset → BagValueByZone zéro"
	)
	check(
		resetBagProfile.Analytics.SummerZone.pendingSummerFullBackpackSale ~= true,
		"Task11 reset → pending false"
	)
	check(#recording.economy == economyBeforeReset, "Task11 reset → aucun événement économie")
	check(countOnboarding(recording, "SoldFirstBackpack") == 0, "Task11 reset → aucun Sold funnel")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-17 : pending Summer survit reconnexion avant vente
	beginIsolatedCase()
	local pendingReconnectProfile = buildAnalyticsProfile({
		Level = ZoneDefs.GetRequiredLevel("SummerZone"),
		Analytics = {
			SummerZoneFunnelSessionId = "task11-pending-reconnect",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {
				ReachedRequiredLevel = true,
				ArrivedAtSummerBridge = true,
				PoppedFirstSummerBubble = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, pendingReconnectProfile, false)
	GameAnalyticsService.OnSummerBackpackFilled(playerA)
	check(
		pendingReconnectProfile.Analytics.SummerZone.pendingSummerFullBackpackSale == true,
		"Task11 pending → true après fill"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	GameAnalyticsService.InitPlayer(playerA, pendingReconnectProfile, false)
	check(
		pendingReconnectProfile.Analytics.SummerZone.pendingSummerFullBackpackSale == true,
		"Task11 pending → survit reconnexion avant vente"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-18 : vente avec étapes Summer manquantes → pending conservé
	beginIsolatedCase()
	local pendingKeepProfile = buildAnalyticsProfile({
		Coins = 0,
		PendingSellValue = 12,
		CurrentBubbles = 2,
		Analytics = {
			BagValueByZone = { GameRoom = 0, SummerZone = 12, Unknown = 0 },
			SummerZoneFunnelSessionId = "task11-pending-keep",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, pendingKeepProfile, false)
	GameAnalyticsService.OnSummerBackpackFilled(playerA)
	pendingKeepProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 2, earned = 12, endingBalance = 12 })
	check(
		countFunnel(recording, "SoldFirstSummerBackpack") == 0,
		"Task11 pending keep → Sold Summer non envoyé"
	)
	check(
		pendingKeepProfile.Analytics.SummerZone.pendingSummerFullBackpackSale == true,
		"Task11 pending keep → pending conservé si Sold non marqué"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11-19 : pas de double comptage OnBubblesAddedToBag vs OnBubblePopped
	beginIsolatedCase()
	local noDoubleProfile = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, noDoubleProfile, true)
	GameAnalyticsService.OnBubblePopped(playerA, {
		zoneId = "GameRoom",
		rarityId = "Normal",
		isSpecial = false,
	})
	noDoubleProfile.PendingSellValue = 6
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 1,
		sellValueAdded = 6,
		zoneId = "GameRoom",
		becameFull = false,
		wasBelowCapacity = true,
	})
	local sessionNoDouble = GameAnalyticsService.GetSessionForTests(playerA)
	check(
		noDoubleProfile.Analytics.BagValueByZone.GameRoom == 6,
		"Task11 no-double → BagValue une seule fois (+6)"
	)
	check(
		sessionNoDouble ~= nil and sessionNoDouble.sessionTotals.normalPops == 1,
		"Task11 no-double → RecordPop une seule fois via OnBubblePopped"
	)
	check(
		sessionNoDouble ~= nil and sessionNoDouble.sessionTotals.salesCount == 0,
		"Task11 no-double → ajout sac n'incrémente pas salesCount"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task11 excess sum > earned → correction déterministe + warn (défense uniquement)
	-- Excès créé APRÈS InitPlayer (sinon la sync bidirectionnelle le corrige).
	beginIsolatedCase()
	local saleExcessProfile = buildAnalyticsProfile({
		Coins = 0,
		PendingSellValue = 25,
		CurrentBubbles = 3,
		Analytics = {
			BagValueByZone = { GameRoom = 25, SummerZone = 0, Unknown = 0 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, saleExcessProfile, false)
	saleExcessProfile.Analytics.BagValueByZone = { GameRoom = 20, SummerZone = 10, Unknown = 5 }
	saleExcessProfile.PendingSellValue = 0
	warnCalls = {}
	GameAnalyticsService.SetWarnHandler(function(...)
		table.insert(warnCalls, { ... })
	end)
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 3, earned = 25, endingBalance = 25 })
	check(sumEconomyAmounts(recording) == 25, "Task11 excess → somme envoyée = earned (pas plus)")
	check(#warnCalls >= 1, "Task11 excess → warn Studio")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	--------------------------------------------------------------------
	-- Task11 lifecycle — Case A : sac conservé à la reconnexion
	-- (DataService.reconcileBackpack conserve CurrentBubbles/PendingSellValue)
	--------------------------------------------------------------------

	-- Stale BagValue + pending 0 → couverture remet la somme à 0 (évite excess=74)
	beginIsolatedCase()
	local staleBagProfile = buildAnalyticsProfile({
		PendingSellValue = 0,
		CurrentBubbles = 0,
		Analytics = {
			BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 74 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, staleBagProfile, false)
	check(GameAnalyticsService.SumBagValueByZone(staleBagProfile) == 0, "Task11 lifecycle stale → bag sum 0")
	check(staleBagProfile.Analytics.BagValueByZone.Unknown == 0, "Task11 lifecycle stale → Unknown 0")
	staleBagProfile.PendingSellValue = 264
	staleBagProfile.CurrentBubbles = 10
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 10,
		sellValueAdded = 264,
		zoneId = "GameRoom",
		becameFull = true,
		wasBelowCapacity = true,
	})
	check(
		GameAnalyticsService.SumBagValueByZone(staleBagProfile) == 264,
		"Task11 lifecycle stale → sum avant vente = earned"
	)
	warnCalls = {}
	staleBagProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 10, earned = 264, endingBalance = 264 })
	check(sumEconomyAmounts(recording) == 264, "Task11 lifecycle stale → économie 264")
	check(#warnCalls == 0, "Task11 lifecycle stale → aucun warning excess")
	check(GameAnalyticsService.SumBagValueByZone(staleBagProfile) == 0, "Task11 lifecycle stale → bag reset après vente")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Case A restauré : Pending=74 → Unknown=74 ; + GameRoom 190 → vente 264 sans excess
	beginIsolatedCase()
	local restoreBagProfile = buildAnalyticsProfile({
		PendingSellValue = 74,
		CurrentBubbles = 5,
		Coins = 0,
		Analytics = {
			BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, restoreBagProfile, false)
	check(restoreBagProfile.Analytics.BagValueByZone.Unknown == 74, "Task11 lifecycle restore → Unknown=74")
	check(GameAnalyticsService.SumBagValueByZone(restoreBagProfile) == 74, "Task11 lifecycle restore → sum=pending")
	restoreBagProfile.PendingSellValue = 264 -- AddBubbles avant analytics
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 8,
		sellValueAdded = 190,
		zoneId = "GameRoom",
		becameFull = false,
		wasBelowCapacity = true,
	})
	check(restoreBagProfile.Analytics.BagValueByZone.GameRoom == 190, "Task11 lifecycle restore → GameRoom=190")
	check(GameAnalyticsService.SumBagValueByZone(restoreBagProfile) == 264, "Task11 lifecycle restore → sum avant vente")
	warnCalls = {}
	restoreBagProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 13, earned = 264, endingBalance = 264 })
	check(economySkuAmount(recording, "BubbleSale_GameRoom") == 190, "Task11 lifecycle restore → GameRoom sku")
	check(economySkuAmount(recording, "BubbleSale_Mixed") == 74, "Task11 lifecycle restore → Mixed sku")
	check(sumEconomyAmounts(recording) == 264, "Task11 lifecycle restore → somme 264")
	check(#warnCalls == 0, "Task11 lifecycle restore → aucun excess")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Ventes consécutives : pas de réutilisation du premier sac
	beginIsolatedCase()
	local consecutiveProfile = buildAnalyticsProfile({ Coins = 0, PendingSellValue = 0 })
	GameAnalyticsService.InitPlayer(playerA, consecutiveProfile, false)
	consecutiveProfile.PendingSellValue = 40
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 2,
		sellValueAdded = 40,
		zoneId = "GameRoom",
		becameFull = false,
		wasBelowCapacity = true,
	})
	consecutiveProfile.PendingSellValue = 0 -- doSell avant OnBackpackSold
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 2, earned = 40, endingBalance = 40 })
	check(GameAnalyticsService.SumBagValueByZone(consecutiveProfile) == 0, "Task11 consecutive → bag 0 après vente 1")
	recording = newRecordingSink()
	attachRecordingSink(recording)
	warnCalls = {}
	GameAnalyticsService.SetWarnHandler(function(...)
		table.insert(warnCalls, { ... })
	end)
	consecutiveProfile.PendingSellValue = 55
	GameAnalyticsService.OnBubblesAddedToBag(playerA, {
		storageAdded = 3,
		sellValueAdded = 55,
		zoneId = "SummerZone",
		becameFull = false,
		wasBelowCapacity = true,
	})
	check(GameAnalyticsService.SumBagValueByZone(consecutiveProfile) == 55, "Task11 consecutive → sum=55 avant vente 2")
	consecutiveProfile.PendingSellValue = 0
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 3, earned = 55, endingBalance = 95 })
	check(sumEconomyAmounts(recording) == 55, "Task11 consecutive → vente 2 = 55 seulement")
	check(economySkuAmount(recording, "BubbleSale_SummerZone") == 55, "Task11 consecutive → Summer seulement")
	check(#warnCalls == 0, "Task11 consecutive → aucun excess")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Reset manuel : bag + pending analytics alignés ; vente impossible côté métier (vide)
	beginIsolatedCase()
	local resetLifeProfile = buildAnalyticsProfile({
		PendingSellValue = 20,
		CurrentBubbles = 2,
		Analytics = {
			BagValueByZone = { GameRoom = 20, SummerZone = 0, Unknown = 0 },
			SummerZone = { pendingSummerFullBackpackSale = true },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, resetLifeProfile, false)
	GameAnalyticsService.OnBackpackReset(playerA)
	check(GameAnalyticsService.SumBagValueByZone(resetLifeProfile) == 0, "Task11 reset life → bag 0")
	check(
		resetLifeProfile.Analytics.SummerZone.pendingSummerFullBackpackSale ~= true,
		"Task11 reset life → pending cleared"
	)
	local economyBeforeEmpty = #recording.economy
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 0, earned = 0, endingBalance = 0 })
	check(#recording.economy == economyBeforeEmpty, "Task11 reset life → earned 0 → pas d'économie")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Vente après pending déjà 0 (ordre doSell) : portions conservées, pas de wipe prématuré
	beginIsolatedCase()
	local soldOrderProfile = buildAnalyticsProfile({
		Coins = 10,
		PendingSellValue = 0, -- déjà vidé par doSell
		CurrentBubbles = 0,
		Analytics = {
			BagValueByZone = { GameRoom = 100, SummerZone = 0, Unknown = 0 },
		},
	})
	GameAnalyticsService.InitPlayer(playerA, soldOrderProfile, false)
	-- Init ne doit pas laisser Unknown fantôme : pending 0 → bag forcé 0...
	-- donc on réinjecte les portions post-Init comme juste avant LogBackpackSaleEconomy.
	soldOrderProfile.Analytics.BagValueByZone.GameRoom = 100
	warnCalls = {}
	GameAnalyticsService.OnBackpackSold(playerA, { sold = 5, earned = 100, endingBalance = 110 })
	check(sumEconomyAmounts(recording) == 100, "Task11 sell-order → économie 100 malgré pending 0")
	check(#warnCalls == 0, "Task11 sell-order → aucun excess")
	check(GameAnalyticsService.SumBagValueByZone(soldOrderProfile) == 0, "Task11 sell-order → bag 0 après")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	--------------------------------------------------------------------
	-- Task 12 — Shop OnUpgradePurchased + sinks / sources
	--------------------------------------------------------------------

	-- Task12-1 : OnUpgradePurchased → sink Shop + sku id brut + onboarding
	beginIsolatedCase()
	local upgradeProfile = buildAnalyticsProfile({
		Coins = 9000,
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
				SoldFirstBackpack = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, upgradeProfile, true)
	check(AnalyticsConfig.IsEconomySkuAllowed("Speed") == true, "Task12 SKU Speed allowlist (id brut)")
	GameAnalyticsService.OnUpgradePurchased(playerA, {
		upgradeId = "Speed",
		amount = 1087,
		endingBalance = 8913,
	})
	check(countOnboarding(recording, "PurchasedFirstUpgrade") == 1, "Task12 upgrade → PurchasedFirstUpgrade")
	check(#recording.economy == 1, "Task12 upgrade → un sink économie")
	check(
		economyFlowName(recording.economy[1].flowType) == "Sink"
			and recording.economy[1].transactionType == "Shop"
			and recording.economy[1].itemSku == "Speed"
			and recording.economy[1].amount == 1087
			and recording.economy[1].endingBalance == 8913,
		"Task12 upgrade → Sink Shop sku=Speed amount/endingBalance"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task12-2 : premier upgrade → onboarding une fois
	beginIsolatedCase()
	local firstUpgradeProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
				SoldFirstBackpack = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, firstUpgradeProfile, true)
	GameAnalyticsService.OnUpgradePurchased(playerA, {
		upgradeId = "Jump",
		amount = 1000,
		endingBalance = 500,
	})
	check(countOnboarding(recording, "PurchasedFirstUpgrade") == 1, "Task12 premier upgrade → onboarding une fois")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task12-3 : second upgrade → pas de second onboarding emit
	beginIsolatedCase()
	local secondUpgradeProfile = buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			OnboardingCompleted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
				SoldFirstBackpack = true,
				PurchasedFirstUpgrade = true,
			},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, secondUpgradeProfile, false)
	GameAnalyticsService.OnUpgradePurchased(playerA, {
		upgradeId = "Power",
		amount = 500,
		endingBalance = 100,
	})
	check(countOnboarding(recording, "PurchasedFirstUpgrade") == 0, "Task12 second upgrade → pas de re-emit onboarding")
	check(countEconomy(recording, "Power") == 1, "Task12 second upgrade → sink Power quand même")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task12-4 : sink item (LogCoinSink) → aucun onboarding
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
				SoldFirstBackpack = true,
			},
		},
	}), true)
	check(AnalyticsConfig.IsEconomySkuAllowed("BackpackGold") == true, "Task12 SKU BackpackGold allowlist (id brut)")
	GameAnalyticsService.LogCoinSink(playerA, {
		amount = 10000,
		endingBalance = 500,
		transactionType = "Shop",
		itemSku = "BackpackGold",
	})
	check(countEconomy(recording, "BackpackGold") == 1, "Task12 item sink → BackpackGold")
	check(countOnboarding(recording, "PurchasedFirstUpgrade") == 0, "Task12 item sink → aucun onboarding upgrade")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task12-5 : sku invalide → aucun sink + warn ; pas d'onboarding
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
				SoldFirstBackpack = true,
			},
		},
	}), true)
	warnCalls = {}
	GameAnalyticsService.OnUpgradePurchased(playerA, {
		upgradeId = "NotARealUpgradeSku",
		amount = 10,
		endingBalance = 5,
	})
	check(#recording.economy == 0, "Task12 sku invalide → aucun sink")
	check(countOnboarding(recording, "PurchasedFirstUpgrade") == 0, "Task12 sku invalide → aucun onboarding")
	check(#warnCalls >= 1, "Task12 sku invalide → warn")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task12-6 : ctx invalide → drop
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	warnCalls = {}
	GameAnalyticsService.OnUpgradePurchased(playerA, nil)
	GameAnalyticsService.OnUpgradePurchased(playerA, "bad")
	check(#recording.economy == 0, "Task12 ctx invalide → aucun sink")
	check(#warnCalls >= 1, "Task12 ctx invalide → warn")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task12-7 : erreur sink → pas de throw
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
				SoldFirstBackpack = true,
			},
		},
	}), true)
	GameAnalyticsService.SetSink({
		logOnboarding = function() end,
		logFunnel = function() end,
		logCustom = function() end,
		logEconomy = function()
			error("economy sink boom")
		end,
		logProgressionComplete = function() end,
	})
	local sinkErrOk = pcall(function()
		GameAnalyticsService.OnUpgradePurchased(playerA, {
			upgradeId = "CoinMult",
			amount = 200,
			endingBalance = 50,
		})
	end)
	check(sinkErrOk == true, "Task12 sink error → OnUpgradePurchased ne throw pas")
	attachRecordingSink(recording)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task12-8 : sku ne contient jamais Name/UserId
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	GameAnalyticsService.OnUpgradePurchased(playerA, {
		upgradeId = "Speed",
		amount = 10,
		endingBalance = 1,
	})
	GameAnalyticsService.LogCoinSink(playerA, {
		amount = 20,
		endingBalance = 1,
		transactionType = "Shop",
		itemSku = "BackpackEmerald",
	})
	GameAnalyticsService.LogCoinSource(playerA, {
		amount = 30,
		endingBalance = 31,
		transactionType = "Gameplay",
		itemSku = "Chest",
	})
	local skuLeak = false
	for _, entry in ipairs(recording.economy) do
		local sku = tostring(entry.itemSku or "")
		if string.find(sku, "Name", 1, true) or string.find(sku, "UserId", 1, true) or string.find(sku, playerA.Name, 1, true) then
			skuLeak = true
		end
	end
	check(skuLeak == false, "Task12 → aucun Name/UserId dans itemSku")
	check(#recording.economy == 3, "Task12 → trois emits economy (upgrade/item/chest)")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task12-9 : amount invalide → pas de sink ; onboarding si upgradeId allowlist
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
				BackpackFullFirstTime = true,
				ReturnedToLobbyAfterFullBackpack = true,
				SoldFirstBackpack = true,
			},
		},
	}), true)
	warnCalls = {}
	GameAnalyticsService.OnUpgradePurchased(playerA, {
		upgradeId = "Speed",
		amount = 0,
		endingBalance = 10,
	})
	check(countOnboarding(recording, "PurchasedFirstUpgrade") == 1, "Task12 amount invalide → onboarding si sku valide")
	check(#recording.economy == 0, "Task12 amount invalide → aucun sink")
	check(#warnCalls >= 1, "Task12 amount invalide → warn sink")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	--------------------------------------------------------------------
	-- Task 13 — Travel / Zone / ZoneAccess (APIs GAS)
	--------------------------------------------------------------------

	-- Task13-1 : transit open → custom OpenedBubbleTransit
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	GameAnalyticsService.OnOpenedBubbleTransit(playerA)
	check(countCustom(recording, "OpenedBubbleTransit") == 1, "Task13 transit open → custom OpenedBubbleTransit")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-2 : Summer locked → Saw (once-per-version)
	beginIsolatedCase()
	local sawT13 = buildAnalyticsProfile({
		Analytics = {
			SummerZoneFunnelSessionId = "t13-saw",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, sawT13, false)
	GameAnalyticsService.OnSawSummerZoneRequirement(playerA)
	GameAnalyticsService.OnSawSummerZoneRequirement(playerA)
	check(countCustom(recording, "SawSummerZoneRequirement") == 1, "Task13 Summer locked → Saw une fois")
	check(sawT13.Analytics.SummerZone.SawSummerZoneRequirement == true, "Task13 Saw → flag persisté")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-3 : Selected Summer → custom SelectedSummerZone
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile({ Level = ZoneDefs.GetRequiredLevel("SummerZone") }), false)
	GameAnalyticsService.OnSelectedSummerZone(playerA)
	check(countCustom(recording, "SelectedSummerZone") == 1, "Task13 Selected Summer → custom")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-4 : PivotTo success → Arrived (funnel ArrivedAtSummerBridge)
	beginIsolatedCase()
	local arriveProfile = buildAnalyticsProfile({
		Level = ZoneDefs.GetRequiredLevel("SummerZone"),
		Analytics = {
			SummerZoneFunnelSessionId = "t13-arrive",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, arriveProfile, false)
	GameAnalyticsService.OnSelectedSummerZone(playerA)
	GameAnalyticsService.OnArrivedAtSummerBridge(playerA)
	check(countCustom(recording, "SelectedSummerZone") == 1, "Task13 PivotTo success → Selected déjà émis")
	check(countFunnel(recording, "ArrivedAtSummerBridge") == 1, "Task13 PivotTo success → Arrived funnel")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-5 : PivotTo fail → Selected sans Arrived
	beginIsolatedCase()
	local failPivotProfile = buildAnalyticsProfile({
		Level = ZoneDefs.GetRequiredLevel("SummerZone"),
		Analytics = {
			SummerZoneFunnelSessionId = "t13-fail-pivot",
			SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion,
			SummerZone = {},
		},
	})
	GameAnalyticsService.InitPlayer(playerA, failPivotProfile, false)
	GameAnalyticsService.OnSelectedSummerZone(playerA)
	-- pas d'OnArrivedAtSummerBridge (PivotTo échoué)
	check(countCustom(recording, "SelectedSummerZone") == 1, "Task13 PivotTo fail → Selected émis")
	check(countFunnel(recording, "ArrivedAtSummerBridge") == 0, "Task13 PivotTo fail → pas d'Arrived")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-6 : GameRoom réel → onboarding step 2
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), true)
	GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "GameRoom")
	check(countOnboarding(recording, "ReachedMainBubbleRoom") == 1, "Task13 GameRoom réel → step 2")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-7 : SummerZone → jamais onboarding step 2
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), true)
	GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "SummerZone")
	check(countOnboarding(recording, "ReachedMainBubbleRoom") == 0, "Task13 SummerZone → jamais step 2")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-8 : Lobby avant full backpack → pas step 5
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = { JoinedGame = true, ReachedMainBubbleRoom = true, PoppedFirstBubble = true },
		},
	}), false)
	GameAnalyticsService.OnReturnedToLobby(playerA)
	check(
		countOnboarding(recording, "ReturnedToLobbyAfterFullBackpack") == 0,
		"Task13 Lobby avant full → pas step 5"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-9 : Lobby après full → step 5
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile({
		Analytics = {
			OnboardingStarted = true,
			Onboarding = {
				JoinedGame = true,
				ReachedMainBubbleRoom = true,
				PoppedFirstBubble = true,
			},
		},
	}), false)
	GameAnalyticsService.OnBackpackBecameFull(playerA, { zoneId = "GameRoom" })
	GameAnalyticsService.OnReturnedToLobby(playerA)
	check(
		countOnboarding(recording, "ReturnedToLobbyAfterFullBackpack") == 1,
		"Task13 Lobby après full → step 5"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-10 : area identique → pas de double zoneChanges
	beginIsolatedCase()
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), false)
	GameAnalyticsService.RecordZoneChange(playerA, "Lobby")
	local sessionT13 = GameAnalyticsService.GetSessionForTests(playerA)
	local changesAfterFirst = if sessionT13 then sessionT13.sessionTotals.zoneChanges else -1
	GameAnalyticsService.RecordZoneChange(playerA, "Lobby")
	sessionT13 = GameAnalyticsService.GetSessionForTests(playerA)
	local changesAfterSame = if sessionT13 then sessionT13.sessionTotals.zoneChanges else -1
	check(changesAfterFirst == 1, "Task13 premier RecordZoneChange Lobby → zoneChanges=1")
	check(changesAfterSame == 1, "Task13 area identique → pas de double zoneChanges")
	GameAnalyticsService.RecordZoneChange(playerA, "GameRoom")
	sessionT13 = GameAnalyticsService.GetSessionForTests(playerA)
	check(
		sessionT13 ~= nil and sessionT13.sessionTotals.zoneChanges == 2,
		"Task13 changement réel → zoneChanges incrémenté"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task13-11 : sans session → warn OK, pas d'exception
	beginIsolatedCase()
	warnCalls = {}
	local noSessionOk = pcall(function()
		GameAnalyticsService.OnOpenedBubbleTransit(playerA)
		GameAnalyticsService.OnSawSummerZoneRequirement(playerA)
		GameAnalyticsService.OnSelectedSummerZone(playerA)
		GameAnalyticsService.OnArrivedAtSummerBridge(playerA)
		GameAnalyticsService.OnReachedMainBubbleRoom(playerA, "GameRoom")
		GameAnalyticsService.OnReturnedToLobby(playerA)
		GameAnalyticsService.RecordZoneChange(playerA, "Lobby")
	end)
	check(noSessionOk == true, "Task13 sans session → aucune exception")
	check(#warnCalls >= 1, "Task13 sans session → warn OK")
	check(#recording.custom == 0, "Task13 sans session → aucun custom émis")
	check(#recording.onboarding == 0, "Task13 sans session → aucun onboarding émis")
	check(#recording.funnel == 0, "Task13 sans session → aucun funnel émis")

	GameAnalyticsService.SetWarnHandler(nil)
	GameAnalyticsService.SetSink(nil)
	GameAnalyticsService.StopFlushLoopForTests()

	print(string.format("[GameAnalyticsServiceTests] assertions: %d pass / %d fail", passCount, failCount))
	if ok then
		print("[GameAnalyticsServiceTests] OK")
	end
	return ok
end

return GameAnalyticsServiceTests
