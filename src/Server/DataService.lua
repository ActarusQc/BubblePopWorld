--!strict
-- Persistance des profils joueurs (DataStore + verrou de session simple).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local store = DataStoreService:GetDataStore("BPW_PlayerData_v1")

local DataService = {}
local profiles: { [Player]: any } = {}

local TEMPLATE = {
	Coins = 0,
	XP = 0,
	Level = 1,
	Pops = 0,
	Playtime = 0,
	ChestsOpened = 0,
	MythicsFound = 0,
	Upgrades = { Speed = 0, Jump = 0, Power = 0, CoinMult = 0, XPMult = 0 },
	Worlds = { "Prairie" },
	Cosmetics = {},
	Titles = {},
	EquippedTitle = "",
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

function DataService.Load(player: Player)
	local ok, saved = retry(function()
		return store:GetAsync("player_" .. player.UserId)
	end)

	local data = if ok and type(saved) == "table" then reconcile(saved, TEMPLATE) else deepCopy(TEMPLATE)
	data.__loaded = ok            -- si false : on ne sauvegarde PAS (évite d'écraser)
	data.__joinClock = os.clock()
	profiles[player] = data

	-- leaderstats (classement natif Roblox)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue"); coins.Name = "Pièces"; coins.Parent = ls
	local level = Instance.new("IntValue"); level.Name = "Niveau"; level.Parent = ls
	local pops  = Instance.new("IntValue"); pops.Name = "Bulles";  pops.Parent = ls
	ls.Parent = player

	DataService.Push(player)
	return data
end

function DataService.Save(player: Player)
	local data = profiles[player]
	if not data then return end
	if not data.__loaded then
		warn("[DataService] sauvegarde ignorée pour " .. player.Name .. " (chargement échoué)")
		return
	end
	data.Playtime += os.clock() - (data.__joinClock or os.clock())
	data.__joinClock = os.clock()

	local payload = deepCopy(data)
	payload.__loaded, payload.__joinClock = nil, nil

	retry(function()
		store:SetAsync("player_" .. player.UserId, payload)
	end)
end

function DataService.Release(player: Player)
	DataService.Save(player)
	profiles[player] = nil
end

-- Envoie au client un résumé (jamais le profil complet).
function DataService.Push(player: Player)
	local d = profiles[player]
	if not d then return end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Pièces") :: IntValue).Value = math.min(d.Coins, 2^31 - 1)
		;(ls:FindFirstChild("Niveau") :: IntValue).Value = d.Level
		;(ls:FindFirstChild("Bulles") :: IntValue).Value = math.min(d.Pops, 2^31 - 1)
	end
	Remotes.Event("StatsUpdate"):FireClient(player, {
		Coins = d.Coins,
		XP = d.XP,
		Level = d.Level,
		XPNeeded = Config.XPForLevel(d.Level),
		Pops = d.Pops,
		Upgrades = d.Upgrades,
		Worlds = d.Worlds,
	})
end

function DataService.AddCoins(player: Player, amount: number)
	local d = profiles[player]
	if not d then return end
	d.Coins = math.max(0, d.Coins + amount)
end

function DataService.AddXP(player: Player, amount: number)
	local d = profiles[player]
	if not d then return end
	d.XP += amount
	local leveled = false
	while d.Level < Config.XP.MaxLevel do
		local need = Config.XPForLevel(d.Level)
		if d.XP < need then break end
		d.XP -= need
		d.Level += 1
		leveled = true
	end
	if leveled then
		DataService.ApplyCharacterStats(player)
		DataService.UnlockWorlds(player)
		Remotes.Event("Announce"):FireClient(player, ("Niveau %d atteint !"):format(d.Level), "level")
	end
end

function DataService.UnlockWorlds(player: Player)
	local d = profiles[player]
	if not d then return end
	for _, world in ipairs(Config.Worlds) do
		if d.Level >= world.LevelReq and not table.find(d.Worlds, world.Id) then
			table.insert(d.Worlds, world.Id)
			Remotes.Event("Announce"):FireClient(player, ("Nouveau monde débloqué : %s"):format(world.Label), "world")
		end
	end
end

function DataService.Multipliers(player: Player): (number, number)
	local d = profiles[player]
	if not d then return 1, 1 end
	local coin = 1 + d.Upgrades.CoinMult * Config.Upgrades.CoinMult.PerLevel
	local xp = 1 + d.Upgrades.XPMult * Config.Upgrades.XPMult.PerLevel
	return coin, xp
end

function DataService.ApplyCharacterStats(player: Player)
	local d = profiles[player]
	local char = player.Character
	if not d or not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.WalkSpeed = Config.Character.BaseWalkSpeed + d.Upgrades.Speed * Config.Upgrades.Speed.PerLevel
	hum.UseJumpPower = true
	hum.JumpPower = Config.Character.BaseJumpPower + d.Upgrades.Jump * Config.Upgrades.Jump.PerLevel
end

function DataService.Start()
	Players.PlayerAdded:Connect(function(player)
		DataService.Load(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			DataService.ApplyCharacterStats(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
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
