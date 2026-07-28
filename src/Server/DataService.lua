--!strict
-- Persistance des profils joueurs (DataStore + verrou de session simple).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local store = DataStoreService:GetDataStore(Config.PlayerStoreName())

local DataService = {}
local profiles: { [Player]: any } = {}
local mutationWaiter: ((Player, number) -> boolean)? = nil
local coinsChangedListeners: { (Player, number) -> () } = {}

local function notifyCoinsChanged(player: Player)
	local d = profiles[player]
	if not d then
		return
	end
	local coins = d.Coins
	for _, listener in ipairs(coinsChangedListeners) do
		task.spawn(listener, player, coins)
	end
end

function DataService.OnCoinsChanged(listener: (Player, number) -> ())
	table.insert(coinsChangedListeners, listener)
end

function DataService.NotifyCoinsChanged(player: Player)
	notifyCoinsChanged(player)
end

-- XP : champ hérité, conservé pour ne pas perdre les anciens profils, mais gelé —
-- il ne pilote plus le niveau (voir TotalBubblesSold) et n'est plus incrémenté ni affiché.
local TEMPLATE = {
	Coins = 0,
	XP = 0,
	Level = 1,
	TotalBubblesSold = 0,
	Pops = 0,
	Playtime = 0,
	ChestsOpened = 0,
	MythicsFound = 0,
	Upgrades = { Speed = 0, Jump = 0, Power = 0, CoinMult = 0, XPMult = 0 },
	Worlds = { "Prairie" },
	Cosmetics = {},
	Titles = {},
	EquippedTitle = "",
	OwnedItems = {},
	EquippedBackpack = "",
	CurrentBubbles = 0,
	BackpackCapacity = Config.Backpack.DefaultCapacity,
	PendingSellValue = 0,
	MusicMuted = false,
	Version = 1,
}

