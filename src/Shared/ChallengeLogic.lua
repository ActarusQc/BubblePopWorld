--!strict
-- Logique pure défis / resets / sélection / progression / classement (testable hors services).

local ChallengeConfig = require(script.Parent.ChallengeConfig)

local ChallengeLogic = {}

ChallengeLogic.METRICS = table.freeze({
	"PopBubbles",
	"PopSpecial",
	"PopSummer",
	"PopGoldenWave",
	"PopColorRush",
	"GiantHits",
	"GiantComplete",
	"MiniEventJoin",
	"MiniEventComplete",
	"FeaturedEventJoin",
	"SellFullBackpack",
	"SellValue",
})

ChallengeLogic.SLOTS = table.freeze({ "Easy", "Medium", "Event", "Weekly" })

export type PlayerContext = {
	hasSummerAccess: boolean,
	featuredEventType: string?,
	enabledEvents: { [string]: boolean }?,
}

export type ChallengeInstance = {
	Id: string,
	Metric: string,
	Target: number,
	Progress: number,
	Completed: boolean,
	Claimed: boolean,
	Slot: string,
	TitleKey: string,
	DescKey: string,
	RewardType: string,
	RewardAmount: number,
}

export type ChallengesState = {
	Version: number,
	DailyKey: string,
	WeeklyKey: string,
	DailyBubblePops: number,
	Daily: { ChallengeInstance },
	Weekly: ChallengeInstance?,
	TrackedId: string?,
	MilestoneNotified: { [string]: { [string]: boolean } }?, -- challengeId -> "0.25" -> true
}

local SECONDS_PER_DAY = 86400

local function floorDiv(a: number, b: number): number
	return math.floor(a / b)
end

-- Hash déterministe stable (DJB2 mod 2^31-1) — portable hors Roblox.
function ChallengeLogic.HashString(s: string): number
	local hash = 5381
	for i = 1, #s do
		hash = (hash * 33 + string.byte(s, i)) % 2147483647
	end
	return hash
end

function ChallengeLogic.UtcYmdParts(unixTime: number): (number, number, number)
	local t = math.max(0, math.floor(unixTime))
	local days = floorDiv(t, SECONDS_PER_DAY)
	-- Algorithme civil UTC (proleptic Gregorian)
	local z = days + 719468
	local era = floorDiv(z, 146097)
	local doe = z - era * 146097
	local yoe = floorDiv(doe - floorDiv(doe, 1460) + floorDiv(doe, 36524) - floorDiv(doe, 146096), 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floorDiv(yoe, 4) - floorDiv(yoe, 100))
	local mp = floorDiv(5 * doy + 2, 153)
	local d = doy - floorDiv(153 * mp + 2, 5) + 1
	local m = mp + if mp < 10 then 3 else -9
	y = y + if m <= 2 then 1 else 0
	return y, m, d
end

function ChallengeLogic.DailyKey(unixTime: number): string
	local y, m, d = ChallengeLogic.UtcYmdParts(unixTime)
	return string.format("%04d%02d%02d", y, m, d)
end

