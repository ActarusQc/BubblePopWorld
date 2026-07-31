--!strict
-- Place des props atomiques approuvés autour du BubbleBoard Summer (3+ côtés).
-- Jamais de scène composite. Edit Studio uniquement.

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ZoneDefs = require(script.Parent.ZoneDefs)
local SummerDecorConfig = require(script.Parent.SummerDecorConfig)
local SummerDecorSceneClassifier = require(script.Parent.SummerDecorSceneClassifier)
local SummerDecorAssetImporter = require(script.Parent.SummerDecorAssetImporter)
local SummerZoneEditingPreview = require(script.Parent.SummerZoneEditingPreview)

local SummerDecorGenerator = {}

local GENERATED_BY = "SummerZoneDecorationGenerator"
local BOARD_CLEARANCE = 8

function SummerDecorGenerator.AssertEditMode(): boolean
	return RunService:IsStudio() and RunService:IsEdit()
end

local function groundY(layout: any): number
	local GameConfig = require(script.Parent.GameConfig)
	return layout.Y - GameConfig.Grid.BubbleSize.Y * 0.35
end

local function categoryFolder(decor: Folder, category: string): Folder
	local map = {
		PalmTrees = "Nature",
		TropicalPlants = "Nature",
		Rocks = "Nature",
		Parasols = "BeachProps",
		LoungeChairs = "BeachProps",
		Surfboards = "BeachProps",
		BeachBalls = "BeachProps",
		Sandcastles = "BeachProps",
		BeachProps = "BeachProps",
		TikiLights = "Structures",
		Structures = "Structures",
		LifeguardTowers = "Structures",
		StringLightPosts = "Structures",
		StringLights = "Effects",
	}
	local folderName = map[category] or "BeachProps"
	local existing = decor:FindFirstChild(folderName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = folderName
	f.Parent = decor
	return f
end

local function clearGenerated(decor: Folder)
	local kill: { Instance } = {}
	for _, d in ipairs(decor:GetDescendants()) do
		if d:GetAttribute("GeneratedBy") == GENERATED_BY then
			table.insert(kill, d)
		end
	end
	table.sort(kill, function(a, b)
		return #a:GetFullName() > #b:GetFullName()
	end)
	local seen: { [Instance]: boolean } = {}
	for _, inst in ipairs(kill) do
		local target = inst
		local walk: Instance? = inst
		while walk and walk ~= decor do
			if walk:IsA("Model") and walk:GetAttribute("GeneratedBy") == GENERATED_BY then
				target = walk
			end
			walk = walk.Parent
		end
		if not seen[target] and target.Parent then
			seen[target] = true
			target:Destroy()
		end
	end
end

-- Slots autour du board : sud, nord, est (fond) — pas sur l'entrée (ouest).
local function buildSlots(layout: any): { { pos: Vector3, yaw: number, side: string } }
	local ox, oz = layout.BoardOrigin.X, layout.BoardOrigin.Z
	local bex, bez = layout.BoardEx, layout.BoardEz
	local y = groundY(layout)
	local margin = BOARD_CLEARANCE + 4
	local slots = {}

	local function addRow(side: string, count: number, base: Vector3, along: Vector3, yaw: number)
		for i = 1, count do
			local t = (i - 0.5) / count - 0.5
			local p = base + along * (t * (if side == "east" then bez * 1.4 else bex * 1.4))
			table.insert(slots, { pos = Vector3.new(p.X, y, p.Z), yaw = yaw, side = side })
		end
	end

	-- Sud (Z-)
	addRow("south", 5, Vector3.new(ox, y, oz - bez - margin), Vector3.new(1, 0, 0), 0)
	-- Nord (Z+)
	addRow("north", 5, Vector3.new(ox, y, oz + bez + margin), Vector3.new(1, 0, 0), math.pi)
	-- Est / fond (X+)
	addRow("east", 4, Vector3.new(ox + bex + margin, y, oz), Vector3.new(0, 0, 1), -math.pi / 2)

	return slots
end

local function listPlaceableTemplates(): { Model }
	local assets = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_ASSETS)
	local out: { Model } = {}
	if not assets then
		return out
	end
	for _, child in ipairs(assets:GetDescendants()) do
		if child:IsA("Model") and child:GetAttribute("SanitizedSummerAsset") == true then
			local key = child:GetAttribute("TemplateKey")
			if type(key) == "string" and SummerDecorConfig.IsTemplateApproved(key) then
				local ok = SummerDecorSceneClassifier.ValidateForPlacement(child, child.Name)
				if ok then
					table.insert(out, child)
				end
			end
		end
	end
	return out
