--!strict
-- Rendu des POP : son, particules, texte flottant. 100% local.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BubbleTypes = require(Shared.BubbleTypes)
local Remotes = require(Shared.Remotes)
local GridUtil = require(script.Parent.GridUtil)

local player = Players.LocalPlayer
local PopEffects = {}

-- ⚠️ Remplace ces IDs par tes propres sons dans Roblox Studio.
local POP_SOUND_ID = "rbxassetid://6042053626"
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
	p.Size = NumberSequence.new(if big then 1.6 else 0.7)
	p.Lifetime = NumberRange.new(0.25, 0.5)
	p.Speed = NumberRange.new(if big then 22 else 11)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Rate = 0
	p.LightEmission = 0.7
	p.Parent = emitterPart
	p:Emit(if big then 45 else 14)

	Debris:AddItem(emitterPart, 1.2)
end

local function floatingText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(8, 2)
	gui.AlwaysOnTop = true
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui

	TweenService:Create(anchor, TweenInfo.new(1), { CFrame = CFrame.new(position + Vector3.new(0, 8, 0)) }):Play()
	TweenService:Create(label, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.2)
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
			local x, z, rarity = entry[1], entry[2], entry[3]
			local pos = GridUtil.CellToWorld(x, z)

			-- On n'affiche que ce qui est proche du joueur : perf + lisibilité.
			if origin and (pos - origin).Magnitude > 140 then continue end

			local def = BubbleTypes.ById[rarity] or BubbleTypes.List[1]
			local special = rarity ~= "Normal"

			burst(pos, def.Color, special)

			if special then
				floatingText(pos, "+" .. def.Coins, def.Color)
			end

			if played < 4 then
				playPop(rarity)
				played += 1
			end
		end
	end)
end

return PopEffects
