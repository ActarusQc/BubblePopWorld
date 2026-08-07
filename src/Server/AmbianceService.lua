--!strict
-- Ambiance visuelle du monde + murs de sécurité aux bordures.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local EnvironmentBackdropBuilder = require(Shared.EnvironmentBackdropBuilder)

local AmbianceService = {}

local function clear(className: string)
	for _, item in ipairs(Lighting:GetChildren()) do
		if item:IsA(className) then item:Destroy() end
	end
end

function AmbianceService.Apply(worldDef)
	Lighting.ClockTime = 14.5
	-- Ombres globales OK pour le hub ; décors d'horizon + bulles ont CastShadow=false.
	Lighting.GlobalShadows = true

	-- Atmosphère / éclairage plat (horizon océan) — stabilise le shading des bulles.
	EnvironmentBackdropBuilder.ApplyAtmosphere(worldDef.Sky)

	clear("BloomEffect")
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.08
	bloom.Size = 10
	bloom.Threshold = 1.8
	bloom.Parent = Lighting

	clear("SunRaysEffect")
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.04
	rays.Spread = 0.7
	rays.Parent = Lighting

	clear("ColorCorrectionEffect")
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.08
	cc.Contrast = 0 -- contrast > 0 assombrit les faces déjà sombres des bulles
	cc.Brightness = 0.02
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
