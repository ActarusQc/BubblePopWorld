--!strict
-- Geometrie pure du hub (Concept 2 + placement RearOfGrid).
-- Aucune Instance : CFrames / tailles derivees de GameConfig.Hub.
--
-- Orientation reference maquette (local) :
--   +Z local = ouverture / escaliers (face aux bulles)
--   -Z local = panneaux
--   -X = SHOP, +X = SELL (joueur face aux bulles)
-- FrontSign mappe le +Z local en monde : +1 (centre) ou -1 (fond de grille, face -Z).

local GameConfig = require(script.Parent.GameConfig)
local ZoneDefs = require(script.Parent.ZoneDefs)
local RearHubLogic = require(script.Parent.RearHubLogic)

local H = GameConfig.Hub
local G = GameConfig.Grid

local HubLayout = {}

HubLayout.ZoneId = "ClassicZone"

local resolvedCenter, resolvedFrontSign, resolvedFaceYaw = RearHubLogic.ResolveHubCenter(H)
HubLayout.Center = resolvedCenter
HubLayout.FrontSign = resolvedFrontSign
HubLayout.FaceYawDegrees = resolvedFaceYaw
-- Rempli runtime par RearHubMigration (bbox réel).
HubLayout.RuntimePlatformFrontZ = nil :: number?
HubLayout.RuntimePlatformRearZ = nil :: number?
HubLayout.RuntimeRoomRearZ = nil :: number?
HubLayout.RuntimePortalWalkTopY = nil :: number?
HubLayout.RuntimeDeckTopY = nil :: number?
-- Emprises de réserve exactes (AABB) — intersection cellule par cellule, pas rectangle global.
HubLayout.RuntimeReserveAabbs = nil :: { RearHubLogic.AabbXZ }?

export type Rect = {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
}

export type ModuleSpec = {
	Name: string,
	Center: Vector3,
	Size: Vector3,
	YawDegrees: number,
	Kind: string,
	Circular: boolean,
}

function HubLayout.LocalOffset(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, offset.Z * HubLayout.FrontSign)
end

function HubLayout.FrontWorldZ(centerZ: number, localZ: number): number
	return centerZ + localZ * HubLayout.FrontSign
end

function HubLayout.WorldExtents(size: Vector3, yawDegrees: number): Vector3
	local rad = math.rad(yawDegrees)
	local c, s = math.abs(math.cos(rad)), math.abs(math.sin(rad))
	return Vector3.new(
		size.X * c + size.Z * s,
		size.Y,
		size.X * s + size.Z * c
	)
end

--------------------------------------------------------------------
-- Deck
--------------------------------------------------------------------
HubLayout.Deck = {
	HalfX = H.DeckHalfX,
	HalfZ = H.DeckHalfZ,
	Chamfer = H.DeckChamfer,
	Thickness = H.DeckThickness,
	TopY = H.DeckTopY,
	DiagonalLimit = H.DeckHalfX + H.DeckHalfZ - H.DeckChamfer,
}

export type SlabSpec = {
	Name: string,
	Size: Vector3,
	Center: Vector3,
	YawDegrees: number,
	IsWedge: boolean,
}

local function plateYawFor(signX: number, signZ: number): number
	if signX > 0 and signZ > 0 then
		return 0
	elseif signX > 0 then
		return 90
	elseif signZ < 0 then
		return 180
	end
	return 270
end

local CORNER_SIGNS = {
	{ Name = "FrontRight", X = 1, Z = 1 },
	{ Name = "FrontLeft", X = -1, Z = 1 },
	{ Name = "BackRight", X = 1, Z = -1 },
	{ Name = "BackLeft", X = -1, Z = -1 },
}

