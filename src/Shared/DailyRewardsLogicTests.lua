--!strict

local DailyRewardsLogic = require(script.Parent.DailyRewardsLogic)

local Tests = {}

local function check(condition: boolean, message: string)
	if not condition then
		error("[DailyRewardsLogicTests] " .. message, 2)
	end
end

function Tests.Run()
	local pass = 0
	local function ok(condition: boolean, message: string)
		check(condition, message)
		pass += 1
	end

	-- UTC day key stable à l'intérieur d'une même journée.
	ok(DailyRewardsLogic.DayKeyFromUnix(0) == 0, "epoch day key")
	ok(DailyRewardsLogic.DayKeyFromUnix(86399) == 0, "same UTC day")
	ok(DailyRewardsLogic.DayKeyFromUnix(86400) == 1, "next UTC day")

	-- Premier login = streak 1, claim disponible.
	local state, visit = DailyRewardsLogic.RecordVisit(nil, 100)
	ok(visit.Changed == true, "first visit changed")
	ok(state.Streak == 1, "first streak is 1")
	ok(DailyRewardsLogic.CurrentCycleDay(state) == 1, "first cycle day")
	ok(DailyRewardsLogic.CanClaim(state, 100) == true, "first day claimable")

	-- Reconnexion même journée : aucun incrément.
	local same, sameVisit = DailyRewardsLogic.RecordVisit(state, 100)
	ok(sameVisit.Changed == false, "same day unchanged")
	ok(same.Streak == 1, "same day streak unchanged")

	-- Claim idempotent.
	local claimed, didClaim, code = DailyRewardsLogic.MarkClaimed(same, 100)
	ok(didClaim == true and code == "ok", "first claim succeeds")
	ok(DailyRewardsLogic.CanClaim(claimed, 100) == false, "claimed day no longer claimable")
	local duplicate, duplicateOk, duplicateCode = DailyRewardsLogic.MarkClaimed(claimed, 100)
	ok(duplicateOk == false and duplicateCode == "already_claimed", "duplicate claim rejected")
	ok(duplicate.LifetimeClaims == 1, "duplicate does not increment lifetime claims")

	-- Jour suivant = streak 2, nouveau claim.
	local nextDay, nextVisit = DailyRewardsLogic.RecordVisit(claimed, 101)
	ok(nextVisit.Advanced == true and nextVisit.Broken == false, "consecutive day advances")
	ok(nextDay.Streak == 2 and DailyRewardsLogic.CurrentCycleDay(nextDay) == 2, "day two streak")
	ok(DailyRewardsLogic.CanClaim(nextDay, 101) == true, "next day claimable")

	-- Journée manquée = retour Day 1.
	local broken, brokenVisit = DailyRewardsLogic.RecordVisit(nextDay, 103)
	ok(brokenVisit.Broken == true, "missed day breaks streak")
	ok(broken.Streak == 1 and DailyRewardsLogic.CurrentCycleDay(broken) == 1, "broken streak resets to day one")

	-- Sept connexions consécutives débloquent le chandail même sans CLAIM.
	local week = DailyRewardsLogic.NewState()
	local reachedDay7 = false
	for day = 200, 206 do
		local result
		week, result = DailyRewardsLogic.RecordVisit(week, day)
		reachedDay7 = result.ReachedDay7
	end
	ok(week.Streak == 7, "seven day streak")
	ok(reachedDay7 == true, "day seven milestone reached")
	ok(week.ShirtUnlocked == true, "shirt unlocked by seventh login")
	ok(week.CompletedCycles == 1, "first cycle completed")
	ok(DailyRewardsLogic.CurrentCycleDay(week) == 7, "cycle day seven")

	-- Huitième jour : cycle visuel revient Day 1 sans perdre le streak ni le chandail.
	local day8, day8Visit = DailyRewardsLogic.RecordVisit(week, 207)
	ok(day8Visit.Broken == false, "day eight remains consecutive")
	ok(day8.Streak == 8 and DailyRewardsLogic.CurrentCycleDay(day8) == 1, "cycle wraps after day seven")
	ok(day8.ShirtUnlocked == true, "shirt unlock persists")

	-- Ancien profil sans DailyRewards se normalise sans erreur.
	local legacy = DailyRewardsLogic.NormalizeState({})
	ok(legacy.Streak == 0 and legacy.ShirtUnlocked == false, "legacy state defaults")

	print(string.format("[DailyRewardsLogicTests] assertions: %d pass / 0 fail", pass))
	print("[DailyRewardsLogicTests] OK")
end

return Tests
