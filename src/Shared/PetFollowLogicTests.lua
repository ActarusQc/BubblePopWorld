--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = require(Shared.PetFollowLogic)

local PetFollowLogicTests = {}

function PetFollowLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[PetFollowLogicTests] FAIL:", msg)
			ok = false
		end
	end

	local root = CFrame.new(0, 6, 0)
	local feet = Logic.FeetY(root.Position, 2, 2)
	check(feet < root.Position.Y - 2, "les pieds sont sous le HumanoidRootPart")
	local grounded = Logic.FollowCFrame(root, feet, 0)
	local jumped = Logic.FollowCFrame(root * CFrame.new(0, 8, 0), Logic.FeetY((root * CFrame.new(0, 8, 0)).Position, 2, 2), 0)
	check(grounded.Position.Y < root.Position.Y, "le toutou reste aux pieds au sol")
	check(jumped.Position.Y > grounded.Position.Y, "le toutou s'élève seulement si le personnage saute")
	check(grounded.Position.Z > 0, "le toutou reste derrière le joueur")
	check(Logic.TargetHeight >= 2 and Logic.TargetHeight <= 2.5, "toutou à hauteur de genou")
	check(Logic.CollisionGroup == "BPWPet", "groupe de collision ghost")

	if ok then
		print("[PetFollowLogicTests] ALL PASS")
	else
		warn("[PetFollowLogicTests] SOME FAILED")
	end
	return ok
end

return PetFollowLogicTests
