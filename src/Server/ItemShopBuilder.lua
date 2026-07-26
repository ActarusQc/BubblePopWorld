--!strict
-- Boutique d'items "ItemShop" : construction + animation 100 % par code.
-- Aucun asset externe (pas d'ImageId, pas de mesh) : uniquement Part + SurfaceGui.
--
-- Rôle : acheter des items plus tard. Ce bâtiment ne vend JAMAIS de bulles :
-- il n'a ni SellZone, ni SellPad, ni ProximityPrompt, et ne référence pas
-- BackpackService. Le kiosque de vente des bulles reste géré par ZoneService.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)

local MODEL_NAME = "ItemShop"
local LEGACY_MODEL_NAME = "BubbleShop"
local WORLD_NAME = "BubblePopWorld"

--------------------------------------------------------------------
-- CONFIGURATION (tout est ajustable ici)
--------------------------------------------------------------------

local COLORS = {
	Magenta = Color3.fromRGB(255, 60, 190),
	MagentaDeep = Color3.fromRGB(185, 25, 135),
	Cyan = Color3.fromRGB(0, 217, 255),
	CyanDeep = Color3.fromRGB(0, 130, 190),
	RoofDark = Color3.fromRGB(10, 10, 26),
	Gold = Color3.fromRGB(255, 199, 44),
	Glass = Color3.fromRGB(190, 225, 255),
	PanelDeep = Color3.fromRGB(8, 18, 55),
	White = Color3.fromRGB(255, 255, 255),
}

local DIMS = {
	Width = 10, -- écartement des piliers sur X
	Depth = 8, -- écartement des piliers sur Z
	PillarHeight = 5,
	PillarDiameter = 0.9,
	RoofThickness = 0.5,
	RoofOverhang = 1.2, -- débord du toit au-delà des piliers
	RoofTiltDegrees = 4,
	BorderThickness = 0.22,
	AwningSlats = 9, -- lamelles magenta/blanches de l'auvent
	AwningDrop = 1.5,
}

local CASE = {
	OffsetX = -2.5,
	OffsetZ = -1.0,
	Radius = 1.7,
	Height = 4.2,
	SocleHeight = 0.9,
	OrbCount = 8,
	OrbSizeMin = 0.45,
	OrbSizeMax = 0.85,
	FloatSpeedMin = 0.4,
	FloatSpeedMax = 0.9,
	FloatAmplitude = 0.9,
	SpinSpeedMin = 0.6,
	SpinSpeedMax = 1.4,
	OrbitRadius = 0.75,
}

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------

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

-- Un cylindre Roblox a son axe sur X : cette rotation le redresse à la verticale.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
-- La face "Front" d'une Part pointe vers son -Z : on retourne la part pour qu'elle
-- regarde la façade de la boutique (+Z local).
local FACE_FRONT = CFrame.Angles(0, math.pi, 0)

