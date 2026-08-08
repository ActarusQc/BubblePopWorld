--!strict
-- Logique pure du streak Daily Rewards. Aucune dépendance DataStore/UI.

local DailyRewardsConfig = require(script.Parent.DailyRewardsConfig)

local DailyRewardsLogic = {}

export type DailyRewardsState = {
	Version: number,
	Streak: number,
	LastVisitDayKey: number,
	LastClaimDayKey: number,
	LifetimeClaims: number,
	CompletedCycles: number,
	ShirtUnlocked: boolean,
	ShirtEquipped: boolean,
}

export type VisitResult = {
	Changed: boolean,
	Advanced: boolean,
	Broken: boolean,
	ReachedDay7: boolean,
	CycleDay: number,
}

local function finiteInteger(value: any, fallback: number, minValue: number, maxValue: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.clamp(math.floor(value), minValue, maxValue)
end

function DailyRewardsLogic.DayKeyFromUnix(unixTime: number): number
	local t = finiteInteger(unixTime, 0, 0, 32503680000) -- jusqu'à l'an 3000 environ
	return math.floor(t / 86400)
end

function DailyRewardsLogic.NewState(): DailyRewardsState
	return {
		Version = DailyRewardsConfig.Version,
		Streak = 0,
		LastVisitDayKey = 0,
		LastClaimDayKey = 0,
		LifetimeClaims = 0,
		CompletedCycles = 0,
		ShirtUnlocked = false,
		ShirtEquipped = false,
	}
end

function DailyRewardsLogic.NormalizeState(saved: any): DailyRewardsState
	local state = DailyRewardsLogic.NewState()
	if type(saved) ~= "table" then
		return state
	end
	state.Version = DailyRewardsConfig.Version
	state.Streak = finiteInteger(saved.Streak, 0, 0, 1000000)
	state.LastVisitDayKey = finiteInteger(saved.LastVisitDayKey, 0, 0, 10000000)
	state.LastClaimDayKey = finiteInteger(saved.LastClaimDayKey, 0, 0, 10000000)
	state.LifetimeClaims = finiteInteger(saved.LifetimeClaims, 0, 0, 100000000)
	state.CompletedCycles = finiteInteger(saved.CompletedCycles, 0, 0, 10000000)
	state.ShirtUnlocked = saved.ShirtUnlocked == true
	state.ShirtEquipped = state.ShirtUnlocked and saved.ShirtEquipped == true
	return state
end

function DailyRewardsLogic.CurrentCycleDay(state: DailyRewardsState): number
	if state.Streak <= 0 then
		return 1
	end
	return ((state.Streak - 1) % DailyRewardsConfig.CycleLength) + 1
end

function DailyRewardsLogic.RecordVisit(saved: any, todayKey: number): (DailyRewardsState, VisitResult)
	local state = DailyRewardsLogic.NormalizeState(saved)
	todayKey = finiteInteger(todayKey, 0, 1, 10000000)
	local result: VisitResult = {
		Changed = false,
		Advanced = false,
		Broken = false,
		ReachedDay7 = false,
		CycleDay = DailyRewardsLogic.CurrentCycleDay(state),
	}

	if state.LastVisitDayKey == todayKey then
		return state, result
	end

	local previousVisit = state.LastVisitDayKey
	if previousVisit > 0 and previousVisit == todayKey - 1 then
		state.Streak += 1
		result.Advanced = true
	elseif previousVisit <= 0 then
		state.Streak = 1
		result.Advanced = true
	else
		-- Trou de calendrier (ou donnée future/corrompue) : nouvelle série.
		result.Broken = previousVisit > 0 and state.Streak > 0
		state.Streak = 1
		result.Advanced = true
	end

	state.LastVisitDayKey = todayKey
	state.Version = DailyRewardsConfig.Version
	result.Changed = true
	result.CycleDay = DailyRewardsLogic.CurrentCycleDay(state)
	result.ReachedDay7 = result.CycleDay == DailyRewardsConfig.CycleLength

	-- Le chandail est un milestone de CONNEXION, pas de clic. Le joueur ne peut donc
	-- pas le perdre s'il oublie de cliquer CLAIM le septième jour.
	if result.ReachedDay7 then
		if not state.ShirtUnlocked then
			state.ShirtUnlocked = true
		end
		state.CompletedCycles += 1
	end

	return state, result
end

function DailyRewardsLogic.CanClaim(state: DailyRewardsState, todayKey: number): boolean
	return state.LastVisitDayKey == todayKey and state.LastClaimDayKey ~= todayKey and state.Streak > 0
end

function DailyRewardsLogic.MarkClaimed(saved: any, todayKey: number): (DailyRewardsState, boolean, string)
	local state = DailyRewardsLogic.NormalizeState(saved)
	todayKey = finiteInteger(todayKey, 0, 1, 10000000)
	if state.LastVisitDayKey ~= todayKey then
		return state, false, "not_visited_today"
	end
	if state.LastClaimDayKey == todayKey then
		return state, false, "already_claimed"
	end
	if state.Streak <= 0 then
		return state, false, "no_streak"
	end
	state.LastClaimDayKey = todayKey
	state.LifetimeClaims += 1
	return state, true, "ok"
end

function DailyRewardsLogic.SerializePublicState(saved: any, todayKey: number): any
	local state = DailyRewardsLogic.NormalizeState(saved)
	return {
		Version = state.Version,
		Streak = state.Streak,
		CycleDay = DailyRewardsLogic.CurrentCycleDay(state),
		CanClaim = DailyRewardsLogic.CanClaim(state, todayKey),
		ShirtUnlocked = state.ShirtUnlocked,
		ShirtEquipped = state.ShirtEquipped,
		CompletedCycles = state.CompletedCycles,
		LifetimeClaims = state.LifetimeClaims,
		ServerDayKey = todayKey,
		Rewards = DailyRewardsConfig.PublicRewards(),
	}
end

return DailyRewardsLogic
