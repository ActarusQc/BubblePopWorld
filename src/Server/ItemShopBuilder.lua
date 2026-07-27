--!strict
-- Bubble Shop purchase kiosk: generated 100% by code.
-- No imported OBJ/FBX assets are required.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local MODEL_NAME = "ItemShop"
local LEGACY_MODEL_NAME = "BubbleShop"
local WORLD_NAME = "BubblePopWorld"

-- Navy / cyan base + amber accents (no pink / magenta).
local COLORS = {
	NavyDeep = Color3.fromRGB(8, 22, 65),
	Navy = Color3.fromRGB(18, 32, 85),
	Blue = Color3.fromRGB(28, 105, 255),
	Cyan = Color3.fromRGB(80, 230, 255),
	CyanSoft = Color3.fromRGB(160, 240, 255),
	Glass = Color3.fromRGB(120, 210, 245),
	White = Color3.fromRGB(245, 250, 255),
	Panel = Color3.fromRGB(10, 26, 72),
	Shelf = Color3.fromRGB(14, 30, 70),
	Amber = Color3.fromRGB(255, 185, 60),
	AmberSoft = Color3.fromRGB(255, 220, 140),
	AmberDeep = Color3.fromRGB(180, 120, 25),
}

local DIMS = {
	PlazaSize = Vector3.new(24, 1.2, 22),
	Width = 16.5,
	PillarHeight = 10.5,
	PillarX = 7.4,
	-- Lower counter so the central tank stays visible from the front.
	CounterSize = Vector3.new(14.5, 2.55, 4.4),
	CanopySize = Vector3.new(18.5, 1.1, 10.5),
	SignSize = Vector3.new(15.5, 3.7, 1.0),
	TankHeight = 6.4,
	TankRadius = 1.85,
}

local BUBBLE = {
	Count = 12,
	MinSize = 0.32,
	MaxSize = 0.85,
	MinSpeed = 0.45,
	MaxSpeed = 0.9,
	Drift = 0.45,
}

type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Parent: Instance,
	Transparency: number?,
	Shape: Enum.PartType?,
	CanCollide: boolean?,
	Reflectance: number?,
	CastShadow: boolean?,
}