function HubLayout.GetOctagonSlabs(
	prefix: string,
	halfX: number,
	halfZ: number,
	chamfer: number,
	thickness: number,
	topY: number
): { SlabSpec }
	local cx, cz = HubLayout.Center.X, HubLayout.Center.Z
	local y = topY - thickness / 2
	local flatHalfX = halfX - chamfer
	local flatHalfZ = halfZ - chamfer
	local slabs: { SlabSpec } = {
		{
			Name = prefix .. "Middle",
			Size = Vector3.new(halfX * 2, thickness, flatHalfZ * 2),
			Center = Vector3.new(cx, y, cz),
			YawDegrees = 0,
			IsWedge = false,
		},
		{
			Name = prefix .. "Front",
			Size = Vector3.new(flatHalfX * 2, thickness, chamfer),
			Center = Vector3.new(cx, y, HubLayout.FrontWorldZ(cz, flatHalfZ + chamfer / 2)),
			YawDegrees = 0,
			IsWedge = false,
		},
		{
			Name = prefix .. "Back",
			Size = Vector3.new(flatHalfX * 2, thickness, chamfer),
			Center = Vector3.new(cx, y, HubLayout.FrontWorldZ(cz, -(flatHalfZ + chamfer / 2))),
			YawDegrees = 0,
			IsWedge = false,
		},
	}
	for _, corner in ipairs(CORNER_SIGNS) do
		table.insert(slabs, {
			Name = prefix .. corner.Name,
			Size = Vector3.new(thickness, chamfer, chamfer),
			Center = Vector3.new(
				cx + corner.X * (halfX - chamfer / 2),
				y,
				HubLayout.FrontWorldZ(cz, corner.Z * (halfZ - chamfer / 2))
			),
			YawDegrees = plateYawFor(corner.X, corner.Z * HubLayout.FrontSign),
			IsWedge = true,
		})
	end
	return slabs
end

function HubLayout.GetDeckSlabs(): { SlabSpec }
	return HubLayout.GetOctagonSlabs("Deck", H.DeckHalfX, H.DeckHalfZ, H.DeckChamfer, H.DeckThickness, H.DeckTopY)
end

HubLayout.Plinth = {
	Inset = 2.5,
	Thickness = 1.8,
}

function HubLayout.GetPlinthSlabs(): { SlabSpec }
	local inset = HubLayout.Plinth.Inset
	return HubLayout.GetOctagonSlabs(
		"Plinth",
		H.DeckHalfX - inset,
		H.DeckHalfZ - inset,
		H.DeckChamfer,
		HubLayout.Plinth.Thickness,
		H.DeckTopY - H.DeckThickness
	)
end

function HubLayout.GetFoundation(): (Vector3, Vector3)
	local inset = 7
	local floorTopY = G.Origin.Y - G.BubbleSize.Y * 0.35
	local bottomY = floorTopY - 0.8
	local topY = H.DeckTopY - H.DeckThickness - HubLayout.Plinth.Thickness
	local height = math.max(1, topY - bottomY)
	local size = Vector3.new((H.DeckHalfX - inset) * 2, height, (H.DeckHalfZ - inset) * 2)
	local center = Vector3.new(HubLayout.Center.X, bottomY + height / 2, HubLayout.Center.Z)
	return size, center
end

export type ChamferSpec = {
	Name: string,
	SignX: number,
	SignZ: number,
	Leg: number,
	Corner: Vector3,
	EdgeCenter: Vector3,
	EdgeLength: number,
	EdgeYawDegrees: number,
}

local function chamferSpec(name: string, signX: number, signZLocal: number): ChamferSpec
	local leg = H.DeckChamfer
	local cornerX = HubLayout.Center.X + signX * H.DeckHalfX
	local cornerZ = HubLayout.FrontWorldZ(HubLayout.Center.Z, signZLocal * H.DeckHalfZ)
	local signZWorld = signZLocal * HubLayout.FrontSign
	local aX, aZ = cornerX - signX * leg, cornerZ
	local bX, bZ = cornerX, cornerZ - signZWorld * leg
	return {
		Name = name,
		SignX = signX,
		SignZ = signZLocal,
		Leg = leg,
		Corner = Vector3.new(cornerX, H.DeckTopY, cornerZ),
		EdgeCenter = Vector3.new((aX + bX) / 2, H.DeckTopY, (aZ + bZ) / 2),
		EdgeLength = leg * math.sqrt(2),
		EdgeYawDegrees = if signX * signZWorld > 0 then 45 else -45,
	}
