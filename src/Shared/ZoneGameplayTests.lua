--!strict
-- Validations : palettes bulles par zone + pools d'objets GameRoom / SummerZone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local OnboardingConfig = require(Shared.OnboardingConfig)
local BubbleTypes = require(Shared.BubbleTypes)
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
	if roomCommon and summerCommon then
		check(not colorEq(roomCommon[1], summerCommon[1]), "Normal GameRoom ≠ Normal Summer")
	end

	-- Teintes actuelles GameRoom (= TintVariants cyan/savon, pas gris).
	local tints = GameConfig.Bubble.Appearance.TintVariants
	check(roomCommon ~= nil and colorEq(roomCommon[1], tints[1]), "GameRoom.Common = TintVariants[1]")

	local rare = BubbleTypes.ById.Rare
	local golden = BubbleTypes.ById.Golden
	local diamond = BubbleTypes.ById.Diamond
	local legendary = BubbleTypes.ById.Legendary
	check(rare ~= nil and golden ~= nil and diamond ~= nil and legendary ~= nil, "raretés BubbleTypes")
	if rare and golden and diamond and legendary then
		check(colorEq(rare.Color, Color3.fromRGB(90, 170, 255)), "Rare inchangé")
		check(colorEq(golden.Color, Color3.fromRGB(255, 200, 70)), "Golden inchangé")
		check(colorEq(diamond.Color, Color3.fromRGB(100, 240, 230)), "Diamond inchangé")
		check(colorEq(legendary.Color, Color3.fromRGB(255, 110, 210)), "Legendary inchangé")
	end

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
	check(OnboardingConfig.DeferCharacterLoadUntilWorldReady == true, "chargement personnage différé")

	if ok then
		print("[ZoneGameplayTests] OK")
	end
	return ok
end

return ZoneGameplayTests
