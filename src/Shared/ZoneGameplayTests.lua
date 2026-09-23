--!strict
-- Validations : palettes bulles par zone + pools d'objets GameRoom / SummerZone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local OnboardingConfig = require(Shared.OnboardingConfig)
local BubbleTypes = require(Shared.BubbleTypes)
local BubbleAppearance = require(Shared.BubbleAppearance)
local ToolDefs = require(Shared.ToolDefs)

local ZoneGameplayTests = {}

local function colorEq(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 1e-4
		and math.abs(a.G - b.G) < 1e-4
		and math.abs(a.B - b.B) < 1e-4
end

local function normalizeCommon(common: any): { Color3 }?
	if common == nil then
		return nil
	end
	if typeof(common) == "Color3" then
		return { common :: Color3 }
	end
	if type(common) == "table" then
		local asTable = common :: { any }
		if asTable[1] ~= nil then
			return asTable :: { Color3 }
		end
		if type(asTable.R) == "number" then
			return { common :: Color3 }
		end
	end
	return nil
end

function ZoneGameplayTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[ZoneGameplayTests] FAIL:", msg)
			ok = false
		end
	end

	local palettes = GameConfig.ZoneBubblePalettes
	check(palettes ~= nil, "ZoneBubblePalettes présent")
	check(palettes.GameRoom ~= nil and palettes.SummerZone ~= nil, "clés GameRoom + SummerZone")

	local roomCommon = normalizeCommon(palettes.GameRoom.Common)
	local summerCommon = normalizeCommon(palettes.SummerZone.Common)
	check(roomCommon ~= nil and #roomCommon > 0, "GameRoom.Common non vide")
	check(summerCommon ~= nil and #summerCommon > 0, "SummerZone.Common non vide")
	if summerCommon then
		check(colorEq(summerCommon[1], Color3.fromRGB(255, 145, 35)), "Summer Normal = orange 255,145,35")
	end

	BubbleAppearance.ClearPaletteCache()
	local filteredRoom = BubbleAppearance.GetNormalPalette("GameRoom")
	check(#filteredRoom == 4, "palette GameRoom = 4 pastels")
	check(BubbleAppearance.ColorsAreDistinct(filteredRoom), "GameRoom couleurs distinctes")
	local expectedPastel = {
		Color3.fromRGB(85, 165, 215),
		Color3.fromRGB(90, 190, 145),
		Color3.fromRGB(145, 120, 210),
		Color3.fromRGB(220, 125, 100),
	}
	for i, c in ipairs(expectedPastel) do
		check(colorEq(filteredRoom[i], c), "GameRoom pastel[" .. i .. "]")
	end
	if summerCommon then
		check(not colorEq(filteredRoom[1], summerCommon[1]), "Normal GameRoom ≠ Normal Summer")
	end

	local rare = BubbleTypes.ById.Rare
	local golden = BubbleTypes.ById.Golden
	local diamond = BubbleTypes.ById.Diamond
	local legendary = BubbleTypes.ById.Legendary
	check(rare ~= nil and golden ~= nil and diamond ~= nil and legendary ~= nil, "raretés BubbleTypes")
	if rare and golden and diamond and legendary then
		check(colorEq(rare.Color, Color3.fromRGB(200, 45, 45)), "Rare rouge Neon")
		check(colorEq(golden.Color, Color3.fromRGB(200, 155, 25)), "Golden jaune Neon")
		check(colorEq(diamond.Color, Color3.fromRGB(20, 175, 195)), "Diamond cyan Neon")
		check(colorEq(legendary.Color, Color3.fromRGB(185, 35, 140)), "Legendary magenta Neon")
		for _, normalColor in ipairs(filteredRoom) do
			check(not colorEq(normalColor, rare.Color), "normale ≠ Rare")
			check(not colorEq(normalColor, golden.Color), "normale ≠ Golden")
			check(not colorEq(normalColor, diamond.Color), "normale ≠ Diamond")
			check(not colorEq(normalColor, legendary.Color), "normale ≠ Legendary")
		end
	end

	local normalStyle = BubbleAppearance.Resolve("GameRoom", "Normal", 1)
check(normalStyle.Material == Enum.Material.SmoothPlastic, "GameRoom Normal Material glossy")
check(normalStyle.Reflectance == 0.08, "GameRoom Normal Reflectance glossy")
	check(normalStyle.Transparency == 0, "GameRoom Normal Transparency 0")
	check(normalStyle.CastShadow == false, "GameRoom Normal CastShadow false")
	local rareStyle = BubbleAppearance.Resolve("GameRoom", "Rare", 1)
check(rareStyle.Material == Enum.Material.SmoothPlastic, "GameRoom Rare Material glossy")
check(rareStyle.Reflectance == 0.1, "GameRoom Rare Reflectance glossy")

	local pools = ToolDefs.ZoneItemPools
	check(pools ~= nil and pools.GameRoom ~= nil and pools.SummerZone ~= nil, "ZoneItemPools")

	check(ToolDefs.PoolKeyForZone("ClassicZone") == "GameRoom", "ClassicZone → GameRoom")
	check(ToolDefs.PoolKeyForZone("SummerZone") == "SummerZone", "SummerZone → SummerZone")

	check(ToolDefs.IsInZonePool("ClassicZone", "Epingle") == true, "Epingle in GameRoom")
	check(ToolDefs.IsInZonePool("ClassicZone", "Marteau") == true, "Marteau in GameRoom")
	check(ToolDefs.IsInZonePool("ClassicZone", "Bombe") == false, "Bombe hors GameRoom")
	check(ToolDefs.IsInZonePool("ClassicZone", "MegaRouleau") == false, "MegaRouleau hors GameRoom")
	check(ToolDefs.IsInZonePool("ClassicZone", "Laser") == false, "Laser hors GameRoom")
	check(ToolDefs.IsInZonePool("ClassicZone", "Singularite") == false, "Singularite hors GameRoom")
	check(ToolDefs.IsInZonePool("ClassicZone", "Ailes") == false, "Ailes hors GameRoom")

	for _, id in ipairs({ "Epingle", "Marteau", "Bombe", "Ailes", "MegaRouleau", "Laser", "Singularite" }) do
		check(ToolDefs.IsInZonePool("SummerZone", id) == true, id .. " in SummerZone")
	end

	-- Poids : objets puissants plus rares que les faibles dans Summer.
	local summerWeights: { [string]: number } = {}
	for _, entry in ipairs(pools.SummerZone) do
		summerWeights[entry.ItemId] = entry.Weight
		check(entry.Weight > 0, "poids > 0 " .. entry.ItemId)
		check(ToolDefs.List[entry.ItemId] ~= nil, "ItemId connu " .. entry.ItemId)
	end
	check((summerWeights.Epingle or 0) > (summerWeights.MegaRouleau or 0), "Epingle > MegaRouleau")
	check((summerWeights.Marteau or 0) > (summerWeights.Laser or 0), "Marteau > Laser")
	check((summerWeights.Singularite or 0) <= (summerWeights.Laser or 0), "Singularite ≤ Laser")

	local rng = Random.new(42)
	for _ = 1, 40 do
		local id = ToolDefs.RollForZone("ClassicZone", rng)
		check(id == "Epingle" or id == "Marteau", "RollForZone Classic = faible impact")
	end

	local seenPowerful = false
	for _ = 1, 200 do
		local id = ToolDefs.RollForZone("SummerZone", rng)
		if id == "MegaRouleau" or id == "Laser" or id == "Singularite" then
			seenPowerful = true
		end
		check(ToolDefs.IsInZonePool("SummerZone", id), "RollForZone Summer dans pool")
	end
	check(seenPowerful == true, "Summer peut tirer un objet puissant")

	-- Spawn onboarding Phase 1 : SpawnPad loin de l'origine, snap de secours cohérent.
	local pad = GameConfig.GameRoom.SpawnPadPosition
	check(pad ~= nil, "SpawnPadPosition défini")
	if pad then
		check(
			OnboardingConfig.IsNearWorldOrigin(pad.X, pad.Z) == false,
			"SpawnPad hors rayon origine monde"
		)
		local originDist = OnboardingConfig.HorizontalDistance(0, 0, pad.X, pad.Z)
		check(originDist > OnboardingConfig.GameRoomSnapMaxDistance, "origine → SpawnPad exige un snap")
		check(OnboardingConfig.NeedsGameRoomSnap(originDist) == true, "NeedsGameRoomSnap(origine→pad)")
		check(OnboardingConfig.NeedsGameRoomSnap(0) == false, "NeedsGameRoomSnap(0) false")
	end
	check(OnboardingConfig.DeferCharacterLoadUntilWorldReady == false, "CharacterAutoLoads non coupé")
	check(OnboardingConfig.EarlySpawnLocationBootstrap == true, "SpawnLocation bootstrap précoce")

	if ok then
		print("[ZoneGameplayTests] OK")
	end
	return ok
end

return ZoneGameplayTests
