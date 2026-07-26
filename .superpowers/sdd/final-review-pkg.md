# Final branch review
BASE: 8f5ae31 (source baseline)
HEAD: 92035c5f5021e8ef7bc8023b6377f205912850cb
## Commits
92035c5 feat: show backpack gauge from player attributes
52615eb fix: clear cell claims and disable Baseplate under arena
fef778d feat: route bubble rewards through backpack with cell claim tokens
e01d49f fix: place SafetyBorders outside bubble extents
d96b139 feat: add ZoneService lobby teleports and safety borders
cba2fb0 fix: harden backpack rollback invariant and tx generation
6f31629 feat: add BackpackService with per-player mutation lock
7f24f7d fix: harden backpack reconcile and skip save while locked
b722e16 feat: persist backpack fields and sourced AddCoins
d535ceb fix: move GameRoom pads outside grid clearance
4211338 feat: add backpack and lobby world config
1519860 docs: add progression loop implementation plan

## Stat
 .superpowers/sdd/task-5-report.md                  |  57 +++
 .../plans/2026-07-25-progression-loop.md           | 491 +++++++++++++++++++++
 src/Client/HUD.lua                                 |  70 +++
 src/Client/PopEffects.lua                          |   3 +-
 src/Server/AmbianceService.lua                     |  28 +-
 src/Server/BackpackService.lua                     | 309 +++++++++++++
 src/Server/BubbleService.lua                       | 185 ++++++--
 src/Server/ChestService.lua                        |   3 +-
 src/Server/DataService.lua                         |  76 +++-
 src/Server/ZoneService.lua                         | 475 ++++++++++++++++++++
 src/Server/init.server.lua                         |   2 +
 src/Shared/BubbleTypes.lua                         |  10 +-
 src/Shared/GameConfig.lua                          |  75 ++++
 13 files changed, 1709 insertions(+), 75 deletions(-)

