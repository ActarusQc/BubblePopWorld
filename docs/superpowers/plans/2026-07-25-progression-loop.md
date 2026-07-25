# Progression Loop (Lobby / Sac / Vente) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implémenter la boucle Lobby → salle → sac → vente → pièces, sans pièces immédiates au pop, avec verrous atomiques et monde additif.

**Architecture:** `DataService` (profil + `AddCoins(source)` crédits positifs) → `BackpackService` (mutex joueur + transactions) → `ZoneService` (lobby, téléports, barrières, FallReset) → `BubbleService` (claim token cellule, pop → sac + XP). HUD : jauge sac **uniquement via attributs Player**. Spec : `docs/superpowers/specs/2026-07-25-progression-loop-design.md`.

**Tech Stack:** Roblox Luau, Rojo (`rojo serve` only), ModuleScripts Server/Client/Shared, DataStore `BPW_PlayerData_v1`.

**Baseline git (avant implémentation) :** commit `chore: establish BubblePopWorld source baseline` — le diff feature commence après ce commit + le commit de ce plan.

## Global Constraints

- `--!strict` en tête de chaque fichier Luau modifié/créé
- Pas de `rojo build` ; pas de publication ; ne jamais vider Workspace
- Objets monde : créer si absents ; si présents, réutiliser sans déplacer/redimensionner (sauf `Config.World.RebuildGeneratedLayout == true`)
- Attribut `GeneratedByCode = true` sur objets créés par le code
- Aucun plancher continu sous la grille de bulles
- Bulles normales : jamais `AddCoins` au pop ; coffres : `AddCoins(..., "Chest")`
- Client n’envoie jamais montants / capacité / type de récompense
- Services : `Start()` ; enregistrés dans `init.server.lua` / `init.client.lua`
- Remotes uniquement via `Shared/Remotes.lua`
- **BackpackService :** un verrou de mutation **par Player** pour AddBubbles / RollbackAdd / Sell / Clear ; rollback par **jeton de transaction** (pas snapshot aveugle)
- **BubbleService :** claim cellule par **jeton unique** (`cell.popClaim = claimToken`) ; libération seulement si token match ; nettoyage garanti (xpcall)
- **AddCoins :** crédits positifs uniquement (`amount > 0`) ; sources `BubbleSale|Chest|DailyReward|Code|Admin` ; dépenses shop restent `profile.Coins -=` / future `SpendCoins` — **ne pas** casser ShopService
- **HUD sac :** `CurrentBubbles`, `BackpackCapacity`, `PendingSellValue`, `PlayerArea` lus **uniquement** depuis attributs Player (pas StatsUpdate pour ces champs)
- **Save :** pas de `task.wait` arbitraire dans PlayerRemoving ; attendre uniquement la fin du verrou mutation (timeout sécurité) puis Save
- **Layout :** positions lobby/entrée/spawn/exit validées contre bounds grille (`Origin`, `SizeX/Z`, `Spacing`) — pas de chevauchement bulles/barrières

---

## File map

| Fichier | Rôle |
|---|---|
| `src/Shared/GameConfig.lua` | `Backpack`, `Lobby`, `World`, helpers bounds optionnels |
| `src/Shared/BubbleTypes.lua` | `StorageValue`, `SellValue` (+ `Coins` legacy) |
| `src/Server/DataService.lua` | template, reconcile, `AddCoins` positif + source, attributs, dirty |
| `src/Server/BackpackService.lua` | **créer** — mutex joueur, tx token, Sell atomique |
| `src/Server/ZoneService.lua` | **créer** — zones, téléports, SafetyBorders, FallReset, Sell |
| `src/Server/BubbleService.lua` | pas de Floor ; claim token ; pop → sac ; pas de pièces |
| `src/Server/AmbianceService.lua` | `BuildWalls` no-op (barrières = ZoneService) |
| `src/Server/ChestService.lua` | `AddCoins(..., "Chest")` |
| `src/Server/ShopService.lua` | **ne pas** passer les dépenses par `AddCoins` |
| `src/Server/init.server.lua` | ordre Start |
| `src/Client/HUD.lua` | jauge sac via attributs |
| `src/Client/PopEffects.lua` | `+storage` pas `+Coins` |

Pas de `BackpackUI.lua` sauf nécessité avérée.

---

### Task 1: Config & BubbleTypes

