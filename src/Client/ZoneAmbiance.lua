--!strict
-- Ambiance locale par zone (client uniquement — Lighting global non modifié pour les autres).
-- ColorCorrection + bannière + cadenas Summer selon PlayerArea.
-- Musique : voir MusicController (ne pas rejouer de sons ici).

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneDefs = require(Shared.ZoneDefs)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local player = Players.LocalPlayer
local ZoneAmbiance = {}

local cc: ColorCorrectionEffect? = nil
local lastBannerAt = 0
local lastArea: string? = nil

local function ensureColorCorrection(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild("BPW_LocalZoneCC")
	if existing and existing:IsA("ColorCorrectionEffect") then
		cc = existing
		return existing
	end
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "BPW_LocalZoneCC"
	effect.Enabled = false
	effect.Parent = Lighting
	cc = effect
	return effect
end

local function showZoneBanner(displayName: string)
	local now = os.clock()
	if now - lastBannerAt < 4 then
		return
	end
	lastBannerAt = now

	local gui = player:FindFirstChild("PlayerGui")
	if not gui then
		return
	end
	local screen = gui:FindFirstChild("BPW_HUD") :: ScreenGui?
	if not screen then
		return
	end

	local banner = Instance.new("TextLabel")
	banner.Name = "ZoneBanner"
	banner.Size = UDim2.new(0, 360, 0, 48)
	banner.Position = UDim2.new(0.5, -180, 0.18, 0)
	banner.BackgroundColor3 = Color3.fromRGB(18, 30, 40)
	banner.BackgroundTransparency = 0.2
	banner.TextColor3 = Color3.fromRGB(255, 230, 120)
	banner.Font = Enum.Font.GothamBlack
	banner.TextScaled = true
	banner.ZIndex = 50
	banner.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = banner
	L10nUtil.localize(banner, displayName)

	task.delay(2.2, function()
		TweenService:Create(banner, TweenInfo.new(0.45), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
		task.wait(0.5)
		banner:Destroy()
	end)
end

local function applyArea(area: string)
	local effect = ensureColorCorrection()

	if area == "SummerZone" then
		local def = ZoneDefs.SummerZone
		local ac = def.Ambiance and def.Ambiance.ColorCorrection
		if ac then
			effect.Enabled = true
			effect.TintColor = ac.TintColor
			effect.Brightness = ac.Brightness
			effect.Contrast = ac.Contrast
			effect.Saturation = ac.Saturation
		end
		if lastArea ~= area then
			showZoneBanner(L10n.SummerZoneTitle)
		end
	else
		effect.Enabled = false
	end
	lastArea = area
end

-- Cadenas local : masqué uniquement pour ce client dès que CanEnter_SummerZone.
local function refreshSummerLockVisual()
	local canEnter = player:GetAttribute("CanEnter_SummerZone")
	local unlocked = canEnter == true

	local gameZones = workspace:FindFirstChild("GameZones")
	local summer = gameZones and gameZones:FindFirstChild("SummerZone")
	local gateFolder = summer and summer:FindFirstChild("LevelGate")
	if not gateFolder then
		return
	end

	local lock = gateFolder:FindFirstChild("LockSymbol")
	if lock and lock:IsA("BasePart") then
		lock.LocalTransparencyModifier = if unlocked then 1 else 0
		local billboard = lock:FindFirstChild("LockBillboard")
		if billboard and billboard:IsA("BillboardGui") then
			billboard.Enabled = not unlocked
		end
	end

	local gate = gateFolder:FindFirstChild("ForceFieldGate")
	if gate and gate:IsA("BasePart") then
		-- La collision reste gérée serveur (groupes). Visuel local adouci si déverrouillé.
		gate.LocalTransparencyModifier = if unlocked then 0.55 else 0
	end
end

function ZoneAmbiance.Start()
	ensureColorCorrection()

	local function onArea()
		local area = player:GetAttribute("PlayerArea")
		if type(area) == "string" then
			applyArea(area)
		end
	end

	player:GetAttributeChangedSignal("PlayerArea"):Connect(onArea)
	onArea()

	player:GetAttributeChangedSignal("CanEnter_SummerZone"):Connect(refreshSummerLockVisual)
	player:GetAttributeChangedSignal("PlayerLevel"):Connect(refreshSummerLockVisual)
	task.defer(refreshSummerLockVisual)

	local function watchGateFolder(folder: Instance)
		folder.ChildAdded:Connect(function()
			task.defer(refreshSummerLockVisual)
		end)
	end

	local gameZones = workspace:FindFirstChild("GameZones")
	if gameZones then
		local summer = gameZones:FindFirstChild("SummerZone")
		local gateFolder = summer and summer:FindFirstChild("LevelGate")
		if gateFolder then
			watchGateFolder(gateFolder)
		end
	else
		workspace.ChildAdded:Connect(function(child)
			if child.Name == "GameZones" then
				task.defer(refreshSummerLockVisual)
				local summer = child:WaitForChild("SummerZone", 5)
				local gateFolder = summer and summer:WaitForChild("LevelGate", 5)
				if gateFolder then
					watchGateFolder(gateFolder)
				end
			end
		end)
	end
end

return ZoneAmbiance
