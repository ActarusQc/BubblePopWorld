# Plan — Hub central « Concept 2 — Équilibré »

Décision approuvée : le hub central au milieu des bulles remplace le lobby séparé comme
point d'arrivée. Référence visuelle = maquette « CONCEPT 2 — ÉQUILIBRÉ ». Concept 3 rejeté.

## Orientation de référence

La maquette est vue depuis l'avant du hub. Pour que le joueur voie exactement cette
composition dès son apparition :

| Élément | Direction monde |
|---|---|
| Ouverture / descente vers les bulles | `+Z` (nord) |
| Panneaux `TOP 3`, `RULES`, boucle | `-Z` (sud) |
| `SELL` (gauche du joueur) | `-X` (ouest) |
| `SHOP` (droite du joueur) | `+X` (est) |
| Regard du joueur au spawn | `-Z` |

Conséquence utile : la convention historique **SELL ouest / SHOP est** est conservée,
donc `SellBooth.YawDegrees = 90` et `ItemShop.YawDegrees = 270` restent valides.

### Arbitrage du regard au spawn

Deux exigences ne peuvent pas être vraies en même temps : « voir la mer de bulles droit
devant » et « lire `POP → SELL → UPGRADE` avec SELL à gauche / SHOP à droite ». Le regard
`-Z` a été retenu parce qu'il reproduit exactement la composition de la maquette
(panneau boucle en face, SELL à gauche, SHOP à droite, `TOP 3` / `RULES` derrière le
panneau) ; les bulles restent visibles tout autour du deck surélevé, et la descente est à
un demi-tour, largement sous les 10 secondes visées.

