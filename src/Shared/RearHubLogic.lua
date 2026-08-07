--!strict
-- Placement hub Tripo INTÉGRÉ dans la grille de bulles (fond original, pas d'extension).
-- Entrée → bulles → bulles → plateau (dernières rangées) → mur nord d'origine.

local GameConfig = require(script.Parent.GameConfig)

local RearHubLogic = {}

export type BoundsXZ = {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	CenterX: number,
	CenterZ: number,
}

export type PlacementResult = {
	Center: Vector3,
	FrontSign: number,
	-- Limite arrière ORIGINALE de la salle (jamais agrandie par le plateau).
	OriginalRoomRearZ: number,
	OriginalRoomMinZ: number,
	OriginalRoomMinX: number,
	OriginalRoomMaxX: number,
	BubbleOuterMaxZ: number,
	BubbleOuterMinZ: number,
	ClearanceStuds: number, -- dégagement marche → bulles (2–4), pas hors grille
	PlatformFrontZ: number,
	PivotToFrontEdge: number,
	PlatformRearZ: number,
	-- Mur nord = fond original (pas platformRear + margin).
	RoomRearBoundaryZ: number,
	RearMargin: number,
	YawTowardBubbles: number,
}

function RearHubLogic.IsRearMode(hubConfig: any?): boolean
	local H = hubConfig or GameConfig.Hub
	local p = H and H.Placement
	return type(p) == "table" and p.Mode == "RearOfGrid"
end

function RearHubLogic.GetBubbleGridBounds(
	origin: Vector3?,
	sizeX: number?,
	sizeZ: number?,
	spacing: number?,
	bubbleSize: Vector3?
): BoundsXZ
	local G = GameConfig.Grid
	local o = origin or G.Origin
	local sx = sizeX or G.SizeX
	local sz = sizeZ or G.SizeZ
	local sp = spacing or G.Spacing
	local bs = bubbleSize or G.BubbleSize
	local halfB = math.max(bs.X, bs.Z) / 2
	local minCenterZ = o.Z + (1 - sz / 2) * sp
	local maxCenterZ = o.Z + (sz - sz / 2) * sp
	local minCenterX = o.X + (1 - sx / 2) * sp
	local maxCenterX = o.X + (sx - sx / 2) * sp
	return {
		MinX = minCenterX - halfB,
		MaxX = maxCenterX + halfB,
		MinZ = minCenterZ - halfB,
		MaxZ = maxCenterZ + halfB,
		CenterX = o.X,
		CenterZ = o.Z,
	}
end

--[[
  Limite arrière JOUABLE originale (alignée ZoneService safety borders, SANS extension hub).
  world Z du bord intérieur nord de la zone bulles + safetyGap.
]]
function RearHubLogic.GetOriginalRoomRearZ(): number
	local G = GameConfig.Grid
	local safetyGap = 2
	local bubbleExtentZ = ((G.SizeZ / 2) - 0.5) * G.Spacing + G.BubbleSize.Z / 2 + safetyGap
	return G.Origin.Z + bubbleExtentZ
end

function RearHubLogic.GetOriginalRoomBounds(): BoundsXZ
	local G = GameConfig.Grid
	local safetyGap = 2
	local bubbleExtentX = ((G.SizeX / 2) - 0.5) * G.Spacing + G.BubbleSize.X / 2 + safetyGap
	local rear = RearHubLogic.GetOriginalRoomRearZ()
	local front = G.Origin.Z - (((G.SizeZ / 2) - 0.5) * G.Spacing + G.BubbleSize.Z / 2 + safetyGap)
	return {
		MinX = G.Origin.X - bubbleExtentX,
		MaxX = G.Origin.X + bubbleExtentX,
		MinZ = front,
		MaxZ = rear,
		CenterX = G.Origin.X,
		CenterZ = G.Origin.Z,
	}
end

function RearHubLogic.GetRearMargin(hubConfig: any?): number
	local H = hubConfig or GameConfig.Hub
	local m = 1.5
	if type(H.Placement) == "table" and type(H.Placement.RearMarginStuds) == "number" then
		m = H.Placement.RearMarginStuds
	end
	return math.clamp(m, 1, 2)
end

-- Dégagement devant marche → bulles (2–4 studs), à l'INTÉRIEUR de la grille.
function RearHubLogic.GetClearanceStuds(hubConfig: any?): number
	local H = hubConfig or GameConfig.Hub
	local clear = 3
	if type(H.Placement) == "table" and type(H.Placement.ClearanceStuds) == "number" then
		clear = H.Placement.ClearanceStuds
	end
	return math.clamp(clear, 2, 4)
end

function RearHubLogic.GetDefaultPivotToFrontEdge(hubConfig: any?): number
	local H = hubConfig or GameConfig.Hub
	return H.DeckHalfZ
		+ H.Stairs.StepCount * H.Stairs.StepDepth
		+ H.Stairs.LandingDepth
end

function RearHubLogic.GetDefaultPivotToRearEdge(hubConfig: any?): number
	local H = hubConfig or GameConfig.Hub
	return H.DeckHalfZ + math.abs(H.Boards.OffsetZ) * 0.35
end

--[[
  INTÉGRATION dans la grille :
  platformRearZ = originalRoomMaxZ - rearMargin
  centerZ       = platformRearZ - pivotToRearEdge
  platformFrontZ = centerZ - pivotToFrontEdge
  (façade escaliers vers -Z / bulles)
]]
function RearHubLogic.ComputeRearPlacement(
	hubConfig: any?,
	pivotToFrontEdge: number?,
	pivotToRearEdge: number?
): PlacementResult
	local H = hubConfig or GameConfig.Hub
	local G = GameConfig.Grid
	local bubbleBounds = RearHubLogic.GetBubbleGridBounds()
	local room = RearHubLogic.GetOriginalRoomBounds()
	local rearMargin = RearHubLogic.GetRearMargin(H)
	local clear = RearHubLogic.GetClearanceStuds(H)
	local frontSign = -1

	local toFront = if type(pivotToFrontEdge) == "number" and pivotToFrontEdge > 0
		then pivotToFrontEdge
		else RearHubLogic.GetDefaultPivotToFrontEdge(H)
	local toRear = if type(pivotToRearEdge) == "number" and pivotToRearEdge > 0
		then pivotToRearEdge
		else RearHubLogic.GetDefaultPivotToRearEdge(H)

	local originalRoomRearZ = room.MaxZ
	local platformRearZ = originalRoomRearZ - rearMargin
	local centerZ = platformRearZ - toRear
	local platformFrontZ = centerZ - toFront

	return {
		Center = Vector3.new(G.Origin.X, H.DeckTopY, centerZ),
		FrontSign = frontSign,
		OriginalRoomRearZ = originalRoomRearZ,
		OriginalRoomMinZ = room.MinZ,
		OriginalRoomMinX = room.MinX,
		OriginalRoomMaxX = room.MaxX,
		BubbleOuterMaxZ = bubbleBounds.MaxZ,
		BubbleOuterMinZ = bubbleBounds.MinZ,
		ClearanceStuds = clear,
		PlatformFrontZ = platformFrontZ,
		PivotToFrontEdge = toFront,
		PlatformRearZ = platformRearZ,
		-- Mur nord fixe = fond original (PAS plateforme + margin).
		RoomRearBoundaryZ = originalRoomRearZ,
		RearMargin = rearMargin,
		YawTowardBubbles = 0,
	}
end

function RearHubLogic.CenterModeCenter(hubConfig: any?): Vector3
	local H = hubConfig or GameConfig.Hub
	local G = GameConfig.Grid
	return Vector3.new(G.Origin.X, H.DeckTopY, G.Origin.Z)
end

function RearHubLogic.ResolveHubCenter(hubConfig: any?): (Vector3, number, number)
	local H = hubConfig or GameConfig.Hub
	if RearHubLogic.IsRearMode(H) then
		local p = RearHubLogic.ComputeRearPlacement(H)
		return p.Center, p.FrontSign, p.YawTowardBubbles
	end
	return RearHubLogic.CenterModeCenter(H), 1, 180
end

-- Platform entièrement dans la salle originale.
function RearHubLogic.AssertPlatformInsideOriginalRoom(
	platformFrontZ: number,
	platformRearZ: number,
	originalMinZ: number,
	originalMaxZ: number
): boolean
	return platformFrontZ >= originalMinZ - 0.5
		and platformRearZ <= originalMaxZ + 0.05
		and platformRearZ > platformFrontZ
end

function RearHubLogic.AssertRearGapOk(originalRearZ: number, platformRearZ: number): boolean
	local gap = originalRearZ - platformRearZ
	return gap >= 0.5 - 1e-3 and gap <= 2.01
end

-- Ancien bug : plateau hors grille, mur suivi.
function RearHubLogic.AssertNotRoomExpandingPlacement(
	platformRearZ: number,
	originalRoomRearZ: number
): boolean
	return platformRearZ <= originalRoomRearZ + 1e-3
end

function RearHubLogic.AssertLandingClearanceOk(clearance: number): boolean
	return clearance >= 0 and clearance <= 4 + 1e-3
end

export type AabbXZ = {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
}

function RearHubLogic.AabbFromCenterSize(center: Vector3, size: Vector3): AabbXZ
	return {
		MinX = center.X - size.X / 2,
		MaxX = center.X + size.X / 2,
		MinZ = center.Z - size.Z / 2,
		MaxZ = center.Z + size.Z / 2,
	}
end

function RearHubLogic.AabbsOverlapXZ(a: AabbXZ, b: AabbXZ): boolean
	return a.MinX < b.MaxX and b.MinX < a.MaxX and a.MinZ < b.MaxZ and b.MinZ < a.MaxZ
end

function RearHubLogic.PointInAabbXZ(aabb: AabbXZ, x: number, z: number, expand: number?): boolean
	local e = expand or 0
	return x >= aabb.MinX - e
		and x <= aabb.MaxX + e
		and z >= aabb.MinZ - e
		and z <= aabb.MaxZ + e
end

function RearHubLogic.ExpandAabbFront(aabb: AabbXZ, frontDepth: number): AabbXZ
	-- Façade = MinZ (vers bulles / -Z)
	return {
		MinX = aabb.MinX,
		MaxX = aabb.MaxX,
		MinZ = aabb.MinZ - frontDepth,
		MaxZ = aabb.MaxZ,
	}
end

function RearHubLogic.CountBubblePlatformIntersections(
	platform: AabbXZ,
	origin: Vector3?,
	sizeX: number?,
	sizeZ: number?,
	spacing: number?,
	bubbleSize: Vector3?
): number
	local G = GameConfig.Grid
	local o = origin or G.Origin
	local sx = sizeX or G.SizeX
	local sz = sizeZ or G.SizeZ
	local sp = spacing or G.Spacing
	local bs = bubbleSize or G.BubbleSize
	local halfX = bs.X / 2
	local halfZ = bs.Z / 2
	local count = 0
	for x = 1, sx do
		for z = 1, sz do
			local pos = o + Vector3.new((x - sx / 2) * sp, 0, (z - sz / 2) * sp)
			local cell: AabbXZ = {
				MinX = pos.X - halfX,
				MaxX = pos.X + halfX,
				MinZ = pos.Z - halfZ,
				MaxZ = pos.Z + halfZ,
			}
			if RearHubLogic.AabbsOverlapXZ(platform, cell) then
				count += 1
			end
		end
	end
	return count
end

function RearHubLogic.CountCellsIntersectingAny(
	aabbs: { AabbXZ },
	origin: Vector3?,
	sizeX: number?,
	sizeZ: number?,
	spacing: number?,
	bubbleSize: Vector3?
): number
	if #aabbs == 0 then
		return 0
	end
	local G = GameConfig.Grid
	local o = origin or G.Origin
	local sx = sizeX or G.SizeX
	local sz = sizeZ or G.SizeZ
	local sp = spacing or G.Spacing
	local bs = bubbleSize or G.BubbleSize
	local halfX = bs.X / 2
	local halfZ = bs.Z / 2
	local count = 0
	for x = 1, sx do
		for z = 1, sz do
			local pos = o + Vector3.new((x - sx / 2) * sp, 0, (z - sz / 2) * sp)
			local cell: AabbXZ = {
				MinX = pos.X - halfX,
				MaxX = pos.X + halfX,
				MinZ = pos.Z - halfZ,
				MaxZ = pos.Z + halfZ,
			}
			for _, aabb in ipairs(aabbs) do
				if RearHubLogic.AabbsOverlapXZ(aabb, cell) then
					count += 1
					break
				end
			end
		end
	end
	return count
end

function RearHubLogic.ClearanceAfterBubbles(platformFrontZ: number, bubbleOuterMaxZ: number): number
	return platformFrontZ - bubbleOuterMaxZ
end

function RearHubLogic.IsClearanceInRange(clearance: number): boolean
	return RearHubLogic.AssertLandingClearanceOk(clearance)
end

-- Centre planche libre sauf si sous emprise hub.
function RearHubLogic.CenterCellShouldBePlayable(
	isCellReserved: (string?, number, number) -> boolean,
	sizeX: number,
	sizeZ: number
): boolean
	local cx = math.floor((sizeX + 1) / 2)
	local cz = math.floor((sizeZ + 1) / 2)
	return not isCellReserved("ClassicZone", cx, cz)
end

return RearHubLogic
