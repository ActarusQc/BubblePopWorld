# Task 5 review
BASE: e01d49f HEAD: fef778dfb64333702370460d2cd20f793d82f9ff
## Commits
fef778d feat: route bubble rewards through backpack with cell claim tokens

## Stat
 src/Server/BubbleService.lua | 181 +++++++++++++++++++++++++++++++++----------
 src/Server/ChestService.lua  |   3 +-
 2 files changed, 142 insertions(+), 42 deletions(-)

## Diff
```diff
diff --git a/src/Server/BubbleService.lua b/src/Server/BubbleService.lua
index 7727708..f3a8649 100644
--- a/src/Server/BubbleService.lua
+++ b/src/Server/BubbleService.lua
@@ -1,24 +1,26 @@
 --!strict
 -- C┼ôur du jeu : g├⌐n├⌐ration de la grille, ├⌐clatement, r├⌐g├⌐n├⌐ration,
--- r├⌐compenses, anti-exploit et diffusion group├⌐e des effets.
+-- r├⌐compenses (sac uniquement, jamais de pi├¿ces), anti-exploit
+-- et diffusion group├⌐e des effets.
 
 local Players = game:GetService("Players")
 local RunService = game:GetService("RunService")
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
 
 local Shared = ReplicatedStorage:WaitForChild("Shared")
 local Config = require(Shared.GameConfig)
 local BubbleTypes = require(Shared.BubbleTypes)
 local Remotes = require(Shared.Remotes)
 
 local DataService = require(script.Parent.DataService)
+local BackpackService = require(script.Parent.BackpackService)
 local GlobalCounterService = require(script.Parent.GlobalCounterService)
 local ComboService = require(script.Parent.ComboService)
 local AmbianceService = require(script.Parent.AmbianceService)
 
 local G = Config.Grid
 local B = Config.Bubble
 
 local BubbleService = {}
 local grid: { [number]: { [number]: any } } = {}
 local rng = Random.new()
@@ -206,29 +208,22 @@ end
 function BubbleService.BuildWorld(worldDef)
 	currentWorld = worldDef or currentWorld
 
 	if worldFolder then worldFolder:Destroy() end
 	grid = {}
 
 	worldFolder = Instance.new("Folder")
 	worldFolder.Name = "BubbleWorld"
 	worldFolder.Parent = workspace
 
-	-- Plancher sous la nappe de bulles (pas de film blanc)
-	local floor = Instance.new("Part")
-	floor.Name = "Floor"
-	floor.Anchored = true
-	floor.Size = Vector3.new(G.SizeX * G.Spacing + 40, 4, G.SizeZ * G.Spacing + 40)
-	floor.CFrame = CFrame.new(G.Origin - Vector3.new(0, 3, 0))
-	floor.Color = currentWorld.Ground
-	floor.Material = Enum.Material.Sand
-	floor.Parent = worldFolder
+	-- Aucun plancher continu sous la grille (spec ┬º8.6) : la chute entre les cases
+	-- vides est voulue ; ZoneService g├¿re les barri├¿res lat├⌐rales et le FallReset.
 
 	for x = 1, G.SizeX do
 		grid[x] = {}
 		for z = 1, G.SizeZ do
 			grid[x][z] = buildBubble(x, z)
 		end
 		if x % 6 == 0 then task.wait() end -- ├⌐vite le gel du serveur au d├⌐marrage
 	end
 
 	AmbianceService.Apply(currentWorld)
@@ -243,75 +238,179 @@ local function regen(cell)
 	cell.alive = true
 	cell.part.CanCollide = true
 	cell.part.CanQuery = true
 	cell.part.CanTouch = true
 	cell.part:SetAttribute("Alive", true)
 	cell.part.CFrame = cell.home
 	cell.mesh.Scale = B.MeshScale
 	applyBubbleAppearance(cell.part, cell.def, cell.tintIndex, true)
 end
 
--- Retourne pi├¿ces, xp, def (ou nil si la bulle n'├⌐tait pas disponible)
-local function popCell(x: number, z: number)
-	if not BubbleService.InBounds(x, z) then return nil end
-	local cell = grid[x] and grid[x][z]
-	if not cell or not cell.alive then return nil end
+--------------------------------------------------------------------
+-- Verrou de cellule : jeton unique, un seul joueur gagne la course
+--------------------------------------------------------------------
+local function tryClaim(cell: any): any?
+	if not cell.alive or cell.popClaim ~= nil then return nil end
+	local token = {}
+	cell.popClaim = token
+	return token
+end
+
+local function releaseClaim(cell: any, token: any)
+	if cell.popClaim == token then
+		cell.popClaim = nil
+	end
+end
+
+-- Mutation r├⌐elle de la bulle. Retourne false si la case n'est plus ├⌐clatable.
+local function applyPop(cell: any, x: number, z: number): boolean
+	if not cell.alive then return false end
+	local part = cell.part :: BasePart?
+	if not part or not part.Parent then return false end
 
-	local def = cell.def
 	cell.alive = false
-	cell.part.CanCollide = false
+	part.CanCollide = false
 	-- CanQuery = false : le raycast client traverse la case vide (plus de faux rebonds)
-	cell.part.CanQuery = false
-	cell.part.CanTouch = false
-	cell.part.Transparency = 1
-	cell.part:SetAttribute("Alive", false)
+	part.CanQuery = false
+	part.CanTouch = false
+	part.Transparency = 1
+	part:SetAttribute("Alive", false)
 
-	table.insert(effectQueue, { x, z, def.Id })
+	table.insert(effectQueue, { x, z, cell.def.Id })
 	task.delay(B.RegenTime, function()
 		if cell.part.Parent then regen(cell) end
 	end)
 
-	return def
+	return true
+end
+
+local function positiveNumber(value: any, fallback: number): number
+	local n = tonumber(value)
+	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge or n <= 0 then
+		return fallback
+	end
+	return n
+end
+
+type PopContext = {
+	coinMult: number,
+	xpMult: number,
+	worldMult: number,
+	extra: number,
+	combo: () -> number,
+}
+
+-- Traite une cellule d├⌐j├á r├⌐serv├⌐e (claim pos├⌐ par l'appelant).
+-- Retourne "ok" (+ def), "full" (sac plein) ou "skip".
+local function popClaimedCell(player: Player, cell: any, x: number, z: number, ctx: PopContext): (string, any?)
+	if not cell.alive then return "skip" end
+
+	local def = cell.def
+	if type(def) ~= "table" or type(def.Id) ~= "string" then return "skip" end
+
+	local storage = math.max(1, math.floor(positiveNumber(def.StorageValue, 1)))
+	if not BackpackService.CanAdd(player, storage) then
+		return "full"
+	end
+
+	local baseSell = positiveNumber(def.SellValue, positiveNumber(def.Coins, 1))
+	local raw = baseSell * ctx.coinMult * ctx.worldMult * ctx.extra * ctx.combo()
+	local sellValue = BackpackService.RoundSellValue(raw, baseSell)
+	if not sellValue or sellValue <= 0 then return "skip" end
+
+	local added, err, tx = BackpackService.AddBubbles(player, storage, sellValue)
+	if not added then
+		return if err == "sac plein" then "full" else "skip"
+	end
+
+	-- Le pop r├⌐el est le seul point o├╣ une erreur Lua laisserait une transaction
+	-- orpheline : on le prot├¿ge explicitement pour garantir le rollback.
+	local popOk, popped = pcall(applyPop, cell, x, z)
+	if not popOk then
+		warn(("[BubbleService] pop ├⌐chou├⌐ en %d,%d : %s"):format(x, z, tostring(popped)))
+	end
+	if not popOk or popped ~= true then
+		BackpackService.RollbackAdd(player, tx)
+		return "skip"
+	end
+
+	return "ok", def
 end
 
 -- API publique : ├⌐clate une liste de cellules pour un joueur.
-function BubbleService.PopCells(player: Player, cells: { { number } }, multiplier: number?)
-	local profile = DataService.Get(player)
-	if not profile then return 0 end
+-- Les bulles ne cr├⌐ditent JAMAIS de pi├¿ces ici : elles remplissent le sac
+-- (vente via BackpackService.Sell). L'XP reste imm├⌐diate apr├¿s un pop r├⌐ussi.
+function BubbleService.PopCells(player: Player, cells: { { number } }, multiplier: number?): number
+	if not DataService.Get(player) then return 0 end
 
 	local coinMult, xpMult = DataService.Multipliers(player)
-	local worldMult = currentWorld.Mult
-	local extra = multiplier or 1
 
-	local coins, xp, count = 0, 0, 0
+	-- Le combo n'est enregistr├⌐ qu'une fois par lot, et seulement si au moins une
+	-- cellule est r├⌐ellement sur le point d'├¬tre ajout├⌐e au sac.
+	local comboMult: number? = nil
+	local ctx: PopContext = {
+		coinMult = coinMult,
+		xpMult = xpMult,
+		worldMult = currentWorld.Mult,
+		extra = multiplier or 1,
+		combo = function(): number
+			if not comboMult then
+				comboMult = ComboService.Register(player)
+			end
+			return comboMult :: number
+		end,
+	}
+
+	local rawXP, count = 0, 0
 	local announce = nil
+	local notifiedFull = false
 
 	for _, c in ipairs(cells) do
-		local def = popCell(c[1], c[2])
-		if def then
-			coins += def.Coins
-			xp += def.XP
-			count += 1
-			if def.Announce then announce = def end
+		local x, z = c[1], c[2]
+		if BubbleService.InBounds(x, z) then
+			local cell = grid[x] and grid[x][z]
+			if cell then
+				local token = tryClaim(cell)
+				if token then
+					local status: string? = nil
+					local def: any = nil
+					local ok = xpcall(function()
+						status, def = popClaimedCell(player, cell, x, z, ctx)
+					end, function(err)
+						warn(("[BubbleService] erreur de pop en %d,%d : %s"):format(x, z, tostring(err)))
+					end)
+					releaseClaim(cell, token) -- garanti sur tous les chemins
+
+					if ok and status == "ok" and def then
+						rawXP += positiveNumber(def.XP, 0)
+						count += 1
+						if def.Announce then announce = def end
+					elseif ok and status == "full" and not notifiedFull then
+						notifiedFull = true
+						BackpackService.NotifyFull(player)
+					end
+				end
+			end
 		end
 	end
 
 	if count == 0 then return 0 end
 
-	local comboMult = ComboService.Register(player)
-
-	coins = math.floor(coins * coinMult * worldMult * extra * comboMult)
-	xp = math.floor(xp * xpMult * extra * comboMult)
+	local profile = DataService.Get(player)
+	if not profile then return count end
 
-	DataService.AddCoins(player, coins)
-	DataService.AddXP(player, xp)
+	local xp = math.floor(rawXP * xpMult * ctx.extra * (comboMult or 1))
+	if xp > 0 then
+		DataService.AddXP(player, xp)
+	end
 	profile.Pops += count
+	profile.__dirty = true
 	DataService.Push(player)
 	GlobalCounterService.Add(count)
 
 	if announce then
 		Remotes.Event("Announce"):FireAllClients(
 			("%s a ├⌐clat├⌐ une %s !"):format(player.DisplayName, announce.Label), "legendary")
 	end
 
 	return count
 end
diff --git a/src/Server/ChestService.lua b/src/Server/ChestService.lua
index 3c322e6..2d81050 100644
--- a/src/Server/ChestService.lua
+++ b/src/Server/ChestService.lua
@@ -74,21 +74,22 @@ local function spawnChest()
 
 	local claimed = false
 	prompt.Triggered:Connect(function(player)
 		if claimed then return end
 		claimed = true
 
 		local coins = rng:NextInteger(tier.Coins[1], tier.Coins[2])
 		local worldMult = BubbleService.CurrentWorld().Mult
 		coins = math.floor(coins * worldMult)
 
-		DataService.AddCoins(player, coins)
+		-- Les coffres restent une source directe de pi├¿ces (hors sac, spec ┬º2).
+		DataService.AddCoins(player, coins, "Chest")
 		DataService.AddXP(player, tier.XP)
 		local profile = DataService.Get(player)
 		if profile then profile.ChestsOpened += 1 end
 		DataService.Push(player)
 
 		Remotes.Event("Announce"):FireAllClients(
 			("%s a ouvert un coffre %s (+%d pi├¿ces)"):format(player.DisplayName, tier.Label, coins), tier.Id)
 		chest:Destroy()
 	end)
 

```
