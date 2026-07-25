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

-- No-op : les barrières de sécurité sont désormais gérées de façon idempotente par
-- `ZoneService` (dossier `SafetyBorders` sous `Workspace.BubblePopWorld.GameRoom`),
-- avec ouverture côté spawn/sortie. Conservé pour compatibilité des appelants existants.
function AmbianceService.BuildWalls(_parent: Instance)
end

function AmbianceService.Start()
	AmbianceService.Apply(Config.Worlds[1])
end

return AmbianceService
