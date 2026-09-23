--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local TentChestConfig = require(Shared.TentChestConfig)

local DataService = require(script.Parent.DataService)
local TentChestService = require(script.Parent.TentChestService)

local TentChestServiceTests = {}

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
		__loaded = true,
		__dirty = false,
	}
	if overrides then
		for key, value in pairs(overrides) do
			profile[key] = value
		end
	end
	return profile
end

function TentChestServiceTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[TentChestServiceTests] FAIL:", msg)
			ok = false
		end
	end

	local tracked: { any } = {}
	local function track(player: any): any
		table.insert(tracked, player)
		return player
	end

	local bronze = TentChestConfig.Chests[1]
	local playerOk = track(fakePlayer("TentWin", 83001))
	local profileOk = buildProfile({ Coins = bronze.Cost + 10 })
	DataService.SetProfileForTests(playerOk, profileOk)
	local opened, reason = TentChestService.TryOpenForTests(playerOk, "Bronze", {
		skipDistance = true,
		roll01 = 0.999,
	})
	check(opened == true and reason == "ok", "ouverture jackpot réussie")
	check(profileOk.Coins == 10 + bronze.Prizes[#bronze.Prizes].Coins, "coût débité puis jackpot crédité")
	check(profileOk.ChestsOpened == 1, "ChestsOpened +1")

	local playerPoor = track(fakePlayer("TentPoor", 83002))
	local profilePoor = buildProfile({ Coins = 10 })
	DataService.SetProfileForTests(playerPoor, profilePoor)
	local denied, denyReason = TentChestService.TryOpenForTests(playerPoor, "Bronze", {
		skipDistance = true,
		roll01 = 0,
	})
	check(denied == false and denyReason == "coins", "solde insuffisant refusé")
	check(profilePoor.Coins == 10, "solde inchangé si refus")

	local playerLoss = track(fakePlayer("TentLoss", 83003))
	local profileLoss = buildProfile({ Coins = bronze.Cost })
	DataService.SetProfileForTests(playerLoss, profileLoss)
	local lost = TentChestService.TryOpenForTests(playerLoss, "Bronze", {
		skipDistance = true,
		roll01 = 0,
	})
	check(lost == true, "perte possible")
	check(profileLoss.Coins == bronze.Prizes[1].Coins, "lot inférieur au coût crédité")
	check(profileLoss.Coins < bronze.Cost, "le joueur termine sous le montant payé")

	local unknown = TentChestService.TryOpenForTests(playerOk, "Nope", { skipDistance = true })
	check(unknown == false, "id inconnu refusé")

	for _, player in ipairs(tracked) do
		DataService.ClearProfileForTests(player)
	end

	if ok then
		print("[TentChestServiceTests] ALL PASS")
	else
		warn("[TentChestServiceTests] SOME FAILED")
	end
	return ok
end

return TentChestServiceTests
