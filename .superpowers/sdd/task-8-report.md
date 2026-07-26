# Task 8 — Validation statique de la boucle de progression

Périmètre : vérification statique uniquement. Roblox Studio n'a pas été exécuté.

## Résultat

- Statut : `VERIFIED_STATIC`
- Échecs de code : **0**
- Commit : non requis (aucun `FAIL` détecté)

## Contrôles statiques demandés

| Contrôle | Statut | Preuve statique |
|---|---|---|
| Fichiers Git sans `rojo.exe` ni `*.rbxl*` | `VERIFIED_STATIC` | `git ls-files` (code retour 0) ne liste aucun de ces fichiers. |
| `BubbleService` ne crédite pas les pièces via `AddCoins` | `VERIFIED_STATIC` | Aucun résultat `AddCoins` dans `src/Server/BubbleService.lua`; les pops appellent `BackpackService.AddBubbles` et n'ajoutent que l'XP après succès. |
| Coffres avec source `"Chest"` | `VERIFIED_STATIC` | `ChestService.lua` appelle `DataService.AddCoins(player, coins, "Chest")`. |
| `BackpackService` possède un verrou de mutation et `Sell` | `VERIFIED_STATIC` | Le verrou par joueur `locks` protège `AddBubbles`, `RollbackAdd` et `Sell` via `runLocked`; `Sell` appelle `DataService.AddCoins(..., "BubbleSale")` puis vide le sac. |
| Rollback concurrent ne restaure pas un snapshot global | `VERIFIED_STATIC` | La transaction contient uniquement `StorageAdded`, `SellValueAdded` et `Gen`; `RollbackAdd` retire uniquement ces montants sous verrou. |
| Vente concurrente pendant un pop sérialisée | `VERIFIED_STATIC` | `AddBubbles`, `RollbackAdd` et `Sell` passent par le même verrou `runLocked`. |
| Achat Shop conservé | `VERIFIED_STATIC` | `ShopService` conserve `BuyUpgrade`, débite les pièces, applique l'upgrade et pousse les stats. |
| `ZoneService` gère les téléports et `FallReset` | `VERIFIED_STATIC` | `TeleportToLobby`, `TeleportToGameRoom`, cooldown de téléport, et `watchFallReset` sont présents; la destination est configurée par `FallResetDestination`. |
| Aucun plancher dans `BubbleService.BuildWorld` | `VERIFIED_STATIC` | `BuildWorld` crée uniquement le dossier et la grille de bulles; le commentaire explicite l'absence de plancher continu. |
| HUD sac alimenté par attributs | `VERIFIED_STATIC` | `HUD.lua` lit `CurrentBubbles`, `BackpackCapacity`, `PendingSellValue` et `PlayerArea` avec `GetAttribute`, puis écoute leurs changements. |

## Checklist du spec §11

Les scénarios suivants nécessitent une exécution Play Solo/serveur Roblox Studio et restent donc à réaliser :

| Scénario | Statut |
|---|---|
| Nouveau joueur lobby, sac `0/25` | `NEEDS_STUDIO` |
| Entrée / sortie / anti-spam téléport | `NEEDS_STUDIO` |
| Pop : sac augmente, pièces inchangées, XP augmente | `NEEDS_STUDIO` |
| Outils / Épingle : capacité | `NEEDS_STUDIO` |
| Sac plein et cooldown du message | `NEEDS_STUDIO` |
| `StorageValue` supérieur au reste | `NEEDS_STUDIO` |
| Vente OK / vide / incohérences réconciliées | `NEEDS_STUDIO` |
| Double vente ; déconnexion pendant vente | `NEEDS_STUDIO` |
| Respawn / reconnexion avec sac partiel | `NEEDS_STUDIO` |
| Coffre avec pièces directes | `NEEDS_STUDIO` |
| Chute vers `GameRoomSpawn` | `NEEDS_STUDIO` |
| Barrières | `NEEDS_STUDIO` |
| Deux joueurs, même bulle : un seul gagnant | `NEEDS_STUDIO` |
| Migration profil ; HUD après reconnexion | `NEEDS_STUDIO` |
| Marker Studio non repositionné avec `Rebuild=false` | `NEEDS_STUDIO` |

## Contrôles additionnels du brief

| Scénario | Statut | Justification |
|---|---|---|
| Deux pops concurrents, rollback A ne supprime pas B | `NEEDS_STUDIO` | Mécanisme de rollback différentiel vérifié statiquement; comportement concurrent à exercer en Studio. |
| Vente pendant pop bloquée par mutex | `NEEDS_STUDIO` | Mutex partagé vérifié statiquement; interleaving réel à exercer en Studio. |
| Achat Shop toujours opérationnel | `NEEDS_STUDIO` | Chemin serveur `BuyUpgrade` vérifié statiquement; achat réel à exercer en Studio. |

## Limites

Aucun build Rojo, publication ou test Studio n'a été exécuté, conformément au périmètre demandé.
