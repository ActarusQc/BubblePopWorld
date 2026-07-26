--!strict
-- Kiosque de vente de bulles "BubbleShop" : construction + animation 100 % par code.
-- Aucun asset externe (pas d'ImageId, pas de mesh) : uniquement Part + SurfaceGui.

local RunService = game:GetService("RunService")

--------------------------------------------------------------------
-- CONFIGURATION (tout est ajustable ici)
--------------------------------------------------------------------

-- Position au sol du kiosque (le point (0,0,0) local = centre de la dalle du sol).
local SHOP_POSITION = Vector3.new(30, 0, -234)
-- Orientation : la façade (comptoir + pad de vente) regarde vers +Z local.
local SHOP_YAW_DEGREES = -90

local COLORS = {
	Cyan = Color3.fromRGB(0, 217, 255), -- #00D9FF
	Violet = Color3.fromRGB(139, 92, 246), -- #8B5CF6
	RoofDark = Color3.fromRGB(10, 10, 26), -- #0A0A1A
	Gold = Color3.fromRGB(255, 199, 44), -- #FFC72C
	Glass = Color3.fromRGB(170, 225, 255),
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
}

local JAR = {
	OffsetX = -2.5, -- position du bocal dans le kiosque
	OffsetZ = -1.0,
	Radius = 1.7,
	Height = 4.2,
	SocleHeight = 0.9,
	BubbleCount = 14, -- entre 12 et 15
	BubbleSizeMin = 0.3,
	BubbleSizeMax = 0.6,
	FloatSpeedMin = 0.5, -- vitesse d'oscillation verticale (rad/s)
	FloatSpeedMax = 1.1,
	FloatAmplitude = 1.1, -- amplitude verticale (studs)
	DriftSpeedMin = 0.15, -- vitesse de dérive horizontale
	DriftSpeedMax = 0.4,
	DriftAmplitude = 0.55,
}

local PROMPT = {
	ActionText = "Vendre mes bulles",
	ObjectText = "Bubble Shop",
	HoldDuration = 0.5,
	MaxActivationDistance = 8,
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
-- regarde la façade du kiosque (+Z local).
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
-- Structure : piliers + plancher du kiosque
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

	-- Dalle de sol du kiosque (fine, sombre)
	makePart({
		Name = "ShopFloor",
		Size = Vector3.new(DIMS.Width + 1, 0.4, DIMS.Depth + 1),
		CFrame = baseCF * CFrame.new(0, 0.2, 0),
		Color = COLORS.RoofDark,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	for index, offset in ipairs(corners) do
		local pillar = makePart({
			Name = "Pillar_" .. tostring(index),
			Size = Vector3.new(DIMS.PillarHeight, DIMS.PillarDiameter, DIMS.PillarDiameter),
			CFrame = baseCF * CFrame.new(offset + Vector3.new(0, DIMS.PillarHeight / 2, 0)) * UPRIGHT,
			Color = COLORS.Cyan,
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Cylinder,
			Parent = model,
		})
		pillar.CanCollide = true
	end
end

--------------------------------------------------------------------
-- Toit : couvre entièrement les piliers + bordure néon violette
--------------------------------------------------------------------

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
			Color = COLORS.Violet,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
	end

	-- Éclairage d'ambiance sous le toit
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
		Color = COLORS.Violet,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	makeLight(rightGlow, COLORS.Violet, 1.2, 12)
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
		Color = COLORS.Cyan,
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

	local label = Instance.new("TextLabel")
	label.Name = "SignText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "VENDRE LES BULLES"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = COLORS.White
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 40, 70)
	label.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(COLORS.White, COLORS.Cyan)
	gradient.Rotation = 90
	gradient.Parent = label

	makeLight(board, COLORS.Cyan, 1.5, 12)
end

--------------------------------------------------------------------
-- Bocal de bulles animé (élément central)
--------------------------------------------------------------------

type BubbleData = {
	Part: BasePart,
	Radius: number,
	BaseX: number,
	BaseY: number,
	BaseZ: number,
	FloatSpeed: number,
	FloatPhase: number,
	FloatAmp: number,
	DriftSpeed: number,
	DriftPhase: number,
	DriftAmp: number,
}

local function createBubbleJar(model: Model, baseCF: CFrame): (CFrame, { BubbleData })
	local socleY = JAR.SocleHeight / 2 + 0.4
	local socleCF = baseCF * CFrame.new(JAR.OffsetX, socleY, JAR.OffsetZ)

	makePart({
		Name = "JarSocle",
		Size = Vector3.new(JAR.SocleHeight, JAR.Radius * 2.4, JAR.Radius * 2.4),
		CFrame = socleCF * UPRIGHT,
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		Parent = model,
	})

	local jarY = 0.4 + JAR.SocleHeight + JAR.Height / 2
	local jarCF = baseCF * CFrame.new(JAR.OffsetX, jarY, JAR.OffsetZ)

	local jar = makePart({
		Name = "BubbleJar",
		Size = Vector3.new(JAR.Height, JAR.Radius * 2, JAR.Radius * 2),
		CFrame = jarCF * UPRIGHT,
		Color = COLORS.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.5,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = model,
	})
	makeLight(jar, COLORS.Cyan, 1.6, 12)

	-- Couvercle néon violet
	makePart({
		Name = "JarLid",
		Size = Vector3.new(0.3, JAR.Radius * 2.15, JAR.Radius * 2.15),
		CFrame = baseCF * CFrame.new(JAR.OffsetX, jarY + JAR.Height / 2 + 0.15, JAR.OffsetZ) * UPRIGHT,
		Color = COLORS.Violet,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = model,
	})

	local bubblesFolder = Instance.new("Folder")
	bubblesFolder.Name = "JarBubbles"
	bubblesFolder.Parent = model

	local palette = { COLORS.Cyan, COLORS.Violet, COLORS.White }
	local bubbles: { BubbleData } = {}

	for i = 1, JAR.BubbleCount do
		local diameter = JAR.BubbleSizeMin + math.random() * (JAR.BubbleSizeMax - JAR.BubbleSizeMin)
		local radius = diameter / 2
		local maxRadial = math.max(JAR.Radius - radius - 0.15, 0.1)
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * maxRadial * 0.7

		local part = makePart({
			Name = "Bubble_" .. tostring(i),
			Size = Vector3.new(diameter, diameter, diameter),
			CFrame = jarCF,
			Color = palette[((i - 1) % #palette) + 1],
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Ball,
			Transparency = 0.1,
			CanCollide = false,
			Parent = bubblesFolder,
		})

		table.insert(bubbles, {
			Part = part,
			Radius = radius,
			BaseX = math.cos(angle) * distance,
			BaseY = (math.random() - 0.5) * (JAR.Height - diameter - 0.4),
			BaseZ = math.sin(angle) * distance,
			FloatSpeed = JAR.FloatSpeedMin + math.random() * (JAR.FloatSpeedMax - JAR.FloatSpeedMin),
			-- Décalage aléatoire : les bulles ne montent jamais en même temps.
			FloatPhase = math.random() * math.pi * 2,
			FloatAmp = JAR.FloatAmplitude * (0.6 + math.random() * 0.6),
			DriftSpeed = JAR.DriftSpeedMin + math.random() * (JAR.DriftSpeedMax - JAR.DriftSpeedMin),
			DriftPhase = math.random() * math.pi * 2,
			DriftAmp = JAR.DriftAmplitude * (0.5 + math.random() * 0.8),
		})
	end

	return jarCF, bubbles
end

--------------------------------------------------------------------
-- Animation continue des bulles (sinusoïdes manuelles, un seul Heartbeat)
--------------------------------------------------------------------

local function animateBubbles(model: Model, jarCF: CFrame, bubbles: { BubbleData })
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			return
		end

		local t = os.clock()
		for _, data in ipairs(bubbles) do
			local y = data.BaseY + math.sin(t * data.FloatSpeed + data.FloatPhase) * data.FloatAmp
			local x = data.BaseX + math.sin(t * data.DriftSpeed + data.DriftPhase) * data.DriftAmp
			local z = data.BaseZ + math.cos(t * data.DriftSpeed * 0.8 + data.DriftPhase * 1.3) * data.DriftAmp

			-- Confinement dans le cylindre du bocal
			local maxRadial = math.max(JAR.Radius - data.Radius - 0.15, 0.1)
			local radial = math.sqrt(x * x + z * z)
			if radial > maxRadial then
				local scale = maxRadial / radial
				x *= scale
				z *= scale
			end

			local maxY = math.max(JAR.Height / 2 - data.Radius - 0.2, 0.1)
			y = math.clamp(y, -maxY, maxY)

			data.Part.CFrame = jarCF * CFrame.new(x, y, z)
		end
	end)
end

--------------------------------------------------------------------
-- Panneau latéral d'info
--------------------------------------------------------------------

local function createSidePanel(model: Model, baseCF: CFrame)
	local panelCF = baseCF * CFrame.new(0.4, 2.6, JAR.OffsetZ - 0.2) * FACE_FRONT

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
	title.Size = UDim2.new(1, 0, 0.42, 0)
	title.BackgroundTransparency = 1
	title.Text = "Transforme tes bulles en pièces !"
	title.TextWrapped = true
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = COLORS.White
	title.TextStrokeTransparency = 0.4
	title.Parent = frame

	local arrow = Instance.new("TextLabel")
	arrow.Name = "ArrowLabel"
	arrow.Size = UDim2.new(1, 0, 0.26, 0)
	arrow.Position = UDim2.new(0, 0, 0.46, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "⬇"
	arrow.TextScaled = true
	arrow.Font = Enum.Font.GothamBold
	arrow.TextColor3 = COLORS.Cyan
	arrow.Parent = frame

	local coin = Instance.new("TextLabel")
	coin.Name = "CoinLabel"
	coin.Size = UDim2.new(1, 0, 0.26, 0)
	coin.Position = UDim2.new(0, 0, 0.72, 0)
	coin.BackgroundTransparency = 1
	coin.Text = "💰"
	coin.TextScaled = true
	coin.Font = Enum.Font.GothamBold
	coin.TextColor3 = COLORS.Gold
	coin.Parent = frame
end

--------------------------------------------------------------------
-- Comptoir avant + icône pièce
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
		Color = COLORS.Cyan,
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

	-- Mis à jour dynamiquement par le script de vente (référence : "BagValueLabel").
	local label = Instance.new("TextLabel")
	label.Name = "BagValueLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "Valeur du sac : 0 pièces"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = COLORS.White
	label.TextStrokeTransparency = 0.35
	label.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(COLORS.White, COLORS.Cyan)
	gradient.Rotation = 90
	gradient.Parent = label
end

local function createCoinIcon(model: Model, baseCF: CFrame)
	local pillarX = DIMS.Width / 2 - DIMS.PillarDiameter / 2
	local pillarZ = DIMS.Depth / 2 - DIMS.PillarDiameter / 2
	local coinCF = baseCF * CFrame.new(pillarX, 3.4, pillarZ + 0.6) * CFrame.Angles(0, math.rad(90), 0)

	local coin = makePart({
		Name = "CoinIcon",
		Size = Vector3.new(0.2, 1.8, 1.8),
		CFrame = coinCF,
		Color = COLORS.Gold,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Parent = model,
	})

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CoinBillboard"
	billboard.Size = UDim2.fromScale(2, 2)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60
	billboard.Parent = coin

	local symbol = Instance.new("TextLabel")
	symbol.Name = "CoinSymbol"
	symbol.Size = UDim2.fromScale(1, 1)
	symbol.BackgroundTransparency = 1
	symbol.Text = "$"
	symbol.TextScaled = true
	symbol.Font = Enum.Font.GothamBlack
	symbol.TextColor3 = Color3.fromRGB(60, 40, 0)
	symbol.TextStrokeTransparency = 0.6
	symbol.Parent = billboard
end

--------------------------------------------------------------------
-- Plateforme au sol (zone de vente) + ProximityPrompt
--------------------------------------------------------------------

local function createFloorPad(model: Model, baseCF: CFrame)
	local padZ = DIMS.Depth / 2 + 2.4

	local pad = makePart({
		Name = "SellPad",
		Size = Vector3.new(7, 0.2, 4.5),
		CFrame = baseCF * CFrame.new(0, 0.1, padZ),
		Color = COLORS.Cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		Parent = model,
	})
	makeLight(pad, COLORS.Cyan, 1, 10)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = PROMPT.ActionText
	prompt.ObjectText = PROMPT.ObjectText
	prompt.HoldDuration = PROMPT.HoldDuration
	prompt.MaxActivationDistance = PROMPT.MaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	-- TODO: brancher RemoteEvent SellBubbles ici
end

--------------------------------------------------------------------
-- API
--------------------------------------------------------------------

local BubbleShopBuilder = {}

function BubbleShopBuilder.Build(position: Vector3?): Model
	local existing = workspace:FindFirstChild("BubbleShop")
	if existing then
		existing:Destroy()
	end

	local origin = position or SHOP_POSITION
	local baseCF = CFrame.new(origin) * CFrame.Angles(0, math.rad(SHOP_YAW_DEGREES), 0)

	local model = Instance.new("Model")
	model.Name = "BubbleShop"

	createStructure(model, baseCF)
	createRoof(model, baseCF)
	createSign(model, baseCF)
	local jarCF, bubbles = createBubbleJar(model, baseCF)
	createSidePanel(model, baseCF)
	createCounter(model, baseCF)
	createCoinIcon(model, baseCF)
	createFloorPad(model, baseCF)

	local primary = model:FindFirstChild("ShopFloor")
	if primary and primary:IsA("BasePart") then
		model.PrimaryPart = primary
	end
	model.Parent = workspace

	animateBubbles(model, jarCF, bubbles)
	return model
end

function BubbleShopBuilder.Start()
	BubbleShopBuilder.Build()
end

return BubbleShopBuilder
