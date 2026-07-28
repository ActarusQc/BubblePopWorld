--!strict
-- Feux d’artifice Summer Zone — client uniquement, décoratif, hors BubbleBoard.
-- Actif seulement si PlayerArea == "SummerZone". Pool d’émetteurs réutilisés.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local UserSettings = UserSettings
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.SummerFireworksConfig)

local player = Players.LocalPlayer
local SummerFireworks = {}

local rng = Random.new()
local running = false
local active = false
local folder: Folder? = nil
local hosts: { BasePart } = {}
local emitters: { ParticleEmitter } = {}
local nextHost = 1
local sound: Sound? = nil
local lastSoundAt = 0.0

local function isLiteMode(): boolean
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return true
	end
	local ok, quality = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel
	end)
	if ok and typeof(quality) == "EnumItem" then
		local level = quality.Value
		-- Automatic = 0 ; Low / VeryLow / etc. souvent <= 5
		if level > 0 and level <= 5 then
			return true
		end
	end
	return false
end

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "SummerZoneFireworksLocal"
	f:SetAttribute("ClientDecor", true)
	f.Parent = workspace
	folder = f
	return f
end

local function buildPool()
	if #hosts > 0 then
		return
	end
	local root = ensureFolder()
	local n = math.clamp(Config.PoolSize, 1, 4)
	for i = 1, n do
		local part = Instance.new("Part")
		part.Name = "FireworkHost" .. i
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = root

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Burst"
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.Lifetime = Config.Lifetime
		emitter.Speed = Config.Speed
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.LightEmission = 0.85
		emitter.LightInfluence = 0
		emitter.Size = Config.Size
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Parent = part

		hosts[i] = part
		emitters[i] = emitter
	end

	if Config.SoundEnabled and Config.SoundId ~= "" and Config.SoundId ~= "rbxassetid://0" then
		local s = Instance.new("Sound")
		s.Name = "FireworkPop"
		s.SoundId = Config.SoundId
		s.Volume = Config.SoundVolume
		s.RollOffMaxDistance = Config.SoundMaxDistance
		s.Parent = SoundService
		sound = s
	end
end

local function destroyPool()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(hosts)
	table.clear(emitters)
	nextHost = 1
	if sound then
		sound:Destroy()
		sound = nil
	end
end

local function pickColor(): Color3
	local colors = Config.Colors
	return colors[rng:NextInteger(1, #colors)]
end

local function launchOne(lite: boolean)
	if #hosts == 0 then
		return
	end
	local positions = Config.GetLaunchPositions()
	if #positions == 0 then
		return
	end

	local pos = positions[rng:NextInteger(1, #positions)]
	local heightJitter = rng:NextNumber(Config.BurstHeightMin, Config.BurstHeightMax)
		- (Config.BurstHeightMin + Config.BurstHeightMax) * 0.5
	pos = pos + Vector3.new(rng:NextNumber(-4, 4), heightJitter, rng:NextNumber(-4, 4))

	local idx = nextHost
	nextHost = nextHost % #hosts + 1
	local host = hosts[idx]
	local emitter = emitters[idx]
	if not host or not emitter then
		return
	end

	host.CFrame = CFrame.new(pos)
	local color = pickColor()
	emitter.Color = ColorSequence.new(color)
	local count = Config.EmitCount
	if lite then
		count = math.max(8, math.floor(count * Config.LiteEmitScale))
	end
	emitter:Emit(count)

	if sound and Config.SoundEnabled then
		local now = os.clock()
		if now - lastSoundAt > 2.5 then
			lastSoundAt = now
			sound.PlaybackSpeed = 0.9 + rng:NextNumber(0, 0.25)
			sound:Play()
		end
	end
end

local function runLoop()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			if not Config.Enabled or not active then
				task.wait(1)
				continue
			end

			local lite = isLiteMode()
			local waitMin = if lite then Config.LiteIntervalMin else Config.IntervalMin
			local waitMax = if lite then Config.LiteIntervalMax else Config.IntervalMax
			local maxBurst = if lite then Config.LiteMaxPerSequence else Config.MaxPerSequence

			task.wait(rng:NextNumber(waitMin, waitMax))
			if not running or not active or not Config.Enabled then
				continue
			end

			local n = rng:NextInteger(1, math.max(1, maxBurst))
			for i = 1, n do
				if not active then
					break
				end
				launchOne(lite)
				if i < n then
					task.wait(Config.StaggerSeconds)
				end
			end
		end
	end)
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	if on and Config.Enabled then
		buildPool()
		runLoop()
	elseif not on then
		-- Garde le pool en mémoire pour ré-entrée rapide ; détruit si hors zone longtemps.
		task.delay(30, function()
			if not active then
				destroyPool()
			end
		end)
	end
end

local function refreshFromArea()
	local area = player:GetAttribute("PlayerArea")
	setActive(area == "SummerZone")
end

function SummerFireworks.Start()
	if not Config.Enabled then
		return
	end
	player:GetAttributeChangedSignal("PlayerArea"):Connect(refreshFromArea)
	refreshFromArea()
end

return SummerFireworks
