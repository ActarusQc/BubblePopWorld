--!strict
-- Rojo sync marker: elevator placement and collision fixes (2026-08-18)
-- Fondation additive du parc. Ne détruit et ne modifie jamais les modèles importés
-- autrement que leur position temporaire pendant l'exécution du jeu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.AmusementParkConfig)

local CollisionLogic = require(Shared.AmusementParkCollisionLogic)
local CoasterLogic = require(Shared.AmusementParkCoasterLogic)
local WorldTourLogic = require(Shared.WorldTourLogic)
local ZoneDefs = require(Shared.ZoneDefs)
local ChestAppearance = require(Shared.ChestAppearance)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)
local TentChestConfig = require(Shared.TentChestConfig)
local TentChestLogic = require(Shared.TentChestLogic)

local Builder = {}
local CODE_VERSION = "park-builder-2026-09-05-v50"

local C = {
	Navy = Color3.fromRGB(20, 48, 92),
	Blue = Color3.fromRGB(34, 132, 220),
	Cyan = Color3.fromRGB(68, 220, 245),
	Red = Color3.fromRGB(235, 69, 78),
	Yellow = Color3.fromRGB(255, 205, 62),
	Purple = Color3.fromRGB(145, 76, 225),
	Mint = Color3.fromRGB(80, 211, 155),
	Cream = Color3.fromRGB(248, 236, 197),
	Ground = Color3.fromRGB(69, 174, 111),
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	p:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function railing(parent: Instance, a: Vector3, b: Vector3)
	local delta = b - a
	local middle = (a + b) / 2
	local length = delta.Magnitude
	local cf = CFrame.lookAt(middle, b)
	part(parent, "RailingTop", Vector3.new(0.45, 0.45, length), cf, C.Navy, Enum.Material.Metal)
	for alpha = 0, 1, 0.25 do
		local pos = a:Lerp(b, alpha)
		part(parent, "RailingPost", Vector3.new(0.42, 4, 0.42), CFrame.new(pos - Vector3.new(0, 2, 0)), C.Navy, Enum.Material.Metal)
	end
end

local function stairs(parent: Instance, name: string, bottom: Vector3, direction: Vector3, width: number, rise: number, steps: number)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	folder.Parent = parent
	local dir = direction.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local run = steps * 2.25
	for i = 1, steps do
		local y = rise * i / steps
		local pos = bottom + dir * (run * (i - 0.5) / steps) + Vector3.new(0, y / 2, 0)
		local cf = CFrame.fromMatrix(pos, right, Vector3.yAxis, -dir)
		part(folder, "Step", Vector3.new(width, y, 2.35), cf, if i % 2 == 0 then C.Blue else C.Cyan)
	end
	local top = bottom + dir * run + Vector3.new(0, rise + 3.2, 0)
	local leftA = bottom - right * (width / 2 + 0.3) + Vector3.new(0, 3.2, 0)
	local leftB = top - right * (width / 2 + 0.3)
	local rightA = bottom + right * (width / 2 + 0.3) + Vector3.new(0, 3.2, 0)
	local rightB = top + right * (width / 2 + 0.3)
	railing(folder, leftA, leftB)
	railing(folder, rightA, rightB)
end

local function platform(parent: Instance, name: string, center: Vector3, size: Vector3, color: Color3)
	part(parent, name, size, CFrame.new(center), color)
	local groundTop = Config.Origin.Y
	local bottom = center.Y - size.Y / 2
	local supportHeight = bottom - groundTop
	if supportHeight > 3 then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				-- Le chapiteau se trouve devant le côté est de la plateforme haute.
				-- Ces deux poteaux coupaient directement son entrée.
				if name == "HighPlatform" and sx == 1 then continue end
				local x = center.X + sx * math.max(2, size.X / 2 - 4)
				local z = center.Z + sz * math.max(2, size.Z / 2 - 4)
				part(parent, name .. "Support", Vector3.new(2.4, supportHeight, 2.4), CFrame.new(x, groundTop + supportHeight / 2, z), C.Navy, Enum.Material.Metal)
			end
		end
	end
	local y = center.Y + size.Y / 2 + 4
	local hx, hz = size.X / 2, size.Z / 2
	railing(parent, Vector3.new(center.X - hx, y, center.Z - hz), Vector3.new(center.X + hx, y, center.Z - hz))
	railing(parent, Vector3.new(center.X - hx, y, center.Z + hz), Vector3.new(center.X + hx, y, center.Z + hz))
end

local function arch(parent: Instance, center: Vector3)
	part(parent, "EntryPillar", Vector3.new(5, 18, 5), CFrame.new(center + Vector3.new(0, 9, -10)), C.Blue)
	part(parent, "EntryPillar", Vector3.new(5, 18, 5), CFrame.new(center + Vector3.new(0, 9, 10)), C.Blue)
	part(parent, "EntryHeader", Vector3.new(5, 7, 25), CFrame.new(center + Vector3.new(0, 19, 0)), C.Red)
	local sign = part(parent, "EntrySign", Vector3.new(0.5, 5.5, 20), CFrame.new(center + Vector3.new(2.7, 19, 0)), C.Yellow)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "AMUSEMENT PARK"
	label.TextColor3 = C.Navy
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = gui
end

local function partBetween(parent: Instance, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?): Part
	local delta = b - a
	return part(parent, name, Vector3.new(thickness, thickness, delta.Magnitude), CFrame.lookAt((a + b) / 2, b), color, material)
end

local function lamp(parent: Instance, position: Vector3)
	part(parent, "LampPost", Vector3.new(0.7, 8, 0.7), CFrame.new(position + Vector3.new(0, 4, 0)), C.Navy, Enum.Material.Metal)
	local bulb = part(parent, "LampBulb", Vector3.new(2.2, 2.2, 2.2), CFrame.new(position + Vector3.new(0, 8.4, 0)), C.Yellow, Enum.Material.Neon)
	bulb.Shape = Enum.PartType.Ball
	bulb.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = C.Yellow
	light.Brightness = 1.8
	light.Range = 22
	light.Parent = bulb
end

local function pennants(parent: Instance, a: Vector3, b: Vector3)
	local decor = parent:FindFirstChild("PennantDecor")
	if not decor then
		decor = Instance.new("Folder")
		decor.Name = "PennantDecor"
		decor.Parent = parent
	end
	partBetween(decor, "PennantLine", a, b, 0.12, C.Navy, Enum.Material.Metal)
	for i = 1, 9 do
		local position = a:Lerp(b, i / 10) - Vector3.new(0, 1.2, 0)
		local flag = part(decor, "Pennant", Vector3.new(1.3, 2, 0.18), CFrame.new(position), ({ C.Red, C.Yellow, C.Cyan, C.Purple })[((i - 1) % 4) + 1])
		flag.CanCollide = false
	end
end

local function carousel(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "Carousel"
	model:SetAttribute("AnimatedAttraction", "Carousel")
	model.Parent = parent
	cylinder(model, "CarouselDeck", 30, 2, CFrame.new(center + Vector3.new(0, 1, 0)), C.Purple)
	part(model, "CarouselMast", Vector3.new(2, 15, 2), CFrame.new(center + Vector3.new(0, 7.5, 0)), C.Yellow, Enum.Material.Metal)
	-- Le Chapiteau Tripo est séparé et statique; ce toit appartient au carrousel.
	local roof = cylinder(model, "CarouselRoof", 32, 1.2, CFrame.new(center + Vector3.new(0, 15.5, 0)), C.Red)
	roof.CanCollide = false
	local crown = cylinder(model, "CarouselRoofCrown", 22, 1, CFrame.new(center + Vector3.new(0, 17, 0)), C.Yellow)
	crown.CanCollide = false
	for i = 1, 8 do
		local angle = (i - 1) * math.pi / 4
		local offset = Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
		part(model, "HorsePole", Vector3.new(0.35, 11, 0.35), CFrame.new(center + offset + Vector3.new(0, 7, 0)), C.Yellow, Enum.Material.Metal)
		local horseCF = CFrame.lookAt(center + offset + Vector3.new(0, 4.5, 0), center + offset + Vector3.new(-math.sin(angle), 4.5, math.cos(angle)))
		local horseColor = ({ C.Cyan, C.Mint, C.Yellow, C.Red })[((i - 1) % 4) + 1]
		local horse = part(model, "CarouselHorseBody", Vector3.new(4.3, 2.2, 1.5), horseCF, horseColor)
		horse.Shape = Enum.PartType.Ball
		local head = part(model, "CarouselHorseHead", Vector3.new(1.5, 2.1, 1.4), horseCF * CFrame.new(0, 1.1, -1.7), horseColor)
		head.Shape = Enum.PartType.Ball
		for _, x in ipairs({ -1.25, 1.25 }) do
			for _, z in ipairs({ -0.42, 0.42 }) do
				part(model, "CarouselHorseLeg", Vector3.new(0.45, 2.6, 0.45), horseCF * CFrame.new(x, -1.6, z), horseColor)
			end
		end
		part(model, "CarouselSaddle", Vector3.new(1.8, 0.45, 1.7), horseCF * CFrame.new(0, 1.05, 0), C.Navy)
		local seat = Instance.new("Seat")
		seat.Name = "CarouselSeat"
		seat.Size = Vector3.new(2.2, 0.5, 2.2)
		seat.CFrame = horse.CFrame * CFrame.new(0, 1.65, 0)
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanTouch = false
		seat.Disabled = true
		seat.Transparency = 1
		seat.Parent = model
	end
	-- Pivot explicite au centre de l'attraction : tous les chevaux décrivent un
	-- cercle au lieu de tourner autour d'un pivot hérité de l'importation.
	model.WorldPivot = CFrame.new(center)
end

local function placeTentChests(parent: Instance, floorCF: CFrame, radius: number, entranceAngle: number)
	local folder = parent:FindFirstChild("TentChests")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "TentChests"
	folder:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	folder.Parent = parent

	for _, placement in ipairs(TentChestLogic.Placements(radius, entranceAngle)) do
		local chest = TentChestLogic.GetChest(placement.Id)
		if chest then
			local worldCF = floorCF * placement.LocalCFrame
			local pedestalTop = TentChestConfig.PedestalHeight
			local stand = cylinder(
				folder,
				"Pedestal_" .. chest.Id,
				5.2,
				pedestalTop,
				worldCF * CFrame.new(0, -TentChestConfig.ChestHeight + 0.5 + pedestalTop / 2, 0),
				C.Navy
			)
			stand.Material = Enum.Material.Marble
			stand.CanCollide = true

			local model = ChestAppearance.BuildModel({
				Id = chest.VisualId,
				Color = chest.AccentColor,
			}, worldCF * CFrame.new(0, pedestalTop, 0))
			model.Name = "TentChest_" .. chest.Id
			model:SetAttribute("TentChestId", chest.Id)
			model:SetAttribute("TentChestCost", chest.Cost)
			model.Parent = folder

			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("BasePart") and (descendant.Name == "Body" or string.sub(descendant.Name, 1, 4) == "Foot") then
					descendant.CanCollide = true
				end
			end

			local root = model.PrimaryPart
			if root then
				local billboard = Instance.new("BillboardGui")
				billboard.Name = "TentChestLabel"
				billboard.Size = UDim2.fromScale(3.4, 1.15)
				billboard.StudsOffset = Vector3.new(0, 2.55, 0)
				billboard.AlwaysOnTop = true
				billboard.MaxDistance = 32
				billboard.LightInfluence = 0
				billboard.Parent = root

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Name = "Name"
				nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
				nameLabel.BackgroundTransparency = 1
				nameLabel.TextColor3 = chest.AccentColor
				nameLabel.TextStrokeTransparency = 0.35
				nameLabel.TextScaled = true
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.Parent = billboard
				L10nUtil.localize(nameLabel, chest.Label)

				local costLabel = Instance.new("TextLabel")
				costLabel.Name = "Cost"
				costLabel.Size = UDim2.new(1, 0, 0.45, 0)
				costLabel.Position = UDim2.new(0, 0, 0.55, 0)
				costLabel.BackgroundTransparency = 1
				costLabel.TextColor3 = Color3.fromRGB(255, 236, 180)
				costLabel.TextStrokeTransparency = 0.35
				costLabel.TextScaled = true
				costLabel.Font = Enum.Font.GothamBold
				costLabel.Parent = billboard
				L10nUtil.dynamic(costLabel, "[E] " .. tostring(chest.Cost) .. " " .. L10n.CoinsUnit)

				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "OpenTentChest"
				-- Custom : pas de billboard Roblox noir. Le label [E] suffit.
				prompt.Style = Enum.ProximityPromptStyle.Custom
				prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
				prompt.ActionText = L10n.TentChestOpenFmt:format(chest.Cost)
				prompt.ObjectText = chest.Label
				prompt.HoldDuration = TentChestConfig.HoldDuration
				prompt.MaxActivationDistance = TentChestConfig.PromptDistance
				prompt.RequiresLineOfSight = false
				prompt.ClickablePrompt = true
				prompt.Enabled = true
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
				prompt:SetAttribute("TentChestId", chest.Id)
				prompt.Parent = root
			end
		end
	end
end

local function restoreTripoTentVisuals(tent: Instance)
	local function restore(value: BasePart)
		value.Transparency = 0
		value.LocalTransparencyModifier = 0
		value.CastShadow = true
		value.CanCollide = false
		value.CanTouch = false
		value.CanQuery = true
		value:SetAttribute("TentDoorwayHidden", nil)
		if value:IsA("MeshPart") then
			(value :: MeshPart).DoubleSided = true
		end
	end
	if tent:IsA("BasePart") then
		restore(tent)
	end
	for _, descendant in ipairs(tent:GetDescendants()) do
		if descendant:IsA("BasePart") then
			restore(descendant)
		end
	end
end

local function tentWorldPosition(inst: Instance): Vector3?
	if inst:IsA("Model") then
		return select(1, inst:GetBoundingBox()).Position
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

local function isChapiteau2Name(name: string): boolean
	local lower = string.lower(name)
	return string.find(lower, "chapiteau2", 1, true) ~= nil or string.find(lower, "chapiteau_2", 1, true) ~= nil
end

local function xzDistToChapiteauSlot(inst: Instance): number
	local pos = tentWorldPosition(inst)
	if not pos then
		return math.huge
	end
	local target = Config.Placements.Chapiteau.Position
	return (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude
end

local function tentBounds(inst: Instance): (CFrame, Vector3)
	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	local p = inst :: BasePart
	return p.CFrame, p.Size
end

local function archiveOldTent(tent: Instance)
	local folder = ServerStorage:FindFirstChild("ChapiteauArchive")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ChapiteauArchive"
		folder.Parent = ServerStorage
	end
	tent.Parent = folder
	print(("[AmusementParkBuilder] ancien chapiteau archivé: %s"):format(tent.Name))
end

local function snapTentOnto(moving: Instance, anchor: Instance)
	local destCF, destSize = tentBounds(anchor)
	local srcCF, srcSize = tentBounds(moving)
	local destGround = Vector3.new(destCF.Position.X, destCF.Position.Y - destSize.Y / 2, destCF.Position.Z)
	local srcGround = Vector3.new(srcCF.Position.X, srcCF.Position.Y - srcSize.Y / 2, srcCF.Position.Z)
	local delta = CFrame.new(destGround - srcGround)
	if moving:IsA("Model") then
		moving:PivotTo(delta * moving:GetPivot())
	else
		(moving :: BasePart).CFrame = delta * (moving :: BasePart).CFrame
	end
end

local function scaleTentToMatch(moving: Instance, anchor: Instance)
	local _, destSize = tentBounds(anchor)
	local _, srcSize = tentBounds(moving)
	local srcSpan = math.max(srcSize.X, srcSize.Y, srcSize.Z)
	local destSpan = math.max(destSize.X, destSize.Y, destSize.Z)
	if srcSpan < 0.05 then
		return
	end
	local factor = destSpan / srcSpan
	if math.abs(factor - 1) < 0.02 then
		return
	end
	if moving:IsA("Model") then
		moving:ScaleTo(moving:GetScale() * factor)
	else
		(moving :: BasePart).Size *= factor
	end
	print(("[AmusementParkBuilder] chapiteau2 échelle x%.3f"):format(factor))
end

local function fitTentToAnchor(moving: Instance, anchor: Instance)
	scaleTentToMatch(moving, anchor)
	snapTentOnto(moving, anchor)
end

local resolvedChapiteau: Instance? = nil
local resolvedChapiteauDone = false

local function findBestChapiteau(_root: Instance): Instance?
	if resolvedChapiteauDone then
		return resolvedChapiteau
	end
	resolvedChapiteauDone = true
	local parkNear = 80
	local park = workspace:FindFirstChild("ParcAttractions")
	local original: Instance? = nil
	local import2: Instance? = nil
	if park then
		for _, child in ipairs(park:GetChildren()) do
			if not (child:IsA("Model") or child:IsA("BasePart")) then
				continue
			end
			if child.Name == "ChapiteauInterior" then
				continue
			end
			local lower = string.lower(child.Name)
			if not string.find(lower, "chapiteau", 1, true) then
				continue
			end
			if isChapiteau2Name(child.Name) then
				import2 = child
			else
				original = child
			end
		end
	end
	local originalDist = if original then xzDistToChapiteauSlot(original) else math.huge
	local importDist = if import2 then xzDistToChapiteauSlot(import2) else math.huge
	if original and import2 and originalDist <= parkNear then
		fitTentToAnchor(import2, original)
		archiveOldTent(original)
		restoreTripoTentVisuals(import2)
		print(("[AmusementParkBuilder] chapiteau2 calé et mis à l'échelle (import était à %.0f studs)"):format(importDist))
		resolvedChapiteau = import2
		return resolvedChapiteau
	end
	if import2 and importDist <= parkNear then
		if original then
			archiveOldTent(original)
		end
		restoreTripoTentVisuals(import2)
		resolvedChapiteau = import2
		return resolvedChapiteau
	end
	if original and originalDist <= parkNear then
		restoreTripoTentVisuals(original)
		resolvedChapiteau = original
		return resolvedChapiteau
	end
	if original then
		restoreTripoTentVisuals(original)
		resolvedChapiteau = original
		return resolvedChapiteau
	end
	resolvedChapiteau = import2
	if resolvedChapiteau then
		restoreTripoTentVisuals(resolvedChapiteau)
	end
	return resolvedChapiteau
end

local function tentInterior(parent: Instance, floorCF: CFrame, radius: number, wallHeight: number, entranceAngle: number, liningVisible: boolean)
	local interior = Instance.new("Folder")
	interior.Name = "ChapiteauInterior"
	interior:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	interior.Parent = parent
	-- Parois proxy : collision seulement si le mesh Blender est déjà visible des deux côtés.
	local liningAlpha = if liningVisible then 0 else 1
	local segments = 28
	local wallRadius = radius
	for i = 0, segments - 1 do
		local angle = (i / segments) * math.pi * 2
		if CollisionLogic.IsTentDoorwayAngle(angle, entranceAngle) then continue end
		local localPosition = Vector3.new(math.cos(angle) * wallRadius, wallHeight / 2, math.sin(angle) * wallRadius)
		local panel = part(
			interior,
			"InteriorDrape",
			Vector3.new(math.max(2.8, wallRadius * 0.26), wallHeight, 0.7),
			floorCF * CFrame.new(localPosition) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			if i % 2 == 0 then C.Red else C.Yellow,
			Enum.Material.Fabric
		)
		panel.CanCollide = true
		panel.CanQuery = false
		panel.CastShadow = false
		panel.Transparency = liningAlpha
	end
	local floorPos = (floorCF * CFrame.new(0, 0.2, 0)).Position
	local floor = cylinder(
		interior,
		"InteriorFloor",
		wallRadius * 1.95,
		0.4,
		CFrame.new(floorPos),
		Color3.fromRGB(45, 110, 190)
	)
	floor.Material = Enum.Material.Fabric
	floor.CanCollide = true
	floor.CanQuery = false
	floor.CastShadow = false
	floor.Transparency = liningAlpha
	local lightHost = part(interior, "InteriorLight", Vector3.new(0.4, 0.4, 0.4), floorCF * CFrame.new(0, wallHeight * 0.55, 0), C.Yellow, Enum.Material.Neon)
	lightHost.CanCollide = false
	lightHost.CanQuery = false
	lightHost.CastShadow = false
	lightHost.Transparency = 1
	local light = Instance.new("PointLight")
	light.Brightness = 2.4
	light.Range = math.max(28, radius * 2.4)
	light.Color = Color3.fromRGB(255, 214, 170)
	light.Parent = lightHost
	placeTentChests(interior, floorCF, radius, entranceAngle)
end

local function ensureBubbleRegions(root: Instance, previewMode: boolean?)
	local regions = root:FindFirstChild("BubbleRegions")
	if not regions then
		regions = Instance.new("Folder")
		regions.Name = "BubbleRegions"
		regions.Parent = root
	end

	local defaults = {
		Ground = { Center = Vector3.new(-237, 7, -4), Size = Vector3.new(86, 0.4, 46), Rows = 7 },
		Mid = { Center = Vector3.new(-270, 18, -51), Size = Vector3.new(50, 0.4, 32), Rows = 5 },
		High = { Center = Vector3.new(-306, 30, 47), Size = Vector3.new(46, 0.4, 30), Rows = 5 },
	}
	for name, def in pairs(defaults) do
		local region = regions:FindFirstChild(name)
		if not (region and region:IsA("BasePart")) then
			region = Instance.new("Part")
			region.Name = name
			region.Anchored = true
			region.CFrame = CFrame.new(def.Center)
			region.Size = def.Size
			region.Parent = regions
		end
	end

	-- Les surfaces dupliquées dans Studio gardent le nom d'origine. Elles doivent
	-- recevoir la même finition que la première, sinon elles restent visibles en
	-- jeu et ne portent pas l'attribut qui les identifie.
	for _, region in ipairs(regions:GetChildren()) do
		if region:IsA("BasePart") then
			for name, def in pairs(defaults) do
				if ZoneDefs.MatchesBubbleRegionFamily(region.Name, name) then
					region.Anchored = true
					region.CanCollide = false
					region.CanTouch = false
					region.CanQuery = false
					region.Material = Enum.Material.ForceField
					region.Color = if name == "Ground" then C.Yellow elseif name == "Mid" then C.Purple else C.Cyan
					region.Transparency = if previewMode then 0.55 else 1
					region:SetAttribute("BubbleRegion", true)
					region:SetAttribute("Rows", def.Rows)
					break
				end
			end
		end
	end
end

local function findCoasterElevatorSource(generated: Instance): Instance?
	local root = generated.Parent
	if not root then
		return nil
	end
	for _, name in ipairs({ "Ascenseur_Commun", "AscenseurCommun", "ascenseur_commun", "Ascenseur-Commun" }) do
		local found = root:FindFirstChild(name, true)
		if found and not found:IsDescendantOf(generated) and (found:IsA("Model") or found:IsA("BasePart")) then
			return found
		end
	end
	return nil
end

local function tourStopAccess(parent: Instance, stop: WorldTourLogic.StopSpec, groundY: number)
	if stop.ZoneId == "AmusementPark" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "TourStop_" .. stop.ZoneId
	folder:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	folder:SetAttribute("TourZoneId", stop.ZoneId)
	folder.Parent = parent
	local pos = stop.Position
	local deckY = pos.Y - 1.2
	local zoneOrigin = ZoneDefs.GetZoneOrigin(stop.ZoneId)
	local towardZone = Vector3.new(zoneOrigin.X - pos.X, 0, zoneOrigin.Z - pos.Z)
	if towardZone.Magnitude < 0.1 then
		towardZone = Vector3.new(0, 0, 1)
	else
		towardZone = towardZone.Unit
	end
	if math.abs(towardZone.X) >= math.abs(towardZone.Z) then
		towardZone = Vector3.new(if towardZone.X >= 0 then 1 else -1, 0, 0)
	else
		towardZone = Vector3.new(0, 0, if towardZone.Z >= 0 then 1 else -1)
	end
	part(folder, "TourDeck", Vector3.new(16, 0.8, 12), CFrame.lookAt(Vector3.new(pos.X, deckY, pos.Z), Vector3.new(pos.X, deckY, pos.Z) - towardZone), C.Cyan)
	local shaftH = math.max(8, deckY - groundY - 0.4)
	local shaftXZ = Vector3.new(pos.X, 0, pos.Z) + towardZone * 7
	local source = findCoasterElevatorSource(parent)
	local usedImported = source ~= nil
	if not usedImported then
		part(folder, "TourElevatorPost", Vector3.new(0.7, shaftH, 0.7), CFrame.new(shaftXZ.X, groundY + shaftH / 2, shaftXZ.Z), C.Navy, Enum.Material.Metal)
		local glass = part(folder, "TourElevatorGlass", Vector3.new(5.2, shaftH - 1.2, 5.2), CFrame.new(shaftXZ.X, groundY + shaftH / 2, shaftXZ.Z), C.Cyan, Enum.Material.Glass)
		glass.Transparency = 0.62
		glass.CanCollide = false
	end
	local padSize = if usedImported then 6 else 5.2
	local groundPad = part(folder, "TourElevatorGround_" .. stop.ZoneId, Vector3.new(padSize, 0.6, padSize), CFrame.new(shaftXZ.X, groundY + 0.35, shaftXZ.Z), C.Yellow)
	groundPad.Transparency = if usedImported then 1 else 0
	groundPad:SetAttribute("TourElevatorPair", stop.ZoneId)
	groundPad:SetAttribute("TourElevatorRole", "Ground")
	local highPad = part(folder, "TourElevatorHigh_" .. stop.ZoneId, Vector3.new(padSize, 0.7, padSize), CFrame.new(pos.X, deckY, pos.Z), C.Yellow)
	highPad.Transparency = if usedImported then 1 else 0
	highPad:SetAttribute("TourElevatorPair", stop.ZoneId)
	highPad:SetAttribute("TourElevatorRole", "High")
	local boarding = part(folder, "TourStation_" .. stop.ZoneId, Vector3.new(12, 7, 12), CFrame.new(pos.X, pos.Y + 2, pos.Z), C.Yellow)
	boarding.Transparency = 1
	boarding.CanCollide = false
	boarding.CanQuery = true
	boarding:SetAttribute("TourZoneId", stop.ZoneId)
	boarding:SetAttribute("TourDisplayName", stop.DisplayName)
	local landPos = WorldTourLogic.GroundLanding(stop.ZoneId, groundY)
	local landing = part(
		folder,
		"TourLanding_" .. stop.ZoneId,
		Vector3.new(28, 2, 28),
		CFrame.new(landPos.X, landPos.Y - 3.4, landPos.Z),
		C.Yellow
	)
	landing.CanCollide = true
	landing:SetAttribute("TourZoneId", stop.ZoneId)
	if usedImported and source then
		local imported = source:Clone()
		imported.Name = "TourAscenseur_" .. stop.ZoneId
		imported:SetAttribute("GeneratedBy", "AmusementParkBuilder")
		imported:SetAttribute("TourElevatorClone", true)
		imported.Parent = folder
		if imported:IsA("BasePart") then
			imported.Anchored = true
		end
		for _, d in ipairs(imported:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = true
				d.CanQuery = true
			end
		end
		local floorY = deckY + 0.35
		local rise = math.max(12, floorY - groundY)
		local needH = rise / 0.62
		local currentSize: Vector3
		if imported:IsA("Model") then
			currentSize = select(2, imported:GetBoundingBox())
		else
			currentSize = (imported :: BasePart).Size
		end
		if currentSize.Y > 0.05 and math.abs(currentSize.Y - needH) / needH > 0.08 then
			if imported:IsA("Model") then
				imported:ScaleTo(imported:GetScale() * (needH / currentSize.Y))
			else
				(imported :: BasePart).Size *= needH / currentSize.Y
			end
		end
		local face = CFrame.lookAt(Vector3.new(shaftXZ.X, 0, shaftXZ.Z), Vector3.new(shaftXZ.X, 0, shaftXZ.Z) + towardZone)
		local sizeAfter: Vector3
		if imported:IsA("Model") then
			sizeAfter = select(2, imported:GetBoundingBox())
		else
			sizeAfter = (imported :: BasePart).Size
		end
		local depth = if math.abs(towardZone.X) >= math.abs(towardZone.Z) then sizeAfter.X else sizeAfter.Z
		local centerXZ = shaftXZ + towardZone * (depth * 0.5 + 0.5)
		local desired = CFrame.new(centerXZ.X, groundY + sizeAfter.Y / 2, centerXZ.Z) * face.Rotation
		if imported:IsA("Model") then
			local boxCF = select(1, imported:GetBoundingBox())
			imported:PivotTo(desired * boxCF:Inverse() * imported:GetPivot())
		else
			(imported :: BasePart).CFrame = desired
		end
		groundPad.CFrame = CFrame.new(centerXZ.X, groundY + 0.35, centerXZ.Z) * face.Rotation
		highPad.CFrame = CFrame.new(pos.X, deckY, pos.Z)
	end
	local sign = part(folder, "TourSign", Vector3.new(10, 3.2, 0.5), CFrame.new(pos.X, pos.Y + 5, pos.Z - 6), C.Yellow)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = stop.DisplayName
	label.TextColor3 = C.Navy
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = gui
end

local function coaster(parent: Instance, stationPoint: Vector3?, _stationForward: Vector3?)
	local model = Instance.new("Folder")
	model.Name = "RollerCoaster"
	model:SetAttribute("AnimatedAttraction", "RollerCoaster")
	model.Parent = parent
	local nodes = Instance.new("Folder")
	nodes.Name = "CoasterNodes"
	nodes.Parent = model
	local trackStart = stationPoint or Vector3.new(-193, 12, 30)
	local points: { Vector3 } = {}
	local islands: { WorldTourLogic.Island } = {}
	local stops: { WorldTourLogic.StopSpec } = {}
	points, islands, stops = WorldTourLogic.BuildRidePoints(trackStart, WorldTourLogic.RideOptionsFromConfig(trackStart.Y))
	if not WorldTourLogic.ReachesOtherZones(points) then
		warn("[AmusementParkBuilder] tracé trop court, rectangle mondial forcé")
		islands = WorldTourLogic.CollectIslands(trackStart.X, 6, 16)
		local corners = WorldTourLogic.BuildOutlineCorners(islands, 16)
		points = WorldTourLogic.RoundOutline(corners, 22, Config.Coaster.CornerSamples, trackStart.Y)
		points = WorldTourLogic.SubdivideStraights(points, 36)
		points = WorldTourLogic.RotateToStation(points, trackStart)
		if #islands > 0 then
			points = WorldTourLogic.SpliceSouthLoop(points, islands[1], Config.Coaster.LoopRadius, Config.Coaster.LoopSamples)
		end
		stops = WorldTourLogic.BuildStops(points, islands, trackStart)
	end
	local minX, maxX, minZ, maxZ = WorldTourLogic.PathExtents(points)
	print(("[AmusementParkBuilder] rails world tour: %d pts, %d arrêts, X[%.0f..%.0f] Z[%.0f..%.0f]"):format(
		#points,
		#stops,
		minX,
		maxX,
		minZ,
		maxZ
	))
	local cframes = CoasterLogic.OrientPath(points)
	for i, cf in ipairs(cframes) do
		local node = part(nodes, string.format("Node%04d", i), Vector3.one, cf, C.Cyan)
		node.Transparency = 1
		node.CanCollide = false
		node.CanQuery = false
	end
	for i, cf in ipairs(cframes) do
		local nextCf = cframes[(i % #cframes) + 1]
		local delta = nextCf.Position - cf.Position
		if delta.Magnitude < 0.4 then
			continue
		end
		local side = cf.RightVector * 2.3
		partBetween(model, "TrackLeft", cf.Position + side, nextCf.Position + nextCf.RightVector * 2.3, 0.75, C.Red, Enum.Material.Metal)
		partBetween(model, "TrackRight", cf.Position - side, nextCf.Position - nextCf.RightVector * 2.3, 0.75, C.Yellow, Enum.Material.Metal)
		partBetween(model, "TrackTie", cf.Position - side, cf.Position + side, 0.42, C.Navy, Enum.Material.Metal)
		local blocksMainEntrance = cf.Position.X > -200 and math.abs(cf.Position.Z) < 20
		local inLoop = cf.UpVector.Y < 0.5
		if i % 8 == 0 and not blocksMainEntrance and not inLoop and WorldTourLogic.ShouldPlaceSupport(cf.Position, islands) then
			partBetween(model, "TrackSupport", Vector3.new(cf.Position.X, Config.Origin.Y, cf.Position.Z), cf.Position, 1.1, C.Navy, Enum.Material.Metal)
		end
		if i % 25 == 0 then
			task.wait()
		end
	end
	local parkBoarding = parent:FindFirstChild("CoasterBoarding", true)
	if parkBoarding and parkBoarding:IsA("BasePart") then
		parkBoarding:SetAttribute("TourZoneId", "AmusementPark")
		parkBoarding:SetAttribute("TourDisplayName", Config.DisplayName)
	end
	for _, stop in ipairs(stops) do
		if stop.ZoneId == "AmusementPark" then
			continue
		end
		local near = false
		for _, island in ipairs(islands) do
			if island.ZoneId == stop.ZoneId then
				local dx = math.max(island.MinX - stop.Position.X, 0, stop.Position.X - island.MaxX)
				local dz = math.max(island.MinZ - stop.Position.Z, 0, stop.Position.Z - island.MaxZ)
				near = (dx * dx + dz * dz) < (72 * 72)
				break
			end
		end
		if near then
			tourStopAccess(parent, stop, Config.Origin.Y)
		end
	end
end

local function attractionSign(parent: Instance, text: string, position: Vector3, color: Color3)
	local sign = part(parent, "AttractionSign", Vector3.new(10, 4, 0.6), CFrame.new(position), color)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.35
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = gui
end

local function bubbleBlasterKiosk(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "BubbleBlasterKiosk"
	model:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	model:SetAttribute("StudioMovableGroup", true)
	model.Parent = parent
	model:SetAttribute("ParkAttraction", "BubbleBlaster")

	part(model, "KioskFloor", Vector3.new(22, 1, 14), CFrame.new(center + Vector3.new(0, 0.5, 0)), C.Navy)
	part(model, "BackWall", Vector3.new(20, 13, 1), CFrame.new(center + Vector3.new(0, 7, -6)), C.Blue)
	part(model, "Counter", Vector3.new(21, 3.4, 3), CFrame.new(center + Vector3.new(0, 2.2, 4.6)), C.Red)
	part(model, "CounterTop", Vector3.new(22, 0.7, 4), CFrame.new(center + Vector3.new(0, 4.1, 4.6)), C.Yellow)

	for i = -3, 3 do
		local stripeColor = if i % 2 == 0 then C.Red else C.Cream
		part(model, "AwningStripe", Vector3.new(3.1, 0.8, 15), CFrame.new(center + Vector3.new(i * 3.05, 14, 0)), stripeColor)
	end
	part(model, "AwningTrim", Vector3.new(22, 1.2, 1), CFrame.new(center + Vector3.new(0, 13.6, 6.7)), C.Yellow)

	local sign = part(model, "BubbleBlasterSign", Vector3.new(18, 5, 0.8), CFrame.new(center + Vector3.new(0, 17, -5.2)), C.Red)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.PixelsPerStud = 35
	signGui.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Text = "BUBBLE BLASTER"
	signText.TextColor3 = C.Yellow
	signText.TextStrokeColor3 = C.Navy
	signText.TextStrokeTransparency = 0.15
	signText.Font = Enum.Font.GothamBlack
	signText.TextScaled = true
	signText.Parent = signGui

	for i, color in ipairs({ C.Cyan, C.Purple, C.Yellow, C.Red, C.Mint }) do
		local balloon = part(model, "PrizeBalloon", Vector3.new(2.1, 2.1, 2.1), CFrame.new(center + Vector3.new(-7.5 + (i - 1) * 3.7, 9.5 + (i % 2), -5.2)), color, Enum.Material.Neon)
		balloon.Shape = Enum.PartType.Ball
		balloon.CanCollide = false
	end

	local interaction = part(model, "BubbleBlasterInteraction", Vector3.new(8, 6, 2), CFrame.new(center + Vector3.new(0, 6.5, 3.2)), C.Cyan)
	interaction.Transparency = 1
	interaction.CanCollide = false
	interaction:SetAttribute("BubbleBlasterPrompt", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlayBubbleBlaster"
	prompt.ActionText = "Play"
	prompt.ObjectText = "Bubble Blaster"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = interaction
end

local function faceLabel(target: BasePart, face: Enum.NormalId, text: string, textColor: Color3, font: Enum.Font, pixels: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels or 30
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0.35
	label.Font = font
	label.TextScaled = true
	label.Parent = gui
	return label
end

local function rollABallKiosk(parent: Instance, center: Vector3)
	local model = Instance.new("Model")
	model.Name = "RollABallKiosk"
	model:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	model:SetAttribute("StudioMovableGroup", true)
	model.Parent = parent
	model:SetAttribute("ParkAttraction", "RollABall")

	local wood = Color3.fromRGB(232, 208, 148)
	local railBlue = Color3.fromRGB(28, 110, 200)
	local cabinetBlue = Color3.fromRGB(22, 86, 168)

	part(model, "CabinetBase", Vector3.new(12, 2.4, 20), CFrame.new(center + Vector3.new(0, 1.2, 0)), cabinetBlue)
	local frontPanel = part(model, "FrontPanel", Vector3.new(11.4, 5.2, 0.7), CFrame.new(center + Vector3.new(0, 4.6, 9.6)), C.Blue)
	faceLabel(frontPanel, Enum.NormalId.Back, "★", C.Yellow, Enum.Font.GothamBlack, 40)

	part(model, "StarBurst", Vector3.new(2.4, 2.4, 0.4), CFrame.new(center + Vector3.new(0, 4.7, 10.05)) * CFrame.Angles(0, 0, math.rad(45)), C.Yellow)
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "SpeedLine", Vector3.new(2.8, 0.35, 0.25), CFrame.new(center + Vector3.new(sx * 3.4, 5.1, 10.0)), Color3.new(1, 1, 1))
		part(model, "SpeedLine", Vector3.new(2.2, 0.28, 0.25), CFrame.new(center + Vector3.new(sx * 3.6, 4.3, 10.0)), C.Red)
		part(model, "CornerStar", Vector3.new(0.7, 0.7, 0.25), CFrame.new(center + Vector3.new(sx * 4.6, 6.4, 10.0)), C.Yellow)
	end

	part(model, "RampBed", Vector3.new(8.2, 0.45, 14.5), CFrame.new(center + Vector3.new(0, 3.05, 1.2)), wood, Enum.Material.Wood)
	for i = 1, 7 do
		local t = i / 7
		local z = 8.2 - t * 13.4
		local y = 3.15 + (t * t) * 4.8
		part(model, "RampStep", Vector3.new(8.0, 0.32, 2.05), CFrame.new(center + Vector3.new(0, y, z)) * CFrame.Angles(math.rad(-8 - t * 28), 0, 0), wood, Enum.Material.Wood)
	end

	part(model, "LeftRail", Vector3.new(0.7, 1.15, 16), CFrame.new(center + Vector3.new(-4.35, 3.7, 0.6)), railBlue)
	part(model, "RightRail", Vector3.new(0.7, 1.15, 16), CFrame.new(center + Vector3.new(4.35, 3.7, 0.6)), railBlue)
	part(model, "LeftRailCap", Vector3.new(0.35, 0.28, 16.2), CFrame.new(center + Vector3.new(-4.35, 4.35, 0.6)), C.Yellow)
	part(model, "RightRailCap", Vector3.new(0.35, 0.28, 16.2), CFrame.new(center + Vector3.new(4.35, 4.35, 0.6)), C.Yellow)

	part(model, "TargetBoard", Vector3.new(9.4, 10.5, 0.7), CFrame.new(center + Vector3.new(0, 9.4, -7.15)), C.Red)
	for i = 0, 6 do
		local stripe = if i % 2 == 0 then Color3.new(1, 1, 1) else C.Red
		part(model, "TargetStripe", Vector3.new(0.55, 10.5, 0.12), CFrame.new(center + Vector3.new(-4.2 + i * 1.4, 9.4, -7.52)), stripe)
	end

	local rings = {
		{ pts = 10, y = 5.4, z = -5.4, d = 4.3 },
		{ pts = 20, y = 7.0, z = -6.0, d = 3.3 },
		{ pts = 30, y = 8.4, z = -6.45, d = 2.55 },
		{ pts = 40, y = 9.65, z = -6.85, d = 2.0 },
		{ pts = 50, y = 10.8, z = -7.15, d = 1.45 },
	}
	for _, ring in ipairs(rings) do
		local cf = CFrame.new(center + Vector3.new(0, ring.y, ring.z)) * CFrame.Angles(0, math.rad(90), 0)
		local hoop = cylinder(model, "Ring" .. ring.pts, ring.d, 0.32, cf, Color3.new(1, 1, 1))
		hoop.Material = Enum.Material.SmoothPlastic
		cylinder(model, "RingHole" .. ring.pts, ring.d * 0.72, 0.18, cf * CFrame.new(0.12, 0, 0), C.Red)
		local number = part(model, "RingLabel" .. ring.pts, Vector3.new(ring.d * 0.5, ring.d * 0.42, 0.12), CFrame.new(center + Vector3.new(0, ring.y, ring.z + 0.22)), C.Red)
		number.CanCollide = false
		faceLabel(number, Enum.NormalId.Back, tostring(ring.pts), Color3.new(1, 1, 1), Enum.Font.GothamBlack, 50)
	end

	part(model, "Marquee", Vector3.new(12.4, 4.4, 1.1), CFrame.new(center + Vector3.new(0, 15.4, -7.3)), C.Blue)
	local title = part(model, "MarqueeTitle", Vector3.new(7.6, 2.2, 0.3), CFrame.new(center + Vector3.new(0, 16.05, -6.7)), C.Blue)
	faceLabel(title, Enum.NormalId.Back, "ROLL-A-BALL", C.Yellow, Enum.Font.GothamBlack, 45)
	local led = part(model, "ScoreLed", Vector3.new(3.2, 1.5, 0.3), CFrame.new(center + Vector3.new(0, 14.55, -6.7)), Color3.fromRGB(40, 8, 12), Enum.Material.Neon)
	faceLabel(led, Enum.NormalId.Back, "000", Color3.fromRGB(255, 70, 70), Enum.Font.GothamBlack, 40)
	for i = -4, 4 do
		local bulb = part(model, "MarqueeBulb", Vector3.new(0.7, 0.7, 0.7), CFrame.new(center + Vector3.new(i * 1.35, 17.85, -7.15)), C.Yellow, Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
		bulb.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = C.Yellow
		light.Brightness = 0.6
		light.Range = 8
		light.Parent = bulb
	end

	part(model, "BallTray", Vector3.new(2.6, 0.45, 6.2), CFrame.new(center + Vector3.new(5.7, 3.35, 5.6)), C.Navy)
	for i = 1, 3 do
		local ball = part(model, "PlayBall", Vector3.new(1.15, 1.15, 1.15), CFrame.new(center + Vector3.new(5.7, 4.05, 3.7 + (i - 1) * 1.7)), Color3.fromRGB(236, 196, 92), Enum.Material.SmoothPlastic)
		ball.Shape = Enum.PartType.Ball
	end

	for _, side in ipairs({ -1, 1 }) do
		part(model, "SidePost", Vector3.new(0.28, 12.5, 0.28), CFrame.new(center + Vector3.new(side * 5.9, 8.4, -6.6)), Color3.fromRGB(160, 170, 180), Enum.Material.Metal)
		part(model, "SidePost", Vector3.new(0.28, 8.5, 0.28), CFrame.new(center + Vector3.new(side * 5.9, 6.4, 8.4)), Color3.fromRGB(160, 170, 180), Enum.Material.Metal)
		partBetween(model, "SideBar", center + Vector3.new(side * 5.9, 14.4, -6.6), center + Vector3.new(side * 5.9, 10.4, 8.4), 0.18, Color3.fromRGB(160, 170, 180), Enum.Material.Metal)
	end

	local interaction = part(model, "RollABallInteraction", Vector3.new(8, 6, 2.4), CFrame.new(center + Vector3.new(0, 5.2, 11.2)), C.Cyan)
	interaction.Transparency = 1
	interaction.CanCollide = false
	interaction.CanTouch = false
	interaction.CanQuery = true
	interaction:SetAttribute("RollABallPrompt", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlayRollABall"
	prompt.ActionText = "Play"
	prompt.ObjectText = "Roll-A-Ball"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = interaction
end

local ALIASES = {
	GrandeRoue = { "GrandeRoue", "granderoue" },
	Chapiteau = { "Chapiteau2", "chapiteau2", "Chapiteau", "chapiteau" },
	StationEmbarquement = { "StationEmbarquement", "embarquement" },
	EntreeParc = { "EntreeParc", "entree-parc" },
	KiosqueBonbons = { "KiosqueBonbons", "kiosquebonbons" },
	Carousel = { "Caroussel", "Carousel", "caroussel", "carousel", "Carrousel", "carrousel", "Manege", "Manège" },
	Ascenceur = { "Ascenceur", "Ascenseur", "ascenceur", "ascenseur", "Elevator" },
	AscenseurCommun = { "Ascenseur_Commun", "AscenseurCommun", "ascenseur_commun", "Ascenseur-Commun" },
	WagonModele = { "WagonModele", "Wagon", "wagon", "TrainCar", "RollerCoasterCar" },
	BubbleBlaster = { "BubbleBlaster", "bubbleblaster", "Bubble Blaster" },
	RollABall = { "roll_a_ball", "Roll_A_Ball", "RollABall", "rollaball", "Roll-A-Ball", "Roll A Ball" },
}

local function normalizeAssetName(name: string): string
	return string.lower((string.gsub(name, "[^%a%d]", "")))
end

local function isGeneratedRollABall(inst: Instance): boolean
	if inst:GetAttribute("GeneratedBy") == "AmusementParkBuilder" then
		return true
	end
	local n = normalizeAssetName(inst.Name)
	return n == "rollaballkiosk" or n == "rollaballgameplay" or n == "rollaballinteraction"
end

local function nameLooksLikeRollABall(name: string): boolean
	local n = normalizeAssetName(name)
	if n == "rollaball" then
		return true
	end
	if string.find(n, "rollaball", 1, true) == nil then
		return false
	end
	return string.find(n, "kiosk", 1, true) == nil
		and string.find(n, "gameplay", 1, true) == nil
		and string.find(n, "interaction", 1, true) == nil
		and string.find(n, "prompt", 1, true) == nil
end

local function promoteImportRoot(inst: Instance): Instance
	local current = inst
	while current.Parent
		and current.Parent ~= workspace
		and current.Parent.Name ~= "ParcAttractions"
		and current.Parent.Name ~= Config.GeneratedFolderName
		and (current.Parent:IsA("Model") or current.Parent:IsA("Folder"))
		and current.Parent:GetAttribute("GeneratedBy") ~= "AmusementParkBuilder"
	do
		local parent = current.Parent
		if nameLooksLikeRollABall(parent.Name) or #parent:GetChildren() <= 6 then
			current = parent
		else
			break
		end
	end
	return current
end

local function scanRollABall(container: Instance?): Instance?
	if not container then
		return nil
	end
	if (container:IsA("Model") or container:IsA("BasePart") or container:IsA("Folder"))
		and nameLooksLikeRollABall(container.Name)
		and not isGeneratedRollABall(container)
	then
		return promoteImportRoot(container)
	end
	for _, descendant in ipairs(container:GetDescendants()) do
		if (descendant:IsA("Model") or descendant:IsA("BasePart") or descendant:IsA("Folder"))
			and nameLooksLikeRollABall(descendant.Name)
			and not isGeneratedRollABall(descendant)
		then
			return promoteImportRoot(descendant)
		end
	end
	return nil
end

local function findAlias(root: Instance, names: { string }): Instance?
	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found then return found end
		-- Tripo importe souvent le modèle directement dans Workspace. Accepter cet
		-- emplacement évite d'obliger le créateur à le déplacer avant chaque test.
		if root ~= workspace then
			found = workspace:FindFirstChild(name, true)
			if found then return found end
		end
	end
	return nil
end

local function findRollABallSource(root: Instance): Instance?
	local direct = root:FindFirstChild("roll_a_ball", true)
		or (root ~= workspace and workspace:FindFirstChild("roll_a_ball", true))
		or ServerStorage:FindFirstChild("roll_a_ball", true)
		or ReplicatedStorage:FindFirstChild("roll_a_ball", true)
	local found = direct or scanRollABall(root) or scanRollABall(workspace) or scanRollABall(ServerStorage) or scanRollABall(ReplicatedStorage)
	if not found then
		print("[AmusementParkBuilder] roll_a_ball introuvable — kiosque généré conservé")
		return nil
	end
	if isGeneratedRollABall(found) then
		print("[AmusementParkBuilder] roll_a_ball ignoré (kiosque généré)")
		return nil
	end
	if not found:IsDescendantOf(workspace) then
		local park = workspace:FindFirstChild("ParcAttractions") or root
		local clone = found:Clone()
		clone.Name = if clone.Name ~= "" then clone.Name else "roll_a_ball"
		clone.Parent = park
		found = clone
		print(("[AmusementParkBuilder] roll_a_ball cloné dans le parc depuis %s"):format(clone:GetFullName()))
	end
	print(("[AmusementParkBuilder] roll_a_ball détecté: %s"):format(found:GetFullName()))
	if found:IsA("Folder") then
		local nested = found:FindFirstChildWhichIsA("Model", true) or found:FindFirstChildWhichIsA("BasePart", true)
		if nested then
			found = promoteImportRoot(nested)
			print(("[AmusementParkBuilder] roll_a_ball mesh: %s"):format(found:GetFullName()))
		end
	end
	return found
end

local function destroyGeneratedRollABallKiosk(root: Instance)
	local removed = 0
	local stale = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == "RollABallKiosk"
			or (descendant:GetAttribute("ParkAttraction") == "RollABall" and descendant:GetAttribute("GeneratedBy") == "AmusementParkBuilder")
		then
			table.insert(stale, descendant)
		end
	end
	for _, inst in ipairs(stale) do
		removed += 1
		inst:Destroy()
	end
	if removed > 0 then
		print(("[AmusementParkBuilder] ancien kiosque Roll-A-Ball retiré (%d)"):format(removed))
	end
end

local function movableModel(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	model:SetAttribute("StudioMovableGroup", true)
	model.Parent = parent
	return model
end

local function guessStationDeckY(station: Instance, boxCF: CFrame, boxSize: Vector3): number
	local baseY = boxCF.Position.Y - boxSize.Y / 2
	local maxY = boxCF.Position.Y - math.min(4, boxSize.Y * 0.1)
	local best = baseY + Config.Coaster.PlatformHeightOffset
	local function consider(p: BasePart)
		if p.Size.Y > 2.8 or p.Size.X < 6 or p.Size.Z < 6 then
			return
		end
		local top = p.Position.Y + p.Size.Y * 0.5
		if top > baseY + 1 and top < maxY then
			best = math.max(best, top)
		end
	end
	if station:IsA("BasePart") then
		consider(station)
	end
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") then
			consider(d)
		end
	end
	return best
end

local function getStationTrackPose(root: Instance): (Vector3, Vector3, Vector3, number, Vector3)
	local station = findAlias(root, ALIASES.StationEmbarquement)
	if station and (station:IsA("Model") or station:IsA("BasePart")) then
		local boxCF: CFrame
		local boxSize: Vector3
		local pivot: CFrame
		if station:IsA("Model") then
			boxCF, boxSize = station:GetBoundingBox()
			pivot = station:GetPivot()
		else
			boxCF, boxSize = station.CFrame, station.Size
			pivot = station.CFrame
		end
		local forward = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
		if forward.Magnitude < 0.1 then forward = Vector3.new(0, 0, -1) end
		forward = forward.Unit
		local right = Vector3.yAxis:Cross(forward).Unit
		local baseY = boxCF.Position.Y - boxSize.Y / 2
		local trackY = baseY + Config.Coaster.TrackHeightOffset
		local floorY = guessStationDeckY(station, boxCF, boxSize)
		return Vector3.new(boxCF.Position.X, trackY, boxCF.Position.Z), forward, right, floorY, boxSize
	end
	local trackY = Config.Origin.Y + Config.Coaster.StationLift + Config.Coaster.TrackHeightOffset
	local floorY = Config.Origin.Y + Config.Coaster.StationLift + Config.Coaster.PlatformHeightOffset
	return Vector3.new(-193, trackY, 30), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), floorY, Vector3.new(16, 12, 16)
end

local function liftStationOnStilts(generated: Instance, root: Instance, previewMode: boolean?)
	if previewMode == true then return end
	local station = findAlias(root, ALIASES.StationEmbarquement)
	if not (station and (station:IsA("Model") or station:IsA("BasePart"))) then return end
	local lift = Config.Coaster.StationLift
	if station:GetAttribute("BPW_StationLifted") ~= true then
		if station:IsA("Model") then
			station:PivotTo(station:GetPivot() + Vector3.new(0, lift, 0))
		else
			(station :: BasePart).CFrame += Vector3.new(0, lift, 0)
		end
		station:SetAttribute("BPW_StationLifted", true)
	end
	local boxCF: CFrame
	local boxSize: Vector3
	if station:IsA("Model") then
		boxCF, boxSize = station:GetBoundingBox()
	else
		boxCF, boxSize = station.CFrame, station.Size
	end
	local bottomY = boxCF.Position.Y - boxSize.Y / 2
	local stiltHeight = math.max(4, bottomY - Config.Origin.Y)
	local hx, hz = math.max(3, boxSize.X / 2 - 2), math.max(3, boxSize.Z / 2 - 2)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local pos = Vector3.new(boxCF.Position.X + sx * hx, Config.Origin.Y + stiltHeight / 2, boxCF.Position.Z + sz * hz)
			part(generated, "StationStilt", Vector3.new(1.6, stiltHeight, 1.6), CFrame.new(pos), C.Navy, Enum.Material.Metal)
		end
	end
end

local function buildStationAccess(generated: Instance, root: Instance): (Vector3, Vector3)
	local stationPoint, forward, _right, floorY, boxSize = getStationTrackPose(root)
	local group = movableModel(generated, "Embarcadere")
	local towardPark = Vector3.new(Config.Origin.X - stationPoint.X, 0, Config.Origin.Z - stationPoint.Z)
	if towardPark.Magnitude < 0.1 then
		towardPark = -forward
	else
		towardPark = towardPark.Unit
	end
	if math.abs(towardPark.X) >= math.abs(towardPark.Z) then
		towardPark = Vector3.new(if towardPark.X >= 0 then 1 else -1, 0, 0)
	else
		towardPark = Vector3.new(0, 0, if towardPark.Z >= 0 then 1 else -1)
	end
	local groundY = Config.Origin.Y
	local right = Vector3.yAxis:Cross(towardPark)
	if right.Magnitude < 0.05 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end
	local edge = (boxSize.X * math.abs(towardPark.X) + boxSize.Z * math.abs(towardPark.Z)) * 0.5
	-- Un peu à gauche du centre, collé à la façade (plus de trou jusqu'au quai).
	local shaftXZ = Vector3.new(stationPoint.X, 0, stationPoint.Z) + towardPark * (edge + 1.2) + right * 6
	local importedLift = findAlias(root, ALIASES.AscenseurCommun)
	local usedImported = importedLift ~= nil and (importedLift:IsA("Model") or importedLift:IsA("BasePart"))

	if not usedImported then
		local width = 6.6
		local shaftH = math.max(8, floorY - groundY - 1.6)
		local function post(offset: Vector3)
			part(
				group,
				"CoasterElevatorPost",
				Vector3.new(0.65, shaftH, 0.65),
				CFrame.new(shaftXZ + offset + Vector3.new(0, groundY + shaftH / 2, 0)),
				C.Navy,
				Enum.Material.Metal
			)
		end
		local corner = width / 2 - 0.15
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				post(right * (sx * corner) + towardPark * (sz * corner))
			end
		end
		local glass = part(
			group,
			"CoasterElevatorGlass",
			Vector3.new(width - 1.2, shaftH - 1.4, width - 1.2),
			CFrame.new(shaftXZ.X, groundY + shaftH / 2, shaftXZ.Z),
			C.Cyan
		)
		glass.Transparency = 0.62
		glass.CanCollide = false
		glass.Material = Enum.Material.Glass
		part(group, "CoasterElevatorRoof", Vector3.new(width + 0.3, 0.5, width + 0.3), CFrame.new(shaftXZ.X, groundY + shaftH + 0.25, shaftXZ.Z), C.Yellow)
	end

	local padSize = if usedImported then 6 else 5.2
	local groundPad = part(group, "CoasterElevatorGroundPad", Vector3.new(padSize, 0.6, padSize), CFrame.new(shaftXZ.X, groundY + 0.35, shaftXZ.Z), C.Yellow)
	groundPad.Transparency = if usedImported then 1 else 0
	groundPad:SetAttribute("ElevatorDestination", "High")

	local deckCenter = shaftXZ - towardPark * (if usedImported then 7 else 5)
	local deckPos = Vector3.new(deckCenter.X, floorY - 0.35, deckCenter.Z)
	local deckLook = CFrame.lookAt(deckPos, Vector3.new(deckPos.X, deckPos.Y, deckPos.Z) - towardPark)
	local deck = part(
		group,
		"CoasterElevatorDeck",
		Vector3.new(8, 0.7, 11),
		deckLook,
		C.Cyan
	)
	local highPad = part(group, "CoasterElevatorHighPad", Vector3.new(padSize, 0.7, padSize), CFrame.new(deckPos), C.Yellow)
	highPad.Transparency = if usedImported then 1 else 0
	highPad:SetAttribute("ElevatorDestination", "Ground")
	local boarding = part(group, "CoasterBoarding", Vector3.new(10, 7, 12), CFrame.new(deckPos.X, floorY + 3, deckPos.Z), C.Yellow)
	boarding.Transparency = 1
	boarding.CanCollide = false
	boarding.CanQuery = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RideCoaster"
	prompt.ActionText = "Ride"
	prompt.ObjectText = "Sky Coaster"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.1
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = boarding

	return stationPoint, towardPark
end

local function importedTentInterior(parent: Instance, root: Instance)
	local tent = findBestChapiteau(root) or findAlias(root, ALIASES.Chapiteau)
	local floorCF: CFrame
	local radius = 14
	local wallHeight = 12
	local entranceAngle = -math.pi / 2
	local interiorParent = parent
	local liningVisible = true
	if tent and (tent:IsA("Model") or tent:IsA("BasePart")) then
		local boxCF: CFrame
		local look: Vector3
		if tent:IsA("Model") then
			boxCF = select(1, tent:GetBoundingBox())
			look = tent:GetPivot().LookVector
			interiorParent = tent
		else
			boxCF = tent.CFrame
			look = tent.CFrame.LookVector
			interiorParent = tent.Parent or parent
		end
		floorCF = CFrame.new(boxCF.Position.X, Config.Origin.Y, boxCF.Position.Z)
		local towardPark = Vector3.new(Config.Origin.X - boxCF.Position.X, 0, Config.Origin.Z - boxCF.Position.Z)
		if towardPark.Magnitude < 0.05 then
			towardPark = Vector3.new(look.X, 0, look.Z)
		end
		entranceAngle = CollisionLogic.EntranceAngleFromLocalLook(floorCF:VectorToObjectSpace(towardPark))
		restoreTripoTentVisuals(tent)
		liningVisible = not isChapiteau2Name(tent.Name)
		print(("[AmusementParkBuilder] chapiteau actif: %s pos=(%.1f, %.1f, %.1f)"):format(
			tent:GetFullName(),
			floorCF.Position.X,
			floorCF.Position.Y,
			floorCF.Position.Z
		))
	else
		local p = Config.Placements.Chapiteau.Position
		floorCF = CFrame.new(p.X, Config.Origin.Y, p.Z)
		print("[AmusementParkBuilder] chapiteau introuvable, coffres au placement config")
	end
	tentInterior(interiorParent, floorCF, radius, wallHeight, entranceAngle, liningVisible)
end

local function ensureTentGameplay(root: Instance?)
	local park = root
	if not (park and park.Parent) then
		park = workspace:FindFirstChild("ParcAttractions")
	end
	if not park then
		park = workspace
	end
	local stale = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Name == "ChapiteauInterior" then
			table.insert(stale, inst)
		end
	end
	for _, inst in ipairs(stale) do
		inst:Destroy()
	end
	importedTentInterior(park, park)
end

local function anchorAll(root: Instance)
	if root:IsA("BasePart") then root.Anchored = true end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
end

local function configureImportedCollision(root: Instance, canCollide: boolean, useDetailedMeshCollision: boolean?, doubleSided: boolean?)
	local function configure(value: Instance)
		if not value:IsA("BasePart") then return end
		value.CanCollide = canCollide
		value.CanTouch = canCollide
		value.CanQuery = true
		value.CollisionGroup = "Default"
		if value:IsA("MeshPart") and (doubleSided == true or canCollide) then
			(value :: MeshPart).DoubleSided = true
		end
		-- PreciseConvexDecomposition peut figer Studio en aperçu. Au runtime il
		-- est nécessaire : la collision Box/Hull laisse traverser les murs Tripo
		-- ou bouche les portes.
		if CollisionLogic.ShouldComputePreciseConvex(canCollide, useDetailedMeshCollision == false)
			and (value:IsA("MeshPart") or value:IsA("UnionOperation")) then
			pcall(function()
				(value :: any).CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
			end)
		end
	end
	configure(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		configure(descendant)
	end
end

local function findPermanentAlias(root: Instance, generated: Instance, names: { string }): Instance?
	-- GeneratedLayout contient aussi des copies runtime portant les memes noms.
	-- Chercher explicitement la source Studio hors de ce dossier.
	for _, name in ipairs(names) do
		local direct = root:FindFirstChild(name)
		if direct and not direct:IsDescendantOf(generated) then return direct end
	end
	for _, candidate in ipairs(root:GetDescendants()) do
		if candidate:IsDescendantOf(generated) then continue end
		for _, name in ipairs(names) do
			if candidate.Name == name then return candidate end
		end
	end
	for _, name in ipairs(names) do
		local candidate = workspace:FindFirstChild(name, true)
		if candidate and not candidate:IsDescendantOf(generated) then return candidate end
	end
	return nil
end

local function syncImportedRuntimeCollisions(root: Instance, generated: Instance)
	-- Builder.Build normalise normalement les collisions. Une disposition Studio
	-- editable saute volontairement Build pour conserver les placements; il faut
	-- donc reappliquer ici les proprietes physiques sans deplacer les modeles.
	for canonical, names in pairs(ALIASES) do
		local imported = if canonical == "Chapiteau"
			then (findBestChapiteau(root) or findPermanentAlias(root, generated, names))
			else findPermanentAlias(root, generated, names)
		if imported then
			local solid = CollisionLogic.ShouldMeshCollide(canonical)
			configureImportedCollision(
				imported,
				solid,
				true,
				CollisionLogic.NeedsInteriorDoubleSided(canonical)
			)
			if canonical == "Chapiteau" then
				restoreTripoTentVisuals(imported)
			end
			anchorAll(imported)
			local partCount = if imported:IsA("BasePart") then 1 else 0
			for _, descendant in ipairs(imported:GetDescendants()) do
				if descendant:IsA("BasePart") then partCount += 1 end
			end
			print(("[AmusementParkBuilder] collisions runtime: %s = %s (%d pièces)"):format(
				canonical,
				if solid then "solide" else "proxy contrôlé",
				partCount
			))
			if canonical == "Carousel" then
				for _, descendant in ipairs(imported:GetDescendants()) do
					if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
						descendant.Disabled = true
						descendant.CanTouch = false
						descendant.CanCollide = false
					end
				end
			end
		end
	end
end

local function scaleImportedToHeight(item: Instance, targetHeight: number?)
	if type(targetHeight) ~= "number" or targetHeight <= 0 then return end
	local size: Vector3
	if item:IsA("Model") then
		size = select(2, item:GetBoundingBox())
	elseif item:IsA("BasePart") then
		size = item.Size
	else
		return
	end
	if size.Y < 0.05 then return end
	local factor = targetHeight / size.Y
	if item:IsA("Model") then
		item:ScaleTo(item:GetScale() * factor)
	else
		item.Size *= factor
	end
end

local function importedBounds(item: Instance): (CFrame, Vector3)
	if item:IsA("Model") then return item:GetBoundingBox() end
	assert(item:IsA("BasePart"))
	return item.CFrame, item.Size
end

local function importedPivot(item: Instance): CFrame
	if item:IsA("Model") then return item:GetPivot() end
	assert(item:IsA("BasePart"))
	return item.CFrame
end

local function moveImportedBounds(item: Instance, desiredBounds: CFrame)
	local currentBounds = select(1, importedBounds(item))
	local desiredPivot = desiredBounds * currentBounds:Inverse() * importedPivot(item)
	if item:IsA("Model") then item:PivotTo(desiredPivot) else item.CFrame = desiredPivot end
end

local function placeImportedCoasterElevator(root: Instance, generated: Instance, towardPark: Vector3)
	local imported = findAlias(root, ALIASES.AscenseurCommun)
	if not imported or not (imported:IsA("Model") or imported:IsA("BasePart")) then
		return
	end
	local dock = generated:FindFirstChild("Embarcadere")
	local groundPad = dock and dock:FindFirstChild("CoasterElevatorGroundPad")
	local highPad = dock and dock:FindFirstChild("CoasterElevatorHighPad")
	if not (groundPad and groundPad:IsA("BasePart") and highPad and highPad:IsA("BasePart")) then
		return
	end
	local groundY = Config.Origin.Y
	local floorY = highPad.Position.Y + 0.35
	local connectXZ = Vector3.new(groundPad.Position.X, 0, groundPad.Position.Z)
	anchorAll(imported)
	-- Le dôme occupe le haut du mesh : on aligne le corps de cabine au quai,
	-- pas le sommet du toit.
	local rise = math.max(12, floorY - groundY)
	local needH = rise / 0.62
	local _, currentSize = importedBounds(imported)
	if currentSize.Y > 0.05 and math.abs(currentSize.Y - needH) / needH > 0.08 then
		scaleImportedToHeight(imported, needH)
	end
	local facePark = CFrame.lookAt(
		Vector3.new(connectXZ.X, 0, connectXZ.Z),
		Vector3.new(connectXZ.X, 0, connectXZ.Z) + towardPark
	)
	local _, sizeAfter = importedBounds(imported)
	local depth = if math.abs(towardPark.X) >= math.abs(towardPark.Z) then sizeAfter.X else sizeAfter.Z
	local centerXZ = connectXZ + towardPark * (depth * 0.5 + 0.5)
	moveImportedBounds(
		imported,
		CFrame.new(centerXZ.X, groundY + sizeAfter.Y / 2, centerXZ.Z) * facePark.Rotation
	)
	groundPad.CFrame = CFrame.new(centerXZ.X, groundY + 0.35, centerXZ.Z) * facePark.Rotation
	configureImportedCollision(
		imported,
		CollisionLogic.ShouldMeshCollide("AscenseurCommun"),
		true,
		CollisionLogic.NeedsInteriorDoubleSided("AscenseurCommun")
	)
	imported:SetAttribute("ParkImportedAsset", "AscenseurCommun")
	print(("[AmusementParkBuilder] modèle Tripo actif: AscenseurCommun -> %s"):format(imported:GetFullName()))
end

local function importedGroundPose(item: Instance): CFrame
	local boxCF, boxSize = importedBounds(item)
	local pivot = importedPivot(item)
	local groundPosition = Vector3.new(boxCF.Position.X, boxCF.Position.Y - boxSize.Y / 2, boxCF.Position.Z)
	return CFrame.new(groundPosition) * pivot.Rotation
end

local function elevatorInteractionCFrames(root: Instance): (CFrame, CFrame)
	local placement = Config.Placements.Ascenceur
	local elevator = findAlias(root, ALIASES.Ascenceur)
	local groundPose = CFrame.new(placement.Position) * CFrame.Angles(0, math.rad(placement.Yaw), 0)
	local automaticOutsideDistance = 10
	if elevator and (elevator:IsA("Model") or elevator:IsA("BasePart")) then
		groundPose = importedGroundPose(elevator)
		local _, boxSize = importedBounds(elevator)
		automaticOutsideDistance = math.clamp(boxSize.Z / 2 + 4, 10, 24)
	end
	local groundOffset = placement.GroundInteractionOffset or Vector3.zero
	local highOffset = placement.HighInteractionOffset or Vector3.zero
	-- Un offset nul signifie « devant la porte », pas au centre du mesh. Cela
	-- garde la commande et les destinations hors du modèle Tripo après tout
	-- déplacement ou changement d'échelle fait dans Studio.
	if groundOffset.Magnitude < 0.01 then
		groundOffset = Vector3.new(0, 0, -automaticOutsideDistance)
	end
	if highOffset.Magnitude < 0.01 then
		highOffset = Vector3.new(0, 0, -automaticOutsideDistance)
	end
	local groundPosition = (groundPose * CFrame.new(groundOffset)).Position + Vector3.new(0, 0.4, 0)
	-- Le palier supérieur du parc est 21,4 studs au-dessus du sol. Cette hauteur
	-- reste liée au modèle déplacé, sans dépendre de ses dimensions Tripo.
	local highPosition = (groundPose * CFrame.new(highOffset)).Position + Vector3.new(0, 21.4, 0)
	return CFrame.new(groundPosition) * groundPose.Rotation, CFrame.new(highPosition) * groundPose.Rotation
end

local function syncElevatorInteractionPads(generated: Instance, root: Instance)
	local ground = generated:FindFirstChild("ElevatorGroundPad")
	local high = generated:FindFirstChild("ElevatorHighPad")
	if not (ground and ground:IsA("BasePart") and high and high:IsA("BasePart")) then return end
	local groundCF, highCF = elevatorInteractionCFrames(root)
	ground.CFrame = groundCF
	high.CFrame = highCF
	ground.Size = Vector3.new(6, 0.7, 6)
	high.Size = Vector3.new(6, 0.7, 6)

	-- Plancher invisible de secours : le MeshPart PreciseConvex porte les murs,
	-- mais le sol Tripo est souvent trop irrégulier pour marcher dessus.
	local elevator = findAlias(root, ALIASES.Ascenceur)
	if elevator and (elevator:IsA("Model") or elevator:IsA("BasePart")) then
		local boxCF, boxSize = importedBounds(elevator)
		local floor = generated:FindFirstChild("ElevatorCabinFloor")
		if not (floor and floor:IsA("BasePart")) then
			if floor then floor:Destroy() end
			floor = Instance.new("Part")
			floor.Name = "ElevatorCabinFloor"
			floor.Anchored = true
			floor.Transparency = 1
			floor.CanCollide = true
			floor.CanTouch = true
			floor.CanQuery = true
			floor.Parent = generated
		end
		local floorPart = floor :: BasePart
		floorPart.Size = Vector3.new(math.clamp(boxSize.X * 0.62, 8, 18), 0.8, math.clamp(boxSize.Z * 0.62, 8, 18))
		local bottomY = boxCF.Position.Y - boxSize.Y / 2
		floorPart.CFrame = CFrame.new(boxCF.Position.X, bottomY + 0.4, boxCF.Position.Z) * importedPivot(elevator).Rotation

		-- Plus de noyau plein : le MeshPart PreciseConvex garde la cabine
		-- praticable tout en empêchant de traverser les murs.
		local blocker = generated:FindFirstChild("ElevatorCollisionCore")
		if blocker then blocker:Destroy() end
	end
end

local function previewFerrisWheel(generated: Instance, root: Instance)
	local source = findAlias(root, ALIASES.GrandeRoue)
	if not source then return end
	local base = findAlias(source, { "Base", "base" })
	local wheel = findAlias(source, { "Roue", "roue", "Wheel" })
	local gondolaSource = findAlias(source, { "NacelleModele", "Nacelle", "Gondola" })
	if not base or not wheel or not gondolaSource then return end
	if not ((base:IsA("Model") or base:IsA("BasePart")) and (wheel:IsA("Model") or wheel:IsA("BasePart")) and (gondolaSource:IsA("Model") or gondolaSource:IsA("BasePart"))) then return end

	local preview = movableModel(generated, "GrandeRouePreview")
	preview:SetAttribute("EditorPreviewOnly", true)
	local settings = Config.FerrisWheel
	local placement = Config.Placements.GrandeRoue
	local rootCF = CFrame.new(placement.Position) * CFrame.Angles(0, math.rad(placement.Yaw), 0)
	local hubCF = rootCF * CFrame.new(0, settings.HubHeight, 0)
	local hubHeight = settings.HubHeight
	if placement.PreserveStudioTransform == true then
		local baseBounds, baseSize = importedBounds(base)
		local wheelBounds = select(1, importedBounds(wheel))
		local groundPosition = Vector3.new(baseBounds.Position.X, baseBounds.Position.Y - baseSize.Y / 2, baseBounds.Position.Z)
		local rootRotation = importedPivot(base).Rotation
		rootCF = CFrame.new(groundPosition) * rootRotation
		hubCF = CFrame.new(wheelBounds.Position) * rootRotation
		hubHeight = math.max(1, wheelBounds.Position.Y - groundPosition.Y)
	end

	anchorAll(base)
	anchorAll(wheel)
	if placement.PreserveStudioTransform ~= true then
		scaleImportedToHeight(base, settings.BaseHeight)
		moveImportedBounds(base, rootCF * CFrame.new(0, settings.BaseHeight / 2, 0))
		local _, wheelSize = importedBounds(wheel)
		local diameter = math.max(wheelSize.X, wheelSize.Y)
		if diameter > 0.05 then
			local factor = settings.WheelDiameter / diameter
			if wheel:IsA("Model") then wheel:ScaleTo(wheel:GetScale() * factor) else wheel.Size *= factor end
		end
		moveImportedBounds(wheel, hubCF)
	end

	for index = 1, settings.GondolaCount do
		local gondola = gondolaSource:Clone()
		gondola.Name = string.format("PreviewGondola%02d", index)
		gondola.Parent = preview
		anchorAll(gondola)
		scaleImportedToHeight(gondola, settings.GondolaHeight)
		local angle = ((index - 1) / settings.GondolaCount) * math.pi * 2
		local attachment = rootCF * CFrame.new(math.cos(angle) * settings.GondolaRadius, hubHeight + math.sin(angle) * settings.GondolaRadius, 0)
		local cabinPosition = attachment.Position - Vector3.new(0, settings.HangerLength + settings.GondolaHeight / 2, 0)
		moveImportedBounds(gondola, CFrame.new(cabinPosition) * rootCF.Rotation)
		part(preview, "PreviewHanger", Vector3.new(0.45, settings.HangerLength, 0.45), CFrame.new(attachment.Position - Vector3.new(0, settings.HangerLength / 2, 0)), C.Cream, Enum.Material.Metal).CanCollide = false
	end
end

local function placeImported(root: Instance, canonical: string, previewMode: boolean?, keepStudioTransform: boolean?)
	local item = if canonical == "Chapiteau"
		then (findBestChapiteau(root) or findAlias(root, ALIASES.Chapiteau))
		elseif canonical == "RollABall" then findRollABallSource(root)
		else findAlias(root, ALIASES[canonical])
	local placement = Config.Placements[canonical]
	if not item or not placement then return end
	anchorAll(item)
	if placement.PreserveStudioTransform ~= true and keepStudioTransform ~= true then
		scaleImportedToHeight(item, placement.TargetHeight)
		local desired = CFrame.new(placement.Position) * CFrame.Angles(0, math.rad(placement.Yaw), 0)
		if item:IsA("Model") then
			local boxCF, boxSize = item:GetBoundingBox()
			local desiredBox = desired * CFrame.new(0, boxSize.Y / 2, 0)
			local delta = desiredBox * boxCF:Inverse()
			item:PivotTo(delta * item:GetPivot())
		elseif item:IsA("BasePart") then
			item.CFrame = desired * CFrame.new(0, item.Size.Y / 2, 0)
		end
	end
	configureImportedCollision(
		item,
		CollisionLogic.ShouldMeshCollide(canonical),
		previewMode ~= true,
		CollisionLogic.NeedsInteriorDoubleSided(canonical)
	)
	if canonical == "Chapiteau" then
		restoreTripoTentVisuals(item)
	end
	item:SetAttribute("ParkImportedAsset", canonical)
	print(("[AmusementParkBuilder] modèle Tripo actif: %s -> %s"):format(canonical, item:GetFullName()))
end

local function importedBubbleBlasterGameplay(generated: Instance, root: Instance): boolean
	local imported = findAlias(root, ALIASES.BubbleBlaster)
	if not imported or not (imported:IsA("Model") or imported:IsA("BasePart")) then return false end

	local previous = generated:FindFirstChild("BubbleBlasterGameplay")
	if previous then previous:Destroy() end
	local group = movableModel(generated, "BubbleBlasterGameplay")
	local placement = Config.Placements.BubbleBlaster
	local offset = placement.InteractionOffset or Vector3.new(0, 5.5, -10)
	-- La commande suit le kiosque tel qu'il est posé dans Studio. S'appuyer sur la
	-- position de configuration la laisserait à l'ancien emplacement.
	local boxCF, boxSize = importedBounds(imported)
	local base = CFrame.new(boxCF.Position.X, boxCF.Position.Y - boxSize.Y / 2, boxCF.Position.Z)
		* importedPivot(imported).Rotation
	local interactionCF = base * CFrame.new(offset)
	local interaction = part(group, "BubbleBlasterInteraction", Vector3.new(9, 7, 3), interactionCF, C.Cyan)
	interaction.Transparency = 1
	interaction.CanCollide = false
	interaction.CanTouch = false
	interaction.CanQuery = true
	interaction:SetAttribute("BubbleBlasterPrompt", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlayBubbleBlaster"
	prompt.ActionText = "Play"
	prompt.ObjectText = "Bubble Blaster"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt.Parent = interaction
	return true
end

local function importedRollABallGameplay(generated: Instance, root: Instance): boolean
	local imported = findRollABallSource(root)
	if not imported or not (imported:IsA("Model") or imported:IsA("BasePart")) then return false end
	destroyGeneratedRollABallKiosk(generated)

	local previous = generated:FindFirstChild("RollABallGameplay")
	if previous then previous:Destroy() end
	local group = movableModel(generated, "RollABallGameplay")
	-- L'orientation d'un import Tripo est arbitraire : un offset dans l'axe local
	-- du mesh peut placer la commande à l'intérieur ou derrière la borne. Le volume
	-- d'interaction enveloppe donc le modèle et reste aligné sur le monde.
	local boxCF, boxSize = importedBounds(imported)
	local reach = math.max(boxSize.X, boxSize.Z) / 2 + 10
	local interactionCF = CFrame.new(boxCF.Position)
	local interaction = part(
		group,
		"RollABallInteraction",
		Vector3.new(boxSize.X + 6, math.max(boxSize.Y, 8), boxSize.Z + 6),
		interactionCF,
		C.Cyan
	)
	interaction.Transparency = 1
	interaction.CanCollide = false
	interaction.CanTouch = false
	interaction.CanQuery = false
	interaction:SetAttribute("RollABallPrompt", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlayRollABall"
	prompt.ActionText = "Play"
	prompt.ObjectText = "Roll-A-Ball"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = math.clamp(reach, 16, 40)
	prompt.RequiresLineOfSight = false
	prompt.Parent = interaction
	print(("[AmusementParkBuilder] prompt Roll-A-Ball à %s (portée %.1f, mesh %s)"):format(
		tostring(boxCF.Position),
		prompt.MaxActivationDistance,
		tostring(boxSize)
	))
	return true
end

local function ensureCarouselModel(source: Instance): Model?
	if source:IsA("Model") then
		return source
	end
	if not CollisionLogic.IsCarouselSourceClass(source.ClassName) then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = if source.Name ~= "" then source.Name else "Carousel"
	model.Parent = source.Parent
	if source:IsA("Folder") then
		for _, child in ipairs(source:GetChildren()) do
			child.Parent = model
		end
		source:Destroy()
	else
		source.Parent = model
	end
	return model
end

local function addCarouselCollisionHull(model: Model, desired: CFrame, boxSize: Vector3)
	for _, name in ipairs({ "CarouselCollisionDeck", "CarouselCollisionBody", "CarouselCollisionHull" }) do
		local old = model:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local diameter = math.max(12, math.max(boxSize.X, boxSize.Z) * CollisionLogic.CarouselHullDiameterScale())
	local deck = cylinder(model, "CarouselCollisionDeck", diameter, 2, desired * CFrame.new(0, 1, 0), C.Purple)
	deck.Transparency = 1
	deck.CanCollide = true
	local bodyHeight = math.clamp(boxSize.Y * 0.55, 8, 16)
	local body = cylinder(model, "CarouselCollisionBody", diameter, bodyHeight, desired * CFrame.new(0, bodyHeight / 2, 0), C.Navy)
	body.Transparency = 1
	body.CanCollide = true
end

local function findStudioCarousel(root: Instance, generated: Instance): Instance?
	for _, child in ipairs(root:GetChildren()) do
		if child ~= generated
			and CollisionLogic.MatchesCarouselName(child.Name)
			and CollisionLogic.IsCarouselSourceClass(child.ClassName) then
			return child
		end
	end
	local tagged = findPermanentAlias(root, generated, ALIASES.Carousel)
	if tagged then
		return tagged
	end
	for _, candidate in ipairs(root:GetDescendants()) do
		if candidate:IsDescendantOf(generated) then
			continue
		end
		if CollisionLogic.IsKnownNonCarouselAsset(candidate.Name) then
			continue
		end
		if CollisionLogic.MatchesCarouselName(candidate.Name)
			and CollisionLogic.IsCarouselSourceClass(candidate.ClassName) then
			return candidate
		end
	end
	return nil
end

local function rescueStudioCarousel(root: Instance, generated: Instance)
	for _, child in ipairs(generated:GetChildren()) do
		if child:GetAttribute("TemporaryParkClone") == true then
			child:Destroy()
			continue
		end
		if CollisionLogic.MatchesCarouselName(child.Name)
			and child:GetAttribute("GeneratedBy") ~= "AmusementParkBuilder" then
			child.Parent = root
		end
	end
end

local function importedCarousel(root: Instance, generated: Instance, _previewMode: boolean?): boolean
	rescueStudioCarousel(root, generated)
	local source = findStudioCarousel(root, generated)
	local placement = Config.Placements.Carousel
	if not source or not placement then
		return false
	end

	local model = ensureCarouselModel(source)
	if not model then
		return false
	end
	model:SetAttribute("AnimatedAttraction", "Carousel")
	model:SetAttribute("ParkImportedAsset", "Carousel")
	model:SetAttribute("TemporaryParkClone", false)
	anchorAll(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") or descendant:IsA("Motor6D") then
			descendant:Destroy()
		elseif descendant:IsA("Seat") or descendant:IsA("VehicleSeat")
			or descendant.Name == "CarouselCollisionDeck"
			or descendant.Name == "CarouselCollisionBody"
			or descendant.Name == "CarouselCollisionHull"
			or descendant.Name == "CarouselSeat" then
			descendant:Destroy()
		end
	end
	local boxCF, boxSize = model:GetBoundingBox()
	local desired = CFrame.new(boxCF.Position.X, boxCF.Position.Y - boxSize.Y / 2, boxCF.Position.Z)
	if placement.PreserveStudioTransform ~= true then
		scaleImportedToHeight(model, placement.TargetHeight)
		desired = CFrame.new(placement.Position) * CFrame.Angles(0, math.rad(placement.Yaw), 0)
		boxCF, boxSize = model:GetBoundingBox()
		local desiredBox = desired * CFrame.new(0, boxSize.Y / 2, 0)
		model:PivotTo(desiredBox * boxCF:Inverse() * model:GetPivot())
		boxCF, boxSize = model:GetBoundingBox()
		desired = CFrame.new(boxCF.Position.X, boxCF.Position.Y - boxSize.Y / 2, boxCF.Position.Z)
	end
	model.PrimaryPart = nil
	model.WorldPivot = desired

	local hull = CollisionLogic.CarouselCollisionFidelity()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
			descendant.CanTouch = true
			descendant.CollisionGroup = "Default"
			if descendant:IsA("MeshPart") then
				descendant.DoubleSided = true
			end
			if descendant:IsA("MeshPart") or descendant:IsA("UnionOperation") then
				pcall(function()
					(descendant :: any).CollisionFidelity = hull
				end)
			end
		end
	end
	addCarouselCollisionHull(model, desired, boxSize)

	local diameter = math.max(12, math.max(boxSize.X, boxSize.Z) * CollisionLogic.CarouselHullDiameterScale())
	local seatRadius = math.max(8, diameter * 0.36)
	for i = 1, 12 do
		local angle = (i - 1) * (math.pi * 2 / 12) + math.pi / 12
		local seat = Instance.new("Seat")
		seat.Name = "CarouselSeat"
		seat.Size = Vector3.new(2.2, 0.5, 2.2)
		seat.CFrame = desired * CFrame.new(math.cos(angle) * seatRadius, 5.25, math.sin(angle) * seatRadius) * CFrame.Angles(0, -angle + math.pi / 2, 0)
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanTouch = false
		seat.Disabled = true
		seat.Transparency = 1
		seat:SetAttribute("CarouselControlledSeat", true)
		seat.Parent = model
	end

	print(("[AmusementParkBuilder] manège animé sur place: %s"):format(model:GetFullName()))
	return true
end

function Builder.Build(previewMode: boolean?): Folder
	local root = workspace:FindFirstChild("ParcAttractions")
	if not root then
		root = Instance.new("Folder")
		root.Name = "ParcAttractions"
		root.Parent = workspace
	end
	-- Conservé hors de GeneratedLayout afin que l'utilisateur puisse déplacer et
	-- redimensionner les trois volumes directement dans Studio.
	ensureBubbleRegions(root, previewMode)
	local old = root:FindFirstChild(Config.GeneratedFolderName)
	-- Migration/récupération : d'anciennes versions du constructeur déplaçaient
	-- parfois les imports Tripo dans GeneratedLayout. Les ressortir AVANT de
	-- détruire l'aperçu évite toute perte permanente en mode édition.
	if old then
		for _, child in ipairs(old:GetDescendants()) do
			local imported = child:GetAttribute("ParkImportedAsset")
			if imported ~= nil and child:GetAttribute("TemporaryParkClone") ~= true then
				child.Parent = root
			end
		end
		for _, child in ipairs(old:GetChildren()) do
			if CollisionLogic.MatchesCarouselName(child.Name)
				and child:GetAttribute("GeneratedBy") ~= "AmusementParkBuilder" then
				child.Parent = root
			end
		end
	end
	if old then old:Destroy() end
	local generated = Instance.new("Folder")
	generated.Name = Config.GeneratedFolderName
	generated:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	generated:SetAttribute("StudioEditableLayout", previewMode == true)
	generated.Parent = root

	local o = Config.Origin
	part(generated, "IslandFoundation", Vector3.new(Config.Size.X + 12, 10, Config.Size.Z + 12), CFrame.new(o.X, o.Y - 6, o.Z), C.Ground, Enum.Material.Grass)
	part(generated, "ParkFloor", Config.Size, CFrame.new(o.X, o.Y - 1, o.Z), C.Cream, Enum.Material.SmoothPlastic)

	-- Passerelle vers le bord ouest de la zone classique.
	part(generated, "ClassicBridge", Vector3.new(48, 2, Config.BridgeWidth), CFrame.new(-144, o.Y - 1, 0), C.Blue)
	railing(generated, Vector3.new(-168, o.Y + 4, -Config.BridgeWidth / 2), Vector3.new(-120, o.Y + 4, -Config.BridgeWidth / 2))
	railing(generated, Vector3.new(-168, o.Y + 4, Config.BridgeWidth / 2), Vector3.new(-120, o.Y + 4, Config.BridgeWidth / 2))

	-- Allée d'entrée et place centrale.
	part(generated, "MainPromenade", Vector3.new(118, 1, 22), CFrame.new(-227, o.Y + 0.5, 0), C.Red)
	cylinder(generated, "CentralPlaza", 58, 1, CFrame.new(-255, o.Y + 0.5, 0), C.Yellow)
	-- Le modèle Tripo est prioritaire. L'arche procédurale ne sert que de secours
	-- lorsque le modèle manuel n'existe pas dans Studio.
	if not findAlias(root, ALIASES.EntreeParc) then
		arch(generated, Vector3.new(-166, o.Y, 0))
	end

	part(generated, "NorthPromenade", Vector3.new(92, 1, 14), CFrame.new(-254, o.Y + 0.5, 50), C.Cyan)
	part(generated, "SouthPromenade", Vector3.new(92, 1, 14), CFrame.new(-254, o.Y + 0.5, -52), C.Purple)
	part(generated, "CrossPromenade", Vector3.new(14, 1, 118), CFrame.new(-258, o.Y + 0.5, 0), C.Yellow)
	-- Le modèle Tripo BubbleBlaster remplace entièrement le kiosque procédural.
	-- Celui-ci reste uniquement comme solution de secours si l'import est absent.
	if not findAlias(root, ALIASES.BubbleBlaster) then
		bubbleBlasterKiosk(generated, Vector3.new(-205, o.Y, -58))
	end
	if not findRollABallSource(root) then
		rollABallKiosk(generated, Vector3.new(-175, o.Y, -58))
	end
	for _, z in ipairs({ -66, -35, 35, 66 }) do
		for _, x in ipairs({ -205, -235, -285, -322 }) do
			lamp(generated, Vector3.new(x, o.Y, z))
		end
	end
	pennants(generated, Vector3.new(-180, o.Y + 17, -18), Vector3.new(-250, o.Y + 20, -18))
	pennants(generated, Vector3.new(-180, o.Y + 17, 18), Vector3.new(-250, o.Y + 20, 18))

	-- Trois niveaux de gameplay.
	platform(generated, "MidPlatform", Vector3.new(-270, o.Y + 10, -51), Vector3.new(58, 2, 42), C.Purple)
	platform(generated, "HighPlatform", Vector3.new(-306, o.Y + 22, 47), Vector3.new(52, 2, 40), C.Blue)
	-- Petit quai d'embarquement dégagé. L'ancienne plateforme de 50 x 78
	-- encerclait la base de la grande roue et bloquait son accès.
	-- Quai ouvert du côté est : aucun garde-corps ne traverse l'escalier.
	local wheelStructure = movableModel(generated, "GrandeRoueStructure")
	part(wheelStructure, "WheelDeck", Vector3.new(22, 0.8, 30), CFrame.new(-302, o.Y + 7.6, 5), C.Cyan)
	for _, z in ipairs({ -10, 20 }) do
		railing(wheelStructure, Vector3.new(-313, o.Y + 12, z), Vector3.new(-294, o.Y + 12, z))
	end
	railing(wheelStructure, Vector3.new(-313, o.Y + 12, -10), Vector3.new(-313, o.Y + 12, 20))
	for _, z in ipairs({ -7, 17 }) do
		part(wheelStructure, "WheelDeckSupport", Vector3.new(2, 7, 2), CFrame.new(-309, o.Y + 3.5, z), C.Navy, Enum.Material.Metal)
	end
	stairs(generated, "StairsToMid", Vector3.new(-225, o.Y, -50), Vector3.new(-1, 0, 0), 12, 10, 10)
	-- L'ancienne SkyWalk traversait l'entrée de la grande roue. L'accès à la
	-- plateforme haute se fait maintenant par l'ascenseur, sans obstacle ici.
	-- L'escalier termine maintenant exactement au bord du quai au lieu de
	-- progresser plusieurs mètres sous celui-ci.
	stairs(wheelStructure, "StairsToWheel", Vector3.new(-275, o.Y, 5), Vector3.new(-1, 0, 0), 10, 8, 7)

	-- Aucun ascenseur rectangulaire de secours : seul le modèle Studio/Tripo est
	-- affiché. Les deux pads invisibles ci-dessous gardent la mécanique active.
	local elevatorGroundCF, elevatorHighCF = elevatorInteractionCFrames(root)
	local elevatorGround = part(generated, "ElevatorGroundPad", Vector3.new(6, 0.7, 6), elevatorGroundCF, C.Yellow, Enum.Material.Neon)
	elevatorGround:SetAttribute("ElevatorDestination", "High")
	elevatorGround.Transparency = 1
	elevatorGround.CanCollide = false
	local elevatorHigh = part(generated, "ElevatorHighPad", Vector3.new(6, 0.7, 6), elevatorHighCF, C.Mint, Enum.Material.Neon)
	elevatorHigh:SetAttribute("ElevatorDestination", "Ground")
	elevatorHigh.Transparency = 1
	-- Le point d'arrivée est légèrement devant le modèle Tripo. Il sert aussi de
	-- petit palier invisible afin que le joueur ne tombe pas après la téléportation.
	elevatorHigh.CanCollide = true
	syncElevatorInteractionPads(generated, root)

	if not importedCarousel(root, generated, previewMode) then
		carousel(generated, Vector3.new(-238, o.Y, 58))
	end
	importedTentInterior(generated, root)
	placeImported(root, "StationEmbarquement", previewMode)
	liftStationOnStilts(generated, root, previewMode)
	local stationPoint, stationForward = buildStationAccess(generated, root)
	placeImportedCoasterElevator(root, generated, stationForward)
	-- Escalier indépendant vers le quai, désormais à la même hauteur que les rails.
	-- L'escalier est maintenant créé par buildStationAccess.
	-- Passerelle supérieure reliant l'escalier décalé au quai sans que le modèle
	-- Tripo de la station empiète sur les premières marches.
	-- Palier indépendant : son bord droit s'arrête avant la station Tripo. Aucun
	-- volume décoratif ne peut désormais couper le passage vers MidPlatform.
	coaster(generated, stationPoint, stationForward)
	attractionSign(generated, "FERRIS WHEEL", Vector3.new(-326, o.Y + 17, -19), C.Blue)
	attractionSign(generated, "ROLL-A-BALL", Vector3.new(-175, o.Y + 12, -42), C.Red)

	-- Zone de vente devant le kiosque à bonbons. ZoneService la traite avec la
	-- même transaction BackpackService que le kiosque Sell Bubbles du lobby.
	local candySellPad = part(generated, "CandySellPad", Vector3.new(14, 0.4, 10), CFrame.new(-190, o.Y + 0.2, -18), C.Yellow, Enum.Material.Neon)
	candySellPad.CanCollide = true
	local candySellZone = part(generated, "ParkSellZone", Vector3.new(26, 8, 30), CFrame.new(-190, o.Y + 4, -29), C.Yellow)
	candySellZone.Transparency = 1
	candySellZone.CanCollide = false
	candySellZone.CanTouch = false
	candySellZone.CanQuery = true

	local minX, maxX = o.X - Config.Size.X / 2, o.X + Config.Size.X / 2
	local minZ, maxZ = o.Z - Config.Size.Z / 2, o.Z + Config.Size.Z / 2
	part(generated, "ParkBorder", Vector3.new(Config.Size.X, 4, 1.2), CFrame.new(o.X, o.Y + 2, minZ), C.Navy, Enum.Material.Metal)
	part(generated, "ParkBorder", Vector3.new(Config.Size.X, 4, 1.2), CFrame.new(o.X, o.Y + 2, maxZ), C.Navy, Enum.Material.Metal)
	part(generated, "ParkBorder", Vector3.new(1.2, 4, Config.Size.Z), CFrame.new(minX, o.Y + 2, o.Z), C.Navy, Enum.Material.Metal)
	local entryGap = 30
	local sideLength = (Config.Size.Z - entryGap) / 2
	part(generated, "ParkBorder", Vector3.new(1.2, 4, sideLength), CFrame.new(maxX, o.Y + 2, -(entryGap + sideLength) / 2), C.Navy, Enum.Material.Metal)
	part(generated, "ParkBorder", Vector3.new(1.2, 4, sideLength), CFrame.new(maxX, o.Y + 2, (entryGap + sideLength) / 2), C.Navy, Enum.Material.Metal)

	-- Points réservés aux futures grilles de bulles sur chaque étage.

	for canonical in pairs(ALIASES) do
		if canonical == "WagonModele" or canonical == "Carousel" or canonical == "StationEmbarquement" or canonical == "AscenseurCommun" then continue end
		placeImported(root, canonical, previewMode)
	end
	importedBubbleBlasterGameplay(generated, root)
	importedRollABallGameplay(generated, root)
	if previewMode == true then previewFerrisWheel(generated, root) end

	print(("[AmusementParkBuilder] Fondation créée; modèles importés conservés. (%s)"):format(CODE_VERSION))
	return generated
end

function Builder.Start()
	print("[AmusementParkBuilder] START " .. CODE_VERSION)
	pcall(ensureTentGameplay)
	local root = workspace:FindFirstChild("ParcAttractions")
	-- Le modèle Studio `roll_a_ball` doit remplacer le kiosque généré avant tout le
	-- reste : un échec plus loin ne doit plus laisser l'ancien booth visible.
	if root then
		local importedRoll = findRollABallSource(root)
		if importedRoll then
			destroyGeneratedRollABallKiosk(root)
			destroyGeneratedRollABallKiosk(workspace)
		end
	end
	-- Un aperçu créé en mode édition devient la disposition officielle du parc.
	-- On le conserve au lancement afin que les déplacements faits manuellement
	-- dans Studio restent identiques en F5 et dans la version publiée.
	local editable = root and root:FindFirstChild(Config.GeneratedFolderName)
	if editable and editable:IsA("Folder") and editable:GetAttribute("StudioEditableLayout") == true then
		ensureBubbleRegions(root, false)
		-- Conserver la position Studio ne doit pas conserver des meshes traversables.
		-- Cette synchronisation ne modifie aucun CFrame ni aucune taille.
		syncImportedRuntimeCollisions(root, editable)
		-- Les pads sont temporaires et suivent toujours le modèle Ascenceur tel
		-- qu'il est présentement placé dans Studio.
		syncElevatorInteractionPads(editable, root)
		-- Les ajouts de gameplay récents doivent aussi apparaître dans une disposition
		-- Studio conservée, sans reconstruire ni déplacer les bâtiments du créateur.
		local imported = findAlias(root, ALIASES.BubbleBlaster)
		if imported then
			local fallback = editable:FindFirstChild("BubbleBlasterKiosk")
			if fallback then fallback:Destroy() end
			-- Disposition Studio conservée : on branche seulement les collisions et
			-- la commande, sans replacer le kiosque sur sa position de configuration.
			placeImported(root, "BubbleBlaster", false, true)
			importedBubbleBlasterGameplay(editable, root)
		elseif not editable:FindFirstChild("BubbleBlasterKiosk") then
			bubbleBlasterKiosk(editable, Vector3.new(-205, Config.Origin.Y, -58))
		end
		local importedRoll = findRollABallSource(root)
		if importedRoll then
			destroyGeneratedRollABallKiosk(root)
			placeImported(root, "RollABall", false, true)
			importedRollABallGameplay(editable, root)
		elseif not root:FindFirstChild("roll_a_ball", true) and not editable:FindFirstChild("RollABallKiosk") then
			rollABallKiosk(editable, Vector3.new(-175, Config.Origin.Y, -58))
		end
		importedCarousel(root, editable, false)
		local oldCoaster = editable:FindFirstChild("RollerCoaster")
		if oldCoaster then oldCoaster:Destroy() end
		local oldDock = editable:FindFirstChild("Embarcadere")
		if oldDock then oldDock:Destroy() end
		for _, child in ipairs(editable:GetChildren()) do
			if string.sub(child.Name, 1, 9) == "TourStop_" then
				child:Destroy()
			end
		end
		for _, child in ipairs(editable:GetChildren()) do
			if child.Name == "StationStilt" then child:Destroy() end
		end
		liftStationOnStilts(editable, root, false)
		local stationPoint, stationForward = buildStationAccess(editable, root)
		placeImportedCoasterElevator(root, editable, stationForward)
		coaster(editable, stationPoint, stationForward)
		pcall(ensureTentGameplay)
		print(("[AmusementParkBuilder] disposition Studio éditable conservée. (%s)"):format(CODE_VERSION))
		return
	end
	Builder.Build()
	pcall(ensureTentGameplay)
end

return Builder
