--!strict
-- Géométrie pure : surface de marche, spawn safe, rampes d'accès.

local RearHubCollisionLogic = {}

RearHubCollisionLogic.WALK_SURFACE_OFFSET = 0.05 -- 0.02..0.08 max au-dessus du visuel
RearHubCollisionLogic.WALK_THICKNESS = 0.4
RearHubCollisionLogic.TRIGGER_LIFT = 1.2
RearHubCollisionLogic.SPAWN_MARGIN = 0.05
RearHubCollisionLogic.MIN_SPAWN_PORTAL_DIST = 12
RearHubCollisionLogic.MAX_RAMP_RISE_PER_STUD = 0.55 -- pente douce
RearHubCollisionLogic.MAX_VISUAL_COLLISION_DELTA = 0.08

function RearHubCollisionLogic.WalkSurfaceTopY(portalVisualTopY: number): number
	local offset = math.clamp(
		RearHubCollisionLogic.WALK_SURFACE_OFFSET,
		0.02,
		RearHubCollisionLogic.MAX_VISUAL_COLLISION_DELTA
	)
	return portalVisualTopY + offset
end

function RearHubCollisionLogic.PartCenterYFromTop(topY: number, thickness: number): number
	return topY - thickness / 2
end

function RearHubCollisionLogic.SpawnCenterY(walkTopY: number, spawnHeight: number): number
	local spawnTop = walkTopY + RearHubCollisionLogic.SPAWN_MARGIN
	return spawnTop - spawnHeight / 2
end

function RearHubCollisionLogic.HumanoidRootSpawnY(floorTopY: number, hipHeight: number, rootHeight: number): number
	return floorTopY + hipHeight + rootHeight / 2 + 0.05
end

function RearHubCollisionLogic.TriggerCenterY(walkTopY: number): number
	return walkTopY + RearHubCollisionLogic.TRIGGER_LIFT
end

function RearHubCollisionLogic.PortalDiameter(padDiameter: number, platformMinXZ: number): number
	local fromPad = math.max(10, padDiameter)
	local fromPlatform = math.max(8, platformMinXZ * 0.42)
	return math.clamp(math.min(fromPad * 1.15, fromPlatform), 10, 36)
end

function RearHubCollisionLogic.YDeltaFromLayoutDeck(measuredDeckTopY: number, layoutDeckTopY: number): number
	return measuredDeckTopY - layoutDeckTopY
end

function RearHubCollisionLogic.ProxyCenterWithDelta(center: Vector3, yDelta: number): Vector3
	return Vector3.new(center.X, center.Y + yDelta, center.Z)
end

--- Spawn décalé du portail (vers escaliers / +X) sur le plancher principal.
function RearHubCollisionLogic.SafeSpawnXZ(
	hubCenter: Vector3,
	platformFrontZ: number,
	platformRearZ: number,
	sideOffsetX: number?
): Vector3
	local sx = if type(sideOffsetX) == "number" then sideOffsetX else 10
	-- Avant-milieu du plateau (entre centre et escaliers), pas le disque portail central.
	local midZ = (hubCenter.Z + platformFrontZ) * 0.5
	local z = math.clamp(midZ, math.min(platformFrontZ, platformRearZ) + 2, math.max(platformFrontZ, platformRearZ) - 2)
	return Vector3.new(hubCenter.X + sx, 0, z)
end

function RearHubCollisionLogic.DistanceXZ(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function RearHubCollisionLogic.IsSpawnFarEnoughFromPortal(spawnPos: Vector3, portalPos: Vector3): boolean
	return RearHubCollisionLogic.DistanceXZ(spawnPos, portalPos) >= RearHubCollisionLogic.MIN_SPAWN_PORTAL_DIST - 1e-3
end

--- Rampe : profondeur horizontale et élévation. Pente max pour rester monteeable.
function RearHubCollisionLogic.RampDepthForRise(rise: number): number
	local riseClamped = math.max(0.5, rise)
	return math.max(6, riseClamped / RearHubCollisionLogic.MAX_RAMP_RISE_PER_STUD)
end

function RearHubCollisionLogic.RampAngleOk(rise: number, depth: number): boolean
	if depth < 0.5 then
		return false
	end
	return (rise / depth) <= RearHubCollisionLogic.MAX_RAMP_RISE_PER_STUD + 1e-3
end

function RearHubCollisionLogic.ShouldPreserveManualAnchorCFrame(manualPlacement: boolean?): boolean
	return manualPlacement == true
end

function RearHubCollisionLogic.ShouldPreserveManualSpawnCFrame(manualPlacement: boolean?, spawnManualInitialized: boolean?): boolean
	return manualPlacement == true or spawnManualInitialized == true
end

return RearHubCollisionLogic