local function makeSurfaceGui(host: BasePart, name: string, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = host
	return gui
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

--------------------------------------------------------------------
-- Structure : piliers + plancher de la boutique
--------------------------------------------------------------------

local function createStructure(model: Model, baseCF: CFrame)
	local halfW = DIMS.Width / 2 - DIMS.PillarDiameter / 2
	local halfD = DIMS.Depth / 2 - DIMS.PillarDiameter / 2
	local corners = {
		Vector3.new(-halfW, 0, -halfD),
		Vector3.new(halfW, 0, -halfD),
		Vector3.new(-halfW, 0, halfD),
		Vector3.new(halfW, 0, halfD),
	}

	makePart({
		Name = "ShopFloor",
		Size = Vector3.new(DIMS.Width + 1, 0.4, DIMS.Depth + 1),
		CFrame = baseCF * CFrame.new(0, 0.2, 0),
		Color = COLORS.RoofDark,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	for index, offset in ipairs(corners) do
		makePart({
			Name = "Pillar_" .. tostring(index),
			Size = Vector3.new(DIMS.PillarHeight, DIMS.PillarDiameter, DIMS.PillarDiameter),
			CFrame = baseCF * CFrame.new(offset + Vector3.new(0, DIMS.PillarHeight / 2, 0)) * UPRIGHT,
			Color = COLORS.Cyan,
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Cylinder,
			Parent = model,
		})
	end
end

--------------------------------------------------------------------
-- Toit + auvent magenta rayé (identité visuelle de la boutique d'items)
--------------------------------------------------------------------

local function createAwning(model: Model, roofCF: CFrame, roofWidth: number, roofDepth: number)
	local slatWidth = roofWidth / DIMS.AwningSlats
	local awningCF = roofCF
		* CFrame.new(0, -DIMS.AwningDrop / 2, roofDepth / 2 + 0.3)
		* CFrame.Angles(math.rad(-38), 0, 0)

	for i = 1, DIMS.AwningSlats do
		local x = -roofWidth / 2 + (i - 0.5) * slatWidth
		makePart({
			Name = "AwningSlat_" .. tostring(i),
			Size = Vector3.new(slatWidth, 0.25, DIMS.AwningDrop * 1.6),
			CFrame = awningCF * CFrame.new(x, 0, 0),
			Color = if i % 2 == 0 then COLORS.White else COLORS.Magenta,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = model,
		})
	end

	local lip = makePart({
		Name = "AwningLip",
		Size = Vector3.new(roofWidth + DIMS.BorderThickness, 0.3, 0.3),
		CFrame = awningCF * CFrame.new(0, 0.05, DIMS.AwningDrop * 0.8),
		Color = COLORS.Magenta,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	makeLight(lip, COLORS.Magenta, 1.6, 16)
end

local function createRoof(model: Model, baseCF: CFrame)
	local roofWidth = DIMS.Width + DIMS.RoofOverhang
	local roofDepth = DIMS.Depth + DIMS.RoofOverhang
	local roofY = DIMS.PillarHeight + DIMS.RoofThickness / 2
	local roofCF = baseCF * CFrame.new(0, roofY, 0) * CFrame.Angles(math.rad(DIMS.RoofTiltDegrees), 0, 0)

	makePart({
		Name = "Roof",
		Size = Vector3.new(roofWidth, DIMS.RoofThickness, roofDepth),
		CFrame = roofCF,
		Color = COLORS.RoofDark,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	local b = DIMS.BorderThickness
	local edges: { { name: string, size: Vector3, offset: Vector3 } } = {
		{
			name = "RoofBorder_Front",
			size = Vector3.new(roofWidth + b, DIMS.RoofThickness * 1.05, b),
			offset = Vector3.new(0, 0, roofDepth / 2),
		},
		{
			name = "RoofBorder_Back",
			size = Vector3.new(roofWidth + b, DIMS.RoofThickness * 1.05, b),
			offset = Vector3.new(0, 0, -roofDepth / 2),
		},
		{
			name = "RoofBorder_Left",
			size = Vector3.new(b, DIMS.RoofThickness * 1.05, roofDepth + b),
			offset = Vector3.new(-roofWidth / 2, 0, 0),
		},
		{
			name = "RoofBorder_Right",
			size = Vector3.new(b, DIMS.RoofThickness * 1.05, roofDepth + b),
			offset = Vector3.new(roofWidth / 2, 0, 0),
		},
	}

	for _, edge in ipairs(edges) do
		makePart({
			Name = edge.name,
			Size = edge.size,
			CFrame = roofCF * CFrame.new(edge.offset),
			Color = COLORS.Magenta,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
	end

	createAwning(model, roofCF, roofWidth, roofDepth)

	local leftGlow = makePart({
		Name = "RoofLight_Left",
		Size = Vector3.new(0.4, 0.2, 0.4),
		CFrame = roofCF * CFrame.new(-3, -0.6, 0),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	makeLight(leftGlow, COLORS.Cyan, 1.4, 14)

	local rightGlow = makePart({
		Name = "RoofLight_Right",
		Size = Vector3.new(0.4, 0.2, 0.4),
		CFrame = roofCF * CFrame.new(3, -0.6, 0),
		Color = COLORS.Magenta,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	makeLight(rightGlow, COLORS.Magenta, 1.3, 13)
end

--------------------------------------------------------------------
-- Enseigne au sommet du toit
--------------------------------------------------------------------

local function createSign(model: Model, baseCF: CFrame)
	local signY = DIMS.PillarHeight + DIMS.RoofThickness + 1.35
	local signCF = baseCF * CFrame.new(0, signY, 0) * FACE_FRONT

	makePart({
		Name = "SignBorder",
		Size = Vector3.new(8.2, 2.9, 0.22),
		CFrame = signCF * CFrame.new(0, 0, -0.12),
		Color = COLORS.Magenta,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})

	local board = makePart({
		Name = "SignBoard",
		Size = Vector3.new(7.8, 2.5, 0.3),
		CFrame = signCF,
		Color = COLORS.PanelDeep,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})

	local gui = makeSurfaceGui(board, "SignGui", 80)

	local frame = Instance.new("Frame")
	frame.Name = "Content"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "SignText"
	title.Size = UDim2.new(1, 0, 0.62, 0)
	title.BackgroundTransparency = 1
	title.Text = Config.Lobby.ItemShop.SignText
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = COLORS.White
	title.TextStrokeTransparency = 0
	title.TextStrokeColor3 = Color3.fromRGB(70, 0, 50)
	title.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(COLORS.White, COLORS.Magenta)
	gradient.Rotation = 90
	gradient.Parent = title

	local tagline = Instance.new("TextLabel")
	tagline.Name = "TaglineText"
	tagline.Size = UDim2.new(1, 0, 0.3, 0)
	tagline.Position = UDim2.new(0, 0, 0.64, 0)
	tagline.BackgroundTransparency = 1
	tagline.Text = Config.Lobby.ItemShop.TaglineText
	tagline.Font = Enum.Font.GothamBold
	tagline.TextScaled = true
	tagline.TextColor3 = COLORS.Cyan
	tagline.Parent = frame

	makeLight(board, COLORS.Magenta, 1.5, 12)
end

--------------------------------------------------------------------
-- Vitrine animée (élément central)
--------------------------------------------------------------------

type OrbData = {
	Part: BasePart,
	BaseY: number,
	OrbitPhase: number,
	FloatSpeed: number,
	FloatPhase: number,
	FloatAmp: number,
	SpinSpeed: number,
}

local function createDisplayCase(model: Model, baseCF: CFrame): (CFrame, { OrbData })
	local socleY = CASE.SocleHeight / 2 + 0.4
	local socleCF = baseCF * CFrame.new(CASE.OffsetX, socleY, CASE.OffsetZ)

	makePart({
		Name = "CaseSocle",
		Size = Vector3.new(CASE.SocleHeight, CASE.Radius * 2.4, CASE.Radius * 2.4),
		CFrame = socleCF * UPRIGHT,
		Color = COLORS.Magenta,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		Parent = model,
	})

	local caseY = 0.4 + CASE.SocleHeight + CASE.Height / 2
	local caseCF = baseCF * CFrame.new(CASE.OffsetX, caseY, CASE.OffsetZ)

	local glass = makePart({
		Name = "DisplayCase",
		Size = Vector3.new(CASE.Height, CASE.Radius * 2, CASE.Radius * 2),
		CFrame = caseCF * UPRIGHT,
		Color = COLORS.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.55,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = model,
	})
	makeLight(glass, COLORS.Magenta, 1.6, 12)

	makePart({
		Name = "CaseLid",
		Size = Vector3.new(0.3, CASE.Radius * 2.15, CASE.Radius * 2.15),
		CFrame = baseCF * CFrame.new(CASE.OffsetX, caseY + CASE.Height / 2 + 0.15, CASE.OffsetZ) * UPRIGHT,
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = model,
	})

	local orbsFolder = Instance.new("Folder")
	orbsFolder.Name = "DisplayOrbs"
	orbsFolder.Parent = model

	local palette = { COLORS.Gold, COLORS.Magenta, COLORS.Cyan }
	local orbs: { OrbData } = {}

	for i = 1, CASE.OrbCount do
		local diameter = CASE.OrbSizeMin + math.random() * (CASE.OrbSizeMax - CASE.OrbSizeMin)

		local part = makePart({
			Name = "ItemOrb_" .. tostring(i),
			Size = Vector3.new(diameter, diameter, diameter),
			CFrame = caseCF,
			Color = palette[((i - 1) % #palette) + 1],
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Ball,
			Transparency = 0.1,
			CanCollide = false,
			Parent = orbsFolder,
		})

		table.insert(orbs, {
			Part = part,
			BaseY = (i / CASE.OrbCount - 0.5) * (CASE.Height - diameter - 0.6),
			OrbitPhase = (i / CASE.OrbCount) * math.pi * 2,
			FloatSpeed = CASE.FloatSpeedMin + math.random() * (CASE.FloatSpeedMax - CASE.FloatSpeedMin),
			-- Décalage aléatoire : les items ne montent jamais en même temps.
			FloatPhase = math.random() * math.pi * 2,
			FloatAmp = CASE.FloatAmplitude * (0.5 + math.random() * 0.6),
			SpinSpeed = CASE.SpinSpeedMin + math.random() * (CASE.SpinSpeedMax - CASE.SpinSpeedMin),
		})
	end

	return caseCF, orbs
end

--------------------------------------------------------------------
-- Animation continue de la vitrine (un seul Heartbeat)
--------------------------------------------------------------------

local function animateOrbs(model: Model, caseCF: CFrame, orbs: { OrbData })
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end

		local t = os.clock()
		for _, data in ipairs(orbs) do
			local angle = data.OrbitPhase + t * data.SpinSpeed * 0.5
			local x = math.cos(angle) * CASE.OrbitRadius
			local z = math.sin(angle) * CASE.OrbitRadius
			local y = data.BaseY + math.sin(t * data.FloatSpeed + data.FloatPhase) * data.FloatAmp

			local maxY = math.max(CASE.Height / 2 - data.Part.Size.Y / 2 - 0.2, 0.1)
			y = math.clamp(y, -maxY, maxY)

			data.Part.CFrame = caseCF * CFrame.new(x, y, z) * CFrame.Angles(0, t * data.SpinSpeed, 0)
		end
	end)
end

--------------------------------------------------------------------
-- Panneau latéral d'info
--------------------------------------------------------------------

local function createSidePanel(model: Model, baseCF: CFrame)
	local panelCF = baseCF * CFrame.new(0.4, 2.6, CASE.OffsetZ - 0.2) * FACE_FRONT

	local panel = makePart({
		Name = "SidePanel",
		Size = Vector3.new(2.6, 3.6, 0.25),
		CFrame = panelCF,
		Color = COLORS.PanelDeep,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})

	local gui = makeSurfaceGui(panel, "SidePanelGui", 70)

	local frame = Instance.new("Frame")
	frame.Name = "Content"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.06, 0)
	padding.PaddingBottom = UDim.new(0.06, 0)
	padding.PaddingLeft = UDim.new(0.08, 0)
	padding.PaddingRight = UDim.new(0.08, 0)
	padding.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "SidePanelText"
	title.Size = UDim2.new(1, 0, 0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "Gear, skins and boosts are on the way!"
	title.TextWrapped = true
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = COLORS.White
	title.TextStrokeTransparency = 0.4
	title.Parent = frame

	local badge = Instance.new("TextLabel")
	badge.Name = "BadgeLabel"
	badge.Size = UDim2.new(1, 0, 0.4, 0)
	badge.Position = UDim2.new(0, 0, 0.55, 0)
	badge.BackgroundTransparency = 1
	badge.Text = "COMING SOON"
	badge.TextWrapped = true
	badge.TextScaled = true
	badge.Font = Enum.Font.GothamBlack
	badge.TextColor3 = COLORS.Magenta
	badge.Parent = frame
end

--------------------------------------------------------------------
-- Comptoir avant
--------------------------------------------------------------------

local function createCounter(model: Model, baseCF: CFrame)
	local counterZ = DIMS.Depth / 2 - 0.6
	local counterCF = baseCF * CFrame.new(0, 1.5, counterZ)

	makePart({
		Name = "CounterBody",
		Size = Vector3.new(DIMS.Width - 1.6, 3, 0.8),
		CFrame = counterCF,
		Color = COLORS.RoofDark,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	makePart({
		Name = "CounterTop",
		Size = Vector3.new(DIMS.Width - 1.4, 0.18, 1.1),
		CFrame = counterCF * CFrame.new(0, 1.6, 0),
		Color = COLORS.Magenta,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})

	local board = makePart({
		Name = "CounterDisplay",
		Size = Vector3.new(DIMS.Width - 2.4, 1.5, 0.2),
		CFrame = counterCF * CFrame.new(0, 0.2, 0.45) * FACE_FRONT,
		Color = COLORS.PanelDeep,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})

	local gui = makeSurfaceGui(board, "CounterGui", 80)

	local label = Instance.new("TextLabel")
	label.Name = "CounterText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "COMING SOON"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = COLORS.White
	label.TextStrokeTransparency = 0.35
	label.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(COLORS.White, COLORS.Magenta)
	gradient.Rotation = 90
	gradient.Parent = label
end

--------------------------------------------------------------------
-- Tapis d'accueil (décor uniquement : aucun prompt, aucune vente)
--------------------------------------------------------------------

local function createWelcomeMat(model: Model, baseCF: CFrame)
	local matZ = DIMS.Depth / 2 + 2.4

	local mat = makePart({
		Name = "WelcomeMat",
		Size = Vector3.new(7, 0.2, 4.5),
		CFrame = baseCF * CFrame.new(0, 0.1, matZ),
		Color = COLORS.Magenta,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		Parent = model,
	})
	makeLight(mat, COLORS.Magenta, 1, 10)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MatBillboard"
	billboard.Size = UDim2.fromScale(7, 1.6)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 70
	billboard.Parent = mat

	local text = Instance.new("TextLabel")
	text.Name = "MatText"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "COMING SOON"
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = COLORS.White
	text.TextStrokeTransparency = 0.2
	text.TextStrokeColor3 = Color3.fromRGB(70, 0, 50)
	text.Parent = billboard
end

--------------------------------------------------------------------
-- Emplacement
--------------------------------------------------------------------

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

-- Supprime la boutique précédente et l'ancien "BubbleShop" (kiosque de vente
-- dupliqué, remplacé par cette boutique d'items).
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

--------------------------------------------------------------------
-- API
--------------------------------------------------------------------

local ItemShopBuilder = {}

function ItemShopBuilder.Build(position: Vector3?): Model
	local parent = resolveParent()
	clearPrevious(parent)

	local shop = Config.Lobby.ItemShop
	local origin = position or Config.Lobby.ItemShopPosition
	local baseCF = CFrame.new(origin) * CFrame.Angles(0, math.rad(shop.YawDegrees), 0)

	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	createStructure(model, baseCF)
	createRoof(model, baseCF)
	createSign(model, baseCF)
	local caseCF, orbs = createDisplayCase(model, baseCF)
	createSidePanel(model, baseCF)
	createCounter(model, baseCF)
	createWelcomeMat(model, baseCF)

	local primary = model:FindFirstChild("ShopFloor")
	if primary and primary:IsA("BasePart") then
		model.PrimaryPart = primary
	end
	model:SetAttribute("BPW_ItemShop", true)
	model.Parent = parent

	animateOrbs(model, caseCF, orbs)
	return model
end

function ItemShopBuilder.Start()
	ItemShopBuilder.Build()
end

return ItemShopBuilder
