--!strict
-- Apparition aléatoire d'objets dans le monde (rayon lumineux + ramassage).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ToolDefs = require(Shared.ToolDefs)
local Remotes = require(Shared.Remotes)

local BubbleService = require(script.Parent.BubbleService)
local ToolService = require(script.Parent.ToolService)

local DropService = {}
local rng = Random.new()

local function spawnDrop()
	local id, def = ToolDefs.Roll(rng)
	local x = rng:NextInteger(3, Config.Grid.SizeX - 3)
	local z = rng:NextInteger(3, Config.Grid.SizeZ - 3)
	local pos = BubbleService.CellToWorld(x, z) + Vector3.new(0, 4, 0)

	local model = Instance.new("Part")
	model.Name = "Drop_" .. id
	model.Anchored = true
	model.CanCollide = false
	model.CFrame = CFrame.new(pos)
	model.Parent = BubbleService.WorldFolder()

	local accent = ToolDefs.RarityColor[def.Rarity] or def.Color
	if id == "Bombe" then
		model.Shape = Enum.PartType.Ball
		model.Size = Vector3.new(2.2, 2.2, 2.2)
		model.Color = Color3.fromRGB(35, 35, 42)
		model.Material = Enum.Material.SmoothPlastic
		local spark = Instance.new("Part")
		spark.Name = "Spark"
		spark.Anchored = true
		spark.CanCollide = false
		spark.Shape = Enum.PartType.Ball
		spark.Size = Vector3.new(0.45, 0.45, 0.45)
		spark.Color = Color3.fromRGB(255, 170, 50)
		spark.Material = Enum.Material.Neon
		spark.CFrame = CFrame.new(pos + Vector3.new(0.4, 1.3, 0))
		spark.Parent = model
	elseif id == "Epingle" then
		model.Size = Vector3.new(0.25, 2.4, 0.25)
		model.Color = Color3.fromRGB(175, 182, 195)
		model.Material = Enum.Material.Metal
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Anchored = true
		head.CanCollide = false
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(0.7, 0.7, 0.7)
		head.Color = Color3.fromRGB(255, 55, 75)
		head.Material = Enum.Material.SmoothPlastic
		head.CFrame = CFrame.new(pos + Vector3.new(0, 1.4, 0))
		head.Parent = model
	elseif id == "Marteau" then
		model.Size = Vector3.new(0.35, 2.2, 0.35)
		model.Color = Color3.fromRGB(120, 85, 50)
		model.Material = Enum.Material.Wood
		local head = Instance.new("Part")
		head.Anchored = true
		head.CanCollide = false
		head.Size = Vector3.new(1.4, 0.6, 0.55)
		head.Color = Color3.fromRGB(160, 165, 175)
		head.Material = Enum.Material.Metal
		head.CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0))
		head.Parent = model
	elseif id == "MegaRouleau" then
		model.Size = Vector3.new(2.4, 2.4, 2.4)
		model.Color = Color3.fromRGB(255, 140, 60)
		model.Material = Enum.Material.SmoothPlastic
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Cylinder
		mesh.Parent = model
		model.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	elseif id == "Laser" then
		model.Size = Vector3.new(0.4, 2.2, 0.4)
		model.Color = Color3.fromRGB(50, 50, 60)
		model.Material = Enum.Material.SmoothPlastic
		local tip = Instance.new("Part")
		tip.Anchored = true
		tip.CanCollide = false
		tip.Shape = Enum.PartType.Ball
		tip.Size = Vector3.new(0.7, 0.7, 0.7)
		tip.Color = Color3.fromRGB(255, 60, 90)
		tip.Material = Enum.Material.Neon
		tip.CFrame = CFrame.new(pos + Vector3.new(0, 1.4, 0))
		tip.Parent = model
	elseif id == "Singularite" then
		model.Shape = Enum.PartType.Ball
		model.Size = Vector3.new(2.0, 2.0, 2.0)
		model.Color = Color3.fromRGB(180, 60, 255)
		model.Material = Enum.Material.Neon
	elseif id == "Ailes" then
		model.Size = Vector3.new(0.4, 0.4, 0.4)
		model.Color = Color3.fromRGB(120, 210, 255)
		model.Material = Enum.Material.Neon
		model.Transparency = 0.3
		for _, side in ipairs({ -1, 1 }) do
			local wing = Instance.new("Part")
			wing.Anchored = true
			wing.CanCollide = false
			wing.Size = Vector3.new(0.2, 1.2, 2.0)
			wing.Color = Color3.fromRGB(140, 220, 255)
			wing.Material = Enum.Material.SmoothPlastic
			wing.Transparency = 0.2
			wing.CFrame = CFrame.new(pos + Vector3.new(side * 1.1, 0, 0))
			wing.Parent = model
		end
	else
		model.Size = Vector3.new(2, 2, 2)
		model.Color = accent
		model.Material = Enum.Material.Neon
	end

	-- Rayon lumineux visible de loin
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.Transparency = 0.55
	beam.Material = Enum.Material.Neon
	beam.Color = accent
	beam.Size = Vector3.new(3, 200, 3)
	beam.CFrame = CFrame.new(pos + Vector3.new(0, 100, 0))
	beam.Parent = model

	local light = Instance.new("PointLight")
	light.Color = accent
	light.Range = 24
	light.Brightness = 3
	light.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(8, 2)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = def.Name
	label.TextColor3 = accent
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	-- Ramassage automatique : le premier joueur qui passe assez près l'emporte.
	local taken = false
	task.spawn(function()
		local radius = Config.Drops.PickupRadius
		while model.Parent and not taken do
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if root and hum and hum.Health > 0 then
					if (root.Position - pos).Magnitude <= radius then
						taken = true
						ToolService.Give(plr, id)
						model:Destroy()
						break
					end
				end
			end
			task.wait(Config.Drops.PickupRate)
		end
	end)

	-- Rotation d'ambiance
	task.spawn(function()
		while model.Parent do
			model.CFrame = model.CFrame * CFrame.Angles(0, math.rad(2), 0)
			task.wait(0.03)
		end
	end)

	if def.Rarity == "Epic" or def.Rarity == "Mythic" then
		Remotes.Event("Announce"):FireAllClients(
			("A %s item just appeared: %s"):format(def.Rarity, def.Name), "item")
	end

	Debris:AddItem(model, Config.Drops.Lifetime)
end

function DropService.Start()
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(Config.Drops.MinInterval, Config.Drops.MaxInterval))
			pcall(spawnDrop)
		end
	end)
end

return DropService