--!strict
-- Position de suivi d'un pet au sol, à côté des pieds du joueur.

local PetFollowLogic = {}

PetFollowLogic.FolderName = "BPW_Pets"
PetFollowLogic.CollisionGroup = "BPWPet"
PetFollowLogic.SideOffset = 2.4
PetFollowLogic.BackOffset = 2.6
PetFollowLogic.TargetHeight = 2.2

function PetFollowLogic.FeetY(rootPosition: Vector3, hipHeight: number, rootHeight: number): number
	return rootPosition.Y - hipHeight - rootHeight * 0.5
end

function PetFollowLogic.FollowCFrame(rootCFrame: CFrame, feetY: number, lift: number): CFrame
	local behind = rootCFrame * CFrame.new(PetFollowLogic.SideOffset, 0, PetFollowLogic.BackOffset)
	local pos = Vector3.new(behind.Position.X, feetY + lift, behind.Position.Z)
	local look = Vector3.new(rootCFrame.Position.X, pos.Y, rootCFrame.Position.Z)
	if (look - pos).Magnitude < 0.05 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, look)
end

return PetFollowLogic
