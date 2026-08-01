--!strict
-- Tests ciblés Task11 : hooks analytics BackpackService (add/sell/reset).

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

	local addedCalls: { any } = {}
	local soldCalls: { any } = {}
	local resetCalls: { any } = {}

	local origAdded = GameAnalyticsService.OnBubblesAddedToBag
	local origSold = GameAnalyticsService.OnBackpackSold
	local origReset = GameAnalyticsService.OnBackpackReset
	local origAddCoins = DataService.AddCoins

	local function restoreHooks()
		GameAnalyticsService.OnBubblesAddedToBag = origAdded
		GameAnalyticsService.OnBackpackSold = origSold
		GameAnalyticsService.OnBackpackReset = origReset
		DataService.AddCoins = origAddCoins
	end

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
		-- AddBubbles refusé → aucun OnBubblesAddedToBag (hook BubbleService uniquement)
		local playerRefuse = fakePlayer("BpRefuse", 71001)
		local profileRefuse = buildProfile({
			CurrentBubbles = Config.Backpack.DefaultCapacity,
			PendingSellValue = 10,
		})
		DataService.SetProfileForTests(playerRefuse, profileRefuse)
		GameAnalyticsService.FlushAndRemovePlayer(playerRefuse)
		GameAnalyticsService.InitPlayer(playerRefuse, profileRefuse, false)
		addedCalls = {}
		local addedOk, err = BackpackService.AddBubbles(playerRefuse, 1, 5)
		check(addedOk == false, "Task11 AddBubbles refusé → false")
		check(err == BackpackService.ErrorCodes.BackpackFull, "Task11 AddBubbles refusé → BackpackFull")
		check(#addedCalls == 0, "Task11 AddBubbles refusé → aucun OnBubblesAddedToBag")
		check(BackpackService.IsLocked(playerRefuse) ~= true, "Task11 AddBubbles refusé → verrou libéré")
		GameAnalyticsService.FlushAndRemovePlayer(playerRefuse)
		DataService.ClearProfileForTests(playerRefuse)

		-- Ajout réussi : BackpackService n'appelle pas le hook ; simulation chemin BubbleService (1×)
		local playerAdd = fakePlayer("BpAdd", 71002)
		local profileAdd = buildProfile()
		DataService.SetProfileForTests(playerAdd, profileAdd)
		GameAnalyticsService.FlushAndRemovePlayer(playerAdd)
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
		GameAnalyticsService.FlushAndRemovePlayer(playerAdd)
		DataService.ClearProfileForTests(playerAdd)

		-- Vente vide → aucun OnBackpackSold
		local playerEmpty = fakePlayer("BpEmpty", 71003)
		local profileEmpty = buildProfile()
		DataService.SetProfileForTests(playerEmpty, profileEmpty)
		GameAnalyticsService.FlushAndRemovePlayer(playerEmpty)
		GameAnalyticsService.InitPlayer(playerEmpty, profileEmpty, false)
		soldCalls = {}
		pcall(function()
			BackpackService.Sell(playerEmpty)
		end)
		check(#soldCalls == 0, "Task11 vente vide → aucun OnBackpackSold")
		GameAnalyticsService.FlushAndRemovePlayer(playerEmpty)
		DataService.ClearProfileForTests(playerEmpty)

		-- AddCoins false → aucun OnBackpackSold
		local playerCredit = fakePlayer("BpCredit", 71004)
		local profileCredit = buildProfile({
			CurrentBubbles = 3,
			PendingSellValue = 15,
		})
		DataService.SetProfileForTests(playerCredit, profileCredit)
		GameAnalyticsService.FlushAndRemovePlayer(playerCredit)
		GameAnalyticsService.InitPlayer(playerCredit, profileCredit, false)
		soldCalls = {}
		DataService.AddCoins = function()
			return false, nil
		end
		local creditSellOk, creditSold, _creditEarned, creditErr = pcall(function()
			return BackpackService.Sell(playerCredit)
		end)
		DataService.AddCoins = origAddCoins
		check(creditSellOk, "Task11 AddCoins false → Sell ne throw pas")
		check(creditSold == nil and creditErr == "credit_failed", "Task11 AddCoins false → credit_failed")
		check(#soldCalls == 0, "Task11 AddCoins false → aucun OnBackpackSold")
		check(profileCredit.CurrentBubbles == 3, "Task11 AddCoins false → sac intact")
		GameAnalyticsService.FlushAndRemovePlayer(playerCredit)
		DataService.ClearProfileForTests(playerCredit)

		-- Vente réussie → OnBackpackSold une fois avec endingBalance
		local playerSale = fakePlayer("BpSale", 71005)
		local profileSale = buildProfile({
			Coins = 100,
			CurrentBubbles = 4,
			PendingSellValue = 30,
		})
		DataService.SetProfileForTests(playerSale, profileSale)
		GameAnalyticsService.FlushAndRemovePlayer(playerSale)
		GameAnalyticsService.InitPlayer(playerSale, profileSale, false)
		soldCalls = {}
		pcall(function()
			BackpackService.Sell(playerSale)
		end)
		check(#soldCalls == 1, "Task11 vente réussie → OnBackpackSold une fois")
		check(
			soldCalls[1] ~= nil
				and soldCalls[1].ctx ~= nil
				and soldCalls[1].ctx.earned == 30
				and soldCalls[1].ctx.endingBalance == 130,
			"Task11 vente réussie → endingBalance correct"
		)
		check(profileSale.CurrentBubbles == 0 and profileSale.PendingSellValue == 0, "Task11 vente réussie → sac vidé")
		GameAnalyticsService.FlushAndRemovePlayer(playerSale)
		DataService.ClearProfileForTests(playerSale)

		-- Reset → OnBackpackReset une fois
		local playerReset = fakePlayer("BpReset", 71006)
		local profileReset = buildProfile({
			CurrentBubbles = 2,
			PendingSellValue = 9,
		})
		DataService.SetProfileForTests(playerReset, profileReset)
		GameAnalyticsService.FlushAndRemovePlayer(playerReset)
		GameAnalyticsService.InitPlayer(playerReset, profileReset, false)
		resetCalls = {}
		local resetOk = BackpackService.ResetSession(playerReset)
		check(resetOk == true, "Task11 reset → ResetSession true")
		check(#resetCalls == 1, "Task11 reset → OnBackpackReset une fois")
		check(BackpackService.IsLocked(playerReset) ~= true, "Task11 reset → verrou libéré")
		GameAnalyticsService.FlushAndRemovePlayer(playerReset)
		DataService.ClearProfileForTests(playerReset)
	end, debug.traceback)

	restoreHooks()

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
