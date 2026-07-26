### Task 2: DataService â€” profil, crÃ©dits positifs, attributs

**Files:**
- Modify: `src/Server/DataService.lua`

**Interfaces:**
- Consumes: `GameConfig.Backpack`
- Produces: `AddCoins(player, amount, source) -> boolean` (amount > 0 only) ; sync attributs ; reconcile backpack
- Note: `ShopService` dÃ©pense via `profile.Coins -= cost` â€” **ne pas** router Ã§a dans `AddCoins`

- [ ] **Step 1: TEMPLATE**

```lua
CurrentBubbles = 0,
BackpackCapacity = Config.Backpack.DefaultCapacity,
PendingSellValue = 0,
```

- [ ] **Step 2: reconcileBackpack** (invariant `CurrentBubbles == 0 â‡” PendingSellValue == 0` ; reset + warn si sac > 0 et pending â‰¤ 0)

- [ ] **Step 3: AddCoins crÃ©dits uniquement**

```lua
local CREDIT_SOURCES = {
	BubbleSale = true, Chest = true, DailyReward = true, Code = true, Admin = true,
}

function DataService.AddCoins(player: Player, amount: number, source: string?): boolean
	local d = profiles[player]
	if not d then return false end
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge then return false end
	amount = math.floor(amount)
	if amount <= 0 then return false end -- pas de dÃ©penses ici
	if source ~= nil and not CREDIT_SOURCES[source] then
		warn("[DataService] source inconnue:", source)
	end
	d.Coins = math.max(0, d.Coins + amount)
	d.__dirty = true
	return true
end
```

VÃ©rifiÃ© baseline : seuls BubbleService/ChestService appellent `AddCoins` ; ShopService utilise `profile.Coins -=`. Aucun appel nÃ©gatif Ã  migrer maintenant. **Ne pas** crÃ©er `SpendCoins` dans cette task sauf si un appel nÃ©gatif apparaÃ®t.

- [ ] **Step 4: SyncAttributes dans Push**

```lua
player:SetAttribute("Coins", d.Coins)
player:SetAttribute("CurrentBubbles", d.CurrentBubbles)
player:SetAttribute("BackpackCapacity", d.BackpackCapacity)
player:SetAttribute("PendingSellValue", d.PendingSellValue)
```

`StatsUpdate` peut encore envoyer XP/Level/Upgrades/Coins/Pops ; **ne pas** y mettre les champs sac comme source HUD (optionnel miroir OK mais HUD nâ€™Ã©coute pas).

- [ ] **Step 5: Save / Release et verrou**

Exporter ou require `BackpackService.WaitUnlocked(player, timeout)` **aprÃ¨s** que Backpack existe â€” attention ordre Start : DataService dÃ©marre avant Backpack. Donc :

- Option A : `DataService.SetMutationWaiter(fn)` appelÃ© depuis `BackpackService.Start`
- Option B : Save lit `player:GetAttribute("BackpackLocked")` posÃ© par Backpack

Utiliser Option A. **Pas** de `task.wait(2)` fixe. Attendre unlock avec timeout `Config.World.MutationLockTimeout` puis Save Ã©tat cohÃ©rent.

- [ ] **Step 6: Test** â€” attributs 0/25 ; coins anciens OK ; ShopService achat toujours fonctionnel.

- [ ] **Step 7: Commit**

```bash
git add src/Server/DataService.lua
git commit -m "feat: persist backpack fields and sourced AddCoins"
```

---