end

HubLayout.Chamfers = {
	chamferSpec("FrontRight", 1, 1),
	chamferSpec("FrontLeft", -1, 1),
	chamferSpec("BackRight", 1, -1),
	chamferSpec("BackLeft", -1, -1),
} :: { ChamferSpec }

local deckTop = H.DeckTopY
local sideTop = deckTop + H.SidePlatform.Rise

local function yawCF(center: Vector3, yawDegrees: number): CFrame
	return CFrame.new(center) * CFrame.Angles(0, math.rad(yawDegrees), 0)
end

HubLayout.YawCFrame = yawCF

local faceYaw = HubLayout.FaceYawDegrees

HubLayout.Spawn = {
	PadDiameter = H.Spawn.PadDiameter,
	PadHeight = H.Spawn.PadHeight,
	YawDegrees = faceYaw,
}

function HubLayout.GetSpawnCenter(): Vector3
	return HubLayout.Center + HubLayout.LocalOffset(H.Spawn.Offset)
end

-- Center suit HubLayout.Center (recalculé après placement bbox runtime).
setmetatable(HubLayout.Spawn :: any, {
	__index = function(_, k)
		if k == "Center" then
			return HubLayout.GetSpawnCenter()
		end
		return nil
	end,
})

function HubLayout.GetSpawnCFrame(): CFrame
	local base = HubLayout.GetSpawnCenter() + Vector3.new(0, H.Spawn.PadHeight + 0.5, 0)
	return yawCF(base, HubLayout.Spawn.YawDegrees)
end

HubLayout.LoopPanel = {
	Center = HubLayout.Center
		+ HubLayout.LocalOffset(H.LoopPanel.Offset)
		+ Vector3.new(0, H.LoopPanel.PlinthHeight + H.LoopPanel.Size.Y / 2, 0),
	Size = H.LoopPanel.Size,
	YawDegrees = faceYaw,
	PlinthHeight = H.LoopPanel.PlinthHeight,
}

local boardCenterY = deckTop + H.Boards.BottomAboveDeck + H.Boards.Size.Y / 2
local boardBottomY = deckTop + H.Boards.BottomAboveDeck

local function boardZ(): number
	return HubLayout.FrontWorldZ(HubLayout.Center.Z, H.Boards.OffsetZ)
end

local function boardMeta(offsetX: number)
	return setmetatable({
		Size = H.Boards.Size,
		YawDegrees = faceYaw,
		BottomY = boardBottomY,
	}, {
		__index = function(_, k)
			if k == "Center" then
				return Vector3.new(HubLayout.Center.X + offsetX, boardCenterY, boardZ())
			end
			return nil
		end,
	})
end

HubLayout.TopBoard = boardMeta(-H.Boards.OffsetX)
HubLayout.WeeklyBoard = boardMeta(0)
HubLayout.RulesBoard = boardMeta(H.Boards.OffsetX)
HubLayout.ChallengesBoard = HubLayout.RulesBoard

local function sidePlatformMeta(signX: number)
	return setmetatable({
		Size = H.SidePlatform.Size,
		TopY = sideTop,
	}, {
		__index = function(_, k)
			if k == "Center" then
				return Vector3.new(
					HubLayout.Center.X + signX * H.SidePlatform.OffsetX,
					deckTop + H.SidePlatform.Rise - H.SidePlatform.Size.Y / 2,
					HubLayout.Center.Z
				)
			end
			return nil
		end,
	})
end

HubLayout.SellPlatform = sidePlatformMeta(1)
HubLayout.ShopPlatform = sidePlatformMeta(-1)

function HubLayout.GetSellBaseCFrame(): CFrame
	local origin = Vector3.new(
		HubLayout.Center.X + H.SidePlatform.OffsetX,
		sideTop,
		HubLayout.Center.Z
	)
	return yawCF(origin, H.Sell.YawDegrees)
