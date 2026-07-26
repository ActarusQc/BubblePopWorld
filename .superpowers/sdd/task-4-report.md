# Task 4 — ZoneService : rapport

**Statut :** Terminé

**Commit :** `d96b139` — feat: add ZoneService lobby teleports and safety borders

## Résumé

- Créé `src/Server/ZoneService.lua` : `EnsureWorld` idempotent (`ensureFolder`/`ensurePart`/`ensurePrompt`, `GeneratedByCode=true`, pas de déplacement sauf `RebuildGeneratedLayout`), hiérarchie `Workspace.BubblePopWorld/{Lobby,GameRoom}` avec `LobbySpawn`, `SellZone`, `GameEntrance`, `GameRoomSpawn`, `ExitZone`, `SafetyBorders` (4 côtés, ouverture centrale sud).
- Prompts français : « Entrer dans la salle de bulles », « Retourner au lobby », « Vendre mes bulles » (distance serveur + `BackpackService.Sell`).
- `TeleportToLobby`/`TeleportToGameRoom` : serveur uniquement, attendent HRP, vélocité à zéro, cooldown `Config.World.TeleportCooldown`, attribut `PlayerArea` posé seulement après succès (bypass cooldown pour spawn initial + FallReset).
- Spawn initial : `CharacterAdded` debouncé, attend le profil (`DataService.Get`) puis téléporte au Lobby.
- `FallReset` : boucle `Heartbeat`, sous `FallResetY` → destination `Config.World.FallResetDestination` (défaut GameRoom).
- Positions validées vs `GetGridBounds` + `ClearanceFromGrid` (warn si chevauchement).
- `AmbianceService.BuildWalls` → no-op (barrières déplacées vers `ZoneService`).
- `init.server.lua` : `ZoneService` inséré après `BackpackService`, avant `GlobalCounterService`/`BubbleService`.
- Aucun plancher continu ajouté ; seulement `SpawnPad`/`ExitPad`. Aucune destruction de map existante.

## Concerns

- Test manuel Studio (rojo serve) non exécuté dans cette session (pas d'accès Studio) : à valider (lobby hors grille, chute → GameRoomSpawn, markers non repositionnés).
- `BubbleWorld` (grille) reste parenté directement à `workspace` par `BubbleService` (hors scope Task 4/5).

## Rapport

`e:\roblox\BubblePopWorld\.superpowers\sdd\task-4-report.md`

## Correctif — SafetyBorders hors volume des bulles

**Statut :** Terminé  
**Commit :** `e01d49f` — fix: place SafetyBorders outside bubble extents

- Les validations `GameRoom.SpawnOffset` et `GameRoom.ExitOffset` utilisent désormais `Config.Lobby.ClearanceFromGrid` (40) au lieu de `0`.
- Les limites des murs sont calculées à partir de `Config.Grid` et de `Config.World.BorderThickness`; le sol de `BubbleService` n'a pas été modifié.
- Math (X/Z) : centre extrême = `(40 / 2 - 0.5) × 6 = 117`; surface bulle = `117 + 5.4 / 2 = 119.7`; face intérieure = `119.7 + 2 = 121.7`; avec épaisseur `3`, centre des murs = `121.7 + 3 / 2 = ±123.2`. L'ouverture sud est conservée.