diff --git a/.superpowers/sdd/task-5-report.md b/.superpowers/sdd/task-5-report.md
new file mode 100644
index 0000000..6b70931
--- /dev/null
+++ b/.superpowers/sdd/task-5-report.md
@@ -0,0 +1,57 @@
+# Task 5 ΓÇö BubbleService : claim token, sac, pas de floor
+
+**Statut :** Termin├⌐
+
+**Commit :** `fef778d` ΓÇö feat: route bubble rewards through backpack with cell claim tokens
+
+## R├⌐sum├⌐
+
+### `src/Server/BubbleService.lua`
+
+- **Plancher retir├⌐** : `BuildWorld` ne cr├⌐e plus la `Part` ┬½ Floor ┬╗ continue sous la grille (spec ┬º8.6). La chute entre cases vides est d├⌐sormais voulue ; les barri├¿res lat├⌐rales et le `FallReset` restent g├⌐r├⌐s par `ZoneService`.
+- **Claim token** : `tryClaim(cell)` refuse la cellule si `cell.alive == false` ou si `cell.popClaim ~= nil`, sinon pose un jeton `{}` unique et le retourne. `releaseClaim(cell, token)` ne lib├¿re que si `cell.popClaim == token` (jamais de lib├⌐ration crois├⌐e). Deux joueurs sur la m├¬me bulle : un seul obtient le jeton, l'autre est ignor├⌐.
+- **`applyPop(cell, x, z)`** : mutation r├⌐elle isol├⌐e (alive, `CanCollide/CanQuery/CanTouch = false`, transparence, attribut `Alive`, file d'effets, `task.delay` de r├⌐g├⌐n├⌐ration). Retourne `false` si la case n'est plus ├⌐clatable (part d├⌐truite / d├⌐j├á ├⌐clat├⌐e).
+- **`popClaimedCell`** applique l'ordre de la spec ┬º6.1 : `alive` ΓåÆ type valide (`def` table + `Id` string) ΓåÆ `CanAdd(storage)` ΓåÆ `RoundSellValue(raw, baseSell)` ΓåÆ `AddBubbles` (tx) ΓåÆ pop r├⌐el ΓåÆ rollback si le pop ├⌐choue ΓåÆ statut.
+- **`PopCells`** : boucle par cellule avec `tryClaim` puis `xpcall`, et `releaseClaim` **syst├⌐matique** juste apr├¿s le `xpcall` (succ├¿s, sac plein, type invalide, erreur de calcul, `AddBubbles` refus├⌐, pop ├⌐chou├⌐, erreur Lua). Le `pcall(applyPop, ...)` interne garantit le `RollbackAdd(tx)` m├¬me si le pop l├¿ve une erreur ΓÇö c'est le seul intervalle o├╣ une transaction pourrait rester orpheline.
+- **Aucun `DataService.AddCoins`** dans `BubbleService` (v├⌐rifi├⌐ par grep). Les bulles ne remplissent que le sac ; les pi├¿ces arrivent uniquement ├á la vente (`BackpackService.Sell` ΓåÆ `AddCoins(..., "BubbleSale")`).
+- **Multiplicateurs** appliqu├⌐s ├á la valeur de vente *avant* `RoundSellValue` : `SellValue ├ù coinMult ├ù worldMult ├ù extra(outil) ├ù comboMult`.
+- **XP** : accumul├⌐e seulement pour les cellules r├⌐ellement ├⌐clat├⌐es, puis `floor(rawXP ├ù xpMult ├ù extra ├ù comboMult)` en fin de lot via `DataService.AddXP`.
+- **Combo** : `ComboService.Register` est appel├⌐ une seule fois par lot, paresseusement, et seulement quand une cellule est sur le point d'├¬tre ajout├⌐e au sac (apr├¿s `CanAdd`). Un lot enti├¿rement bloqu├⌐ par un sac plein n'incr├⌐mente plus le combo.
+- **Sac plein** : `NotifyFull` (une fois par lot, cooldown c├┤t├⌐ BackpackService), aucun effet, aucune XP, claim lib├⌐r├⌐, bulle intacte.
+- Fin de lot : `profile.Pops += count`, `__dirty`, `DataService.Push`, `GlobalCounterService.Add`, annonce l├⌐gendaire inchang├⌐e. Le profil est re-lu apr├¿s la boucle (les appels sac peuvent yield).
+- Robustesse : `positiveNumber` filtre NaN/infini/valeurs Γëñ 0 pour `StorageValue`, `SellValue`, `Coins` (legacy) et `XP` ; `storage` est plancher ├á 1.
+
+### `src/Server/ChestService.lua`
+
+- `DataService.AddCoins(player, coins, "Chest")` ΓÇö source explicite, coffres hors sac.
+
+### Compatibilit├⌐
+
+- `ToolService` appelle toujours `BubbleService.PopCells(player, cells, def.Multiplier)` : signature inchang├⌐e, retour = nombre de cellules ├⌐clat├⌐es.
+- Aucun client ne r├⌐f├⌐ren├ºait `BubbleWorld.Floor` (grep `Floor`/`Ground`) ; seul `ZoneService` cr├⌐e un `Floor` (lobby) et `AmbianceService` utilise `worldDef.Ground` pour l'atmosph├¿re.
+
+## Tests
+
+- Analyse statique : aucun diagnostic de lint sur les deux fichiers modifi├⌐s.
+- Revue de chemins (raisonnement, cf. contraintes Rojo : pas de `rojo build`, pas de Studio dans cette session) :
+  - deux joueurs sur la m├¬me cellule ΓåÆ un seul jeton, le second `tryClaim` retourne `nil` ;
+  - rollback d'un joueur A ΓåÆ `RollbackAdd` ne soustrait que le montant de *sa* transaction (tx token), donc n'efface pas un ajout concurrent ;
+  - sac plein ΓåÆ pas de mutation, pas d'XP, pas d'effet, claim lib├⌐r├⌐.
+
+## Concerns
+
+- **Test Studio non ex├⌐cut├⌐** (pas d'acc├¿s Studio dans cette session) : ├á valider manuellement ΓÇö chute entre bulles ΓåÆ `FallReset` vers `GameRoomSpawn`, deux joueurs m├¬me bulle, pop avec sac plein, jauge HUD (Task 7 pas encore faite, le HUD n'affiche pas encore le sac).
+- Si `AddBubbles` bloque sur le mutex jusqu'au timeout (`Config.World.MutationLockTimeout` = 5 s), la cellule reste r├⌐serv├⌐e pendant cette dur├⌐e : elle redevient poppable d├¿s la lib├⌐ration du claim, mais elle est inerte entre-temps. Comportement volontaire (pas de double cr├⌐dit), ├á surveiller si le timeout est augment├⌐.
+- `PopEffects` affiche encore `+Coins` c├┤t├⌐ client (pr├⌐vu Task 7).
+- `BubbleWorld` reste parent├⌐ directement ├á `workspace` (hors scope, d├⌐j├á not├⌐ en Task 4).
+
+## Rapport
+
+`e:\roblox\BubblePopWorld\.superpowers\sdd\task-5-report.md`
+
+## Follow-ups de revue
+
+- `regen` annule d├⌐sormais tout `popClaim` r├⌐siduel avant de r├⌐activer la cellule.
+- `BackpackService.ErrorCodes.BackpackFull` est le code stable retourn├⌐ ├á capacit├⌐ atteinte ; le message d'annonce fran├ºais reste interne ├á `NotifyFull`.
+- `ZoneService.EnsureWorld` d├⌐sactive uniquement la collision et rend invisible le `Baseplate` direct de `workspace` lorsqu'il est un `BasePart`.
+- Un ├⌐chec de `RollbackAdd` est signal├⌐ par `BubbleService`.
diff --git a/docs/superpowers/plans/2026-07-25-progression-loop.md b/docs/superpowers/plans/2026-07-25-progression-loop.md
new file mode 100644
index 0000000..1131cb9
--- /dev/null
+++ b/docs/superpowers/plans/2026-07-25-progression-loop.md
@@ -0,0 +1,491 @@
+# Progression Loop (Lobby / Sac / Vente) ΓÇö Implementation Plan
+
+> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
+
+**Goal:** Impl├⌐menter la boucle Lobby ΓåÆ salle ΓåÆ sac ΓåÆ vente ΓåÆ pi├¿ces, sans pi├¿ces imm├⌐diates au pop, avec verrous atomiques et monde additif.
+
+**Architecture:** `DataService` (profil + `AddCoins(source)` cr├⌐dits positifs) ΓåÆ `BackpackService` (mutex joueur + transactions) ΓåÆ `ZoneService` (lobby, t├⌐l├⌐ports, barri├¿res, FallReset) ΓåÆ `BubbleService` (claim token cellule, pop ΓåÆ sac + XP). HUD : jauge sac **uniquement via attributs Player**. Spec : `docs/superpowers/specs/2026-07-25-progression-loop-design.md`.
+
+**Tech Stack:** Roblox Luau, Rojo (`rojo serve` only), ModuleScripts Server/Client/Shared, DataStore `BPW_PlayerData_v1`.
+
+**Baseline git (avant impl├⌐mentation) :** commit `chore: establish BubblePopWorld source baseline` ΓÇö le diff feature commence apr├¿s ce commit + le commit de ce plan.
+
+## Global Constraints
+
+- `--!strict` en t├¬te de chaque fichier Luau modifi├⌐/cr├⌐├⌐
+- Pas de `rojo build` ; pas de publication ; ne jamais vider Workspace
+- Objets monde : cr├⌐er si absents ; si pr├⌐sents, r├⌐utiliser sans d├⌐placer/redimensionner (sauf `Config.World.RebuildGeneratedLayout == true`)
+- Attribut `GeneratedByCode = true` sur objets cr├⌐├⌐s par le code
+- Aucun plancher continu sous la grille de bulles
+- Bulles normales : jamais `AddCoins` au pop ; coffres : `AddCoins(..., "Chest")`
+- Client nΓÇÖenvoie jamais montants / capacit├⌐ / type de r├⌐compense
+- Services : `Start()` ; enregistr├⌐s dans `init.server.lua` / `init.client.lua`
+- Remotes uniquement via `Shared/Remotes.lua`
+- **BackpackService :** un verrou de mutation **par Player** pour AddBubbles / RollbackAdd / Sell / Clear ; rollback par **jeton de transaction** (pas snapshot aveugle)
+- **BubbleService :** claim cellule par **jeton unique** (`cell.popClaim = claimToken`) ; lib├⌐ration seulement si token match ; nettoyage garanti (xpcall)
+- **AddCoins :** cr├⌐dits positifs uniquement (`amount > 0`) ; sources `BubbleSale|Chest|DailyReward|Code|Admin` ; d├⌐penses shop restent `profile.Coins -=` / future `SpendCoins` ΓÇö **ne pas** casser ShopService
+- **HUD sac :** `CurrentBubbles`, `BackpackCapacity`, `PendingSellValue`, `PlayerArea` lus **uniquement** depuis attributs Player (pas StatsUpdate pour ces champs)
+- **Save :** pas de `task.wait` arbitraire dans PlayerRemoving ; attendre uniquement la fin du verrou mutation (timeout s├⌐curit├⌐) puis Save
+- **Layout :** positions lobby/entr├⌐e/spawn/exit valid├⌐es contre bounds grille (`Origin`, `SizeX/Z`, `Spacing`) ΓÇö pas de chevauchement bulles/barri├¿res
+
+---
+
+## File map
+
+| Fichier | R├┤le |
+|---|---|
+| `src/Shared/GameConfig.lua` | `Backpack`, `Lobby`, `World`, helpers bounds optionnels |
+| `src/Shared/BubbleTypes.lua` | `StorageValue`, `SellValue` (+ `Coins` legacy) |
+| `src/Server/DataService.lua` | template, reconcile, `AddCoins` positif + source, attributs, dirty |
+| `src/Server/BackpackService.lua` | **cr├⌐er** ΓÇö mutex joueur, tx token, Sell atomique |
+| `src/Server/ZoneService.lua` | **cr├⌐er** ΓÇö zones, t├⌐l├⌐ports, SafetyBorders, FallReset, Sell |
+| `src/Server/BubbleService.lua` | pas de Floor ; claim token ; pop ΓåÆ sac ; pas de pi├¿ces |
+| `src/Server/AmbianceService.lua` | `BuildWalls` no-op (barri├¿res = ZoneService) |
+| `src/Server/ChestService.lua` | `AddCoins(..., "Chest")` |
+| `src/Server/ShopService.lua` | **ne pas** passer les d├⌐penses par `AddCoins` |
+| `src/Server/init.server.lua` | ordre Start |
+| `src/Client/HUD.lua` | jauge sac via attributs |
+| `src/Client/PopEffects.lua` | `+storage` pas `+Coins` |
+
+Pas de `BackpackUI.lua` sauf n├⌐cessit├⌐ av├⌐r├⌐e.
+
+---
+
+### Task 1: Config & BubbleTypes
+
+**Files:**
+- Modify: `src/Shared/GameConfig.lua`
+- Modify: `src/Shared/BubbleTypes.lua`
+
+**Interfaces:**
+- Produces: `GameConfig.Backpack`, `GameConfig.Lobby`, `GameConfig.GameRoom`, `GameConfig.World`, `GameConfig.GetGridBounds()` (ou ├⌐quivalent) ; `BubbleTypes.*.StorageValue/SellValue`
+
+- [ ] **Step 1: Ajouter blocs config + bounds**
+
+```lua
+GameConfig.Backpack = {
+	DefaultCapacity = 25,
+	MaxCapacity = 1000,
+	NearlyFullRatio = 0.75,
+	FullNotifyCooldown = 3,
+}
+
+GameConfig.World = {
+	FallResetY = -25,
+	FallResetDestination = "GameRoom",
+	RebuildGeneratedLayout = false,
+	TeleportCooldown = 1.5,
+	SellMaxDistance = 16,
+	BorderHeight = 28,
+	BorderThickness = 3,
+	BorderTransparency = 0.45,
+	BorderColor = Color3.fromRGB(80, 200, 255),
+	MutationLockTimeout = 5,
+}
+
+-- Bounds grille (half-extent approx centres ┬▒ Spacing/2)
+function GameConfig.GetGridBounds()
+	local G = GameConfig.Grid
+	local halfX = (G.SizeX * G.Spacing) / 2
+	local halfZ = (G.SizeZ * G.Spacing) / 2
+	return {
+		MinX = G.Origin.X - halfX,
+		MaxX = G.Origin.X + halfX,
+		MinZ = G.Origin.Z - halfZ,
+		MaxZ = G.Origin.Z + halfZ,
+		MinY = G.Origin.Y - 2,
+		Origin = G.Origin,
+	}
+end
+
+-- Lobby HORS de la grille : RootOffset.Z doit ├¬tre < MinZ - marge (ex. 40 studs)
+-- Valeurs par d├⌐faut calcul├⌐es / document├⌐es pour Size 40, Spacing 6 ΓåÆ halfZ=120
+-- RootOffset Z Γëê -(halfZ + 60) = -180 (marge 60 hors bordure)
+GameConfig.Lobby = {
+	RootOffset = Vector3.new(0, 0, -180), -- valid├⌐ vs GetGridBounds + marge
+	FloorSize = Vector3.new(80, 2, 60),
+	FloorColor = Color3.fromRGB(60, 100, 160),
+	SpawnOffset = Vector3.new(0, 4, 0),
+	SellZoneOffset = Vector3.new(-20, 2, 10),
+	SellZoneSize = Vector3.new(12, 4, 12),
+	EntranceOffset = Vector3.new(0, 2, 28), -- vers +Z direction grille, toujours hors MinZ
+	EntranceSize = Vector3.new(14, 6, 8),
+	ClearanceFromGrid = 40,
+	SignText = "1. Entre dans la salle\n2. Fais ├⌐clater des bulles\n3. Remplis ton sac\n4. Reviens vendre tes bulles",
+}
+
+local halfZ = (GameConfig.Grid.SizeZ * GameConfig.Grid.Spacing) / 2
+GameConfig.GameRoom = {
+	-- Pad au sud de la grille (Z n├⌐gatif), hors bulles
+	SpawnOffset = Vector3.new(0, 8, -(halfZ + 24)),
+	ExitOffset = Vector3.new(0, 6, -(halfZ + 36)),
+	ExitSize = Vector3.new(14, 6, 8),
+	PadSize = Vector3.new(24, 2, 24),
+	PadColor = Color3.fromRGB(50, 140, 180),
+}
+```
+
+Ajouter un assert / warn au chargement config (ou dans ZoneService Task 4) :
+
+```lua
+local function assertOutsideGrid(worldPos: Vector3, label: string)
+	local b = GameConfig.GetGridBounds()
+	local margin = GameConfig.Lobby.ClearanceFromGrid
+	if worldPos.X > b.MinX - margin and worldPos.X < b.MaxX + margin
+		and worldPos.Z > b.MinZ - margin and worldPos.Z < b.MaxZ + margin then
+		warn("[BPW] layout overlap risk:", label, worldPos)
+	end
+end
+```
+
+Les pads/lobby ne doivent pas chevaucher les bulles, ni les SafetyBorders, ni passer sous la grille, ni bloquer la chute entre bulles.
+
+- [ ] **Step 2: ├ëtendre BubbleTypes**
+
+Chaque entr├⌐e : `StorageValue = 1`, `SellValue = <ancien Coins>`, garder `Coins = SellValue` legacy.
+
+- [ ] **Step 3: V├⌐rifier** ΓÇö require Shared OK ; Normal StorageValue/SellValue = 1.
+
+- [ ] **Step 4: Commit**
+
+```bash
+git add src/Shared/GameConfig.lua src/Shared/BubbleTypes.lua
+git commit -m "feat: add backpack and lobby world config"
+```
+
+---
+
+### Task 2: DataService ΓÇö profil, cr├⌐dits positifs, attributs
+
+**Files:**
+- Modify: `src/Server/DataService.lua`
+
+**Interfaces:**
+- Consumes: `GameConfig.Backpack`
+- Produces: `AddCoins(player, amount, source) -> boolean` (amount > 0 only) ; sync attributs ; reconcile backpack
+- Note: `ShopService` d├⌐pense via `profile.Coins -= cost` ΓÇö **ne pas** router ├ºa dans `AddCoins`
+
+- [ ] **Step 1: TEMPLATE**
+
+```lua
+CurrentBubbles = 0,
+BackpackCapacity = Config.Backpack.DefaultCapacity,
+PendingSellValue = 0,
+```
+
+- [ ] **Step 2: reconcileBackpack** (invariant `CurrentBubbles == 0 Γçö PendingSellValue == 0` ; reset + warn si sac > 0 et pending Γëñ 0)
+
+- [ ] **Step 3: AddCoins cr├⌐dits uniquement**
+
+```lua
+local CREDIT_SOURCES = {
+	BubbleSale = true, Chest = true, DailyReward = true, Code = true, Admin = true,
+}
+
+function DataService.AddCoins(player: Player, amount: number, source: string?): boolean
+	local d = profiles[player]
+	if not d then return false end
+	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return false end
+	amount = math.floor(amount)
+	if amount <= 0 then return false end -- pas de d├⌐penses ici
+	if source ~= nil and not CREDIT_SOURCES[source] then
+		warn("[DataService] source inconnue:", source)
+	end
+	d.Coins = math.max(0, d.Coins + amount)
+	d.__dirty = true
+	return true
+end
+```
+
+V├⌐rifi├⌐ baseline : seuls BubbleService/ChestService appellent `AddCoins` ; ShopService utilise `profile.Coins -=`. Aucun appel n├⌐gatif ├á migrer maintenant. **Ne pas** cr├⌐er `SpendCoins` dans cette task sauf si un appel n├⌐gatif appara├«t.
+
+- [ ] **Step 4: SyncAttributes dans Push**
+
+```lua
+player:SetAttribute("Coins", d.Coins)
+player:SetAttribute("CurrentBubbles", d.CurrentBubbles)
+player:SetAttribute("BackpackCapacity", d.BackpackCapacity)
+player:SetAttribute("PendingSellValue", d.PendingSellValue)
+```
+
+`StatsUpdate` peut encore envoyer XP/Level/Upgrades/Coins/Pops ; **ne pas** y mettre les champs sac comme source HUD (optionnel miroir OK mais HUD nΓÇÖ├⌐coute pas).
+
+- [ ] **Step 5: Save / Release et verrou**
+
+Exporter ou require `BackpackService.WaitUnlocked(player, timeout)` **apr├¿s** que Backpack existe ΓÇö attention ordre Start : DataService d├⌐marre avant Backpack. Donc :
+
+- Option A : `DataService.SetMutationWaiter(fn)` appel├⌐ depuis `BackpackService.Start`
+- Option B : Save lit `player:GetAttribute("BackpackLocked")` pos├⌐ par Backpack
+
+Utiliser Option A. **Pas** de `task.wait(2)` fixe. Attendre unlock avec timeout `Config.World.MutationLockTimeout` puis Save ├⌐tat coh├⌐rent.
+
+- [ ] **Step 6: Test** ΓÇö attributs 0/25 ; coins anciens OK ; ShopService achat toujours fonctionnel.
+
+- [ ] **Step 7: Commit**
+
+```bash
+git add src/Server/DataService.lua
+git commit -m "feat: persist backpack fields and sourced AddCoins"
+```
+
+---
+
+### Task 3: BackpackService ΓÇö mutex joueur + transactions
+
+**Files:**
+- Create: `src/Server/BackpackService.lua`
+- Modify: `src/Server/init.server.lua` (Start apr├¿s DataService)
+- Modify: `src/Server/DataService.lua` (SetMutationWaiter si Option A)
+
+**Interfaces:**
+- Produces:
+
+```lua
+-- Transaction token (pas snapshot complet)
+type Tx = { Id: string, StorageAdded: number, SellValueAdded: number, Valid: boolean }
+
+AddBubbles(player, storageAmount, sellValue) -> ok, err, tx?
+RollbackAdd(player, tx) -> boolean
+  -- sous le m├¬me mutex : soustrait StorageAdded / SellValueAdded si tx.Valid ;
+  -- invalide le tx ; ne restaure JAMAIS un snapshot global
+Sell(player) -> soldBubbles?, earnedCoins?, err?
+IsLocked(player) -> boolean
+WaitUnlocked(player, timeout) -> boolean
+RoundSellValue(raw, baseSellValue) -> number?
+```
+
+- [ ] **Step 1: Mutex par joueur**
+
+File/mutex synchrone Luau (une seule coroutine mutate ├á la fois par player) :
+
+```lua
+local locks: { [Player]: boolean } = {}
+local function withLock(player, fn)
+	-- spin/wait court si locked ; timeout MutationLockTimeout
+	-- locks[player]=true ; local ok, a,b,c = pcall(fn) ; locks[player]=false ; return ...
+end
+```
+
+Toutes les mutations `CurrentBubbles` / `PendingSellValue` passent par `withLock`.
+
+- [ ] **Step 2: AddBubbles + RollbackAdd**
+
+```lua
+-- AddBubbles sous lock:
+--   CanAdd ; arrondi d├⌐j├á fait par appelant OU RoundSellValue ici
+--   incr├⌐menter ; tx = { Id=HttpService:GenerateGUID(false), StorageAdded=..., SellValueAdded=..., Valid=true }
+--   return true, nil, tx
+
+-- RollbackAdd sous lock:
+--   if not tx or not tx.Valid then return false end
+--   d.CurrentBubbles -= tx.StorageAdded
+--   d.PendingSellValue -= tx.SellValueAdded
+--   clamp + invariant
+--   tx.Valid = false
+```
+
+- [ ] **Step 3: Sell sous le m├¬me lock (pas IsSelling s├⌐par├⌐ qui ignore AddBubbles)**
+
+Ordre synchrone m├⌐moire (aucun ├⌐tat interm├⌐diaire observable hors lock) :
+
+1. V├⌐rifier sac (`CurrentBubbles > 0` et `PendingSellValue > 0`)
+2. Copier `sold`, `earned`
+3. `DataService.AddCoins(player, earned, "BubbleSale")` ΓÇö si false, abort sans clear
+4. Remettre `CurrentBubbles=0`, `PendingSellValue=0`
+5. dirty + Push/attributs
+6. lib├⌐rer lock (finally)
+7. Announce hors ou dans lock (apr├¿s mutation OK)
+
+Pas de requ├¬te DataStore dans Sell. Pas dΓÇÖattente 2 s.
+
+- [ ] **Step 4: NotifyFull** avec cooldown
+
+- [ ] **Step 5: Start** ΓÇö wire `DataService.SetMutationWaiter(BackpackService.WaitUnlocked)` ; clear locks on PlayerRemoving
+
+- [ ] **Step 6: Test** ΓÇö Sell vide ΓåÆ message ; concurrent mental model OK
+
+- [ ] **Step 7: Commit**
+
+```bash
+git add src/Server/BackpackService.lua src/Server/DataService.lua src/Server/init.server.lua
+git commit -m "feat: add BackpackService with per-player mutation lock"
+```
+
+---
+
+### Task 4: ZoneService ΓÇö lobby, t├⌐l├⌐ports, barri├¿res, FallReset
+
+**Files:**
+- Create: `src/Server/ZoneService.lua`
+- Modify: `src/Server/AmbianceService.lua`
+- Modify: `src/Server/init.server.lua`
+
+**Interfaces:**
+- Produces: `TeleportToLobby`, `TeleportToGameRoom`, `EnsureWorld` ; attribut `PlayerArea`
+
+- [ ] **Step 1: ensureFolder / ensurePart / ensurePrompt** (idempotent ; no move si existe ; Rebuild flag)
+
+- [ ] **Step 2: EnsureWorld** ΓÇö valider positions via `GetGridBounds` + `ClearanceFromGrid` avant cr├⌐ation ; SafetyBorders autour grille avec ouverture c├┤t├⌐ spawn/exit
+
+- [ ] **Step 3ΓÇô6:** T├⌐l├⌐ports, spawn initial debounce, prompts Entrance/Exit/Sell (distance serveur + `BackpackService.Sell`), FallReset
+
+- [ ] **Step 7:** `AmbianceService.BuildWalls` ΓåÆ no-op
+
+- [ ] **Step 8: Test Studio** ΓÇö lobby hors grille ; chute ΓåÆ GameRoomSpawn ; markers non repositionn├⌐s
+
+- [ ] **Step 9: Commit**
+
+```bash
+git add src/Server/ZoneService.lua src/Server/AmbianceService.lua src/Server/init.server.lua
+git commit -m "feat: add ZoneService lobby teleports and safety borders"
+```
+
+---
+
+### Task 5: BubbleService ΓÇö claim token, sac, pas de floor
+
+**Files:**
+- Modify: `src/Server/BubbleService.lua`
+- Modify: `src/Server/ChestService.lua`
+
+**Interfaces:**
+- Consumes: `BackpackService.AddBubbles/RollbackAdd/CanAdd/NotifyFull/RoundSellValue` (sous mutex Backpack)
+- Produces: `PopCells` sans pi├¿ces ; claim token
+
+- [ ] **Step 1: Retirer Floor** continu sous la grille
+
+- [ ] **Step 2: Claim token**
+
+```lua
+local function tryClaim(cell): any?
+	if not cell.alive or cell.popClaim ~= nil then return nil end
+	local token = {}
+	cell.popClaim = token
+	return token
+end
+
+local function releaseClaim(cell, token)
+	if cell.popClaim == token then
+		cell.popClaim = nil
+	end
+end
+```
+
+- [ ] **Step 3: PopCells avec xpcall par cellule**
+
+Pour chaque cellule :
+
+```lua
+local token = tryClaim(cell)
+if not token then continue end
+local ok, err = xpcall(function()
+	-- validate type, CanAdd, RoundSellValue
+	-- AddBubbles -> tx
+	-- pop r├⌐el
+	-- si pop ├⌐choue: RollbackAdd(tx); error/return
+	-- XP accum
+end, warn)
+releaseClaim(cell, token) -- TOUJOURS
+-- sur ├⌐chec AddBubbles / full: NotifyFull, pas d'effet, pas d'XP
+```
+
+Chemins couverts : sac plein, type invalide, erreur calcul, AddBubbles refus├⌐, pop ├⌐chou├⌐, succ├¿s, erreur Lua.
+
+**Ne jamais** `DataService.AddCoins` ici. XP oui apr├¿s pop r├⌐el.
+
+- [ ] **Step 4: ChestService** ΓåÆ `AddCoins(player, coins, "Chest")`
+
+- [ ] **Step 5: Tests** ΓÇö deux joueurs m├¬me bulle ; rollback nΓÇÖefface pas autre pop ; chute entre bulles
+
+- [ ] **Step 6: Commit**
+
+```bash
+git add src/Server/BubbleService.lua src/Server/ChestService.lua
+git commit -m "feat: route bubble rewards through backpack with cell claim tokens"
+```
+
+---
+
+### Task 6: Ordre Start final + ToolService
+
+**Files:**
+- Modify: `src/Server/init.server.lua`
+- Verify: `src/Server/ToolService.lua`
+
+```lua
+local services = {
+	require(script.DataService),
+	require(script.BackpackService),
+	require(script.ZoneService),
+	require(script.GlobalCounterService),
+	require(script.ComboService),
+	require(script.AmbianceService),
+	require(script.BubbleService),
+	require(script.ToolService),
+	require(script.DropService),
+	require(script.ChestService),
+	require(script.ShopService),
+	require(script.LeaderboardService),
+}
+```
+
+Outils ΓåÆ uniquement `BubbleService.PopCells`. Commit : `chore: order server services for backpack dependency`.
+
+---
+
+### Task 7: HUD attributs + PopEffects
+
+**Files:**
+- Modify: `src/Client/HUD.lua`
+- Modify: `src/Client/PopEffects.lua`
+
+- [ ] **Step 1: Jauge sac** ΓÇö lire **uniquement** :
+
+```lua
+player:GetAttribute("CurrentBubbles")
+player:GetAttribute("BackpackCapacity")
+player:GetAttribute("PendingSellValue") -- lobby only
+player:GetAttribute("PlayerArea")
+```
+
+via `GetAttributeChangedSignal` / d├⌐marrage. **Ne pas** mettre ├á jour la jauge depuis `StatsUpdate`.
+
+- [ ] **Step 2:** `StatsUpdate` reste pour XP/Level/Upgrades/libell├⌐ pi├¿ces si d├⌐j├á branch├⌐ ; pi├¿ces HUD peuvent suivre attribut `Coins` aussi pour coh├⌐rence (pr├⌐f├⌐rer attribut `Coins` pour le label pi├¿ces si simple).
+
+- [ ] **Step 3: PopEffects** ΓÇö `+"..storage` ; plus de `+Coins` comme pi├¿ces
+
+- [ ] **Step 4ΓÇô5:** Test UI + commit `feat: show backpack gauge from player attributes`
+
+---
+
+### Task 8: Checklist validation manuelle (spec ┬º11)
+
+Ex├⌐cuter la checklist compl├¿te du spec + :
+
+- deux pops concurrent ΓåÆ rollback A nΓÇÖefface pas B
+- Sell pendant pop bloqu├⌐ par mutex
+- ShopService achat toujours OK
+- `git ls-files` sans `rojo.exe` / `*.rbxl*`
+
+---
+
+## Self-review (plan vs corrections)
+
+| Correction | Couverture |
+|---|---|
+| Baseline commit source | Pr├⌐requis git (fait avant impl├⌐mentation) |
+| Mutex + tx rollback | Task 3 |
+| Claim token + xpcall | Task 5 |
+| AddCoins > 0 ; Shop intact | Task 2 |
+| HUD attributs seuls (sac) | Task 7 |
+| Save attend unlock, pas wait 2s | Task 2 + 3 |
+| Bounds lobby vs grille | Task 1 + 4 |
+| Commit plan s├⌐par├⌐ | Ce fichier |
+
+---
+
+## Handoff
+
+Ex├⌐cution : **Subagent-Driven** ΓÇö un sous-agent par task, revue spec + qualit├⌐, commit apr├¿s validation, arr├¬t si r├⌐gression.
+
+Ne pas impl├⌐menter avant confirmation des hashes baseline + plan et exclusion `rojo.exe` / builds.
diff --git a/src/Client/HUD.lua b/src/Client/HUD.lua
index 94637ee..7c917c6 100644
--- a/src/Client/HUD.lua
+++ b/src/Client/HUD.lua
@@ -78,10 +78,41 @@ function HUD.Start()
 	xpFill.BackgroundColor3 = ACCENT
 	xpFill.BorderSizePixel = 0
 	xpFill.Parent = xpBack
 	corner(xpFill, 7)
 
+	-- Jauge du sac : son ├⌐tat provient exclusivement des attributs du joueur.
+	local backpackFrame = Instance.new("Frame")
+	backpackFrame.Size = UDim2.new(0, 260, 0, 74)
+	backpackFrame.Position = UDim2.new(0, 16, 0, 120)
+	backpackFrame.BackgroundColor3 = BG
+	backpackFrame.BackgroundTransparency = 0.15
+	backpackFrame.BorderSizePixel = 0
+	backpackFrame.Parent = gui
+	corner(backpackFrame, 14)
+
+	local backpackLabel = label(backpackFrame, "Sac 0 / 0", UDim2.new(1, -24, 0, 24), UDim2.new(0, 12, 0, 7))
+
+	local backpackBack = Instance.new("Frame")
+	backpackBack.Size = UDim2.new(1, -24, 0, 14)
+	backpackBack.Position = UDim2.new(0, 12, 0, 34)
+	backpackBack.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
+	backpackBack.BorderSizePixel = 0
+	backpackBack.Parent = backpackFrame
+	corner(backpackBack, 7)
+
+	local backpackFill = Instance.new("Frame")
+	backpackFill.Size = UDim2.new(0, 0, 1, 0)
+	backpackFill.BackgroundColor3 = ACCENT
+	backpackFill.BorderSizePixel = 0
+	backpackFill.Parent = backpackBack
+	corner(backpackFill, 7)
+
+	local backpackStatus = label(backpackFrame, "Place disponible", UDim2.new(1, -24, 0, 18), UDim2.new(0, 12, 0, 52), false)
+	backpackStatus.TextColor3 = ACCENT
+	backpackStatus.TextSize = 13
+
 	-- Compteur mondial
 	local globalFrame = Instance.new("Frame")
 	globalFrame.Size = UDim2.new(0, 320, 0, 52)
 	globalFrame.Position = UDim2.new(0.5, -160, 0, 12)
 	globalFrame.BackgroundColor3 = BG
@@ -145,18 +176,57 @@ function HUD.Start()
 			task.wait(0.45)
 			frame:Destroy()
 		end)
 	end
 
