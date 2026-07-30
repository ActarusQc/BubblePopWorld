--!strict
-- Walk-in ItemShop building: three browse walls (Skills / Items / Cosmetics).
-- Layout (Yaw 90°, local +Z = entrance toward spawn):
--   Back (-Z) = Items | Left (-X) = Skills | Right (+X) = Cosmetics

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local MODEL_NAME = "ItemShop"
local LEGACY_MODEL_NAME = "BubbleShop"
local WORLD_NAME = "BubblePopWorld"

local COLORS = {
	NavyDeep = Color3.fromRGB(8, 22, 65),
	Navy = Color3.fromRGB(18, 32, 85),
	Blue = Color3.fromRGB(28, 105, 255),
	Cyan = Color3.fromRGB(80, 230, 255),
	CyanSoft = Color3.fromRGB(160, 240, 255),
	White = Color3.fromRGB(245, 250, 255),
	Panel = Color3.fromRGB(10, 26, 72),
	Amber = Color3.fromRGB(255, 185, 60),
	AmberSoft = Color3.fromRGB(255, 220, 140),
	AmberDeep = Color3.fromRGB(180, 120, 25),
	Floor = Color3.fromRGB(14, 28, 72),
}

type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Parent: Instance,
	Transparency: number?,
	CanCollide: boolean?,
	Shape: Enum.PartType?,
}

type CategoryId = "Skills" | "Items" | "Cosmetics"

type CategorySpec = {
	Id: CategoryId,
	WallName: string,
	PromptBrowseKey: string,
	ObjectTextKey: string,
	LabelKey: string,
	Accent: Color3,
	-- Wall center in local space (inside face).
	WallCenter: Vector3,
	-- Outward normal from wall into the room.
	Inward: Vector3,
}

local CATEGORIES: { CategorySpec } = {
	{
		Id = "Skills",
		WallName = "Wall_Skills",
		PromptBrowseKey = "BrowseSkills",
		ObjectTextKey = "Skills",
		LabelKey = "Skills",
		Accent = COLORS.Cyan,
		WallCenter = Vector3.new(0, 0, 0), -- filled at build time
		Inward = Vector3.new(1, 0, 0),
	},
	{
		Id = "Items",
		WallName = "Wall_Items",
		PromptBrowseKey = "BrowseItems",
		ObjectTextKey = "Items",
		LabelKey = "Items",
		Accent = COLORS.Amber,
		WallCenter = Vector3.new(0, 0, 0),
		Inward = Vector3.new(0, 0, 1),
	},
	{
		Id = "Cosmetics",
		WallName = "Wall_Cosmetics",
		PromptBrowseKey = "BrowseCosmetics",
		ObjectTextKey = "Cosmetics",
		LabelKey = "Cosmetics",
		Accent = COLORS.Blue,
		WallCenter = Vector3.new(0, 0, 0),
		Inward = Vector3.new(-1, 0, 0),
	},
}

local function makePart(props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.Name
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color
	part.Material = props.Material
	part.Transparency = props.Transparency or 0
	part.Shape = props.Shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = if props.CanCollide ~= nil then props.CanCollide else true
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.Parent
	return part
end

local function localCF(base: CFrame, position: Vector3, rotation: CFrame?): CFrame
	local result = base * CFrame.new(position)
	if rotation then
		result *= rotation
	end
	return result
end

local function l10nText(key: string): string
	local value = (L10n :: any)[key]
	if type(value) == "string" then
		return value
	end
	return key
end

local function makeSurfaceGui(host: BasePart, name: string, face: Enum.NormalId): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.Enabled = true
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.AlwaysOnTop = true
	gui.Parent = host
	return gui
end

local function addWallLabel(
	gui: SurfaceGui,
	textKey: string,
	titleColor: Color3,
	strokeColor: Color3
)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -12, 1, -12)
	label.Position = UDim2.new(0, 6, 0, 6)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = titleColor
	label.TextStrokeColor3 = strokeColor
	label.TextStrokeTransparency = 0.35
	label.Parent = gui
	L10nUtil.localize(label, l10nText(textKey))
end