**Files:**
- Modify: `src/Shared/GameConfig.lua`
- Modify: `src/Shared/BubbleTypes.lua`

**Interfaces:**
- Produces: `GameConfig.Backpack`, `GameConfig.Lobby`, `GameConfig.GameRoom`, `GameConfig.World`, `GameConfig.GetGridBounds()` (ou équivalent) ; `BubbleTypes.*.StorageValue/SellValue`

- [ ] **Step 1: Ajouter blocs config + bounds**

```lua
GameConfig.Backpack = {
	DefaultCapacity = 25,
	MaxCapacity = 1000,
	NearlyFullRatio = 0.75,
	FullNotifyCooldown = 3,
}

GameConfig.World = {
	FallResetY = -25,
	FallResetDestination = "GameRoom",
	RebuildGeneratedLayout = false,
	TeleportCooldown = 1.5,
	SellMaxDistance = 16,
	BorderHeight = 28,
	BorderThickness = 3,
	BorderTransparency = 0.45,
	BorderColor = Color3.fromRGB(80, 200, 255),
	MutationLockTimeout = 5,
}

-- Bounds grille (half-extent approx centres ± Spacing/2)
function GameConfig.GetGridBounds()
	local G = GameConfig.Grid
	local halfX = (G.SizeX * G.Spacing) / 2
	local halfZ = (G.SizeZ * G.Spacing) / 2
	return {
		MinX = G.Origin.X - halfX,
		MaxX = G.Origin.X + halfX,
		MinZ = G.Origin.Z - halfZ,
		MaxZ = G.Origin.Z + halfZ,
		MinY = G.Origin.Y - 2,
		Origin = G.Origin,
	}
end

-- Lobby HORS de la grille : RootOffset.Z doit être < MinZ - marge (ex. 40 studs)
-- Valeurs par défaut calculées / documentées pour Size 40, Spacing 6 → halfZ=120
-- RootOffset Z ≈ -(halfZ + 60) = -180 (marge 60 hors bordure)
GameConfig.Lobby = {
	RootOffset = Vector3.new(0, 0, -180), -- validé vs GetGridBounds + marge
	FloorSize = Vector3.new(80, 2, 60),
	FloorColor = Color3.fromRGB(60, 100, 160),
	SpawnOffset = Vector3.new(0, 4, 0),
	SellZoneOffset = Vector3.new(-20, 2, 10),
	SellZoneSize = Vector3.new(12, 4, 12),
	EntranceOffset = Vector3.new(0, 2, 28), -- vers +Z direction grille, toujours hors MinZ
	EntranceSize = Vector3.new(14, 6, 8),
	ClearanceFromGrid = 40,
	SignText = "1. Entre dans la salle\n2. Fais éclater des bulles\n3. Remplis ton sac\n4. Reviens vendre tes bulles",
}

local halfZ = (GameConfig.Grid.SizeZ * GameConfig.Grid.Spacing) / 2
GameConfig.GameRoom = {
	-- Pad au sud de la grille (Z négatif), hors bulles
	SpawnOffset = Vector3.new(0, 8, -(halfZ + 24)),
	ExitOffset = Vector3.new(0, 6, -(halfZ + 36)),
	ExitSize = Vector3.new(14, 6, 8),
	PadSize = Vector3.new(24, 2, 24),
	PadColor = Color3.fromRGB(50, 140, 180),
}
```

Ajouter un assert / warn au chargement config (ou dans ZoneService Task 4) :

```lua
local function assertOutsideGrid(worldPos: Vector3, label: string)
	local b = GameConfig.GetGridBounds()
	local margin = GameConfig.Lobby.ClearanceFromGrid
	if worldPos.X > b.MinX - margin and worldPos.X < b.MaxX + margin
		and worldPos.Z > b.MinZ - margin and worldPos.Z < b.MaxZ + margin then
		warn("[BPW] layout overlap risk:", label, worldPos)
	end
end
```

Les pads/lobby ne doivent pas chevaucher les bulles, ni les SafetyBorders, ni passer sous la grille, ni bloquer la chute entre bulles.

- [ ] **Step 2: Étendre BubbleTypes**

Chaque entrée : `StorageValue = 1`, `SellValue = <ancien Coins>`, garder `Coins = SellValue` legacy.