+	local function attributeNumber(name: string): number
+		local value = player:GetAttribute(name)
+		return if type(value) == "number" then value else 0
+	end
+
+	local function refreshBackpack()
+		local current = math.max(0, attributeNumber("CurrentBubbles"))
+		local capacity = math.max(0, attributeNumber("BackpackCapacity"))
+		local pendingSellValue = math.max(0, attributeNumber("PendingSellValue"))
+		local area = player:GetAttribute("PlayerArea")
+		local ratio = if capacity > 0 then math.clamp(current / capacity, 0, 1) else 0
+
+		backpackLabel.Text = ("Sac %s / %s"):format(comma(current), comma(capacity))
+		backpackFill.Size = UDim2.new(ratio, 0, 1, 0)
+
+		if ratio >= 1 then
+			backpackFill.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
+			backpackStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
+			backpackStatus.Text = "Sac plein !"
+		elseif ratio >= Config.Backpack.NearlyFullRatio then
+			backpackFill.BackgroundColor3 = Color3.fromRGB(255, 190, 70)
+			backpackStatus.TextColor3 = Color3.fromRGB(255, 210, 90)
+			backpackStatus.Text = "Sac presque plein"
+		else
+			backpackFill.BackgroundColor3 = ACCENT
+			backpackStatus.TextColor3 = ACCENT
+			backpackStatus.Text = "Place disponible"
+		end
+
+		if area == "Lobby" then
+			backpackStatus.Text = ("Valeur du sac : %s pi├¿ces"):format(comma(pendingSellValue))
+		end
+	end
+
 	-- Branchements
 	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function(stats)
 		coinsLabel.Text = comma(stats.Coins) .. " pi├¿ces"
 		levelLabel.Text = ("Niveau %d  ┬╖  %s bulles"):format(stats.Level, comma(stats.Pops))
 		local ratio = if stats.XPNeeded > 0 then math.clamp(stats.XP / stats.XPNeeded, 0, 1) else 0
 		TweenService:Create(xpFill, TweenInfo.new(0.25), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
 	end)
 
