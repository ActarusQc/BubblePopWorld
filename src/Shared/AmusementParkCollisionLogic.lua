--!strict
-- Politique de collision / animation des assets Tripo du parc.

local AmusementParkCollisionLogic = {}

local NON_SOLID = {
	WagonModele = true,
}

-- Bâtiments où l'on entre : PreciseConvex bouche les portes (rideaux, trou concave).
-- Le mesh reste visuel ; les parois proxy du builder portent la collision.
local WALK_IN = {
	Chapiteau = true,
}

local INTERIOR_VISIBLE = {
	Chapiteau = true,
	EntreeParc = true,
	StationEmbarquement = true,
	Ascenceur = true,
	AscenseurCommun = true,
}

local TENT_DOORWAY_HALF_ANGLE = 0.85

function AmusementParkCollisionLogic.ShouldMeshCollide(canonical: string): boolean
	return NON_SOLID[canonical] ~= true and WALK_IN[canonical] ~= true
end

function AmusementParkCollisionLogic.NeedsProxyInteriorCollision(canonical: string): boolean
	return WALK_IN[canonical] == true
end

function AmusementParkCollisionLogic.TentDoorwayHalfAngle(): number
	return TENT_DOORWAY_HALF_ANGLE
end

function AmusementParkCollisionLogic.EntranceAngleFromLocalLook(localLook: Vector3): number
	local flat = Vector3.new(localLook.X, 0, localLook.Z)
	if flat.Magnitude < 0.05 then
		return -math.pi / 2
	end
	flat = flat.Unit
	return math.atan2(flat.Z, flat.X)
end

function AmusementParkCollisionLogic.IsTentDoorwayAngle(angle: number, entranceAngle: number): boolean
	local difference = math.atan2(math.sin(angle - entranceAngle), math.cos(angle - entranceAngle))
	return math.abs(difference) < TENT_DOORWAY_HALF_ANGLE
end

-- Uniquement les petits occludeurs dans l'ouverture (jamais la coque Tripo).
function AmusementParkCollisionLogic.ShouldHideTentDoorwayPart(
	localPos: Vector3,
	partSize: Vector3,
	partColor: Color3,
	radius: number,
	entranceAngle: number,
	wallHeight: number
): boolean
	local flat = Vector3.new(localPos.X, 0, localPos.Z)
	local maxDim = math.max(partSize.X, partSize.Y, partSize.Z)
	if maxDim >= radius * 1.2 then
		return false
	end
	if flat.Magnitude < radius * 0.45 or flat.Magnitude > radius * 1.25 then
		return false
	end
	if localPos.Y < 0 or localPos.Y > wallHeight * 1.15 then
		return false
	end
	local angle = math.atan2(flat.Z, flat.X)
	if not AmusementParkCollisionLogic.IsTentDoorwayAngle(angle, entranceAngle) then
		return false
	end
	local isDark = (partColor.R + partColor.G + partColor.B) < 0.45
	return isDark or maxDim >= 3
end

function AmusementParkCollisionLogic.ShouldConcealTripoTentInterior(): boolean
	return false
end

function AmusementParkCollisionLogic.NeedsInteriorDoubleSided(canonical: string): boolean
	return INTERIOR_VISIBLE[canonical] == true
end

function AmusementParkCollisionLogic.ShouldComputePreciseConvex(canCollide: boolean, isPreview: boolean): boolean
	return canCollide == true and isPreview ~= true
end

function AmusementParkCollisionLogic.NeedsAnimatedCarouselClone(_hasAnimatedClone: boolean): boolean
	return false
end

function AmusementParkCollisionLogic.IsCarouselSourceClass(className: string): boolean
	return className == "Model"
		or className == "Folder"
		or className == "Part"
		or className == "MeshPart"
		or className == "UnionOperation"
end

function AmusementParkCollisionLogic.MatchesCarouselName(name: string): boolean
	local lower = string.lower(name)
	if string.find(lower, "collision", 1, true)
		or string.find(lower, "seat", 1, true)
		or string.find(lower, "boarding", 1, true)
		or string.find(lower, "sign", 1, true) then
		return false
	end
	return string.find(lower, "carou", 1, true) ~= nil
		or string.find(lower, "manege", 1, true) ~= nil
		or string.find(lower, "manège", 1, true) ~= nil
end

function AmusementParkCollisionLogic.IsKnownNonCarouselAsset(name: string): boolean
	local lower = string.lower(name)
	return string.find(lower, "chapiteau", 1, true) ~= nil
		or string.find(lower, "granderoue", 1, true) ~= nil
		or string.find(lower, "entree", 1, true) ~= nil
		or string.find(lower, "kiosque", 1, true) ~= nil
		or string.find(lower, "ascen", 1, true) ~= nil
		or string.find(lower, "station", 1, true) ~= nil
		or string.find(lower, "wagon", 1, true) ~= nil
		or string.find(lower, "blaster", 1, true) ~= nil
		or string.find(lower, "rollaball", 1, true) ~= nil
		or string.find(lower, "roll_a_ball", 1, true) ~= nil
		or string.find(lower, "roll-a-ball", 1, true) ~= nil
		or string.find(lower, "ferris", 1, true) ~= nil
end

function AmusementParkCollisionLogic.LooksLikeCarouselBounds(size: Vector3): boolean
	local xz = math.max(size.X, size.Z)
	if xz < 16 or xz > 70 then
		return false
	end
	local ratio = math.min(size.X, size.Z) / xz
	return ratio >= 0.72 and size.Y >= 6 and size.Y <= 45
end

function AmusementParkCollisionLogic.ShouldArchiveCarouselSource(_isPreview: boolean): boolean
	return false
end

function AmusementParkCollisionLogic.CarouselCollisionFidelity(): Enum.CollisionFidelity
	return Enum.CollisionFidelity.Hull
end

function AmusementParkCollisionLogic.CarouselHullDiameterScale(): number
	return 1.08
end

function AmusementParkCollisionLogic.IsGeneratedLayoutName(name: string): boolean
	return name == "GeneratedLayout"
end

function AmusementParkCollisionLogic.PreferStudioCarouselOverGenerated(): boolean
	return true
end

function AmusementParkCollisionLogic.FerrisBaseShouldCollide(): boolean
	return true
end

function AmusementParkCollisionLogic.FerrisSpinningWheelShouldCollide(): boolean
	return false
end

return AmusementParkCollisionLogic
