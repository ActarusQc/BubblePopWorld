--!strict
-- Coffres payants du chapiteau : coûts, lots et placement.
-- Tirage : 9/10 gain (dont 7/10 petit gain, 2/10 gros gain), 1/10 perte.

export type Prize = {
	Coins: number,
	Weight: number,
}

export type ChestDef = {
	Id: string,
	Label: string,
	VisualId: string,
	AccentColor: Color3,
	Cost: number,
	Prizes: { Prize },
}

local TentChestConfig = {
	Cooldown = 1.25,
	MaxOpenDistance = 16,
	HoldDuration = 0,
	PromptDistance = 10,
	Spacing = 12,
	SpreadDegrees = 70,
	BackRadiusScale = 0.52,
	MinBackDistance = 6.5,
	MaxBackDistance = 10.5,
	ChestHeight = 2.22,
	PedestalHeight = 0.55,

	-- Poids sur 100 : perte 10, petits gains 70, gros gains 20.
	Chests = {
		{
			Id = "Bronze",
			Label = "Bronze Chest",
			VisualId = "Common",
			AccentColor = Color3.fromRGB(175, 120, 55),
			Cost = 250,
			Prizes = {
				{ Coins = 80, Weight = 10 },
				{ Coins = 280, Weight = 20 },
				{ Coins = 320, Weight = 20 },
				{ Coins = 380, Weight = 15 },
				{ Coins = 450, Weight = 15 },
				{ Coins = 900, Weight = 12 },
				{ Coins = 2500, Weight = 8 },
			},
		},
		{
			Id = "Silver",
			Label = "Silver Chest",
			VisualId = "Rare",
			AccentColor = Color3.fromRGB(70, 150, 255),
			Cost = 1000,
			Prizes = {
				{ Coins = 300, Weight = 10 },
				{ Coins = 1100, Weight = 20 },
				{ Coins = 1250, Weight = 20 },
				{ Coins = 1450, Weight = 15 },
				{ Coins = 1700, Weight = 15 },
				{ Coins = 3500, Weight = 12 },
				{ Coins = 10000, Weight = 8 },
			},
		},
		{
			Id = "Gold",
			Label = "Gold Chest",
			VisualId = "Legendary",
			AccentColor = Color3.fromRGB(255, 180, 40),
			Cost = 4000,
			Prizes = {
				{ Coins = 1200, Weight = 10 },
				{ Coins = 4400, Weight = 20 },
				{ Coins = 5000, Weight = 20 },
				{ Coins = 5600, Weight = 15 },
				{ Coins = 6500, Weight = 15 },
				{ Coins = 14000, Weight = 12 },
				{ Coins = 40000, Weight = 8 },
			},
		},
	} :: { ChestDef },
}

return table.freeze(TentChestConfig)
