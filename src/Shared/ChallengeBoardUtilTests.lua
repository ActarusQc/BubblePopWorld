--!strict
-- Tests ChallengeBoardUtil (format lignes panneau Challenges 3D).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChallengeBoardUtil = require(Shared.ChallengeBoardUtil)

local ChallengeBoardUtilTests = {}

function ChallengeBoardUtilTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[ChallengeBoardUtilTests] FAIL:", msg)
		end
	end

	local function loc(key: string, fallback: string): string
		if key == "ChallengePopBubbles" then
			return "Pop bubbles"
		end
		if key == "ChallengeWeeklyPop" then
			return "Weekly: Pop bubbles"
		end
		return fallback
	end

	check(ChallengeBoardUtil.StatusMark(false) == "○", "todo mark")
	check(ChallengeBoardUtil.StatusMark(true) == "✓", "done mark")
	check(ChallengeBoardUtil.ProgressText(37, 50) == "37 / 50", "progress mid")
	check(ChallengeBoardUtil.ProgressText(500, 500) == "500 / 500", "progress done")

	local open = ChallengeBoardUtil.BuildLine({
		Id = "Pop_50",
		TitleKey = "ChallengePopBubbles",
		Progress = 327,
		Target = 500,
		Completed = false,
	}, loc)
	check(open.Status == "○", "open status")
	check(open.Title == "Pop bubbles", "title real")
	check(open.ProgressText == "327 / 500", "progress text")
	check(open.Completed == false, "not completed")

	local done = ChallengeBoardUtil.BuildLine({
		Id = "Pop_500",
		TitleKey = "ChallengePopBubbles",
		Progress = 500,
		Target = 500,
		Completed = true,
	}, loc)
	check(done.Status == "✓", "done checkmark")
	check(done.ProgressText == "500 / 500", "full progress")

	local daily = ChallengeBoardUtil.BuildDailyLines({
		{ Id = "a", TitleKey = "ChallengePopBubbles", Progress = 1, Target = 10 },
		{ Id = "b", TitleKey = "ChallengePopBubbles", Progress = 2, Target = 20 },
		{ Id = "c", TitleKey = "ChallengePopBubbles", Progress = 3, Target = 30 },
	}, loc, 2)
	check(#daily == 2, "cap daily 2")
	check(daily[1].Id == "a" and daily[2].Id == "b", "order daily")

	local weekly = ChallengeBoardUtil.BuildWeeklyLines({
		Id = "w",
		TitleKey = "ChallengeWeeklyPop",
		Progress = 10,
		Target = 100,
	}, loc, 3)
	check(#weekly == 1, "un seul weekly réel")
	check(weekly[1].Title == "Weekly: Pop bubbles", "weekly title")
	check(#ChallengeBoardUtil.BuildWeeklyLines(nil, loc, 3) == 0, "pas de fake weekly")

	-- Pas de fuite croisée : deux builds indépendants
	local aLines = ChallengeBoardUtil.BuildDailyLines({
		{ Id = "playerA", TitleKey = "ChallengePopBubbles", Progress = 1, Target = 5 },
	}, loc, 2)
	local bLines = ChallengeBoardUtil.BuildDailyLines({
		{ Id = "playerB", TitleKey = "ChallengePopBubbles", Progress = 4, Target = 5 },
	}, loc, 2)
	check(aLines[1].Id == "playerA" and bLines[1].Id == "playerB", "séparation joueur A/B")
	check(aLines[1].ProgressText ~= bLines[1].ProgressText, "progress distinctes")

	if failed == 0 then
		print("[ChallengeBoardUtilTests] OK")
		return true
	end
	return false
end

return ChallengeBoardUtilTests
