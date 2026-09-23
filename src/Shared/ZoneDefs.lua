--!strict
-- Configuration centralisée des zones de jeu (planches thématiques).
-- Niveau requis, thème, origine, taille de grille et marges décoratives.

local GameConfig = require(script.Parent.GameConfig)
local SummerZoneConfig = require(script.Parent.SummerZoneConfig)
local Workspace = game:GetService("Workspace")

export type ZoneDef = {
	Id: string,
	DisplayName: string,
	RequiredLevel: number,
	ThemeId: string,
	RewardMultiplier: number,
	-- Centre du BubbleBoard (grille de bulles)
	Origin: Vector3,
	-- Centre de l’emprise extérieure de la zone (murs / plancher). Défaut = Origin.
	ZoneOrigin: Vector3,
	RightDirection: Vector3,
	SizeX: number,
	SizeZ: number,
	BubbleTintVariants: { Color3 }?,
	FloorColor: Color3?,
	BorderColor: Color3?,
	Ambiance: {
		ColorCorrection: {
			TintColor: Color3,
			Brightness: number,
			Contrast: number,
			Saturation: number,
		}?,
		SoundIds: { string }?,
	}?,
}

local G = GameConfig.Grid

local CLASSIC_RIGHT = Vector3.new(1, 0, 0)
local OUTER_HALF_X = (G.SizeX * G.Spacing) / 2
local OUTER_HALF_Z = (G.SizeZ * G.Spacing) / 2
local INTER_ZONE_GAP = 48

--------------------------------------------------------------------
-- Summer compacte : dimensions indépendantes de la planche Classic.
--------------------------------------------------------------------
local SUMMER_HALF_X = SummerZoneConfig.ZoneDepth / 2
local SUMMER_HALF_Z = SummerZoneConfig.ZoneWidth / 2
local SideDecorMargin = SummerZoneConfig.SideDecorMargin
local EntranceDecorMargin = SummerZoneConfig.EntranceDecorMargin
local RearDecorMargin = SummerZoneConfig.RearDecorMargin
local BubbleSpacing = G.Spacing

local function playExtentForSize(sizeX: number, sizeZ: number): (number, number)
	local safetyGap = 2
	local ex = ((sizeX / 2) - 0.5) * BubbleSpacing + G.BubbleSize.X / 2 + safetyGap
	local ez = ((sizeZ / 2) - 0.5) * BubbleSpacing + G.BubbleSize.Z / 2 + safetyGap
	return ex, ez
end

local function maxCellsForExtent(availableHalf: number): number
	for size = G.SizeX, 1, -1 do
		local ex = select(1, playExtentForSize(size, size))
		if ex <= availableHalf + 1e-6 then
			return size
		end
	end
	return 1
end

local classicOrigin = G.Origin
local summerZoneOrigin = Vector3.new(
	classicOrigin.X + OUTER_HALF_X + INTER_ZONE_GAP + SUMMER_HALF_X,
	classicOrigin.Y,
	classicOrigin.Z + SummerZoneConfig.EntryCenterOffset
)

local availableHalfX = (SUMMER_HALF_X * 2 - EntranceDecorMargin - RearDecorMargin) / 2
local availableHalfZ = (SUMMER_HALF_Z * 2 - SideDecorMargin * 2) / 2
local BubbleColumns = maxCellsForExtent(availableHalfX)
local BubbleRows = math.max(1, maxCellsForExtent(availableHalfZ) - SummerZoneConfig.BubbleRowReduction)
local boardEx, boardEz = playExtentForSize(BubbleColumns, BubbleRows)
local BubbleBoardWidth = boardEx * 2
local BubbleBoardDepth = boardEz * 2

-- Board ancré côté entrée : marge entrée exacte → surplus au fond.
local summerZoneMinX = summerZoneOrigin.X - SUMMER_HALF_X
local summerBoardOrigin = Vector3.new(
	summerZoneMinX + EntranceDecorMargin + boardEx,
	summerZoneOrigin.Y,
	summerZoneOrigin.Z
)

local ZoneDefs = {}