end

function HubLayout.GetSellZoneCFrame(): CFrame
	return HubLayout.GetSellBaseCFrame() * CFrame.new(H.Sell.ZoneLocalOffset)
end

function HubLayout.GetShopBaseCFrame(): CFrame
	local origin = Vector3.new(
		HubLayout.Center.X - H.SidePlatform.OffsetX,
		sideTop,
		HubLayout.Center.Z
	)
	return yawCF(origin, H.Shop.YawDegrees)
end

function HubLayout.GetShopOrigin(): Vector3
	return Vector3.new(
		HubLayout.Center.X - H.SidePlatform.OffsetX,
		sideTop,
		HubLayout.Center.Z
	)
end

function HubLayout.GetTransitPosition(): Vector3
	local o = HubLayout.LocalOffset(H.Transit.Offset)
	return Vector3.new(HubLayout.Center.X + o.X, deckTop, HubLayout.Center.Z + o.Z)
end

function HubLayout.GetTransitAlcoveCenter(): Vector3
	return HubLayout.GetTransitPosition()
end

function HubLayout.GetTransitCFrame(): CFrame
	return yawCF(HubLayout.GetTransitPosition(), faceYaw)
end

function HubLayout.GetBubbleTransitMaxActivationDistance(): number
	return 5.5
end

function HubLayout.GetBubbleTransitTriggerCFrame(floorTopY: number?): CFrame
	local floorY = if type(floorTopY) == "number" then floorTopY else deckTop
	local chestY = floorY + 3.2
	local o = HubLayout.LocalOffset(Vector3.new(0, 0, -16.5))
	local pos = Vector3.new(HubLayout.Center.X + o.X, chestY, HubLayout.Center.Z + o.Z)
	return yawCF(pos, faceYaw)
end

export type RailSpec = {
	Name: string,
	Size: Vector3,
	Center: Vector3,
	YawDegrees: number,
}

function HubLayout.GetPerimeterSegments(height: number, thickness: number, centerY: number): { RailSpec }
	local cx, cz = HubLayout.Center.X, HubLayout.Center.Z
	local halfX, halfZ, ch = H.DeckHalfX, H.DeckHalfZ, H.DeckChamfer
	local flatHalfX = halfX - ch
	local flatHalfZ = halfZ - ch
	local opening = HubLayout.GetFrontOpeningHalfWidth()
	local segments: { RailSpec } = {}
	local frontSide = flatHalfX - opening
	if frontSide > 0.5 then
		for _, sign in ipairs({ -1, 1 }) do
			table.insert(segments, {
				Name = if sign < 0 then "RailFrontLeft" else "RailFrontRight",
				Size = Vector3.new(frontSide, height, thickness),
				Center = Vector3.new(
					cx + sign * (opening + frontSide / 2),
					centerY,
					HubLayout.FrontWorldZ(cz, halfZ - thickness / 2)
				),
				YawDegrees = 0,
			})
		end
	end
	table.insert(segments, {
		Name = "RailBack",
		Size = Vector3.new(flatHalfX * 2, height, thickness),
		Center = Vector3.new(cx, centerY, HubLayout.FrontWorldZ(cz, -(halfZ - thickness / 2))),
		YawDegrees = 0,
	})
	for _, sign in ipairs({ -1, 1 }) do
		table.insert(segments, {
			Name = if sign < 0 then "RailWest" else "RailEast",
			Size = Vector3.new(thickness, height, flatHalfZ * 2),
			Center = Vector3.new(cx + sign * (halfX - thickness / 2), centerY, cz),
			YawDegrees = 0,
		})
	end
	for _, chamfer in ipairs(HubLayout.Chamfers) do
		table.insert(segments, {
			Name = "Rail" .. chamfer.Name,
			Size = Vector3.new(chamfer.EdgeLength, height, thickness),
			Center = Vector3.new(chamfer.EdgeCenter.X, centerY, chamfer.EdgeCenter.Z),
			YawDegrees = chamfer.EdgeYawDegrees,
		})
	end
	return segments
