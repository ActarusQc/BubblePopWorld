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
	-- Bubble Transit
	"RequestDestinationList", -- client -> serveur : transitId
	"DestinationListUpdated", -- serveur -> client : liste destinations filtrée
	"RequestTravel",          -- client -> serveur : destinationId, transitId
	"TravelResult",           -- serveur -> client : ok / code / message
	-- Mini-événements
	"MiniEventState",         -- serveur -> client : état structuré (countdown/active/ended)
	-- Défis quotidiens / hebdo
	"ChallengeState",         -- serveur -> client : état challenges + LB
	"ChallengeRequestState",  -- client -> serveur : demande état
	"ChallengeClaim",         -- client -> serveur : challengeId (claim idempotent)
	"ChallengeTrack",         -- client -> serveur : challengeId suivi UI
	"ChallengeNotify",        -- serveur -> client : toasts (complete/claim/milestone)
	"ChallengePanelOpened",   -- client -> serveur : analytics panel
	-- Tutoriel d'accueil (serveur → client uniquement)
	"TutorialState",          -- serveur -> client : étape / progrès / célébration / fin
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