ZoneDefs.ClassicZone = {
	Id = "ClassicZone",
	DisplayName = "CLASSIC ZONE",
	RequiredLevel = 1,
	ThemeId = "Classic",
	RewardMultiplier = 1,
	Origin = classicOrigin,
	ZoneOrigin = classicOrigin,
	RightDirection = CLASSIC_RIGHT,
	SizeX = G.SizeX,
	SizeZ = G.SizeZ,
	FloorColor = Color3.fromRGB(18, 32, 58),
	BorderColor = Color3.fromRGB(40, 140, 200),
	BubbleTintVariants = nil,
	Ambiance = nil,
} :: ZoneDef

ZoneDefs.SummerZone = {
	Id = "SummerZone",
	DisplayName = "SUMMER ZONE",
	RequiredLevel = 3,
	ThemeId = "Summer",
	RewardMultiplier = 1,
	Origin = summerBoardOrigin,
	ZoneOrigin = summerZoneOrigin,
	RightDirection = CLASSIC_RIGHT,
	SizeX = BubbleColumns,
	SizeZ = BubbleRows,
	FloorColor = Color3.fromRGB(210, 185, 130),
	BorderColor = Color3.fromRGB(40, 190, 200),
	-- Normales : orange vif (voir GameConfig.ZoneBubblePalettes.SummerZone).
	-- Raretés : couleurs globales BubbleTypes (inchangées).
	BubbleTintVariants = {
		Color3.fromRGB(255, 145, 35),
	},
	Ambiance = {
		ColorCorrection = {
			TintColor = Color3.fromRGB(255, 245, 220),
			Brightness = 0.04,
			Contrast = 0.02,
			Saturation = 0.08,
		},
		SoundIds = {
			"rbxassetid://9113826540",
		},
	},
} :: ZoneDef

-- Parc d'attractions : une seule planche logique, répartie physiquement sur
-- trois étages. Les coordonnées personnalisées sont résolues dans CellToWorld.
local AMUSEMENT_REGION_SLOTS = {
	{ Name = "Ground", Rows = 7, Center = Vector3.new(-237, 7, -4), Size = Vector3.new(86, 0.4, 46), Required = true },
	{ Name = "Ground_02", Rows = 7 },
	{ Name = "Ground_03", Rows = 7 },
	{ Name = "Mid", Rows = 5, Center = Vector3.new(-270, 18, -51), Size = Vector3.new(50, 0.4, 32), Required = true },
	{ Name = "Mid_02", Rows = 5 },
	{ Name = "Mid_03", Rows = 5 },
	{ Name = "High", Rows = 5, Center = Vector3.new(-306, 30, 47), Size = Vector3.new(46, 0.4, 30), Required = true },
	{ Name = "High_02", Rows = 5 },
	{ Name = "High_03", Rows = 5 },
}

local AMUSEMENT_TOTAL_ROWS = 0
for _, slot in ipairs(AMUSEMENT_REGION_SLOTS) do
	slot.FirstRow = AMUSEMENT_TOTAL_ROWS + 1
	AMUSEMENT_TOTAL_ROWS += slot.Rows
	local family, index = string.match(slot.Name, "^(%a+)_(%d+)$")
	slot.Family = family or slot.Name
	slot.Index = if index then tonumber(index) else 1
end

local function amusementSlotForRow(z: number): any?
	for _, slot in ipairs(AMUSEMENT_REGION_SLOTS) do
		if z >= slot.FirstRow and z < slot.FirstRow + slot.Rows then
			return slot
		end
	end
	return nil
end

ZoneDefs.AmusementPark = {
	Id = "AmusementPark",
	DisplayName = "AMUSEMENT PARK",
	RequiredLevel = 1,
	ThemeId = "AmusementPark",
	RewardMultiplier = 2,
	Origin = Vector3.new(-258, 6, 0),
	ZoneOrigin = Vector3.new(-258, 6, 0),
	RightDirection = CLASSIC_RIGHT,
	SizeX = 16,
	-- Trois surfaces éditables maximum par étage. Les surfaces _02/_03 ne
	-- produisent aucune bulle tant que leur Part n'existe pas dans BubbleRegions.
	SizeZ = AMUSEMENT_TOTAL_ROWS,
	FloorColor = Color3.fromRGB(25, 58, 108),
	BorderColor = Color3.fromRGB(255, 196, 48),
	BubbleTintVariants = {
		Color3.fromRGB(255, 88, 104),
		Color3.fromRGB(255, 198, 50),
		Color3.fromRGB(58, 213, 255),
		Color3.fromRGB(170, 92, 255),
	},
	MultiLevel = true,
	Ambiance = nil,
} :: any