end

function HubLayout.GetRailings(): { RailSpec }
	return HubLayout.GetPerimeterSegments(
		H.RailingHeight,
		H.RailingThickness,
		H.DeckTopY + H.RailingHeight / 2
	)
end

export type StepSpec = {
	Index: number,
	Size: Vector3,
	Center: Vector3,
	TopY: number,
}

function HubLayout.GetStairSteps(): { StepSpec }
	local S = H.Stairs
	local steps: { StepSpec } = {}
	local startZ = HubLayout.FrontWorldZ(HubLayout.Center.Z, H.DeckHalfZ)
	for i = 1, S.StepCount do
		local topY = deckTop - i * S.StepRise
		local thickness = S.StepRise + 1.2
		local centerZ = startZ + HubLayout.FrontSign * (i - 0.5) * S.StepDepth
		table.insert(steps, {
			Index = i,
			Size = Vector3.new(S.Width, thickness, S.StepDepth),
			Center = Vector3.new(HubLayout.Center.X, topY - thickness / 2, centerZ),
			TopY = topY,
		})
	end
	return steps
end

function HubLayout.GetStairsEndZ(): number
	return HubLayout.FrontWorldZ(
		HubLayout.Center.Z,
		H.DeckHalfZ + H.Stairs.StepCount * H.Stairs.StepDepth
	)
end

function HubLayout.GetStairsBottomY(): number
	return deckTop - H.Stairs.StepCount * H.Stairs.StepRise
end

function HubLayout.GetLandingDepth(): number
	local S = H.Stairs
	-- RearOfGrid : clearance fixe vers bulles — ne pas étendre le palier dans la grille.
	if HubLayout.FrontSign < 0 or HubLayout.IsRearPlacement() then
		return S.LandingDepth
	end
	local endZ = HubLayout.GetStairsEndZ()
	local first = HubLayout.GetFirstLiveBubbleEdgeZ()
	local gap = HubLayout.FrontSign * (first - endZ)
	return math.max(S.LandingDepth, gap)
end

function HubLayout.GetLanding(): (Vector3, Vector3)
	local S = H.Stairs
	local endZ = HubLayout.GetStairsEndZ()
	local topY = HubLayout.GetStairsBottomY()
	local depth = HubLayout.GetLandingDepth()
	local thickness = 1.2
	local size = Vector3.new(S.Width, thickness, depth)
	local center = Vector3.new(
		HubLayout.Center.X,
		topY - thickness / 2,
		endZ + HubLayout.FrontSign * depth / 2
	)
	return size, center
end

function HubLayout.GetFrontOpeningHalfWidth(): number
	return H.Stairs.Width / 2 + 1
end

function HubLayout.GetPlatformFrontZ(): number
	if type(HubLayout.RuntimePlatformFrontZ) == "number" then
		return HubLayout.RuntimePlatformFrontZ :: number
	end
	if HubLayout.IsRearPlacement() then
		return RearHubLogic.ComputeRearPlacement().PlatformFrontZ
	end
	return HubLayout.FrontWorldZ(HubLayout.Center.Z, H.DeckHalfZ)
end

function HubLayout.IsInsideDeckFootprint(x: number, z: number, expand: number?): boolean
	local e = expand or 0
	local dx = math.abs(x - HubLayout.Center.X)
	local dz = math.abs(z - HubLayout.Center.Z)
	if dx > H.DeckHalfX + e or dz > H.DeckHalfZ + e then
		return false
	end
	return dx + dz <= HubLayout.Deck.DiagonalLimit + e * math.sqrt(2)
end

function HubLayout.GetStairsRect(): Rect
	local S = H.Stairs
	local startZ = HubLayout.FrontWorldZ(HubLayout.Center.Z, H.DeckHalfZ)
	local endZ = HubLayout.GetStairsEndZ() + HubLayout.FrontSign * S.LandingDepth
	return {
		MinX = HubLayout.Center.X - S.Width / 2,
		MaxX = HubLayout.Center.X + S.Width / 2,
		MinZ = math.min(startZ, endZ),
		MaxZ = math.max(startZ, endZ),
	}
