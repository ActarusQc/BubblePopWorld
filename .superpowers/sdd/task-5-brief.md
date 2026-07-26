### Task 5: BubbleService â€” claim token, sac, pas de floor

**Files:**
- Modify: `src/Server/BubbleService.lua`
- Modify: `src/Server/ChestService.lua`

**Interfaces:**
- Consumes: `BackpackService.AddBubbles/RollbackAdd/CanAdd/NotifyFull/RoundSellValue` (sous mutex Backpack)
- Produces: `PopCells` sans piÃ¨ces ; claim token

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
	-- pop rÃ©el
	-- si pop Ã©choue: RollbackAdd(tx); error/return
	-- XP accum
end, warn)
releaseClaim(cell, token) -- TOUJOURS
-- sur Ã©chec AddBubbles / full: NotifyFull, pas d'effet, pas d'XP
```

Chemins couverts : sac plein, type invalide, erreur calcul, AddBubbles refusÃ©, pop Ã©chouÃ©, succÃ¨s, erreur Lua.

**Ne jamais** `DataService.AddCoins` ici. XP oui aprÃ¨s pop rÃ©el.

- [ ] **Step 4: ChestService** â†’ `AddCoins(player, coins, "Chest")`

- [ ] **Step 5: Tests** â€” deux joueurs mÃªme bulle ; rollback nâ€™efface pas autre pop ; chute entre bulles

- [ ] **Step 6: Commit**

```bash
git add src/Server/BubbleService.lua src/Server/ChestService.lua
git commit -m "feat: route bubble rewards through backpack with cell claim tokens"
```

---