function ZoneDefs.GetAmusementParkRegionName(z: number): string?
	local slot = amusementSlotForRow(z)
	return if slot then slot.Name else nil
end

-- Capacité d'une surface BubbleRegions : grille à Spacing naturel (jamais compressée).
-- Le plan jouable suit les deux axes locaux les plus horizontaux (ignore l'épaisseur).
function ZoneDefs.GetAmusementParkRegionPlayAxes(regionCF: CFrame, regionSize: Vector3): (number, number, Vector3, Vector3)
	local candidates = {
		{ Align = math.abs(regionCF.RightVector.Y), Extent = regionSize.X, Axis = Vector3.new(1, 0, 0) },
		{ Align = math.abs(regionCF.UpVector.Y), Extent = regionSize.Y, Axis = Vector3.new(0, 1, 0) },
		{ Align = math.abs(regionCF.LookVector.Y), Extent = regionSize.Z, Axis = Vector3.new(0, 0, 1) },
	}
	table.sort(candidates, function(a, b)
		if a.Align == b.Align then
			return a.Extent > b.Extent
		end
		return a.Align > b.Align
	end)
	-- candidates[1] = axe le plus vertical = épaisseur de la surface
	local a = candidates[2]
	local b = candidates[3]
	local aWorld = regionCF:VectorToWorldSpace(a.Axis)
	local bWorld = regionCF:VectorToWorldSpace(b.Axis)
	-- Colonnes ≈ axe le plus « gauche-droite » en monde
	if math.abs(aWorld.X) >= math.abs(bWorld.X) then
		return a.Extent, b.Extent, a.Axis, b.Axis
	end
	return b.Extent, a.Extent, b.Axis, a.Axis
end

function ZoneDefs.GetAmusementParkRegionCapacity(
	regionCF: CFrame,
	regionSize: Vector3,
	maxCols: number,
	maxRows: number
): (number, number)
	local spacing = G.Spacing
	local pad = math.max(G.BubbleSize.X, G.BubbleSize.Z)
	local planeCol, planeRow = ZoneDefs.GetAmusementParkRegionPlayAxes(regionCF, regionSize)
	local usableCol = math.max(0, planeCol - pad)
	local usableRow = math.max(0, planeRow - pad)
	local cols = math.clamp(math.floor(usableCol / spacing) + 1, 1, math.max(1, maxCols))
	local rows = math.clamp(math.floor(usableRow / spacing) + 1, 1, math.max(1, maxRows))
	while cols > 1 and (cols - 1) * spacing > usableCol + 1e-6 do
		cols -= 1
	end
	while rows > 1 and (rows - 1) * spacing > usableRow + 1e-6 do
		rows -= 1
	end
	return cols, rows
end

-- Dupliquer une surface dans Studio garde le nom d'origine ("Ground", "Ground",
-- "Ground"). On accepte donc les homonymes autant que les suffixes numériques,
-- et on les ordonne de façon stable pour que chaque étage garde sa place.
function ZoneDefs.MatchesBubbleRegionFamily(name: string, family: string): boolean
	if name == family then
		return true
	end
	if string.sub(name, 1, #family) ~= family then
		return false
	end
	return string.match(string.sub(name, #family + 1), "^[%s_%-]*%(?%d+%)?$") ~= nil
end

local regionCache: { [string]: { BasePart } } = {}
local regionCacheClock = -math.huge

local function amusementRegionParts(family: string): { BasePart }
	local now = os.clock()
	if now - regionCacheClock > 0.5 then
		regionCache = {}
		regionCacheClock = now
	end
	local cached = regionCache[family]
	if cached then
		return cached
	end
	local park = Workspace:FindFirstChild("ParcAttractions")
	local regions = park and park:FindFirstChild("BubbleRegions")
	local found: { BasePart } = {}
	if regions then
		for _, child in ipairs(regions:GetChildren()) do
			if child:IsA("BasePart") and ZoneDefs.MatchesBubbleRegionFamily(child.Name, family) then
				table.insert(found, child)
			end
		end
		table.sort(found, function(a: BasePart, b: BasePart): boolean
			if a.Name ~= b.Name then
				return a.Name < b.Name
			end
			local pa, pb = a.Position, b.Position
			if math.abs(pa.X - pb.X) > 1e-3 then
				return pa.X < pb.X
			end
			if math.abs(pa.Z - pb.Z) > 1e-3 then
				return pa.Z < pb.Z
			end
			return pa.Y < pb.Y
		end)
	end
	regionCache[family] = found
	return found
end

local function amusementRegionPart(slot: any): BasePart?
	return amusementRegionParts(slot.Family)[slot.Index]
end

local function amusementRegionPlacement(slot: any): (CFrame, number, number, number, Vector3, Vector3)
	local fallbackCenter = slot.Center or Vector3.new(-237, 7, -4)
	local fallbackSize = slot.Size or Vector3.new(30, 0.4, 22)
	local region = amusementRegionPart(slot)
	local regionCF = if region then region.CFrame else CFrame.new(fallbackCenter)
	local regionSize = if region then region.Size else fallbackSize
	local maxCols = ZoneDefs.AmusementPark.SizeX
	local maxRows = slot.Rows
	local cols, rows = ZoneDefs.GetAmusementParkRegionCapacity(regionCF, regionSize, maxCols, maxRows)
	local _, _, colAxis, rowAxis = ZoneDefs.GetAmusementParkRegionPlayAxes(regionCF, regionSize)
	return regionCF, cols, rows, G.Spacing, colAxis, rowAxis
end

function ZoneDefs.GetAmusementParkFitForRow(z: number): (number, number)
	local slot = amusementSlotForRow(z)
	if not slot then
		return 0, 0
	end
	local _, cols, rows = amusementRegionPlacement(slot)
	return cols, rows
end

function ZoneDefs.IsBubbleCellEnabled(zoneId: string, x: number, z: number): boolean
	if zoneId ~= "AmusementPark" then return true end
	local slot = amusementSlotForRow(z)
	if not slot then return false end
	if slot.Required ~= true then
		local region = amusementRegionPart(slot)
		if not region then return false end
	end
	local _, colsFit, rowsFit = amusementRegionPlacement(slot)
	local localCol = x
	local localRow = z - slot.FirstRow + 1
	return localCol >= 1 and localCol <= colsFit and localRow >= 1 and localRow <= rowsFit
end

-- Constantes Summer (source unique pour preview / builder / rapport).
ZoneDefs.SummerLayout = {
	SideDecorMargin = SideDecorMargin,
	EntranceDecorMargin = EntranceDecorMargin,
	RearDecorMargin = RearDecorMargin,
	BubbleSpacing = BubbleSpacing,
	BubbleBoardWidth = BubbleBoardWidth,
	BubbleBoardDepth = BubbleBoardDepth,
	BubbleRows = BubbleRows,
	BubbleColumns = BubbleColumns,
	OuterHalfX = SUMMER_HALF_X,
	OuterHalfZ = SUMMER_HALF_Z,
	ZoneWidth = SummerZoneConfig.ZoneWidth,
	ZoneDepth = SummerZoneConfig.ZoneDepth,
	EntryCenterOffset = SummerZoneConfig.EntryCenterOffset,
	LightPerimeterSpacing = SummerZoneConfig.LightPerimeterSpacing,
}

ZoneDefs.List = {
	ZoneDefs.ClassicZone,
	ZoneDefs.SummerZone,
	ZoneDefs.AmusementPark,
} :: { ZoneDef }

ZoneDefs.ById = {
	ClassicZone = ZoneDefs.ClassicZone,
	SummerZone = ZoneDefs.SummerZone,
	AmusementPark = ZoneDefs.AmusementPark,
} :: { [string]: ZoneDef }

ZoneDefs.INTER_ZONE_GAP = INTER_ZONE_GAP
ZoneDefs.CLASSIC_RIGHT = CLASSIC_RIGHT

function ZoneDefs.Get(zoneId: string): ZoneDef?
	return ZoneDefs.ById[zoneId]
end

function ZoneDefs.GetRequiredLevel(zoneId: string): number
	local def = ZoneDefs.ById[zoneId]
	return if def then def.RequiredLevel else 1
end

function ZoneDefs.CanLevelEnter(playerLevel: number, zoneId: string): boolean
	return playerLevel >= ZoneDefs.GetRequiredLevel(zoneId)
end

function ZoneDefs.GetRewardMultiplier(zoneId: string): number
	local def = ZoneDefs.ById[zoneId]
	return if def then def.RewardMultiplier else 1
end

function ZoneDefs.GetGridSize(zoneId: string): (number, number)
	local def = ZoneDefs.ById[zoneId]
	if def then
		return def.SizeX, def.SizeZ
	end
	return G.SizeX, G.SizeZ
end

function ZoneDefs.GetZoneOrigin(zoneId: string): Vector3
	local def = ZoneDefs.ById[zoneId]
	if not def then
		return G.Origin
	end
	return def.ZoneOrigin or def.Origin
end

-- Demi-emprise des centres de grille (board).
function ZoneDefs.GetGridHalfExtent(zoneId: string?): (number, number)
	if type(zoneId) == "string" then
		local sx, sz = ZoneDefs.GetGridSize(zoneId)
		return (sx * G.Spacing) / 2, (sz * G.Spacing) / 2
	end
	return OUTER_HALF_X, OUTER_HALF_Z
end

-- Demi-emprise extérieure de la zone (murs / plancher).
function ZoneDefs.GetOuterHalfExtent(zoneId: string?): (number, number)
	if zoneId == "SummerZone" then
		return SUMMER_HALF_X, SUMMER_HALF_Z
	end
	if type(zoneId) == "string" and zoneId ~= "ClassicZone" then
		return ZoneDefs.GetGridHalfExtent(zoneId)
	end
	return OUTER_HALF_X, OUTER_HALF_Z
end

function ZoneDefs.GetBubblePlayExtent(zoneId: string?): (number, number)
	if type(zoneId) == "string" then
		local sx, sz = ZoneDefs.GetGridSize(zoneId)
		return playExtentForSize(sx, sz)
	end
	return playExtentForSize(G.SizeX, G.SizeZ)
end

-- Emprise visuelle des murs (hors board réduit) : footprint extérieur.
function ZoneDefs.GetOuterPlayExtent(zoneId: string?): (number, number)
	if zoneId == "SummerZone" then
		return SUMMER_HALF_X, SUMMER_HALF_Z
	end
	return playExtentForSize(G.SizeX, G.SizeZ)
end

function ZoneDefs.CellToWorld(x: number, z: number, zoneId: string?): Vector3
	local id = zoneId or "ClassicZone"
	if id == "AmusementPark" then
		local slot = amusementSlotForRow(z) or AMUSEMENT_REGION_SLOTS[1]
		local regionCF, colsFit, rowsFit, spacing, colAxis, rowAxis = amusementRegionPlacement(slot)
		local localCol = math.clamp(x, 1, colsFit)
		local localRow = math.clamp(z - slot.FirstRow + 1, 1, rowsFit)
		local posCol = (localCol - (colsFit + 1) / 2) * spacing
		local posRow = (localRow - (rowsFit + 1) / 2) * spacing
		return regionCF:PointToWorldSpace(colAxis * posCol + rowAxis * posRow)
	end
	local def = ZoneDefs.ById[id]
	local origin = if def then def.Origin else G.Origin
	local sizeX, sizeZ = ZoneDefs.GetGridSize(id)
	return origin + Vector3.new((x - sizeX / 2) * G.Spacing, 0, (z - sizeZ / 2) * G.Spacing)
end

function ZoneDefs.InBounds(x: number, z: number, zoneId: string?): boolean
	local sizeX, sizeZ = ZoneDefs.GetGridSize(zoneId or "ClassicZone")
	return x >= 1 and x <= sizeX and z >= 1 and z <= sizeZ
end

export type SummerBridgeLayout = {
	ClassicEdgeX: number,
	SummerEdgeX: number,
	MidX: number,
	Span: number,
	PathW: number,
	BridgeGap: number,
	ArchX: number,
	ArchZ: number,
	ArchGap: number,
	GateX: number,
	Y: number,
	Origin: Vector3,
	ZoneOrigin: Vector3,
	BoardOrigin: Vector3,
	FloorColor: Color3,
	BorderColor: Color3,
	BorderThickness: number,
	BorderHeight: number,
	Ex: number,
	Ez: number,
	BoardEx: number,
	BoardEz: number,
	SideDecorMargin: number,
	EntranceDecorMargin: number,
	RearDecorMargin: number,
	BubbleSpacing: number,
	BubbleRows: number,
	BubbleColumns: number,
	BubbleBoardWidth: number,
	BubbleBoardDepth: number,
	ZoneWidth: number,
	ZoneDepth: number,
	EntryCenterOffset: number,
	LightPerimeterSpacing: number,
}

function ZoneDefs.GetSummerBridgeLayout(): SummerBridgeLayout
	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local layout = ZoneDefs.SummerLayout
	local outerEx, outerEz = ZoneDefs.GetOuterPlayExtent(summer.Id)
	local boardEx, boardEz = ZoneDefs.GetBubblePlayExtent(summer.Id)
	local pathW = GameConfig.GameRoom.PathSize.X
	local zoneO = summer.ZoneOrigin
	local classicEdgeX = classic.Origin.X + select(1, ZoneDefs.GetBubblePlayExtent(classic.Id))
	local summerEdgeX = zoneO.X - outerEx
	local midX = (classicEdgeX + summerEdgeX) / 2
	local span = math.max(4, summerEdgeX - classicEdgeX)
	local y = classic.Origin.Y
	return {
		ClassicEdgeX = classicEdgeX,
		SummerEdgeX = summerEdgeX,
		MidX = midX,
		Span = span,
		PathW = pathW,
		BridgeGap = pathW + 6,
		ArchX = summerEdgeX - 2,
		ArchZ = zoneO.Z,
		ArchGap = pathW + 2,
		GateX = summerEdgeX + 1.5,
		Y = y,
		Origin = zoneO,
		ZoneOrigin = zoneO,
		BoardOrigin = summer.Origin,
		FloorColor = summer.FloorColor or Color3.fromRGB(210, 185, 130),
		BorderColor = summer.BorderColor or Color3.fromRGB(40, 190, 200),
		BorderThickness = GameConfig.World.BorderThickness,
		BorderHeight = 5,
		Ex = outerEx,
		Ez = outerEz,
		BoardEx = boardEx,
		BoardEz = boardEz,
		SideDecorMargin = layout.SideDecorMargin,
		EntranceDecorMargin = layout.EntranceDecorMargin,
		RearDecorMargin = layout.RearDecorMargin,
		BubbleSpacing = layout.BubbleSpacing,
		BubbleRows = layout.BubbleRows,
		BubbleColumns = layout.BubbleColumns,
		BubbleBoardWidth = layout.BubbleBoardWidth,
		BubbleBoardDepth = layout.BubbleBoardDepth,
		ZoneWidth = layout.ZoneWidth,
		ZoneDepth = layout.ZoneDepth,
		EntryCenterOffset = layout.EntryCenterOffset,
		LightPerimeterSpacing = layout.LightPerimeterSpacing,
	}
end

function ZoneDefs.GetZoneBounds(zoneId: string): {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	MinY: number,
	Origin: Vector3,
}?
	local def = ZoneDefs.ById[zoneId]
	if not def then
		return nil
	end
	local o = def.ZoneOrigin or def.Origin
	local halfX, halfZ = ZoneDefs.GetOuterHalfExtent(zoneId)
	return {
		MinX = o.X - halfX,
		MaxX = o.X + halfX,
		MinZ = o.Z - halfZ,
		MaxZ = o.Z + halfZ,
		MinY = o.Y - 2,
		Origin = o,
	}
end

function ZoneDefs.GetBoardBounds(zoneId: string): {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	Origin: Vector3,
}?
	local def = ZoneDefs.ById[zoneId]
	if not def then
		return nil
	end
	local ex, ez = ZoneDefs.GetBubblePlayExtent(zoneId)
	local o = def.Origin
	return {
		MinX = o.X - ex,
		MaxX = o.X + ex,
		MinZ = o.Z - ez,
		MaxZ = o.Z + ez,
		Origin = o,
	}
end

function ZoneDefs.ResolveZoneIdAt(pos: Vector3): string
	for _, def in ipairs(ZoneDefs.List) do
		local b = ZoneDefs.GetZoneBounds(def.Id)
		if b and pos.X >= b.MinX and pos.X <= b.MaxX and pos.Z >= b.MinZ and pos.Z <= b.MaxZ then
			return def.Id
		end
	end
	local bestId = "ClassicZone"
	local bestDist = math.huge
	for _, def in ipairs(ZoneDefs.List) do
		local zo = def.ZoneOrigin or def.Origin
		local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(zo.X, 0, zo.Z)).Magnitude
		if d < bestDist then
			bestDist = d
			bestId = def.Id
		end
	end
	return bestId
end

function ZoneDefs.GetAccessThresholds(): { number }
	local seen: { [number]: boolean } = {}
	local list: { number } = { 1 }
	seen[1] = true
	for _, def in ipairs(ZoneDefs.List) do
		local lvl = def.RequiredLevel
		if lvl > 1 and not seen[lvl] then
			seen[lvl] = true
			table.insert(list, lvl)
		end
	end
	table.sort(list)
	return list
end

function ZoneDefs.GetAccessGroupName(level: number): string
	local thresholds = ZoneDefs.GetAccessThresholds()
	local best = 1
	for _, t in ipairs(thresholds) do
		if level >= t then
			best = t
		end
	end
	return "ZoneAccess_" .. tostring(best)
end

function ZoneDefs.GateGroupName(zoneId: string): string
	return "ZoneGate_" .. zoneId
end

function ZoneDefs.GetGatedZones(): { ZoneDef }
	local out: { ZoneDef } = {}
	for _, def in ipairs(ZoneDefs.List) do
		if def.RequiredLevel > 1 then
			table.insert(out, def)
		end
	end
	return out
end

do
	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local L = ZoneDefs.SummerLayout
	assert(classic.Origin == G.Origin, "[ZoneDefs] ClassicZone.Origin doit matcher Grid.Origin")
	assert(summer.RequiredLevel == 3, "[ZoneDefs] SummerZone.RequiredLevel doit être 3")
	assert(summer.RewardMultiplier == 1, "[ZoneDefs] RewardMultiplier doit rester 1")
	assert(classic.RewardMultiplier == 1, "[ZoneDefs] Classic RewardMultiplier doit rester 1")
	assert(summer.SizeX == L.BubbleColumns and summer.SizeZ == L.BubbleRows, "[ZoneDefs] Size vs BubbleRows/Columns")
	assert(L.BubbleColumns < G.SizeX or L.BubbleRows < G.SizeZ, "[ZoneDefs] Summer board doit être plus petit")

	local dx = (summer.ZoneOrigin - classic.Origin):Dot(CLASSIC_RIGHT)
	assert(dx > OUTER_HALF_X * 2, "[ZoneDefs] SummerZone doit être à droite de ClassicZone")

	local cb = ZoneDefs.GetZoneBounds("ClassicZone")
	local sb = ZoneDefs.GetZoneBounds("SummerZone")
	if cb and sb then
		local overlapX = cb.MaxX > sb.MinX and cb.MinX < sb.MaxX
		local overlapZ = cb.MaxZ > sb.MinZ and cb.MinZ < sb.MaxZ
		assert(not (overlapX and overlapZ), "[ZoneDefs] emprises Classic/Summer sécantes")
	end

	local bb = ZoneDefs.GetBoardBounds("SummerZone")
	if sb and bb then
		assert(bb.MinX - sb.MinX >= L.EntranceDecorMargin - 0.05, "[ZoneDefs] marge entrée")
		assert(sb.MaxX - bb.MaxX >= L.RearDecorMargin - 0.05, "[ZoneDefs] marge fond")
		assert(bb.MinZ - sb.MinZ >= L.SideDecorMargin - 0.05, "[ZoneDefs] marge côté sud")
		assert(sb.MaxZ - bb.MaxZ >= L.SideDecorMargin - 0.05, "[ZoneDefs] marge côté nord")
		assert(sb.MaxX - bb.MaxX > bb.MinX - sb.MinX, "[ZoneDefs] fond plus large que entrée")
	end
end

return ZoneDefs