-- ISO-8601 week : lundi = début, semaine 1 = celle contenant le 1er jeudi.
function ChallengeLogic.WeeklyKey(unixTime: number): string
	local y, m, d = ChallengeLogic.UtcYmdParts(unixTime)
	-- Day of week Monday=0 .. Sunday=6
	local t = math.max(0, math.floor(unixTime))
	local days = floorDiv(t, SECONDS_PER_DAY)
	local dow = (days + 3) % 7 -- 1970-01-01 was Thursday → Monday=0 offset by +3 from Thursday?

	-- Better: use civil date to get weekday
	-- Sakamoto weekday: 0=Sunday ... 6=Saturday
	local function sakamoto(yy: number, mm: number, dd: number): number
		local tmap = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
		if mm < 3 then
			yy -= 1
		end
		return (yy + floorDiv(yy, 4) - floorDiv(yy, 100) + floorDiv(yy, 400) + tmap[mm] + dd) % 7
	end
	local sun0 = sakamoto(y, m, d) -- 0=Sun
	local mon0 = (sun0 + 6) % 7 -- 0=Mon

	-- Thursday of this week
	local dayOffsetToThu = 3 - mon0
	local thuUnix = t + dayOffsetToThu * SECONDS_PER_DAY
	local ty, tm, td = ChallengeLogic.UtcYmdParts(thuUnix)
	-- ISO year is the year of the Thursday
	local isoYear = ty

	-- Jan 4 of isoYear is always in week 1
	local function ymdToUnix(yy: number, mm: number, dd: number): number
		-- days since epoch
		local function daysFromCivil(y0: number, m0: number, d0: number): number
			y0 -= if m0 <= 2 then 1 else 0
			local era = floorDiv(y0, 400)
			local yoe = y0 - era * 400
			local doy = floorDiv(153 * (m0 + if m0 > 2 then -3 else 9) + 2, 5) + d0 - 1
			local doe = yoe * 365 + floorDiv(yoe, 4) - floorDiv(yoe, 100) + doy
			return era * 146097 + doe - 719468
		end
		return daysFromCivil(yy, mm, dd) * SECONDS_PER_DAY
	end

	local jan4 = ymdToUnix(isoYear, 1, 4)
	local jan4Days = floorDiv(jan4, SECONDS_PER_DAY)
	local thuDays = floorDiv(thuUnix, SECONDS_PER_DAY)
	-- Monday of week of Jan 4
	local j4y, j4m, j4d = ChallengeLogic.UtcYmdParts(jan4)
	local j4sun = sakamoto(j4y, j4m, j4d)
	local j4mon = (j4sun + 6) % 7
	local week1MonDays = jan4Days - j4mon
	local week = floorDiv(thuDays - week1MonDays, 7) + 1
	-- td unused but keeps civil path stable under strict
	local _ = td
	return string.format("%04d-W%02d", isoYear, week)
end

function ChallengeLogic.SecondsUntilDailyReset(unixTime: number): number
	local t = math.max(0, math.floor(unixTime))
	local nextMidnight = (floorDiv(t, SECONDS_PER_DAY) + 1) * SECONDS_PER_DAY
	return math.max(0, nextMidnight - t)
end

function ChallengeLogic.SecondsUntilWeeklyReset(unixTime: number): number
	local t = math.max(0, math.floor(unixTime))
	local days = floorDiv(t, SECONDS_PER_DAY)
	-- 1970-01-01 Thursday. Monday = days where (days+3)%7==0? 
	-- Thursday + 4 days = Monday → day index for Monday: (days - 4) % 7 == 0?
	local dayInWeek = (days + 3) % 7 -- 0=Mon if epoch Thu: (0+3)%7=3=Thu if Mon=0: Thu=3. Yes with Mon=0: (days+3)%7? 
	-- epoch day 0 Thu. We want Mon=0: (days + 4) % 7 for Thu=4... 
	-- Mon 0: Thu = 3. So (days + 4) % 7: day0 → 4 not 3.
	-- Correct Mon=0: (days + 3) % 7 for day0: 3 = Thursday. Yes Mon=0 Sun=6.
	local mon0 = (days + 3) % 7
	local daysUntilNextMon = if mon0 == 0 then 7 else (7 - mon0)
	-- If we are Monday, next reset is next Monday (full week) only at 00:00.
	-- At Monday 00:00 mon0=0 and seconds into day = 0 → week just started.
	local secIntoDay = t % SECONDS_PER_DAY
	if mon0 == 0 and secIntoDay == 0 then
		return 7 * SECONDS_PER_DAY
	end
	if mon0 == 0 then
		-- already past Monday 00:00 this week → days until next Monday = 7
		daysUntilNextMon = 7
	end
	local nextMonMidnight = (days + daysUntilNextMon) * SECONDS_PER_DAY
	return math.max(0, nextMonMidnight - t)
end

function ChallengeLogic.FormatCountdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local days = floorDiv(s, SECONDS_PER_DAY)
	local hours = floorDiv(s % SECONDS_PER_DAY, 3600)
	local mins = floorDiv(s % 3600, 60)
	if days > 0 then
		return string.format("%dd %dh", days, hours)
	end
	if hours > 0 then
		return string.format("%dh %dm", hours, mins)
	end
	return string.format("%dm", math.max(1, mins))
end

