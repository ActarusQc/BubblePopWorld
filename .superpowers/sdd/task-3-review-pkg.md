# Task 3 re-review
HEAD: cba2fb0
## Diff
```diff
diff --git a/src/Server/BackpackService.lua b/src/Server/BackpackService.lua
new file mode 100644
index 0000000..1e67bcf
--- /dev/null
+++ b/src/Server/BackpackService.lua
@@ -0,0 +1,306 @@
+--!strict
+-- Sac ├á bulles : capacit├⌐, ajout/retrait atomiques et vente, sous un verrou de mutation par joueur.
+-- Toute mutation de CurrentBubbles / PendingSellValue passe par ce verrou (AddBubbles, RollbackAdd, Sell).
+
+local Players = game:GetService("Players")
+local HttpService = game:GetService("HttpService")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.GameConfig)
+local Remotes = require(Shared.Remotes)
+
+local DataService = require(script.Parent.DataService)
+
+export type Tx = {
+	Id: string,
+	StorageAdded: number,
+	SellValueAdded: number,
+	Gen: number,
+	Valid: boolean,
+}
+
+local BackpackService = {}
+
+-- Verrou de mutation par joueur : une seule op├⌐ration sac ├á la fois (AddBubbles/RollbackAdd/Sell).
+local locks: { [Player]: boolean } = {}
+local lastFullNotify: { [Player]: number } = {}
+-- Compteur de g├⌐n├⌐ration sac (session) : invalid├⌐ apr├¿s Sell pour bloquer les rollbacks p├⌐rim├⌐s.
+local gen: { [Player]: number } = {}
+
+local function getGen(player: Player): number
+	return gen[player] or 0
+end
+
+local function bumpGen(player: Player)
+	gen[player] = getGen(player) + 1
+end
+
+-- Invariant sym├⌐trique : sac vide Γçö valeur de vente nulle.
+local function enforceBackpackInvariant(d: any)
+	if d.CurrentBubbles <= 0 or d.PendingSellValue <= 0 then
+		d.CurrentBubbles = 0
+		d.PendingSellValue = 0
+	end
+end
+
+local function isFiniteNumber(value: any): boolean
+	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
+end
+
+local function acquire(player: Player): boolean
+	local deadline = os.clock() + Config.World.MutationLockTimeout
+	while locks[player] do
+		if os.clock() >= deadline then
+			return false
+		end
+		task.wait()
+	end
+	locks[player] = true
+	return true
+end
+
+local function release(player: Player)
+	locks[player] = nil
+end
+
+-- Ex├⌐cute `body` sous le verrou du joueur. Retourne (false) si le verrou n'a pas pu ├¬tre
+-- acquis (timeout) ou si `body` a lev├⌐ une erreur ; sinon (true, ...r├⌐sultats de body).
+local function runLocked(player: Player, body: () -> ...any): (boolean, ...any)
+	if not acquire(player) then
+		return false
+	end
+	local packed = table.pack(pcall(body))
+	release(player)
+	if not packed[1] then
+		warn(("[BackpackService] erreur sous verrou (%s) : %s"):format(player.Name, tostring(packed[2])))
+		return false
+	end
+	return true, table.unpack(packed, 2, packed.n)
+end
+
+function BackpackService.IsLocked(player: Player): boolean
+	return locks[player] == true
+end
+
+-- Attend que le verrou du joueur se lib├¿re (ou expire). N'acquiert PAS le verrou :
+-- utilis├⌐ par DataService.Save pour ├⌐viter de persister un ├⌐tat interm├⌐diaire.
+function BackpackService.WaitUnlocked(player: Player, timeout: number?): boolean
+	local deadline = os.clock() + (timeout or Config.World.MutationLockTimeout)
+	while locks[player] do
+		if os.clock() >= deadline then
+			return false
+		end
+		task.wait()
+	end
+	return true
+end
+
+function BackpackService.GetRemainingCapacity(player: Player): number
+	local d = DataService.Get(player)
+	if not d then
+		return 0
+	end
+	return math.max(0, d.BackpackCapacity - d.CurrentBubbles)
+end
+
+function BackpackService.IsFull(player: Player): boolean
+	local d = DataService.Get(player)
+	if not d then
+		return false
+	end
+	return d.CurrentBubbles >= d.BackpackCapacity
+end
+
+function BackpackService.CanAdd(player: Player, storageAmount: number): boolean
+	local d = DataService.Get(player)
+	if not d then
+		return false
+	end
+	if not isFiniteNumber(storageAmount) or storageAmount <= 0 then
+		return false
+	end
+	return d.CurrentBubbles + math.floor(storageAmount) <= d.BackpackCapacity
+end
+
+function BackpackService.GetStoredAmount(player: Player): number
+	local d = DataService.Get(player)
+	return if d then d.CurrentBubbles else 0
+end
+
+function BackpackService.GetSellValue(player: Player): number
+	local d = DataService.Get(player)
+	return if d then d.PendingSellValue else 0
+end
+
+-- Arrondi de la valeur de vente en attente (spec ┬º5.2) :
+-- floor(raw + 0.5), plancher ├á 1 si la bulle a une valeur de base positive,
+-- rejet (nil) si NaN / infini / n├⌐gatif.
+function BackpackService.RoundSellValue(raw: number, baseSellValue: number): number?
+	if not isFiniteNumber(raw) or raw < 0 then
+		return nil
+	end
+	local rounded = math.floor(raw + 0.5)
+	if isFiniteNumber(baseSellValue) and baseSellValue > 0 then
+		rounded = math.max(1, rounded)
+	end
+	return rounded
+end
+
+function BackpackService.NotifyFull(player: Player)
+	local now = os.clock()
+	local last = lastFullNotify[player]
+	if last and now - last < Config.Backpack.FullNotifyCooldown then
+		return
+	end
+	lastFullNotify[player] = now
+	Remotes.Event("Announce"):FireClient(player, "Ton sac est plein ! Va vendre tes bulles.", "backpack_full")
+end
+
+-- Doit ├¬tre appel├⌐ sous le verrou (voir AddBubbles).
+local function doAddBubbles(player: Player, storageAmount: number, sellValue: number): (boolean, string?, Tx?)
+	local d = DataService.Get(player)
+	if not d then
+		return false, "profil introuvable"
+	end
+	if d.CurrentBubbles + storageAmount > d.BackpackCapacity then
+		BackpackService.NotifyFull(player)
+		return false, "sac plein"
+	end
+
+	d.CurrentBubbles += storageAmount
+	d.PendingSellValue += sellValue
+	enforceBackpackInvariant(d)
+	d.__dirty = true
+
+	local tx: Tx = {
+		Id = HttpService:GenerateGUID(false),
+		StorageAdded = storageAmount,
+		SellValueAdded = sellValue,
+		Gen = getGen(player),
+		Valid = true,
+	}
+	return true, nil, tx
+end
+
+-- Ajoute atomiquement `storageAmount` bulles et `sellValue` (d├⌐j├á arrondi, voir RoundSellValue)
+-- au sac du joueur. Aucun ajout partiel : si la capacit├⌐ restante est insuffisante, rien n'est
+-- mut├⌐. Retourne un jeton de transaction (pas un snapshot complet) pour un ├⌐ventuel rollback.
+function BackpackService.AddBubbles(player: Player, storageAmount: number, sellValue: number): (boolean, string?, Tx?)
+	if not isFiniteNumber(storageAmount) or storageAmount <= 0 then
+		return false, "storageAmount invalide"
+	end
+	storageAmount = math.floor(storageAmount)
+
+	if not isFiniteNumber(sellValue) or sellValue <= 0 then
+		return false, "sellValue invalide"
+	end
+	sellValue = math.floor(sellValue)
+
+	local locked, ok, err, tx = runLocked(player, function()
+		return doAddBubbles(player, storageAmount, sellValue)
+	end)
+	if not locked then
+		return false, "verrou occup├⌐ (timeout)"
+	end
+	return ok :: boolean, err, tx
+end
+
+-- Doit ├¬tre appel├⌐ sous le verrou (voir RollbackAdd).
+local function doRollbackAdd(player: Player, tx: Tx?): boolean
+	if not tx or not tx.Valid then
+		return false
+	end
+	if tx.Gen ~= getGen(player) then
+		return false
+	end
+	local d = DataService.Get(player)
+	if not d then
+		tx.Valid = false
+		return false
+	end
+
+	d.CurrentBubbles = math.max(0, d.CurrentBubbles - tx.StorageAdded)
+	d.PendingSellValue = math.max(0, d.PendingSellValue - tx.SellValueAdded)
+	enforceBackpackInvariant(d)
+	d.__dirty = true
+
+	tx.Valid = false
+	return true
+end
+
+-- Annule uniquement le montant de cette transaction (pas de restauration d'un snapshot global) :
+-- s├╗r m├¬me si d'autres AddBubbles/Sell ont eu lieu entre-temps pour ce joueur.
+function BackpackService.RollbackAdd(player: Player, tx: Tx?): boolean
+	if not tx or not tx.Valid then
+		return false
+	end
+	local locked, ok = runLocked(player, function()
+		return doRollbackAdd(player, tx)
+	end)
+	return locked and ok == true
+end
+
+-- Doit ├¬tre appel├⌐ sous le verrou (voir Sell). Renvoie (sold, earned) en succ├¿s,
+-- ou (nil, nil, code) en ├⌐chec ; code Γêê { "empty", "no_profile", "credit_failed" }.
+local function doSell(player: Player): (number?, number?, string?)
+	local d = DataService.Get(player)
+	if not d then
+		return nil, nil, "no_profile"
+	end
+	if d.CurrentBubbles <= 0 or d.PendingSellValue <= 0 then
+		return nil, nil, "empty"
+	end
+
+	local sold = d.CurrentBubbles
+	local earned = d.PendingSellValue
+
+	local credited = DataService.AddCoins(player, earned, "BubbleSale")
+	if not credited then
+		return nil, nil, "credit_failed"
+	end
+
+	-- Vider le sac imm├⌐diatement en m├⌐moire : aucun ├⌐tat interm├⌐diaire observable hors verrou.
+	d.CurrentBubbles = 0
+	d.PendingSellValue = 0
+	bumpGen(player)
+	d.__dirty = true
+
+	return sold, earned, nil
+end
+
+-- Vend tout le sac du joueur sous le m├¬me verrou que AddBubbles/RollbackAdd (pas de drapeau
+-- IsSelling s├⌐par├⌐ qui pourrait courir avec un pop concurrent). Aucune requ├¬te DataStore ici.
+function BackpackService.Sell(player: Player): (number?, number?, string?)
+	local locked, sold, earned, err = runLocked(player, function()
+		return doSell(player)
+	end)
+
+	if not locked then
+		warn("[BackpackService] vente ignor├⌐e pour " .. player.Name .. " : verrou occup├⌐")
+		return nil, nil, "verrou occup├⌐ (timeout)"
+	end
+
+	if sold and earned then
+		DataService.Push(player)
+		Remotes.Event("Announce"):FireClient(player, ("Sac vendu : +%d pi├¿ces !"):format(earned), "sell")
+		return sold, earned, nil
+	end
+
+	if err == "empty" then
+		Remotes.Event("Announce"):FireClient(player, "Ton sac est vide, rien ├á vendre.", "sell")
+	end
+	return nil, nil, err
+end
+
+function BackpackService.Start()
+	DataService.SetMutationWaiter(BackpackService.WaitUnlocked)
+
+	Players.PlayerRemoving:Connect(function(player)
+		locks[player] = nil
+		lastFullNotify[player] = nil
+		gen[player] = nil
+	end)
+end
+
+return BackpackService
diff --git a/src/Server/init.server.lua b/src/Server/init.server.lua
index 20f51d0..8022262 100644
--- a/src/Server/init.server.lua
+++ b/src/Server/init.server.lua
@@ -1,16 +1,17 @@
 --!strict
 -- Point d'entr├⌐e serveur : ordre de d├⌐marrage explicite.
 
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
 require(ReplicatedStorage:WaitForChild("Shared").Remotes) -- cr├⌐e les remotes en premier
 
 local services = {
 	require(script.DataService),
+	require(script.BackpackService),
 	require(script.GlobalCounterService),
 	require(script.ComboService),
 	require(script.AmbianceService),
 	require(script.BubbleService),
 	require(script.ToolService),
 	require(script.DropService),
 	require(script.ChestService),
 	require(script.ShopService),

```
