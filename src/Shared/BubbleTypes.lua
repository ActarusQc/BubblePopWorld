--!strict
-- Table de raretés des bulles + tirage pondéré.

local BubbleTypes = {}

BubbleTypes.List = {
	-- Teintes bulle de savon (pas de blanc opaque)
	{ Id = "Normal",    Label = "Bulle",             Weight = 1000, Coins = 1,    XP = 1,   Color = Color3.fromRGB(145, 225, 255) },
	{ Id = "Rare",      Label = "Bulle rare",        Weight = 110,  Coins = 8,    XP = 5,   Color = Color3.fromRGB(90, 170, 255) },
	{ Id = "Golden",    Label = "Bulle dorée",       Weight = 30,   Coins = 45,   XP = 22,  Color = Color3.fromRGB(255, 200, 70) },
	{ Id = "Diamond",   Label = "Bulle diamant",     Weight = 7,    Coins = 220,  XP = 95,  Color = Color3.fromRGB(100, 240, 230) },
	{ Id = "Legendary", Label = "Bulle légendaire",  Weight = 1,    Coins = 1800, XP = 700, Color = Color3.fromRGB(255, 110, 210), Announce = true },
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
