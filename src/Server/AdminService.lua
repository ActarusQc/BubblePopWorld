--!strict
-- Outil d'administration temporaire : réinitialisation de la progression joueur.
-- Volontairement sans RemoteEvent : la commande n'existe que côté serveur (Player.Chatted
-- + point d'entrée _G pour la barre de commande Studio), donc rien n'est exposé au client.
-- À retirer une fois la phase de test terminée.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local BackpackService = require(script.Parent.BackpackService)
local LeaderboardService = require(script.Parent.LeaderboardService)

local AdminService = {}

type Pending = {
	Label: string,
	TargetUserId: number,
	Expires: number,
}

local pending: { [Player]: Pending } = {}

local function log(fmt: string, ...: any)
	print("[AdminService] " .. fmt:format(...))
end

local function isAdmin(player: Player): boolean
	for _, id in ipairs(Config.Admin.UserIds) do
		if player.UserId == id then
			return true
		end
	end

	if not Config.Admin.AllowPlaceOwner then
		return false
	end

	-- Place non publiée ouverte en Studio : pas de propriétaire à comparer, et la session
	-- est locale à la machine du développeur.
	if RunService:IsStudio() and game.CreatorId == 0 then
		return true
	end

	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end

	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		return ok and rank == 255
	end

	return false
end

local function reply(player: Player, message: string)
	Remotes.Event("Announce"):FireClient(player, message, "admin")
	log("→ %s (%d) : %s", player.Name, player.UserId, message)
end

-- Réinitialisation effective d'un UserId, en ligne ou hors ligne.
local function resetUserId(userId: number): (boolean, string)
	local target = Players:GetPlayerByUserId(userId)

	if target then
		if not BackpackService.ResetSession(target) then
			return false, ("Échec : profil de %s non chargé ou verrou occupé."):format(target.Name)
		end
		DataService.Save(target)
		LeaderboardService.RemoveEntry(userId)
		Remotes.Event("Announce"):FireClient(target, "Your progress has been reset.", "admin")
		log("profil réinitialisé EN LIGNE : %s (%d)", target.Name, userId)
		return true, ("%s réinitialisé (en ligne) et sauvegardé."):format(target.Name)
	end

	if not DataService.ResetStoredProfile(userId) then
		return false, ("Échec de l'effacement de la clé de %d (DataStore)."):format(userId)
	end
	LeaderboardService.RemoveEntry(userId)
	log("clé effacée HORS LIGNE : %d", userId)
	return true, ("Clé de %d effacée. S'il est connecté ailleurs, sa sauvegarde de sortie annulera ce reset."):format(userId)
end

local function arm(player: Player, label: string, targetUserId: number)
	pending[player] = {
		Label = label,
		TargetUserId = targetUserId,
		Expires = os.clock() + Config.Admin.ConfirmTimeout,
	}
	log("action armée par %s (%d) : %s", player.Name, player.UserId, label)
	reply(player, ("%s — confirme avec « %s confirm » (%ds)."):format(
		label, Config.Admin.CommandPrefix, Config.Admin.ConfirmTimeout))
end

local function resolveUserId(argument: string): (number?, string?)
	local numeric = tonumber(argument)
	if numeric and numeric > 0 and numeric == math.floor(numeric) then
		return numeric, nil
	end
	local ok, resolved = pcall(function()
		return Players:GetUserIdFromNameAsync(argument)
	end)
	if ok and type(resolved) == "number" then
		return resolved, nil
	end
	return nil, ("Joueur introuvable : %s"):format(argument)
end

local function usage(player: Player)
	local p = Config.Admin.CommandPrefix
	reply(player, ("Commandes : %s me | %s user <UserId|pseudo> | %s all | %s status | %s confirm | %s cancel")
		:format(p, p, p, p, p, p))
end

local function handleCommand(player: Player, action: string, argument: string?)
	if action == "" or action == "help" then
		usage(player)
		return
	end

	if action == "status" then
		local waiting = pending[player]
		local waitingLabel = if waiting and os.clock() < waiting.Expires then waiting.Label else "aucune"
		reply(player, ("Store profils : %s | classements : %s | en attente : %s"):format(
			DataService.StoreName(), Config.Data.LeaderboardVersion, waitingLabel))
		return
	end

	if action == "cancel" then
		pending[player] = nil
		reply(player, "Action annulée.")
		return
	end

	if action == "me" then
		arm(player, ("Réinitialiser %s (%d)"):format(player.Name, player.UserId), player.UserId)
		return
	end

	if action == "user" then
		if not argument or argument == "" then
			reply(player, ("Usage : %s user <UserId|pseudo>"):format(Config.Admin.CommandPrefix))
			return
		end
		local userId, err = resolveUserId(argument)
		if not userId then
			reply(player, err :: string)
			return
		end
		arm(player, ("Réinitialiser l'UserId %d"):format(userId), userId)
		return
	end

	if action == "all" then
		reply(player, ("Impossible à l'exécution : Roblox n'énumère pas les clés d'un DataStore. "
			.. "Change GameConfig.Data.StoreVersion (actuel : %s) puis republie ; l'ancien store est conservé.")
			:format(Config.Data.StoreVersion))
		return
	end

	if action == "confirm" then
		local action_ = pending[player]
		pending[player] = nil
		if not action_ then
			reply(player, "Aucune action en attente.")
			return
		end
		if os.clock() >= action_.Expires then
			reply(player, "Confirmation expirée, relance la commande.")
			return
		end
		-- Re-vérification de l'habilitation juste avant l'écriture.
		if not isAdmin(player) then
			warn(("[AdminService] confirmation refusée pour %s (%d) : plus admin"):format(player.Name, player.UserId))
			return
		end
		log("EXÉCUTION par %s (%d) : %s", player.Name, player.UserId, action_.Label)
		local ok, message = resetUserId(action_.TargetUserId)
		if not ok then
			warn("[AdminService] " .. message)
		end
		reply(player, message)
		return
	end

	usage(player)
end

local function onChatted(player: Player, message: string)
	local prefix = Config.Admin.CommandPrefix
	if message:sub(1, #prefix):lower() ~= prefix:lower() then
		return
	end
	local rest = message:sub(#prefix + 1)
	if rest ~= "" and rest:sub(1, 1) ~= " " then
		return
	end
	if not isAdmin(player) then
		warn(("[AdminService] commande refusée pour %s (%d)"):format(player.Name, player.UserId))
		return
	end

	local action, argument = rest:match("^%s*(%S*)%s*(.-)%s*$")
	handleCommand(player, (action or ""):lower(), argument)
end

function AdminService.Start()
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(message)
			onChatted(player, message)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.Chatted:Connect(function(message)
			onChatted(player, message)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)

	-- Secours pour la barre de commande Studio (contexte serveur) : _G.BPWReset(userId).
	-- Aucun client ne peut atteindre _G du serveur.
	if RunService:IsStudio() then
		(_G :: any).BPWReset = function(userId: number)
			local id = tonumber(userId)
			if not id then
				warn("[AdminService] _G.BPWReset attend un UserId numérique")
				return false
			end
			local ok, message = resetUserId(id)
			print("[AdminService] " .. message)
			return ok
		end
	end

	log("actif — store profils : %s", DataService.StoreName())
end

return AdminService
