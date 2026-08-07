--!strict
-- Tests purs : FormatCompact, WeeklyBest semaine, top entries, merge score.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LeaderboardUtil = require(Shared.LeaderboardUtil)
local WeeklyBestLogic = require(Shared.WeeklyBestLogic)
local ChallengeLogic = require(Shared.ChallengeLogic)

local WeeklyBestLogicTests = {}

function WeeklyBestLogicTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[WeeklyBestLogicTests] FAIL:", msg)
		end
	end

	--------------------------------------------------------------------
	-- FormatCompact
	--------------------------------------------------------------------
	check(LeaderboardUtil.FormatCompact(0) == "0", "compact 0")
	check(LeaderboardUtil.FormatCompact(999) == "999", "compact <1K")
	check(LeaderboardUtil.FormatCompact(1200) == "1.2K", "compact 1.2K")
	check(LeaderboardUtil.FormatCompact(3400000) == "3.4M", "compact 3.4M")
	check(LeaderboardUtil.FormatCompact(5600000000) == "5.6B", "compact 5.6B")
	check(LeaderboardUtil.FormatCompact(7800000000000) == "7.8T", "compact 7.8T")

	--------------------------------------------------------------------
	-- Week key stable + lundi / dimanche
	--------------------------------------------------------------------
	-- 2026-08-03 = lundi UTC (approx midday key)
	local mon = ChallengeLogic.UnixFromDailyKey("20260803")
	local sun = ChallengeLogic.UnixFromDailyKey("20260809")
	local nextMon = ChallengeLogic.UnixFromDailyKey("20260810")
	check(mon ~= nil and sun ~= nil and nextMon ~= nil, "unix keys")
	if mon and sun and nextMon then
		local kMon = WeeklyBestLogic.WeekKey(mon)
		local kSun = WeeklyBestLogic.WeekKey(sun)
		local kNext = WeeklyBestLogic.WeekKey(nextMon)
		check(kMon == kSun, "lundi et dimanche même semaine")
		check(kMon ~= kNext, "lundi suivant = nouvelle semaine")
		check(string.match(kMon, "^%d%d%d%d%-W%d%d$") ~= nil, "format année-Wxx")
		check(WeeklyBestLogic.StoreName(kMon) == "WeeklyBestScore_v1_" .. kMon, "store name versionné")
		check(WeeklyBestLogic.StoreNameForTime(mon) ~= WeeklyBestLogic.StoreNameForTime(nextMon), "stores distincts par semaine")
	end

	--------------------------------------------------------------------
	-- Rollover local n'efface pas l'historique store (logique seulement)
	--------------------------------------------------------------------
	local weekA = WeeklyBestLogic.WeekKey(mon :: number)
	local weekB = WeeklyBestLogic.WeekKey(nextMon :: number)
	local rolled, changed = WeeklyBestLogic.RollWeekState({ WeekKey = weekA, Score = 9001 }, nextMon :: number)
	check(changed == true, "changement de semaine détecté")
	check(rolled.WeekKey == weekB and rolled.Score == 0, "score local reset, clé B")
	local same, sameChanged = WeeklyBestLogic.RollWeekState({ WeekKey = weekA, Score = 42 }, mon :: number)
	check(sameChanged == false and same.Score == 42, "même semaine conserve score")

	local added = WeeklyBestLogic.AddLocalScore({ WeekKey = weekA, Score = 10 }, 5, mon :: number)
	check(added.Score == 15, "cumul score local")

	--------------------------------------------------------------------
	-- Classement trié / top 5
	--------------------------------------------------------------------
	local raw = {
		{ UserId = 1, Name = "A", Value = 100 },
		{ UserId = 2, Name = "B", Value = 500 },
		{ UserId = 3, Name = "C", Value = 300 },
		{ UserId = 4, Name = "D", Value = 500 },
		{ UserId = 5, Name = "E", Value = 50 },
		{ UserId = 6, Name = "F", Value = 10 },
	}
	check(WeeklyBestLogic.TOP_N == 10, "weekly top 10 défaut")
	local top = WeeklyBestLogic.TakeTop(raw, 5)
	check(#top == 5, "top 5 cap explicite")
	check(top[1].UserId == 2 and top[1].Rank == 1, "rang 1 valeur max")
	check(top[2].UserId == 4 and top[2].Rank == 2, "tie-break userid")
	check(top[5].Value == 50, "5e entrée")
	check(#WeeklyBestLogic.TakeTop({}, 5) == 0, "vide ok")
	check(#WeeklyBestLogic.TakeTop(raw, WeeklyBestLogic.TOP_N) == 6, "top 10 peut contenir 6")
	check(WeeklyBestLogic.FormatScore(1200) == "1.2K", "format score")
	check(WeeklyBestLogic.MergeScore(100, 50) == 100, "merge ne diminue pas")
	check(WeeklyBestLogic.MergeScore(nil, 77) == 77, "merge init")

	if failed == 0 then
		print("[WeeklyBestLogicTests] OK")
		return true
	end
	return false
end

return WeeklyBestLogicTests