local function deepCopy(src)
	local out = {}
	for k, v in pairs(src) do
		out[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return out
end

-- Ajoute les nouvelles clés du template sans écraser les données existantes.
local function reconcile(data, template)
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = if type(v) == "table" then deepCopy(v) else v
		elseif type(v) == "table" and type(data[k]) == "table" then
			reconcile(data[k], v)
		end
	end
	return data
end

local function finiteNumber(value: any, fallback: number): number
	local numberValue = tonumber(value)
	if type(numberValue) ~= "number" or numberValue ~= numberValue
		or numberValue == math.huge or numberValue == -math.huge then
		return fallback
	end
	return numberValue
end

local function reconcileOwnedItems(data)
	if type(data.OwnedItems) ~= "table" then
		data.OwnedItems = {}
	end
	local cleaned: { [string]: boolean } = {}
	for id, owned in pairs(data.OwnedItems) do
		if type(id) == "string" and owned == true and Config.ShopItems[id] ~= nil then
			cleaned[id] = true
		end
	end
	data.OwnedItems = cleaned

	local equipped = data.EquippedBackpack
	if type(equipped) ~= "string" then
		equipped = ""
	end
	if equipped ~= "" then
		local def = Config.ShopItems[equipped]
		if not cleaned[equipped] or not def or def.Kind ~= "Backpack" then
			equipped = ""
		end
	end
	data.EquippedBackpack = equipped
	data.BackpackCapacity = Config.BackpackCapacityFor(equipped)
end

local function reconcileBackpack(data)
	local capacity = math.clamp(
		finiteNumber(data.BackpackCapacity, Config.Backpack.DefaultCapacity),
		Config.Backpack.DefaultCapacity,
		Config.Backpack.MaxCapacity
	)
	local bubbles = math.clamp(math.floor(finiteNumber(data.CurrentBubbles, 0)), 0, capacity)
	local pending = math.max(0, math.floor(finiteNumber(data.PendingSellValue, 0)))

	if bubbles == 0 then
		pending = 0
	elseif pending <= 0 then
		warn("[DataService] sac réinitialisé : bulles sans valeur de vente valide")
		bubbles = 0
		pending = 0
	end

	data.BackpackCapacity = capacity
	data.CurrentBubbles = bubbles
	data.PendingSellValue = pending
end

-- TotalBubblesSold est l'unique source de vérité du niveau : on l'assainit au chargement
-- puis on recalcule Level, y compris pour un profil antérieur où Level venait de l'XP.
local function reconcileProgression(data)
	data.TotalBubblesSold = math.max(0, math.floor(finiteNumber(data.TotalBubblesSold, 0)))
	data.Level = Config.LevelForBubbles(data.TotalBubblesSold)
end

local function retry(fn, tries: number?)
	local attempts = tries or 4
	for i = 1, attempts do
		local ok, res = pcall(fn)
		if ok then return true, res end
		if i == attempts then
			warn("[DataService] échec après " .. attempts .. " tentatives: " .. tostring(res))
			return false, res
		end
		task.wait(2 ^ i)
	end
	return false
end

function DataService.Get(player: Player)
	return profiles[player]
end

-- Source autoritaire du niveau (HUD + barrières zones). Jamais d'attribut client.
function DataService.GetPlayerLevel(player: Player): number
	local d = profiles[player]
	if d and type(d.Level) == "number" then
		return d.Level
	end
	return 1
end

local function refreshZoneAccess(player: Player)
	task.defer(function()
		local ok, ZoneService = pcall(function()
			return require(script.Parent.ZoneService)
		end)
		if ok and ZoneService and ZoneService.RefreshPlayerAccess then
			ZoneService.RefreshPlayerAccess(player)
		end
	end)
end

function DataService.SetMutationWaiter(waiter: ((Player, number) -> boolean)?)
	mutationWaiter = waiter
end

function DataService.Load(player: Player)
	local ok, saved = retry(function()
		return store:GetAsync(Config.PlayerKey(player.UserId))
	end)

	local data = if ok and type(saved) == "table" then reconcile(saved, TEMPLATE) else deepCopy(TEMPLATE)
	reconcileOwnedItems(data)
	reconcileBackpack(data)
	reconcileProgression(data)
	data.MusicMuted = data.MusicMuted == true
	data.__loaded = ok            -- si false : on ne sauvegarde PAS (évite d'écraser)
	data.__joinClock = os.clock()
	profiles[player] = data

	-- leaderstats (classement natif Roblox)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue"); coins.Name = "Coins"; coins.Parent = ls
	local level = Instance.new("IntValue"); level.Name = "Level"; level.Parent = ls
	local pops  = Instance.new("IntValue"); pops.Name = "Bubbles"; pops.Parent = ls
	ls.Parent = player

	DataService.Push(player)
	-- Collision groups / portes : appliquer dès que le profil (niveau HUD) est connu.
	refreshZoneAccess(player)
	if data.__loaded then
		notifyCoinsChanged(player)
	end
	return data
end

function DataService.Save(player: Player)
	local data = profiles[player]
	if not data then return end
	if not data.__loaded then
		warn("[DataService] sauvegarde ignorée pour " .. player.Name .. " (chargement échoué)")
		return
	end
	if mutationWaiter then
		local ok, unlocked = pcall(mutationWaiter, player, Config.World.MutationLockTimeout)
		if not ok then
			warn("[DataService] attente de mutation échouée pour " .. player.Name)
			return
		elseif not unlocked then
			warn("[DataService] délai d'attente de mutation dépassé pour " .. player.Name)
			return
		end
	end
	data.Playtime += os.clock() - (data.__joinClock or os.clock())
	data.__joinClock = os.clock()

	local payload = deepCopy(data)
	payload.__loaded, payload.__joinClock, payload.__dirty = nil, nil, nil

	retry(function()
		store:SetAsync(Config.PlayerKey(player.UserId), payload)
	end)
end

function DataService.Release(player: Player)
	DataService.Save(player)
	profiles[player] = nil
end

function DataService.StoreName(): string
	return Config.PlayerStoreName()
end

-- Remet le profil en mémoire au TEMPLATE. À appeler sous le verrou de mutation du sac
-- (voir BackpackService.ResetSession) : sinon un pop concurrent réinjecte des bulles.
function DataService.ResetProfile(player: Player): boolean
	if not profiles[player] then
		return false
	end
	local fresh = deepCopy(TEMPLATE)
	fresh.__loaded = true
	fresh.__joinClock = os.clock()
	fresh.__dirty = true
	profiles[player] = fresh
	DataService.ApplyCharacterStats(player)
	DataService.Push(player)
	notifyCoinsChanged(player)
	return true
end

-- Efface la clé persistée d'un joueur hors ligne : au prochain chargement il repart du
-- TEMPLATE. S'il est connecté sur un autre serveur, sa sauvegarde de sortie annulera ceci.
function DataService.ResetStoredProfile(userId: number): boolean
	local ok = retry(function()
		store:RemoveAsync(Config.PlayerKey(userId))
	end)
	return ok == true
end

-- Envoie au client un résumé (jamais le profil complet).
function DataService.Push(player: Player)
	local d = profiles[player]
	if not d then return end
	player:SetAttribute("Coins", d.Coins)
	player:SetAttribute("CurrentBubbles", d.CurrentBubbles)
	player:SetAttribute("BackpackCapacity", d.BackpackCapacity)
	player:SetAttribute("PendingSellValue", d.PendingSellValue)
	player:SetAttribute("TotalBubblesSold", d.TotalBubblesSold)
	player:SetAttribute("EquippedBackpack", d.EquippedBackpack or "")
	player:SetAttribute("PlayerLevel", d.Level)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Coins") :: IntValue).Value = math.min(d.Coins, 2^31 - 1)
		;(ls:FindFirstChild("Level") :: IntValue).Value = d.Level
		;(ls:FindFirstChild("Bubbles") :: IntValue).Value = math.min(d.Pops, 2^31 - 1)
	end
	local nextLevel = d.Level + 1
	Remotes.Event("StatsUpdate"):FireClient(player, {
		Coins = d.Coins,
		Level = d.Level,
		Pops = d.Pops,
		BubblesSold = d.TotalBubblesSold,
		LevelStart = Config.BubblesForLevel(d.Level),
		-- nil au niveau max : le HUD affiche alors « MAX ».
		NextLevelAt = if nextLevel <= Config.Progression.MaxLevel then Config.BubblesForLevel(nextLevel) else nil,
		Upgrades = d.Upgrades,
		Worlds = d.Worlds,
		OwnedItems = d.OwnedItems,
		EquippedBackpack = d.EquippedBackpack or "",
		MusicMuted = d.MusicMuted == true,
	})
end

local CREDIT_SOURCES = {
	BubbleSale = true,
	Chest = true,
	DailyReward = true,
	Code = true,
	Admin = true,
}

function DataService.AddCoins(player: Player, amount: number, source: string?): boolean
	local d = profiles[player]
	if not d then return false end
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return false end
	amount = math.floor(amount)
	if amount <= 0 then return false end
	if source ~= nil and not CREDIT_SOURCES[source] then
		warn("[DataService] source inconnue:", source)
	end
	d.Coins = math.max(0, d.Coins + amount)
	d.__dirty = true
	notifyCoinsChanged(player)
	return true
end

-- Unique source de progression permanente : les bulles réellement vendues au kiosque.
-- Appelée sous le verrou du sac par BackpackService, après le débit effectif du sac.
function DataService.AddBubblesSold(player: Player, amount: number): boolean
	local d = profiles[player]
	if not d then return false end
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return false end
	amount = math.floor(amount)
	if amount <= 0 then return false end

	d.TotalBubblesSold += amount
	d.__dirty = true

	local newLevel = Config.LevelForBubbles(d.TotalBubblesSold)
	if newLevel > d.Level then
		d.Level = newLevel
		DataService.ApplyCharacterStats(player)
		DataService.UnlockWorlds(player)
		Remotes.Event("Announce"):FireClient(player, ("Level %d reached!"):format(d.Level), "level")
		-- Accès zones (collision groups) immédiat, sans respawn.
		refreshZoneAccess(player)
	end
	return true
end

function DataService.UnlockWorlds(player: Player)
	local d = profiles[player]
	if not d then return end
	for _, world in ipairs(Config.Worlds) do
		if d.Level >= world.LevelReq and not table.find(d.Worlds, world.Id) then
			table.insert(d.Worlds, world.Id)
			Remotes.Event("Announce"):FireClient(player, ("New world unlocked: %s"):format(world.Label), "world")
		end
	end
end

function DataService.Multipliers(player: Player): number
	local d = profiles[player]
	if not d then return 1 end
	local coinLevel = Config.EffectiveUpgradeLevel("CoinMult", d.Upgrades.CoinMult or 0)
	return 1 + coinLevel * Config.Upgrades.CoinMult.PerLevel
end

-- Vitesse et saut sont décidés par le serveur à chaque apparition du personnage.
function DataService.ApplyCharacterStats(player: Player)
	local d = profiles[player]
	local char = player.Character
	if not d or not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local M = Config.PlayerMovement
	local speedLevel = Config.EffectiveUpgradeLevel("Speed", d.Upgrades.Speed or 0)
	local jumpLevel = Config.EffectiveUpgradeLevel("Jump", d.Upgrades.Jump or 0)
	hum.WalkSpeed = math.clamp(
		M.WalkSpeed + speedLevel * Config.Upgrades.Speed.PerLevel, 0, M.MaxWalkSpeed)
	hum.UseJumpPower = M.UseJumpPower
	hum.JumpPower = math.clamp(
		M.JumpPower + jumpLevel * Config.Upgrades.Jump.PerLevel, 0, M.MaxJumpPower)
end

function DataService.Start()
	-- Valeurs de départ appliquées par Roblox dès l'apparition, avant même
	-- ApplyCharacterStats : évite une frame de saut à la hauteur par défaut.
	local M = Config.PlayerMovement
	StarterPlayer.CharacterUseJumpPower = M.UseJumpPower
	StarterPlayer.CharacterJumpPower = M.JumpPower
	StarterPlayer.CharacterWalkSpeed = M.WalkSpeed

	Remotes.Event("SetMusicMuted").OnServerEvent:Connect(function(player: Player, muted: any)
		if typeof(muted) ~= "boolean" then
			return
		end
		local d = profiles[player]
		if not d or d.__loaded ~= true then
			return
		end
		if d.MusicMuted == muted then
			return
		end
		d.MusicMuted = muted
		d.__dirty = true
		DataService.Push(player)
	end)

	local bound: { [Player]: boolean } = {}

	local function bindPlayer(player: Player)
		if bound[player] then
			return
		end
		bound[player] = true

		DataService.Load(player)
		local function onCharacter(character: Model)
			character:WaitForChild("Humanoid", 10)
			DataService.ApplyCharacterStats(player)
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end

	Players.PlayerAdded:Connect(bindPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		bound[player] = nil
		DataService.Release(player)
	end)

	-- Sauvegarde automatique échelonnée
	task.spawn(function()
		while task.wait(60) do
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(DataService.Save, player)
				task.wait(0.5)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(DataService.Save, player)
		end
		task.wait(3)
	end)
end

return DataService