end

local function insideRect(rect: Rect, x: number, z: number, expand: number): boolean
	return x >= rect.MinX - expand
		and x <= rect.MaxX + expand
		and z >= rect.MinZ - expand
		and z <= rect.MaxZ + expand
end

function HubLayout.IsWorldPointReserved(x: number, z: number, expand: number?): boolean
	local e = expand or 0
	-- RearOfGrid intégré : réserve uniquement les AABB runtime (bbox plateau + collisions + palier 2–4).
	if HubLayout.IsRearPlacement() then
		local list = HubLayout.RuntimeReserveAabbs
		if type(list) == "table" and #list > 0 then
			for _, aabb in ipairs(list) do
				if RearHubLogic.PointInAabbXZ(aabb, x, z, e) then
					return true
				end
			end
			return false
		end
		-- Fallback layout (avant metrics runtime) : emprise étroite deck + escaliers.
		if HubLayout.IsInsideDeckFootprint(x, z, H.ReserveMargin + e) then
			return true
		end
		return insideRect(HubLayout.GetStairsRect(), x, z, e)
	end
	if HubLayout.IsInsideDeckFootprint(x, z, H.ReserveMargin + e) then
		return true
	end
	return insideRect(HubLayout.GetStairsRect(), x, z, e)
end

function HubLayout.IsCellReserved(zoneId: string?, x: number, z: number): boolean
	if not H.Enabled then
		return false
	end
	local id = zoneId or HubLayout.ZoneId
	if id ~= HubLayout.ZoneId then
		return false
	end
	local pos = ZoneDefs.CellToWorld(x, z, id)
	local halfBubble = math.max(G.BubbleSize.X, G.BubbleSize.Z) / 2
	return HubLayout.IsWorldPointReserved(pos.X, pos.Z, halfBubble)
end

function HubLayout.GetFirstLiveBubbleEdgeZ(): number
	local rect = HubLayout.GetStairsRect()
	if not H.Enabled then
		return if HubLayout.FrontSign > 0 then rect.MaxZ else rect.MinZ
	end
	local id = HubLayout.ZoneId
	local sizeX, sizeZ = ZoneDefs.GetGridSize(id)
	local centerX = math.floor((sizeX + 1) / 2)
	local halfBubble = math.max(G.BubbleSize.X, G.BubbleSize.Z) / 2
	if HubLayout.FrontSign > 0 then
		for z = 1, sizeZ do
			local pos = ZoneDefs.CellToWorld(centerX, z, id)
			if pos.Z > rect.MaxZ and not HubLayout.IsCellReserved(id, centerX, z) then
				return pos.Z - halfBubble
			end
		end
		return rect.MaxZ
	end
	for z = sizeZ, 1, -1 do
		local pos = ZoneDefs.CellToWorld(centerX, z, id)
		if pos.Z < rect.MinZ and not HubLayout.IsCellReserved(id, centerX, z) then
			return pos.Z + halfBubble
		end
	end
	return rect.MinZ
end

function HubLayout.CountReservedCells(zoneId: string?): number
	local id = zoneId or HubLayout.ZoneId
	local sizeX, sizeZ = ZoneDefs.GetGridSize(id)
	local count = 0
	for x = 1, sizeX do
		for z = 1, sizeZ do
			if HubLayout.IsCellReserved(id, x, z) then
				count += 1
			end
		end
	end
	return count
end

export type CollisionProxySpec = {
	Name: string,
	Size: Vector3,
	Center: Vector3,
	TopY: number,
}

