--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubSpawnLogic = require(Shared.HubSpawnLogic)
local ManualRig = require(Shared.RearHubManualRig)

local HubSpawnLogicTests = {}

function HubSpawnLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[HubSpawnLogicTests] FAIL:", msg)
			ok = false
		end
	end

	-- Spawn manuel : CFrame Studio intouchable, aucun déplacement du personnage
	check(HubSpawnLogic.IsManualPlacement(true, false) == true, "BPW_ManualPlacement")
	check(HubSpawnLogic.ShouldRewriteSpawnCFrame(true) == false, "pas de rewrite CFrame manuel")
	check(HubSpawnLogic.UsesRobloxRespawnLocation() == true, "RespawnLocation natif")
	check(HubSpawnLogic.AllowsPostSpawnCharacterTeleport("CharacterAdded") == false, "aucun teleport post-spawn")
	check(HubSpawnLogic.MaxPostSpawnTeleports() == 0, "0 teleport")
	check(HubSpawnLogic.FootFloorGapOk(0.05) == true, "gap ok")
	check(HubSpawnLogic.FootFloorGapOk(1.2) == false, "flottement rejeté")
	check(HubSpawnLogic.FootFloorGapOk(-0.5) == false, "enfoncement rejeté")

	-- Versions
	check(ManualRig.CODE_VERSION == "MANUAL-RIG-V1", "code version rig")
	check(ManualRig.RIG_VERSION == "MANUAL_RIG_V1", "rig version")
	check(ManualRig.RIG_NAME == "ManualCollisionRig", "nom du rig")

	-- Structure exacte du rig
	local expected = {
		"UpperDeckFloor",
		"LowerDeckFloor",
		"FrontStairRamp",
		"LeftDeckFloor",
		"RightDeckFloor",
		"LeftFoundationBlocker",
		"RightFoundationBlocker",
		"FrontFoundationBlockerLeft",
		"FrontFoundationBlockerRight",
	}
	check(#ManualRig.SPECS == #expected, "9 collisions attendues")
	for i, name in ipairs(expected) do
		check(ManualRig.SPECS[i] ~= nil and ManualRig.SPECS[i].Name == name, "collision #" .. i .. " = " .. name)
	end

	-- Couleurs par type
	check(ManualRig.KindForName("UpperDeckFloor") == "Walkable", "palier praticable")
	check(ManualRig.KindForName("FrontStairRamp") == "Ramp", "rampe")
	check(ManualRig.KindForName("LeftFoundationBlocker") == "Blocker", "bloqueur")
	local green = ManualRig.ColorForKind("Walkable")
	local yellow = ManualRig.ColorForKind("Ramp")
	local red = ManualRig.ColorForKind("Blocker")
	check(green.G > green.R and green.G > green.B, "praticable = vert")
	check(yellow.R > 0.7 and yellow.G > 0.7 and yellow.B < 0.3, "rampe = jaune")
	check(red.R > red.G and red.R > red.B, "bloqueur = rouge")

	-- Visibilité édition / runtime
	check(ManualRig.EditTransparency() == 0.35, "transparence édition")
	check(ManualRig.RuntimeTransparency() == 1, "invisible au runtime")

	-- Préservation des placements manuels
	check(ManualRig.ShouldPreserveManualPart(true) == true, "placement manuel préservé")
	check(ManualRig.ShouldPreserveManualPart(false) == false, "placement auto remplaçable")
	check(ManualRig.ShouldPreserveManualPart(nil) == false, "attribut absent")

	-- Anciens systèmes supprimés
	for _, name in ipairs({
		"FrontStairSafetyRamp",
		"UpperSpawnWalkSurface",
		"UpperDeckWalkSurface",
		"MainDeckWalkSurface",
		"MainFloorCollision",
		"FrontAccessRamp",
		"LeftAccessRamp",
		"RightAccessRamp",
	}) do
		check(ManualRig.IsLegacyPartName(name) == true, "legacy: " .. name)
	end
	check(ManualRig.IsLegacyFolderName("RearHubCollisions") == true, "dossier legacy")
	for _, spec in ipairs(ManualRig.SPECS) do
		check(ManualRig.IsLegacyPartName(spec.Name) == false, "rig conservé: " .. spec.Name)
	end

	-- Rig requis au minimum
	check(#ManualRig.REQUIRED_CORE == 3, "3 collisions critiques")

	-- Portail jamais utilisé comme spawn
	check(HubSpawnLogic.IsPortalName("BubbleTransitInteractionAnchor") == true, "portail détecté")
	check(
		HubSpawnLogic.PortalMustNotBeSpawn("HubSpawnLocation", "BubbleTransitInteractionAnchor") == true,
		"portail ≠ spawn"
	)

	if ok then
		print("[HubSpawnLogicTests] ALL PASS")
	else
		warn("[HubSpawnLogicTests] SOME FAILED")
	end
	return ok
end

return HubSpawnLogicTests
