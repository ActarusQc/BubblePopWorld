--!strict
-- Tests ciblés Task12 : hooks analytics ChestService (source coins).
-- Isolation stricte : aucun AnalyticsService / FireAllClients réel.
-- Ne purge jamais FlushAllPlayers (préserve la session Studio live).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)

local DataService = require(script.Parent.DataService)
local ChestService = require(script.Parent.ChestService)
local GameAnalyticsService = require(script.Parent.GameAnalyticsService)

local ChestServiceTests = {}

local function fakePlayer(name: string, userId: number): any
	return {
		Name = name,
		UserId = userId,
		DisplayName = name,
		SetAttribute = function() end,
		FindFirstChild = function()
			return nil
		end,
	}
end

local function buildProfile(overrides: { [string]: any }?): any
	local profile = {
		Coins = 0,
		ChestsOpened = 0,
		CurrentBubbles = 0,
		PendingSellValue = 0,
		BackpackCapacity = Config.Backpack.DefaultCapacity,
		TotalBubblesSold = 0,
		Pops = 0,
		Level = 1,
		Upgrades = {},
		Worlds = { "Prairie" },
		OwnedItems = {},
		EquippedBackpack = "",
		MusicMuted = false,
		__loaded = false,
		__dirty = false,
		Analytics = {
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
		},
	}
	if overrides then
		for key, value in pairs(overrides) do
			profile[key] = value
		end
	end
	return profile
end