end

local function isLifeguard(model: Model): boolean
	local n = string.lower(model.Name)
	local cat = ""
	local sid = model:GetAttribute("SourceAssetId")
	if type(sid) == "number" then
		cat = SummerDecorConfig.GetCategoryForAssetId(sid) or ""
	end
	return string.find(n, "lifeguard", 1, true) ~= nil
		or string.find(n, "tower", 1, true) ~= nil
		or cat == "LifeguardTowers"
		or cat == "Structures"
end

function SummerDecorGenerator.Refresh(): number
	if not SummerDecorGenerator.AssertEditMode() then
		warn("[SummerDecorGenerator] Refresh uniquement en Studio Edit")
		return 0
	end

	-- Purge composites avant tout placement
	SummerDecorAssetImporter.PurgeCompositeRejected()

	local decor = SummerZoneEditingPreview.EnsureSummerZoneDecor()
	clearGenerated(decor)

	local layout = ZoneDefs.GetSummerBridgeLayout()
	local slots = buildSlots(layout)
	local templates = listPlaceableTemplates()
	local compositePlaced = 0
	local placed = 0

	if #templates == 0 then
		print("[SummerDecorGenerator] Composite templates placed: 0")
		print("[SummerDecorGenerator] No approved atomic templates in SummerDecorAssets")
		return 0
	end

	-- Séparer lifeguard (1 max, Structures) du reste
	local lifeguard: Model? = nil
	local props: { Model } = {}
	for _, t in ipairs(templates) do
		if isLifeguard(t) and not lifeguard then
			lifeguard = t
		elseif not isLifeguard(t) then
			table.insert(props, t)
		end
	end

	-- Tour de sauveteur : un seul, Structures, loin du board
	if lifeguard then
		local ok, cls = SummerDecorSceneClassifier.ValidateForPlacement(lifeguard, lifeguard.Name)
		if ok then
			local clone = lifeguard:Clone()
			local scale = 1
			local bound = cls.BoundSize
			local tallest = math.max(bound.X, bound.Y, bound.Z)
			if tallest > 18 then
				scale = 14 / tallest
			end
			if scale ~= 1 then
				pcall(function()
					clone:ScaleTo(scale)
				end)
			end
			local folder = categoryFolder(decor, "LifeguardTowers")
			-- Coin nord-est, 8+ studs du board
			local pos = Vector3.new(
				layout.BoardOrigin.X + layout.BoardEx + BOARD_CLEARANCE + 10,
				groundY(layout),
				layout.BoardOrigin.Z + layout.BoardEz * 0.35
			)
			clone:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(-120), 0))
			clone:SetAttribute("GeneratedBy", GENERATED_BY)
			clone.Parent = folder
			placed += 1
		else
			print("[SummerDecorGenerator] Lifeguard rejected:", cls.Reason)
		end
	end

	local slotIndex = 1
	for i, template in ipairs(props) do
		if slotIndex > #slots then
			break
		end
		local ok, cls = SummerDecorSceneClassifier.ValidateForPlacement(template, template.Name)
		if not ok then
			if cls.IsCompositeScene then
				compositePlaced += 1
			end
			continue
		end
		local slot = slots[slotIndex]
		slotIndex += 1
		local clone = template:Clone()
		local sid = template:GetAttribute("SourceAssetId")
		local cat = if type(sid) == "number" then SummerDecorConfig.GetCategoryForAssetId(sid) else nil
		local folder = categoryFolder(decor, cat or "BeachProps")
		clone:PivotTo(CFrame.new(slot.pos) * CFrame.Angles(0, slot.yaw + (i % 3) * 0.2, 0))
		clone:SetAttribute("GeneratedBy", GENERATED_BY)
		clone.Parent = folder
		placed += 1
	end

	print(("[SummerDecorGenerator] Composite templates placed: %d"):format(compositePlaced))
	print(("[SummerDecorGenerator] Atomic props placed: %d (sides used: south/north/east)"):format(placed))
	return placed
end

SummerDecorGenerator.GENERATED_BY = GENERATED_BY

return SummerDecorGenerator