Pour inverser : `GameConfig.Hub.Spawn.YawDegrees = 0` (le joueur apparaît face à
l'escalier et aux bulles, SELL passe alors à sa droite). Un seul nombre, aucun autre
changement.

## Géométrie cible

- Centre du hub : `Grid.Origin` en X/Z, dessus de la plateforme à `Y = 12`
  (bulles à `Y ≈ 7.35`, plancher de jeu à `5.3`).
- Deck octogonal : demi-emprise `42 × 30`, coins chanfreinés à `12` (4 `WedgePart`).
- Fondation pleine sous le deck jusqu'au plancher de jeu : plus aucun trou visible.
- Escalier avant : 4 marches de `1.1` de haut, `26` studs de large, `Z = 30 → 44`.
- Garde-corps bas (`3.5`) sur tout le périmètre sauf l'ouverture avant.

## Étapes

1. `GameConfig.Hub` — configuration centrale (dimensions, offsets, couleurs, flags
   d'import d'assets). Aucun nombre magique dans les builders.
2. `Shared/HubLayout.lua` — géométrie **pure** dérivée de la config : CFrames des
   modules, emprise, rectangles réservés, prédicat `IsCellReserved`.
3. `Shared/HubLayoutTests.lua` — symétrie, containment, non-chevauchement, réservation.
4. `Server/CentralHubBuilder.lua` — construction idempotente :
   deck + fondation + chanfreins + garde-corps + escalier + médaillon de spawn +
   `SpawnLocation` + panneau boucle + stand SELL (`SellZone`, `SellValueBoard`) +
   stand SHOP + panneaux `TOP 3` / `RULES` + socle Bubble Transit + `HubAnchors`.
5. `ZoneService` — spawn/FallReset/vente sur le hub, lobby et connexion non construits,
   bordure sud refermée, exclusion du hub dans l'analytics « reached main bubble room ».
6. `BubbleService` — cellules réservées sous l'emprise du hub non instanciées.
7. `ItemShopBuilder` — ancre hub, pas de `FallbackShell`, validation d'emprise hub.
8. `LeaderboardService` — panneau `TOP 3` (3 lignes) et résolution de surface hub.
9. `TravelConfig` / `TravelController` — destination `CentralHub` (retour depuis Summer),
   destination `Lobby` désactivée, pastille lobby non construite.
10. `LocalizationStrings` + `HUD` — textes hub, `SellValueBoard` trouvé dans le hub.
11. Câblage de la suite de tests dans `init.server.lua`.

## Comportements modifiés (documentés)

- **Tous** les joueurs apparaissent dans le hub central (avant : nouveau joueur →
  `GameRoom`, vétéran → `Lobby`). `OnboardingConfig.ShouldSpawnInGameRoom` reste
  utilisé quand `Hub.Enabled == false`.
- `FallResetDestination = "GameRoom"` renvoie désormais sur le hub.
- `GameAnalyticsService.OnReturnedToLobby` ne peut plus se déclencher (plus de zone
  `Lobby` atteignable). Le funnel « vente » reste piloté par `BackpackService.Sell`.
- Destination Bubble Transit `Lobby` désactivée, remplacée par `CentralHub`.
- 176 cellules de bulles (11 % de la planche Classic) ne sont plus instanciées.
- Le décor Studio du lobby (`SellKiosk`, `ItemShopVisual`, tout enfant du dossier `Lobby`
  non marqué `GeneratedByCode`) est déplacé en Play dans
  `ServerStorage.BPW_ParkedLobbyDecor` : sans plancher de lobby il flotterait à
  l'horizon. Le fichier Studio n'est jamais modifié et tout revient avec
  `Hub.Enabled = false`.

## Retour arrière

`GameConfig.Hub.Enabled = false` restaure intégralement le lobby, les pads sud, la
destination transit `Lobby` et la logique de spawn nouveau/vétéran.

## Assets importés (OBJ / MeshPart)

Chaque module visuel a un flag `UseImported` et un anchor invisible dans
`Workspace.BubblePopWorld.CentralHub.HubAnchors`. Quand le flag est vrai **et** que le
modèle existe dans `Workspace.StudioDecoration.CentralHubVisual`, le code ne génère plus
la forme mais garde tous les repères fonctionnels (SellZone, prompts, surfaces GUI).

### Procédure d'import

1. Modéliser en **studs** (1 unité = 1 stud), pivot au **centre de la boîte** indiquée,
   axe `-Z` = face avant du module, `+Y` = haut.
2. Importer en Roblox, grouper dans un `Model` nommé exactement comme la colonne
   « MODEL À POSER », le poser sous `Workspace.StudioDecoration.CentralHubVisual`.
3. Aligner le `WorldPivot` du modèle sur l'anchor correspondant
   (`CentralHub.HubAnchors.Anchor_<Module>` : attributs `TargetSize`, `YawDegrees`).
4. Passer `GameConfig.Hub.Assets.<Module>.UseImported = true`, relancer.

Fiche des cotes exactes : `python tools\run_central_hub_tests.py` (section 10).

| Module | Taille (studs) | Rôle | Priorité pour la fidélité |
|---|---|---|---|
| `HubDeck` | 84 × 2 × 60 | Plateforme octogonale + fondation + garde-corps | haute (chanfreins et moulures propres) |
| `HubSellStand` | 24 × 8.2 × 22 | Comptoir SELL, auvent, piles de billets | haute |
| `HubShopStand` | 16 × 9 × 22 | Kiosque SHOP ouvert, étagères | haute |
| `HubLoopPanel` | 30 × 6.4 × 0.8 | Cadre du panneau boucle (le texte reste en SurfaceGui) | moyenne |
| `HubTopBoard` / `HubRulesBoard` | 17 × 13 × 0.8 | Cadres coupe + presse-papier de la maquette | moyenne |
| `HubSpawnMedallion` | 18 × 0.4 × 18 | Médaillon étoile au sol | basse |
| `HubStairs` | 26 × 4.7 × 15.5 | Descente frontale + rampes | basse |
| `HubTransitAlcove` | ⌀9 × 0.6 | Socle Bubble Transit (la capsule reste générée) | basse |

Les surfaces de texte (`SurfaceGui`) et les repères (`SellZone`, `SpawnLocation`,
prompts, `CameraPoint_*`) ne sont **jamais** remplacés par un asset : un modèle importé
ne peut donc pas casser le gameplay.

## Vérifications

```
python tools\run_hub_tests.py             # géométrie pure (symétrie, emprise, réservation)
python tools\run_central_hub_tests.py     # build réel, idempotence, bascule asset importé
python tools\run_itemshop_builder_tests.py # kiosque hub + pipeline lobby historique
python tools\run_travel_tests.py          # destination transit sur le hub
```
