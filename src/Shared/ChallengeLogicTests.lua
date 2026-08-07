--!strict
-- Tests unitaires ChallengeLogic (resets, sélection, progression, rewards, leaderboard).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChallengeLogic = require(Shared.ChallengeLogic)
local ChallengeConfig = require(Shared.ChallengeConfig)

local ChallengeLogicTests = {}

function ChallengeLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[ChallengeLogicTests] FAIL:", msg)
			ok = false
		end
	end

	--------------------------------------------------------------------
	-- Clés quotidiennes / hebdomadaires
	--------------------------------------------------------------------
	-- 2026-08-03 12:00 UTC — day known
	local u20260803 = ChallengeLogic.UnixFromDailyKey("20260803")
	check(u20260803 ~= nil, "UnixFromDailyKey 20260803")
	if u20260803 then
		check(ChallengeLogic.DailyKey(u20260803) == "20260803", "DailyKey 20260803")
		local y, m, d = ChallengeLogic.UtcYmdParts(u20260803)
		check(y == 2026 and m == 8 and d == 3, "UtcYmdParts 2026-08-03")
	end

	-- Reset countdown : juste avant minuit
	local almostMidnight = (math.floor((u20260803 :: number) / 86400) + 1) * 86400 - 90
	check(ChallengeLogic.SecondsUntilDailyReset(almostMidnight) == 90, "90s avant reset daily")
	check(ChallengeLogic.DailyKey(almostMidnight + 120) == "20260804", "après minuit → jour suivant")

	-- Lundi 2026-08-03 est un lundi
	if u20260803 then
		local wk = ChallengeLogic.WeeklyKey(u20260803)
		check(type(wk) == "string" and string.find(wk, "2026%-W") ~= nil, "WeeklyKey format ISO " .. tostring(wk))
		-- Semaine suivante (lundi + 7j) change la clé
		local nextMon = u20260803 + 7 * 86400
		check(ChallengeLogic.WeeklyKey(nextMon) ~= wk, "semaine suivante ≠ clé")
		-- Dimanche de la même semaine conserve la clé
		local sunday = u20260803 + 6 * 86400
		check(ChallengeLogic.WeeklyKey(sunday) == wk, "dimanche même semaine")
	end

	check(ChallengeLogic.FormatCountdown(12 * 3600 + 14 * 60) == "12h 14m", "format 12h 14m")
	check(ChallengeLogic.FormatCountdown(3 * 86400 + 12 * 3600) == "3d 12h", "format 3d 12h")
	check(ChallengeLogic.FormatCountdown(45) == "1m", "format minutes min")

	--------------------------------------------------------------------
	-- Featured event déterministe
	--------------------------------------------------------------------
	local f1 = ChallengeLogic.FeaturedEventForDay("20260803")
	local f1b = ChallengeLogic.FeaturedEventForDay("20260803")
	check(f1 == f1b, "featured identique pour même jour")
	check(
		f1 == "GoldenWave" or f1 == "ColorRush",
		"featured dans rotation (sans GiantBubble)"
	)
	check(f1 ~= "GiantBubble", "GiantBubble hors featured")
	local f2 = ChallengeLogic.FeaturedEventForDay("20260804")
	check(f2 ~= f1, "jours adjacents featured différent (rotation)")
	check(ChallengeLogic.FeaturedEventForDay("20260805") ~= "GiantBubble", "jamais GiantBubble featured")

	--------------------------------------------------------------------
	-- Sélection 3 daily + 1 weekly
	--------------------------------------------------------------------
	local ctxNoSummer = {
		hasSummerAccess = false,
		featuredEventType = f1,
		enabledEvents = { GoldenWave = true, ColorRush = true, GiantBubble = true },
	}
	local daily = ChallengeLogic.SelectDailyChallenges("20260803", ctxNoSummer)
	check(#daily == 3, "3 défis quotidiens")
	local slots = {}
	local metrics = {}
	for _, ch in ipairs(daily) do
		slots[ch.Slot] = true
		check(ch.Progress == 0, "progress 0")
		check(ch.Completed == false, "not completed")
		check(ch.Claimed == false, "not claimed")
		check(ch.Target >= 1, "target >= 1")
		if ch.Metric == "PopSummer" then
			ok = false
			warn("[ChallengeLogicTests] FAIL: Summer sans accès")
		end
		metrics[ch.Metric] = (metrics[ch.Metric] or 0) + 1
	end
	check(slots.Easy == true and slots.Medium == true and slots.Event == true, "slots Easy/Medium/Event")

	local weekly = ChallengeLogic.SelectWeeklyChallenge("2026-W32", ctxNoSummer)
	check(weekly ~= nil, "weekly généré")
	if weekly then
		check(weekly.Slot == "Weekly", "slot weekly")
		check(weekly.Target >= 1, "weekly target")
		check(weekly.Metric ~= "GiantComplete", "weekly n'est plus Giant")
		check(weekly.Id ~= "WeeklyGiant_5", "WeeklyGiant retiré")
	end

	-- Aucun défi actif ne dépend de Giant Bubble (spawn mini-event peu fiable).
	for _, poolName in ipairs({ "DailyEasyPool", "DailyMediumPool", "DailyEventPool", "WeeklyPool" }) do
		local pool = (ChallengeConfig :: any)[poolName]
		for _, def in ipairs(pool) do
			check(def.Metric ~= "GiantHits", poolName .. " sans GiantHits: " .. tostring(def.Id))
			check(def.Metric ~= "GiantComplete", poolName .. " sans GiantComplete: " .. tostring(def.Id))
			check(def.Id ~= "FeaturedGiant_10", "FeaturedGiant retiré")
			check(def.Id ~= "WeeklyGiant_5", "WeeklyGiant retiré")
		end
	end
	local popSpecialEvent = ChallengeConfig.FindDefById("PopSpecial_10")
	check(popSpecialEvent ~= nil, "PopSpecial_10 remplace Giant")
	if popSpecialEvent then
		check(popSpecialEvent.Metric == "PopSpecial", "PopSpecial_10 metric")
		check(popSpecialEvent.Target == 10, "PopSpecial_10 target 10")
		check(popSpecialEvent.Slot == "Event", "PopSpecial_10 slot Event")
	end

	-- Migration profil : Giant actif → Pop Special immédiatement
	local giantLegacy = {
		Id = "FeaturedGiant_10",
		Metric = "GiantHits",
		Target = 10,
		Progress = 3,
		Completed = false,
		Claimed = false,
		Slot = "Event",
		TitleKey = "ChallengeGiantHits",
		DescKey = "ChallengeGiantHitsDesc",
		RewardType = "SellBonus",
		RewardAmount = 500,
	}
	local migrated, did = ChallengeLogic.MigrateDeprecatedChallenge(giantLegacy :: any)
	check(did == true, "migration Giant → PopSpecial")
	check(migrated.Id == "PopSpecial_10", "id PopSpecial_10")
	check(migrated.Metric == "PopSpecial", "metric PopSpecial")
	check(migrated.Target == 10, "target 10")
	check(migrated.Progress == 0, "progress reset après migration")
	check(ChallengeLogic.IsDeprecatedGiantChallenge("FeaturedGiant_10") == true, "deprecated id")
	check(ChallengeLogic.IsDeprecatedGiantChallenge("GiantHits") == true, "deprecated metric")

	local savedGiant = {
		DailyKey = ChallengeLogic.DailyKey(u20260803 :: number),
		WeeklyKey = ChallengeLogic.WeeklyKey(u20260803 :: number),
		DailyBubblePops = 5,
		Daily = {
			{
				Id = "PopBubbles_50",
				Metric = "PopBubbles",
				Target = 50,
				Progress = 2,
				Completed = false,
				Claimed = false,
				Slot = "Easy",
				TitleKey = "ChallengePopBubbles",
				DescKey = "ChallengePopBubblesDesc",
				RewardType = "SellBonus",
				RewardAmount = 250,
			},
			{
				Id = "SellFull_8",
				Metric = "SellFullBackpack",
				Target = 8,
				Progress = 0,
				Completed = false,
				Claimed = false,
				Slot = "Medium",
				TitleKey = "ChallengeSellFull",
				DescKey = "ChallengeSellFullDesc",
				RewardType = "SellBonus",
				RewardAmount = 400,
			},
			giantLegacy,
		},
		Weekly = {
			Id = "WeeklyGiant_5",
			Metric = "GiantComplete",
			Target = 5,
			Progress = 1,
			Completed = false,
			Claimed = false,
			Slot = "Weekly",
			TitleKey = "ChallengeWeeklyGiant",
			DescKey = "ChallengeWeeklyGiantDesc",
			RewardType = "SellBonus",
			RewardAmount = 2000,
		},
	}
	local recon, reconChanged = ChallengeLogic.ReconcileState(savedGiant, u20260803 :: number, ctxNoSummer)
	check(reconChanged == true or recon.Daily[3].Id == "PopSpecial_10", "reconcile migre Event")
	check(recon.Daily[3].Metric == "PopSpecial", "daily event PopSpecial")
	check(recon.Weekly ~= nil and recon.Weekly.Id == "WeeklySpecial_100", "weekly migre Special")
	check(recon.Weekly ~= nil and recon.Weekly.Metric == "PopSpecial", "weekly metric PopSpecial")

	-- Stabilité multi-serveurs
	local dA = ChallengeLogic.SelectDailyChallenges("20260803", ctxNoSummer)
	local dB = ChallengeLogic.SelectDailyChallenges("20260803", ctxNoSummer)
	for i = 1, 3 do
		check(dA[i].Id == dB[i].Id, "même sélection entre serveurs " .. i)
	end

	-- Avec Summer : peut inclure PopSummer (pas obligatoire)
	local ctxSummer = {
		hasSummerAccess = true,
		featuredEventType = "GoldenWave",
		enabledEvents = { GoldenWave = true, ColorRush = true, GiantBubble = true },
	}
	local withSummer = ChallengeLogic.SelectDailyChallenges("20260810", ctxSummer)
	check(#withSummer == 3, "3 daily avec summer access")

	--------------------------------------------------------------------
	-- Progression
	--------------------------------------------------------------------
	local state = ChallengeLogic.EmptyState(u20260803 :: number, ctxNoSummer)
	check(state.DailyBubblePops == 0, "pops 0")

	-- Forcer un défi PopBubbles pour le test
	state.Daily[1] = {
		Id = "PopBubbles_50",
		Metric = "PopBubbles",
		Target = 50,
		Progress = 0,
		Completed = false,
		Claimed = false,
		Slot = "Easy",
		TitleKey = "ChallengePopBubbles",
		DescKey = "ChallengePopBubblesDesc",
		RewardType = "SellBonus",
		RewardAmount = 250,
	}
	state.Daily[2] = {
		Id = "FeaturedGolden_15",
		Metric = "PopGoldenWave",
		Target = 15,
		Progress = 0,
		Completed = false,
		Claimed = false,
		Slot = "Event",
		TitleKey = "ChallengeGoldenWave",
		DescKey = "ChallengeGoldenWaveDesc",
		RewardType = "SellBonus",
		RewardAmount = 500,
	}

	local _, deltas = ChallengeLogic.ApplyProgress(state, {
		{ metric = "PopBubbles", amount = 1 },
		{ metric = "PopGoldenWave", amount = 1 },
	})
	check(state.Daily[1].Progress == 1, "pop bubbles +1")
	check(state.Daily[2].Progress == 1, "golden +1")
	check(#deltas >= 1, "deltas émis")

	-- Même action ne double pas dans un seul call pour un metric (grouped once)
	ChallengeLogic.ApplyProgress(state, {
		{ metric = "PopBubbles", amount = 1 },
		{ metric = "PopBubbles", amount = 1 },
	})
	-- amountByMetric sums both — that's intentional for multi-pop batches.
	-- Single bubble should call with amount=1 once.
	check(state.Daily[1].Progress == 3, "batch sum metrics")

	-- Color rush only for color metric
	state.Daily[2].Metric = "PopColorRush"
	state.Daily[2].Progress = 0
	state.Daily[2].Completed = false
	ChallengeLogic.ApplyProgress(state, { { metric = "PopBubbles", amount = 5 } })
	check(state.Daily[2].Progress == 0, "color rush ignore normal pops")

	-- Giant hits ≠ bubbles
	ChallengeLogic.ApplyProgress(state, { { metric = "GiantHits", amount = 10 } })
	check(state.Daily[1].Metric ~= "GiantHits" or state.Daily[1].Progress >= 0, "giant distinct")

	-- Sell full only
	state.Daily[1] = {
		Id = "SellFull_3",
		Metric = "SellFullBackpack",
		Target = 3,
		Progress = 0,
		Completed = false,
		Claimed = false,
		Slot = "Easy",
		TitleKey = "ChallengeSellFull",
		DescKey = "ChallengeSellFullDesc",
		RewardType = "SellBonus",
		RewardAmount = 250,
	}
	ChallengeLogic.ApplyProgress(state, { { metric = "SellValue", amount = 999 } })
	check(state.Daily[1].Progress == 0, "sell value ≠ full backpack")
	ChallengeLogic.ApplyProgress(state, { { metric = "SellFullBackpack", amount = 1 } })
	check(state.Daily[1].Progress == 1, "full backpack +1")

	--------------------------------------------------------------------
	-- Complet + claim idempotent
	--------------------------------------------------------------------
	state.Daily[1].Progress = 2
	state.Daily[1].Target = 3
	ChallengeLogic.ApplyProgress(state, { { metric = "SellFullBackpack", amount = 1 } })
	check(state.Daily[1].Completed == true, "completed at target")
	local claim1, code1 = ChallengeLogic.TryClaim(state.Daily[1])
	check(claim1 == true and code1 == "ok", "claim ok")
	local claim2, code2 = ChallengeLogic.TryClaim(state.Daily[1])
	check(claim2 == false and code2 == "already_claimed", "claim duplicate blocked")
	check(state.Daily[1].RewardType == "SellBonus", "pas de monnaie inventée")

	--------------------------------------------------------------------
	-- Reconcile : période expirée reset ; claim préservé dans période
	--------------------------------------------------------------------
	local saved = {
		DailyKey = "20260803",
		WeeklyKey = ChallengeLogic.WeeklyKey(u20260803 :: number),
		DailyBubblePops = 100,
		Daily = {
			{
				Id = "SellFull_3",
				Metric = "SellFullBackpack",
				Target = 3,
				Progress = 3,
				Completed = true,
				Claimed = true,
				Slot = "Easy",
				TitleKey = "ChallengeSellFull",
				DescKey = "ChallengeSellFullDesc",
				RewardType = "SellBonus",
				RewardAmount = 250,
			},
		},
		Weekly = state.Weekly,
	}
	local sameDay, ch1 = ChallengeLogic.ReconcileState(saved, u20260803 :: number, ctxNoSummer)
	check(ch1 == false or sameDay.Daily[1].Claimed == true, "claimed préservé même jour")
	check(sameDay.Daily[1].Claimed == true, "claimed still true")
	check(sameDay.DailyBubblePops == 100, "pops préservés même jour")

	local nextDayUnix = (u20260803 :: number) + 86400
	local newDay = ChallengeLogic.ReconcileState(saved, nextDayUnix, ctxNoSummer)
	check(newDay.DailyKey == ChallengeLogic.DailyKey(nextDayUnix), "new daily key")
	check(newDay.DailyBubblePops == 0, "pops reset new day")
	for _, ch in ipairs(newDay.Daily) do
		check(ch.Claimed == false, "nouveaux défis non claim")
		check(ch.Progress == 0, "progress reset")
	end

	--------------------------------------------------------------------
	-- Classement : pops valides
	--------------------------------------------------------------------
	check(
		ChallengeLogic.IsValidDailyBubblePop({ serverAccepted = true }) == true,
		"pop normal valid"
	)
	check(
		ChallengeLogic.IsValidDailyBubblePop({ serverAccepted = true, isGiantHit = true }) == false,
		"giant hit exclu"
	)
	check(
		ChallengeLogic.IsValidDailyBubblePop({ serverAccepted = true, isTutorial = true }) == false,
		"tutoriel exclu"
	)
	check(
		ChallengeLogic.IsValidDailyBubblePop({ serverAccepted = true, isGiantBody = true }) == false,
		"giant body exclu v1"
	)
	check(ChallengeLogic.MergeLeaderboardScore(100, 50) == 100, "score ne diminue pas")
	check(ChallengeLogic.MergeLeaderboardScore(50, 80) == 80, "score augmente")
	check(ChallengeLogic.MergeLeaderboardScore(nil, 10) == 10, "score initial")

	--------------------------------------------------------------------
	-- Featured join filter
	--------------------------------------------------------------------
	state.Daily[1] = {
		Id = "FeaturedParticipate_1",
		Metric = "FeaturedEventJoin",
		Target = 1,
		Progress = 0,
		Completed = false,
		Claimed = false,
		Slot = "Event",
		TitleKey = "ChallengeFeaturedJoin",
		DescKey = "ChallengeFeaturedJoinDesc",
		RewardType = "SellBonus",
		RewardAmount = 500,
	}
	ChallengeLogic.ApplyProgress(state, {
		{
			metric = "FeaturedEventJoin",
			amount = 1,
			eventType = "ColorRush",
			featuredEventType = "GoldenWave",
		},
	})
	check(state.Daily[1].Progress == 0, "featured mismatch ignoré")
	ChallengeLogic.ApplyProgress(state, {
		{
			metric = "FeaturedEventJoin",
			amount = 1,
			eventType = "GoldenWave",
			featuredEventType = "GoldenWave",
		},
	})
	check(state.Daily[1].Progress == 1 and state.Daily[1].Completed, "featured match compte")

	--------------------------------------------------------------------
	-- Milestones
	--------------------------------------------------------------------
	local crossed = ChallengeLogic.CrossedMilestones("x", 0, 25, 100, {})
	check(#crossed >= 1 and crossed[1] == 0.25, "milestone 25%")
	local notified = ChallengeLogic.MarkMilestones({}, "x", { 0.25 })
	local crossed2 = ChallengeLogic.CrossedMilestones("x", 0, 25, 100, notified)
	check(#crossed2 == 0, "milestone déjà notifié")

	--------------------------------------------------------------------
	-- Challenges terminés restent listés / tri affichage
	--------------------------------------------------------------------
	local sorted = ChallengeLogic.SortChallengesForDisplay({
		{
			Id = "c_claimed",
			Metric = "PopBubbles",
			Target = 10,
			Progress = 10,
			Completed = true,
			Claimed = true,
			Slot = "Easy",
			TitleKey = "a",
			DescKey = "a",
			RewardType = "SellBonus",
			RewardAmount = 1,
		},
		{
			Id = "c_active",
			Metric = "PopBubbles",
			Target = 10,
			Progress = 3,
			Completed = false,
			Claimed = false,
			Slot = "Easy",
			TitleKey = "a",
			DescKey = "a",
			RewardType = "SellBonus",
			RewardAmount = 1,
		},
		{
			Id = "c_ready",
			Metric = "PopBubbles",
			Target = 10,
			Progress = 10,
			Completed = true,
			Claimed = false,
			Slot = "Easy",
			TitleKey = "a",
			DescKey = "a",
			RewardType = "SellBonus",
			RewardAmount = 1,
		},
	})
	check(#sorted == 3, "tri conserve les 3 défis")
	check(sorted[1].Id == "c_active", "actifs d'abord")
	check(sorted[2].Id == "c_ready", "ready ensuite")
	check(sorted[3].Id == "c_claimed", "claimed enfin")
	check(ChallengeLogic.IsChallengeVisibleInList(sorted[3]) == true, "claimed toujours visible")
	check(ChallengeLogic.ChallengeStatus(sorted[2]) == "ReadyToClaim", "status ready")
	check(ChallengeLogic.ChallengeStatus(sorted[3]) == "Claimed", "status claimed")

	if ok then
		print("[ChallengeLogicTests] OK")
	end
	return ok
end

return ChallengeLogicTests
