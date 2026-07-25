--!strict
-- Ambiance visuelle du monde + murs de sécurité aux bordures.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)

local AmbianceService = {}

local function clear(className: string)
	for _, item in ipairs(Lighting:GetChildren()) do
		if item:IsA(className) then item:Destroy() end
	end
end

function AmbianceService.Apply(worldDef)
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.0
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.25
	Lighting.GlobalShadows = true
	Lighting.OutdoorAmbient = worldDef.Sky
	Lighting.Ambient = Color3.fromRGB(70, 75, 90)
	Lighting.FogEnd = 900

	clear("Atmosphere")
	local atmos = Instance.new("Atmosphere")
	atmos.Density = 0.28
	atmos.Offset = 0.2
	atmos.Color = worldDef.Sky
	atmos.Decay = worldDef.Ground
	atmos.Glare = 0.15
	atmos.Haze = 1.0
	atmos.Parent = Lighting

	clear("BloomEffect")
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.15
	bloom.Size = 12
	bloom.Threshold = 1.5
	bloom.Parent = Lighting

	clear("SunRaysEffect")
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.08
	rays.Spread = 0.8
	rays.Parent = Lighting

	clear("ColorCorrectionEffect")
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.12
	cc.Contrast = 0.08
	cc.Brightness = 0
	cc.Parent = Lighting
end

-- Murs invisibles : on ne tombe plus hors de la nappe de bulles.
function AmbianceService.BuildWalls(parent: Instance)
	local G = Config.Grid
	local w = G.SizeX * G.Spacing
	local d = G.SizeZ * G.Spacing
	local height = 220

	local sides = {
		{ Vector3.new(w + 20, height, 4), Vector3.new(0, height / 2, -d / 2 - 8) },
		{ Vector3.new(w + 20, height, 4), Vector3.new(0, height / 2, d / 2 + 8) },
		{ Vector3.new(4, height, d + 20), Vector3.new(-w / 2 - 8, height / 2, 0) },
		{ Vector3.new(4, height, d + 20), Vector3.new(w / 2 + 8, height / 2, 0) },
	}

	for i, side in ipairs(sides) do
		local wall = Instance.new("Part")
		wall.Name = "Wall" .. i
		wall.Anchored = true
		wall.CanCollide = true
		wall.Transparency = 1
		wall.Size = side[1]
		wall.CFrame = CFrame.new(G.Origin + side[2])
		wall.Parent = parent
	end
end

function AmbianceService.Start()
	AmbianceService.Apply(Config.Worlds[1])
end

return AmbianceService
