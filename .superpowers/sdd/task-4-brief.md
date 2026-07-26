### Task 4: ZoneService â€” lobby, tÃ©lÃ©ports, barriÃ¨res, FallReset

**Files:**
- Create: `src/Server/ZoneService.lua`
- Modify: `src/Server/AmbianceService.lua`
- Modify: `src/Server/init.server.lua`

**Interfaces:**
- Produces: `TeleportToLobby`, `TeleportToGameRoom`, `EnsureWorld` ; attribut `PlayerArea`

- [ ] **Step 1: ensureFolder / ensurePart / ensurePrompt** (idempotent ; no move si existe ; Rebuild flag)

- [ ] **Step 2: EnsureWorld** â€” valider positions via `GetGridBounds` + `ClearanceFromGrid` avant crÃ©ation ; SafetyBorders autour grille avec ouverture cÃ´tÃ© spawn/exit

- [ ] **Step 3â€“6:** TÃ©lÃ©ports, spawn initial debounce, prompts Entrance/Exit/Sell (distance serveur + `BackpackService.Sell`), FallReset

- [ ] **Step 7:** `AmbianceService.BuildWalls` â†’ no-op

- [ ] **Step 8: Test Studio** â€” lobby hors grille ; chute â†’ GameRoomSpawn ; markers non repositionnÃ©s

- [ ] **Step 9: Commit**

```bash
git add src/Server/ZoneService.lua src/Server/AmbianceService.lua src/Server/init.server.lua
git commit -m "feat: add ZoneService lobby teleports and safety borders"
```

---
