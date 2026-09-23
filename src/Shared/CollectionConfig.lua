--!strict
-- Catalogue autoritaire des bulles de collection.
-- Remplacer ImageId par rbxassetid://... après téléversement dans Roblox.

local CollectionConfig = {}

CollectionConfig.Version = 1
CollectionConfig.RarityOrder = { "Common", "Rare", "Epic" }

CollectionConfig.Rarities = {
	Common = { Label = "COMMUN", Color = Color3.fromRGB(40, 180, 255), ZoneId = "ClassicZone", SpawnChance = 1 / 800, Enabled = true },
	Rare = { Label = "RARE", Color = Color3.fromRGB(70, 220, 255), ZoneId = "SummerZone", SpawnChance = 1 / 450, Enabled = true },
	Epic = { Label = "EPIC", Color = Color3.fromRGB(190, 65, 255), ZoneId = "FutureZone", SpawnChance = 1 / 1400, Enabled = false },
}

CollectionConfig.PersonalDiscovery = {
	FirstGuaranteePops = 30,
	TargetMinDistance = 20,
	TargetMaxDistance = 45,
	TargetFallbackDistance = 75,
	TargetLifetimeSeconds = 90,
	PityStartPops = 250,
	GuaranteedPops = 650,
	GuaranteedNewDiscoveries = 3,
	UndiscoveredPreference = 0.75,
}

function CollectionConfig.PersonalChance(popsSinceCollection: number): number
	local pops = math.max(0, math.floor(popsSinceCollection))
	if pops >= 650 then return 1 end
	if pops >= 550 then return 1 / 100 end
	if pops >= 400 then return 1 / 250 end
	if pops >= 250 then return 1 / 500 end
	return 0
end

function CollectionConfig.RarityForZone(zoneId: string): string?
	for _, rarityId in ipairs(CollectionConfig.RarityOrder) do
		local rarity = CollectionConfig.Rarities[rarityId]
		if rarity.Enabled and rarity.ZoneId == zoneId then return rarityId end
	end
	return nil
end

local function item(id: string, name: string, rarity: string, imageId: string?)
	return { Id = id, Name = name, Rarity = rarity, ImageId = imageId or "" }
end

CollectionConfig.Items = {
	item("common_apple", "Pomme", "Common", "rbxassetid://74090160768198"),
	item("common_duck", "Canard", "Common", "rbxassetid://108348622429513"),
	item("common_soccer", "Ballon", "Common", "rbxassetid://126821401053147"),
	item("common_blue_balloon", "Ballon bleu", "Common", "rbxassetid://112229928663566"),
	item("common_donut", "Beigne", "Common", "rbxassetid://135435081452431"),
	item("common_watermelon", "Pastèque", "Common", "rbxassetid://80121398694671"),
	item("common_beach_ball", "Ballon de plage", "Common", "rbxassetid://131605050782904"),
	item("common_cookie", "Biscuit", "Common", "rbxassetid://73410959646068"),
	item("common_candy", "Bonbon", "Common", "rbxassetid://107361656917875"),
	item("common_star", "Étoile", "Common", "rbxassetid://102404264897847"),
	item("common_cloud", "Nuage", "Common", "rbxassetid://120217960466558"),
	item("common_gum", "Gomme balloune", "Common", "rbxassetid://71512941034547"),
	item("rare_diamond", "Diamant", "Rare", "rbxassetid://133321122405154"),
	item("rare_galaxy", "Galaxie", "Rare", "rbxassetid://74173989620550"),
	item("rare_narwhal", "Narval", "Rare", "rbxassetid://130761419211382"),
	item("rare_rainbow", "Arc-en-ciel", "Rare", "rbxassetid://71583914233740"),
	item("rare_green_potion", "Potion verte", "Rare", "rbxassetid://96990645815705"),
	item("rare_dragon", "Dragon", "Rare", "rbxassetid://78679862362241"),
	item("epic_cosmic_dragon", "Draco cosmique", "Epic", "rbxassetid://140510151788724"),
	item("epic_ethereal_rainbow", "Arc-en-ciel éthéré", "Epic", "rbxassetid://103166825452487"),
	item("epic_celestial_crystal", "Cristal céleste", "Epic", "rbxassetid://74744978363045"),
	item("epic_infernal_phoenix", "Phénix infernal", "Epic", "rbxassetid://139045698977726"),
}

CollectionConfig.ById = {}
CollectionConfig.ByRarity = {}
for _, rarity in ipairs(CollectionConfig.RarityOrder) do CollectionConfig.ByRarity[rarity] = {} end
for _, def in ipairs(CollectionConfig.Items) do
	CollectionConfig.ById[def.Id] = def
	table.insert(CollectionConfig.ByRarity[def.Rarity], def)
end

function CollectionConfig.RollForZone(zoneId: string, random: Random): any?
	for _, rarityId in ipairs(CollectionConfig.RarityOrder) do
		local rarity = CollectionConfig.Rarities[rarityId]
		if rarity.Enabled and rarity.ZoneId == zoneId and random:NextNumber() <= rarity.SpawnChance then
			local pool = CollectionConfig.ByRarity[rarityId]
			return pool[random:NextInteger(1, #pool)]
		end
	end
	return nil
end

function CollectionConfig.PublicCatalog()
	local result = {}
	for _, def in ipairs(CollectionConfig.Items) do
		local rarity = CollectionConfig.Rarities[def.Rarity]
		table.insert(result, { Id = def.Id, Name = def.Name, Rarity = def.Rarity, ImageId = def.ImageId,
			Available = rarity.Enabled, ZoneId = rarity.ZoneId })
	end
	return result
end

return CollectionConfig