function ChallengeLogic.FeaturedEventForDay(dailyKey: string): string
	local rotation = ChallengeConfig.FeaturedEventRotation
	if type(rotation) ~= "table" or #rotation == 0 then
		return "GoldenWave"
	end
	local hash = ChallengeLogic.HashString("featured:" .. dailyKey)
	local idx = (hash % #rotation) + 1
	-- Eviter deux jours consécutifs si possible : base sur day number
	local dayNum = tonumber(dailyKey)
	if dayNum then
		idx = ((dayNum - 1) % #rotation) + 1
	end
	local pick = rotation[idx]
	return if type(pick) == "string" then pick else "GoldenWave"
end

function ChallengeLogic.IsMetricValid(metric: string): boolean
	for _, m in ipairs(ChallengeLogic.METRICS) do
		if m == metric then
			return true
		end
	end
	return false
end

local function defEligible(def: any, ctx: PlayerContext): boolean
	if def.RequiresSummer == true and ctx.hasSummerAccess ~= true then
		return false
	end
	if def.FeaturedOnly == true then
		local featured = ctx.featuredEventType
		if featured == "GoldenWave" and def.Metric ~= "PopGoldenWave" then
			return false
		end
		if featured == "ColorRush" and def.Metric ~= "PopColorRush" then
			return false
		end
		-- GiantBubble retiré de la rotation challenges ; garder une garde pour configs legacy.
		if featured == "GiantBubble" and def.Metric ~= "PopSpecial" and def.Metric ~= "GiantHits" then
			return false
		end
		local enabled = ctx.enabledEvents
		if type(enabled) == "table" and featured and enabled[featured] == false then
			return false
		end
	end
	return true
end

local function pickFromPool(
	pool: { any },
	seedKey: string,
	ctx: PlayerContext,
	usedMetrics: { [string]: boolean }
): any?
	local candidates = {}
	for _, def in ipairs(pool) do
		if defEligible(def, ctx) and usedMetrics[def.Metric] ~= true then
			table.insert(candidates, def)
		end
	end
	if #candidates == 0 then
		-- retenter sans filtre metric unique
		for _, def in ipairs(pool) do
			if defEligible(def, ctx) then
				table.insert(candidates, def)
			end
		end
	end
	if #candidates == 0 then
		-- fall back sans Summer / Featured
		for _, def in ipairs(pool) do
			if def.RequiresSummer ~= true and def.FeaturedOnly ~= true then
				table.insert(candidates, def)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local hash = ChallengeLogic.HashString(seedKey)
	local idx = (hash % #candidates) + 1
	return candidates[idx]
end

function ChallengeLogic.InstantiateDef(def: any): ChallengeInstance
	local reward = ChallengeConfig.RewardForKey(def.RewardKey or "DailyEasy")
	return {
		Id = def.Id,
		Metric = def.Metric,
		Target = ChallengeConfig.ScaleTarget(def.Target),
		Progress = 0,
		Completed = false,
		Claimed = false,
		Slot = def.Slot,
		TitleKey = def.TitleKey,
		DescKey = def.DescKey,
		RewardType = reward.Type,
		RewardAmount = reward.Amount,
	}
end

-- Anciens challenges Giant Bubble / hits → Pop Special Bubbles (actifs immédiatement).
local DEPRECATED_CHALLENGE_MAP: { [string]: string } = {
	FeaturedGiant_10 = "PopSpecial_10",
	WeeklyGiant_5 = "WeeklySpecial_100",
}

local DEPRECATED_METRICS: { [string]: string } = {
	GiantHits = "PopSpecial",
	GiantComplete = "PopSpecial",
}

function ChallengeLogic.IsDeprecatedGiantChallenge(idOrMetric: string): boolean
	return DEPRECATED_CHALLENGE_MAP[idOrMetric] ~= nil or DEPRECATED_METRICS[idOrMetric] ~= nil
end

function ChallengeLogic.MigrateDeprecatedChallenge(inst: ChallengeInstance): (ChallengeInstance, boolean)
	local replacementId = DEPRECATED_CHALLENGE_MAP[inst.Id]
	if not replacementId and DEPRECATED_METRICS[inst.Metric] then
		if inst.Slot == "Weekly" then
			replacementId = "WeeklySpecial_100"
		elseif inst.Slot == "Event" then
			replacementId = "PopSpecial_10"
		elseif inst.Slot == "Medium" then
			replacementId = "PopSpecial_20"
		else
			replacementId = "PopSpecial_5"
		end
	end
	if not replacementId then
		return inst, false
	end
	local def = ChallengeConfig.FindDefById(replacementId)
	if not def then
		def = ChallengeConfig.FindDefById("PopSpecial_10")
	end
	if not def then
		return inst, false
	end
	local fresh = ChallengeLogic.InstantiateDef(def)
	-- Conserve claim ; sinon repart de 0 (GiantHits ≠ pops spéciaux).
	if inst.Claimed == true then
		fresh.Progress = fresh.Target
		fresh.Completed = true
		fresh.Claimed = true
	else
		fresh.Progress = 0
		fresh.Completed = false
		fresh.Claimed = false
	end
	return fresh, true
end

function ChallengeLogic.SelectDailyChallenges(dailyKey: string, ctx: PlayerContext): { ChallengeInstance }
	local used: { [string]: boolean } = {}
	local out: { ChallengeInstance } = {}
	local pools = {
		{ "Easy", ChallengeConfig.DailyEasyPool },
		{ "Medium", ChallengeConfig.DailyMediumPool },
		{ "Event", ChallengeConfig.DailyEventPool },
	}
	for _, entry in ipairs(pools) do
		local slotName = entry[1] :: string
		local pool = entry[2] :: { any }
		local picked = pickFromPool(pool, dailyKey .. ":" .. slotName, ctx, used)
		if picked then
			local inst = ChallengeLogic.InstantiateDef(picked)
			used[inst.Metric] = true
			table.insert(out, inst)
		end
	end
	return out
end

function ChallengeLogic.SelectWeeklyChallenge(weeklyKey: string, ctx: PlayerContext): ChallengeInstance?
	local used = {}
	local picked = pickFromPool(ChallengeConfig.WeeklyPool, weeklyKey .. ":Weekly", ctx, used)
	if not picked then
		return nil
	end
	return ChallengeLogic.InstantiateDef(picked)
end

function ChallengeLogic.EmptyState(unixTime: number, ctx: PlayerContext): ChallengesState
	local dailyKey = ChallengeLogic.DailyKey(unixTime)
	local weeklyKey = ChallengeLogic.WeeklyKey(unixTime)
	local featured = ChallengeLogic.FeaturedEventForDay(dailyKey)
	local fullCtx: PlayerContext = {
		hasSummerAccess = ctx.hasSummerAccess == true,
		featuredEventType = featured,
		enabledEvents = ctx.enabledEvents,
	}
	return {
		Version = ChallengeConfig.Version,
		DailyKey = dailyKey,
		WeeklyKey = weeklyKey,
		DailyBubblePops = 0,
		Daily = ChallengeLogic.SelectDailyChallenges(dailyKey, fullCtx),
		Weekly = ChallengeLogic.SelectWeeklyChallenge(weeklyKey, fullCtx),
		TrackedId = nil,
		MilestoneNotified = {},
	}
end

-- Réconcilie / reset périodes expirées. Préserve Claimed dans la période active.
function ChallengeLogic.ReconcileState(
	raw: any,
	unixTime: number,
	ctx: PlayerContext
): (ChallengesState, boolean) -- state, changed
	local dailyKey = ChallengeLogic.DailyKey(unixTime)
	local weeklyKey = ChallengeLogic.WeeklyKey(unixTime)
	local featured = ChallengeLogic.FeaturedEventForDay(dailyKey)
	local fullCtx: PlayerContext = {
		hasSummerAccess = ctx.hasSummerAccess == true,
		featuredEventType = featured,
		enabledEvents = ctx.enabledEvents,
	}

	if type(raw) ~= "table" then
		return ChallengeLogic.EmptyState(unixTime, fullCtx), true
	end

	local changed = false
	local state: ChallengesState = {
		Version = ChallengeConfig.Version,
		DailyKey = if type(raw.DailyKey) == "string" then raw.DailyKey else "",
		WeeklyKey = if type(raw.WeeklyKey) == "string" then raw.WeeklyKey else "",
		DailyBubblePops = math.max(0, math.floor(tonumber(raw.DailyBubblePops) or 0)),
		Daily = {},
		Weekly = nil,
		TrackedId = if type(raw.TrackedId) == "string" then raw.TrackedId else nil,
		MilestoneNotified = if type(raw.MilestoneNotified) == "table" then raw.MilestoneNotified else {},
	}

	local function normalizeInstance(src: any, fallback: ChallengeInstance?): ChallengeInstance?
		if type(src) ~= "table" or type(src.Id) ~= "string" then
			return fallback
		end
		local progress = math.max(0, math.floor(tonumber(src.Progress) or 0))
		local target = math.max(1, math.floor(tonumber(src.Target) or (fallback and fallback.Target) or 1))
		local completed = src.Completed == true or progress >= target
		local claimed = src.Claimed == true
		if claimed then
			completed = true
		end
		return {
			Id = src.Id,
			Metric = if type(src.Metric) == "string" then src.Metric else (fallback and fallback.Metric) or "PopBubbles",
			Target = target,
			Progress = math.min(progress, target),
			Completed = completed,
			Claimed = claimed,
			Slot = if type(src.Slot) == "string" then src.Slot else (fallback and fallback.Slot) or "Easy",
			TitleKey = if type(src.TitleKey) == "string" then src.TitleKey else (fallback and fallback.TitleKey) or "ChallengePopBubbles",
			DescKey = if type(src.DescKey) == "string" then src.DescKey else (fallback and fallback.DescKey) or "ChallengePopBubblesDesc",
			RewardType = if type(src.RewardType) == "string" then src.RewardType else (fallback and fallback.RewardType) or "SellBonus",
			RewardAmount = math.max(0, math.floor(tonumber(src.RewardAmount) or (fallback and fallback.RewardAmount) or 0)),
		}
	end

	if state.DailyKey ~= dailyKey then
		state.DailyKey = dailyKey
		state.Daily = ChallengeLogic.SelectDailyChallenges(dailyKey, fullCtx)
		state.DailyBubblePops = 0
		state.MilestoneNotified = {}
		changed = true
	else
		local fresh = ChallengeLogic.SelectDailyChallenges(dailyKey, fullCtx)
		if type(raw.Daily) == "table" and #raw.Daily >= 1 then
			for i = 1, 3 do
				local src = raw.Daily[i]
				local fb = fresh[i]
				local inst = normalizeInstance(src, fb)
				if inst then
					local migrated, didMigrate = ChallengeLogic.MigrateDeprecatedChallenge(inst)
					if didMigrate then
						changed = true
						inst = migrated
					end
					table.insert(state.Daily, inst)
				elseif fb then
					table.insert(state.Daily, fb)
					changed = true
				end
			end
		else
			state.Daily = fresh
			changed = true
		end
		-- Compléter si moins de 3
		while #state.Daily < 3 and #fresh > #state.Daily do
			table.insert(state.Daily, fresh[#state.Daily + 1])
			changed = true
		end
	end

	if state.WeeklyKey ~= weeklyKey then
		state.WeeklyKey = weeklyKey
		state.Weekly = ChallengeLogic.SelectWeeklyChallenge(weeklyKey, fullCtx)
		changed = true
	else
		local freshW = ChallengeLogic.SelectWeeklyChallenge(weeklyKey, fullCtx)
		if type(raw.Weekly) == "table" then
			local w = normalizeInstance(raw.Weekly, freshW)
			if w then
				local migrated, didMigrate = ChallengeLogic.MigrateDeprecatedChallenge(w)
				if didMigrate then
					changed = true
					w = migrated
				end
			end
			state.Weekly = w
		else
			state.Weekly = freshW
			changed = true
		end
	end

	return state, changed
end

export type GameplayEvent = {
	metric: string,
	amount: number,
	-- Pour FeaturedEventJoin : eventType de l'événement rejoint
	eventType: string?,
	featuredEventType: string?,
}

-- Une action incrémente chaque défi une seule fois (même métrique).
function ChallengeLogic.ApplyProgress(
	state: ChallengesState,
	events: { GameplayEvent }
): (ChallengesState, { { challengeId: string, progress: number, target: number, completed: boolean, slot: string } })
	local deltas = {}
	local amountByMetric: { [string]: number } = {}
	for _, ev in ipairs(events) do
		if ChallengeLogic.IsMetricValid(ev.metric) then
			local amt = math.max(0, math.floor(tonumber(ev.amount) or 0))
			if amt > 0 then
				-- FeaturedEventJoin : ne compte que si match featured
				if ev.metric == "FeaturedEventJoin" then
					if ev.eventType and ev.featuredEventType and ev.eventType == ev.featuredEventType then
						amountByMetric[ev.metric] = (amountByMetric[ev.metric] or 0) + amt
					end
				else
					amountByMetric[ev.metric] = (amountByMetric[ev.metric] or 0) + amt
				end
			end
		end
	end

	local function bump(ch: ChallengeInstance): ChallengeInstance?
		if ch.Completed or ch.Claimed then
			return nil
		end
		local add = amountByMetric[ch.Metric]
		if not add or add <= 0 then
			return nil
		end
		local before = ch.Progress
		ch.Progress = math.min(ch.Target, ch.Progress + add)
		if ch.Progress ~= before then
			if ch.Progress >= ch.Target then
				ch.Completed = true
				ch.Progress = ch.Target
			end
			table.insert(deltas, {
				challengeId = ch.Id,
				progress = ch.Progress,
				target = ch.Target,
				completed = ch.Completed,
				slot = ch.Slot,
			})
			return ch
		end
		return nil
	end

	for _, ch in ipairs(state.Daily) do
		bump(ch)
	end
	if state.Weekly then
		bump(state.Weekly)
	end

	return state, deltas
end

function ChallengeLogic.CrossedMilestones(
	challengeId: string,
	beforeProgress: number,
	afterProgress: number,
	target: number,
	notified: { [string]: { [string]: boolean } }?
): { number }
	local bag = if type(notified) == "table" then notified[challengeId] else nil
	local crossed = {}
	if target <= 0 then
		return crossed
	end
	local beforeRatio = beforeProgress / target
	local afterRatio = afterProgress / target
	for _, m in ipairs(ChallengeConfig.ProgressMilestones) do
		local key = tostring(m)
		if beforeRatio < m and afterRatio >= m then
			if not bag or bag[key] ~= true then
				table.insert(crossed, m)
			end
		end
	end
	return crossed
end

function ChallengeLogic.MarkMilestones(
	notified: { [string]: { [string]: boolean } },
	challengeId: string,
	milestones: { number }
): { [string]: { [string]: boolean } }
	if type(notified) ~= "table" then
		notified = {}
	end
	if type(notified[challengeId]) ~= "table" then
		notified[challengeId] = {}
	end
	for _, m in ipairs(milestones) do
		notified[challengeId][tostring(m)] = true
	end
	return notified
end

-- Claim idempotent : true si reward doit être accordée maintenant.
function ChallengeLogic.TryClaim(ch: ChallengeInstance): (boolean, string)
	if ch.Claimed then
		return false, "already_claimed"
	end
	if not ch.Completed and ch.Progress < ch.Target then
		return false, "not_complete"
	end
	ch.Completed = true
	ch.Claimed = true
	ch.Progress = ch.Target
	return true, "ok"
end

-- Ordre d'affichage : progress → réclamable → réclamé (tous restent visibles).
function ChallengeLogic.SortChallengesForDisplay(list: { ChallengeInstance }): { ChallengeInstance }
	local copy = {}
	for i, ch in ipairs(list) do
		copy[i] = ch
	end
	table.sort(copy, function(a, b)
		local function rank(ch: ChallengeInstance): number
			if ch.Claimed == true then
				return 3
			end
			if ch.Completed == true or ch.Progress >= ch.Target then
				return 2
			end
			return 1
		end
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.Id < b.Id
	end)
	return copy
end

function ChallengeLogic.ChallengeStatus(ch: ChallengeInstance): string
	if ch.Claimed == true then
		return "Claimed"
	end
	if ch.Completed == true or (ch.Target > 0 and ch.Progress >= ch.Target) then
		return "ReadyToClaim"
	end
	return "InProgress"
end

function ChallengeLogic.IsChallengeVisibleInList(_ch: ChallengeInstance): boolean
	-- Les défis de la période active restent toujours listés (y compris terminés / claimés).
	return true
end

function ChallengeLogic.FindChallenge(state: ChallengesState, challengeId: string): ChallengeInstance?
	for _, ch in ipairs(state.Daily) do
		if ch.Id == challengeId then
			return ch
		end
	end
	if state.Weekly and state.Weekly.Id == challengeId then
		return state.Weekly
	end
	return nil
end

function ChallengeLogic.DefaultTrackedId(state: ChallengesState): string?
	for _, ch in ipairs(state.Daily) do
		if not ch.Completed and not ch.Claimed then
			return ch.Id
		end
	end
	if state.Weekly and not state.Weekly.Completed and not state.Weekly.Claimed then
		return state.Weekly.Id
	end
	-- tous terminés : premier daily
	if #state.Daily > 0 then
		return state.Daily[1].Id
	end
	if state.Weekly then
		return state.Weekly.Id
	end
	return nil
end

function ChallengeLogic.IsValidDailyBubblePop(ctx: {
	isTutorial: boolean?,
	isGiantHit: boolean?,
	isGiantBody: boolean?,
	serverAccepted: boolean?,
}): boolean
	if ctx.serverAccepted == false then
		return false
	end
	if ctx.isTutorial == true then
		return false
	end
	if ctx.isGiantHit == true then
		return false
	end
	if ctx.isGiantBody == true and ChallengeConfig.CountGiantDestroyAsPop ~= true then
		return false
	end
	return true
end

-- Score OrderedDataStore : ne doit jamais diminuer.
function ChallengeLogic.MergeLeaderboardScore(existing: number?, candidate: number): number
	local e = math.max(0, math.floor(tonumber(existing) or 0))
	local c = math.max(0, math.floor(candidate))
	return math.max(e, c)
end

function ChallengeLogic.SerializePublicState(
	state: ChallengesState,
	unixTime: number,
	leaderboard: any?,
	featuredEventType: string?
): { [string]: any }
	local dailyList = {}
	for _, ch in ipairs(state.Daily) do
		table.insert(dailyList, {
			Id = ch.Id,
			Metric = ch.Metric,
			Target = ch.Target,
			Progress = ch.Progress,
			Completed = ch.Completed,
			Claimed = ch.Claimed,
			Slot = ch.Slot,
			TitleKey = ch.TitleKey,
			DescKey = ch.DescKey,
			RewardType = ch.RewardType,
			RewardAmount = ch.RewardAmount,
		})
	end
	local weekly = nil
	if state.Weekly then
		local w = state.Weekly
		weekly = {
			Id = w.Id,
			Metric = w.Metric,
			Target = w.Target,
			Progress = w.Progress,
			Completed = w.Completed,
			Claimed = w.Claimed,
			Slot = w.Slot,
			TitleKey = w.TitleKey,
			DescKey = w.DescKey,
			RewardType = w.RewardType,
			RewardAmount = w.RewardAmount,
		}
	end
	return {
		DailyKey = state.DailyKey,
		WeeklyKey = state.WeeklyKey,
		Daily = dailyList,
		Weekly = weekly,
		DailyBubblePops = state.DailyBubblePops,
		TrackedId = state.TrackedId or ChallengeLogic.DefaultTrackedId(state),
		FeaturedEventType = featuredEventType or ChallengeLogic.FeaturedEventForDay(state.DailyKey),
		SecondsToDailyReset = ChallengeLogic.SecondsUntilDailyReset(unixTime),
		SecondsToWeeklyReset = ChallengeLogic.SecondsUntilWeeklyReset(unixTime),
		Leaderboard = leaderboard,
		ServerNow = math.floor(unixTime),
	}
end

-- Pour tests : conversion date YYYYMMDD → unix approx midday
function ChallengeLogic.UnixFromDailyKey(dailyKey: string): number?
	local y = tonumber(string.sub(dailyKey, 1, 4))
	local m = tonumber(string.sub(dailyKey, 5, 6))
	local d = tonumber(string.sub(dailyKey, 7, 8))
	if not y or not m or not d then
		return nil
	end
	local function daysFromCivil(y0: number, m0: number, d0: number): number
		y0 -= if m0 <= 2 then 1 else 0
		local era = floorDiv(y0, 400)
		local yoe = y0 - era * 400
		local doy = floorDiv(153 * (m0 + if m0 > 2 then -3 else 9) + 2, 5) + d0 - 1
		local doe = yoe * 365 + floorDiv(yoe, 4) - floorDiv(yoe, 100) + doy
		return era * 146097 + doe - 719468
	end
	return daysFromCivil(y, m, d) * SECONDS_PER_DAY + 12 * 3600
end

return ChallengeLogic
