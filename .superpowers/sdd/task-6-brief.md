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

Outils â†’ uniquement `BubbleService.PopCells`. Commit : `chore: order server services for backpack dependency`.

---
