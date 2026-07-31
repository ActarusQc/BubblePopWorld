--!strict
-- Tests socle GameAnalyticsService (sans DataService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameAnalyticsService = require(script.Parent.GameAnalyticsService)

local GameAnalyticsServiceTests = {}

local function fakePlayer(name: string, userId: number): any
	return { Name = name, UserId = userId }
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

	local recording = {
		custom = {} :: { { name: string, value: number? } },
	}
	GameAnalyticsService.SetSink({
		logOnboarding = function() end,
		logFunnel = function() end,
		logCustom = function(_player, name, value, _fields)
			table.insert(recording.custom, { name = name, value = value })
		end,
		logEconomy = function() end,
		logProgressionComplete = function() end,
	})

	local playerA = fakePlayer("TestPlayer", 1)
	local playerB = fakePlayer("OtherPlayer", 2)
	local profile = {}

	GameAnalyticsService.InitPlayer(playerA, profile, true)
	check(GameAnalyticsService.HasSession(playerA), "InitPlayer crée une session")
	local dumpA = GameAnalyticsService.DumpPlayerState(playerA)
	check(dumpA ~= "no session", "DumpPlayerState contient une session")
	check(string.find(dumpA, "sessionId=") ~= nil, "Dump contient sessionId")
	check(string.find(dumpA, "onboardingActive=true") ~= nil, "Dump contient onboardingActive pour nouveau profil")

	local session = GameAnalyticsService.GetSessionForTests(playerA)
	check(session ~= nil and session.isInitialProfileSession == true, "isInitialProfileSession pour nouveau profil")

	GameAnalyticsService.FlushAndRemovePlayer(playerA)
	check(not GameAnalyticsService.HasSession(playerA), "FlushAndRemovePlayer purge la session")
	check(GameAnalyticsService.DumpPlayerState(playerA) == "no session", "Dump indique no session après flush")

	warnCalls = {}
	GameAnalyticsService.DebugEmitCustom(playerA, "TestEvent", 1)
	check(#warnCalls == 1, "DebugEmitCustom sans session appelle le warn handler")
	check(warnCalls[1][1] == "[GameAnalytics] no session for", "warn handler reçoit le préfixe attendu")
	check(warnCalls[1][2] == "TestPlayer", "warn handler reçoit le nom joueur")
	check(warnCalls[1][3] == "TestEvent", "warn handler reçoit le contexte")
	check(#recording.custom == 0, "DebugEmitCustom sans session n'appelle pas le sink")

	GameAnalyticsService.InitPlayer(playerA, profile, false)
	local threw = false
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
	check(okCall and not threw, "sink en erreur : DebugEmitCustom ne propage pas l'exception")

	GameAnalyticsService.InitPlayer(playerA, profile, false)
	GameAnalyticsService.InitPlayer(playerB, profile, true)
	check(GameAnalyticsService.HasSession(playerA) and GameAnalyticsService.HasSession(playerB), "deux sessions actives")
	GameAnalyticsService.FlushAllPlayers()
	check(not GameAnalyticsService.HasSession(playerA), "FlushAllPlayers purge playerA")
	check(not GameAnalyticsService.HasSession(playerB), "FlushAllPlayers purge playerB")

	local bagProfile = {
		Analytics = {
			BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 },
			SummerZoneFunnelSessionId = "",
		},
		PendingSellValue = 50,
	}
	GameAnalyticsService.InitPlayer(playerA, bagProfile, false)
	check(
		bagProfile.Analytics.BagValueByZone.Unknown == 50,
		"EnsureBagValueCoverage : PendingSellValue 50 → Unknown 50"
	)
	check(
		bagProfile.Analytics.SummerZoneFunnelSessionId == "",
		"SummerZoneFunnelSessionId reste vide (Task 4)"
	)
	GameAnalyticsService.FlushAndRemovePlayer(playerA)

	local source = script.Parent:WaitForChild("GameAnalyticsService").Source
	check(string.find(source, "DataService") == nil, "GameAnalyticsService ne require pas DataService")

	GameAnalyticsService.SetWarnHandler(nil)
	GameAnalyticsService.SetSink(nil)

	if ok then
		print("[GameAnalyticsServiceTests] OK")
	end
	return ok
end

return GameAnalyticsServiceTests
