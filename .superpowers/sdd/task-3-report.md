# Rapport — Task 3 : BackpackService

## Statut

Implémentation terminée et commitée.

## Commit

- `6f31629 feat: add BackpackService with per-player mutation lock`

## Changements

- Nouveau `src/Server/BackpackService.lua` : verrou de mutation par joueur (`locks[Player]`, `acquire`/`release`/`runLocked`) englobant **toutes** les mutations de `CurrentBubbles`/`PendingSellValue` (`AddBubbles`, `RollbackAdd`, `Sell`) — aucun drapeau `IsSelling` séparé, donc Sell ne peut pas courir avec un pop concurrent.
- `AddBubbles` : pas de remplissage partiel, retourne un jeton `Tx {Id, StorageAdded, SellValueAdded, Valid}` (pas de snapshot global) ; `RollbackAdd` soustrait uniquement les montants du jeton, invalide `Valid`, réapplique l'invariant sac vide ⇔ valeur nulle.
- `Sell` : sous le même verrou — vérifie, copie `sold`/`earned`, `DataService.AddCoins(..., "BubbleSale")`, vide le sac en mémoire, libère le verrou (via `runLocked`), puis `Push` + `Announce` (succès ou sac vide) hors verrou ; aucun accès DataStore dans `Sell`.
- `RoundSellValue(raw, baseSellValue)` : `floor(raw+0.5)`, plancher 1 si `baseSellValue>0`, rejette NaN/infini/négatif (`nil`).
- `NotifyFull` avec cooldown (`Config.Backpack.FullNotifyCooldown`).
- `WaitUnlocked`/`IsLocked` exposés ; `Start()` appelle `DataService.SetMutationWaiter(BackpackService.WaitUnlocked)` et nettoie les verrous/cooldowns sur `PlayerRemoving`.
- `src/Server/init.server.lua` : `BackpackService` ajouté juste après `DataService` dans l'ordre de démarrage.

## Tests et vérifications

- Relecture ciblée des chemins de concurrence : timeout d'acquisition, pcall interne, rollback partiel après plusieurs `AddBubbles`, double appel `Sell` (le second échoue proprement une fois le sac vidé par le premier), `RollbackAdd` avec jeton déjà invalidé pendant l'attente du verrou (revalidé sous verrou → no-op sûr).
- Diagnostics IDE sur `BackpackService.lua` et `init.server.lua` : aucun problème.
- `git diff --check` : aucun conflit d'espacement.

## Préoccupations

- Aucun exécuteur Luau/Studio configuré dans le dépôt ; vérifications statiques + relecture manuelle uniquement.
- `AddBubbles`/`RoundSellValue` supposent que l'appelant (Task 5, `BubbleService`) applique l'arrondi avant ou utilise `RoundSellValue` ; l'intégration réelle avec les multiplicateurs sera validée à cette tâche.

---

## Correctifs Medium/Important (review)

**Statut :** terminé — commit `cba2fb0`.

**SHA :** `cba2fb0`

### Changements

- Invariant symétrique `enforceBackpackInvariant` : si `CurrentBubbles <= 0` **ou** `PendingSellValue <= 0`, les deux champs sont remis à 0 (appliqué après `AddBubbles` et `RollbackAdd`).
- Compteur de génération session `gen[player]` : `Tx.Gen` est tamponné à l'ajout ; `Sell` incrémente la gen après vidage ; `RollbackAdd` no-op (`false`) si `tx.Gen ~= gen` courante (rollback périmé post-vente).
- `AddBubbles` rejette désormais `sellValue <= 0` (en plus de `storageAmount <= 0` déjà rejeté).