- [ ] **Step 3: Vérifier** — require Shared OK ; Normal StorageValue/SellValue = 1.

- [ ] **Step 4: Commit**

```bash
git add src/Shared/GameConfig.lua src/Shared/BubbleTypes.lua
git commit -m "feat: add backpack and lobby world config"
```

---

### Task 2: DataService — profil, crédits positifs, attributs

**Files:**
- Modify: `src/Server/DataService.lua`

**Interfaces:**
- Consumes: `GameConfig.Backpack`
- Produces: `AddCoins(player, amount, source) -> boolean` (amount > 0 only) ; sync attributs ; reconcile backpack
- Note: `ShopService` dépense via `profile.Coins -= cost` — **ne pas** router ça dans `AddCoins`

- [ ] **Step 1: TEMPLATE**

```lua
CurrentBubbles = 0,
BackpackCapacity = Config.Backpack.DefaultCapacity,
PendingSellValue = 0,
```

- [ ] **Step 2: reconcileBackpack** (invariant `CurrentBubbles == 0 ⇔ PendingSellValue == 0` ; reset + warn si sac > 0 et pending ≤ 0)

- [ ] **Step 3: AddCoins crédits uniquement**

```lua
local CREDIT_SOURCES = {
	BubbleSale = true, Chest = true, DailyReward = true, Code = true, Admin = true,
}

function DataService.AddCoins(player: Player, amount: number, source: string?): boolean
	local d = profiles[player]
	if not d then return false end
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return false end
	amount = math.floor(amount)
	if amount <= 0 then return false end -- pas de dépenses ici
	if source ~= nil and not CREDIT_SOURCES[source] then
		warn("[DataService] source inconnue:", source)
	end
	d.Coins = math.max(0, d.Coins + amount)
	d.__dirty = true
	return true
end
```

Vérifié baseline : seuls BubbleService/ChestService appellent `AddCoins` ; ShopService utilise `profile.Coins -=`. Aucun appel négatif à migrer maintenant. **Ne pas** créer `SpendCoins` dans cette task sauf si un appel négatif apparaît.

- [ ] **Step 4: SyncAttributes dans Push**

```lua
player:SetAttribute("Coins", d.Coins)
player:SetAttribute("CurrentBubbles", d.CurrentBubbles)
player:SetAttribute("BackpackCapacity", d.BackpackCapacity)
player:SetAttribute("PendingSellValue", d.PendingSellValue)
```

`StatsUpdate` peut encore envoyer XP/Level/Upgrades/Coins/Pops ; **ne pas** y mettre les champs sac comme source HUD (optionnel miroir OK mais HUD n’écoute pas).

- [ ] **Step 5: Save / Release et verrou**

Exporter ou require `BackpackService.WaitUnlocked(player, timeout)` **après** que Backpack existe — attention ordre Start : DataService démarre avant Backpack. Donc :

- Option A : `DataService.SetMutationWaiter(fn)` appelé depuis `BackpackService.Start`
- Option B : Save lit `player:GetAttribute("BackpackLocked")` posé par Backpack

Utiliser Option A. **Pas** de `task.wait(2)` fixe. Attendre unlock avec timeout `Config.World.MutationLockTimeout` puis Save état cohérent.

- [ ] **Step 6: Test** — attributs 0/25 ; coins anciens OK ; ShopService achat toujours fonctionnel.

- [ ] **Step 7: Commit**

```bash
git add src/Server/DataService.lua
git commit -m "feat: persist backpack fields and sourced AddCoins"
```

---

### Task 3: BackpackService — mutex joueur + transactions

**Files:**
- Create: `src/Server/BackpackService.lua`
- Modify: `src/Server/init.server.lua` (Start après DataService)
- Modify: `src/Server/DataService.lua` (SetMutationWaiter si Option A)

**Interfaces:**
- Produces:

```lua
-- Transaction token (pas snapshot complet)
type Tx = { Id: string, StorageAdded: number, SellValueAdded: number, Valid: boolean }

AddBubbles(player, storageAmount, sellValue) -> ok, err, tx?
RollbackAdd(player, tx) -> boolean
  -- sous le même mutex : soustrait StorageAdded / SellValueAdded si tx.Valid ;
  -- invalide le tx ; ne restaure JAMAIS un snapshot global
Sell(player) -> soldBubbles?, earnedCoins?, err?
IsLocked(player) -> boolean
WaitUnlocked(player, timeout) -> boolean
RoundSellValue(raw, baseSellValue) -> number?
```

