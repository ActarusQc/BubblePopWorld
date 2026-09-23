--!strict
-- Génère un décor 360° d'horizon océan / îlots / nuages (pas de montagnes).
-- Idempotent : remplace uniquement Workspace.GeneratedWorld.EnvironmentBackdrop.
-- Décoratif uniquement (pas de collision, CastShadow = false).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.EnvironmentBackdropConfig)
local ZoneDefs = require(Shared.ZoneDefs)

local EnvironmentBackdropBuilder = {}

local GENERATED_FOLDER = "GeneratedWorld"
local MODEL_NAME = "EnvironmentBackdrop"

local function overlapsSummerZone(x: number, z: number, halfExtentX: number, halfExtentZ: number): boolean
	local sb = ZoneDefs.GetZoneBounds("SummerZone")
	if not sb then
		return false
	end
	local pad = Config.SummerExclusionPad or 12
	local minX = sb.MinX - pad
	local maxX = sb.MaxX + pad
	local minZ = sb.MinZ - pad
	local maxZ = sb.MaxZ + pad
	return not (x + halfExtentX < minX or x - halfExtentX > maxX or z + halfExtentZ < minZ or z - halfExtentZ > maxZ)
end

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
	part.CastShadow = false -- jamais d'ombre de décor sur le plateau de jeu
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = 0
end

