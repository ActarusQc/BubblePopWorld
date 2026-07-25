--!strict
-- Coffres : apparition, course au premier arrivé, annonce mondiale pour les légendaires.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local BubbleService = require(script.Parent.BubbleService)
local DataService = require(script.Parent.DataService)

local ChestService = {}
local rng = Random.new()

local totalWeight = 0
for _, tier in ipairs(Config.Chest.Tiers) do totalWeight += tier.Weight end

local function rollTier()
	local roll = rng:NextNumber(0, totalWeight)
	local acc = 0
	for _, tier in ipairs(Config.Chest.Tiers) do
		acc += tier.Weight
		if roll <= acc then return tier end
	end
	return Config.Chest.Tiers[1]
end

local function spawnChest()
	local tier = rollTier()
	local x = rng:NextInteger(4, Config.Grid.SizeX - 4)
	local z = rng:NextInteger(4, Config.Grid.SizeZ - 4)
	local pos = BubbleService.CellToWorld(x, z) + Vector3.new(0, 4, 0)

	local chest = Instance.new("Part")
	chest.Name = "Chest_" .. tier.Id
	chest.Anchored = true
	chest.CanCollide = false
	chest.Size = Vector3.new(5, 4, 3.5)
	chest.Color = tier.Color
	chest.Material = Enum.Material.Neon
	chest.CFrame = CFrame.new(pos)
	chest.Parent = BubbleService.WorldFolder()

	local light = Instance.new("PointLight")
	light.Color = tier.Color
	light.Range = 30
	light.Brightness = 5
	light.Parent = chest

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(10, 2.4)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = chest
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "Coffre " .. tier.Label
	label.TextColor3 = tier.Color
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ouvrir"
	prompt.ObjectText = "Coffre " .. tier.Label
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.Parent = chest

	local claimed = false
	prompt.Triggered:Connect(function(player)
		if claimed then return end
		claimed = true

		local coins = rng:NextInteger(tier.Coins[1], tier.Coins[2])
		local worldMult = BubbleService.CurrentWorld().Mult
		coins = math.floor(coins * worldMult)

		-- Les coffres restent une source directe de pièces (hors sac, spec §2).
		DataService.AddCoins(player, coins, "Chest")
		DataService.AddXP(player, tier.XP)
		local profile = DataService.Get(player)
		if profile then profile.ChestsOpened += 1 end
		DataService.Push(player)

		Remotes.Event("Announce"):FireAllClients(
			("%s a ouvert un coffre %s (+%d pièces)"):format(player.DisplayName, tier.Label, coins), tier.Id)
		chest:Destroy()
	end)

	if tier.Announce then
		Remotes.Event("Announce"):FireAllClients("⭐ Un coffre légendaire est apparu !", "legendary")
		pcall(function()
			MessagingService:PublishAsync(Config.Global.Topic .. "_Chest", { tier = tier.Id })
		end)
	end

	Debris:AddItem(chest, Config.Chest.Lifetime)
end

function ChestService.Start()
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(Config.Chest.MinInterval, Config.Chest.MaxInterval))
			pcall(spawnChest)
		end
	end)
end

return ChestService
