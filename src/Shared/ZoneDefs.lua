--!strict
-- Configuration centralisée des zones de jeu (planches thématiques).
-- Niveau requis, thème, origine, taille de grille et marges décoratives.

local GameConfig = require(script.Parent.GameConfig)

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
-- Summer : emprise extérieure inchangée ; BubbleBoard réduit + marges décor.
--------------------------------------------------------------------
local SideDecorMargin = 16
local EntranceDecorMargin = 14
local RearDecorMargin = 24
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
local summerZoneOrigin = classicOrigin + CLASSIC_RIGHT * (OUTER_HALF_X * 2 + INTER_ZONE_GAP)

local availableHalfX = (OUTER_HALF_X * 2 - EntranceDecorMargin - RearDecorMargin) / 2
local availableHalfZ = (OUTER_HALF_Z * 2 - SideDecorMargin * 2) / 2
local BubbleColumns = maxCellsForExtent(availableHalfX)
local BubbleRows = maxCellsForExtent(availableHalfZ)
local boardEx, boardEz = playExtentForSize(BubbleColumns, BubbleRows)
local BubbleBoardWidth = boardEx * 2
local BubbleBoardDepth = boardEz * 2

-- Board ancré côté entrée : marge entrée exacte → surplus au fond.
local summerZoneMinX = summerZoneOrigin.X - OUTER_HALF_X
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
	RequiredLevel = 5,
	ThemeId = "Summer",
	RewardMultiplier = 1,
	Origin = summerBoardOrigin,
	ZoneOrigin = summerZoneOrigin,
	RightDirection = CLASSIC_RIGHT,
	SizeX = BubbleColumns,
	SizeZ = BubbleRows,
	FloorColor = Color3.fromRGB(210, 185, 130),
	BorderColor = Color3.fromRGB(40, 190, 200),
	BubbleTintVariants = {
		Color3.fromRGB(80, 220, 230),
		Color3.fromRGB(130, 210, 255),
		Color3.fromRGB(255, 220, 90),
		Color3.fromRGB(255, 140, 130),
		Color3.fromRGB(160, 240, 120),
		Color3.fromRGB(235, 210, 160),
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
	OuterHalfX = OUTER_HALF_X,
	OuterHalfZ = OUTER_HALF_Z,
	OuterWidth = OUTER_HALF_X * 2,
	OuterDepth = OUTER_HALF_Z * 2,
}

ZoneDefs.List = {
	ZoneDefs.ClassicZone,
	ZoneDefs.SummerZone,
} :: { ZoneDef }

ZoneDefs.ById = {
	ClassicZone = ZoneDefs.ClassicZone,
	SummerZone = ZoneDefs.SummerZone,
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
	if type(zoneId) == "string" and zoneId ~= "SummerZone" and zoneId ~= "ClassicZone" then
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
	return playExtentForSize(G.SizeX, G.SizeZ)
end

function ZoneDefs.CellToWorld(x: number, z: number, zoneId: string?): Vector3
	local id = zoneId or "ClassicZone"
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
}

function ZoneDefs.GetSummerBridgeLayout(): SummerBridgeLayout
	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local layout = ZoneDefs.SummerLayout
	local outerEx, outerEz = ZoneDefs.GetOuterPlayExtent()
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
	assert(summer.RequiredLevel == 5, "[ZoneDefs] SummerZone.RequiredLevel doit être 5")
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
