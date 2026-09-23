--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = require(Shared.BubbleContactLogic)

local BubbleContactLogicTests = {}

function BubbleContactLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[BubbleContactLogicTests] FAIL:", msg)
			ok = false
		end
	end

	local bubble = Vector3.new(0, 6.35, 0)
	check(Logic.IsStandingOn(Vector3.new(0, 9.2, 0), 0, bubble, 6) == true, "debout sur la bulle")
	check(Logic.IsStandingOn(Vector3.new(0, 9.2, 0), 18, bubble, 6) == false, "ignore la montée de saut")
	check(Logic.IsStandingOn(Vector3.new(8, 9.2, 0), 0, bubble, 6) == false, "trop loin sur le côté")
	check(Logic.IsStandingOn(Vector3.new(0, 20, 0), 0, bubble, 6) == false, "trop haut")

	if ok then
		print("[BubbleContactLogicTests] ALL PASS")
	else
		warn("[BubbleContactLogicTests] SOME FAILED")
	end
	return ok
end

return BubbleContactLogicTests
