--!strict
-- Apparence zone principale : Neon émissif stable + pastels calibrés, sans marqueurs.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local BubbleTypes = require(Shared.BubbleTypes)
local BubbleAppearance = require(Shared.BubbleAppearance)
local BubbleValue = require(Shared.BubbleValue)
local ChestAppearance = require(Shared.ChestAppearance)

local BubbleAppearanceTests = {}

local function colorEq(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 1e-4
		and math.abs(a.G - b.G) < 1e-4
		and math.abs(a.B - b.B) < 1e-4
end

function BubbleAppearanceTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[BubbleAppearanceTests] FAIL:", msg)
			ok = false
		end
	end

	BubbleAppearance.ClearPaletteCache()

	local lightingSnap = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ExposureCompensation = Lighting.ExposureCompensation,
	}

	-- Valeurs / poids inchangés
	check(BubbleTypes.ById.Normal.Weight == 1000, "Weight Normal")
	check(BubbleTypes.ById.Rare.Weight == 110, "Weight Rare")
	check(BubbleTypes.ById.Golden.Weight == 30, "Weight Golden")
	check(BubbleTypes.ById.Diamond.Weight == 7, "Weight Diamond")
	check(BubbleTypes.ById.Legendary.Weight == 1, "Weight Legendary")
	check(BubbleTypes.ById.Normal.SellValue == 1, "Sell Normal")
	check(BubbleTypes.ById.Rare.SellValue == 8, "Sell Rare")
	check(BubbleTypes.ById.Golden.SellValue == 45, "Sell Golden")
	check(BubbleTypes.ById.Diamond.SellValue == 220, "Sell Diamond")
	check(BubbleTypes.ById.Legendary.SellValue == 1800, "Sell Legendary")

	local specialMap = GameConfig.Bubble.MainZoneSpecialColors
	check(specialMap ~= nil, "MainZoneSpecialColors présent")
	check(colorEq(BubbleTypes.ById.Rare.Color, Color3.fromRGB(200, 45, 45)), "Rare rouge Neon")
	check(colorEq(BubbleTypes.ById.Golden.Color, Color3.fromRGB(200, 155, 25)), "Golden jaune Neon")
	check(colorEq(BubbleTypes.ById.Diamond.Color, Color3.fromRGB(20, 175, 195)), "Diamond cyan Neon")
	check(colorEq(BubbleTypes.ById.Legendary.Color, Color3.fromRGB(185, 35, 140)), "Legendary magenta Neon")
	if specialMap then
		check(colorEq(specialMap.Rare, BubbleTypes.ById.Rare.Color), "map Rare = BubbleTypes")
		check(colorEq(specialMap.Golden, BubbleTypes.ById.Golden.Color), "map Golden = BubbleTypes")
		check(colorEq(specialMap.Diamond, BubbleTypes.ById.Diamond.Color), "map Diamond = BubbleTypes")
		check(colorEq(specialMap.Legendary, BubbleTypes.ById.Legendary.Color), "map Legendary = BubbleTypes")
	end

	local rng = Random.new(20260802)
	local counts: { [string]: number } = {}
	local N = 30000
	for _ = 1, N do
		local def = BubbleTypes.Roll(rng)
		counts[def.Id] = (counts[def.Id] or 0) + 1
	end
	for _, def in ipairs(BubbleTypes.List) do
		if def.Weight > 0 then
			check((counts[def.Id] or 0) > 0, def.Id .. " sélectionnable")
		end
	end

	-- Palette pastels Neon zone principale (4 couleurs)
	local pastel = GameConfig.Bubble.MainZoneNormalColors
	check(type(pastel) == "table" and #pastel == 4, "MainZoneNormalColors = 4")
	local expectedPastel = {
		Color3.fromRGB(85, 165, 215),
		Color3.fromRGB(90, 190, 145),
		Color3.fromRGB(145, 120, 210),
		Color3.fromRGB(220, 125, 100),
	}
	if pastel then
		for i, c in ipairs(expectedPastel) do
			check(colorEq(pastel[i], c), "pastel[" .. i .. "] exact")
		end
	end

	local roomPalette = BubbleAppearance.GetNormalPalette("ClassicZone")
	check(#roomPalette == 4, "palette ClassicZone = 4 pastels")
	check(BubbleAppearance.ColorsAreDistinct(roomPalette), "pastels distincts")

	local seenPastel: { [number]: boolean } = {}
	for i = 1, 4 do
		local part = Instance.new("Part")
		part.Size = Vector3.new(5.4, 2, 5.4)
		Instance.new("SpecialMesh").Parent = part
		BubbleAppearance.ApplyBubbleVisual(part, "Normal", "ClassicZone", i, true)
		check(BubbleAppearance.IsNormalPaletteColor("ClassicZone", part.Color), "normal tint " .. i .. " pastel")
		check(BubbleAppearance.IsAllowedMainZoneNormalColor(part.Color), "normal " .. i .. " palette autorisée")
		check(BubbleAppearance.IsMainZoneStableVisual(part, true), "normal " .. i .. " rendu stable Neon")
		check(not BubbleAppearance.HasRarityMarker(part), "normal " .. i .. " sans marqueur")
		check(not BubbleAppearance.HasSpecialBorder(part), "normal " .. i .. " sans bordure")
		check(not BubbleAppearance.HasSpecialSymbol(part), "normal " .. i .. " sans symbole")
		check(not BubbleAppearance.HasRealLights(part), "normal " .. i .. " sans lights")
		check(not BubbleAppearance.HasBeam(part), "normal " .. i .. " sans beam")
		check(part.Material == Enum.Material.Neon, "normal " .. i .. " Neon")
		check(part.Reflectance == 0, "normal " .. i .. " Reflectance 0")
		check(part.Transparency == 0, "normal " .. i .. " Transparency 0")
		check(part.CastShadow == false, "normal " .. i .. " CastShadow false")
		check(part:FindFirstChildOfClass("SurfaceAppearance") == nil, "normal " .. i .. " pas SurfaceAppearance")
		check(part:FindFirstChildOfClass("Highlight") == nil, "normal " .. i .. " pas Highlight")
		check(colorEq(part.Color, expectedPastel[i]), "normal tint " .. i .. " couleur fixe")
		seenPastel[i] = true
		local fixedColor = part.Color
		local fixedMat = part.Material
		-- Les propriétés ne changent pas tant que la bulle est active du même type
		BubbleAppearance.ApplyToPart(part, "ClassicZone", "Normal", i, true)
		check(colorEq(part.Color, fixedColor), "normal " .. i .. " couleur stable apply")
		check(part.Material == fixedMat, "normal " .. i .. " Material stable apply")
		part:Destroy()
	end
	for i = 1, 4 do
		check(seenPastel[i] == true, "pastel " .. i .. " réalisable")
	end

	-- A/B matériaux : Resolve n’utilise pas Plastic/SmoothPlastic en zone principale
	local ab = BubbleAppearance.Resolve("ClassicZone", "Normal", 1)
	check(ab.Material == Enum.Material.Neon, "Resolve main Normal = Neon (pas Plastic/SmoothPlastic)")
	check(ab.Reflectance == 0, "Resolve main Reflectance 0")
	check(ab.Transparency == 0, "Resolve main Transparency 0")

	local specialIds = { "Rare", "Golden", "Diamond", "Legendary" }
	for _, id in ipairs(specialIds) do
		local def = BubbleTypes.ById[id]
		local part = Instance.new("Part")
		part.Size = Vector3.new(5.4, 2, 5.4)
		part.CFrame = CFrame.new(5, 12, 0)
		Instance.new("SpecialMesh").Parent = part
		BubbleAppearance.ApplyToPart(part, "ClassicZone", id, 1, true)

		check(not BubbleAppearance.HasBeam(part), id .. " no Beam")
		check(not BubbleAppearance.HasRealLights(part), id .. " no Point/Spot/SurfaceLight")
		check(not BubbleAppearance.HasSpecialBorder(part), id .. " sans bordure")
		check(not BubbleAppearance.HasSpecialSymbol(part), id .. " sans symbole")
		check(not BubbleAppearance.HasRarityMarker(part), id .. " sans marqueur rareté")
		check(colorEq(part.Color, def.Color), id .. " couleur réservée fixe")
		check(BubbleAppearance.IsAllowedMainZoneSpecialColor(part.Color), id .. " palette spéciale autorisée")
		check(colorEq(part.Color, BubbleAppearance.GetSpecialColor(id)), id .. " GetSpecialColor")
		check(not BubbleAppearance.IsNormalPaletteColor("ClassicZone", part.Color), id .. " hors palette pastel")
		check(part:GetAttribute("BaseValue") == def.SellValue, id .. " valeur")
		check(part.Material == Enum.Material.Neon, id .. " Neon")
		check(part.Reflectance == 0, id .. " Reflectance 0 main")
		check(part.Transparency == 0, id .. " Transparency 0")
		check(part.CastShadow == false, id .. " CastShadow false")
		check(BubbleAppearance.IsMainZoneStableVisual(part, true), id .. " stable visual")
		check(part:FindFirstChild("SpecialVisuals") == nil, id .. " pas de folder SpecialVisuals")
		check(part:FindFirstChildOfClass("SurfaceAppearance") == nil, id .. " pas SurfaceAppearance")

		-- Pop nettoie
		BubbleAppearance.ApplyToPart(part, "ClassicZone", id, 1, false)
		check(not BubbleAppearance.HasSpecialBorder(part), id .. " bordure cleared")
		check(not BubbleAppearance.HasSpecialSymbol(part), id .. " symbol cleared")
		check(not BubbleAppearance.HasRarityMarker(part), id .. " marqueurs cleared après pop")
		check(not BubbleAppearance.HasRealLights(part), id .. " lights still none after pop")
		check(part.Material == Enum.Material.Neon, id .. " Neon après pop")

		-- Respawn special : même couleur fixe, toujours sans marqueur
		BubbleAppearance.ApplyToPart(part, "ClassicZone", id, 1, true)
		check(colorEq(part.Color, def.Color), id .. " couleur fixe au respawn")
		check(part.Material == Enum.Material.Neon, id .. " Neon respawn")
		check(not BubbleAppearance.HasRarityMarker(part), id .. " sans marqueur respawn")
		check(not BubbleAppearance.HasRealLights(part), id .. " no lights respawn")

		-- Respawn normal : purge + pastel Neon
		BubbleAppearance.ApplyToPart(part, "ClassicZone", "Normal", 3, true)
		check(not BubbleAppearance.HasSpecialBorder(part), id .. "→Normal clear border")
		check(not BubbleAppearance.HasSpecialSymbol(part), id .. "→Normal clear symbol")
		check(not BubbleAppearance.HasRarityMarker(part), id .. "→Normal clear markers")
		check(BubbleAppearance.IsNormalPaletteColor("ClassicZone", part.Color), id .. "→Normal pastel")
		check(part.Material == Enum.Material.Neon, id .. "→Normal Neon")
		check(not colorEq(part.Color, def.Color), id .. "→Normal ne conserve pas couleur spéciale")
		check(BubbleAppearance.IsMainZoneStableVisual(part, true), id .. "→Normal stable")
		part:Destroy()
	end

	-- Cycle recycle : Normal → Special → Normal
	local recycle = Instance.new("Part")
	recycle.Size = Vector3.new(5.4, 2, 5.4)
	Instance.new("SpecialMesh").Parent = recycle
	BubbleAppearance.ApplyBubbleVisual(recycle, "Normal", "GameRoom", 1, true)
	check(BubbleAppearance.IsMainZoneStableVisual(recycle, true), "recycle start stable")
	local mat0 = recycle.Material
	BubbleAppearance.ApplyBubbleVisual(recycle, "Rare", "GameRoom", 1, true)
	check(recycle.Material == Enum.Material.Neon, "recycle→Rare Neon")
	check(colorEq(recycle.Color, Color3.fromRGB(200, 45, 45)), "recycle→Rare color")
	check(not BubbleAppearance.HasRarityMarker(recycle), "recycle→Rare no markers")
	BubbleAppearance.ApplyBubbleVisual(recycle, "Normal", "GameRoom", 2, true)
	check(recycle.Material == mat0, "recycle→Normal material preserved Neon")
	check(colorEq(recycle.Color, expectedPastel[2]), "recycle→Normal menthe")
	check(BubbleAppearance.IsMainZoneStableVisual(recycle, true), "recycle end stable")
	recycle:Destroy()

	-- Plus de symboles de rareté sur zone principale
	check(BubbleAppearance.GetSymbolForRarity("Rare") == nil, "symbol Rare nil")
	check(BubbleAppearance.GetSymbolForRarity("Golden") == nil, "symbol Golden nil")
	check(BubbleAppearance.GetSymbolForRarity("Diamond") == nil, "symbol Diamond nil")
	check(BubbleAppearance.GetSymbolForRarity("Legendary") == nil, "symbol Legendary nil")
	check(BubbleAppearance.GetSymbolForRarity("Normal") == nil, "symbol Normal nil")

	-- Lighting inchangé par Apply
	check(Lighting.Brightness == lightingSnap.Brightness, "Lighting.Brightness intact")
	check(Lighting.Ambient == lightingSnap.Ambient, "Lighting.Ambient intact")
	check(Lighting.OutdoorAmbient == lightingSnap.OutdoorAmbient, "Lighting.OutdoorAmbient intact")
	check(Lighting.ExposureCompensation == lightingSnap.ExposureCompensation, "Exposure intact")

	-- Summer inchangée
	local sn = BubbleAppearance.Resolve("SummerZone", "Normal", 1)
	check(colorEq(sn.Color, Color3.fromRGB(255, 145, 35)), "Summer Normal orange")
	check(sn.Material == Enum.Material.Glass, "Summer Normal Glass")
	check(BubbleValue.GetBubbleBagValue("Rare", "SummerZone") == 16, "Summer bag")

	local summerMap = GameConfig.Bubble.SummerZoneSpecialColors
	if summerMap then
		check(colorEq(summerMap.Rare, Color3.fromRGB(255, 125, 25)), "Summer Rare orange legacy")
		check(colorEq(summerMap.Golden, Color3.fromRGB(175, 190, 210)), "Summer Golden argent")
		check(colorEq(summerMap.Diamond, Color3.fromRGB(255, 200, 45)), "Summer Diamond or")
		check(colorEq(summerMap.Legendary, Color3.fromRGB(190, 55, 255)), "Summer Legendary violet")
		check(colorEq(BubbleAppearance.GetSpecialColor("Rare", "SummerZone"), summerMap.Rare), "GetSpecialColor Summer Rare")
	end

	local partS = Instance.new("Part")
	partS.Size = Vector3.new(5.4, 2, 5.4)
	Instance.new("SpecialMesh").Parent = partS
	BubbleAppearance.ApplyToPart(partS, "SummerZone", "Rare", 1, true)
	check(colorEq(partS.Color, Color3.fromRGB(255, 125, 25)), "Summer Rare body color")
	check(BubbleAppearance.HasSpecialBorder(partS), "Summer Rare garde bordure")
	check(BubbleAppearance.HasSpecialSymbol(partS), "Summer Rare garde symbole")
	check(partS.Material == Enum.Material.SmoothPlastic, "Summer Rare Material SmoothPlastic")
	partS:Destroy()

	check(BubbleAppearance.GetSymbolForRarity("Rare", "SummerZone") == "★", "symbol Summer Rare")
	check(BubbleAppearance.GetSymbolForRarity("Rare", "ClassicZone") == nil, "symbol Classic nil")
	check(BubbleAppearance.GetSymbolForRarity("Rare") == nil, "symbol default nil")

	local chest = ChestAppearance.BuildModel(GameConfig.Chest.Tiers[1], CFrame.new())
	check(chest:FindFirstChild("Body") ~= nil, "Chest model")
	local chestLights = 0
	for _, d in ipairs(chest:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			chestLights += 1
		end
	end
	check(chestLights == 0, "Chest sans vraie lumière (anti surexposition)")
	chest:Destroy()

	if ok then
		print("[BubbleAppearanceTests] OK")
	end
	return ok
end

return BubbleAppearanceTests