function HubLayout.GetFinalHubCollisionProxies(): { CollisionProxySpec }
	local cx, cz = HubLayout.Center.X, HubLayout.Center.Z
	local fs = HubLayout.FrontSign
	return {
		{
			Name = "MainHubFloor",
			Size = Vector3.new(58, 1, 42),
			Center = Vector3.new(cx, 11.5, cz),
			TopY = 12,
		},
		{
			Name = "SellFloor",
			Size = Vector3.new(22, 1, 19),
			Center = Vector3.new(cx + 27, 12.7, cz),
			TopY = 13.2,
		},
		{
			Name = "ShopFloor",
			Size = Vector3.new(22, 1, 19),
			Center = Vector3.new(cx - 27, 12.7, cz),
			TopY = 13.2,
		},
		{
			Name = "TransitFloor",
			Size = Vector3.new(12, 1, 12),
			Center = Vector3.new(cx, 11.5, cz + (-19) * fs),
			TopY = 12,
		},
	}
end

function HubLayout.GetCompositeCollisionProxies(): { CollisionProxySpec }
	return HubLayout.GetFinalHubCollisionProxies()
end

function HubLayout.GetRearHubCollisionProxies(): { CollisionProxySpec }
	local list = HubLayout.GetFinalHubCollisionProxies()
	for _, step in ipairs(HubLayout.GetStairSteps()) do
		table.insert(list, {
			Name = "StairStep" .. tostring(step.Index),
			Size = step.Size,
			Center = step.Center,
			TopY = step.TopY,
		})
	end
	local landSize, landCenter = HubLayout.GetLanding()
	table.insert(list, {
		Name = "StairLanding",
		Size = landSize,
		Center = landCenter,
		TopY = HubLayout.GetStairsBottomY(),
	})
	return list
end

function HubLayout.GetCirculationCorridor(): Rect
	local halfW = 3
	local spawnZ = HubLayout.Spawn.Center.Z
	local endZ = HubLayout.GetStairsEndZ() + HubLayout.FrontSign * HubLayout.GetLandingDepth()
	return {
		MinX = HubLayout.Center.X - halfW,
		MaxX = HubLayout.Center.X + halfW,
		MinZ = math.min(spawnZ - 4, endZ),
		MaxZ = math.max(spawnZ + 4, endZ),
	}
end

