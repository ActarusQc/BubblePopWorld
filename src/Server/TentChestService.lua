--!strict
-- Coffres payants du chapiteau. Le serveur débite, tire le lot et crédite.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local TentChestConfig = require(Shared.TentChestConfig)
local TentChestLogic = require(Shared.TentChestLogic)
local DataService = require(script.Parent.DataService)

local Service = {}
local rng = Random.new()
local lastOpenAt: { [Player]: number } = {}
local boundPrompts: { [ProximityPrompt]: boolean } = {}

type OpenOptions = {
	skipDistance: boolean?,
	roll01: number?,
	chestPosition: Vector3?,
}

local function announce(player: Player, message: string, kind: string)
	pcall(function()
		Remotes.Event("Announce"):FireClient(player, message, kind)
	end)
end

local function logEconomy(player: Player, kind: string, amount: number, endingBalance: number)
	pcall(function()
		local GameAnalyticsService = require(script.Parent.GameAnalyticsService)
		local ctx = {
			amount = amount,
			endingBalance = endingBalance,
			transactionType = "Gameplay",
			itemSku = "TentChest",
		}
		if kind == "sink" then
			GameAnalyticsService.LogCoinSink(player, ctx)
		else
			GameAnalyticsService.LogCoinSource(player, ctx)
		end
	end)
end

local function playerRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return character:FindFirstChild("Torso") :: BasePart?
end

local function popLid(model: Model)
	local lid = model:FindFirstChild("Lid")
	if not (lid and lid:IsA("BasePart")) then
		return
	end
	local closed = lid.CFrame
	local opened = closed * CFrame.new(0, 0.85, -0.45) * CFrame.Angles(math.rad(-55), 0, 0)
	TweenService:Create(lid, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = opened,
	}):Play()
	task.delay(1.35, function()
		if lid.Parent then
			TweenService:Create(lid, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = closed,
			}):Play()
		end
	end)
end

local function openChest(player: Player, chestId: string, options: OpenOptions): (boolean, string)
	local chest = TentChestLogic.GetChest(chestId)
	if not chest then
		return false, "unknown"
	end

	local now = os.clock()
	local last = lastOpenAt[player]
	if options.skipDistance ~= true and last and now - last < TentChestConfig.Cooldown then
		announce(player, L10n.TentChestCooldown, "info")
		return false, "cooldown"
	end

		if options.skipDistance ~= true then
		local root = playerRoot(player)
		local chestPos = options.chestPosition
		if not root or typeof(chestPos) ~= "Vector3" then
			return false, "distance"
		end
		if (root.Position - chestPos).Magnitude > TentChestConfig.MaxOpenDistance then
			return false, "distance"
		end
	end

	local profile = DataService.Get(player)
	if not profile then
		return false, "profile"
	end
	if type(profile.Coins) ~= "number" or profile.Coins < chest.Cost then
		announce(player, L10n.TentChestNeedCoins, "info")
		return false, "coins"
	end

	lastOpenAt[player] = now
	profile.Coins -= chest.Cost
	profile.__dirty = true
	local afterPay = profile.Coins

	local prize = TentChestLogic.RollPrize(chestId, options.roll01 or rng:NextNumber())
	if type(prize) ~= "number" or prize <= 0 then
		profile.Coins += chest.Cost
		return false, "roll"
	end

	local credited, endingBalance = DataService.AddCoins(player, prize, "TentChest")
	if not credited then
		profile.Coins += chest.Cost
		DataService.NotifyCoinsChanged(player)
		return false, "credit"
	end

	if type(profile.ChestsOpened) == "number" then
		profile.ChestsOpened += 1
	end
	DataService.Push(player)
	DataService.NotifyCoinsChanged(player)

	logEconomy(player, "sink", chest.Cost, afterPay)
	if type(endingBalance) == "number" then
		logEconomy(player, "source", prize, endingBalance)
	end

	local delta = TentChestLogic.NetDelta(chest.Cost, prize)
	if TentChestLogic.IsWin(chest.Cost, prize) then
		announce(player, L10n.TentChestWinFmt:format(prize, delta), "win")
	else
		announce(player, L10n.TentChestLossFmt:format(prize, delta), "info")
	end
	return true, "ok"
end

function Service.TryOpenForTests(player: Player, chestId: string, options: OpenOptions?): (boolean, string)
	return openChest(player, chestId, options or { skipDistance = true, roll01 = 0 })
end

local function bindPrompt(prompt: ProximityPrompt)
	if boundPrompts[prompt] then
		return
	end
	local host = prompt.Parent
	if not host then
		return
	end
	local model = if host:IsA("Model") then host else host.Parent
	local chestId = if model then model:GetAttribute("TentChestId") else nil
	if type(chestId) ~= "string" and prompt:GetAttribute("TentChestId") ~= nil then
		chestId = prompt:GetAttribute("TentChestId")
	end
	if type(chestId) ~= "string" then
		return
	end
	if TentChestLogic.GetChest(chestId) == nil then
		return
	end

	boundPrompts[prompt] = true
	prompt.Triggered:Connect(function(player)
		local chestPos = if host:IsA("BasePart") then host.Position else nil
		if not chestPos and model and model:IsA("Model") and model.PrimaryPart then
			chestPos = model.PrimaryPart.Position
		end
		local ok = openChest(player, chestId, {
			chestPosition = chestPos,
		})
		if ok and model and model:IsA("Model") then
			popLid(model)
		end
	end)
	prompt.Destroying:Connect(function()
		boundPrompts[prompt] = nil
	end)
end

local function scanPrompts()
	local park = workspace:FindFirstChild("ParcAttractions")
	if not park then
		return
	end
	for _, descendant in ipairs(park:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			bindPrompt(descendant)
		end
	end
end

function Service.Start()
	workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			task.defer(bindPrompt, descendant)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastOpenAt[player] = nil
	end)
	task.defer(scanPrompts)
end

return Service
