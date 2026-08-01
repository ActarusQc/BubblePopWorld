--!strict
-- Tests purs de la machine à états d'onboarding (aucune dépendance Roblox métier).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local OnboardingConfig = require(Shared.OnboardingConfig)

local OnboardingConfigTests = {}

local function baseSnap(overrides: { [string]: any }?): OnboardingConfig.Snapshot
	local snap: OnboardingConfig.Snapshot = {
		OnboardingStarted = true,
		OnboardingCompleted = false,
		PoppedFirstBubble = false,
		SoldFirstBackpack = false,
		PurchasedFirstUpgrade = false,
		CurrentBubbles = 0,
		BackpackCapacity = 25,
		Coins = 0,
		CheapestUpgradeCost = 250,
	}
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			(snap :: any)[key] = value
		end
	end
	return snap
end

function OnboardingConfigTests.Run(): boolean
	local failed = 0
	local passed = 0

	local function check(cond: boolean, msg: string)
		if cond then
			passed += 1
			print(("  PASS  %s"):format(msg))
		else
			failed += 1
			warn(("[OnboardingConfigTests] FAIL: %s"):format(msg))
		end
	end

	local O = OnboardingConfig.Objective

	-- 1. Nouveau joueur avant premier pop
	check(OnboardingConfig.ResolveObjective(baseSnap(nil)) == O.Pop, "1 new player before first pop → Pop")

	-- 2. Premier pop effectué, sac vide
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			CurrentBubbles = 0,
			BackpackCapacity = 25,
		})) == O.None,
		"2 after first pop empty bag → None"
	)

	-- 3. Sac partiellement rempli
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			CurrentBubbles = 24,
			BackpackCapacity = 25,
		})) == O.None,
		"3 partially filled bag → None"
	)

	-- 4. Sac plein
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			CurrentBubbles = 25,
			BackpackCapacity = 25,
		})) == O.Sell,
		"4 full bag → Sell"
	)

	-- 5. Sac au-delà de la capacité
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			CurrentBubbles = 30,
			BackpackCapacity = 25,
		})) == O.Sell,
		"5 over capacity → Sell"
	)

	-- 6. Première vente, solde insuffisant
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			SoldFirstBackpack = true,
			Coins = 100,
			CheapestUpgradeCost = 250,
		})) == O.None,
		"6 sold but not enough coins → None"
	)

	-- 7. Première vente, solde suffisant
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			SoldFirstBackpack = true,
			Coins = 250,
			CheapestUpgradeCost = 250,
		})) == O.Shop,
		"7 sold with enough coins → Shop"
	)

	-- 8. Solde très supérieur
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			SoldFirstBackpack = true,
			Coins = 9999,
			CheapestUpgradeCost = 250,
		})) == O.Shop,
		"8 sold with surplus coins → Shop"
	)

	-- 9. Premier achat effectué
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			SoldFirstBackpack = true,
			PurchasedFirstUpgrade = true,
			Coins = 9999,
			CheapestUpgradeCost = 250,
		})) == O.None,
		"9 purchased first upgrade → None"
	)

	-- 10. Onboarding terminé
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			OnboardingCompleted = true,
			PoppedFirstBubble = true,
			SoldFirstBackpack = true,
			PurchasedFirstUpgrade = true,
		})) == O.None,
		"10 onboarding completed → None"
	)

	-- 11. Profil vétéran
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			OnboardingStarted = false,
		})) == O.None,
		"11 veteran OnboardingStarted=false → None"
	)

	-- 12. Reconnexion pendant l'onboarding (sac plein)
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			SoldFirstBackpack = false,
			CurrentBubbles = 25,
			BackpackCapacity = 25,
		})) == O.Sell,
		"12 reconnect mid-onboarding full bag → Sell"
	)

	-- 13. Analytics incomplet mais réconcilié (Started=true, Onboarding vide)
	check(
		OnboardingConfig.ResolveObjective({
			OnboardingStarted = true,
			OnboardingCompleted = false,
		}) == O.Pop,
		"13 incomplete analytics reconciled → Pop"
	)

	-- 14. Snapshot nil
	check(OnboardingConfig.ResolveObjective(nil) == O.None, "14 nil snapshot → None")

	-- 15. Capacité 0 : jamais Sell
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			CurrentBubbles = 0,
			BackpackCapacity = 0,
		})) == O.None,
		"15 capacity 0 → None (never Sell)"
	)

	-- 16. Coût introuvable
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			SoldFirstBackpack = true,
			Coins = 9999,
			CheapestUpgradeCost = -1,
		})) == O.None,
		"16 missing upgrade cost → None"
	)

	-- 17. NaN / infinis
	local nan = (0 / 0)
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			SoldFirstBackpack = true,
			Coins = nan,
			CheapestUpgradeCost = 250,
		})) == O.None,
		"17 NaN coins → None"
	)
	check(
		OnboardingConfig.ResolveObjective(baseSnap({
			PoppedFirstBubble = true,
			CurrentBubbles = 25,
			BackpackCapacity = math.huge,
		})) == O.None,
		"17 infinite capacity → None"
	)

	-- 18. ShouldSpawnInGameRoom
	check(OnboardingConfig.ShouldSpawnInGameRoom(baseSnap(nil)) == true, "18a spawn GameRoom for new before pop")
	check(
		OnboardingConfig.ShouldSpawnInGameRoom(baseSnap({
			PoppedFirstBubble = true,
		})) == false,
		"18b no GameRoom spawn after first pop"
	)
	check(
		OnboardingConfig.ShouldSpawnInGameRoom(baseSnap({
			PurchasedFirstUpgrade = true,
		})) == false,
		"18c no GameRoom spawn after purchase"
	)
	check(
		OnboardingConfig.ShouldSpawnInGameRoom(baseSnap({
			OnboardingStarted = false,
		})) == false,
		"18d no GameRoom spawn for veteran"
	)
	check(OnboardingConfig.ShouldSpawnInGameRoom(nil) == false, "18e nil snapshot → no GameRoom spawn")

	-- Profil indisponible / deadline : traité comme snapshot nil côté service
	check(OnboardingConfig.ShouldSpawnInGameRoom(nil) == false, "unavailable profile → lobby fallback")

	print(("[OnboardingConfigTests] %d passed, %d failed"):format(passed, failed))
	if failed == 0 then
		print("[OnboardingConfigTests] OK")
		return true
	end
	return false
end

return OnboardingConfigTests