local function makeBlock(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Shape = Enum.PartType.Block
	part.Transparency = transparency or 0
	decorateBase(part)
	part.Parent = parent
	return part
end

local function makeBall(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, transparency: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = cf
	part.Color = color
	part.Transparency = transparency or 0.15
	decorateBase(part)
	part.Parent = parent
	return part
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
	local jitter = (rng() - 0.5) * ((math.pi * 2) / count) * 0.45
	local angle = baseAngle + jitter
	local radius = lerp(radiusMin, radiusMax, rng())
	return angle, radius
end

local function buildOcean(parent: Folder, rng: () -> number, center: Vector3, seaY: number)
	local cfg = Config.Ocean
	local folder = Instance.new("Folder")
	folder.Name = "Ocean"
	folder.Parent = parent

	for ring = 1, cfg.RingCount do
		local tRing = if cfg.RingCount <= 1 then 0 else (ring - 1) / (cfg.RingCount - 1)
		local radius = lerp(cfg.RadiusMin, cfg.RadiusMax, tRing)
		local segs = cfg.SegmentsPerRing
		local arcLen = (math.pi * 2 * radius) / segs * 1.08
		local width = (cfg.RadiusMax - cfg.RadiusMin) / cfg.RingCount * 1.35
		for i = 1, segs do
			local angle = ((i - 1) / segs) * math.pi * 2 + (rng() - 0.5) * 0.04
			local x = center.X + math.cos(angle) * radius
			local z = center.Z + math.sin(angle) * radius
			local yaw = angle + math.pi / 2
			local color = pickColor(rng, cfg.Colors)
			if not overlapsSummerZone(x, z, width * 0.5, arcLen * 0.5) then
				makeBlock(
					folder,
					string.format("Sea_R%d_%02d", ring, i),
					Vector3.new(width, cfg.Thickness, arcLen),
					CFrame.new(x, seaY, z) * CFrame.Angles(0, yaw, 0),
					color,
					0.08
				)
			end
		end
	end
end

local function buildPalm(parent: Folder, name: string, position: Vector3, scale: number, rng: () -> number)
	local cfg = Config.Palms
	local trunkH = 7 * scale
	local trunkR = 0.45 * scale
	makeCylinder(
		parent,
		name .. "_Trunk",
		Vector3.new(trunkH, trunkR * 2, trunkR * 2),
		CFrame.new(position + Vector3.new(0, trunkH * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		cfg.TrunkColor
	)

	local frondColor = pickColor(rng, cfg.FrondColors)
	local top = position + Vector3.new(0, trunkH * 0.92, 0)
	for i = 1, 5 do
		local a = ((i - 1) / 5) * math.pi * 2 + rng() * 0.2
		local len = lerp(4.5, 6.5, rng()) * scale
		local tilt = math.rad(lerp(25, 55, rng()))
		local cf = CFrame.new(top)
			* CFrame.Angles(0, a, 0)
			* CFrame.Angles(tilt, 0, 0)
			* CFrame.new(0, 0, -len * 0.45)
		makeBlock(
			parent,
			string.format("%s_Frond%d", name, i),
			Vector3.new(0.35 * scale, 0.25 * scale, len),
			cf,
			frondColor,
			0
		)
	end
end

local function buildIslands(parent: Folder, rng: () -> number, center: Vector3, seaY: number)
	local cfg = Config.Islands
	local folder = Instance.new("Folder")
	folder.Name = "Islands"
	folder.Parent = parent

	for i = 1, cfg.Count do
		local angle, radius = ringPlacement(rng, i, cfg.Count, cfg.RadiusMin, cfg.RadiusMax)
		local size = lerp(cfg.SizeMin, cfg.SizeMax, rng())
		local height = lerp(cfg.HeightMin, cfg.HeightMax, rng())
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local yaw = angle + math.pi / 2 + (rng() - 0.5) * 0.4
		local sand = pickColor(rng, cfg.SandColors)
		local grass = pickColor(rng, cfg.GrassColors)

		if not overlapsSummerZone(x, z, size * 0.55, size * 0.55) then
			local islandFolder = Instance.new("Folder")
			islandFolder.Name = string.format("Island_%02d", i)
			islandFolder.Parent = folder

			makeBlock(
				islandFolder,
				"Sand",
				Vector3.new(size, height, size * lerp(0.75, 1.1, rng())),
				CFrame.new(x, seaY + height * 0.55, z) * CFrame.Angles(0, yaw, 0),
				sand,
				0
			)
			makeBlock(
				islandFolder,
				"Cap",
				Vector3.new(size * 0.72, height * 0.45, size * 0.68),
				CFrame.new(x, seaY + height * 1.05, z) * CFrame.Angles(0, yaw + 0.15, 0),
				grass,
				0
			)

			local palmCount = math.floor(lerp(Config.Palms.PerIslandMin, Config.Palms.PerIslandMax + 0.999, rng()))
			for p = 1, palmCount do
				local ox = (rng() - 0.5) * size * 0.35
				local oz = (rng() - 0.5) * size * 0.35
				local scale = lerp(0.85, 1.25, rng())
				buildPalm(
					islandFolder,
					string.format("Palm_%d", p),
					Vector3.new(x + ox, seaY + height * 0.95, z + oz),
					scale,
					rng
				)
			end
		else
			-- Consommer le RNG palm pour garder un horizon reproductible
			local palmCount = math.floor(lerp(Config.Palms.PerIslandMin, Config.Palms.PerIslandMax + 0.999, rng()))
			for _ = 1, palmCount do
				local _ = rng()
				local _ = rng()
				local _ = rng()
				pickColor(rng, Config.Palms.FrondColors)
				for _f = 1, 5 do
					local _ = rng()
					local _ = rng()
				end
			end
		end
	end
end

local function buildClouds(parent: Folder, rng: () -> number, center: Vector3)
	local cfg = Config.Clouds
	local folder = Instance.new("Folder")
	folder.Name = "Clouds"
	folder.Parent = parent

	for i = 1, cfg.Count do
		local angle, radius = ringPlacement(rng, i, cfg.Count, cfg.RadiusMin, cfg.RadiusMax)
		local y = lerp(cfg.AltitudeMin, cfg.AltitudeMax, rng())
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local sx = lerp(28, 55, rng())
		local sy = lerp(4, 8, rng())
		local sz = lerp(16, 36, rng())
		local color = pickColor(rng, cfg.Colors)
		if not overlapsSummerZone(x, z, sx * 0.5, sz * 0.5) then
			makeBlock(
				folder,
				string.format("Cloud_%02d", i),
				Vector3.new(sx, sy, sz),
				CFrame.new(x, y, z) * CFrame.Angles(0, angle, 0),
				color,
				0.2
			)
		end
	end
end

local function buildDecorBubbles(parent: Folder, rng: () -> number, center: Vector3)
	local cfg = Config.DecorBubbles
	local folder = Instance.new("Folder")
	folder.Name = "DecorBubbles"
	folder.Parent = parent

	for i = 1, cfg.Count do
		local angle, radius = ringPlacement(rng, i, cfg.Count, cfg.RadiusMin, cfg.RadiusMax)
		local y = lerp(cfg.AltitudeMin, cfg.AltitudeMax, rng())
		local diameter = lerp(cfg.SizeMin, cfg.SizeMax, rng())
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local color = pickColor(rng, cfg.Colors)
		if not overlapsSummerZone(x, z, diameter * 0.5, diameter * 0.5) then
			makeBall(
				folder,
				string.format("DecorBubble_%02d", i),
				diameter,
				CFrame.new(x, y, z),
				color,
				0.35
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
	local seaY = Config.SeaLevelY or Config.GroundY or -14

	local generated = ensureGeneratedFolder()
	clearPreviousBackdrop(generated)

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("GeneratedByCode", true)
	model:SetAttribute("EnvironmentBackdropSeed", Config.Seed)
	model:SetAttribute("BackdropTheme", "OceanHorizon")

	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)

	buildOcean(model, rng, center, seaY)
	buildIslands(model, rng, center, seaY)
	buildClouds(model, rng, center)
	buildDecorBubbles(model, rng, center)

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

	local streaming = Config.WorldStreaming
	if streaming then
		-- StreamingMinRadius a été retiré de Workspace par Roblox ; y écrire lève une
		-- erreur qui interromprait tout le reste de l'ambiance.
		local world = game:GetService("Workspace")
		pcall(function()
			world.StreamingMinRadius = streaming.MinRadius
		end)
		pcall(function()
			world.StreamingTargetRadius = streaming.TargetRadius
		end)
	end

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
