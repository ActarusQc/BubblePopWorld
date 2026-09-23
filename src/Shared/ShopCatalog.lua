--!strict
-- Catalogue boutique walk-in : catégories, items live et Coming Soon.

local Config = require(script.Parent.GameConfig)

export type ShopItemDef = {
	Id: string,
	NameKey: string,
	Category: string,
	DescriptionKey: string,
	IconKey: string,
	ModelName: string,
	Type: "Upgrade" | "Tool" | "Cosmetic" | "Backpack",
	Equipable: boolean,
	Available: boolean,
	UpgradeId: string?,
	ShopItemId: string?,
}

local ShopCatalog = {}

ShopCatalog.Categories = { "Skills", "Items", "Hats", "Vests", "Shirts", "Accessories", "Shoes" }

local ALL_ITEMS: { ShopItemDef } = {
	-- Skills (live)
	{
		Id = "Speed",
		NameKey = "SkillSpeed",
		Category = "Skills",
		DescriptionKey = "SkillSpeedDesc",
		IconKey = "SkillSpeed",
		ModelName = "SpeedUpgrade",
		Type = "Upgrade",
		Equipable = false,
		Available = true,
		UpgradeId = "Speed",
	},
	{
		Id = "Jump",
		NameKey = "SkillJump",
		Category = "Skills",
		DescriptionKey = "SkillJumpDesc",
		IconKey = "SkillJump",
		ModelName = "JumpUpgrade",
		Type = "Upgrade",
		Equipable = false,
		Available = true,
		UpgradeId = "Jump",
	},
	{
		Id = "Power",
		NameKey = "SkillPower",
		Category = "Skills",
		DescriptionKey = "SkillPowerDesc",
		IconKey = "SkillPower",
		ModelName = "PowerUpgrade",
		Type = "Upgrade",
		Equipable = false,
		Available = true,
		UpgradeId = "Power",
	},
	{
		Id = "CoinMult",
		NameKey = "SkillCoinMult",
		Category = "Skills",
		DescriptionKey = "SkillCoinMultDesc",
		IconKey = "SkillCoinMult",
		ModelName = "CoinMultUpgrade",
		Type = "Upgrade",
		Equipable = false,
		Available = true,
		UpgradeId = "CoinMult",
	},
	-- Skills (Coming Soon)
	{
		Id = "Magnet",
		NameKey = "SkillMagnet",
		Category = "Skills",
		DescriptionKey = "SkillMagnetDesc",
		IconKey = "SkillMagnet",
		ModelName = "MagnetUpgrade",
		Type = "Upgrade",
		Equipable = false,
		Available = false,
	},
	{
		Id = "Luck",
		NameKey = "SkillLuck",
		Category = "Skills",
		DescriptionKey = "SkillLuckDesc",
		IconKey = "SkillLuck",
		ModelName = "LuckUpgrade",
		Type = "Upgrade",
		Equipable = false,
		Available = false,
	},
	{
		Id = "CapacityBoost",
		NameKey = "SkillCapacityBoost",
		Category = "Skills",
		DescriptionKey = "SkillCapacityBoostDesc",
		IconKey = "SkillCapacityBoost",
		ModelName = "CapacityBoostUpgrade",
		Type = "Upgrade",
		Equipable = false,
		Available = false,
	},
	-- Items (live backpacks)
	{
		Id = "BackpackGold",
		NameKey = "GoldBackpack",
		Category = "Items",
		DescriptionKey = "BackpackGoldDesc",
		IconKey = "BackpackGold",
		ModelName = "BackpackGold",
		Type = "Backpack",
		Equipable = true,
		Available = true,
		ShopItemId = "BackpackGold",
	},
	{
		Id = "BackpackEmerald",
		NameKey = "EmeraldBackpack",
		Category = "Items",
		DescriptionKey = "BackpackEmeraldDesc",
		IconKey = "BackpackEmerald",
		ModelName = "BackpackEmerald",
		Type = "Backpack",
		Equipable = true,
		Available = true,
		ShopItemId = "BackpackEmerald",
	},
	{
		Id = "BackpackNeon",
		NameKey = "NeonBackpack",
		Category = "Items",
		DescriptionKey = "BackpackNeonDesc",
		IconKey = "BackpackNeon",
		ModelName = "BackpackNeon",
		Type = "Backpack",
		Equipable = true,
		Available = true,
		ShopItemId = "BackpackNeon",
	},
	-- Items (Coming Soon)
	{
		Id = "Pin",
		NameKey = "ItemPin",
		Category = "Items",
		DescriptionKey = "ItemPinDesc",
		IconKey = "ItemPin",
		ModelName = "PinTool",
		Type = "Tool",
		Equipable = false,
		Available = false,
	},
	{
		Id = "Hammer",
		NameKey = "ItemHammer",
		Category = "Items",
		DescriptionKey = "ItemHammerDesc",
		IconKey = "ItemHammer",
		ModelName = "HammerTool",
		Type = "Tool",
		Equipable = false,
		Available = false,
	},
	{
		Id = "MultiPopTool",
		NameKey = "ItemMultiPopTool",
		Category = "Items",
		DescriptionKey = "ItemMultiPopToolDesc",
		IconKey = "ItemMultiPopTool",
		ModelName = "MultiPopTool",
		Type = "Tool",
		Equipable = false,
		Available = false,
	},
	{
		Id = "SpecialTool",
		NameKey = "ItemSpecialTool",
		Category = "Items",
		DescriptionKey = "ItemSpecialToolDesc",
		IconKey = "ItemSpecialTool",
		ModelName = "SpecialTool",
		Type = "Tool",
		Equipable = false,
		Available = false,
	},
	-- Cosmetics (Coming Soon)
	{
		Id = "Cap",
		NameKey = "CosmeticCap",
		Category = "Hats",
		DescriptionKey = "CosmeticCapDesc",
		IconKey = "CosmeticCap",
		ModelName = "MulticolorCapAccessory",
		Type = "Cosmetic",
		Equipable = true,
		Available = true,
		ShopItemId = "Cap",
	},
	{
		Id = "FrogHat",
		NameKey = "CosmeticFrogHat",
		Category = "Hats",
		DescriptionKey = "CosmeticFrogHatDesc",
		IconKey = "CosmeticHat",
		ModelName = "FrogHatAccessory",
		Type = "Cosmetic",
		Equipable = true,
		Available = true,
		ShopItemId = "FrogHat",
	},
	{
		Id = "WizardHat",
		NameKey = "CosmeticWizardHat",
		Category = "Hats",
		DescriptionKey = "CosmeticWizardHatDesc",
		IconKey = "CosmeticHat",
		ModelName = "WizardHatAccessory",
		Type = "Cosmetic",
		Equipable = true,
		Available = true,
		ShopItemId = "WizardHat",
	},
	{
		Id = "BlueJeweledCrown",
		NameKey = "CosmeticBlueJeweledCrown",
		Category = "Hats",
		DescriptionKey = "CosmeticBlueJeweledCrownDesc",
		IconKey = "CosmeticHat",
		ModelName = "BlueJeweledCrownAccessory",
		Type = "Cosmetic",
		Equipable = true,
		Available = true,
		ShopItemId = "BlueJeweledCrown",
	},
	{
		Id = "Vest",
		NameKey = "CosmeticVest",
		Category = "Vests",
		DescriptionKey = "CosmeticVestDesc",
		IconKey = "CosmeticVest",
		ModelName = "VestCosmetic",
		Type = "Cosmetic",
		Equipable = true,
		Available = false,
	},
	{ Id = "RedStripesShirt", NameKey = "RedStripesShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "RedStripes", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "RedStripesShirt" },
	{ Id = "SkyBlueShirt", NameKey = "SkyBlueShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "SkyBlue", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "SkyBlueShirt" },
	{ Id = "MintWavesShirt", NameKey = "MintWavesShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "MintWaves", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "MintWavesShirt" },
	{ Id = "YellowSmileShirt", NameKey = "YellowSmileShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "YellowSmile", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "YellowSmileShirt" },
	{ Id = "OrangeSunsetShirt", NameKey = "OrangeSunsetShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "OrangeSunset", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "OrangeSunsetShirt" },
	{ Id = "LavandeStarShirt", NameKey = "LavandeStarShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "LavandeStar", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "LavandeStarShirt" },
	{ Id = "BlueBubbleShirt", NameKey = "BlueBubbleShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "BlueBubble", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "BlueBubbleShirt" },
	{ Id = "NavyBubbleShirt", NameKey = "NavyBubbleShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "Navy_Bubble", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "NavyBubbleShirt" },
	{ Id = "BlackNeonShirt", NameKey = "BlackNeonShirt", Category = "Shirts", DescriptionKey = "CommonShirtDesc", IconKey = "CosmeticShirt", ModelName = "BlackNeon", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "BlackNeonShirt" },
	{ Id = "CosmicDragonShirt", NameKey = "CosmicDragonShirt", Category = "Shirts", DescriptionKey = "EpicShirtDesc", IconKey = "CosmeticShirt", ModelName = "CosmicDragonShirt", Type = "Cosmetic", Equipable = true, Available = true, ShopItemId = "CosmicDragonShirt" },
	{
		Id = "Accessory",
		NameKey = "CosmeticAccessory",
		Category = "Accessories",
		DescriptionKey = "CosmeticAccessoryDesc",
		IconKey = "CosmeticAccessory",
		ModelName = "AccessoryCosmetic",
		Type = "Cosmetic",
		Equipable = true,
		Available = false,
	},
	{
		Id = "Shoes",
		NameKey = "CosmeticShoes",
		Category = "Shoes",
		DescriptionKey = "CosmeticShoesDesc",
		IconKey = "CosmeticShoes",
		ModelName = "ShoesCosmetic",
		Type = "Cosmetic",
		Equipable = true,
		Available = false,
	},
}

local BY_ID: { [string]: ShopItemDef } = {}
for _, item in ipairs(ALL_ITEMS) do
	BY_ID[item.Id] = item
end

-- Complète le catalogue avec les chandails découverts dans Studio par GameConfig.
for _, id in ipairs(Config.ShopItemOrder) do
	local def = Config.ShopItems[id]
	if not BY_ID[id] and def and def.Kind == "Cosmetic" and def.Slot == "Shirt" then
		local descriptionKey = if def.Style == "Epic" then "EpicShirtDesc" else if def.Style == "Rare" then "RareShirtDesc" else "CommonShirtDesc"
		local item: ShopItemDef = {
			Id = id, NameKey = def.Label, Category = "Shirts", DescriptionKey = descriptionKey,
			IconKey = "CosmeticShirt", ModelName = def.ModelName, Type = "Cosmetic",
			Equipable = true, Available = true, ShopItemId = id,
		}
		table.insert(ALL_ITEMS, item)
		BY_ID[id] = item
	end
end

local function isInList(list: { string }, id: string): boolean
	return table.find(list, id) ~= nil
end

local function isLiveItem(item: ShopItemDef): boolean
	if item.UpgradeId then
		return isInList(Config.UpgradeOrder, item.UpgradeId)
	end
	local shopId = item.ShopItemId or item.Id
	return isInList(Config.ShopItemOrder, shopId)
end

function ShopCatalog.GetItem(id: string): ShopItemDef?
	return BY_ID[id]
end

function ShopCatalog.GetCategoryItems(category: string): { ShopItemDef }
	local out: { ShopItemDef } = {}
	for _, item in ipairs(ALL_ITEMS) do
		if item.Category == category then
			table.insert(out, item)
		end
	end
	return out
end

function ShopCatalog.IsPurchasable(id: string): boolean
	local item = ShopCatalog.GetItem(id)
	if not item or not item.Available then
		return false
	end
	return isLiveItem(item)
end

return ShopCatalog
