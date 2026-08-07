--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RearHubCollisionLogic = require(Shared.RearHubCollisionLogic)

local RearHubCollisionLogicTests = {}

function RearHubCollisionLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[RearHubCollisionLogicTests] FAIL:", msg)
			ok = false
		end
	end

	local visualTop = 24.5
	local walkTop = RearHubCollisionLogic.WalkSurfaceTopY(visualTop)
	check(walkTop > visualTop, "walk surface above visual")
	check(walkTop - visualTop <= 0.08, "walk offset <= 0.08")
	check(walkTop - visualTop >= 0.02, "walk offset >= 0.02")

	local thick = RearHubCollisionLogic.WALK_THICKNESS
	local centerY = RearHubCollisionLogic.PartCenterYFromTop(walkTop, thick)
	check(math.abs((centerY + thick / 2) - walkTop) < 1e-6, "top de part = walkTop")

	local portal = Vector3.new(0, 12, 100)
	local spawnXZ = RearHubCollisionLogic.SafeSpawnXZ(Vector3.new(0, 12, 100), 70, 120, 10)
	check(RearHubCollisionLogic.IsSpawnFarEnoughFromPortal(spawnXZ, portal),
		"spawn décalé du portail (>=12)")
	check(spawnXZ.X ~= portal.X or math.abs(spawnXZ.Z - portal.Z) >= 8, "pas superposé XZ portail")

	local tooClose = Vector3.new(1, 12, 101)
	check(not RearHubCollisionLogic.IsSpawnFarEnoughFromPortal(tooClose, portal), "trop près détecté")

	local rise = 8
	local depth = RearHubCollisionLogic.RampDepthForRise(rise)
	check(RearHubCollisionLogic.RampAngleOk(rise, depth), "rampe pente OK")
	check(not RearHubCollisionLogic.RampAngleOk(10, 2), "marche trop raide refusee")

	check(RearHubCollisionLogic.ShouldPreserveManualAnchorCFrame(true) == true, "manual preserve")
	check(RearHubCollisionLogic.ShouldPreserveManualAnchorCFrame(false) == false, "non-manual")
	check(RearHubCollisionLogic.ShouldPreserveManualAnchorCFrame(nil) == false, "nil non-manual")

	local rootY = RearHubCollisionLogic.HumanoidRootSpawnY(12, 2, 2)
	check(rootY > 12 + 2, "HRP au-dessus surface")

	if ok then
		print("[RearHubCollisionLogicTests] ALL PASS")
	else
		warn("[RearHubCollisionLogicTests] SOME FAILED")
	end
	return ok
end

return RearHubCollisionLogicTests
