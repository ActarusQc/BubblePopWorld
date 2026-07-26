### Task 3: BackpackService â€” mutex joueur + transactions

**Files:**
- Create: `src/Server/BackpackService.lua`
- Modify: `src/Server/init.server.lua` (Start aprÃ¨s DataService)
- Modify: `src/Server/DataService.lua` (SetMutationWaiter si Option A)

**Interfaces:**
- Produces:

```lua
-- Transaction token (pas snapshot complet)
type Tx = { Id: string, StorageAdded: number, SellValueAdded: number, Valid: boolean }

AddBubbles(player, storageAmount, sellValue) -> ok, err, tx?
RollbackAdd(player, tx) -> boolean
  -- sous le mÃªme mutex : soustrait StorageAdded / SellValueAdded si tx.Valid ;
  -- invalide le tx ; ne restaure JAMAIS un snapshot global
Sell(player) -> soldBubbles?, earnedCoins?, err?
IsLocked(player) -> boolean
WaitUnlocked(player, timeout) -> boolean
RoundSellValue(raw, baseSellValue) -> number?
```

- [ ] **Step 1: Mutex par joueur**

File/mutex synchrone Luau (une seule coroutine mutate Ã  la fois par player) :

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
--   CanAdd ; arrondi dÃ©jÃ  fait par appelant OU RoundSellValue ici
--   incrÃ©menter ; tx = { Id=HttpService:GenerateGUID(false), StorageAdded=..., SellValueAdded=..., Valid=true }
--   return true, nil, tx

-- RollbackAdd sous lock:
--   if not tx or not tx.Valid then return false end
--   d.CurrentBubbles -= tx.StorageAdded
--   d.PendingSellValue -= tx.SellValueAdded
--   clamp + invariant
--   tx.Valid = false
```

- [ ] **Step 3: Sell sous le mÃªme lock (pas IsSelling sÃ©parÃ© qui ignore AddBubbles)**

Ordre synchrone mÃ©moire (aucun Ã©tat intermÃ©diaire observable hors lock) :

1. VÃ©rifier sac (`CurrentBubbles > 0` et `PendingSellValue > 0`)
2. Copier `sold`, `earned`
3. `DataService.AddCoins(player, earned, "BubbleSale")` â€” si false, abort sans clear
4. Remettre `CurrentBubbles=0`, `PendingSellValue=0`
5. dirty + Push/attributs
6. libÃ©rer lock (finally)
7. Announce hors ou dans lock (aprÃ¨s mutation OK)

Pas de requÃªte DataStore dans Sell. Pas dâ€™attente 2 s.

- [ ] **Step 4: NotifyFull** avec cooldown

- [ ] **Step 5: Start** â€” wire `DataService.SetMutationWaiter(BackpackService.WaitUnlocked)` ; clear locks on PlayerRemoving

- [ ] **Step 6: Test** â€” Sell vide â†’ message ; concurrent mental model OK

- [ ] **Step 7: Commit**

```bash
git add src/Server/BackpackService.lua src/Server/DataService.lua src/Server/init.server.lua
git commit -m "feat: add BackpackService with per-player mutation lock"
```

---
