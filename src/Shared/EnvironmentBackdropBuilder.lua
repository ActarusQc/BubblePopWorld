--!strict
-- Génère un décor 360° de vallée montagneuse autour du plateau jouable.
-- Idempotent : remplace uniquement Workspace.GeneratedWorld.EnvironmentBackdrop.
-- Décoratif uniquement (pas de collision, pas de scripts runtime).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.EnvironmentBackdropConfig)

local EnvironmentBackdropBuilder = {}

local GENERATED_FOLDER = "GeneratedWorld"
local MODEL_NAME = "EnvironmentBackdrop"

local function createRng(seed: number): () -> number
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state = 1
	end
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

local function pickColor(rng: () -> number, colors: { Color3 }): Color3
	local index = math.clamp(math.floor(rng() * #colors) + 1, 1, #colors)
	return colors[index]
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function decorateBase(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
end

local function makeBlock(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Shape = Enum.PartType.Block
	decorateBase(part)
	part.Parent = parent
	return part
end

local function makeWedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cf
	wedge.Color = color
	decorateBase(wedge)
	wedge.Parent = parent
	return wedge
end

local function makeCylinder(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Shape = Enum.PartType.Cylinder
	decorateBase(part)
	part.Parent = parent
	return part
end

local function ensureGeneratedFolder(): Folder
	local existing = workspace:FindFirstChild(GENERATED_FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = GENERATED_FOLDER
	folder.Parent = workspace
	return folder
end

local function clearPreviousBackdrop(generated: Folder)
	local previous = generated:FindFirstChild(MODEL_NAME)
	if previous then
		previous:Destroy()
	end
end

local function ringPlacement(
	rng: () -> number,
	index: number,
	count: number,
	radiusMin: number,
	radiusMax: number
): (number, number)
	local baseAngle = ((index - 1) / count) * math.pi * 2
	local jitter = (rng() - 0.5) * ((math.pi * 2) / count) * 0.55
	local angle = baseAngle + jitter
	local radius = lerp(radiusMin, radiusMax, rng())
	return angle, radius
end

local function buildMountain(
	folder: Folder,
	namePrefix: string,
	center: Vector3,
	groundY: number,
	angle: number,
	radius: number,
	height: number,
	width: number,
	depth: number,
	color: Color3,
	yawJitter: number,
	snowColor: Color3?,
	withSnow: boolean
)
	local x = center.X + math.cos(angle) * radius
	local z = center.Z + math.sin(angle) * radius
	local yaw = angle + math.pi / 2 + yawJitter
	local baseCF = CFrame.new(x, groundY + height * 0.22, z) * CFrame.Angles(0, yaw, 0)

	makeBlock(
		folder,
		namePrefix .. "_Base",
		Vector3.new(width * 0.95, height * 0.45, depth * 0.9),
		baseCF,
		color
	)

	local peakHeight = height * 0.7
	local peakCF = CFrame.new(x, groundY + height * 0.45 + peakHeight / 2, z)
		* CFrame.Angles(0, yaw + 0.12, 0)
	makeWedge(
		folder,
		namePrefix .. "_PeakA",
		Vector3.new(depth * 0.85, peakHeight, width * 0.72),
		peakCF,
		color
	)

	local peakBHeight = height * lerp(0.35, 0.55, math.abs(math.sin(angle * 3)))
	local sideOffset = CFrame.new(x, groundY + height * 0.38 + peakBHeight / 2, z)
		* CFrame.Angles(0, yaw - 0.55, 0)
		* CFrame.new(width * 0.18, 0, 0)
	makeWedge(
		folder,
		namePrefix .. "_PeakB",
		Vector3.new(depth * 0.55, peakBHeight, width * 0.42),
		sideOffset,
		color
	)

	if withSnow and snowColor then
		local snowH = height * 0.18
		local snowCF = CFrame.new(x, groundY + height * 0.82 + snowH / 2, z)
			* CFrame.Angles(0, yaw + 0.08, 0)
		makeWedge(
			folder,
			namePrefix .. "_Snow",
			Vector3.new(depth * 0.42, snowH, width * 0.38),
			snowCF,
			snowColor
		)
	end
end

local function buildMountainLayer(
	parent: Folder,
	layerName: string,
	rng: () -> number,
	center: Vector3,
	groundY: number,
	layer: {
		RadiusMin: number,
		RadiusMax: number,
		Count: number,
		HeightMin: number,
		HeightMax: number,
		WidthMin: number,
		WidthMax: number,
		DepthMin: number,
		DepthMax: number,
		Colors: { Color3 },
		SnowCapChance: number?,
		SnowColor: Color3?,
		SkipIndices: { number }?,
	}
)
	local folder = Instance.new("Folder")
	folder.Name = layerName
	folder.Parent = parent

	local skip: { [number]: boolean } = {}
	if layer.SkipIndices then
		for _, idx in ipairs(layer.SkipIndices) do
			skip[idx] = true
		end
	end

	for i = 1, layer.Count do
		local angle, radius = ringPlacement(rng, i, layer.Count, layer.RadiusMin, layer.RadiusMax)
		local height = lerp(layer.HeightMin, layer.HeightMax, rng())
		local width = lerp(layer.WidthMin, layer.WidthMax, rng())
		local depth = lerp(layer.DepthMin, layer.DepthMax, rng())
		local color = pickColor(rng, layer.Colors)
		local yawJitter = (rng() - 0.5) * 0.7
		local snowChance = layer.SnowCapChance or 0
		local withSnow = snowChance > 0 and rng() < snowChance
		-- Consomme le RNG même si skip → le reste de l'horizon reste identique.
		if not skip[i] then
			buildMountain(
				folder,
				string.format("%s_%02d", layerName, i),
				center,
				groundY,
				angle,
				radius,
				height,
				width,
				depth,
				color,
				yawJitter,
				layer.SnowColor,
				withSnow
			)
		end
	end
end

local function buildGroundBand(parent: Folder, rng: () -> number, center: Vector3, groundY: number)
	local cfg = Config.GroundBand
	local folder = Instance.new("Folder")
	folder.Name = "GroundBand"
	folder.Parent = parent

	for i = 1, cfg.SegmentCount do
		local angle, radius = ringPlacement(rng, i, cfg.SegmentCount, cfg.RadiusMin, cfg.RadiusMax)
		local width = lerp(cfg.WidthMin, cfg.WidthMax, rng())
		local length = lerp(55, 95, rng())
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local yaw = angle + math.pi / 2 + (rng() - 0.5) * 0.35
		makeBlock(
			folder,
			string.format("Ground_%02d", i),
			Vector3.new(width, cfg.Thickness, length),
			CFrame.new(x, groundY + cfg.Thickness * 0.35, z) * CFrame.Angles(0, yaw, 0),
			pickColor(rng, cfg.BaseColors)
		)
	end

	for i = 1, cfg.HillCount do
		local angle, radius = ringPlacement(rng, i, cfg.HillCount, cfg.RadiusMin + 20, cfg.RadiusMax - 10)
		local h = lerp(cfg.HillHeightMin, cfg.HillHeightMax, rng())
		local w = lerp(28, 55, rng())
		local d = lerp(22, 40, rng())
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local yaw = angle + math.pi / 2 + (rng() - 0.5) * 0.5
		makeWedge(
			folder,
			string.format("Hill_%02d", i),
			Vector3.new(d, h, w),
			CFrame.new(x, groundY + h * 0.5, z) * CFrame.Angles(0, yaw, 0),
			pickColor(rng, cfg.Colors)
		)
	end

	for i = 1, cfg.RockCount do
		local angle, radius = ringPlacement(rng, i, cfg.RockCount, cfg.RadiusMin + 10, cfg.RadiusMax + 30)
		local size = lerp(4, 12, rng())
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		makeBlock(
			folder,
			string.format("Rock_%02d", i),
			Vector3.new(size * lerp(0.8, 1.4, rng()), size * lerp(0.5, 1.1, rng()), size * lerp(0.7, 1.3, rng())),
			CFrame.new(x, groundY + size * 0.35, z)
				* CFrame.Angles(rng() * 0.4, rng() * math.pi * 2, rng() * 0.35),
			pickColor(rng, cfg.RockColors)
		)
	end
end

local function buildTree(parent: Folder, name: string, position: Vector3, scale: number, rng: () -> number)
	local cfg = Config.Trees
	local trunkH = 4.5 * scale
	local trunkR = 0.55 * scale
	-- Cylinder axis = X ; on oriente vers Y.
	makeCylinder(
		parent,
		name .. "_Trunk",
		Vector3.new(trunkH, trunkR * 2, trunkR * 2),
		CFrame.new(position + Vector3.new(0, trunkH * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		cfg.TrunkColor
	)

	local foliageColor = pickColor(rng, cfg.FoliageColors)
	local baseY = position.Y + trunkH * 0.55
	for layer = 1, 3 do
		local t = (layer - 1) / 2
		local diameter = lerp(5.2, 2.2, t) * scale
		local height = lerp(3.2, 2.4, t) * scale
		local y = baseY + layer * (2.1 * scale) - height * 0.25
		makeCylinder(
			parent,
			string.format("%s_Foliage%d", name, layer),
			Vector3.new(height, diameter, diameter),
			CFrame.new(position.X, y, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
			foliageColor
		)
	end
end

local function buildTrees(parent: Folder, rng: () -> number, center: Vector3, groundY: number)
	local cfg = Config.Trees
	local folder = Instance.new("Folder")
	folder.Name = "TreeClusters"
	folder.Parent = parent

	for c = 1, cfg.ClusterCount do
		local angle, radius = ringPlacement(rng, c, cfg.ClusterCount, cfg.RadiusMin, cfg.RadiusMax)
		local clusterX = center.X + math.cos(angle) * radius
		local clusterZ = center.Z + math.sin(angle) * radius
		local clusterFolder = Instance.new("Folder")
		clusterFolder.Name = string.format("Cluster_%02d", c)
		clusterFolder.Parent = folder

		local treeCount = math.floor(lerp(cfg.TreesPerClusterMin, cfg.TreesPerClusterMax + 0.999, rng()))
		for t = 1, treeCount do
			local ox = (rng() - 0.5) * 18
			local oz = (rng() - 0.5) * 18
			local scale = lerp(0.85, 1.45, rng())
			buildTree(
				clusterFolder,
				string.format("Tree_%d", t),
				Vector3.new(clusterX + ox, groundY, clusterZ + oz),
				scale,
				rng
			)
		end
	end
end

local function countBaseParts(root: Instance): number
	local n = 0
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

function EnvironmentBackdropBuilder.Build(): Model
	local rng = createRng(Config.Seed)
	local center = Config.WorldCenter
	local groundY = Config.GroundY

	local generated = ensureGeneratedFolder()
	clearPreviousBackdrop(generated)

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("GeneratedByCode", true)
	model:SetAttribute("EnvironmentBackdropSeed", Config.Seed)

	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)

	buildGroundBand(model, rng, center, groundY)
	buildMountainLayer(model, "Foothills", rng, center, groundY, Config.Foothills)
	buildMountainLayer(model, "MainMountains", rng, center, groundY, Config.MainMountains)
	buildMountainLayer(model, "FarPeaks", rng, center, groundY, Config.FarPeaks)
	buildTrees(model, rng, center, groundY)

	model.Parent = generated
	model:SetAttribute("PartCount", countBaseParts(model))
	return model
end

function EnvironmentBackdropBuilder.ApplyAtmosphere(worldSky: Color3?)
	local Lighting = game:GetService("Lighting")
	local atm = Config.Atmosphere
	local light = Config.Lighting

	for _, item in ipairs(Lighting:GetChildren()) do
		if item:IsA("Atmosphere") then
			item:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "EnvironmentBackdropAtmosphere"
	atmosphere.Density = atm.Density
	atmosphere.Offset = atm.Offset
	atmosphere.Haze = atm.Haze
	atmosphere.Glare = atm.Glare
	atmosphere.Color = atm.Color
	atmosphere.Decay = atm.Decay
	atmosphere.Parent = Lighting

	Lighting.FogStart = atm.FogStart
	Lighting.FogEnd = atm.FogEnd
	Lighting.Brightness = light.Brightness
	Lighting.Ambient = light.Ambient
	Lighting.EnvironmentDiffuseScale = light.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = light.EnvironmentSpecularScale
	Lighting.ColorShift_Top = light.ColorShift_Top
	Lighting.ColorShift_Bottom = light.ColorShift_Bottom

	if worldSky then
		local blend = light.OutdoorAmbientBlend
		Lighting.OutdoorAmbient = worldSky:Lerp(light.OutdoorAmbientTint, blend)
	else
		Lighting.OutdoorAmbient = light.OutdoorAmbientTint
	end
end

return EnvironmentBackdropBuilder
