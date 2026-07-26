# Rapport — Task 2: DataService

## Statut

Implémentation terminée et commitée.

## Commit

- `b722e16 feat: persist backpack fields and sourced AddCoins`

## Changements

- Ajout des champs persistés `CurrentBubbles`, `BackpackCapacity` et `PendingSellValue`.
- Réconciliation du sac à la charge avec remise à zéro des états invalides et avertissement lorsqu'un sac non vide n'a aucune valeur de vente valide.
- `AddCoins(player, amount, source)` accepte uniquement les crédits positifs, rejette les valeurs non numériques, NaN, `math.huge` et les montants arrondis inférieurs ou égaux à zéro.
- Ajout de la liste de sources de crédits, du marqueur `__dirty`, et exclusion de ce marqueur du payload DataStore.
- Synchronisation des attributs `Coins`, `CurrentBubbles`, `BackpackCapacity` et `PendingSellValue` dans `Push`.
- Ajout de `SetMutationWaiter`; `Save` attend le callback injecté avec `Config.World.MutationLockTimeout`, sans attente fixe. `Release` passe par `Save`.
- `ShopService` conserve `profile.Coins -= cost` et ne passe pas par `AddCoins`.

## Tests et vérifications

- Test statique initial exécuté avant le changement: échec attendu sur les contrats Task 2 absents.
- Test statique Task 2 après changement: succès.
- Revue des exigences: template, invariant, crédits positifs, attributs, verrou de sauvegarde et achat Shop: succès.
- `git show --check HEAD`: succès.
- Diagnostics IDE sur `src/Server/DataService.lua`: aucun problème.

## Auto-revue

La signature publique, les sources autorisées, le timeout du verrou et la compatibilité Shop correspondent au brief. Aucun problème bloquant trouvé.

## Préoccupations

- Aucun exécuteur Luau/Studio ni suite de tests Roblox n'est configuré dans le dépôt; les vérifications sont statiques.
- Les appels actuels de `BubbleService` et `ChestService` restent valides avec `source` optionnel; leur routage final est prévu par la Task 5.

---

## Correctif de revue — Critical/Important

### Statut

Corrigé et commitée dans `7f24f7d fix: harden backpack reconcile and skip save while locked`.

### Changements

- `reconcileBackpack` normalise désormais `BackpackCapacity`, `CurrentBubbles` et `PendingSellValue` selon les bornes de configuration, avec arrondi inférieur des compteurs.
- `NaN`, `math.huge` et `-math.huge` sont remplacés par des valeurs sûres avant les opérations numériques.
- L'invariant sac vide / valeur de vente nulle est appliqué et un sac non vide sans valeur positive est signalé puis réinitialisé.
- `Save` quitte avant toute mise à jour du profil persisté ou `SetAsync` si le waiter de mutation échoue ou expire; `Release` passe par cette même protection.

### Vérifications

- Relecture des chemins de normalisation et de sauvegarde effectuée.
- Diagnostics IDE de `src/Server/DataService.lua`: aucun problème.
- `git diff --check`: succès avant commit.
