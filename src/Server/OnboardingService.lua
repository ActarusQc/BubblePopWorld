--!strict
-- Autorité serveur de l'onboarding : snapshot + attribut OnboardingObjective.
-- Aucun polling, aucune écriture analytics/profil ici.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local OnboardingConfig = require(Shared.OnboardingConfig)

local DataService = require(script.Parent.DataService)

local OnboardingService = {}

local function onboardingTable(analytics: any): any
	if type(analytics) ~= "table" then
		return nil
	end
	local onboarding = analytics.Onboarding
	if type(onboarding) ~= "table" then
		return nil
	end
	return onboarding
end

function OnboardingService.CheapestUpgradeCost(profile: any): number
	if type(profile) ~= "table" then
		return -1
	end
	local upgrades = if type(profile.Upgrades) == "table" then profile.Upgrades else {}
	local cheapest = -1
	for _, upgradeId in ipairs(Config.UpgradeOrder) do
		local def = Config.Upgrades[upgradeId]
		if def then
			local stored = upgrades[upgradeId] or 0
			local level = Config.EffectiveUpgradeLevel(upgradeId, stored)
			if level < def.Max then
				local cost = Config.UpgradeCost(upgradeId, level)
				if type(cost) == "number" and cost > 0 and cost ~= math.huge then
					if cheapest < 0 or cost < cheapest then
						cheapest = cost
					end
				end
			end
		end
	end
	return cheapest
end

function OnboardingService.BuildSnapshot(player: Player): OnboardingConfig.Snapshot?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end

	local analytics = profile.Analytics
	local onboarding = onboardingTable(analytics)

	return {
		OnboardingStarted = if type(analytics) == "table" then analytics.OnboardingStarted == true else false,
		OnboardingCompleted = if type(analytics) == "table" then analytics.OnboardingCompleted == true else false,
		PoppedFirstBubble = if onboarding then onboarding.PoppedFirstBubble == true else false,
		SoldFirstBackpack = if onboarding then onboarding.SoldFirstBackpack == true else false,
		PurchasedFirstUpgrade = if onboarding then onboarding.PurchasedFirstUpgrade == true else false,
		CurrentBubbles = if type(profile.CurrentBubbles) == "number" then profile.CurrentBubbles else 0,
		BackpackCapacity = if type(profile.BackpackCapacity) == "number" then profile.BackpackCapacity else 0,
		Coins = if type(profile.Coins) == "number" then profile.Coins else 0,
		CheapestUpgradeCost = OnboardingService.CheapestUpgradeCost(profile),
	}
end

function OnboardingService.ShouldSpawnInGameRoom(player: Player): boolean
	local snapshot = OnboardingService.BuildSnapshot(player)
	if snapshot == nil then
		return false
	end
	return OnboardingConfig.ShouldSpawnInGameRoom(snapshot)
end

function OnboardingService.Refresh(player: Player)
	local snapshot = OnboardingService.BuildSnapshot(player)
	local nextObjective = OnboardingConfig.ResolveObjective(snapshot)
	local attr = OnboardingConfig.AttributeName
	local previous = player:GetAttribute(attr)
	if previous == nextObjective then
		return
	end
	player:SetAttribute(attr, nextObjective)
end

function OnboardingService.Start()
	local attr = OnboardingConfig.AttributeName

	local function bind(player: Player)
		if player:GetAttribute(attr) == nil then
			player:SetAttribute(attr, OnboardingConfig.Objective.None)
		end
		OnboardingService.Refresh(player)
	end

	Players.PlayerAdded:Connect(bind)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(bind, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		-- Attribut nettoyé par Roblox à la destruction du Player.
		player:SetAttribute(attr, nil)
	end)
end

return OnboardingService
