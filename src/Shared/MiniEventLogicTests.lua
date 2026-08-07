--!strict
-- Tests unitaires MiniEventLogic (planificateur, Golden Wave, Color Rush, Giant Bubble).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MiniEventLogic = require(Shared.MiniEventLogic)
local MiniEventConfig = require(Shared.MiniEventConfig)

local MiniEventLogicTests = {}

function MiniEventLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[MiniEventLogicTests] FAIL:", msg)
			ok = false
		end
	end

	--------------------------------------------------------------------
	-- Planificateur
	--------------------------------------------------------------------
	check(MiniEventLogic.CanStartScheduler(false, 10, 1, 5) == false, "désactivé → pas de start")
	check(MiniEventLogic.CanStartScheduler(true, 0, 1, 0) == false, "0 joueurs → pas de start")
	check(MiniEventLogic.CanStartScheduler(true, 2, 1, 0) == false, "aucun joueur en zone bulles")
	check(MiniEventLogic.CanStartScheduler(true, 1, 1, 1) == true, "min joueurs + zone OK")

	check(MiniEventLogic.CanTransition("Idle", "Countdown") == true, "Idle→Countdown")
	check(MiniEventLogic.CanTransition("Countdown", "Active") == true, "Countdown→Active")
	check(MiniEventLogic.CanTransition("Active", "Cleanup") == true, "Active→Cleanup")
	check(MiniEventLogic.CanTransition("Cleanup", "Cooldown") == true, "Cleanup→Cooldown")
	check(MiniEventLogic.CanTransition("Cooldown", "Idle") == true, "Cooldown→Idle")
	check(MiniEventLogic.CanTransition("Active", "Countdown") == false, "pas de chevauchement Active→Countdown")
	check(MiniEventLogic.CanTransition("Active", "Active") == false, "pas de double Active")
	check(MiniEventLogic.CanTransition("Idle", "Active") == false, "pas de saut Idle→Active")

	local rng = Random.new(42)
	local last: string? = nil
	for _ = 1, 20 do
		local pick = MiniEventLogic.PickNextEvent(MiniEventConfig.ListEnabledEvents(), last, rng)
		check(pick ~= nil, "PickNextEvent retourne un type")
		if pick and last and #MiniEventConfig.ListEnabledEvents() > 1 then
			check(pick ~= last, "pas deux fois le même événement de suite")
		end
		last = pick
	end

	check(MiniEventLogic.PickNextEvent({}, nil, rng) == nil, "aucun événement activé → nil")
	check(MiniEventLogic.IsValidEventType("GoldenWave") == true, "GoldenWave valid")
	check(MiniEventLogic.IsValidEventType("NoSuch") == false, "type inconnu invalid")

	--------------------------------------------------------------------
	-- Golden Wave
	--------------------------------------------------------------------
	check(MiniEventLogic.IsNormalEligibleForGolden("Normal", true, nil) == true, "normale vivante admissible")
	check(MiniEventLogic.IsNormalEligibleForGolden("Rare", true, nil) == false, "spéciale non admissible")
	check(MiniEventLogic.IsNormalEligibleForGolden("Golden", true, nil) == false, "rareté Golden non admissible")
	check(MiniEventLogic.IsNormalEligibleForGolden("Normal", false, nil) == false, "éclatée non admissible")
	check(MiniEventLogic.IsNormalEligibleForGolden("Normal", true, "GoldenWave") == false, "déjà variante événement")
	check(MiniEventLogic.IsNormalEligibleForGolden("Normal", true, "ColorRush") == false, "autre variante exclue")

	local indices = MiniEventLogic.SelectTransformIndices(100, 0.18, Random.new(1))
	check(#indices >= 15 and #indices <= 25, "ratio ~18% sur 100 → ~18")

	check(
		MiniEventLogic.GetPopSellMultiplier("GoldenWave", true, "Normal", "GoldenWave", false)
			== MiniEventConfig.Events.GoldenWave.SellMultiplier,
		"multi doré correct"
	)
	check(MiniEventLogic.GetPopSellMultiplier("GoldenWave", true, "Normal", nil, false) == 1, "normale non dorée = ×1")
	check(MiniEventLogic.GetPopSellMultiplier("GoldenWave", true, "Rare", "GoldenWave", false) == 1, "spéciaux jamais × doré")
	check(MiniEventLogic.GetPopSellMultiplier("GoldenWave", false, "Normal", "GoldenWave", false) == 1, "inactif = ×1")

	--------------------------------------------------------------------
	-- Color Rush
	--------------------------------------------------------------------
	local target = MiniEventLogic.PickTargetColor({
		Color3.fromRGB(30, 95, 255),
		Color3.fromRGB(30, 95, 255),
		Color3.fromRGB(255, 70, 140),
	}, { Color3.fromRGB(255, 200, 45) }, 0.3, Random.new(2))
	check(target ~= nil, "couleur valide choisie")
	if target then
		check(
			MiniEventLogic.ColorsMatch(target, Color3.fromRGB(30, 95, 255), 0.2)
				or MiniEventLogic.ColorsMatch(target, Color3.fromRGB(255, 70, 140), 0.2),
			"cible parmi observées"
		)
	end

	check(MiniEventLogic.PickTargetColor({}, nil, 0.3, rng) == nil, "aucune couleur → nil")
	check(
		MiniEventLogic.GetPopSellMultiplier("ColorRush", true, "Normal", nil, true)
			== MiniEventConfig.Events.ColorRush.SellMultiplier,
		"bonne couleur = multi"
	)
	check(MiniEventLogic.GetPopSellMultiplier("ColorRush", true, "Normal", nil, false) == 1, "mauvaise couleur = ×1")
	check(MiniEventLogic.GetPopSellMultiplier("ColorRush", true, "Rare", nil, true) == 1, "spéciale exclue Color Rush")

	local reservedOnly = MiniEventLogic.PickTargetColor(
		{ Color3.fromRGB(255, 200, 45) },
		{ Color3.fromRGB(255, 200, 45) },
		0.3,
		rng
	)
	check(reservedOnly == nil, "couleur réservée absente du choix")

	--------------------------------------------------------------------
	-- Giant Bubble
	--------------------------------------------------------------------
	local req = MiniEventLogic.ComputeRequiredHits(30, 15, 2)
	check(req == 60, "Base 30 + 15×2 = 60")
	local fixed = MiniEventLogic.ComputeRequiredHits(30, 15, 4)
	check(fixed == 90, "cible fixe au lancement (4 joueurs)")
	check(MiniEventLogic.ComputeRequiredHits(30, 15, 0) == 30, "0 joueur → base seulement")

	check(MiniEventLogic.ContributionForTool("Epingle") == 2, "Pin contribution")
	check(MiniEventLogic.ContributionForTool("Marteau") == 3, "Hammer contribution")
	check(MiniEventLogic.ContributionForTool("Jump") == 1, "Jump contribution")
	check(MiniEventLogic.ContributionForTool("UnknownTool") == 1, "outil inconnu → 1")

	local ms = MiniEventLogic.CrossedMilestones(0.2, 0.5, { 0.25, 0.5, 0.75, 1.0 })
	check(#ms == 2 and ms[1] == 0.25 and ms[2] == 0.5, "jalons 25% et 50%")

	local bonus = MiniEventLogic.ComputeSellBonus(27, 500, 3, 40, 8, 120, true)
	check(bonus > 0, "bonus récompense > 0 pour participant")
	check(MiniEventLogic.ComputeSellBonus(2, 500, 3, 40, 8, 120, true) == 0, "sous min contribution → 0")
	check(MiniEventLogic.ComputeSellBonus(50, 500, 3, 40, 8, 120, false) == 0, "échec → 0")

	--------------------------------------------------------------------
	-- Réseau
	--------------------------------------------------------------------
	local payload = MiniEventLogic.BuildNetworkPayload(
		"Active",
		"GoldenWave",
		100,
		145,
		{ "ClassicZone" },
		{ mult = 5 },
		nil,
		nil,
		nil
	)
	check(payload.state == "Active", "payload state")
	check(payload.eventType == "GoldenWave", "payload eventType")
	check(payload.startTime == 100 and payload.endTime == 145, "timestamps cohérents")
	check(payload.endTime > payload.startTime, "end > start")

	--------------------------------------------------------------------
	-- UI / bonus coins (bandeau)
	--------------------------------------------------------------------
	check(MiniEventLogic.ComputeEventBonusCoins(50, 10) == 40, "bonus = with − without")
	check(MiniEventLogic.ComputeEventBonusCoins(10, 10) == 0, "pas de bonus si mult 1")
	check(MiniEventLogic.ComputeEventBonusCoins(8, 12) == 0, "jamais négatif")
	check(MiniEventLogic.HasPassCondition("GoldenWave") == false, "GoldenWave sans pass/fail")
	check(MiniEventLogic.HasPassCondition("ColorRush") == false, "ColorRush sans pass/fail")
	check(MiniEventLogic.HasPassCondition("GiantBubble") == true, "GiantBubble avec pass/fail")

	local uiPayload = MiniEventLogic.EnrichPayloadForUi(payload, {
		displayName = "GOLDEN WAVE",
		objectiveText = "Pop golden bubbles to earn extra Coins!",
		progressCurrent = 7,
		progressTarget = nil,
		bonusCoins = 280,
		hasPassCondition = false,
		completed = nil,
	})
	check(uiPayload.displayName == "GOLDEN WAVE", "ui displayName")
	check(uiPayload.objectiveText ~= nil and uiPayload.objectiveText ~= "", "ui objectiveText")
	check(uiPayload.progressCurrent == 7, "ui progressCurrent")
	check(uiPayload.progressTarget == nil, "ui progressTarget optionnel")
	check(uiPayload.bonusCoins == 280, "ui bonusCoins")
	check(uiPayload.hasPassCondition == false, "ui hasPassCondition")
	check(uiPayload.endTime == 145, "enrich conserve endTime")

	local endedUi = MiniEventLogic.EnrichPayloadForUi(
		MiniEventLogic.BuildNetworkPayload("Ended", "GiantBubble", 1, 2, {}, nil, nil, "Failed", nil),
		{
			displayName = "GIANT BUBBLE",
			objectiveText = "Hit the giant bubble together!",
			progressCurrent = 11,
			progressTarget = 15,
			bonusCoins = 0,
			hasPassCondition = true,
			completed = false,
		}
	)
	check(endedUi.completed == false, "Ended Failed → completed false")
	check(endedUi.progressTarget == 15, "Giant progressTarget")

	local ser = MiniEventLogic.SerializeColor(Color3.fromRGB(30, 95, 255))
	local des = MiniEventLogic.DeserializeColor(ser)
	check(des ~= nil and MiniEventLogic.ColorDistance(des :: Color3, Color3.fromRGB(30, 95, 255)) < 0.01, "serialize color")

	--------------------------------------------------------------------
	-- Config
	--------------------------------------------------------------------
	check(MiniEventConfig.IsParticipatingZone("ClassicZone") == true, "ClassicZone participante")
	check(MiniEventConfig.IsParticipatingZone("SummerZone") == true, "SummerZone participante")
	check(MiniEventConfig.IsParticipatingZone("Lobby") == false, "Lobby non participante")
	check(#MiniEventConfig.ListEnabledEvents() >= 1, "au moins un événement activé")
	local enabled = MiniEventConfig.ListEnabledEvents()
	local hasGiant = false
	for _, id in ipairs(enabled) do
		if id == "GiantBubble" then
			hasGiant = true
		end
	end
	check(hasGiant == false, "GiantBubble hors rotation active")
	check(MiniEventConfig.IsEventEnabled("GiantBubble") == false, "GiantBubble.Enabled = false")
	check(MiniEventConfig.IsEventEnabled("GoldenWave") == true, "GoldenWave actif")
	check(MiniEventConfig.IsEventEnabled("ColorRush") == true, "ColorRush actif")

	if ok then
		print("[MiniEventLogicTests] OK")
	end
	return ok
end

return MiniEventLogicTests
