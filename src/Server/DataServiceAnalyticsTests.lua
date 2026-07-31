--!strict
-- Tests analytics profil DataService (Task 3) : isNewProfile, reconcile, AddCoins tuple.

local DataService = require(script.Parent.DataService)

local DataServiceAnalyticsTests = {}

local function fakePlayer(name: string, userId: number): any
	return { Name = name, UserId = userId }
end

function DataServiceAnalyticsTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[DataServiceAnalyticsTests] FAIL:", msg)
			ok = false
		else
			print("[DataServiceAnalyticsTests] PASS:", msg)
		end
	end

	check(
		DataService.IsNewProfileFromLoadResult(true, nil) == true,
		"isNewProfile : GetAsync ok sans table sauvegardée"
	)
	check(
		DataService.IsNewProfileFromLoadResult(true, { Coins = 1 }) == false,
		"isNewProfile : profil existant"
	)
	check(
		DataService.IsNewProfileFromLoadResult(false, nil) == false,
		"isNewProfile : échec DataStore n'est pas nouveau"
	)
	check(
		DataService.IsNewProfileFromLoadResult(false, { Coins = 1 }) == false,
		"isNewProfile : échec DataStore avec saved ignoré"
	)

	local oldProfile = DataService.ReconcileProfileForTests({ Coins = 10 })
	check(type(oldProfile.Analytics) == "table", "reconcile : Analytics présent sur ancien profil")
	check(oldProfile.Analytics.OnboardingStarted == false, "reconcile : OnboardingStarted false par défaut")
	check(oldProfile.__isNewProfile == false, "reconcile : ancien profil pas isNewProfile")

	local newProfile = DataService.ReconcileProfileForTests(nil, true)
	check(newProfile.__isNewProfile == true, "reconcile : nil saved avec ok=true → isNewProfile")
	check(newProfile.Analytics.OnboardingStarted == false, "reconcile : template OnboardingStarted false")

	local failedLoad = DataService.ReconcileProfileForTests(nil, false)
	check(failedLoad.__isNewProfile == false, "reconcile : échec load → isNewProfile false")

	local player = fakePlayer("CoinTest", 999)
	DataService.SetProfileForTests(player, { Coins = 50 })
	local credited, endingBalance = DataService.AddCoins(player, 50, "Chest")
	check(credited == true and endingBalance == 100, "AddCoins retourne true et solde final")
	local badCredit, noBalance = DataService.AddCoins(player, 0, "Chest")
	check(badCredit == false and noBalance == nil, "AddCoins montant nul retourne false, nil")
	DataService.ClearProfileForTests(player)

	if ok then
		print("[DataServiceAnalyticsTests] OK")
	end
	return ok
end

return DataServiceAnalyticsTests
