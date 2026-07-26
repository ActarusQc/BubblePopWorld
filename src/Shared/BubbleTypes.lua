--!strict
-- Table de raretés des bulles + tirage pondéré.

local BubbleTypes = {}

BubbleTypes.List = {
	-- Teintes bulle de savon (pas de blanc opaque)
	{ Id = "Normal",    Label = "Bubble",           Weight = 1000, StorageValue = 1, SellValue = 1,    Coins = 1,    Color = Color3.fromRGB(145, 225, 255) },
	{ Id = "Rare",      Label = "Rare bubble",      Weight = 110,  StorageValue = 1, SellValue = 8,    Coins = 8,    Color = Color3.fromRGB(90, 170, 255) },
	{ Id = "Golden",    Label = "Golden bubble",    Weight = 30,   StorageValue = 1, SellValue = 45,   Coins = 45,   Color = Color3.fromRGB(255, 200, 70) },
	{ Id = "Diamond",   Label = "Diamond bubble",   Weight = 7,    StorageValue = 1, SellValue = 220,  Coins = 220,  Color = Color3.fromRGB(100, 240, 230) },
	{ Id = "Legendary", Label = "Legendary bubble", Weight = 1,    StorageValue = 1, SellValue = 1800, Coins = 1800, Color = Color3.fromRGB(255, 110, 210), Announce = true },
}

BubbleTypes.ById = {}
local total = 0
for _, def in ipairs(BubbleTypes.List) do
	BubbleTypes.ById[def.Id] = def
	total += def.Weight
end

function BubbleTypes.Roll(rng: Random?)
	local roll = if rng then rng:NextNumber(0, total) else math.random() * total
	local acc = 0
	for _, def in ipairs(BubbleTypes.List) do
		acc += def.Weight
		if roll <= acc then return def end
	end
	return BubbleTypes.List[1]
end

return BubbleTypes