- [ ] **Step 1: Mutex par joueur**

File/mutex synchrone Luau (une seule coroutine mutate à la fois par player) :

```lua
local locks: { [Player]: boolean } = {}
local function withLock(player, fn)
	-- spin/wait court si locked ; timeout MutationLockTimeout
	-- locks[player]=true ; local ok, a,b,c = pcall(fn) ; locks[player]=false ; return ...
end
```

Toutes les mutations `CurrentBubbles` / `PendingSellValue` passent par `withLock`.

- [ ] **Step 2: AddBubbles + RollbackAdd**

```lua
-- AddBubbles sous lock:
--   CanAdd ; arrondi déjà fait par appelant OU RoundSellValue ici
--   incrémenter ; tx = { Id=HttpService:GenerateGUID(false), StorageAdded=..., SellValueAdded=..., Valid=true }
--   return true, nil, tx

-- RollbackAdd sous lock:
--   if not tx or not tx.Valid then return false end
--   d.CurrentBubbles -= tx.StorageAdded
--   d.PendingSellValue -= tx.SellValueAdded
--   clamp + invariant
--   tx.Valid = false
```

- [ ] **Step 3: Sell sous le même lock (pas IsSelling séparé qui ignore AddBubbles)**

Ordre synchrone mémoire (aucun état intermédiaire observable hors lock) :

1. Vérifier sac (`CurrentBubbles > 0` et `PendingSellValue > 0`)
2. Copier `sold`, `earned`
3. `DataService.AddCoins(player, earned, "BubbleSale")` — si false, abort sans clear
4. Remettre `CurrentBubbles=0`, `PendingSellValue=0`
5. dirty + Push/attributs
6. libérer lock (finally)
7. Announce hors ou dans lock (après mutation OK)

Pas de requête DataStore dans Sell. Pas d’attente 2 s.

- [ ] **Step 4: NotifyFull** avec cooldown

- [ ] **Step 5: Start** — wire `DataService.SetMutationWaiter(BackpackService.WaitUnlocked)` ; clear locks on PlayerRemoving

- [ ] **Step 6: Test** — Sell vide → message ; concurrent mental model OK

- [ ] **Step 7: Commit**

```bash
git add src/Server/BackpackService.lua src/Server/DataService.lua src/Server/init.server.lua
git commit -m "feat: add BackpackService with per-player mutation lock"
```

---

### Task 4: ZoneService — lobby, téléports, barrières, FallReset

**Files:**
- Create: `src/Server/ZoneService.lua`
- Modify: `src/Server/AmbianceService.lua`
- Modify: `src/Server/init.server.lua`

**Interfaces:**
- Produces: `TeleportToLobby`, `TeleportToGameRoom`, `EnsureWorld` ; attribut `PlayerArea`

- [ ] **Step 1: ensureFolder / ensurePart / ensurePrompt** (idempotent ; no move si existe ; Rebuild flag)

- [ ] **Step 2: EnsureWorld** — valider positions via `GetGridBounds` + `ClearanceFromGrid` avant création ; SafetyBorders autour grille avec ouverture côté spawn/exit

- [ ] **Step 3–6:** Téléports, spawn initial debounce, prompts Entrance/Exit/Sell (distance serveur + `BackpackService.Sell`), FallReset

- [ ] **Step 7:** `AmbianceService.BuildWalls` → no-op

- [ ] **Step 8: Test Studio** — lobby hors grille ; chute → GameRoomSpawn ; markers non repositionnés

- [ ] **Step 9: Commit**

```bash
git add src/Server/ZoneService.lua src/Server/AmbianceService.lua src/Server/init.server.lua
git commit -m "feat: add ZoneService lobby teleports and safety borders"
```

---

### Task 5: BubbleService — claim token, sac, pas de floor

**Files:**
- Modify: `src/Server/BubbleService.lua`
- Modify: `src/Server/ChestService.lua`

**Interfaces:**
- Consumes: `BackpackService.AddBubbles/RollbackAdd/CanAdd/NotifyFull/RoundSellValue` (sous mutex Backpack)
- Produces: `PopCells` sans pièces ; claim token

- [ ] **Step 1: Retirer Floor** continu sous la grille

