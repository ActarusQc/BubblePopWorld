--!strict
-- Secousse de caméra, traînée de rebond et flash d'atterrissage.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BubbleTypes = require(Shared.BubbleTypes)
local Remotes = require(Shared.Remotes)
local GridUtil = require(script.Parent.GridUtil)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local JuiceController = {}
local shake = 0
local rng = Random.new()

local function addShake(amount: number)
	shake = math.min(1.6, shake + amount)
end

--------------------------------------------------------------------
-- Caméra
--------------------------------------------------------------------
local function startShake()
	RunService:BindToRenderStep("BPW_Shake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if shake <= 0.001 then
			shake = 0
			return
		end
		shake = math.max(0, shake - dt * 4.5)

		local intensity = shake * shake
		local offset = Vector3.new(
			rng:NextNumber(-1, 1) * intensity * 0.55,
			rng:NextNumber(-1, 1) * intensity * 0.55,
			0
		)
		local tilt = rng:NextNumber(-1, 1) * intensity * 0.02

		camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, tilt)
	end)
end

--------------------------------------------------------------------
-- Traînée du personnage
--------------------------------------------------------------------
local function setupTrail(char: Model)
	local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root then return end

	local a0 = Instance.new("Attachment")
	a0.Name = "BPW_TrailA"
	a0.Position = Vector3.new(-0.9, 0.4, 0)
	a0.Parent = root

	local a1 = Instance.new("Attachment")
	a1.Name = "BPW_TrailB"
	a1.Position = Vector3.new(0.9, -0.8, 0)
	a1.Parent = root

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.32
	trail.MinLength = 0.2
	trail.LightEmission = 0.8
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = ColorSequence.new(
		Color3.fromRGB(150, 230, 255),
		Color3.fromRGB(255, 160, 240)
	)
	trail.Enabled = false
	trail.Parent = root

	RunService.Heartbeat:Connect(function()
		if not root.Parent then return end
		trail.Enabled = root.AssemblyLinearVelocity.Magnitude > 28
	end)
end

--------------------------------------------------------------------
-- Réaction aux POP
--------------------------------------------------------------------
local function watchPops()
	Remotes.Event("PopEffects").OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" then return end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end

		for _, entry in ipairs(batch) do
			local pos = GridUtil.CellToWorld(entry[1], entry[2])
			local distance = (pos - root.Position).Magnitude
			if distance > 90 then continue end

			local falloff = 1 - math.clamp(distance / 90, 0, 1)
			local rarity = entry[3]

			if rarity == "Legendary" then
				addShake(1.2 * falloff)
			elseif rarity == "Diamond" then
				addShake(0.7 * falloff)
			elseif rarity == "Golden" then
				addShake(0.35 * falloff)
			else
				addShake(0.07 * falloff)
			end
		end
	end)
end

function JuiceController.Start()
	startShake()
	watchPops()

	if player.Character then setupTrail(player.Character) end
	player.CharacterAdded:Connect(setupTrail)
end

return JuiceController