+	for _, attributeName in { "CurrentBubbles", "BackpackCapacity", "PendingSellValue", "PlayerArea" } do
+		player:GetAttributeChangedSignal(attributeName):Connect(refreshBackpack)
+	end
+	refreshBackpack()
+
 	Remotes.Event("GlobalCounter").OnClientEvent:Connect(function(total, target)
 		globalLabel.Text = ("%s / %s bulles"):format(comma(total), comma(target))
 		goalFill.Size = UDim2.new(math.clamp(total / target, 0, 1), 0, 1, 0)
 	end)
 
diff --git a/src/Client/PopEffects.lua b/src/Client/PopEffects.lua
index 08f0faf..3c7f186 100644
--- a/src/Client/PopEffects.lua
+++ b/src/Client/PopEffects.lua
@@ -117,11 +117,12 @@ function PopEffects.Start()
 			local special = rarity ~= "Normal"
 
 			burst(pos, def.Color, special)
 
 			if special then
-				floatingText(pos, "+" .. def.Coins, def.Color)
+				local storageValue = if type(def.StorageValue) == "number" then math.max(1, math.floor(def.StorageValue)) else 1
+				floatingText(pos, "+" .. storageValue, def.Color)
 			end
 
 			if played < 4 then
 				playPop(rarity)
 				played += 1
