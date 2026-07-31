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

type RecordingSink = {
	onboarding: { { step: number, stepName: string } },
	funnel: { { funnelName: string, sessionId: string, step: number, stepName: string, fields: any? } },
	custom: { { name: string, value: number? } },
}

local function newRecordingSink(): RecordingSink
	return {
		onboarding = {},
		funnel = {},
		custom = {},
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
		logEconomy = function() end,
		logProgressionComplete = function() end,
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

local function onboardingStepNames(recording: RecordingSink): { string }
	local names: { string } = {}
	for _, entry in ipairs(recording.onboarding) do
		table.insert(names, entry.stepName)
	end
	return names
end

function GameAnalyticsServiceTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[GameAnalyticsServiceTests] FAIL:", msg)
			ok = false
		else
			print("[GameAnalyticsServiceTests] PASS:", msg)
		end
	end

	GameAnalyticsService.FlushAllPlayers()
	GameAnalyticsService.SetSink(nil)
	GameAnalyticsService.SetWarnHandler(nil)
	GameAnalyticsService.Start()

	local warnCalls: { { any } } = {}
	GameAnalyticsService.SetWarnHandler(function(...)
		table.insert(warnCalls, { ... })
	end)

	local recording = newRecordingSink()
	attachRecordingSink(recording)

	local playerA = fakePlayer("TestPlayer", 1)
	local playerB = fakePlayer("OtherPlayer", 2)

	-- Task 2 socle
	GameAnalyticsService.InitPlayer(playerA, buildAnalyticsProfile(), true)
	check(GameAnalyticsService.HasSession(playerA), "InitPlayer crée une session")
	local dumpA = GameAnalyticsService.DumpPlayerState(playerA)
	check(dumpA ~= "no session", "DumpPlayerState contient une session")
	check(string.find(dumpA, "sessionId=") ~= nil, "Dump contient sessionId")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	warnCalls = {}
	GameAnalyticsService.DebugEmitCustom(playerA, "TestEvent", 1)
	check(#warnCalls == 1, "DebugEmitCustom sans session appelle le warn handler")
	check(#recording.custom == 0, "DebugEmitCustom sans session n'appelle pas le sink")

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
	attachRecordingSink(recording)

	-- Task 4 — cas 1 : nouveau profil
	recording = newRecordingSink()
	attachRecordingSink(recording)
	GameAnalyticsService.FlushAllPlayers()

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
	recording = newRecordingSink()
	attachRecordingSink(recording)
	local reconciled = buildAnalyticsProfile()
	GameAnalyticsService.InitPlayer(playerA, reconciled, false)
	check(reconciled.Analytics.OnboardingStarted == false, "isNewProfile=false → OnboardingStarted reste false")
	check(#recording.onboarding == 0, "isNewProfile=false → aucun appel onboarding sink")
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	-- Task 4 — cas 3 : reconnexion onboarding en cours
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
	GameAnalyticsService.FlushAllPlayers()
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
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

	-- Task 5 — cas 6b : sink fail timing (Option A)
	recording = newRecordingSink()
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
		timingFailProfile.Analytics.Onboarding.PoppedFirstBubble ~= true,
		"sink fail timing initial → PoppedFirstBubble non marqué (Option A)"
	)
	check(
		countOnboarding(recording, "PoppedFirstBubble") >= 1,
		"sink fail timing → onboarding quand même tenté avant custom"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	attachRecordingSink(recording)

	-- Task 5 — cas 7 : FirstSpecialBubble
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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
	recording = newRecordingSink()
	attachRecordingSink(recording)
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

	local source = script.Parent:WaitForChild("GameAnalyticsService").Source
	check(string.find(source, "DataService") == nil, "GameAnalyticsService ne require pas DataService")
	check(string.find(source, "ZoneDefs") ~= nil, "GameAnalyticsService require ZoneDefs")

	GameAnalyticsService.SetWarnHandler(nil)
	GameAnalyticsService.SetSink(nil)

	if ok then
		print("[GameAnalyticsServiceTests] OK")
	end
	return ok
end

return GameAnalyticsServiceTests
