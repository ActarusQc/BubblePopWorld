--!strict
-- Règles pures pour le spawn hub manuel (testables hors Studio).

local HubSpawnLogic = {}

function HubSpawnLogic.IsManualPlacement(manualPlacement: boolean?, spawnManualInitialized: boolean?): boolean
	return manualPlacement == true or spawnManualInitialized == true
end

function HubSpawnLogic.ShouldRewriteSpawnCFrame(isManual: boolean): boolean
	return not isManual
end

function HubSpawnLogic.HorizontalDisplacement(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function HubSpawnLogic.IsSpawnCFramePreserved(studio: CFrame, runtime: CFrame, maxHoriz: number?, maxVert: number?): boolean
	local mh = if type(maxHoriz) == "number" then maxHoriz else 0.1
	local mv = if type(maxVert) == "number" then maxVert else 0.1
	local d = runtime.Position - studio.Position
	local horiz = math.sqrt(d.X * d.X + d.Z * d.Z)
	return horiz <= mh and math.abs(d.Y) <= mv
end

--- Ne plus repositionner le personnager après spawn natif.
function HubSpawnLogic.AllowsPostSpawnCharacterTeleport(_reason: string?): boolean
	return false
end

function HubSpawnLogic.UsesRobloxRespawnLocation(): boolean
	return true
end

--- Portail Bubble Transit ne doit jamais être la cible de spawn.
function HubSpawnLogic.IsPortalName(name: string): boolean
	return name == "BubbleTransitInteractionAnchor"
		or name == "PortalWalkSurface"
		or name == "PortalPad"
end

function HubSpawnLogic.PortalMustNotBeSpawn(spawnName: string, portalName: string): boolean
	return spawnName ~= portalName and not HubSpawnLogic.IsPortalName(spawnName)
end

function HubSpawnLogic.IsLargeYOffset(offset: number): boolean
	return math.abs(offset) >= 2.5
end

function HubSpawnLogic.MaxPostSpawnTeleports(): number
	return 0
end

function HubSpawnLogic.FootFloorGapOk(gap: number): boolean
	return gap >= -0.10 and gap <= 0.15
end

return HubSpawnLogic
