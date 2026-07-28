--!strict
-- Tests purs LeaderboardUtil (tri, format, clés, top 10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LeaderboardUtil = require(Shared.LeaderboardUtil)

local LeaderboardTests = {}

function LeaderboardTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[LeaderboardTests] FAIL:", msg)
		end
	end

	check(LeaderboardUtil.SanitizeCoins(12.9) == 12, "sanitize floor")
	check(LeaderboardUtil.SanitizeCoins(-3) == 0, "sanitize clamp min")
	check(LeaderboardUtil.SanitizeCoins("abc") == nil, "sanitize invalid")
	check(LeaderboardUtil.SanitizeCoins(math.huge) == nil, "sanitize inf")

	check(LeaderboardUtil.Comma(12450) == "12,450", "comma thousands")
	check(LeaderboardUtil.Comma(0) == "0", "comma zero")
	check(LeaderboardUtil.Comma(999) == "999", "comma under 1000")

	check(LeaderboardUtil.ParseUserIdKey("12345") == 12345, "parse userid string")
	check(LeaderboardUtil.ParseUserIdKey(99) == 99, "parse userid number")
	check(LeaderboardUtil.ParseUserIdKey("0") == nil, "parse userid 0 invalid")
	check(LeaderboardUtil.ParseUserIdKey("nope") == nil, "parse userid garbage")
	check(LeaderboardUtil.ParseUserIdKey(-5) == nil, "parse userid negative")

	local raw = {
		{ UserId = 1, Name = "A", Value = 10 },
		{ UserId = 2, Name = "B", Value = 50 },
		{ UserId = 3, Name = "C", Value = 30 },
		{ UserId = 4, Name = "D", Value = 50 },
	}
	local top = LeaderboardUtil.TakeTop(raw, 10)
	check(#top == 4, "top size")
	check(top[1].UserId == 2 and top[1].Rank == 1, "highest first (tie-break userid)")
	check(top[2].UserId == 4 and top[2].Rank == 2, "tie lower userid second")
	check(top[3].Value == 30, "third value")

	local many = {}
	for i = 1, 20 do
		table.insert(many, { UserId = i, Name = "P" .. i, Value = i * 10 })
	end
	local limited = LeaderboardUtil.TakeTop(many, 10)
	check(#limited == 10, "limit 10")
	check(limited[1].Value == 200 and limited[10].Value == 110, "desc top 10 values")

	local line = LeaderboardUtil.FormatLine({
		Rank = 1,
		UserId = 1,
		Name = "PlayerName",
		Value = 12450,
	})
	check(line == "1. PlayerName — 12,450", "format line")

	check(LeaderboardUtil.FallbackName(123456) == "Player 123456", "fallback name")

	-- État vide / erreur : TakeTop([]) → {}
	check(#LeaderboardUtil.TakeTop({}, 10) == 0, "empty ranking")

	-- Pas de doublons de rang
	local ranks = {}
	for _, e in ipairs(limited) do
		check(ranks[e.Rank] == nil, "unique ranks")
		ranks[e.Rank] = true
	end

	if failed == 0 then
		print("[LeaderboardTests] OK")
		return true
	end
	return false
end

return LeaderboardTests
