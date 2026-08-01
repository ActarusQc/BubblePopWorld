--!strict
-- Coffres : apparition, course au premier arrivé, annonce mondiale pour les légendaires.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local BubbleService = require(script.Parent.BubbleService)
local DataService = require(script.Parent.DataService)

local ChestService = {}
local rng = Random.new()

local announceHandlerForTests: ((message: string, kind: string) -> ())? = nil

function ChestService.SetAnnounceHandlerForTests(handler: ((string, string) -> ())?)
	announceHandlerForTests = handler
end

local function safeAnnounceAll(message: string, kind: string)
	if announceHandlerForTests ~= nil then
		announceHandlerForTests(message, kind)
		return
	end
	pcall(function()
		Remotes.Event("Announce"):FireAllClients(message, kind)
	end)
end

-- Crédit coffre + analytics source post-succès. claimState.claimed empêche le double claim.
local function tryClaimChest(player: Player, coins: number, claimState: { claimed: boolean }, tierLabel: string, tierId: string): boolean
	if claimState.claimed then
		return false
	end
	claimState.claimed = true

	local credited, endingBalance = DataService.AddCoins(player, coins, "Chest")
	if credited and type(endingBalance) == "number" then
		pcall(function()
			local GameAnalyticsService = require(script.Parent.GameAnalyticsService)
			GameAnalyticsService.LogCoinSource(player, {
				amount = coins,
				endingBalance = endingBalance,
				transactionType = "Gameplay",
				itemSku = "Chest",
			})
		end)
	end

	local profile = DataService.Get(player)
	if profile then
		profile.ChestsOpened += 1
	end
	DataService.Push(player)

	-- Nom joueur + nombres : non localisable en bloc (toast client = AutoLocalize false).
	local displayName = if typeof(player) == "Instance" then player.DisplayName else tostring((player :: any).Name or "Player")
	safeAnnounceAll(("%s opened a %s chest (+%d coins)"):format(displayName, tierLabel, coins), tierId)
	return true
end

function ChestService.TryClaimForTests(player: Player, coins: number, claimState: { claimed: boolean }): boolean
	return tryClaimChest(player, coins, claimState, "Test", "common")
end

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
	label.TextColor3 = tier.Color
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard
	L10nUtil.localize(label, tier.Label .. L10n.ChestSuffix)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = tier.Label .. L10n.ChestSuffix
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.Parent = chest

	local claimState = { claimed = false }
	prompt.Triggered:Connect(function(player)
		local coins = rng:NextInteger(tier.Coins[1], tier.Coins[2])
		local worldMult = BubbleService.CurrentWorld().Mult
		coins = math.floor(coins * worldMult)

		-- Les coffres restent une source directe de pièces (hors sac, spec §2).
		local claimedNow = tryClaimChest(player, coins, claimState, tier.Label, tier.Id)
		if claimedNow then
			chest:Destroy()
		end
	end)

	if tier.Announce then
		safeAnnounceAll(L10n.LegendaryChestAppeared, "legendary")
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
