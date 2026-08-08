--!strict
-- Rendu des POP : son, particules, feedback court au pop des spéciales. 100% local.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BubbleTypes = require(Shared.BubbleTypes)
local BubbleAppearance = require(Shared.BubbleAppearance)
local Remotes = require(Shared.Remotes)
local L10nUtil = require(Shared.LocalizationUtil)
local GridUtil = require(script.Parent.GridUtil)

local player = Players.LocalPlayer
local PopEffects = {}

local POP_SOUND_ID = "rbxassetid://109359226723492"
local RARE_SOUND_ID = "rbxassetid://6026984224"

local soundPool: { Sound } = {}
local POOL_SIZE = 12
local poolIndex = 1

local function buildPool()
	for i = 1, POOL_SIZE do
		local s = Instance.new("Sound")
		s.SoundId = POP_SOUND_ID
		s.Volume = 0.45
		s.RollOffMaxDistance = 90
		s.Parent = SoundService
		soundPool[i] = s
	end
end

local function playPop(rarity: string)
	local s = soundPool[poolIndex]
	poolIndex = poolIndex % POOL_SIZE + 1
	if not s then return end
	s.SoundId = if rarity == "Normal" then POP_SOUND_ID else RARE_SOUND_ID
	s.PlaybackSpeed = 0.92 + math.random() * 0.18
	s:Play()
end

local function burst(position: Vector3, color: Color3, big: boolean)
	local emitterPart = Instance.new("Part")
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.one
	emitterPart.CFrame = CFrame.new(position)
	emitterPart.Parent = workspace

	local p = Instance.new("ParticleEmitter")
	p.Color = ColorSequence.new(color)
	p.Size = NumberSequence.new(if big then 1.35 else 0.65)
	p.Lifetime = NumberRange.new(0.22, 0.45)
	p.Speed = NumberRange.new(if big then 18 else 10)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Rate = 0
	p.LightEmission = 0.65
	p.Parent = emitterPart
	p:Emit(if big then 28 else 12)

	Debris:AddItem(emitterPart, 1.0)
end

-- Feedback éphémère au POP d'une spéciale uniquement (vraie valeur de sac).
local function specialPopFeedback(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Name = "SpecialPopFeedback"
	gui.Size = UDim2.fromOffset(72, 28)
	gui.StudsOffset = Vector3.new(0, 1.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 70
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.25
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextSize = 22
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	L10nUtil.dynamic(label, text)

	TweenService:Create(
		anchor,
		TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(position + Vector3.new(0, 3.2, 0)) }
	):Play()
	TweenService:Create(label, TweenInfo.new(0.85), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(anchor, 0.95)
end

function PopEffects.Start()
	buildPool()

	Remotes.Event("PopEffects").OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" then return end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local origin = root and root.Position

		local played = 0
		for _, entry in ipairs(batch) do
			local x, z, rarity, zoneId = entry[1], entry[2], entry[3], entry[4]
			local zone = if type(zoneId) == "string" then zoneId else "ClassicZone"
			local pos = GridUtil.CellToWorld(x, z, zone)

			if origin and (pos - origin).Magnitude > 140 then continue end

			local def = BubbleTypes.ById[rarity] or BubbleTypes.List[1]
			local special = BubbleAppearance.IsSpecialRarity(rarity)

			burst(pos, def.Color, special)

			if special then
				local text = BubbleAppearance.FormatPopRewardText(rarity, zone)
				if text then
					specialPopFeedback(pos, text, def.Color)
				end
			end

			if played < 4 then
				playPop(rarity)
				played += 1
			end
		end
	end)
end

return PopEffects
