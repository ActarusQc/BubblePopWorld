# Task 7 Report — HUD attributs + PopEffects

**Status:** DONE  
**Commit:** `92035c5` — `feat: show backpack gauge from player attributes`

## Summary

- `src/Client/HUD.lua` : ajoute la jauge du sac dans le `BPW_HUD` existant. Elle lit exclusivement les attributs `CurrentBubbles`, `BackpackCapacity`, `PendingSellValue` et `PlayerArea`, au démarrage et à chaque `GetAttributeChangedSignal`.
- Les états de la jauge sont normal (`< 75 %`), presque plein (`>= GameConfig.Backpack.NearlyFullRatio` et `< 100 %`) et plein (`>= 100 %`). Dans le lobby, le statut affiche `Valeur du sac : N pièces`.
- `StatsUpdate` conserve uniquement la mise à jour pièces, niveau et XP ; il ne touche pas à la jauge du sac.
- `src/Client/PopEffects.lua` affiche la capacité gagnée (`+StorageValue`, repli `+1`) pour les bulles spéciales, jamais `+Coins`.

## Validation

- Diagnostics IDE : aucune erreur dans les deux fichiers modifiés.
- `git diff --check` : succès.
- Build Rojo : non exécuté, la commande `rojo` n'est pas installée ou disponible dans l'environnement.

