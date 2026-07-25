# Task 5 — BubbleService : claim token, sac, pas de floor

**Statut :** Terminé

**Commit :** `fef778d` — feat: route bubble rewards through backpack with cell claim tokens

## Résumé

### `src/Server/BubbleService.lua`

- **Plancher retiré** : `BuildWorld` ne crée plus la `Part` « Floor » continue sous la grille (spec §8.6). La chute entre cases vides est désormais voulue ; les barrières latérales et le `FallReset` restent gérés par `ZoneService`.
- **Claim token** : `tryClaim(cell)` refuse la cellule si `cell.alive == false` ou si `cell.popClaim ~= nil`, sinon pose un jeton `{}` unique et le retourne. `releaseClaim(cell, token)` ne libère que si `cell.popClaim == token` (jamais de libération croisée). Deux joueurs sur la même bulle : un seul obtient le jeton, l'autre est ignoré.
- **`applyPop(cell, x, z)`** : mutation réelle isolée (alive, `CanCollide/CanQuery/CanTouch = false`, transparence, attribut `Alive`, file d'effets, `task.delay` de régénération). Retourne `false` si la case n'est plus éclatable (part détruite / déjà éclatée).
- **`popClaimedCell`** applique l'ordre de la spec §6.1 : `alive` → type valide (`def` table + `Id` string) → `CanAdd(storage)` → `RoundSellValue(raw, baseSell)` → `AddBubbles` (tx) → pop réel → rollback si le pop échoue → statut.
- **`PopCells`** : boucle par cellule avec `tryClaim` puis `xpcall`, et `releaseClaim` **systématique** juste après le `xpcall` (succès, sac plein, type invalide, erreur de calcul, `AddBubbles` refusé, pop échoué, erreur Lua). Le `pcall(applyPop, ...)` interne garantit le `RollbackAdd(tx)` même si le pop lève une erreur — c'est le seul intervalle où une transaction pourrait rester orpheline.
- **Aucun `DataService.AddCoins`** dans `BubbleService` (vérifié par grep). Les bulles ne remplissent que le sac ; les pièces arrivent uniquement à la vente (`BackpackService.Sell` → `AddCoins(..., "BubbleSale")`).
- **Multiplicateurs** appliqués à la valeur de vente *avant* `RoundSellValue` : `SellValue × coinMult × worldMult × extra(outil) × comboMult`.
- **XP** : accumulée seulement pour les cellules réellement éclatées, puis `floor(rawXP × xpMult × extra × comboMult)` en fin de lot via `DataService.AddXP`.
- **Combo** : `ComboService.Register` est appelé une seule fois par lot, paresseusement, et seulement quand une cellule est sur le point d'être ajoutée au sac (après `CanAdd`). Un lot entièrement bloqué par un sac plein n'incrémente plus le combo.
- **Sac plein** : `NotifyFull` (une fois par lot, cooldown côté BackpackService), aucun effet, aucune XP, claim libéré, bulle intacte.
- Fin de lot : `profile.Pops += count`, `__dirty`, `DataService.Push`, `GlobalCounterService.Add`, annonce légendaire inchangée. Le profil est re-lu après la boucle (les appels sac peuvent yield).
- Robustesse : `positiveNumber` filtre NaN/infini/valeurs ≤ 0 pour `StorageValue`, `SellValue`, `Coins` (legacy) et `XP` ; `storage` est plancher à 1.

### `src/Server/ChestService.lua`

- `DataService.AddCoins(player, coins, "Chest")` — source explicite, coffres hors sac.

### Compatibilité

- `ToolService` appelle toujours `BubbleService.PopCells(player, cells, def.Multiplier)` : signature inchangée, retour = nombre de cellules éclatées.
- Aucun client ne référençait `BubbleWorld.Floor` (grep `Floor`/`Ground`) ; seul `ZoneService` crée un `Floor` (lobby) et `AmbianceService` utilise `worldDef.Ground` pour l'atmosphère.

## Tests

- Analyse statique : aucun diagnostic de lint sur les deux fichiers modifiés.
- Revue de chemins (raisonnement, cf. contraintes Rojo : pas de `rojo build`, pas de Studio dans cette session) :
  - deux joueurs sur la même cellule → un seul jeton, le second `tryClaim` retourne `nil` ;
  - rollback d'un joueur A → `RollbackAdd` ne soustrait que le montant de *sa* transaction (tx token), donc n'efface pas un ajout concurrent ;
  - sac plein → pas de mutation, pas d'XP, pas d'effet, claim libéré.

## Concerns

- **Test Studio non exécuté** (pas d'accès Studio dans cette session) : à valider manuellement — chute entre bulles → `FallReset` vers `GameRoomSpawn`, deux joueurs même bulle, pop avec sac plein, jauge HUD (Task 7 pas encore faite, le HUD n'affiche pas encore le sac).
- Si `AddBubbles` bloque sur le mutex jusqu'au timeout (`Config.World.MutationLockTimeout` = 5 s), la cellule reste réservée pendant cette durée : elle redevient poppable dès la libération du claim, mais elle est inerte entre-temps. Comportement volontaire (pas de double crédit), à surveiller si le timeout est augmenté.
- `PopEffects` affiche encore `+Coins` côté client (prévu Task 7).
- `BubbleWorld` reste parenté directement à `workspace` (hors scope, déjà noté en Task 4).

## Rapport

`e:\roblox\BubblePopWorld\.superpowers\sdd\task-5-report.md`

## Follow-ups de revue

- `regen` annule désormais tout `popClaim` résiduel avant de réactiver la cellule.
- `BackpackService.ErrorCodes.BackpackFull` est le code stable retourné à capacité atteinte ; le message d'annonce français reste interne à `NotifyFull`.
- `ZoneService.EnsureWorld` désactive uniquement la collision et rend invisible le `Baseplate` direct de `workspace` lorsqu'il est un `BasePart`.
- Un échec de `RollbackAdd` est signalé par `BubbleService`.
