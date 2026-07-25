--!strict
-- Définition des objets. Les formes sont calculées côté serveur à partir
-- de Shape + Radius pour éviter d'envoyer de grosses tables au client.

local ToolDefs = {}

ToolDefs.List = {
	Epingle = {
		Name = "Épingle", Rarity = "Common", Weight = 40,
		Cooldown = 0.45, Range = 20, Shape = "Cross", Radius = 1,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(255, 55, 75),
		Desc = "1 usage : éclate devant, derrière, gauche et droite. RT pour utiliser.",
	},
	Marteau = {
		Name = "Marteau", Rarity = "Common", Weight = 28,
		Cooldown = 1.0, Range = 20, Shape = "Square", Radius = 1,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(150, 110, 70),
		Desc = "1 usage : écrase un carré 3x3 autour de toi.",
	},
	Bombe = {
		Name = "Bombe", Rarity = "Rare", Weight = 14,
		Cooldown = 1.0, Range = 20, Shape = "Around", Radius = 1,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(40, 40, 45),
		Desc = "1 usage : explose les 8 bulles autour de toi.",
	},
	MegaRouleau = {
		Name = "Méga rouleau", Rarity = "Epic", Weight = 6,
		Cooldown = 1.0, Range = 20, Shape = "FullRow", Radius = 1,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(255, 140, 60),
		Desc = "1 usage : écrase toute une ligne de la grille.",
	},
	Laser = {
		Name = "Rayon laser", Rarity = "Epic", Weight = 5,
		Cooldown = 1.0, Range = 20, Shape = "Line", Radius = 16,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(255, 60, 90),
		Desc = "1 usage : traverse les bulles en ligne devant toi.",
	},
	Singularite = {
		Name = "Singularité", Rarity = "Mythic", Weight = 1,
		Cooldown = 1.0, Range = 20, Shape = "Disc", Radius = 9, Multiplier = 3,
		SelfCentered = true, Consumable = true, Color = Color3.fromRGB(180, 60, 255), Announce = true,
		Desc = "1 usage mythique : implosion massive, récompenses x3.",
	},
	-- Permanent : boost de saut, ne se consomme pas
	Ailes = {
		Name = "Ailes", Rarity = "Rare", Weight = 10,
		Cooldown = 0, Range = 0, Shape = "Wings", Radius = 0,
		SelfCentered = true, Consumable = false, Permanent = true,
		WingCells = 5, Color = Color3.fromRGB(120, 210, 255),
		Desc = "Équipe/retire (RT) : vole sur 5 bulles. Permanent.",
	},
}

ToolDefs.RarityColor = {
	Common = Color3.fromRGB(190, 190, 190),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Mythic = Color3.fromRGB(255, 90, 220),
}

local totalWeight = 0
for _, def in pairs(ToolDefs.List) do totalWeight += def.Weight end

function ToolDefs.Roll(rng: Random?): (string, any)
	local roll = if rng then rng:NextNumber(0, totalWeight) else math.random() * totalWeight
	local acc = 0
	for id, def in pairs(ToolDefs.List) do
		acc += def.Weight
		if roll <= acc then return id, def end
	end
	return "Epingle", ToolDefs.List.Epingle
end

return ToolDefs
