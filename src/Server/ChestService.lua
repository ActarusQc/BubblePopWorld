--!strict
-- Coffres : apparition, course au premier arrivé, annonce mondiale pour les légendaires.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ChestAppearance = require(Shared.ChestAppearance)
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
	local pos = BubbleService.CellToWorld(x, z) + Vector3.new(0, 3.2, 0)
	local world = BubbleService.WorldFolder()
	if not world then
		return
	end

	local model = ChestAppearance.BuildModel(tier, CFrame.new(pos))
	model.Parent = world

	local root = model.PrimaryPart
	if not root then
		model:Destroy()
		return
	end

	local visual = ChestAppearance.ResolveVisual(tier)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ChestLabel"
	billboard.Size = UDim2.fromScale(8, 2)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = visual.AccentColor
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
	prompt.Parent = root

	local claimState = { claimed = false }
	prompt.Triggered:Connect(function(player)
		local coins = rng:NextInteger(tier.Coins[1], tier.Coins[2])
		local worldMult = BubbleService.CurrentWorld().Mult
		coins = math.floor(coins * worldMult)

		local claimedNow = tryClaimChest(player, coins, claimState, tier.Label, tier.Id)
		if claimedNow then
			model:Destroy()
		end
	end)

	if tier.Announce then
		safeAnnounceAll(L10n.LegendaryChestAppeared, "legendary")
		pcall(function()
			MessagingService:PublishAsync(Config.Global.Topic .. "_Chest", { tier = tier.Id })
		end)
	end

	Debris:AddItem(model, Config.Chest.Lifetime)
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
