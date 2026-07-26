# Final layout fix — Critical findings (C1, C2) + Important

**Statut :** Terminé
**Fichiers :** `src/Shared/GameConfig.lua`, `src/Server/ZoneService.lua` (+ `src/Client/HUD.lua`, `src/Server/BackpackService.lua` conservés : couplés au panneau de vente créé par `ZoneService`)

## C1 — Passerelle pad → grille de bulles

Avant : `ArrivalPath` avait une longueur fixe (`PathSize.Z = 18`) posée au milieu de l'intervalle
pad/grille. Avec un écart réel de ~30 studs, il restait ~12 studs de vide entre la fin du chemin
et la première rangée de bulles → chute systématique et boucle `FallReset`.

Après (`ZoneService.buildGameRoom`) :

- longueur calculée à l'exécution : du bord nord du `SpawnPad` (`spawnPos.Z + PadSize.Z/2`)
  jusqu'à la face sud des bulles (`Origin.Z - ((SizeZ/2 - 0.5) * Spacing + BubbleSize.Z/2)`),
  avec 1 stud de recouvrement de chaque côté (pas de joint) ;
- largeur / épaisseur / couleur depuis `GameConfig.GameRoom.PathSize` (X, Y) et `PathColor` ;
- dessus de la passerelle aligné sur `Grid.Origin.Y` (= dessus des pads, 1 stud sous le sommet
  des bulles : marche montante naturelle) ;
- `GeneratedByCode = true` (via `ensurePart`), donc idempotent et reconstruit uniquement avec
  `RebuildGeneratedLayout` ;
- l'ouverture sud des `SafetyBorders` est maintenant calibrée sur la passerelle
  (`PathSize.X + 8 = 24` au lieu de `PadSize.X + 8 = 36`) : le trou latéral est réduit ;
- garde-corps en verre le long de la passerelle (`PathRailLeft/Right`), arrêtés avant la première
  rangée de bulles pour ne pas les traverser.

## C2 — Séparation Lobby / GameRoom

- `Lobby.RootOffset` = `(0, 0, -240)` (au lieu de -230 dans le WIP). Plancher 110×80 →
  **Z ∈ [-280, -200]**, hors de toute emprise de pad.
- Pads redimensionnés et repositionnés pour être **jointifs mais jamais sécants** :
  `SpawnPad` Z ∈ [-176, -152] (28×24), `ExitPad` Z ∈ [-192, -176] (22×16, nouveau
  `GameRoom.ExitPadSize` — la taille était codée en dur dans `ZoneService`).
- 8 studs de dégagement entre le bord sud de l'`ExitPad` et le bord nord du plancher du lobby.
- `LobbySpawn` = `(0, 4, -240)` : centre du plancher du lobby, à plus de 55 studs de l'`ExitPad`.
- `SpawnPadPosition.Z = -164` reste ≤ `MinZ - ClearanceFromGrid` (-160) : aucun avertissement
  `assertOutsideGrid`.
- Nouvelles validations au chargement de `GameConfig` : chevauchement des **emprises au sol**
  (Lobby.Floor × SpawnPad × ExitPad) et position du `LobbySpawn` (sur le plancher du lobby,
  jamais au-dessus d'un pad). Warnings uniquement, aucune erreur bloquante.

## RebuildGeneratedLayout

`GameConfig.World.RebuildGeneratedLayout = false` (le WIP était à `true`).

> Attention déploiement : dans un lieu déjà construit avec l'ancienne géométrie, les objets
> `GeneratedByCode` existants ne sont pas repositionnés tant que le flag reste `false`.
> Passer le flag à `true` une seule fois (ou supprimer `Workspace.BubblePopWorld`), lancer,
> puis remettre `false`.

## Important

- **FallReset contextuel** : `fallResetToLobby(player)` renvoie le lobby si
  `player.PlayerArea == "Lobby"`, sinon suit `World.FallResetDestination` (défaut `GameRoom`).
  Une chute depuis le lobby ne téléporte plus dans la salle de bulles.
- **`ZoneService.Start`** : `bindPlayer` est appliqué à `Players.PlayerAdded` **et** aux joueurs
  déjà présents (`Players:GetPlayers()`), utile en hot reload Rojo / Studio.
- Save-on-timeout inchangé (hors périmètre).

## Non touché

`BackpackService` mutex / transactions et le claim token cellule de `BubbleService` :
aucune modification de logique. Le seul changement `BackpackService` conservé est le texte de
l'annonce de vente.

## Géométrie (Z, studs)

| Élément | Z min | Z max | X | Dessus (Y) |
|---|---|---|---|---|
| Grille de bulles (faces) | -119.7 | +119.7 | ±119.7 | 7 |
| Barrière sud (ouverture X ∈ [-12, 12]) | -123.7 | -121.7 | — | 28 (collision) |
| Passerelle `ArrivalPath` | -153.0 | -118.7 | ±8 | 6 |
| `SpawnPad` | -176 | -152 | ±14 | 6 |
| `ExitPad` | -192 | -176 | ±11 | 6 |
| Plancher du lobby | -280 | -200 | ±55 | 0 |
| `LobbySpawn` | -240 | -240 | 0 | 4 (marker) |

## Tests

Analyse statique uniquement (aucun binaire Luau / Rojo / Studio disponible dans cette session) :
pas de diagnostic de lint sur les fichiers modifiés, géométrie vérifiée à la main (voir tableau).
À valider en Studio : marcher du `SpawnPad` jusqu'aux bulles sans chute, chute depuis le lobby →
retour lobby, chute dans la salle → `SpawnPad`, vente au comptoir.
