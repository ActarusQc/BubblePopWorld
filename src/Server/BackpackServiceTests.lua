--!strict
-- Tests ciblés Task11 : hooks analytics BackpackService (add/sell/reset).
-- Isolation stricte : aucun AnalyticsService / FireClient / Save réel.
-- Ne purge jamais FlushAllPlayers (préserve la session Studio live).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)

local DataService = require(script.Parent.DataService)
local BackpackService = require(script.Parent.BackpackService)
local GameAnalyticsService = require(script.Parent.GameAnalyticsService)

local BackpackServiceTests = {}

local function fakePlayer(name: string, userId: number): any
	return {
		Name = name,
		UserId = userId,
		SetAttribute = function() end,
		FindFirstChild = function()
			return nil
		end,
	}
end

local function buildProfile(overrides: { [string]: any }?): any
	local profile = {
		Coins = 0,
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

function BackpackServiceTests.Run(): boolean
	local ok = true
	local passCount = 0
	local failCount = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[BackpackServiceTests] FAIL:", msg)
			ok = false
			failCount += 1
		else
			print("[BackpackServiceTests] PASS:", msg)
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

	local addedCalls: { any } = {}
	local soldCalls: { any } = {}
	local resetCalls: { any } = {}
	local announceCalls: { any } = {}

	local origAdded = GameAnalyticsService.OnBubblesAddedToBag
	local origSold = GameAnalyticsService.OnBackpackSold
	local origReset = GameAnalyticsService.OnBackpackReset
	local origAddCoins = DataService.AddCoins
	local origSave = DataService.Save
	local origPush = DataService.Push

	-- Sentinelle : session live ne doit pas être touchée par le cleanup.
	local sentinel = fakePlayer("BpSentinelLive", 71999)
	local sentinelProfile = buildProfile()
	DataService.SetProfileForTests(sentinel, sentinelProfile)
	GameAnalyticsService.InitPlayer(sentinel, sentinelProfile, false)
	check(GameAnalyticsService.HasSession(sentinel) == true, "Task11 sentinel → session créée avant suite")

	local function restoreAll()
		GameAnalyticsService.OnBubblesAddedToBag = origAdded
		GameAnalyticsService.OnBackpackSold = origSold
		GameAnalyticsService.OnBackpackReset = origReset
		DataService.AddCoins = origAddCoins
		DataService.Save = origSave
		DataService.Push = origPush
		BackpackService.SetAnnounceHandlerForTests(nil)
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
	BackpackService.SetAnnounceHandlerForTests(function(player, message, kind)
		table.insert(announceCalls, { player = player, message = message, kind = kind })
	end)
	DataService.Save = function() end
	DataService.Push = function() end

	GameAnalyticsService.OnBubblesAddedToBag = function(player, ctx)
		table.insert(addedCalls, { player = player, ctx = ctx })
		return origAdded(player, ctx)
	end
	GameAnalyticsService.OnBackpackSold = function(player, ctx)
		table.insert(soldCalls, { player = player, ctx = ctx })
		return origSold(player, ctx)
	end
	GameAnalyticsService.OnBackpackReset = function(player)
		table.insert(resetCalls, { player = player })
		return origReset(player)
	end

	local restoreOk, restoreErr = xpcall(function()
		local playerRefuse = track(fakePlayer("BpRefuse", 71001))
		local profileRefuse = buildProfile({
			CurrentBubbles = Config.Backpack.DefaultCapacity,
			PendingSellValue = 10,
		})
		DataService.SetProfileForTests(playerRefuse, profileRefuse)
		GameAnalyticsService.InitPlayer(playerRefuse, profileRefuse, false)
		addedCalls = {}
		announceCalls = {}
		local addedOk, err = BackpackService.AddBubbles(playerRefuse, 1, 5)
		check(addedOk == false, "Task11 AddBubbles refusé → false")
		check(err == BackpackService.ErrorCodes.BackpackFull, "Task11 AddBubbles refusé → BackpackFull")
		check(#addedCalls == 0, "Task11 AddBubbles refusé → aucun OnBubblesAddedToBag")
		check(BackpackService.IsLocked(playerRefuse) ~= true, "Task11 AddBubbles refusé → verrou libéré")
		check(#announceCalls >= 1, "Task11 AddBubbles refusé → announce via seam (pas FireClient)")

		local playerAdd = track(fakePlayer("BpAdd", 71002))
		local profileAdd = buildProfile()
		DataService.SetProfileForTests(playerAdd, profileAdd)
		GameAnalyticsService.InitPlayer(playerAdd, profileAdd, false)
		addedCalls = {}
		local addOk = BackpackService.AddBubbles(playerAdd, 1, 8)
		check(addOk == true, "Task11 AddBubbles succès → true")
		check(#addedCalls == 0, "Task11 AddBubbles seul → pas de hook bag (réservé BubbleService)")
		GameAnalyticsService.OnBubblesAddedToBag(playerAdd, {
			storageAdded = 1,
			sellValueAdded = 8,
			zoneId = "GameRoom",
			becameFull = false,
			wasBelowCapacity = true,
		})
		check(#addedCalls == 1, "Task11 ajout réussi → OnBubblesAddedToBag une fois")

		local playerEmpty = track(fakePlayer("BpEmpty", 71003))
		local profileEmpty = buildProfile()
		DataService.SetProfileForTests(playerEmpty, profileEmpty)
		GameAnalyticsService.InitPlayer(playerEmpty, profileEmpty, false)
		soldCalls = {}
		BackpackService.Sell(playerEmpty)
		check(#soldCalls == 0, "Task11 vente vide → aucun OnBackpackSold")

		local playerCredit = track(fakePlayer("BpCredit", 71004))
		local profileCredit = buildProfile({
			CurrentBubbles = 3,
			PendingSellValue = 15,
		})
		DataService.SetProfileForTests(playerCredit, profileCredit)
		GameAnalyticsService.InitPlayer(playerCredit, profileCredit, false)
		soldCalls = {}
		DataService.AddCoins = function()
			return false, nil
		end
		local creditSold, _creditEarned, creditErr = BackpackService.Sell(playerCredit)
		DataService.AddCoins = origAddCoins
		check(creditSold == nil and creditErr == "credit_failed", "Task11 AddCoins false → credit_failed")
		check(#soldCalls == 0, "Task11 AddCoins false → aucun OnBackpackSold")
		check(profileCredit.CurrentBubbles == 3, "Task11 AddCoins false → sac intact")

		local playerSale = track(fakePlayer("BpSale", 71005))
		local profileSale = buildProfile({
			Coins = 100,
			CurrentBubbles = 4,
			PendingSellValue = 30,
		})
		DataService.SetProfileForTests(playerSale, profileSale)
		GameAnalyticsService.InitPlayer(playerSale, profileSale, false)
		soldCalls = {}
		BackpackService.Sell(playerSale)
		check(#soldCalls == 1, "Task11 vente réussie → OnBackpackSold une fois")
		check(
			soldCalls[1] ~= nil
				and soldCalls[1].ctx ~= nil
				and soldCalls[1].ctx.earned == 30
				and soldCalls[1].ctx.endingBalance == 130,
			"Task11 vente réussie → endingBalance correct"
		)
		check(profileSale.CurrentBubbles == 0 and profileSale.PendingSellValue == 0, "Task11 vente réussie → sac vidé")

		local playerReset = track(fakePlayer("BpReset", 71006))
		local profileReset = buildProfile({
			CurrentBubbles = 2,
			PendingSellValue = 9,
		})
		DataService.SetProfileForTests(playerReset, profileReset)
		GameAnalyticsService.InitPlayer(playerReset, profileReset, false)
		resetCalls = {}
		local resetOk = BackpackService.ResetSession(playerReset)
		check(resetOk == true, "Task11 reset → ResetSession true")
		check(#resetCalls == 1, "Task11 reset → OnBackpackReset une fois")
		check(BackpackService.IsLocked(playerReset) ~= true, "Task11 reset → verrou libéré")
	end, debug.traceback)

	restoreAll()

	check(GameAnalyticsService.HasSession(sentinel) == true, "Task11 sentinel → session préservée après cleanup")
	GameAnalyticsService.FlushAndRemovePlayer(sentinel)
	DataService.ClearProfileForTests(sentinel)

	if not restoreOk then
		warn("[BackpackServiceTests] FAIL: suite error:", tostring(restoreErr))
		ok = false
		failCount += 1
	end

	print(string.format("[BackpackServiceTests] assertions: %d pass / %d fail", passCount, failCount))
	if ok then
		print("[BackpackServiceTests] OK")
	end
	return ok
end

return BackpackServiceTests
