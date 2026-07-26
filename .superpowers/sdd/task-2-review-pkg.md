# Review package Task 2 re-review
BASE: d535ceb HEAD: 7f24f7d9a4a14ba1b8b19f0b820fb754c53e8e2f
## Commits
7f24f7d fix: harden backpack reconcile and skip save while locked
b722e16 feat: persist backpack fields and sourced AddCoins

## Stat
 src/Server/DataService.lua | 76 ++++++++++++++++++++++++++++++++++++++++++++--
 1 file changed, 73 insertions(+), 3 deletions(-)

## Diff
```diff
diff --git a/src/Server/DataService.lua b/src/Server/DataService.lua
index a00008c..4f82755 100644
--- a/src/Server/DataService.lua
+++ b/src/Server/DataService.lua
@@ -8,30 +8,34 @@ local ReplicatedStorage = game:GetService("ReplicatedStorage")
 local Shared = ReplicatedStorage:WaitForChild("Shared")
 local Config = require(Shared.GameConfig)
 local Remotes = require(Shared.Remotes)
 
 local store = DataStoreService:GetDataStore("BPW_PlayerData_v1")
 
 local DataService = {}
 local profiles: { [Player]: any } = {}
+local mutationWaiter: ((Player, number) -> boolean)? = nil
 
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
+	CurrentBubbles = 0,
+	BackpackCapacity = Config.Backpack.DefaultCapacity,
+	PendingSellValue = 0,
 	Version = 1,
 }
 
 local function deepCopy(src)
 	local out = {}
 	for k, v in pairs(src) do
 		out[k] = if type(v) == "table" then deepCopy(v) else v
 	end
@@ -45,16 +49,47 @@ local function reconcile(data, template)
 			data[k] = if type(v) == "table" then deepCopy(v) else v
 		elseif type(v) == "table" and type(data[k]) == "table" then
 			reconcile(data[k], v)
 		end
 	end
 	return data
 end
 
+local function finiteNumber(value: any, fallback: number): number
+	local numberValue = tonumber(value)
+	if type(numberValue) ~= "number" or numberValue ~= numberValue
+		or numberValue == math.huge or numberValue == -math.huge then
+		return fallback
+	end
+	return numberValue
+end
+
+local function reconcileBackpack(data)
+	local capacity = math.clamp(
+		finiteNumber(data.BackpackCapacity, Config.Backpack.DefaultCapacity),
+		Config.Backpack.DefaultCapacity,
+		Config.Backpack.MaxCapacity
+	)
+	local bubbles = math.clamp(math.floor(finiteNumber(data.CurrentBubbles, 0)), 0, capacity)
+	local pending = math.max(0, math.floor(finiteNumber(data.PendingSellValue, 0)))
+
+	if bubbles == 0 then
+		pending = 0
+	elseif pending <= 0 then
+		warn("[DataService] sac r├⌐initialis├⌐ : bulles sans valeur de vente valide")
+		bubbles = 0
+		pending = 0
+	end
+
+	data.BackpackCapacity = capacity
+	data.CurrentBubbles = bubbles
+	data.PendingSellValue = pending
+end
+
 local function retry(fn, tries: number?)
 	local attempts = tries or 4
 	for i = 1, attempts do
 		local ok, res = pcall(fn)
 		if ok then return true, res end
 		if i == attempts then
 			warn("[DataService] ├⌐chec apr├¿s " .. attempts .. " tentatives: " .. tostring(res))
 			return false, res
@@ -63,22 +98,27 @@ local function retry(fn, tries: number?)
 	end
 	return false
 end
 
 function DataService.Get(player: Player)
 	return profiles[player]
 end
 
+function DataService.SetMutationWaiter(waiter: ((Player, number) -> boolean)?)
+	mutationWaiter = waiter
+end
+
 function DataService.Load(player: Player)
 	local ok, saved = retry(function()
 		return store:GetAsync("player_" .. player.UserId)
 	end)
 
 	local data = if ok and type(saved) == "table" then reconcile(saved, TEMPLATE) else deepCopy(TEMPLATE)
+	reconcileBackpack(data)
 	data.__loaded = ok            -- si false : on ne sauvegarde PAS (├⌐vite d'├⌐craser)
 	data.__joinClock = os.clock()
 	profiles[player] = data
 
 	-- leaderstats (classement natif Roblox)
 	local ls = Instance.new("Folder")
 	ls.Name = "leaderstats"
 	local coins = Instance.new("IntValue"); coins.Name = "Pi├¿ces"; coins.Parent = ls
@@ -92,36 +132,50 @@ end
 
 function DataService.Save(player: Player)
 	local data = profiles[player]
 	if not data then return end
 	if not data.__loaded then
 		warn("[DataService] sauvegarde ignor├⌐e pour " .. player.Name .. " (chargement ├⌐chou├⌐)")
 		return
 	end
+	if mutationWaiter then
+		local ok, unlocked = pcall(mutationWaiter, player, Config.World.MutationLockTimeout)
+		if not ok then
+			warn("[DataService] attente de mutation ├⌐chou├⌐e pour " .. player.Name)
+			return
+		elseif not unlocked then
+			warn("[DataService] d├⌐lai d'attente de mutation d├⌐pass├⌐ pour " .. player.Name)
+			return
+		end
+	end
 	data.Playtime += os.clock() - (data.__joinClock or os.clock())
 	data.__joinClock = os.clock()
 
 	local payload = deepCopy(data)
-	payload.__loaded, payload.__joinClock = nil, nil
+	payload.__loaded, payload.__joinClock, payload.__dirty = nil, nil, nil
 
 	retry(function()
 		store:SetAsync("player_" .. player.UserId, payload)
 	end)
 end
 
 function DataService.Release(player: Player)
 	DataService.Save(player)
 	profiles[player] = nil
 end
 
 -- Envoie au client un r├⌐sum├⌐ (jamais le profil complet).
 function DataService.Push(player: Player)
 	local d = profiles[player]
 	if not d then return end
+	player:SetAttribute("Coins", d.Coins)
+	player:SetAttribute("CurrentBubbles", d.CurrentBubbles)
+	player:SetAttribute("BackpackCapacity", d.BackpackCapacity)
+	player:SetAttribute("PendingSellValue", d.PendingSellValue)
 	local ls = player:FindFirstChild("leaderstats")
 	if ls then
 		(ls:FindFirstChild("Pi├¿ces") :: IntValue).Value = math.min(d.Coins, 2^31 - 1)
 		;(ls:FindFirstChild("Niveau") :: IntValue).Value = d.Level
 		;(ls:FindFirstChild("Bulles") :: IntValue).Value = math.min(d.Pops, 2^31 - 1)
 	end
 	Remotes.Event("StatsUpdate"):FireClient(player, {
 		Coins = d.Coins,
@@ -129,20 +183,36 @@ function DataService.Push(player: Player)
 		Level = d.Level,
 		XPNeeded = Config.XPForLevel(d.Level),
 		Pops = d.Pops,
 		Upgrades = d.Upgrades,
 		Worlds = d.Worlds,
 	})
 end
 
-function DataService.AddCoins(player: Player, amount: number)
+local CREDIT_SOURCES = {
+	BubbleSale = true,
+	Chest = true,
+	DailyReward = true,
+	Code = true,
+	Admin = true,
+}
+
+function DataService.AddCoins(player: Player, amount: number, source: string?): boolean
 	local d = profiles[player]
-	if not d then return end
+	if not d then return false end
+	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return false end
+	amount = math.floor(amount)
+	if amount <= 0 then return false end
+	if source ~= nil and not CREDIT_SOURCES[source] then
+		warn("[DataService] source inconnue:", source)
+	end
 	d.Coins = math.max(0, d.Coins + amount)
+	d.__dirty = true
+	return true
 end
 
 function DataService.AddXP(player: Player, amount: number)
 	local d = profiles[player]
 	if not d then return end
 	d.XP += amount
 	local leveled = false
 	while d.Level < Config.XP.MaxLevel do

```