- [ ] **Step 2: Claim token**

```lua
local function tryClaim(cell): any?
	if not cell.alive or cell.popClaim ~= nil then return nil end
	local token = {}
	cell.popClaim = token
	return token
end

local function releaseClaim(cell, token)
	if cell.popClaim == token then
		cell.popClaim = nil
	end
end
```

- [ ] **Step 3: PopCells avec xpcall par cellule**

Pour chaque cellule :

```lua
local token = tryClaim(cell)
if not token then continue end
local ok, err = xpcall(function()
	-- validate type, CanAdd, RoundSellValue
	-- AddBubbles -> tx
	-- pop réel
	-- si pop échoue: RollbackAdd(tx); error/return
	-- XP accum
end, warn)
releaseClaim(cell, token) -- TOUJOURS
-- sur échec AddBubbles / full: NotifyFull, pas d'effet, pas d'XP
```

Chemins couverts : sac plein, type invalide, erreur calcul, AddBubbles refusé, pop échoué, succès, erreur Lua.

**Ne jamais** `DataService.AddCoins` ici. XP oui après pop réel.

- [ ] **Step 4: ChestService** → `AddCoins(player, coins, "Chest")`

- [ ] **Step 5: Tests** — deux joueurs même bulle ; rollback n’efface pas autre pop ; chute entre bulles

- [ ] **Step 6: Commit**

```bash
git add src/Server/BubbleService.lua src/Server/ChestService.lua
git commit -m "feat: route bubble rewards through backpack with cell claim tokens"
```

---

### Task 6: Ordre Start final + ToolService

**Files:**
- Modify: `src/Server/init.server.lua`
- Verify: `src/Server/ToolService.lua`

```lua
local services = {
	require(script.DataService),
	require(script.BackpackService),
	require(script.ZoneService),
	require(script.GlobalCounterService),
	require(script.ComboService),
	require(script.AmbianceService),
	require(script.BubbleService),
	require(script.ToolService),
	require(script.DropService),
	require(script.ChestService),
	require(script.ShopService),
	require(script.LeaderboardService),
}
```

Outils → uniquement `BubbleService.PopCells`. Commit : `chore: order server services for backpack dependency`.

---

### Task 7: HUD attributs + PopEffects

**Files:**
- Modify: `src/Client/HUD.lua`
- Modify: `src/Client/PopEffects.lua`

- [ ] **Step 1: Jauge sac** — lire **uniquement** :

```lua
player:GetAttribute("CurrentBubbles")
player:GetAttribute("BackpackCapacity")
player:GetAttribute("PendingSellValue") -- lobby only
player:GetAttribute("PlayerArea")
```

via `GetAttributeChangedSignal` / démarrage. **Ne pas** mettre à jour la jauge depuis `StatsUpdate`.

- [ ] **Step 2:** `StatsUpdate` reste pour XP/Level/Upgrades/libellé pièces si déjà branché ; pièces HUD peuvent suivre attribut `Coins` aussi pour cohérence (préférer attribut `Coins` pour le label pièces si simple).

- [ ] **Step 3: PopEffects** — `+"..storage` ; plus de `+Coins` comme pièces

- [ ] **Step 4–5:** Test UI + commit `feat: show backpack gauge from player attributes`

---

### Task 8: Checklist validation manuelle (spec §11)

Exécuter la checklist complète du spec + :

- deux pops concurrent → rollback A n’efface pas B
- Sell pendant pop bloqué par mutex
- ShopService achat toujours OK
- `git ls-files` sans `rojo.exe` / `*.rbxl*`

---

## Self-review (plan vs corrections)

| Correction | Couverture |
|---|---|
| Baseline commit source | Prérequis git (fait avant implémentation) |
| Mutex + tx rollback | Task 3 |
| Claim token + xpcall | Task 5 |
| AddCoins > 0 ; Shop intact | Task 2 |
| HUD attributs seuls (sac) | Task 7 |
| Save attend unlock, pas wait 2s | Task 2 + 3 |
| Bounds lobby vs grille | Task 1 + 4 |
| Commit plan séparé | Ce fichier |

---

## Handoff

Exécution : **Subagent-Driven** — un sous-agent par task, revue spec + qualité, commit après validation, arrêt si régression.

Ne pas implémenter avant confirmation des hashes baseline + plan et exclusion `rojo.exe` / builds.
