--!strict
-- Apparence centralisée des coffres (modèle lisible + couleurs par tier config).
-- Ne décide pas les récompenses ni les probabilités.

local GameConfig = require(script.Parent.GameConfig)

local ChestAppearance = {}

export type TierVisual = {
	AccentColor: Color3,
	BodyColor: Color3,
	MetalColor: Color3,
	LightBrightness: number,
	LightRange: number,
	UseNeonAccent: boolean,
	IsChestModel: boolean,
}

-- Bois / métal de base ; l'accent vient du tier.Color réel de GameConfig.
local BODY_BY_TIER: { [string]: Color3 } = {
	Common = Color3.fromRGB(120, 78, 42),
	Rare = Color3.fromRGB(55, 72, 110),
	Epic = Color3.fromRGB(78, 48, 112),
	Legendary = Color3.fromRGB(120, 82, 28),
}

local METAL_BY_TIER: { [string]: Color3 } = {
	Common = Color3.fromRGB(150, 115, 70),
	Rare = Color3.fromRGB(190, 205, 230),
	Epic = Color3.fromRGB(190, 150, 255),
	Legendary = Color3.fromRGB(255, 210, 90),
}

function ChestAppearance.GetTierById(tierId: string): any?
	for _, tier in ipairs(GameConfig.Chest.Tiers) do
		if tier.Id == tierId then
			return tier
		end
	end
	return nil
end

function ChestAppearance.ResolveVisual(tier: any): TierVisual
	local id = if type(tier) == "table" then tostring(tier.Id or "Common") else "Common"
	local accent = if type(tier) == "table" and typeof(tier.Color) == "Color3"
		then tier.Color
		else Color3.fromRGB(170, 120, 70)
	local rank = 1
	for i, t in ipairs(GameConfig.Chest.Tiers) do
		if t.Id == id then
			rank = i
			break
		end
	end
	local t = rank / math.max(#GameConfig.Chest.Tiers, 1)
	return {
		AccentColor = accent,
		BodyColor = BODY_BY_TIER[id] or Color3.fromRGB(110, 75, 40),
		MetalColor = METAL_BY_TIER[id] or Color3.fromRGB(160, 160, 160),
		LightBrightness = 1.2 + t * 2.4,
		LightRange = 14 + t * 16,
		UseNeonAccent = id == "Epic" or id == "Legendary",
		IsChestModel = true,
	}
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	worldCFrame: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Material = material
	p.Color = color
	p.Size = size
	p.CFrame = worldCFrame
	p.Parent = parent
	return p
end

-- Construit un coffre Model. `root` (Part) porte le ProximityPrompt + PrimaryPart.
function ChestAppearance.BuildModel(tier: any, worldCFrame: CFrame): Model
	local visual = ChestAppearance.ResolveVisual(tier)
	local tierId = if type(tier) == "table" then tostring(tier.Id or "Common") else "Common"

	local model = Instance.new("Model")
	model.Name = "Chest_" .. tierId
	model:SetAttribute("TierId", tierId)
	model:SetAttribute("IsChestModel", true)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = true
	root.CanTouch = false
	root.Transparency = 1
	root.Size = Vector3.new(4.6, 3.6, 3.2)
	root.CFrame = worldCFrame
	root.Parent = model
	model.PrimaryPart = root

	makePart(
		model,
		"Body",
		Vector3.new(4.2, 2.2, 2.9),
		worldCFrame * CFrame.new(0, -0.4, 0),
		visual.BodyColor,
		Enum.Material.Wood
	)

	makePart(
		model,
		"Lid",
		Vector3.new(4.35, 0.7, 3.05),
		worldCFrame * CFrame.new(0, 0.95, 0),
		visual.BodyColor:Lerp(visual.AccentColor, 0.25),
		Enum.Material.Wood
	)

	local band = makePart(
		model,
		"Band",
		Vector3.new(4.45, 0.35, 3.1),
		worldCFrame * CFrame.new(0, 0.25, 0),
		visual.MetalColor,
		Enum.Material.Metal
	)
	band.Reflectance = 0.25

	makePart(
		model,
		"Lock",
		Vector3.new(0.7, 0.85, 0.35),
		worldCFrame * CFrame.new(0, 0.15, 1.55),
		visual.AccentColor,
		if visual.UseNeonAccent then Enum.Material.Neon else Enum.Material.Metal
	)

	local feetOffsets = {
		Vector3.new(-1.6, -1.55, -1.0),
		Vector3.new(1.6, -1.55, -1.0),
		Vector3.new(-1.6, -1.55, 1.0),
		Vector3.new(1.6, -1.55, 1.0),
	}
	for i, off in ipairs(feetOffsets) do
		makePart(
			model,
			"Foot" .. i,
			Vector3.new(0.55, 0.35, 0.55),
			worldCFrame * CFrame.new(off),
			visual.MetalColor,
			Enum.Material.Metal
		)
	end

	makePart(
		model,
		"Trim",
		Vector3.new(4.5, 0.2, 0.25),
		worldCFrame * CFrame.new(0, 1.25, 1.45),
		visual.AccentColor,
		if visual.UseNeonAccent then Enum.Material.Neon else Enum.Material.Metal
	)

	-- PointLight retiré : ne doit jamais surexposer le hub (même si peu de coffres).
	-- Couleur / silhouette restent l’identifiant de rareté.
	if tierId == "Legendary" then
		-- Pas de particules / lumières : silhouette métal + accent or suffisent.
	end

	return model
end

-- Vérifie qu'un instance construit n'est pas le placeholder monobloc blanc.
function ChestAppearance.IsPlaceholderWhiteBox(instance: Instance): boolean
	if instance:IsA("Model") and instance:GetAttribute("IsChestModel") == true then
		return false
	end
	if instance:IsA("BasePart") and instance:FindFirstChild("Body") == nil then
		-- Ancien Part unique « carré » : considéré placeholder si monochrome clair Neon.
		if instance.Material == Enum.Material.Neon then
			local c = instance.Color
			local brightness = (c.R + c.G + c.B) / 3
			return brightness > 0.7 and math.abs(c.R - c.G) < 0.08 and math.abs(c.G - c.B) < 0.08
		end
	end
	return false
end

return ChestAppearance