diff --git a/src/Server/AmbianceService.lua b/src/Server/AmbianceService.lua
index 21d0414..cab693a 100644
--- a/src/Server/AmbianceService.lua
+++ b/src/Server/AmbianceService.lua
@@ -54,34 +54,14 @@ function AmbianceService.Apply(worldDef)
 	cc.Contrast = 0.08
 	cc.Brightness = 0
 	cc.Parent = Lighting
 end
 
--- Murs invisibles : on ne tombe plus hors de la nappe de bulles.
-function AmbianceService.BuildWalls(parent: Instance)
-	local G = Config.Grid
-	local w = G.SizeX * G.Spacing
-	local d = G.SizeZ * G.Spacing
-	local height = 220
-
-	local sides = {
-		{ Vector3.new(w + 20, height, 4), Vector3.new(0, height / 2, -d / 2 - 8) },
-		{ Vector3.new(w + 20, height, 4), Vector3.new(0, height / 2, d / 2 + 8) },
-		{ Vector3.new(4, height, d + 20), Vector3.new(-w / 2 - 8, height / 2, 0) },
-		{ Vector3.new(4, height, d + 20), Vector3.new(w / 2 + 8, height / 2, 0) },
-	}
-
-	for i, side in ipairs(sides) do
-		local wall = Instance.new("Part")
-		wall.Name = "Wall" .. i
-		wall.Anchored = true
-		wall.CanCollide = true
-		wall.Transparency = 1
-		wall.Size = side[1]
-		wall.CFrame = CFrame.new(G.Origin + side[2])
-		wall.Parent = parent
-	end
+-- No-op : les barri├¿res de s├⌐curit├⌐ sont d├⌐sormais g├⌐r├⌐es de fa├ºon idempotente par
+-- `ZoneService` (dossier `SafetyBorders` sous `Workspace.BubblePopWorld.GameRoom`),
+-- avec ouverture c├┤t├⌐ spawn/sortie. Conserv├⌐ pour compatibilit├⌐ des appelants existants.
+function AmbianceService.BuildWalls(_parent: Instance)
 end
 
 function AmbianceService.Start()
 	AmbianceService.Apply(Config.Worlds[1])
 end
diff --git a/src/Server/BackpackService.lua b/src/Server/BackpackService.lua
new file mode 100644
index 0000000..262a2c4
--- /dev/null
+++ b/src/Server/BackpackService.lua
@@ -0,0 +1,309 @@
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
+BackpackService.ErrorCodes = table.freeze({
+	BackpackFull = "BackpackFull",
+})
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
+		return false, BackpackService.ErrorCodes.BackpackFull
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
diff --git a/src/Server/BubbleService.lua b/src/Server/BubbleService.lua
index 7727708..6436945 100644
--- a/src/Server/BubbleService.lua
+++ b/src/Server/BubbleService.lua
@@ -1,8 +1,9 @@
 --!strict
 -- C┼ôur du jeu : g├⌐n├⌐ration de la grille, ├⌐clatement, r├⌐g├⌐n├⌐ration,
--- r├⌐compenses, anti-exploit et diffusion group├⌐e des effets.
+-- r├⌐compenses (sac uniquement, jamais de pi├¿ces), anti-exploit
+-- et diffusion group├⌐e des effets.
 
 local Players = game:GetService("Players")
 local RunService = game:GetService("RunService")
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
 
@@ -10,10 +11,11 @@ local Shared = ReplicatedStorage:WaitForChild("Shared")
 local Config = require(Shared.GameConfig)
 local BubbleTypes = require(Shared.BubbleTypes)
 local Remotes = require(Shared.Remotes)
 
 local DataService = require(script.Parent.DataService)
+local BackpackService = require(script.Parent.BackpackService)
 local GlobalCounterService = require(script.Parent.GlobalCounterService)
 local ComboService = require(script.Parent.ComboService)
 local AmbianceService = require(script.Parent.AmbianceService)
 
 local G = Config.Grid
@@ -211,19 +213,12 @@ function BubbleService.BuildWorld(worldDef)
 
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
@@ -237,10 +232,12 @@ end
 
 --------------------------------------------------------------------
 -- ├ëclatement
 --------------------------------------------------------------------
 local function regen(cell)
+	-- Un claim ne doit jamais survivre au cycle de r├⌐g├⌐n├⌐ration.
+	cell.popClaim = nil
 	cell.def = BubbleTypes.Roll(rng)
 	cell.alive = true
 	cell.part.CanCollide = true
 	cell.part.CanQuery = true
 	cell.part.CanTouch = true
@@ -248,65 +245,171 @@ local function regen(cell)
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
+		return if err == BackpackService.ErrorCodes.BackpackFull then "full" else "skip"
+	end
+
+	-- Le pop r├⌐el est le seul point o├╣ une erreur Lua laisserait une transaction
+	-- orpheline : on le prot├¿ge explicitement pour garantir le rollback.
+	local popOk, popped = pcall(applyPop, cell, x, z)
+	if not popOk then
+		warn(("[BubbleService] pop ├⌐chou├⌐ en %d,%d : %s"):format(x, z, tostring(popped)))
+	end
+	if not popOk or popped ~= true then
+		if not BackpackService.RollbackAdd(player, tx) then
+			warn(("[BubbleService] rollback du sac ├⌐chou├⌐ en %d,%d"):format(x, z))
+		end
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
diff --git a/src/Server/ChestService.lua b/src/Server/ChestService.lua
index 3c322e6..2d81050 100644
--- a/src/Server/ChestService.lua
+++ b/src/Server/ChestService.lua
@@ -79,11 +79,12 @@ local function spawnChest()
 
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
 
diff --git a/src/Server/DataService.lua b/src/Server/DataService.lua
index a00008c..4f82755 100644
--- a/src/Server/DataService.lua
+++ b/src/Server/DataService.lua
@@ -11,10 +11,11 @@ local Remotes = require(Shared.Remotes)
 
 local store = DataStoreService:GetDataStore("BPW_PlayerData_v1")
 
 local DataService = {}
 local profiles: { [Player]: any } = {}
