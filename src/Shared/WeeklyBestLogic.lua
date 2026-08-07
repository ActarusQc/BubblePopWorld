--!strict
-- Logique pure Weekly Best Score (semaine ISO, store, tri) — testable hors Roblox.

local ChallengeLogic = require(script.Parent.ChallengeLogic)
local LeaderboardUtil = require(script.Parent.LeaderboardUtil)

local WeeklyBestLogic = {}

WeeklyBestLogic.STORE_PREFIX = "WeeklyBestScore_v1_"
WeeklyBestLogic.TOP_N = 10

-- Identifiant de semaine stable (lundi–dimanche, UTC / ISO-8601).
function WeeklyBestLogic.WeekKey(unixTime: number): string
	return ChallengeLogic.WeeklyKey(unixTime)
end

function WeeklyBestLogic.StoreName(weekKey: string): string
	return WeeklyBestLogic.STORE_PREFIX .. weekKey
end

function WeeklyBestLogic.StoreNameForTime(unixTime: number): string
	return WeeklyBestLogic.StoreName(WeeklyBestLogic.WeekKey(unixTime))
end

function WeeklyBestLogic.SanitizeScore(value: any): number?
	return LeaderboardUtil.SanitizeCoins(value)
end

function WeeklyBestLogic.MergeScore(existing: number?, candidate: number): number
	return ChallengeLogic.MergeLeaderboardScore(existing, candidate)
end

export type WeekState = {
	WeekKey: string,
	Score: number,
}

-- Remise à zéro locale si la semaine a changé (ne touche pas l'historique ODS).
function WeeklyBestLogic.RollWeekState(state: WeekState?, unixTime: number): (WeekState, boolean)
	local weekKey = WeeklyBestLogic.WeekKey(unixTime)
	if type(state) ~= "table" then
		return { WeekKey = weekKey, Score = 0 }, true
	end
	local prevKey = if type(state.WeekKey) == "string" then state.WeekKey else ""
	local score = math.max(0, math.floor(tonumber(state.Score) or 0))
	if prevKey ~= weekKey then
		return { WeekKey = weekKey, Score = 0 }, true
	end
	return { WeekKey = weekKey, Score = score }, false
end

function WeeklyBestLogic.AddLocalScore(state: WeekState, amount: number, unixTime: number): WeekState
	local rolled = WeeklyBestLogic.RollWeekState(state, unixTime)
	local add = math.max(0, math.floor(tonumber(amount) or 0))
	return {
		WeekKey = rolled.WeekKey,
		Score = rolled.Score + add,
	}
end

export type BoardEntry = LeaderboardUtil.BoardEntry

function WeeklyBestLogic.TakeTop(entries: { LeaderboardUtil.RawEntry }, limit: number?): { BoardEntry }
	return LeaderboardUtil.TakeTop(entries, limit or WeeklyBestLogic.TOP_N)
end

function WeeklyBestLogic.FormatScore(value: number): string
	return LeaderboardUtil.FormatCompact(value)
end

return WeeklyBestLogic
