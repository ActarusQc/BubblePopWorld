--!strict
-- Définition des objets. Les formes sont calculées côté serveur à partir
-- de Shape + Radius pour éviter d'envoyer de grosses tables au client.

local ToolDefs = {}

--[[
	SupportsMobileAction : affiche le bouton tactile quand l'outil est équipé.
	MobileActionLabel    : libellé du bouton (POP / USE / …).
	RequiresTarget       : réticule + raycast centre écran (outils non SelfCentered).
	IconGlyph / IconImage: icône bouton (Image prioritaire si définie).
]]

ToolDefs.List = {
	Epingle = {
		Name = "Pin", Rarity = "Common", Weight = 40,
		Cooldown = 0.45, Range = 20, Shape = "Cross", Radius = 1,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(255, 55, 75),
		SupportsMobileAction = true, MobileActionLabel = "POP",
		RequiresTarget = false, IconGlyph = "📍",
		Desc = "1 use: pops front, back, left and right. RT to use.",
	},
	Marteau = {
		Name = "Hammer", Rarity = "Common", Weight = 28,
		Cooldown = 1.0, Range = 20, Shape = "Square", Radius = 1,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(150, 110, 70),
		SupportsMobileAction = true, MobileActionLabel = "USE",
		RequiresTarget = false, IconGlyph = "🔨",
		Desc = "1 use: crushes a 3x3 square around you.",
	},
	Bombe = {
		Name = "Bomb", Rarity = "Rare", Weight = 14,
		Cooldown = 1.0, Range = 20, Shape = "Around", Radius = 1,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(40, 40, 45),
		SupportsMobileAction = true, MobileActionLabel = "USE",
		RequiresTarget = false, IconGlyph = "💣",
		Desc = "1 use: blows up the 8 bubbles around you.",
	},
	MegaRouleau = {
		Name = "Mega roller", Rarity = "Epic", Weight = 6,
		Cooldown = 1.0, Range = 20, Shape = "FullRow", Radius = 1,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(255, 140, 60),
		SupportsMobileAction = true, MobileActionLabel = "USE",
		RequiresTarget = false, IconGlyph = "🛞",
		Desc = "1 use: flattens a whole row of the grid.",
	},
	Laser = {
		Name = "Laser beam", Rarity = "Epic", Weight = 5,
		Cooldown = 1.0, Range = 20, Shape = "Line", Radius = 16,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(255, 60, 90),
		SupportsMobileAction = true, MobileActionLabel = "USE",
		RequiresTarget = false, IconGlyph = "🔴",
		Desc = "1 use: cuts straight through the bubbles ahead of you.",
	},
	Singularite = {
		Name = "Singularity", Rarity = "Mythic", Weight = 1,
		Cooldown = 1.0, Range = 20, Shape = "Disc", Radius = 9, Multiplier = 3,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(180, 60, 255), Announce = true,
		SupportsMobileAction = true, MobileActionLabel = "USE",
		RequiresTarget = false, IconGlyph = "✦",
		Desc = "1 mythic use: massive implosion, x3 rewards.",
	},
	-- Permanent : boost de saut, ne se consomme pas
	Ailes = {
		Name = "Wings", Rarity = "Rare", Weight = 10,
		Cooldown = 0, Range = 0, Shape = "Wings", Radius = 0,
		SelfCentered = true, Consumable = false, Permanent = true,
		WingCells = 5, Color = Color3.fromRGB(120, 210, 255),
		SupportsMobileAction = true, MobileActionLabel = "USE",
		RequiresTarget = false, IconGlyph = "🪽",
		Desc = "Equip/unequip (RT): glide over 5 bubbles. Permanent.",
	},
}

ToolDefs.RarityColor = {
	Common = Color3.fromRGB(190, 190, 190),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Mythic = Color3.fromRGB(255, 90, 220),
}

-- Pools d'apparition par zone (poids relatifs au sein du pool).
-- GameRoom = planche ClassicZone : objets à faible impact uniquement.
-- SummerZone : objets de base + objets puissants (plus rares).
ToolDefs.ZoneItemPools = {
	GameRoom = {
		{ ItemId = "Epingle", Weight = 60 },
		{ ItemId = "Marteau", Weight = 40 },
	},
	SummerZone = {
		{ ItemId = "Epingle", Weight = 42 },
		{ ItemId = "Marteau", Weight = 28 },
		{ ItemId = "Bombe", Weight = 14 },
		{ ItemId = "Ailes", Weight = 8 },
		{ ItemId = "MegaRouleau", Weight = 5 },
		{ ItemId = "Laser", Weight = 4 },
		{ ItemId = "Singularite", Weight = 1 },
	},
}

local totalWeight = 0
for _, def in pairs(ToolDefs.List) do totalWeight += def.Weight end

local poolTotals: { [string]: number } = {}
for poolKey, entries in pairs(ToolDefs.ZoneItemPools) do
	local sum = 0
	for _, entry in ipairs(entries) do
		sum += entry.Weight
	end
	poolTotals[poolKey] = sum
end

-- ClassicZone (planche GameRoom) → pool GameRoom.
function ToolDefs.PoolKeyForZone(zoneId: string): string
	if zoneId == "ClassicZone" or zoneId == "GameRoom" then
		return "GameRoom"
	end
	return zoneId
end

function ToolDefs.GetZonePool(zoneId: string): { { ItemId: string, Weight: number } }?
	return ToolDefs.ZoneItemPools[ToolDefs.PoolKeyForZone(zoneId)]
end

function ToolDefs.IsInZonePool(zoneId: string, itemId: string): boolean
	local pool = ToolDefs.GetZonePool(zoneId)
	if not pool then
		return false
	end
	for _, entry in ipairs(pool) do
		if entry.ItemId == itemId then
			return true
		end
	end
	return false
end

function ToolDefs.RollForZone(zoneId: string, rng: Random?): (string, any)
	local poolKey = ToolDefs.PoolKeyForZone(zoneId)
	local pool = ToolDefs.ZoneItemPools[poolKey]
	local poolTotal = poolTotals[poolKey]
	if not pool or not poolTotal or poolTotal <= 0 then
		return "Epingle", ToolDefs.List.Epingle
	end
	local roll = if rng then rng:NextNumber(0, poolTotal) else math.random() * poolTotal
	local acc = 0
	for _, entry in ipairs(pool) do
		acc += entry.Weight
		if roll <= acc then
			local def = ToolDefs.List[entry.ItemId]
			if def then
				return entry.ItemId, def
			end
		end
	end
	local fallbackId = pool[1].ItemId
	return fallbackId, ToolDefs.List[fallbackId] or ToolDefs.List.Epingle
end

-- Legacy : tirage global (boutique / tests). Les drops monde utilisent RollForZone.
function ToolDefs.Roll(rng: Random?): (string, any)
	local roll = if rng then rng:NextNumber(0, totalWeight) else math.random() * totalWeight
	local acc = 0
	for id, def in pairs(ToolDefs.List) do
		acc += def.Weight
		if roll <= acc then return id, def end
	end
	return "Epingle", ToolDefs.List.Epingle
end

function ToolDefs.Get(id: string): any?
	return ToolDefs.List[id]
end

return ToolDefs
