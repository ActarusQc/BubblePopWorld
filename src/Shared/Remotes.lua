--!strict
-- Création/accès centralisé des Remotes. Le serveur les crée, le client attend.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"PopRequest",       -- client -> serveur : x, z, zoneId?
	"PopEffects",       -- serveur -> clients : batch d'effets
	"ToolActivate",     -- client -> serveur : position visée
	"StatsUpdate",      -- serveur -> client : profil résumé
	"Announce",         -- serveur -> clients : bannière
	"GlobalCounter",    -- serveur -> clients : compteur mondial
	"LeaderboardUpdate",-- serveur -> clients : classements
	"ComboUpdate",      -- serveur -> client : combo en cours
	"SetMusicMuted",    -- client -> serveur : préférence musique d'ambiance (boolean)
}

local FUNCTIONS = {
	"BuyUpgrade",       -- client -> serveur : id d'amélioration
	"BuyItem",          -- client -> serveur : id d'item boutique
	"EquipBackpack",    -- client -> serveur : id sac ("" = défaut)
	"GetShopData",      -- client -> serveur : upgrades + items
}

local Remotes = {}
local folder: Folder

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(EVENTS) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in ipairs(FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.Func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
