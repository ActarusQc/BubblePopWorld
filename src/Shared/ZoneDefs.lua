--!strict
-- Configuration centralisée des zones de jeu (planches thématiques).
-- Niveau requis, thème, origine et multiplicateur : une seule source de vérité.

local GameConfig = require(script.Parent.GameConfig)

export type ZoneDef = {
	Id: string,
	DisplayName: string,
	RequiredLevel: number,
	ThemeId: string,
	RewardMultiplier: number,
	-- Origine monde du centre de la grille de bulles
	Origin: Vector3,
	-- Direction locale « droite » de la planche classique (pour placement relatif)
	RightDirection: Vector3,
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

-- Côté droit de la planche classique : approche depuis le lobby (sud / -Z),
-- regard vers +Z → droite = +X mondial.
local CLASSIC_RIGHT = Vector3.new(1, 0, 0)
local HALF_X = (G.SizeX * G.Spacing) / 2
local HALF_Z = (G.SizeZ * G.Spacing) / 2
-- Espace visuel + passerelle entre bords des deux grilles (hors bulles).
local INTER_ZONE_GAP = 48

local classicOrigin = G.Origin
local summerOrigin = classicOrigin + CLASSIC_RIGHT * (HALF_X * 2 + INTER_ZONE_GAP)

local ZoneDefs = {}

ZoneDefs.ClassicZone = {
	Id = "ClassicZone",
	DisplayName = "CLASSIC ZONE",
	RequiredLevel = 1,
	ThemeId = "Classic",
	RewardMultiplier = 1,
	Origin = classicOrigin,
	RightDirection = CLASSIC_RIGHT,
	FloorColor = Color3.fromRGB(18, 32, 58),
	BorderColor = Color3.fromRGB(40, 140, 200),
	BubbleTintVariants = nil, -- utilise GameConfig.Bubble.Appearance
	Ambiance = nil,
} :: ZoneDef

ZoneDefs.SummerZone = {
	Id = "SummerZone",
	DisplayName = "SUMMER ZONE",
	RequiredLevel = 5,
	ThemeId = "Summer",
	RewardMultiplier = 1,
	Origin = summerOrigin,
	RightDirection = CLASSIC_RIGHT,
	FloorColor = Color3.fromRGB(210, 185, 130),
	BorderColor = Color3.fromRGB(40, 190, 200),
	BubbleTintVariants = {
		Color3.fromRGB(80, 220, 230), -- turquoise
		Color3.fromRGB(130, 210, 255), -- bleu clair
		Color3.fromRGB(255, 220, 90), -- jaune soleil
		Color3.fromRGB(255, 140, 130), -- rose corail
		Color3.fromRGB(160, 240, 120), -- vert lime
		Color3.fromRGB(235, 210, 160), -- beige sable
	},
	Ambiance = {
		ColorCorrection = {
			TintColor = Color3.fromRGB(255, 245, 220),
			Brightness = 0.04,
			Contrast = 0.02,
			Saturation = 0.08,
		},
		SoundIds = {
			-- Placeholders : remplacer en Studio si besoin (vagues / oiseaux).
			"rbxassetid://9113826540",
		},
	},
} :: ZoneDef

-- Ordre d'enregistrement (classic d'abord).
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

-- Règle d'accès unique : niveau joueur >= RequiredLevel (inclusif).
function ZoneDefs.CanLevelEnter(playerLevel: number, zoneId: string): boolean
	return playerLevel >= ZoneDefs.GetRequiredLevel(zoneId)
end

function ZoneDefs.GetRewardMultiplier(zoneId: string): number
	local def = ZoneDefs.ById[zoneId]
	return if def then def.RewardMultiplier else 1
end

function ZoneDefs.GetGridHalfExtent(): (number, number)
	return HALF_X, HALF_Z
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
	local o = def.Origin
	return {
		MinX = o.X - HALF_X,
		MaxX = o.X + HALF_X,
		MinZ = o.Z - HALF_Z,
		MaxZ = o.Z + HALF_Z,
		MinY = o.Y - 2,
		Origin = o,
	}
end

-- Seuils de niveau uniques (>1) pour les groupes de collision d'accès.
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

-- Nom du groupe de collision joueur selon le niveau autoritaire.
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

-- Zones qui ont une barrière de niveau (RequiredLevel > 1).
function ZoneDefs.GetGatedZones(): { ZoneDef }
	local out: { ZoneDef } = {}
	for _, def in ipairs(ZoneDefs.List) do
		if def.RequiredLevel > 1 then
			table.insert(out, def)
		end
	end
	return out
end

-- Validations au chargement du module.
do
	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	assert(classic.Origin == G.Origin, "[ZoneDefs] ClassicZone.Origin doit matcher Grid.Origin")
	assert(summer.RequiredLevel == 5, "[ZoneDefs] SummerZone.RequiredLevel doit être 5")
	assert(summer.RewardMultiplier == 1, "[ZoneDefs] RewardMultiplier doit rester 1")
	assert(classic.RewardMultiplier == 1, "[ZoneDefs] Classic RewardMultiplier doit rester 1")

	local dx = (summer.Origin - classic.Origin):Dot(CLASSIC_RIGHT)
	assert(dx > HALF_X * 2, "[ZoneDefs] SummerZone doit être à droite de ClassicZone")

	-- Pas de chevauchement des emprises grille.
	local cb = ZoneDefs.GetZoneBounds("ClassicZone")
	local sb = ZoneDefs.GetZoneBounds("SummerZone")
	if cb and sb then
		local overlapX = cb.MaxX > sb.MinX and cb.MinX < sb.MaxX
		local overlapZ = cb.MaxZ > sb.MinZ and cb.MinZ < sb.MaxZ
		assert(not (overlapX and overlapZ), "[ZoneDefs] emprises Classic/Summer sécantes")
	end
end

return ZoneDefs
