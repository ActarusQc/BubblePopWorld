--!strict
-- Tests purs HubDisplays (Studio-owned anchors, no runtime placement).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubDisplaysLogic = require(Shared.HubDisplaysLogic)
local HubDisplaysLayout = require(Shared.HubDisplaysLayout)
local LeaderboardUtil = require(Shared.LeaderboardUtil)

local HubDisplaysLogicTests = {}

function HubDisplaysLogicTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[HubDisplaysLogicTests] FAIL:", msg)
		end
	end

	check(#HubDisplaysLayout.ANCHORS == 3, "exactement 3 ancrages")
	local names: { [string]: boolean } = {}
	for _, a in ipairs(HubDisplaysLayout.ANCHORS) do
		check(names[a.Name] ~= true, "nom unique " .. a.Name)
		names[a.Name] = true
		check(type(a.PluginLocalOffset) == "vector" or typeof(a.PluginLocalOffset) == "Vector3", "plugin offset " .. a.Name)
		check(a.DefaultCreateSize.Z < 1, "thin part size " .. a.Name)
	end
	check(names.LeftLeaderboardAnchor == true, "Left")
	check(names.CenterLeaderboardAnchor == true, "Center")
	check(names.RightLeaderboardAnchor == true, "Right")

	check(HubDisplaysLayout.SpecByRole("Coins") ~= nil, "role Coins")
	check(HubDisplaysLayout.SpecByRole("WeeklyBest") ~= nil, "role WeeklyBest")
	check(HubDisplaysLayout.SpecByRole("Levels") ~= nil, "role Levels")

	-- Plugin transform: single pivot multiply (no double transform)
	local piv = CFrame.new(100, 12, 200)
	local left = HubDisplaysLayout.SpecByRole("Coins")
	assert(left)
	local w = HubDisplaysLayout.PluginWorldCFrame(piv, left)
	local expected = piv * CFrame.new(left.PluginLocalOffset) * CFrame.Angles(0, math.rad(left.PluginLocalYawDegrees), 0)
	check((w.Position - expected.Position).Magnitude < 0.01, "plugin world near tripo pivot")
	check(HubDisplaysLayout.DistanceXZ(w.Position, piv.Position) < 30, "plugin spawn within 30 of tripo")
	check(not HubDisplaysLayout.IsAnchorTooFarFromTripo(w.Position, piv.Position), "not too far")
	check(HubDisplaysLayout.IsAnchorTooFarFromTripo(Vector3.new(0, 0, 0), Vector3.new(100, 0, 0)) == true, "far flagged")

	-- Runtime must not depend on legacy local approx
	check(HubDisplaysLayout.MAX_DISTANCE_FROM_TRIPO == 30, "max dist 30")

	check(
		HubDisplaysLogic.ValidateAnchorProps({
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
		}),
		"props ok"
	)

	check(HubDisplaysLogic.SanitizeLevel(12.9) == 12, "level floor")
	check(HubDisplaysLogic.MergeHighestLevel(50, 40) == 50, "level never down")
	check(HubDisplaysLogic.ExpectedDebugAdornmentCount(true) == 3, "debug 3")
	check(HubDisplaysLogic.ExpectedDebugAdornmentCount(false) == 0, "debug 0")
	check(HubDisplaysLogic.ServiceStartsOnce(0) == 1, "single start")
	check(HubDisplaysLogic.ServiceStartsOnce(1) == 1, "idempotent start")
	check(HubDisplaysLogic.PreserveOnRefresh(true) == true, "preserve manual")
	check(#LeaderboardUtil.TakeTop({}, 10) == 0, "empty ranking")

	if failed == 0 then
		print("[HubDisplaysLogicTests] ALL PASS")
		return true
	end
	warn("[HubDisplaysLogicTests] SOME FAILED:", failed)
	return false
end

return HubDisplaysLogicTests