+local mutationWaiter: ((Player, number) -> boolean)? = nil
 
 local TEMPLATE = {
 	Coins = 0,
 	XP = 0,
 	Level = 1,
@@ -25,10 +26,13 @@ local TEMPLATE = {
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
@@ -48,10 +52,41 @@ local function reconcile(data, template)
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
@@ -66,16 +101,21 @@ end
 
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
@@ -95,15 +135,25 @@ function DataService.Save(player: Player)
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
@@ -115,10 +165,14 @@ end
 
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
@@ -132,14 +186,30 @@ function DataService.Push(player: Player)
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
diff --git a/src/Server/ZoneService.lua b/src/Server/ZoneService.lua
new file mode 100644
index 0000000..d40c4d3
--- /dev/null
+++ b/src/Server/ZoneService.lua
@@ -0,0 +1,475 @@
+--!strict
+-- Lobby, salle de bulles, t├⌐l├⌐ports serveur, barri├¿res de s├⌐curit├⌐ et chute (FallReset).
+-- Monde additif idempotent : les objets existants (d├⌐cor Studio ou d├⌐j├á cr├⌐├⌐s) ne sont
+-- jamais d├⌐plac├⌐s, redimensionn├⌐s ni d├⌐truits, sauf `Config.World.RebuildGeneratedLayout`
+-- qui ne repositionne que les objets marqu├⌐s `GeneratedByCode`.
+
+local Players = game:GetService("Players")
+local RunService = game:GetService("RunService")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.GameConfig)
+
+local DataService = require(script.Parent.DataService)
+local BackpackService = require(script.Parent.BackpackService)
+
+local ZoneService = {}
+
+--------------------------------------------------------------------
+-- Aides idempotentes
+--------------------------------------------------------------------
+local function ensureFolder(parent: Instance, name: string): Folder
+	local existing = parent:FindFirstChild(name)
+	if existing and existing:IsA("Folder") then
+		return existing
+	end
+	local folder = Instance.new("Folder")
+	folder.Name = name
+	folder.Parent = parent
+	return folder
+end
+
+-- Cr├⌐e `name` sous `container` via `build()` s'il est absent ; sinon r├⌐utilise l'objet
+-- existant sans le d├⌐placer/redimensionner (comportement par d├⌐faut). Si
+-- `Config.World.RebuildGeneratedLayout` est actif ET que l'objet existant porte
+-- `GeneratedByCode = true`, seule sa position/taille est r├⌐align├⌐e (jamais un marker
+-- plac├⌐ manuellement dans Studio, qui n'a pas cet attribut).
+local function ensurePart(container: Instance, name: string, build: () -> BasePart): BasePart
+	local existing = container:FindFirstChild(name)
+	if existing and existing:IsA("BasePart") then
+		if Config.World.RebuildGeneratedLayout and existing:GetAttribute("GeneratedByCode") == true then
+			local fresh = build()
+			existing.Size = fresh.Size
+			existing.CFrame = fresh.CFrame
+			fresh:Destroy()
+		end
+		return existing
+	end
+	local part = build()
+	part.Name = name
+	part:SetAttribute("GeneratedByCode", true)
+	part.Parent = container
+	return part
+end
+
+-- R├⌐pare additivement un ProximityPrompt : compl├¿te uniquement les propri├⌐t├⌐s manquantes
+-- (jamais d'├⌐crasement d'une personnalisation Studio existante).
+local function ensurePrompt(
+	part: BasePart,
+	name: string,
+	actionText: string,
+	objectText: string,
+	maxDistance: number
+): ProximityPrompt
+	local prompt = part:FindFirstChild(name)
+	if not (prompt and prompt:IsA("ProximityPrompt")) then
+		local created = Instance.new("ProximityPrompt")
+		created.Name = name
+		created.HoldDuration = 0.4
+		created.RequiresLineOfSight = false
+		created.Parent = part
+		prompt = created
+	end
+	local p = prompt :: ProximityPrompt
+	if p.ActionText == "" then
+		p.ActionText = actionText
+	end
+	if p.ObjectText == "" then
+		p.ObjectText = objectText
+	end
+	if p.MaxActivationDistance <= 0 then
+		p.MaxActivationDistance = maxDistance
+	end
+	return p
+end
+
+-- Connecte `fn` une seule fois sur la dur├⌐e de vie du prompt (prot├¿ge contre un double
+-- appel d'EnsureWorld, ex. Rebuild dev).
+local function connectOnce(prompt: ProximityPrompt, key: string, fn: (Player) -> ())
+	if prompt:GetAttribute(key) == true then
+		return
+	end
+	prompt:SetAttribute(key, true)
+	prompt.Triggered:Connect(fn)
+end
+
+local function validateOutsideGrid(pos: Vector3, margin: number, label: string)
+	local b = Config.GetGridBounds()
+	if pos.X > b.MinX - margin and pos.X < b.MaxX + margin
+		and pos.Z > b.MinZ - margin and pos.Z < b.MaxZ + margin then
+		warn("[ZoneService] position hors limites attendue mais chevauche la grille :", label, pos)
+	end
+end
+
+--------------------------------------------------------------------
+-- R├⌐f├⌐rences remplies par EnsureWorld
+--------------------------------------------------------------------
+local lobbySpawnPart: BasePart? = nil
+local gameRoomSpawnPart: BasePart? = nil
+
+local function disableStudioBaseplate()
+	local baseplate = workspace:FindFirstChild("Baseplate")
+	if baseplate and baseplate:IsA("BasePart") then
+		baseplate.CanCollide = false
+		baseplate.Transparency = 1
+	end
+end
+
+--------------------------------------------------------------------
+-- Barri├¿res de s├⌐curit├⌐ (c├┤t├⌐s grille, ouverture centrale c├┤t├⌐ spawn/sortie)
+--------------------------------------------------------------------
+local function ensureBorderWall(container: Instance, name: string, size: Vector3, cframe: CFrame): BasePart
+	return ensurePart(container, name, function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = true
+		p.CanQuery = false
+		p.CanTouch = false
+		p.Material = Enum.Material.ForceField
+		p.Color = Config.World.BorderColor
+		p.Transparency = Config.World.BorderTransparency
+		p.Size = size
+		p.CFrame = cframe
+		return p
+	end)
+end
+
+local function buildSafetyBorders(gameRoom: Folder)
+	local borders = ensureFolder(gameRoom, "SafetyBorders")
+	local G = Config.Grid
+	local W = Config.World
+	local t = W.BorderThickness
+	local h = W.BorderHeight
+	local yCenter = G.Origin.Y + h / 2
+	-- Les centres extr├¬mes sont ├á ((Size / 2) - 0.5) * Spacing. Les faces
+	-- int├⌐rieures des murs restent 2 studs apr├¿s le volume des bulles.
+	local safetyGap = 2
+	local bubbleExtentX = ((G.SizeX / 2) - 0.5) * G.Spacing + G.BubbleSize.X / 2 + safetyGap
+	local bubbleExtentZ = ((G.SizeZ / 2) - 0.5) * G.Spacing + G.BubbleSize.Z / 2 + safetyGap
+
+	ensureBorderWall(borders, "BorderNorth",
+		Vector3.new((bubbleExtentX + t) * 2, h, t),
+		CFrame.new(G.Origin.X, yCenter, G.Origin.Z + bubbleExtentZ + t / 2))
+
+	ensureBorderWall(borders, "BorderEast",
+		Vector3.new(t, h, (bubbleExtentZ + t) * 2),
+		CFrame.new(G.Origin.X + bubbleExtentX + t / 2, yCenter, G.Origin.Z))
+
+	ensureBorderWall(borders, "BorderWest",
+		Vector3.new(t, h, (bubbleExtentZ + t) * 2),
+		CFrame.new(G.Origin.X - bubbleExtentX - t / 2, yCenter, G.Origin.Z))
+
+	-- Sud : ouverture centrale (pas de mur au-dessus des plateformes spawn/sortie).
+	local gapWidth = math.max(Config.GameRoom.ExitSize.X, Config.GameRoom.PadSize.X) + 6
+	local segLen = math.max(0, bubbleExtentX + t - gapWidth / 2)
+	if segLen > 0 then
+		ensureBorderWall(borders, "BorderSouthLeft",
+			Vector3.new(segLen, h, t),
+			CFrame.new(G.Origin.X - (gapWidth / 2 + segLen / 2), yCenter, G.Origin.Z - bubbleExtentZ - t / 2))
+		ensureBorderWall(borders, "BorderSouthRight",
+			Vector3.new(segLen, h, t),
+			CFrame.new(G.Origin.X + (gapWidth / 2 + segLen / 2), yCenter, G.Origin.Z - bubbleExtentZ - t / 2))
+	end
+end
+
+--------------------------------------------------------------------
+-- Lobby
+--------------------------------------------------------------------
+local function buildLobby(lobby: Folder)
+	local L = Config.Lobby
+	local root = L.RootOffset
+
+	validateOutsideGrid(root, L.ClearanceFromGrid, "Lobby.RootOffset")
+	validateOutsideGrid(root + L.SellZoneOffset, L.ClearanceFromGrid, "Lobby.SellZoneOffset")
+	validateOutsideGrid(root + L.EntranceOffset, L.ClearanceFromGrid, "Lobby.EntranceOffset")
+
+	ensurePart(lobby, "Floor", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = true
+		p.Material = Enum.Material.SmoothPlastic
+		p.Color = L.FloorColor
+		p.Size = L.FloorSize
+		p.CFrame = CFrame.new(root - Vector3.new(0, L.FloorSize.Y / 2, 0))
+		return p
+	end)
+
+	local spawn = ensurePart(lobby, "LobbySpawn", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.CanQuery = false
+		p.Transparency = 1
+		p.Size = Vector3.new(4, 1, 4)
+		p.CFrame = CFrame.new(root + L.SpawnOffset)
+		return p
+	end)
+	lobbySpawnPart = spawn
+
+	local sellZone = ensurePart(lobby, "SellZone", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.Material = Enum.Material.Neon
+		p.Color = Color3.fromRGB(255, 210, 90)
+		p.Transparency = 0.6
+		p.Size = L.SellZoneSize
+		p.CFrame = CFrame.new(root + L.SellZoneOffset)
+		return p
+	end)
+
+	local entrance = ensurePart(lobby, "GameEntrance", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.Material = Enum.Material.Neon
+		p.Color = Color3.fromRGB(120, 220, 140)
+		p.Transparency = 0.6
+		p.Size = L.EntranceSize
+		p.CFrame = CFrame.new(root + L.EntranceOffset)
+		return p
+	end)
+
+	local sellPrompt = ensurePrompt(sellZone, "SellPrompt", "Vendre mes bulles", "Vente", Config.World.SellMaxDistance)
+	connectOnce(sellPrompt, "_wiredSell", function(player: Player)
+		local char = player.Character
+		local hrp = char and char:FindFirstChild("HumanoidRootPart")
+		if not (hrp and hrp:IsA("BasePart")) then
+			return
+		end
+		if (hrp.Position - sellZone.Position).Magnitude > Config.World.SellMaxDistance then
+			return
+		end
+		BackpackService.Sell(player)
+	end)
+
+	local entrancePrompt = ensurePrompt(entrance, "EntrancePrompt", "Entrer dans la salle de bulles", "Bulles", 10)
+	connectOnce(entrancePrompt, "_wiredEntrance", function(player: Player)
+		ZoneService.TeleportToGameRoom(player)
+	end)
+end
+
+--------------------------------------------------------------------
+-- Salle de bulles (spawn, sortie, plateformes, barri├¿res)
+--------------------------------------------------------------------
+local function buildGameRoom(gameRoom: Folder)
+	local G = Config.Grid
+	local R = Config.GameRoom
+
+	local spawnPos = G.Origin + R.SpawnOffset
+	local exitPos = G.Origin + R.ExitOffset
+	validateOutsideGrid(spawnPos, Config.Lobby.ClearanceFromGrid, "GameRoom.SpawnOffset")
+	validateOutsideGrid(exitPos, Config.Lobby.ClearanceFromGrid, "GameRoom.ExitOffset")
+
+	-- Plateformes (pads) uniquement sous spawn/sortie : aucun plancher continu sous la grille.
+	ensurePart(gameRoom, "SpawnPad", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = true
+		p.Material = Enum.Material.SmoothPlastic
+		p.Color = R.PadColor
+		p.Size = R.PadSize
+		p.CFrame = CFrame.new(spawnPos.X, G.Origin.Y - R.PadSize.Y / 2, spawnPos.Z)
+		return p
+	end)
+
+	ensurePart(gameRoom, "ExitPad", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = true
+		p.Material = Enum.Material.SmoothPlastic
+		p.Color = R.PadColor
+		p.Size = R.PadSize
+		p.CFrame = CFrame.new(exitPos.X, G.Origin.Y - R.PadSize.Y / 2, exitPos.Z)
+		return p
+	end)
+
+	local spawn = ensurePart(gameRoom, "GameRoomSpawn", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.CanQuery = false
+		p.Transparency = 1
+		p.Size = Vector3.new(4, 1, 4)
+		p.CFrame = CFrame.new(spawnPos)
+		return p
+	end)
+	gameRoomSpawnPart = spawn
+
+	local exitZone = ensurePart(gameRoom, "ExitZone", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.Material = Enum.Material.Neon
+		p.Color = Color3.fromRGB(220, 120, 120)
+		p.Transparency = 0.6
+		p.Size = R.ExitSize
+		p.CFrame = CFrame.new(exitPos)
+		return p
+	end)
+
+	local exitPrompt = ensurePrompt(exitZone, "ExitPrompt", "Retourner au lobby", "Sortie", 10)
+	connectOnce(exitPrompt, "_wiredExit", function(player: Player)
+		ZoneService.TeleportToLobby(player)
+	end)
+
+	buildSafetyBorders(gameRoom)
+end
+
+--------------------------------------------------------------------
+-- Monde additif
+--------------------------------------------------------------------
+-- Idempotent : ne recr├⌐e/d├⌐place jamais un objet existant (sauf Rebuild + GeneratedByCode).
+-- Ne d├⌐truit jamais la map existante.
+function ZoneService.EnsureWorld(): Folder
+	disableStudioBaseplate()
+
+	local root = ensureFolder(workspace, "BubblePopWorld")
+	local lobby = ensureFolder(root, "Lobby")
+	local gameRoom = ensureFolder(root, "GameRoom")
+
+	buildLobby(lobby)
+	buildGameRoom(gameRoom)
+
+	return root
+end
+
+--------------------------------------------------------------------
+-- T├⌐l├⌐ports serveur uniquement
+--------------------------------------------------------------------
+local teleportLast: { [Player]: number } = {}
+
+local function waitForHRP(player: Player, timeout: number?): (Model?, BasePart?)
+	local char = player.Character
+	if not char then
+		local ok, result = pcall(function()
+			return player.CharacterAdded:Wait()
+		end)
+		if not ok then
+			return nil, nil
+		end
+		char = result
+	end
+	if not char then
+		return nil, nil
+	end
+
+	local deadline = os.clock() + (timeout or 5)
+	local hrp = char:FindFirstChild("HumanoidRootPart")
+	while not (hrp and hrp:IsA("BasePart")) do
+		if os.clock() >= deadline or not char.Parent then
+			return nil, nil
+		end
+		task.wait()
+		hrp = char:FindFirstChild("HumanoidRootPart")
+	end
+	return char, hrp :: BasePart
+end
+
+local function doTeleport(player: Player, targetPos: Vector3, area: string, bypassCooldown: boolean?): boolean
+	if not bypassCooldown then
+		local last = teleportLast[player]
+		if last and os.clock() - last < Config.World.TeleportCooldown then
+			return false
+		end
+	end
+
+	local char, hrp = waitForHRP(player)
+	if not char or not hrp then
+		return false
+	end
+
+	char:PivotTo(CFrame.new(targetPos))
+	hrp.AssemblyLinearVelocity = Vector3.zero
+	hrp.AssemblyAngularVelocity = Vector3.zero
+
+	teleportLast[player] = os.clock()
+	-- L'attribut PlayerArea n'est pos├⌐ qu'apr├¿s un t├⌐l├⌐port r├⌐ussi.
+	player:SetAttribute("PlayerArea", area)
+	return true
+end
+
+-- Serveur uniquement (module sous ServerScriptService). `bypassCooldown` r├⌐serv├⌐ au
+-- spawn initial et au FallReset (s├⌐curit├⌐, ne doit pas ├¬tre bloqu├⌐ par l'anti-spam).
+function ZoneService.TeleportToLobby(player: Player, bypassCooldown: boolean?): boolean
+	if not lobbySpawnPart then
+		return false
+	end
+	return doTeleport(player, lobbySpawnPart.Position + Vector3.new(0, 3, 0), "Lobby", bypassCooldown)
+end
+
+function ZoneService.TeleportToGameRoom(player: Player, bypassCooldown: boolean?): boolean
+	if not gameRoomSpawnPart then
+		return false
+	end
+	return doTeleport(player, gameRoomSpawnPart.Position + Vector3.new(0, 3, 0), "GameRoom", bypassCooldown)
+end
+
+--------------------------------------------------------------------
+-- Spawn initial (debounce) + FallReset
+--------------------------------------------------------------------
+local spawningInProgress: { [Player]: boolean } = {}
+
+local function onCharacterAdded(player: Player)
+	if spawningInProgress[player] then
+		return
+	end
+	spawningInProgress[player] = true
+	task.spawn(function()
+		local deadline = os.clock() + 10
+		while not DataService.Get(player) and os.clock() < deadline do
+			task.wait()
+		end
+		ZoneService.TeleportToLobby(player, true)
+		spawningInProgress[player] = nil
+	end)
+end
+
+local fallResetGuard: { [Player]: boolean } = {}
+
+local function watchFallReset()
+	RunService.Heartbeat:Connect(function()
+		for _, player in ipairs(Players:GetPlayers()) do
+			if fallResetGuard[player] then
+				continue
+			end
+			local char = player.Character
+			local hrp = char and char:FindFirstChild("HumanoidRootPart")
+			if hrp and hrp:IsA("BasePart") and hrp.Position.Y < Config.World.FallResetY then
+				fallResetGuard[player] = true
+				task.spawn(function()
+					if Config.World.FallResetDestination == "Lobby" then
+						ZoneService.TeleportToLobby(player, true)
+					else
+						ZoneService.TeleportToGameRoom(player, true)
+					end
+					fallResetGuard[player] = nil
+				end)
+			end
+		end
+	end)
+end
+
+function ZoneService.Start()
+	ZoneService.EnsureWorld()
+
+	Players.PlayerAdded:Connect(function(player: Player)
+		player.CharacterAdded:Connect(function()
+			onCharacterAdded(player)
+		end)
+		if player.Character then
+			onCharacterAdded(player)
+		end
+	end)
+
+	Players.PlayerRemoving:Connect(function(player: Player)
+		teleportLast[player] = nil
+		spawningInProgress[player] = nil
+		fallResetGuard[player] = nil
+	end)
+
+	watchFallReset()
+end
+
+return ZoneService
diff --git a/src/Server/init.server.lua b/src/Server/init.server.lua
index 20f51d0..e46c5c2 100644
--- a/src/Server/init.server.lua
+++ b/src/Server/init.server.lua
@@ -4,10 +4,12 @@
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
 require(ReplicatedStorage:WaitForChild("Shared").Remotes) -- cr├⌐e les remotes en premier
 
 local services = {
 	require(script.DataService),
+	require(script.BackpackService),
+	require(script.ZoneService),
 	require(script.GlobalCounterService),
 	require(script.ComboService),
 	require(script.AmbianceService),
 	require(script.BubbleService),
 	require(script.ToolService),
diff --git a/src/Shared/BubbleTypes.lua b/src/Shared/BubbleTypes.lua
index 782f88d..ca581a6 100644
--- a/src/Shared/BubbleTypes.lua
+++ b/src/Shared/BubbleTypes.lua
@@ -3,15 +3,15 @@
 
 local BubbleTypes = {}
 
 BubbleTypes.List = {
 	-- Teintes bulle de savon (pas de blanc opaque)
-	{ Id = "Normal",    Label = "Bulle",             Weight = 1000, Coins = 1,    XP = 1,   Color = Color3.fromRGB(145, 225, 255) },
-	{ Id = "Rare",      Label = "Bulle rare",        Weight = 110,  Coins = 8,    XP = 5,   Color = Color3.fromRGB(90, 170, 255) },
-	{ Id = "Golden",    Label = "Bulle dor├⌐e",       Weight = 30,   Coins = 45,   XP = 22,  Color = Color3.fromRGB(255, 200, 70) },
-	{ Id = "Diamond",   Label = "Bulle diamant",     Weight = 7,    Coins = 220,  XP = 95,  Color = Color3.fromRGB(100, 240, 230) },
-	{ Id = "Legendary", Label = "Bulle l├⌐gendaire",  Weight = 1,    Coins = 1800, XP = 700, Color = Color3.fromRGB(255, 110, 210), Announce = true },
+	{ Id = "Normal",    Label = "Bulle",             Weight = 1000, StorageValue = 1, SellValue = 1,    Coins = 1,    XP = 1,   Color = Color3.fromRGB(145, 225, 255) },
+	{ Id = "Rare",      Label = "Bulle rare",        Weight = 110,  StorageValue = 1, SellValue = 8,    Coins = 8,    XP = 5,   Color = Color3.fromRGB(90, 170, 255) },
+	{ Id = "Golden",    Label = "Bulle dor├⌐e",       Weight = 30,   StorageValue = 1, SellValue = 45,   Coins = 45,   XP = 22,  Color = Color3.fromRGB(255, 200, 70) },
+	{ Id = "Diamond",   Label = "Bulle diamant",     Weight = 7,    StorageValue = 1, SellValue = 220,  Coins = 220,  XP = 95,  Color = Color3.fromRGB(100, 240, 230) },
+	{ Id = "Legendary", Label = "Bulle l├⌐gendaire",  Weight = 1,    StorageValue = 1, SellValue = 1800, Coins = 1800, XP = 700, Color = Color3.fromRGB(255, 110, 210), Announce = true },
 }
 
 BubbleTypes.ById = {}
 local total = 0
 for _, def in ipairs(BubbleTypes.List) do
diff --git a/src/Shared/GameConfig.lua b/src/Shared/GameConfig.lua
index f2380a8..2acd51c 100644
--- a/src/Shared/GameConfig.lua
+++ b/src/Shared/GameConfig.lua
@@ -10,10 +10,71 @@ GameConfig.Grid = {
 	Spacing = 6,                             -- distance entre 2 centres de bulle (studs)
 	BubbleSize = Vector3.new(5.4, 2.0, 5.4), -- hitbox de la bulle (d├┤me papier bulle)
 	Origin = Vector3.new(0, 6, 0),           -- centre de la grille
 }
 
+-- Bounds grille (half-extent approx centres ┬▒ Spacing/2)
+function GameConfig.GetGridBounds()
+	local G = GameConfig.Grid
+	local halfX = (G.SizeX * G.Spacing) / 2
+	local halfZ = (G.SizeZ * G.Spacing) / 2
+	return {
+		MinX = G.Origin.X - halfX,
+		MaxX = G.Origin.X + halfX,
+		MinZ = G.Origin.Z - halfZ,
+		MaxZ = G.Origin.Z + halfZ,
+		MinY = G.Origin.Y - 2,
+		Origin = G.Origin,
+	}
+end
+
+GameConfig.Backpack = {
+	DefaultCapacity = 25,
+	MaxCapacity = 1000,
+	NearlyFullRatio = 0.75,
+	FullNotifyCooldown = 3,
+}
+
+GameConfig.World = {
+	FallResetY = -25,
+	FallResetDestination = "GameRoom",
+	RebuildGeneratedLayout = false,
+	TeleportCooldown = 1.5,
+	SellMaxDistance = 16,
+	BorderHeight = 28,
+	BorderThickness = 3,
+	BorderTransparency = 0.45,
+	BorderColor = Color3.fromRGB(80, 200, 255),
+	MutationLockTimeout = 5,
+}
+
+-- Lobby HORS de la grille : RootOffset.Z doit ├¬tre < MinZ - marge (ex. 40 studs)
+-- Valeurs par d├⌐faut calcul├⌐es / document├⌐es pour Size 40, Spacing 6 ΓåÆ halfZ=120
+-- RootOffset Z Γëê -(halfZ + 60) = -180 (marge 60 hors bordure)
+GameConfig.Lobby = {
+	RootOffset = Vector3.new(0, 0, -180), -- valid├⌐ vs GetGridBounds + marge
+	FloorSize = Vector3.new(80, 2, 60),
+	FloorColor = Color3.fromRGB(60, 100, 160),
+	SpawnOffset = Vector3.new(0, 4, 0),
+	SellZoneOffset = Vector3.new(-20, 2, 10),
+	SellZoneSize = Vector3.new(12, 4, 12),
+	EntranceOffset = Vector3.new(0, 2, 28), -- vers +Z direction grille, toujours hors MinZ
+	EntranceSize = Vector3.new(14, 6, 8),
+	ClearanceFromGrid = 40,
+	SignText = "1. Entre dans la salle\n2. Fais ├⌐clater des bulles\n3. Remplis ton sac\n4. Reviens vendre tes bulles",
+}
+
+local halfZ = (GameConfig.Grid.SizeZ * GameConfig.Grid.Spacing) / 2
+GameConfig.GameRoom = {
+	-- Pad au sud de la grille (Z n├⌐gatif), hors bulles
+	SpawnOffset = Vector3.new(0, 8, -(halfZ + 44)),
+	ExitOffset = Vector3.new(0, 6, -(halfZ + 56)),
+	ExitSize = Vector3.new(14, 6, 8),
+	PadSize = Vector3.new(24, 2, 24),
+	PadColor = Color3.fromRGB(50, 140, 180),
+}
+
 GameConfig.Bubble = {
 	RegenTime = 30,          -- secondes avant r├⌐apparition
 	PressDepth = 0.7,        -- enfoncement visuel quand on marche dessus
 	MaxPopRange = 18,        -- port├⌐e max sans objet (anti-triche serveur)
 	WingPopRange = 48,       -- port├⌐e pendant le vol avec Ailes
@@ -136,6 +197,20 @@ GameConfig.Worlds = {
 	{ Id = "Future",     Label = "Futuriste",      LevelReq = 150, Mult = 16.0, Sky = Color3.fromRGB(40, 200, 220),  Ground = Color3.fromRGB(30, 60, 90) },
 	{ Id = "Candy",      Label = "Bonbons",        LevelReq = 200, Mult = 24.0, Sky = Color3.fromRGB(255, 190, 230), Ground = Color3.fromRGB(255, 150, 200) },
 	{ Id = "Underwater", Label = "Sous-marin",     LevelReq = 260, Mult = 35.0, Sky = Color3.fromRGB(30, 120, 180),  Ground = Color3.fromRGB(25, 90, 140) },
 }
 
+local function assertOutsideGrid(worldPos: Vector3, label: string)
+	local b = GameConfig.GetGridBounds()
+	local margin = GameConfig.Lobby.ClearanceFromGrid
+	if worldPos.X > b.MinX - margin and worldPos.X < b.MaxX + margin
+		and worldPos.Z > b.MinZ - margin and worldPos.Z < b.MaxZ + margin then
+		warn("[BPW] layout overlap risk:", label, worldPos)
+	end
+end
+
+assertOutsideGrid(GameConfig.Lobby.RootOffset, "Lobby.RootOffset")
+local gridOrigin = GameConfig.Grid.Origin
+assertOutsideGrid(gridOrigin + GameConfig.GameRoom.SpawnOffset, "GameRoom.SpawnOffset")
+assertOutsideGrid(gridOrigin + GameConfig.GameRoom.ExitOffset, "GameRoom.ExitOffset")
+
 return GameConfig
