--!strict
-- Garde de visibilité du bouton Daily Rewards.
-- Le bouton d'ouverture n'est utile que lorsqu'une récompense est réclamable.
-- Ce script reste séparé du contrôleur visuel afin de ne pas toucher au panneau
-- avant sa refonte graphique.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local stateRemote = Remotes.Event("DailyRewardsState")

local gui = playerGui:WaitForChild("BPW_DailyRewards")
local openButton = gui:WaitForChild("DailyRewardsButton") :: TextButton
local overlay = gui:WaitForChild("Overlay") :: Frame

local canClaim: boolean? = nil

local function syncVisibility()
	-- Avant le premier état serveur, conserver le comportement initial du contrôleur.
	if canClaim == nil then
		return
	end

	openButton.Active = canClaim == true
	openButton.Selectable = canClaim == true
	openButton.Visible = canClaim == true and overlay.Visible == false
end

stateRemote.OnClientEvent:Connect(function(state: any)
	if type(state) ~= "table" then
		return
	end

	canClaim = state.CanClaim == true
	-- Le contrôleur principal traite le même RemoteEvent. Defer garantit que cette
	-- garde de visibilité s'applique après son rendu, quel que soit l'ordre des connexions.
	task.defer(syncVisibility)
end)

overlay:GetPropertyChangedSignal("Visible"):Connect(function()
	task.defer(syncVisibility)
end)