local function resolveParent(): Instance
	local world = Workspace:FindFirstChild(WORLD_NAME)
	if world then
		local lobby = world:FindFirstChild("Lobby")
		if lobby then
			return lobby
		end
		return world
	end
	return Workspace
end

local function destroyExisting(parent: Instance)
	for _, container in ipairs({ Workspace, parent }) do
		for _, name in ipairs({ MODEL_NAME, LEGACY_MODEL_NAME }) do
			local existing = container:FindFirstChild(name)
			while existing do
				existing:Destroy()
				existing = container:FindFirstChild(name)
			end
		end
	end
end

local function rotationFacingInward(inward: Vector3): CFrame
	if inward.X > 0.5 then
		return CFrame.Angles(0, -math.pi / 2, 0)
	elseif inward.X < -0.5 then
		return CFrame.Angles(0, math.pi / 2, 0)
	elseif inward.Z > 0.5 then
		return CFrame.identity
	end
	return CFrame.Angles(0, math.pi, 0)
end

local function createFloor(model: Model, baseCF: CFrame, width: number, depth: number)
	local floorY = 0.5
	makePart({
		Name = "Floor",
		Size = Vector3.new(width + 2, 1, depth + 2),
		CFrame = localCF(baseCF, Vector3.new(0, floorY, 0)),
		Color = COLORS.Floor,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	makePart({
		Name = "FloorAccent",
		Size = Vector3.new(width - 1, 0.12, depth - 1),
		CFrame = localCF(baseCF, Vector3.new(0, 1.06, 0)),
		Color = COLORS.Blue,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 0.4,
		Parent = model,
	})
end

local function createFrontWall(
	model: Model,
	baseCF: CFrame,
	width: number,
	depth: number,
	height: number,
	thickness: number,
	doorWidth: number
)
	local halfW = width / 2
	local halfD = depth / 2
	local wallY = 1 + (height - 1) / 2
	local wallH = height - 1
	local frontZ = halfD - thickness / 2
	local sideWidth = (width - doorWidth) / 2

	local function segment(name: string, centerX: number, segWidth: number)
		makePart({
			Name = name,
			Size = Vector3.new(segWidth, wallH, thickness),
			CFrame = localCF(baseCF, Vector3.new(centerX, wallY, frontZ)),
			Color = COLORS.NavyDeep,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end

	segment("FrontWall_L", -halfW + sideWidth / 2, sideWidth)
	segment("FrontWall_R", halfW - sideWidth / 2, sideWidth)

	local lintelH = 2.5
	makePart({
		Name = "FrontLintel",
		Size = Vector3.new(doorWidth, lintelH, thickness),
		CFrame = localCF(baseCF, Vector3.new(0, 1 + wallH - lintelH / 2, frontZ)),
		Color = COLORS.Navy,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	makePart({
		Name = "FrontTrim",
		Size = Vector3.new(doorWidth + 0.8, 0.2, 0.2),
		CFrame = localCF(baseCF, Vector3.new(0, 1 + wallH - lintelH, frontZ + 0.15)),
		Color = COLORS.Amber,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.2,
		Parent = model,
	})
end

local function createEntrance(model: Model, baseCF: CFrame, depth: number, doorWidth: number): Part
	local halfD = depth / 2
	local marker = makePart({
		Name = "Entrance",
		Size = Vector3.new(doorWidth - 1, 0.2, 1.2),
		CFrame = localCF(baseCF, Vector3.new(0, 1.12, halfD + 0.4)),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.55,
		Parent = model,
	})
	return marker
end

local function createRoof(model: Model, baseCF: CFrame, width: number, depth: number, height: number)
	makePart({
		Name = "Roof",
		Size = Vector3.new(width + 1.2, 0.6, depth + 1.2),
		CFrame = localCF(baseCF, Vector3.new(0, height + 0.3, 0)),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})

	makePart({
		Name = "RoofNeon",
		Size = Vector3.new(width - 2, 0.18, 0.22),
		CFrame = localCF(baseCF, Vector3.new(0, height + 0.05, depth / 2 + 0.35)),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.25,
		Parent = model,
	})
end

local function createFacadeSign(model: Model, baseCF: CFrame, width: number, depth: number, height: number, signText: string)
	local halfD = depth / 2
	local board = makePart({
		Name = "FacadeSign",
		Size = Vector3.new(math.min(width - 4, 14), 2.8, 0.35),
		CFrame = localCF(baseCF, Vector3.new(0, height - 1.2, halfD + 0.2), CFrame.Angles(0, math.pi, 0)),
		Color = COLORS.Panel,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})

	local gui = makeSurfaceGui(board, "SignGui", Enum.NormalId.Front)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 1, -8)
	title.Position = UDim2.new(0, 8, 0, 4)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = COLORS.White
	title.TextStrokeColor3 = COLORS.NavyDeep
	title.TextStrokeTransparency = 0.35
	title.Parent = gui
	L10nUtil.dynamic(title, signText)
end

local function createCategoryWall(
	model: Model,
	baseCF: CFrame,
	spec: CategorySpec,
	width: number,
	depth: number,
	height: number,
	thickness: number
): Model
	local wallModel = Instance.new("Model")
	wallModel.Name = spec.WallName
	wallModel.Parent = model

	local halfW = width / 2
	local halfD = depth / 2
	local wallY = 1 + (height - 1) / 2
	local wallH = height - 1

	local center: Vector3
	local size: Vector3
	local face: Enum.NormalId
	local labelRot: CFrame

	if spec.Id == "Skills" then
		center = Vector3.new(-halfW + thickness / 2, wallY, 0)
		size = Vector3.new(thickness, wallH, depth - thickness * 2)
		face = Enum.NormalId.Right
		labelRot = CFrame.identity
	elseif spec.Id == "Items" then
		center = Vector3.new(0, wallY, -halfD + thickness / 2)
		size = Vector3.new(width - thickness * 2, wallH, thickness)
		face = Enum.NormalId.Front
		labelRot = CFrame.identity
	else
		center = Vector3.new(halfW - thickness / 2, wallY, 0)
		size = Vector3.new(thickness, wallH, depth - thickness * 2)
		face = Enum.NormalId.Left
		labelRot = CFrame.Angles(0, math.pi, 0)
	end

	spec.WallCenter = center

	local body = makePart({
		Name = "Body",
		Size = size,
		CFrame = localCF(baseCF, center),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = wallModel,
	})

	makePart({
		Name = "Accent",
		Size = if spec.Id == "Items"
			then Vector3.new(size.X - 1.2, 0.18, 0.14)
			else Vector3.new(0.14, size.Y - 2, size.Z - 1.2),
		CFrame = localCF(baseCF, center + spec.Inward * (thickness / 2 + 0.08)),
		Color = spec.Accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.3,
		Parent = wallModel,
	})

	local labelHost = makePart({
		Name = "LabelBoard",
		Size = if spec.Id == "Items" then Vector3.new(6, 2.2, 0.2) else Vector3.new(0.2, 2.2, 6),
		CFrame = localCF(baseCF, center + spec.Inward * (thickness / 2 + 0.12) + Vector3.new(0, 2.5, 0), labelRot),
		Color = COLORS.Panel,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = wallModel,
	})

	local gui = makeSurfaceGui(labelHost, "WallLabelGui", face)
	addWallLabel(gui, spec.LabelKey, COLORS.White, spec.Accent)

	wallModel.PrimaryPart = body
	return wallModel
end

local function createDisplay(model: Model, baseCF: CFrame, spec: CategorySpec, height: number): Model
	local display = Instance.new("Model")
	display.Name = "Display_" .. spec.Id
	display.Parent = model

	local inward = spec.Inward
	local standCenter = spec.WallCenter + inward * 3.5 + Vector3.new(0, 0, 0)
	local standY = 1.35

	local base = makePart({
		Name = "Pedestal",
		Size = Vector3.new(3.2, 0.5, 3.2),
		CFrame = localCF(baseCF, Vector3.new(standCenter.X, standY, standCenter.Z), rotationFacingInward(inward)),
		Color = COLORS.Navy,
		Material = Enum.Material.SmoothPlastic,
		Parent = display,
	})

	makePart({
		Name = "PedestalTop",
		Size = Vector3.new(2.6, 0.22, 2.6),
		CFrame = localCF(baseCF, Vector3.new(standCenter.X, standY + 0.36, standCenter.Z), rotationFacingInward(inward)),
		Color = spec.Accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.25,
		Parent = display,
	})

	makePart({
		Name = "Showcase",
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = localCF(
			baseCF,
			Vector3.new(standCenter.X, standY + 1.35, standCenter.Z),
			rotationFacingInward(inward)
		),
		Color = spec.Accent,
		Material = Enum.Material.Glass,
		CanCollide = false,
		Transparency = 0.35,
		Parent = display,
	})

	display.PrimaryPart = base
	return display
end

local function createPromptAnchor(
	model: Model,
	baseCF: CFrame,
	spec: CategorySpec,
	shopConfig: typeof(Config.Lobby.ItemShop)
): Part
	local anchor = makePart({
		Name = "PromptAnchor_" .. spec.Id,
		Size = Vector3.new(4, 5, 2),
		CFrame = localCF(
			baseCF,
			spec.WallCenter + spec.Inward * 2.2 + Vector3.new(0, 3.5, 0),
			rotationFacingInward(spec.Inward)
		),
		Color = COLORS.CyanSoft,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 1,
		Parent = model,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BrowsePrompt"
	prompt.ActionText = l10nText(spec.PromptBrowseKey)
	prompt.ObjectText = l10nText(spec.ObjectTextKey)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = shopConfig.PromptMaxDistance or 13
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("BPW_ShopCategory", spec.Id)
	prompt.Parent = anchor

	return anchor
end

local function createCameraPoint(model: Model, baseCF: CFrame, spec: CategorySpec): Part
	local displayOffset = spec.WallCenter + spec.Inward * 3.5
	local camPos = displayOffset + spec.Inward * 5 + Vector3.new(0, 4.5, 0)

	return makePart({
		Name = "CameraPoint_" .. spec.Id,
		Size = Vector3.new(0.5, 0.5, 0.5),
		CFrame = localCF(baseCF, camPos, rotationFacingInward(spec.Inward)),
		Color = COLORS.White,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 1,
		Parent = model,
	})
end

local function createFrontStep(model: Model, baseCF: CFrame, doorWidth: number, depth: number)
	local halfD = depth / 2
	makePart({
		Name = "FrontStep",
		Size = Vector3.new(doorWidth + 1.5, 0.35, 2.2),
		CFrame = localCF(baseCF, Vector3.new(0, 0.85, halfD + 1.4)),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
end

local ItemShopBuilder = {}

function ItemShopBuilder.Build(position: Vector3?): Model
	local parent = resolveParent()
	destroyExisting(parent)

	local shopConfig = Config.Lobby.ItemShop
	local origin = position or Config.Lobby.ItemShopPosition
	local baseCF = CFrame.new(origin) * CFrame.Angles(0, math.rad(shopConfig.YawDegrees), 0)

	local width = shopConfig.Width or 22
	local depth = shopConfig.Depth or 18
	local height = shopConfig.Height or 12
	local doorWidth = shopConfig.DoorWidth or 10
	local thickness = shopConfig.WallThickness or 0.6
	local signText = shopConfig.SignText or L10n.ShopSign

	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	createFloor(model, baseCF, width, depth)
	createFrontWall(model, baseCF, width, depth, height, thickness, doorWidth)
	createFrontStep(model, baseCF, doorWidth, depth)
	local entrance = createEntrance(model, baseCF, depth, doorWidth)
	createRoof(model, baseCF, width, depth, height)
	createFacadeSign(model, baseCF, width, depth, height, signText)

	for _, spec in ipairs(CATEGORIES) do
		createCategoryWall(model, baseCF, spec, width, depth, height, thickness)
		createDisplay(model, baseCF, spec, height)
		createPromptAnchor(model, baseCF, spec, shopConfig)
		createCameraPoint(model, baseCF, spec)
	end

	local floor = model:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		model.PrimaryPart = floor
	end

	model:SetAttribute("BPW_ItemShop", true)
	model.Parent = parent

	print(
		string.format(
			"[ItemShopBuilder] origin=%s size=%dx%dx%d door=%d",
			tostring(origin),
			width,
			depth,
			height,
			doorWidth
		)
	)

	return model
end

function ItemShopBuilder.Start()
	ItemShopBuilder.Build()
end

return ItemShopBuilder