function HubLayout.GetModules(): { ModuleSpec }
	local shopOrigin = HubLayout.GetShopOrigin()
	local sellBase = HubLayout.GetSellBaseCFrame()
	local stairSize, stairCenter = HubLayout.GetLanding()
	local stairsRect = HubLayout.GetStairsRect()
	return {
		{
			Name = "Deck",
			Center = Vector3.new(HubLayout.Center.X, deckTop - H.DeckThickness / 2, HubLayout.Center.Z),
			Size = Vector3.new(H.DeckHalfX * 2, H.DeckThickness, H.DeckHalfZ * 2),
			YawDegrees = 0,
			Kind = "Structure",
			Circular = false,
		},
		{
			Name = "SpawnMedallion",
			Center = HubLayout.Spawn.Center,
			Size = Vector3.new(H.Spawn.PadDiameter, H.Spawn.PadHeight, H.Spawn.PadDiameter),
			YawDegrees = HubLayout.Spawn.YawDegrees,
			Kind = "Function",
			Circular = true,
		},
		{
			Name = "LoopPanel",
			Center = HubLayout.LoopPanel.Center,
			Size = HubLayout.WorldExtents(HubLayout.LoopPanel.Size, HubLayout.LoopPanel.YawDegrees),
			YawDegrees = HubLayout.LoopPanel.YawDegrees,
			Kind = "Sign",
			Circular = false,
		},
		{
			Name = "SellStand",
			Center = Vector3.new(
				HubLayout.SellPlatform.Center.X,
				sideTop + H.Sell.CounterSize.Y / 2,
				HubLayout.SellPlatform.Center.Z
			),
			Size = Vector3.new(H.SidePlatform.Size.X, H.Sell.CounterSize.Y + 4, H.SidePlatform.Size.Z),
			YawDegrees = H.Sell.YawDegrees,
			Kind = "Structure",
			Circular = false,
		},
		{
			Name = "ShopStand",
			Center = Vector3.new(shopOrigin.X, sideTop + H.Shop.WallHeight / 2, shopOrigin.Z),
			Size = HubLayout.WorldExtents(
				Vector3.new(H.Shop.Width, H.Shop.WallHeight, H.Shop.Depth),
				H.Shop.YawDegrees
			),
			YawDegrees = H.Shop.YawDegrees,
			Kind = "Structure",
			Circular = false,
		},
		{
			Name = "TopBoard",
			Center = HubLayout.TopBoard.Center,
			Size = HubLayout.WorldExtents(HubLayout.TopBoard.Size, HubLayout.TopBoard.YawDegrees),
			YawDegrees = HubLayout.TopBoard.YawDegrees,
			Kind = "Sign",
			Circular = false,
		},
		{
			Name = "WeeklyBoard",
			Center = HubLayout.WeeklyBoard.Center,
			Size = HubLayout.WorldExtents(HubLayout.WeeklyBoard.Size, HubLayout.WeeklyBoard.YawDegrees),
			YawDegrees = HubLayout.WeeklyBoard.YawDegrees,
			Kind = "Sign",
			Circular = false,
		},
		{
			Name = "RulesBoard",
			Center = HubLayout.RulesBoard.Center,
			Size = HubLayout.WorldExtents(HubLayout.RulesBoard.Size, HubLayout.RulesBoard.YawDegrees),
			YawDegrees = HubLayout.RulesBoard.YawDegrees,
			Kind = "Sign",
			Circular = false,
		},
		{
			Name = "TransitAlcove",
			Center = HubLayout.GetTransitAlcoveCenter(),
			Size = Vector3.new(H.Transit.AlcoveDiameter, H.Transit.AlcoveHeight, H.Transit.AlcoveDiameter),
			YawDegrees = faceYaw,
			Kind = "Function",
			Circular = true,
		},
		{
			Name = "Stairs",
			Center = Vector3.new(
				HubLayout.Center.X,
				(deckTop + HubLayout.GetStairsBottomY()) / 2,
				(stairsRect.MinZ + stairsRect.MaxZ) / 2
			),
			Size = Vector3.new(
				H.Stairs.Width,
				deckTop - HubLayout.GetStairsBottomY(),
				stairsRect.MaxZ - stairsRect.MinZ
			),
			YawDegrees = 0,
			Kind = "Structure",
			Circular = false,
		},
		{
			Name = "StairsLanding",
			Center = stairCenter,
			Size = stairSize,
			YawDegrees = 0,
			Kind = "Structure",
			Circular = false,
		},
		{
			Name = "SellZone",
			Center = HubLayout.GetSellZoneCFrame().Position,
			Size = HubLayout.WorldExtents(H.Sell.ZoneSize, H.Sell.YawDegrees),
			YawDegrees = H.Sell.YawDegrees,
			Kind = "Function",
			Circular = false,
		},
		{
			Name = "SellPad",
			Center = (sellBase * CFrame.new(H.Sell.PadLocalOffset)).Position,
			Size = HubLayout.WorldExtents(H.Sell.PadSize, H.Sell.YawDegrees),
			YawDegrees = H.Sell.YawDegrees,
			Kind = "Function",
			Circular = false,
		},
	}
end

function HubLayout.GetModule(name: string): ModuleSpec?
	for _, spec in ipairs(HubLayout.GetModules()) do
		if spec.Name == name then
			return spec
		end
	end
	return nil
end

function HubLayout.ShouldBuildCodeVisual(assetKey: string, importedPresent: boolean): boolean
	local spec = H.Assets[assetKey]
	if not spec then
		return true
	end
	if spec.UseImported ~= true then
		return true
	end
	return not importedPresent
end

function HubLayout.GetAssetModelName(assetKey: string): string?
	local spec = H.Assets[assetKey]
	return if spec then spec.ModelName else nil
end

function HubLayout.IsRearPlacement(): boolean
	return RearHubLogic.IsRearMode(H)
end

return HubLayout
