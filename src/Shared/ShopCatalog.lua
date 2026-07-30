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

ShopCatalog.Categories = { "Skills", "Items", "Cosmetics" }

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
		Category = "Cosmetics",
		DescriptionKey = "CosmeticCapDesc",
		IconKey = "CosmeticCap",
		ModelName = "CapCosmetic",
		Type = "Cosmetic",
		Equipable = true,
		Available = false,
	},
	{
		Id = "Hat",
		NameKey = "CosmeticHat",
		Category = "Cosmetics",
		DescriptionKey = "CosmeticHatDesc",
		IconKey = "CosmeticHat",
		ModelName = "HatCosmetic",
		Type = "Cosmetic",
		Equipable = true,
		Available = false,
	},
	{
		Id = "Vest",
		NameKey = "CosmeticVest",
		Category = "Cosmetics",
		DescriptionKey = "CosmeticVestDesc",
		IconKey = "CosmeticVest",
		ModelName = "VestCosmetic",
		Type = "Cosmetic",
		Equipable = true,
		Available = false,
	},
	{
		Id = "Shirt",
		NameKey = "CosmeticShirt",
		Category = "Cosmetics",
		DescriptionKey = "CosmeticShirtDesc",
		IconKey = "CosmeticShirt",
		ModelName = "ShirtCosmetic",
		Type = "Cosmetic",
		Equipable = true,
		Available = false,
	},
	{
		Id = "Accessory",
		NameKey = "CosmeticAccessory",
		Category = "Cosmetics",
		DescriptionKey = "CosmeticAccessoryDesc",
		IconKey = "CosmeticAccessory",
		ModelName = "AccessoryCosmetic",
		Type = "Cosmetic",
		Equipable = true,
		Available = false,
	},
}

local BY_ID: { [string]: ShopItemDef } = {}
for _, item in ipairs(ALL_ITEMS) do
	BY_ID[item.Id] = item
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
