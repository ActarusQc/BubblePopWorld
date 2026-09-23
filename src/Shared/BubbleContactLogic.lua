--!strict
-- Détection serveur : le joueur est-il posé sur une bulle ?

local BubbleContactLogic = {}

BubbleContactLogic.MaxAscentY = 4
BubbleContactLogic.MinAbove = 0.35
BubbleContactLogic.MaxAbove = 6.5
BubbleContactLogic.HorizontalFactor = 0.58

function BubbleContactLogic.IsStandingOn(
	rootPosition: Vector3,
	rootVelocityY: number,
	bubblePosition: Vector3,
	spacing: number
): boolean
	if rootVelocityY > BubbleContactLogic.MaxAscentY then
		return false
	end
	local offset = rootPosition - bubblePosition
	local horiz = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if horiz > spacing * BubbleContactLogic.HorizontalFactor then
		return false
	end
	if offset.Y < BubbleContactLogic.MinAbove or offset.Y > BubbleContactLogic.MaxAbove then
		return false
	end
	return true
end

return BubbleContactLogic
