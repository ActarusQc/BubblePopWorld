# Task 6 Report — Ordre Start + ToolService

**Status:** DONE  
**Commit:** no commit needed (already ordered)

## Summary

- `src/Server/init.server.lua` : ordre de démarrage déjà conforme au brief.
- `src/Server/ToolService.lua` : utilise uniquement `BubbleService.PopCells` (ligne 265) ; aucun appel à `AddCoins`.

## Ordre vérifié

```
DataService → BackpackService → ZoneService → GlobalCounterService → ComboService → AmbianceService → BubbleService → ToolService → DropService → ChestService → ShopService → LeaderboardService
```

## ToolService — BubbleService

| Méthode     | Utilisée |
|-------------|----------|
| `PopCells`  | Oui (activation outils) |
| `WorldToCell` | Oui (résolution cellule) |
| `IsAlive`   | Oui (validation Single) |
| `AddCoins`  | Non |

Aucune modification requise.