function ChestServiceTests.Run(): boolean
	local ok = true
	local passCount = 0
	local failCount = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[ChestServiceTests] FAIL:", msg)
			ok = false
			failCount += 1
		else
			print("[ChestServiceTests] PASS:", msg)
			passCount += 1
		end
	end

	local trackedPlayers: { any } = {}
	local function track(player: any)
		table.insert(trackedPlayers, player)
		return player
	end
	local function flushTrackedOnly()
		for _, player in ipairs(trackedPlayers) do
			GameAnalyticsService.FlushAndRemovePlayer(player)
			DataService.ClearProfileForTests(player)
		end
		table.clear(trackedPlayers)
	end

	local sourceCalls: { any } = {}
	local announceCalls: { any } = {}

	local origLogCoinSource = GameAnalyticsService.LogCoinSource
	local origAddCoins = DataService.AddCoins
	local origPush = DataService.Push
	local origSave = DataService.Save

	local sentinel = fakePlayer("ChestSentinelLive", 72999)
	local sentinelProfile = buildProfile()
	DataService.SetProfileForTests(sentinel, sentinelProfile)
	GameAnalyticsService.InitPlayer(sentinel, sentinelProfile, false)
	check(GameAnalyticsService.HasSession(sentinel) == true, "Task12 sentinel → session créée avant suite")

	local function restoreAll()
		GameAnalyticsService.LogCoinSource = origLogCoinSource
		DataService.AddCoins = origAddCoins
		DataService.Push = origPush
		DataService.Save = origSave
		ChestService.SetAnnounceHandlerForTests(nil)
		GameAnalyticsService.SetSink(nil)
		GameAnalyticsService.SetWarnHandler(nil)
		flushTrackedOnly()
		-- Ne jamais FlushAllPlayers ici : préserver sessions Studio (ex. joueur réel).
	end

	GameAnalyticsService.SetSink({
		logOnboarding = function() end,
		logFunnel = function() end,
		logCustom = function() end,
		logEconomy = function() end,
		logProgressionComplete = function() end,
	})
	GameAnalyticsService.SetWarnHandler(function() end)
	ChestService.SetAnnounceHandlerForTests(function(message, kind)
		table.insert(announceCalls, { message = message, kind = kind })
	end)
	DataService.Save = function() end
	DataService.Push = function() end

	GameAnalyticsService.LogCoinSource = function(player, ctx)
		table.insert(sourceCalls, { player = player, ctx = ctx })
		return origLogCoinSource(player, ctx)
	end

	local restoreOk, restoreErr = xpcall(function()
		local playerOk = track(fakePlayer("ChestOk", 72001))
		local profileOk = buildProfile({ Coins = 100 })
		DataService.SetProfileForTests(playerOk, profileOk)
		GameAnalyticsService.InitPlayer(playerOk, profileOk, false)
		sourceCalls = {}
		announceCalls = {}
		local claimState = { claimed = false }
		local claimed = ChestService.TryClaimForTests(playerOk, 40, claimState)
		check(claimed == true, "Task12 claim succès → true")
		check(claimState.claimed == true, "Task12 claim succès → claimState.claimed")
		check(profileOk.Coins == 140, "Task12 claim succès → coins crédités")
		check(profileOk.ChestsOpened == 1, "Task12 claim succès → ChestsOpened +1")
		check(#sourceCalls == 1, "Task12 claim succès → LogCoinSource une fois")
		check(
			sourceCalls[1] ~= nil
				and sourceCalls[1].ctx ~= nil
				and sourceCalls[1].ctx.amount == 40
				and sourceCalls[1].ctx.endingBalance == 140
				and sourceCalls[1].ctx.transactionType == "Gameplay"
				and sourceCalls[1].ctx.itemSku == "Chest",
			"Task12 claim succès → source Gameplay/Chest + endingBalance"
		)
		check(#announceCalls == 1, "Task12 claim succès → announce via seam")

		sourceCalls = {}
		local claimedAgain = ChestService.TryClaimForTests(playerOk, 40, claimState)
		check(claimedAgain == false, "Task12 refuse/cooldown → false")
		check(#sourceCalls == 0, "Task12 refuse/cooldown → aucun LogCoinSource")
		check(profileOk.Coins == 140, "Task12 refuse/cooldown → coins inchangés")
		check(profileOk.ChestsOpened == 1, "Task12 refuse/cooldown → ChestsOpened inchangé")

		local playerCredit = track(fakePlayer("ChestCreditFail", 72002))
		local profileCredit = buildProfile({ Coins = 50, ChestsOpened = 2 })
		DataService.SetProfileForTests(playerCredit, profileCredit)
		GameAnalyticsService.InitPlayer(playerCredit, profileCredit, false)
		sourceCalls = {}
		DataService.AddCoins = function()
			return false, nil
		end
		local failState = { claimed = false }
		local creditClaimed = ChestService.TryClaimForTests(playerCredit, 25, failState)
		DataService.AddCoins = origAddCoins
		check(creditClaimed == true, "Task12 AddCoins false → claim consommé (claimed)")
		check(failState.claimed == true, "Task12 AddCoins false → claimState.claimed")
		check(#sourceCalls == 0, "Task12 AddCoins false → aucun LogCoinSource")
		check(profileCredit.Coins == 50, "Task12 AddCoins false → coins inchangés")
		check(profileCredit.ChestsOpened == 3, "Task12 AddCoins false → ChestsOpened quand même +1")

		local playerSink = track(fakePlayer("ChestSinkErr", 72003))
		local profileSink = buildProfile({ Coins = 10 })
		DataService.SetProfileForTests(playerSink, profileSink)
		GameAnalyticsService.InitPlayer(playerSink, profileSink, false)
		sourceCalls = {}
		GameAnalyticsService.LogCoinSource = function(_player, _ctx)
			error("sink boom")
		end
		local sinkState = { claimed = false }
		local sinkClaimed = ChestService.TryClaimForTests(playerSink, 15, sinkState)
		GameAnalyticsService.LogCoinSource = function(player, ctx)
			table.insert(sourceCalls, { player = player, ctx = ctx })
			return origLogCoinSource(player, ctx)
		end
		check(sinkClaimed == true, "Task12 sink error → claim réussit quand même")
		check(profileSink.Coins == 25, "Task12 sink error → grant coins intact")
		check(profileSink.ChestsOpened == 1, "Task12 sink error → ChestsOpened +1")
		check(sinkState.claimed == true, "Task12 sink error → claimState.claimed")
	end, debug.traceback)

	restoreAll()

	check(GameAnalyticsService.HasSession(sentinel) == true, "Task12 sentinel → session préservée après cleanup")
	GameAnalyticsService.FlushAndRemovePlayer(sentinel)
	DataService.ClearProfileForTests(sentinel)

	if not restoreOk then
		warn("[ChestServiceTests] FAIL: suite error:", tostring(restoreErr))
		ok = false
		failCount += 1
	end

	print(string.format("[ChestServiceTests] assertions: %d pass / %d fail", passCount, failCount))
	if ok then
		print("[ChestServiceTests] OK")
	end
	return ok
end

return ChestServiceTests