type BubbleData = {
	Part: BasePart,
	TankCF: CFrame,
	Height: number,
	Radius: number,
	Speed: number,
	Phase: number,
	OffsetX: number,
	OffsetZ: number,
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
	part.CastShadow = props.CastShadow or false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Reflectance then
		part.Reflectance = props.Reflectance
	end
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

local function makeLight(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

local function makeSurfaceGui(host: BasePart, name: string, pixelsPerStud: number, alwaysOnTop: boolean?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.Enabled = true
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.AlwaysOnTop = if alwaysOnTop == nil then true else alwaysOnTop
	gui.Parent = host
	return gui
end

-- Hollow neon frame: four thin borders only (never a solid plate over the GUI).
local function addOpenBorder(
	parent: Instance,
	name: string,
	baseCF: CFrame,
	center: Vector3,
	width: number,
	height: number,
	border: number,
	depth: number,
	color: Color3,
	rotation: CFrame?,
	transparency: number?
)
	local t = transparency or 0.2
	local rot = rotation
	local halfW = width / 2
	local halfH = height / 2
	local inset = border / 2

	makePart({
		Name = name .. "_Top",
		Size = Vector3.new(width, border, depth),
		CFrame = localCF(baseCF, center + Vector3.new(0, halfH - inset, 0), rot),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = t,
		Parent = parent,
	})
	makePart({
		Name = name .. "_Bottom",
		Size = Vector3.new(width, border, depth),
		CFrame = localCF(baseCF, center + Vector3.new(0, -halfH + inset, 0), rot),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = t,
		Parent = parent,
	})
	makePart({
		Name = name .. "_Left",
		Size = Vector3.new(border, height - border * 2, depth),
		CFrame = localCF(baseCF, center + Vector3.new(-halfW + inset, 0, 0), rot),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = t,
		Parent = parent,
	})
	makePart({
		Name = name .. "_Right",
		Size = Vector3.new(border, height - border * 2, depth),
		CFrame = localCF(baseCF, center + Vector3.new(halfW - inset, 0, 0), rot),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = t,
		Parent = parent,
	})
end

local function addTextLabel(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3,
	font: Enum.Font,
	strokeColor: Color3?,
	localize: boolean?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = font
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	if strokeColor then
		label.TextStrokeColor3 = strokeColor
		label.TextStrokeTransparency = 0.35
	end
	label.Parent = parent
	if localize == false then
		L10nUtil.dynamic(label, text)
	else
		L10nUtil.localize(label, text)
	end
	return label
end

local function addBubbleIcon(parent: Instance, name: string, center: Vector3, baseCF: CFrame, scale: number, color: Color3?)
	local tint = color or COLORS.Cyan
	for i, data in ipairs({
		{ Vector3.new(0, 0, 0), 1.0 },
		{ Vector3.new(-0.65, 0.35, 0.08), 0.42 },
		{ Vector3.new(0.55, 0.55, 0.05), 0.32 },
		{ Vector3.new(0.48, -0.45, 0.06), 0.25 },
	}) do
		local position = center + data[1] * scale
		local diameter = data[2] * scale
		makePart({
			Name = name .. tostring(i),
			Size = Vector3.new(diameter, diameter, 0.18),
			CFrame = localCF(baseCF, position, CFrame.Angles(math.rad(90), 0, 0)),
			Color = tint,
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			Transparency = 0.15,
			Parent = parent,
		})
	end
end

local function addMedallion(parent: Instance, name: string, center: Vector3, baseCF: CFrame, scale: number)
	makePart({
		Name = name .. "_Outer",
		Size = Vector3.new(0.22, scale * 1.55, scale * 1.55),
		CFrame = localCF(baseCF, center, CFrame.Angles(0, 0, math.rad(90))),
		Color = COLORS.AmberDeep,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = parent,
	})
	makePart({
		Name = name .. "_Ring",
		Size = Vector3.new(0.18, scale * 1.28, scale * 1.28),
		CFrame = localCF(baseCF, center + Vector3.new(0, 0, 0.06), CFrame.Angles(0, 0, math.rad(90))),
		Color = COLORS.Amber,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Transparency = 0.2,
		Parent = parent,
	})
	makePart({
		Name = name .. "_Core",
		Size = Vector3.new(0.16, scale * 0.72, scale * 0.72),
		CFrame = localCF(baseCF, center + Vector3.new(0, 0, 0.1), CFrame.Angles(0, 0, math.rad(90))),
		Color = COLORS.AmberSoft,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Transparency = 0.25,
		Parent = parent,
	})
	makePart({
		Name = name .. "_Bubble",
		Size = Vector3.new(scale * 0.55, scale * 0.55, 0.14),
		CFrame = localCF(baseCF, center + Vector3.new(0, 0, 0.16), CFrame.Angles(math.rad(90), 0, 0)),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Transparency = 0.2,
		Parent = parent,
	})
end

local function createPlaza(model: Model, baseCF: CFrame)
	makePart({
		Name = "ShopFloor",
		Size = DIMS.PlazaSize,
		CFrame = localCF(baseCF, Vector3.new(0, 0.4, 0.6)),
		Color = COLORS.Navy,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	makePart({
		Name = "ShopFloorInset",
		Size = Vector3.new(21.8, 0.16, 19.8),
		CFrame = localCF(baseCF, Vector3.new(0, 1.08, 0.5)),
		Color = COLORS.Blue,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 0.35,
		Parent = model,
	})

	makePart({
		Name = "PlazaTrimFront",
		Size = Vector3.new(22.5, 0.14, 0.28),
		CFrame = localCF(baseCF, Vector3.new(0, 1.18, 8.9)),
		Color = COLORS.Amber,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.25,
		Parent = model,
	})

	makePart({
		Name = "PlazaTrimBack",
		Size = Vector3.new(22.5, 0.12, 0.22),
		CFrame = localCF(baseCF, Vector3.new(0, 1.18, -7.6)),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.35,
		Parent = model,
	})

	for _, x in ipairs({ -10.9, 10.9 }) do
		makePart({
			Name = "PlazaSideNeon_" .. tostring(x),
			Size = Vector3.new(0.22, 0.12, 18.0),
			CFrame = localCF(baseCF, Vector3.new(x, 1.18, 0.6)),
			Color = COLORS.Cyan,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.4,
			Parent = model,
		})
	end

	makePart({
		Name = "FrontStep",
		Size = Vector3.new(13.5, 0.38, 2.6),
		CFrame = localCF(baseCF, Vector3.new(0, 1.12, 10.4)),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	makePart({
		Name = "FrontStepUpper",
		Size = Vector3.new(11.8, 0.28, 1.6),
		CFrame = localCF(baseCF, Vector3.new(0, 1.4, 9.55)),
		Color = COLORS.Navy,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	makePart({
		Name = "FrontStepTrim",
		Size = Vector3.new(13.2, 0.12, 0.2),
		CFrame = localCF(baseCF, Vector3.new(0, 1.34, 11.65)),
		Color = COLORS.Amber,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.2,
		Parent = model,
	})
end

local function createPillars(model: Model, baseCF: CFrame)
	local height = DIMS.PillarHeight
	local y = height / 2 + 0.4

	for _, side in ipairs({ -1, 1 }) do
		local x = side * DIMS.PillarX
		local suffix = if side < 0 then "L" else "R"

		makePart({
			Name = "Pillar_" .. suffix,
			Size = Vector3.new(2.8, height, 3.0),
			CFrame = localCF(baseCF, Vector3.new(x, y, -1.2)),
			Color = COLORS.NavyDeep,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})

		makePart({
			Name = "PillarInset_" .. suffix,
			Size = Vector3.new(1.7, height - 1.0, 0.36),
			CFrame = localCF(baseCF, Vector3.new(x, y, 0.28)),
			Color = COLORS.Navy,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = model,
		})

		local neon = makePart({
			Name = "PillarNeon_" .. suffix,
			Size = Vector3.new(0.2, height - 1.6, 0.38),
			CFrame = localCF(baseCF, Vector3.new(x, y, 0.5)),
			Color = COLORS.Cyan,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.2,
			Parent = model,
		})
		makeLight(neon, COLORS.Cyan, 0.35, 7)

		makePart({
			Name = "PillarAmberEdge_" .. suffix,
			Size = Vector3.new(0.16, height - 2.2, 0.22),
			CFrame = localCF(baseCF, Vector3.new(x + side * 0.85, y, 0.42)),
			Color = COLORS.Amber,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.3,
			Parent = model,
		})

		for _, capY in ipairs({ 0.65, height + 0.15 }) do
			makePart({
				Name = "PillarCap_" .. suffix .. tostring(capY),
				Size = Vector3.new(3.3, 0.5, 3.5),
				CFrame = localCF(baseCF, Vector3.new(x, capY, -1.2)),
				Color = COLORS.Navy,
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
			makePart({
				Name = "PillarCapAmber_" .. suffix .. tostring(capY),
				Size = Vector3.new(3.0, 0.12, 3.2),
				CFrame = localCF(baseCF, Vector3.new(x, capY + (if capY < 1 then 0.28 else -0.28), -1.2)),
				Color = COLORS.AmberDeep,
				Material = Enum.Material.Neon,
				CanCollide = false,
				Transparency = 0.35,
				Parent = model,
			})
		end

		addMedallion(model, "PillarMedallion_" .. suffix, Vector3.new(x, 5.8, 0.62), baseCF, 1.15)
	end
end

local function createRoof(model: Model, baseCF: CFrame)
	local canopy = DIMS.CanopySize

	makePart({
		Name = "RoofMain",
		Size = canopy,
		CFrame = localCF(baseCF, Vector3.new(0, 9.55, 0.8)),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})

	for i, layer in ipairs({
		{ Vector3.new(17.5, 0.48, 9.4), 10.25, COLORS.Navy },
		{ Vector3.new(15.7, 0.42, 8.1), 10.8, COLORS.NavyDeep },
		{ Vector3.new(13.8, 0.35, 6.8), 11.25, COLORS.Navy },
	}) do
		makePart({
			Name = "RoofLayer" .. tostring(i),
			Size = layer[1] :: Vector3,
			CFrame = localCF(baseCF, Vector3.new(0, layer[2] :: number, 0.4)),
			Color = layer[3] :: Color3,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = model,
		})
	end

	local frontNeon = makePart({
		Name = "RoofFrontNeon",
		Size = Vector3.new(canopy.X + 0.5, 0.22, 0.28),
		CFrame = localCF(baseCF, Vector3.new(0, 9.05, canopy.Z / 2 + 0.95)),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.25,
		Parent = model,
	})
	makeLight(frontNeon, COLORS.Cyan, 0.55, 12)

	makePart({
		Name = "RoofAmberBand",
		Size = Vector3.new(canopy.X - 1.4, 0.28, 0.22),
		CFrame = localCF(baseCF, Vector3.new(0, 9.45, canopy.Z / 2 + 0.92)),
		Color = COLORS.Amber,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.25,
		Parent = model,
	})
end

local function createSign(model: Model, baseCF: CFrame)
	local size = DIMS.SignSize
	local shopConfig = Config.Lobby.ItemShop
	local titleText = shopConfig.SignText or L10n.BubbleShop
	local subtitleText = shopConfig.TaglineText or L10n.BuyBubblesAndItems
	local faceFront = CFrame.Angles(0, math.pi, 0)
	-- Board sits so its Front face (SurfaceGui) looks toward the player (+local Z).
	local boardZ = 1.15
	local borderZ = boardZ + size.Z / 2 + 0.12

	makePart({
		Name = "SignBack",
		Size = Vector3.new(size.X + 1.2, size.Y + 1.0, 0.55),
		CFrame = localCF(baseCF, Vector3.new(0, 12.35, 0.45)),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})

	local sign = makePart({
		Name = "SignBoard",
		Size = size,
		CFrame = localCF(baseCF, Vector3.new(0, 12.35, boardZ), faceFront),
		Color = COLORS.Panel,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})

	-- Open cyan + amber borders only — center stays clear for the SurfaceGui.
	addOpenBorder(
		model,
		"SignBorderCyan",
		baseCF,
		Vector3.new(0, 12.35, borderZ),
		size.X + 0.55,
		size.Y + 0.55,
		0.28,
		0.14,
		COLORS.Cyan,
		faceFront,
		0.15
	)
	addOpenBorder(
		model,
		"SignBorderAmber",
		baseCF,
		Vector3.new(0, 12.35, borderZ + 0.08),
		size.X + 0.2,
		size.Y + 0.2,
		0.16,
		0.1,
		COLORS.Amber,
		faceFront,
		0.25
	)

	local gui = makeSurfaceGui(sign, "SignGui", 55, true)
	addTextLabel(
		gui,
		"Title",
		titleText,
		UDim2.new(1, -40, 0.58, 0),
		UDim2.new(0, 20, 0.05, 0),
		COLORS.White,
		Enum.Font.GothamBlack,
		COLORS.NavyDeep
	)
	addTextLabel(
		gui,
		"Subtitle",
		subtitleText,
		UDim2.new(1, -48, 0.26, 0),
		UDim2.new(0, 24, 0.64, 0),
		COLORS.AmberSoft,
		Enum.Font.GothamBold,
		COLORS.AmberDeep
	)

	makeLight(sign, COLORS.Cyan, 0.4, 9)
	addBubbleIcon(model, "TopBubbleLogo", Vector3.new(0, 15.35, 0.95), baseCF, 1.25, COLORS.Cyan)
end

local function createBackWall(model: Model, baseCF: CFrame)
	makePart({
		Name = "BackWall",
		Size = Vector3.new(15.5, 7.5, 0.6),
		CFrame = localCF(baseCF, Vector3.new(0, 4.5, -4.2)),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	for _, x in ipairs({ -5.7, 5.7 }) do
		makePart({
			Name = "BackWallAccent_" .. tostring(x),
			Size = Vector3.new(0.2, 6.4, 0.14),
			CFrame = localCF(baseCF, Vector3.new(x, 4.8, -3.86)),
			Color = COLORS.Cyan,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.35,
			Parent = model,
		})
	end
end

local function createCounter(model: Model, baseCF: CFrame)
	local size = DIMS.CounterSize

	-- Counter sits lower and farther forward so the tank remains the focal point.
	makePart({
		Name = "CounterBody",
		Size = size,
		CFrame = localCF(baseCF, Vector3.new(0, 2.15, 1.15)),
		Color = COLORS.Navy,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	makePart({
		Name = "CounterFrontInset",
		Size = Vector3.new(size.X - 1.0, 1.9, 0.42),
		CFrame = localCF(baseCF, Vector3.new(0, 2.2, 3.35)),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})

	local counterTop = makePart({
		Name = "CounterTop",
		Size = Vector3.new(size.X + 0.7, 0.42, size.Z + 0.7),
		CFrame = localCF(baseCF, Vector3.new(0, 3.55, 1.2)),
		Color = COLORS.Blue,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.04,
		Parent = model,
	})

	local counterNeon = makePart({
		Name = "CounterFrontNeon",
		Size = Vector3.new(size.X - 0.5, 0.16, 0.2),
		CFrame = localCF(baseCF, Vector3.new(0, 3.42, 3.45)),
		Color = COLORS.Amber,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.15,
		Parent = model,
	})
	makeLight(counterNeon, COLORS.Amber, 0.3, 7)

	addBubbleIcon(model, "CounterBubbleLogo", Vector3.new(0, 2.15, 3.55), baseCF, 0.95, COLORS.Cyan)

	return counterTop
end

local function attachOpenShopPrompt(anchor: BasePart)
	local shopConfig = Config.Lobby.ItemShop
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenShopPrompt"
	prompt.ActionText = shopConfig.PromptActionText or L10n.OpenShop
	prompt.ObjectText = shopConfig.PromptObjectText or L10n.ShopObject
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = shopConfig.PromptMaxDistance or 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("BPW_OpenShop", true)
	prompt.Parent = anchor
end

local function createShelf(model: Model, baseCF: CFrame, name: string, x: number)
	makePart({
		Name = name .. "_Body",
		Size = Vector3.new(4.0, 5.4, 1.35),
		CFrame = localCF(baseCF, Vector3.new(x, 4.2, -3.15)),
		Color = COLORS.Shelf,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	makePart({
		Name = name .. "_Frame",
		Size = Vector3.new(4.25, 5.65, 0.14),
		CFrame = localCF(baseCF, Vector3.new(x, 4.2, -2.4)),
		Color = COLORS.AmberDeep,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.45,
		Parent = model,
	})

	for i = 1, 3 do
		local y = 2.35 + (i - 1) * 1.5
		makePart({
			Name = name .. "_Shelf" .. tostring(i),
			Size = Vector3.new(3.6, 0.16, 1.1),
			CFrame = localCF(baseCF, Vector3.new(x, y, -2.5)),
			Color = COLORS.Blue,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})

		local productColor = if i == 1 then COLORS.Cyan elseif i == 2 then COLORS.Amber else COLORS.Blue
		makePart({
			Name = name .. "_Product" .. tostring(i),
			Size = Vector3.new(0.65 + i * 0.08, 0.65 + i * 0.08, 0.65 + i * 0.08),
			CFrame = localCF(baseCF, Vector3.new(x + ((i % 2 == 0) and 0.65 or -0.65), y + 0.48, -2.42)),
			Color = productColor,
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Ball,
			Transparency = 0.18,
			CanCollide = false,
			Parent = model,
		})
	end
end

local function createItemsPanel(model: Model, baseCF: CFrame)
	local faceFront = CFrame.Angles(0, math.pi, 0)
	local panelSize = Vector3.new(3.5, 5.2, 0.32)
	local panelZ = -2.2
	local borderZ = panelZ + panelSize.Z / 2 + 0.1

	local panel = makePart({
		Name = "ItemsPanel",
		Size = panelSize,
		CFrame = localCF(baseCF, Vector3.new(5.5, 5.0, panelZ), faceFront),
		Color = COLORS.Panel,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})

	addOpenBorder(
		model,
		"ItemsPanelBorder",
		baseCF,
		Vector3.new(5.5, 5.0, borderZ),
		panelSize.X + 0.35,
		panelSize.Y + 0.35,
		0.22,
		0.12,
		COLORS.Amber,
		faceFront,
		0.2
	)

	local gui = makeSurfaceGui(panel, "ItemsGui", 55, true)
	addTextLabel(
		gui,
		"Title",
		L10n.BubbleItems,
		UDim2.new(1, -16, 0.16, 0),
		UDim2.new(0, 8, 0.04, 0),
		COLORS.AmberSoft,
		Enum.Font.GothamBlack,
		COLORS.AmberDeep
	)

	local lines = { L10n.ItemPotion, L10n.ItemWand, L10n.ItemBoost, L10n.ItemMegaBubble }
	for i, line in ipairs(lines) do
		addTextLabel(
			gui,
			"Line" .. tostring(i),
			line,
			UDim2.new(1, -20, 0.14, 0),
			UDim2.new(0, 10, 0.24 + (i - 1) * 0.17, 0),
			COLORS.White,
			Enum.Font.GothamBold,
			nil
		)
	end
end

local function createBubbleTank(model: Model, baseCF: CFrame): { BubbleData }
	local bubbles: { BubbleData } = {}
	local height = DIMS.TankHeight
	local radius = DIMS.TankRadius
	-- Forward of the counter so it reads clearly from the front approach.
	local tankCenter = Vector3.new(0, 5.35, -0.55)
	local tankCF = localCF(baseCF, tankCenter)

	makePart({
		Name = "TankBase",
		Size = Vector3.new(0.7, radius * 2.55, radius * 2.55),
		CFrame = localCF(baseCF, Vector3.new(tankCenter.X, 1.85, tankCenter.Z), CFrame.Angles(0, 0, math.rad(90))),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Cylinder,
		Parent = model,
	})

	makePart({
		Name = "TankBaseNeon",
		Size = Vector3.new(0.22, radius * 2.3, radius * 2.3),
		CFrame = localCF(baseCF, Vector3.new(tankCenter.X, 2.2, tankCenter.Z), CFrame.Angles(0, 0, math.rad(90))),
		Color = COLORS.Amber,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Transparency = 0.25,
		Parent = model,
	})

	local glass = makePart({
		Name = "BubbleTankGlass",
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = tankCF * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.52,
		Reflectance = 0.08,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = model,
	})

	local glowCore = makePart({
		Name = "TankInnerGlow",
		Size = Vector3.new(height * 0.82, radius * 1.15, radius * 1.15),
		CFrame = tankCF * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.78,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = model,
	})
	makeLight(glowCore, COLORS.Cyan, 0.55, 9)
	makeLight(glass, COLORS.CyanSoft, 0.25, 8)

	makePart({
		Name = "TankTop",
		Size = Vector3.new(0.55, radius * 2.5, radius * 2.5),
		CFrame = localCF(baseCF, Vector3.new(tankCenter.X, 8.7, tankCenter.Z), CFrame.Angles(0, 0, math.rad(90))),
		Color = COLORS.NavyDeep,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = model,
	})

	makePart({
		Name = "TankTopNeon",
		Size = Vector3.new(0.2, radius * 2.28, radius * 2.28),
		CFrame = localCF(baseCF, Vector3.new(tankCenter.X, 8.4, tankCenter.Z), CFrame.Angles(0, 0, math.rad(90))),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Transparency = 0.2,
		Parent = model,
	})

	for i = 1, BUBBLE.Count do
		local diameter = BUBBLE.MinSize + math.random() * (BUBBLE.MaxSize - BUBBLE.MinSize)
		local angle = math.random() * math.pi * 2
		local radial = math.random() * (radius - 0.5)
		local bubble = makePart({
			Name = "TankBubble_" .. tostring(i),
			Size = Vector3.new(diameter, diameter, diameter),
			CFrame = tankCF,
			Color = if i % 4 == 0 then COLORS.AmberSoft elseif i % 3 == 0 then COLORS.CyanSoft else COLORS.Cyan,
			Material = Enum.Material.Glass,
			Transparency = 0.22,
			Reflectance = 0.1,
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			Parent = model,
		})
		table.insert(bubbles, {
			Part = bubble,
			TankCF = tankCF,
			Height = height,
			Radius = radius,
			Speed = BUBBLE.MinSpeed + math.random() * (BUBBLE.MaxSpeed - BUBBLE.MinSpeed),
			Phase = math.random() * height,
			OffsetX = math.cos(angle) * radial,
			OffsetZ = math.sin(angle) * radial,
		})
	end

	return bubbles
end

local function createInterior(model: Model, baseCF: CFrame): { BubbleData }
	createShelf(model, baseCF, "LeftShelf", -5.45)
	createItemsPanel(model, baseCF)
	return createBubbleTank(model, baseCF)
end

local function animateBubbles(model: Model, bubbles: { BubbleData })
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end

		local now = os.clock()
		for _, data in ipairs(bubbles) do
			local travel = (now * data.Speed + data.Phase) % data.Height
			local y = -data.Height / 2 + travel
			local driftX = math.sin(now * 0.8 + data.Phase) * BUBBLE.Drift
			local driftZ = math.cos(now * 0.65 + data.Phase) * BUBBLE.Drift
			data.Part.CFrame = data.TankCF * CFrame.new(
				math.clamp(data.OffsetX + driftX, -data.Radius + 0.3, data.Radius - 0.3),
				y,
				math.clamp(data.OffsetZ + driftZ, -data.Radius + 0.3, data.Radius - 0.3)
			)
		end
	end)
end

local function resolveParent(): Instance
	local world = workspace:FindFirstChild(WORLD_NAME)
	if world then
		local lobby = world:FindFirstChild("Lobby")
		if lobby then
			return lobby
		end
		return world
	end
	return workspace
end

local function clearPrevious(parent: Instance)
	for _, container in ipairs({ parent, workspace }) do
		for _, name in ipairs({ MODEL_NAME, LEGACY_MODEL_NAME }) do
			local existing = container:FindFirstChild(name)
			while existing do
				existing:Destroy()
				existing = container:FindFirstChild(name)
			end
		end
	end
end

local ItemShopBuilder = {}

function ItemShopBuilder.Build(position: Vector3?): Model
	local parent = resolveParent()
	clearPrevious(parent)

	local shopConfig = Config.Lobby.ItemShop
	local origin = position or Config.Lobby.ItemShopPosition
	local baseCF = CFrame.new(origin) * CFrame.Angles(0, math.rad(shopConfig.YawDegrees), 0)

	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	createPlaza(model, baseCF)
	createPillars(model, baseCF)
	local counterTop = createCounter(model, baseCF)
	createRoof(model, baseCF)
	createSign(model, baseCF)
	createBackWall(model, baseCF)
	local bubbles = createInterior(model, baseCF)

	if counterTop then
		attachOpenShopPrompt(counterTop)
	end

	local primary = model:FindFirstChild("ShopFloor")
	if primary and primary:IsA("BasePart") then
		model.PrimaryPart = primary
	end

	model:SetAttribute("BPW_ItemShop", true)
	model.Parent = parent
	animateBubbles(model, bubbles)

	return model
end

function ItemShopBuilder.Start()
	ItemShopBuilder.Build()
end

return ItemShopBuilder
