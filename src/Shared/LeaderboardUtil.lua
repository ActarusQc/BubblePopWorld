--!strict
-- Utilitaires purs pour le classement Top Coins (testables hors DataStore).

local LeaderboardUtil = {}

local MAX_SCORE = 2 ^ 31 - 1

function LeaderboardUtil.SanitizeCoins(value: any): number?
	local n = tonumber(value)
	if type(n) ~= "number" then
		return nil
	end
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return math.clamp(math.floor(n), 0, MAX_SCORE)
end

function LeaderboardUtil.Comma(n: number): string
	local s = tostring(math.floor(math.max(0, n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function LeaderboardUtil.ParseUserIdKey(key: any): number?
	local userId = tonumber(key)
	if type(userId) ~= "number" or userId ~= userId or userId <= 0 then
		return nil
	end
	if userId ~= math.floor(userId) then
		return nil
	end
	return userId
end

export type RawEntry = { UserId: number, Name: string, Value: number }
export type BoardEntry = { Rank: number, UserId: number, Name: string, Value: number }

function LeaderboardUtil.SortDescending(entries: { RawEntry }): { RawEntry }
	local copy = table.clone(entries)
	table.sort(copy, function(a, b)
		if a.Value == b.Value then
			return a.UserId < b.UserId
		end
		return a.Value > b.Value
	end)
	return copy
end

function LeaderboardUtil.TakeTop(entries: { RawEntry }, limit: number): { BoardEntry }
	local sorted = LeaderboardUtil.SortDescending(entries)
	local out: { BoardEntry } = {}
	local n = math.min(limit, #sorted)
	for i = 1, n do
		local e = sorted[i]
		table.insert(out, {
			Rank = i,
			UserId = e.UserId,
			Name = e.Name,
			Value = e.Value,
		})
	end
	return out
end

function LeaderboardUtil.FormatLine(entry: BoardEntry): string
	return ("%d. %s — %s"):format(entry.Rank, entry.Name, LeaderboardUtil.Comma(entry.Value))
end

function LeaderboardUtil.FallbackName(userId: number): string
	return "Player " .. tostring(userId)
end

return LeaderboardUtil
