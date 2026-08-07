--!strict
-- Logique pure ancre transit Studio-owned.

local TransitAnchorLogic = {}

TransitAnchorLogic.NAME = "BubbleTransitInteractionAnchor"
TransitAnchorLogic.MANUAL_ATTR = "BPW_ManualPlacement"
TransitAnchorLogic.INIT_ATTR = "BPW_ManualPlacementInitialized"
TransitAnchorLogic.LEGACY_MIGRATED_ATTR = "BPW_LegacyTransitPoseMigrated"

-- Fallback / pose validée UNIQUEMENT si l'instance est absente, ou migration legacy.
TransitAnchorLogic.FALLBACK_SIZE = Vector3.new(6, 5, 7)
TransitAnchorLogic.FALLBACK_POSITION = Vector3.new(0, 8.5, 70.5)

-- Ancienne pose plugin BubbleTransitAnchorEditor (à corriger une seule fois).
TransitAnchorLogic.LEGACY_PLUGIN_SIZE = Vector3.new(2, 4, 2)
TransitAnchorLogic.LEGACY_PLUGIN_POSITION = Vector3.new(0, 8, 19)

function TransitAnchorLogic.MustNeverWriteCFrameOrSizeWhenExists(exists: boolean): boolean
	return exists == true
end

function TransitAnchorLogic.ShouldCreateFallback(exists: boolean): boolean
	return exists == false
end

function TransitAnchorLogic.FallbackCFrame(): CFrame
	return CFrame.new(TransitAnchorLogic.FALLBACK_POSITION)
end

local function near(a: number, b: number, e: number): boolean
	return math.abs(a - b) <= e
end

function TransitAnchorLogic.MatchesFallbackPose(size: Vector3, position: Vector3, epsilon: number?): boolean
	local e = epsilon or 0.05
	local wantS = TransitAnchorLogic.FALLBACK_SIZE
	local wantP = TransitAnchorLogic.FALLBACK_POSITION
	return near(size.X, wantS.X, e)
		and near(size.Y, wantS.Y, e)
		and near(size.Z, wantS.Z, e)
		and near(position.X, wantP.X, e)
		and near(position.Y, wantP.Y, e)
		and near(position.Z, wantP.Z, e)
end

--- True si la pose correspond à l'ancien fallback plugin (2x4x2 @ 0,8,19).
function TransitAnchorLogic.IsLegacyPluginPose(size: Vector3, position: Vector3, epsilon: number?): boolean
	local e = epsilon or 0.35
	local wantS = TransitAnchorLogic.LEGACY_PLUGIN_SIZE
	local wantP = TransitAnchorLogic.LEGACY_PLUGIN_POSITION
	return near(size.X, wantS.X, e)
		and near(size.Y, wantS.Y, e)
		and near(size.Z, wantS.Z, e)
		and near(position.X, wantP.X, e)
		and near(position.Y, wantP.Y, e)
		and near(position.Z, wantP.Z, e)
end

--- Migration unique : seulement legacy (0,8,19)/(2,4,2) et pas encore migrée.
function TransitAnchorLogic.ShouldMigrateLegacyPose(
	alreadyMigrated: boolean?,
	size: Vector3,
	position: Vector3
): boolean
	if alreadyMigrated == true then
		return false
	end
	return TransitAnchorLogic.IsLegacyPluginPose(size, position)
end

return TransitAnchorLogic
