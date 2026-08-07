# Spécification de production — Asset pack 3D du hub central « Concept 2 — Équilibré »

Statut : **spécification uniquement**. Aucun script de production n'est modifié par ce
document. La version actuelle générée par script est officiellement rétrogradée en
`PrototypeVisualFallback` : elle reste l'architecture, le gameplay, les repères, les
collisions et le mode debug, mais elle **n'est plus le rendu final approuvé**.

Références :

- maquette `CONCEPT 2 — ÉQUILIBRÉ` (source de vérité artistique) ;
- rendu Studio actuel (prototype rejeté), dont la géométrie exacte est reproduite plus bas
  à partir du code (inventaire mesuré, pas estimé) ;
- ancres autoritatives : `src/Shared/HubLayout.lua` et `GameConfig.Hub`
  (dump : `python tools\run_central_hub_tests.py`, section 10).

## 0. Repère monde et cotes de référence

Toutes les cotes sont en **studs**, dans le repère monde du jeu.

| Axe | Direction | Signification |
|---|---|---|
| `+Z` | avant | vers les bulles, côté caméra de la maquette |
| `-Z` | arrière | panneaux `TOP 3` / `RULES` / Bubble Transit |
| `-X` | gauche du joueur au spawn | aile `SELL` |
| `+X` | droite du joueur au spawn | aile `SHOP` |
| `+Y` | haut | — |

Centre du hub : `(0, ·, 0)`. Altitudes clés :

| Niveau | Y |
|---|---|
| Dessus du plancher de jeu (sous les bulles) | `5.30` |
| Surface de marche sur les bulles | `7.35` |
| Bas de la fondation du hub | `4.50` |
| Haut de la fondation | `8.20` |
| Haut du socle intermédiaire (plinth) | `10.00` |
| **Dessus du deck (niveau principal)** | **`12.00`** |
| Dessus des plateformes Sell / Shop | `13.20` |
| Haut du garde-corps | `15.50` |
| Bas des panneaux arrière | `20.50` |
| Haut des panneaux arrière | `33.50` |

Emprise du deck : octogone `84 × 60` (demi-emprise `42 × 30`), chanfreins de `12` de
jambe. Conséquences géométriques exactes :

- arête avant plate : `60` de large, à `Z = +30` ;
- arête arrière plate : `60` de large, à `Z = -30` ;
- arêtes latérales plates : `36` de profondeur, à `X = ±42` ;
- 4 arêtes chanfreinées : longueur `16.97`, centres `(±36, ·, ±24)`, yaw `±45°` ;
- ouverture frontale (sans garde-corps) : `28` de large, centrée sur `X = 0`.

## 1. Comparaison détaillée maquette vs prototype

Inventaire mesuré du prototype (126 pièces visibles dans `HubStructure`, hors repères
invisibles et ancres) :

| Matériau | Pièces |
|---|---|
| `SmoothPlastic` | 68 |
| `Neon` | 56 |
| `Glass` | 1 |
| `Slate` | 1 |
| `MeshPart` | **0** |
| `SurfaceAppearance` | **0** |
| Sources lumineuses (`PointLight` / `SpotLight`) | **0** |

Couleurs dominantes : `96,106,128` (30 pièces), `90,210,255` cyan néon (26),
`214,220,232` blanc bleuté (12 pièces — mais ce sont **les plus grandes surfaces**),
`24,34,62` (11), `255,205,80` (10).

### 1.1 Plateforme — écart le plus grave

| Constat prototype (mesuré) | Maquette | Écart |
|---|---|---|
| `DeckMiddle` `84 × 2 × 36` en `214,220,232` (blanc bleuté), + `DeckFront` / `DeckBack` `60 × 2 × 12`, + 4 wedges `2 × 12 × 12` | base graphite foncé, ~`RGB 55-80` | la totalité du sol du hub est quasi blanche : c'est l'erreur n°1, elle donne l'aspect « plateforme temporaire » |
| `HubFoundationGlow` : dalle néon cyan `73 × 0.6 × 49` (2146 studs³) | liseré cyan **fin**, intégré dans la moulure de bordure | une fondation cyan massive, exactement ce qui est rejeté |
| Octogone = 3 boîtes + 4 wedges, arêtes verticales à 90° vives | bordure **stratifiée** : nez de dalle, moulure, retrait, jupe | aucun chanfrein vertical, aucune moulure, aucune profondeur de bord |
| 3 niveaux (fondation `Slate`, plinth `96,106,128`, deck blanc) mais tous plats et lisses | 4-5 strates lisibles avec ombres portées | la stratification existe dans la config mais ne se **voit** pas : pas de retrait suffisant (2.5 studs), pas de variation de matériau |
| Centre du deck strictement à la même hauteur que le reste | centre légèrement surélevé sous le médaillon | silhouette plate, pas de hiérarchie centrale |
| `HubSellPlatform` / `HubShopPlatform` : 2 boîtes `24 × 1.2 × 22` blanches posées sur le deck | ailes **intégrées** à la structure, avec jupe et moulure continues | les ailes ressemblent à des palettes posées, pas à un prolongement du bâti |
| Fondation `70 × 3.7 × 46` : rentrée de 7 sur tous les bords | jupe qui descend visiblement jusqu'aux bulles, sans vide | vue de côté, le deck surplombe le vide sur 7 studs → effet de plateforme flottante |

### 1.2 Kiosque `SELL`

| Constat prototype | Maquette | Écart |
|---|---|---|
| `HubSellCounter` `15 × 4.2 × 5.4` en `24,34,62` (bleu nuit très sombre) | comptoir clair posé dans une alcôve **verte** | lu comme un gros bloc noir |
| `HubSellBackWall` `17 × 9 × 1.2` + `HubSellCanopy` `17 × 1 × 8.5` : 2 dalles orthogonales | cadre épais en U, montants larges, auvent mouluré | aucune épaisseur de cadre, aucune arche, aucune profondeur |
| Intérieur du stand : rien (dalle sombre) | fond vert lumineux + étagères + caisses + billets | l'intérieur est vide, aucun volume ne remplit l'alcôve |
| Enseigne `HubSellSign` `14 × 3.4 × 0.9` : dalle posée au-dessus de l'auvent | enseigne **intégrée** au fronton, épaisse, avec cadre et halo | enseigne « plaquée », typique du prototype |
| Accents : 9 disques néon or (`HubSellCoin*`) + 1 cube `Glass` | piles de billets et caisses modélisées | les pièces néon lisent comme des jetons flottants |
| Emprise `24 × 8.2 × 22` : plus profond (22) que haut (8.2) | kiosque plutôt haut que profond (~1:1) | proportions écrasées, silhouette trop basse et trop étalée |

### 1.3 Kiosque `SHOP`

| Constat prototype | Maquette | Écart |
|---|---|---|
| `HubShopBackWall` `22 × 9 × 1` + 2 murs latéraux `10 × 9 × 1` | alcôve ouverte avec cadre épais et fronton | 3 dalles fines = boîte ouverte, pas un kiosque |
| `HubShopCanopy` : dalle `24 × 1.1 × 12` (world `12 × 1.1 × 24`) qui dépasse la plateforme de 1 stud de chaque côté | auvent mouluré aligné sur le cadre | débord visible = défaut d'alignement |
| 10 cubes néon `1.5³` (`HubShopGoods*`) sur 2 étagères | objets exposés variés (potions, coffres, panier) | cubes néon = placeholder évident |
| Comptoirs `HubShopCounterL/R` en 2 tronçons rectangulaires | comptoir compact unique avec panneau frontal décoré | volumes bruts |
| Couleur dominante `230,95,215` en néon | violet/magenta **en accent** sur structure graphite | néon utilisé comme matériau principal |
| Emprise world `16 × 9 × 22` (profondeur X = 16) contre `24 × 8.2 × 22` pour le Sell | Sell et Shop strictement symétriques | asymétrie gauche/droite non justifiée (8 studs d'écart en profondeur) |

### 1.4 Panneau central `POP → SELL → UPGRADE`

| Constat prototype | Maquette | Écart |
|---|---|---|
| `HubLoopPanel` `30 × 6.4 × 0.8` | cadre large, épais, coins arrondis | rapport `4.7:1` contre ~`3.5:1` estimé sur la maquette → panneau en boîte aux lettres |
| Épaisseur `0.8` + « cadre » = une seconde dalle néon `31.2 × 7.6 × 0.5` | cadre en relief de 1.5-2 studs d'épaisseur avec biseau | cadre plat, pas de relief, halo néon en aplat |
| `HubLoopPlinth` `31.6 × 1.5 × 3.2` : simple boîte sous le panneau | pieds / supports intégrés, socle mouluré | socle brut |
| Aucune profondeur : le panneau est une dalle | caisson avec côtés visibles | silhouette « carton » |

### 1.5 `TOP 3` et `RULES`

| Constat prototype | Maquette | Écart |
|---|---|---|
| 2 dalles `17 × 13 × 0.8` + une dalle néon `18.4 × 14.4 × 0.55` | cadres épais à **sommet arrondi**, socle plein, icônes trophée / presse-papiers en relief | sommet plat, aucun arrondi, aucune icône 3D |
| Pieds : 2 boîtes `1.6 × 8.5 × 1.6` par panneau | supports intégrés au socle | pieds grêles, panneau qui semble sur pilotis |
| Largeur `17` pour `13` de haut | ~`20 × 14.5` estimé (cadre compris) | panneaux un peu étroits, cadre trop mince |

### 1.6 Bubble Transit

| Constat prototype | Maquette | Écart |
|---|---|---|
| `HubTransitAlcove` : cylindre `⌀9 × 0.6` + anneau néon violet | petite arche avec portail cyan, enseigne intégrée, profondeur réelle | il n'y a **aucun** volume vertical : le module est absent visuellement |

### 1.7 Escalier et jonction aux bulles

| Constat prototype | Maquette | Écart |
|---|---|---|
| 3 marches `26 × 2.75 × 3.5` blanches (`214,220,232`), tops `10.45` / `8.90` / `7.35` | marches graphite avec nez mouluré et joues latérales | couleur fausse, aucun nez sculpté, joues absentes (remplacées par 6 boîtes `0.9 × 2.6 × 3.5`) |
| `HubStairsLanding` `26 × 1.2 × 10.8` blanc, avant à `Z = 51.3` | palier intégré, transition douce vers les bulles | géométriquement correct (touche la première bulle vivante) mais visuellement blanc et plat |
| `HubBubblesArrows` : dalle + SurfaceGui | flèches en relief lumineuses encastrées dans le sol | flèches en texture plate |

### 1.8 Éclairage, matériaux, hiérarchie visuelle

- **56 pièces `Neon` sur 126** (44 %) : le néon sert de matériau de base au lieu d'être un
  accent. La maquette n'a que des liserés fins et des points lumineux localisés.
- **Zéro source lumineuse** : aucun `PointLight` / `SpotLight` / `SurfaceLight`. La maquette
  montre des projecteurs sous les auvents, des bornes basses le long du deck et une lueur
  au sol autour du médaillon.
- **Aucune variation de roughness** : `SmoothPlastic` partout, donc aucune lecture métal /
  pierre / composite.
- **Hiérarchie visuelle inversée** : les plus grands volumes du hub sont blancs et unis
  (`DeckMiddle` 6048 studs³, `PlinthMiddle` 4408, `HubFoundationGlow` 2146), donc l'œil est
  attiré par le sol au lieu des panneaux et des kiosques. Dans la maquette, le sol est le
  fond sombre et les kiosques colorés sont les points focaux.
- **Silhouette frontale** : depuis la caméra de référence, le prototype présente un trapèze
  clair, sans découpe verticale ni sommet arrondi ; la maquette présente une silhouette
  découpée (deux tours arrondies à l'arrière, deux frontons de kiosques, une arche de
  transit sur la droite) sur une base sombre.

## 2. Caméra de validation `CentralHubConcept2ReferenceCamera`

Caméra **de contrôle artistique uniquement**. Elle n'est jamais appliquée à la caméra des
joueurs : c'est un `Camera` ou un `Part` repère nommé
`CentralHubConcept2ReferenceCamera`, placé dans
`Workspace.StudioDecoration.CentralHubVisual.ValidationCameras`, non ancré au gameplay et
sans script.

| Paramètre | Valeur |
|---|---|
| Position | `(0, 74, 124)` |
| Cible (point visé) | `(0, 15, 4)` |
| Distance à la cible | `133.7` studs |
| Hauteur au-dessus du deck | `+62` studs (deck à `Y = 12`) |
| Yaw | `180°` (regard vers `-Z`) |
| Pitch | `-26.2°` |
| Roll | `0°` |
| `FieldOfView` (vertical Roblox) | `36` |
| Rapport d'image | `16:9` — rendu de contrôle `1920 × 1080` |

Construction exacte (à coller dans la barre de commande Studio, hors runtime) :

```lua
workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(0, 74, 124), Vector3.new(0, 15, 4))
workspace.CurrentCamera.FieldOfView = 36
```

Cadrage garanti par ce réglage :

- sommet des panneaux arrière (`Y = 33.5`, `Z = -23`) à `10.8°` au-dessus de l'axe ;
- avant du palier d'escalier (`Y = 7.35`, `Z = 51.3`) à `16.3°` sous l'axe ;
- bords latéraux du deck (`X = ±42`) à `16.6°` de l'axe, pour une demi-ouverture
  horizontale de `28.5°` → le hub occupe ~60 % de la largeur, comme la maquette, avec des
  bulles sur tout le pourtour.

### Caméras secondaires de validation (captures obligatoires)

| Nom | Position | Cible | FOV | Rapport |
|---|---|---|---|---|
| `ValidationCam_Spawn` | `(0, 19.5, 20)` | `(0, 16.5, -10)` | `70` | 16:9 |
| `ValidationCam_FromBubbles` | `(0, 12, 92)` | `(0, 16, 20)` | `55` | 16:9 |
| `ValidationCam_Back` | `(0, 66, -112)` | `(0, 18, -10)` | `40` | 16:9 |
| `ValidationCam_Top` | `(0, 152, 4)` | `(0, 12, 0)` | `40` | 16:9 |
| `ValidationCam_Mobile` | `(0, 74, 124)` | `(0, 15, 4)` | `40` | 20:9 (`2340 × 1080`) |

## 3. Modules 3D requis

Règles communes à tous les modules :

- **Unité** : 1 unité de modélisation = 1 stud. Chaque export contient un cube témoin
  `ScaleCheck_10` de `10 × 10 × 10` studs (à supprimer après contrôle) : après import, sa
  `Size` doit afficher exactement `10, 10, 10`.
- **Pivot** : au centre de la bounding box indiquée, sauf mention contraire, à
  l'altitude indiquée dans la colonne « centre monde ».
- **Orientation d'authoring** : `-Z` = face avant du module, `+Y` = haut. Le yaw indiqué
  est appliqué **à l'import dans Roblox**, pas dans le fichier source.
- **Limite dure Roblox** : `10 000` triangles par mesh. Les budgets ci-dessous indiquent le
  découpage en meshes.
- **Aucun script**, aucun `SurfaceGui`, aucune `ProximityPrompt` dans les meshes.
- **Collisions** : `CanCollide = false` sur tous les meshes visuels sauf mention contraire,
  car les volumes de collision restent des Parts invisibles générées par le code
  (`PrototypeVisualFallback` conserve exactement les collisions actuelles). Les meshes qui
  doivent porter la collision sont explicitement notés, avec `CollisionFidelity = Box` ou
  `Hull`.
- `CastShadow = true` uniquement sur les coques principales (deck, kiosques, panneaux) ;
  `false` sur les accents néon et les petits props.

### 3.1 `HubDeckShell` — priorité 1

| Champ | Valeur |
|---|---|
| Rôle visuel | Plateforme octogonale complète : jupe/fondation, socle intermédiaire, dalle principale, moulures de bordure, accents cyan encastrés, ailes Sell et Shop intégrées |
| Bounding box | `84 × 8.7 × 60` (`X × Y × Z`) — inclut les ailes surélevées |
| Centre monde | `(0, 8.85, 0)` — de `Y = 4.50` (bas de jupe) à `Y = 13.20` (dessus des ailes) |
| Orientation | yaw `0°` |
| Pivot | `(0, 8.25, 0)`, aligné sur `Anchor_Deck` (`CentralHub.HubAnchors.Anchor_Deck`, `TargetSize = 84 × 2 × 60`) — **distinct** du centre bbox ; ne pas recentrer le modèle sur `(0, 8.85, 0)` |
| Silhouette imposée | octogone : arête avant/arrière plate `60`, arêtes latérales `36`, 4 chanfreins de `16.97` à `±45°`, centres `(±36, ·, ±24)` |
| Strates verticales imposées | jupe `Y 4.50→8.20` (rentrée de 7 max, biseau vers le bas) · socle `Y 8.20→10.00` (rentré de `2.5`) · dalle `Y 10.00→12.00` · nez de dalle en surplomb de `0.6` avec gorge de `0.25` |
| Ailes Sell / Shop | 2 plateaux `24 × 1.2 × 22` centrés `(±30, 12.60, 0)`, dessus à `Y = 13.20` (dessous `Y = 12.00`), **rattachés à la dalle par une jupe continue, une moulure et 2 marches de `0.6`**, jamais posés ni affleurants |
| Centre surélevé | disque de `Ø26` centré `(0, ·, 8)`, dessus à `Y = 12.25` (`+0.25`), bord biseauté — reçoit `HubSpawnMedallion` |
| Zones à laisser libres | ouverture frontale `28` de large centrée `X = 0` à `Z = +30` (aucune moulure haute, aucun poteau) · disque `Ø18` en `(0, ·, 8)` (médaillon) · empreinte `11 × 9` en `(-23.6, ·, 0)` (pad de vente) · empreinte `9 × 9` en `(30, ·, 3.5)` (pad panier Shop) · disque `Ø9` en `(34, ·, -19)` (socle transit) |
| Meshes séparés | `DeckShell_Base` (jupe + socle + dalle, ~9 000 tris) · `DeckShell_Moulding` (nez, gorges, moulures, ~5 000) · `DeckShell_Wings` (2 ailes, ~4 000) · `DeckShell_NeonTrim` (liserés cyan, mesh distinct pour matériau Neon, ~2 000) |
| Budget triangles | `20 000` total (4 meshes) |
| LOD | pas de LOD nécessaire (`RenderFidelity = Automatic`) |
| Matériaux | `Slate` sombre (jupe) · `Metal` peint mat (socle) · `Concrete`/composite sombre (dalle) · `Neon` (liserés uniquement) |
| Couleurs | jupe `#23262E` · socle `#31353F` · dalle `#3A3F4B` · nez de dalle `#4A505E` · liserés `#4FD8FF` |
| Textures | `ColorMap` + `NormalMap` + `RoughnessMap` en `1024²`, atlas partagé pour les 3 meshes structurels ; `MetalnessMap` seulement sur `DeckShell_Moulding` |
| Néon | liserés de `0.3` de section encastrés dans la gorge du nez de dalle, sur tout le périmètre **sauf** l'ouverture frontale |
| Points lumineux | aucun dans ce module (voir `HubLightFixtures`) |
| Collisions | `CanCollide = false` (le sol jouable reste les Parts invisibles du code) |
| Ancres fonctionnelles | `Anchor_Deck` |
| Noms d'instances après import | `HubDeckShell` (Model) contenant `Base`, `Moulding`, `Wings`, `NeonTrim` |
| Emplacement | `Workspace.StudioDecoration.CentralHubVisual.HubDeckShell` |

### 3.2 `HubFrontStairs` — priorité 7

| Champ | Valeur |
|---|---|
| Rôle visuel | Descente frontale vers les bulles + palier de raccordement |
| Bounding box | `26 × 4.65 × 20.8` |
| Centre monde | `(0, 8.68, 40.90)` — de `Y = 6.15` (dessous de la 3ᵉ marche) à `Y = 12.00`, de `Z = 30.0` à `Z = 51.3` |
| Orientation | yaw `0°` |
| Pivot | `(0, 12.00, 30.00)` = arête haute au bord du deck (facilite l'alignement) |
| Marches imposées | 3 marches de `26` de large, `3.5` de profondeur, dessus à `Y = 10.45` / `8.90` / `7.35`, centres `Z = 31.75` / `35.25` / `38.75` |
| Palier | `26 × 1.2 × 10.8`, dessus `Y = 7.35`, de `Z = 40.5` à `Z = 51.3` (contact exact avec la première rangée de bulles conservée) |
| Zones à laisser libres | aucune barrière au-dessus de `Y = 12` dans l'ouverture ; joues latérales limitées à `1.2` de large pour ne pas réduire la largeur utile |
| Meshes séparés | `Stairs_Steps` (marches + joues, ~4 000) · `Stairs_Landing` (~1 200) · `Stairs_NeonNosing` (nez lumineux, ~800) |
| Budget triangles | `6 000` |
| Matériaux | `Concrete` sombre (marches), `Metal` (joues), `Neon` (nez) |
| Couleurs | marches `#3A3F4B`, contremarches `#2A2E38`, joues `#4A505E`, nez `#4FD8FF` |
| Textures | `ColorMap` + `NormalMap` + `RoughnessMap` `1024²`, atlas partagé avec `HubDeckShell` |
| Néon | nez de marche de `0.2` de section, plus 2 chevrons au sol sur le palier |
| Points lumineux | 2 `PointLight` (voir `HubLightFixtures`) au niveau des joues |
| Collisions | `CanCollide = false` — les marches jouables restent les Parts du code (mêmes cotes) |
| Ancres fonctionnelles | `Anchor_Stairs`, `Anchor_StairsLanding` |
| Noms d'instances | `HubFrontStairs` → `Steps`, `Landing`, `NeonNosing` |
| Emplacement | `…CentralHubVisual.HubFrontStairs` |

### 3.3 `HubRailingsAndPosts` — priorité 9

| Champ | Valeur |
|---|---|
| Rôle visuel | Garde-corps bas du périmètre + poteaux lumineux bas de la maquette |
| Bounding box | `84 × 4.2 × 60` (creuse, périmètre uniquement) |
| Centre monde | `(0, 14.10, 0)` — de `Y = 12.00` à `Y = 16.20` |
| Orientation | yaw `0°` |
| Segments imposés (repris de `HubLayout.GetRailings`) | avant gauche/droite `16 × 3.5 × 1` en `(∓22, 13.75, 29.5)` · arrière `60 × 3.5 × 1` en `(0, 13.75, -29.5)` · latéraux `1 × 3.5 × 36` en `(±41.5, 13.75, 0)` · 4 chanfreins `17 × 3.5 × 1` en `(±36, 13.75, ±24)` yaw `±45°` |
| Poteaux | 12 poteaux `1.6 × 4.2 × 1.6` aux jonctions de segments et aux extrémités de l'ouverture frontale (`X = ±14`, `Z = 29.5`) |
| Zones à laisser libres | ouverture frontale `28` studs (`X` de `-14` à `+14` à `Z = 29.5`) |
| Meshes séparés | `Railings_Segments` (~5 000) · `Railings_Posts` (~3 000) · `Railings_NeonCaps` (~1 500) |
| Budget triangles | `10 000` |
| Matériaux | `Metal` peint mat (barreaux et poteaux), `Neon` (capuchons et lanternes) |
| Couleurs | structure `#31353F`, capuchon `#4FD8FF`, lanterne `#DCEEFF` |
| Textures | `ColorMap` + `RoughnessMap` `512²` (atlas partagé avec les moulures du deck) |
| Néon | main courante lumineuse de `0.2` + capuchon de poteau |
| Points lumineux | 1 `PointLight` par poteau (`Brightness 0.6`, `Range 12`, `#CFE8FF`) — instanciés dans `HubLightFixtures` |
| Collisions | `CanCollide = false` (la barrière physique reste celle du code) |
| Ancres fonctionnelles | aucune (dérivé du périmètre du deck) |
| Noms d'instances | `HubRailingsAndPosts` → `Segments`, `Posts`, `NeonCaps` |
| Emplacement | `…CentralHubVisual.HubRailingsAndPosts` |

### 3.4 `HubSellStandShell` — priorité 2

| Champ | Valeur |
|---|---|
| Rôle visuel | Kiosque `SELL` vert ouvert : cadre épais graphite en U, fronton avec enseigne `SELL`, alcôve verte, comptoir, caisses et billets décoratifs |
| Bounding box | `18 × 14 × 22` (`X` = profondeur du kiosque, `Z` = largeur visible) |
| Centre monde | `(-33.0, 20.20, 0)` — de `Y = 13.20` (dessus de l'aile) à `Y = 27.20` |
| Orientation | yaw `90°` (façade vers `+X`, c'est-à-dire vers le centre du hub) |
| Pivot | `(-30.0, 13.20, 0)` = `Anchor_SellStand` / `HubLayout.GetSellBaseCFrame()` : origine au sol de l'aile, `+Z` local = vers le centre du hub |
| Composition locale imposée (repère local du stand) | fond à `z = -8` · comptoir centré `z = -3`, hauteur `4.2` · auvent à `y = 9.6` · fronton/enseigne à `y = 11.8`, dimensions `14 × 3.4` · panneau valeur du sac `7.6 × 3.4` à `y = 5.8`, `z = -7.2` |
| Zones à laisser libres | volume de vente `11 × 8 × 12` centré `(-23.6, 16.8, 0)` : **aucun mesh** dedans (le joueur s'y tient) · empreinte `11 × 9` du pad en `(-23.6, 13.5, 0)` : décor au sol autorisé mais épaisseur `≤ 0.3` · surface plane libre pour le `SurfaceGui` du panneau valeur (voir « surfaces GUI ») |
| Surfaces GUI à prévoir | `SellSignFace` : plan `13 × 3` face `+Z` local à `y = 11.8` · `SellValueFace` : plan `7 × 3` face `+Z` local à `y = 5.8` — plans strictement plats, sans relief, matériau neutre |
| Meshes séparés | `SellStand_Frame` (cadre + fronton, ~5 000) · `SellStand_Interior` (fond, étagères, alcôve, ~3 000) · `SellStand_Counter` (~1 500) · `SellStand_NeonTrim` (~1 000) · `SellStand_Props` (caisses, liasses, ~1 500 — peut aller dans `HubDecorProps`) |
| Budget triangles | `12 000` |
| Matériaux | `Metal` peint (cadre), composite mat (fond), `Wood`/`Metal` (comptoir), `Neon` (liserés + halo d'enseigne) |
| Couleurs | cadre `#2E323C` · intérieur `#1E4B33` avec fond dégradé vers `#2FA96A` · comptoir `#5A6172` · accents `#5AE68C` · enseigne `SELL` `#7BFFA8` |
| Textures | `ColorMap` + `NormalMap` + `RoughnessMap` + `MetalnessMap` `1024²`, UV uniques (atlas propre au module) |
| Néon | liseré de cadre `0.25`, bandeau sous l'auvent, halo derrière l'enseigne |
| Points lumineux | 2 `SpotLight` sous l'auvent (vers le bas, `Angle 70`, `Brightness 1.2`, `#B8FFD4`) + 1 `PointLight` dans l'alcôve |
| Collisions | `CanCollide = false`, sauf `SellStand_Counter` en `CollisionFidelity = Box` si l'on veut empêcher de traverser le comptoir (optionnel, non requis) |
| Ancres fonctionnelles | `Anchor_SellStand`, `Anchor_SellZone`, `Anchor_SellPad` |
| Noms d'instances | `HubSellStandShell` → `Frame`, `Interior`, `Counter`, `NeonTrim`, `SellSignFace`, `SellValueFace` |
| Emplacement | `…CentralHubVisual.HubSellStandShell` |

### 3.5 `HubShopStandShell` — priorité 3

| Champ | Valeur |
|---|---|
| Rôle visuel | Kiosque `SHOP` violet/magenta ouvert, strictement symétrique du `SELL` : cadre épais, fronton `SHOP`, alcôve, étagères, petits objets exposés, comptoir compact, icône panier au sol |
| Bounding box | `18 × 14 × 22` (identique au Sell, symétrie imposée) |
| Centre monde | `(33.0, 20.20, 0)` — de `Y = 13.20` à `Y = 27.20` |
| Orientation | yaw `270°` (façade vers `-X`, vers le centre du hub) |
| Pivot | `(30.0, 13.20, 0)` = `Anchor_ShopStand` / `HubLayout.GetShopOrigin()` ; `+Z` local = vers le centre |
| Composition locale imposée | fond à `z = -7.5` · 2 étagères à `y = 2.4` et `y = 5.2` · comptoir compact `y ≤ 3.4` en `z = +5`, largeur locale `≤ 16` avec **passage central de 6 studs libre** · fronton/enseigne `14 × 3.4` à `y = 12.2` |
| Zones à laisser libres | passage central de `6` studs de large sur toute la profondeur (le joueur s'approche des bornes) · cylindre `Ø3` autour de chaque `PromptAnchor_*` généré par `ItemShopBuilder` · empreinte `9 × 9` du pad panier en `(30, 13.2, 3.5)` |
| Surfaces GUI à prévoir | `ShopSignFace` : plan `13 × 3` face `+Z` local à `y = 12.2` · 3 plans `Display_*Face` de `3.4 × 4` à `y = 4.6` alignés sur les `Display_Skills` / `Display_Items` / `Display_Cosmetics` existants |
| Meshes séparés | `ShopStand_Frame` (~5 000) · `ShopStand_Interior` (fond + étagères, ~3 000) · `ShopStand_Counter` (~1 500) · `ShopStand_NeonTrim` (~1 000) · objets exposés → `HubDecorProps` |
| Budget triangles | `12 000` |
| Matériaux | identiques au Sell (symétrie de fabrication), variation de teinte uniquement |
| Couleurs | cadre `#2E323C` · intérieur `#3A1E4B` → `#8E3FD1` · comptoir `#5A6172` · accents `#E65FD7` et `#9664FF` · enseigne `SHOP` `#FFA8F2` |
| Textures | mêmes maps que le Sell, atlas propre au module `1024²` |
| Néon | liseré de cadre, bandeau d'étagère, halo d'enseigne |
| Points lumineux | 2 `SpotLight` sous l'auvent (`#F0C8FF`) + 1 `PointLight` d'étagère |
| Collisions | `CanCollide = false` (les collisions du stand restent les Parts du code) |
| Ancres fonctionnelles | `Anchor_ShopStand`, `PromptAnchor_Skills/Items/Cosmetics`, `CameraPoint_Skills/Items/Cosmetics`, `Display_*` |
| Noms d'instances | `HubShopStandShell` → `Frame`, `Interior`, `Counter`, `NeonTrim`, `ShopSignFace`, `DisplaySkillsFace`, `DisplayItemsFace`, `DisplayCosmeticsFace` |
| Emplacement | `…CentralHubVisual.HubShopStandShell` |

### 3.6 `HubLoopPanelFrame` — priorité 4

| Champ | Valeur |
|---|---|
| Rôle visuel | Caisson 3D du panneau `POP → SELL → UPGRADE` : cadre large et épais, coins arrondis, fond bleu nuit, liseré lumineux discret, supports intégrés |
| Bounding box | `34 × 9.5 × 2.0` (⚠ voir §15 : le prototype fait `30 × 6.4 × 0.8`) |
| Centre monde | `(0, 18.25, -4.0)` — bas du cadre à `Y = 13.50` (dessus du socle), haut à `Y = 23.00` |
| Orientation | yaw `180°` (face lisible vers `+Z`, donc vers le spawn) |
| Pivot | `(0, 13.50, -4.0)` = milieu de l'arête basse, aligné sur `Anchor_LoopPanel` |
| Socle / supports | socle mouluré `36 × 1.5 × 4` de `Y = 12.00` à `13.50`, plus 2 jambes obliques intégrées au dos |
| Zones à laisser libres | face avant plane de `30 × 7` (surface GUI) · dégagement de `1` stud autour du cadre |
| Surfaces GUI à prévoir | `LoopPanelFace` : plan **strictement plat** `30 × 7`, centré `(0, 18.25, -3.0)`, normale `+Z`, sans relief ni texture — reçoit le `SurfaceGui` existant. **Le texte ne doit jamais être gravé ni texturé dans le mesh.** |
| Meshes séparés | `LoopPanel_Frame` (cadre + caisson + supports, ~3 000) · `LoopPanel_NeonEdge` (~1 000) |
| Budget triangles | `4 000` |
| Matériaux | `Metal` peint mat (cadre), composite mat très sombre (fond), `Neon` (liseré) |
| Couleurs | cadre `#2A2E38` · biseau `#4A505E` · fond `#101A34` · liseré `#4FD8FF` (intensité basse) |
| Textures | `ColorMap` + `NormalMap` + `RoughnessMap` `1024²` |
| Néon | liseré périmétrique de `0.25` en retrait de `0.4` derrière le cadre (halo, pas d'aplat) |
| Points lumineux | 2 `SpotLight` rasants sur la face avant (`Brightness 0.8`, `#CFE8FF`) |
| Collisions | `CanCollide = false` |
| Ancres fonctionnelles | `Anchor_LoopPanel` |
| Noms d'instances | `HubLoopPanelFrame` → `Frame`, `NeonEdge`, `LoopPanelFace` |
| Emplacement | `…CentralHubVisual.HubLoopPanelFrame` |

### 3.7 `HubTop3BoardFrame` — priorité 5

| Champ | Valeur |
|---|---|
| Rôle visuel | Panneau arrière gauche : cadre épais, **sommet arrondi**, socle plein, emplacement d'icône trophée en relief |
| Bounding box | `20 × 15.5 × 2.0` cadre + `20 × 3 × 4` socle (⚠ prototype : `17 × 13 × 0.8`) |
| Centre monde | cadre `(-19.0, 28.25, -23.0)` (de `Y = 20.50` à `36.00`) · socle `(-19.0, 19.00, -23.0)` (de `Y = 17.50` à `20.50`) · jambes de `Y = 12.00` à `17.50` intégrées au socle |
| Orientation | yaw `180°` (face lisible vers `+Z`) |
| Pivot | `(-19.0, 20.50, -23.0)` = milieu de l'arête basse du cadre, aligné sur `Anchor_TopBoard` |
| Sommet | arc de rayon `10` sur les `4` studs supérieurs (même famille de formes que `RulesBoard`) |
| Zones à laisser libres | face avant plane `17 × 11.5` · zone d'icône `4 × 4` au sommet |
| Surfaces GUI à prévoir | `Top3Face` : plan plat `17 × 11.5`, centré `(-19, 27.5, -22.0)`, normale `+Z` → reçoit le `SurfaceGui` de `LeaderboardService` (`BPW_Rows = 3`). Le mesh conserve l'instance nommée `GlobalLeaderboardBoard` comme cible de recherche. |
| Meshes séparés | `Top3_Frame` (~2 500) · `Top3_Base` (~800) · `Top3_TrophyIcon` (~700, peut être dans `HubDecorProps`) |
| Budget triangles | `4 000` |
| Matériaux | `Metal` peint (cadre), composite sombre (fond), `Metal` doré brossé (icône) |
| Couleurs | cadre `#2A2E38` · fond `#101A34` · liseré `#FFCD50` · icône `#FFD766` |
| Textures | `ColorMap` + `NormalMap` + `RoughnessMap` + `MetalnessMap` `1024²`, atlas partagé avec `HubRulesBoardFrame` |
| Néon | liseré or discret sur le cadre uniquement |
| Points lumineux | 1 `SpotLight` au sommet, dirigé vers la face (`#FFE7B0`, `Brightness 1.0`) |
| Collisions | `CanCollide = false` |
| Ancres fonctionnelles | `Anchor_TopBoard` |
| Noms d'instances | `HubTop3BoardFrame` → `Frame`, `Base`, `TrophyIcon`, `Top3Face` |
| Emplacement | `…CentralHubVisual.HubTop3BoardFrame` |

### 3.8 `HubRulesBoardFrame` — priorité 6

Identique à `HubTop3BoardFrame`, en miroir sur `X`, avec l'accent ambre et une icône
presse-papiers :

| Champ | Valeur |
|---|---|
| Bounding box | `20 × 15.5 × 2.0` + socle `20 × 3 × 4` |
| Centre monde | cadre `(19.0, 28.25, -23.0)` · socle `(19.0, 19.00, -23.0)` |
| Orientation / pivot | yaw `180°`, pivot `(19.0, 20.50, -23.0)`, aligné sur `Anchor_RulesBoard` |
| Surface GUI | `RulesFace` : plan plat `17 × 11.5`, centré `(19, 27.5, -22.0)`, normale `+Z` |
| Couleurs | cadre `#2A2E38` · fond `#101A34` · liseré `#FFAA3C` · icône presse-papiers `#F0F4FF` |
| Budget triangles | `4 000` (`Rules_Frame`, `Rules_Base`, `Rules_ClipboardIcon`) |
| Lien visuel | même famille de formes, même hauteur, même cadre, même socle que `Top3` ; les deux panneaux restent **séparés** mais reliés au sol par une plinthe basse commune de `1.5` de haut allant de `X = -29` à `X = 29` à `Z = -23` |
| Noms d'instances | `HubRulesBoardFrame` → `Frame`, `Base`, `ClipboardIcon`, `RulesFace` |
| Emplacement | `…CentralHubVisual.HubRulesBoardFrame` |

### 3.9 `HubTransitShell` — priorité 8

| Champ | Valeur |
|---|---|
| Rôle visuel | Petite arche Bubble Transit avec portail cyan, enseigne intégrée, profondeur réelle. Taille **secondaire** : ne doit jamais concurrencer les kiosques |
| Bounding box | `10 × 11 × 10` |
| Centre monde | `(34.0, 17.50, -19.0)` — de `Y = 12.00` (socle sur le deck) à `Y = 23.00` |
| Orientation | yaw `180°` (façade vers `+Z`) |
| Pivot | `(34.0, 12.00, -19.0)` = centre du socle, aligné sur `Anchor_TransitAlcove` (socle `Ø9 × 0.6`) |
| Zones à laisser libres | cylindre `Ø6 × 8` centré `(34, 12.6, -19)` : la pastille de téléport de `BubbleTransitBuilder` s'y pose et doit rester cliquable ; **aucun mesh ne doit la recouvrir** |
| Surfaces GUI à prévoir | `TransitSignFace` : plan `6 × 1.6` face `+Z` à `Y = 21.4` |
| Meshes séparés | `Transit_Arch` (~2 500) · `Transit_Base` (~1 000) · `Transit_PortalNeon` (~800, mesh distinct pour matériau Neon + transparence) · `Transit_Sign` (~700) |
| Budget triangles | `5 000` |
| Matériaux | `Metal` peint (arche), `Neon` + `ForceField` (portail), composite (socle) |
| Couleurs | arche `#2E323C` · portail `#4FD8FF` (transparence `0.45`) · socle `#31353F` · enseigne `#DCEEFF` |
| Textures | `ColorMap` + `RoughnessMap` `512²` |
| Néon | disque de portail + liseré d'arche |
| Points lumineux | 1 `PointLight` cyan au centre du portail (`Range 14`, `Brightness 1.4`) |
| Collisions | `CanCollide = false` |
| Ancres fonctionnelles | `Anchor_TransitAlcove`, pastille `BubbleTransit` (générée par `BubbleTransitBuilder`) |
| Noms d'instances | `HubTransitShell` → `Arch`, `Base`, `PortalNeon`, `Sign`, `TransitSignFace` |
| Emplacement | `…CentralHubVisual.HubTransitShell` |

### 3.10 `HubSpawnMedallion` — priorité 10

| Champ | Valeur |
|---|---|
| Rôle visuel | Médaillon de spawn encastré : étoile centrale en relief, anneau mouluré, lueur au sol |
| Bounding box | `Ø18 × 0.9` (cylindrique) |
| Centre monde | `(0, 12.45, 8.0)` — encastré dans le rehaussement central du deck (`Y = 12.25`), sommet du relief à `Y = 12.90` maximum |
| Orientation | yaw `0°` |
| Pivot | `(0, 12.00, 8.0)`, aligné sur `Anchor_SpawnMedallion` |
| Zones à laisser libres | volume `12 × 5 × 12` au-dessus du médaillon (apparition des personnages) : rien au-dessus de `Y = 12.90` |
| Meshes séparés | `SpawnMedallion_Ring` (~1 200) · `SpawnMedallion_Star` (~800) · `SpawnMedallion_NeonCore` (~500) |
| Budget triangles | `2 500` |
| Matériaux | `Metal` brossé (anneau), composite sombre (fond), `Neon` (cœur) |
| Couleurs | anneau `#4A505E` · fond `#22262E` · étoile `#DCEEFF` · cœur `#4FD8FF` |
| Textures | `ColorMap` + `NormalMap` + `RoughnessMap` `512²` |
| Néon | cœur de `Ø3` + rainures de l'étoile |
| Points lumineux | 1 `PointLight` au sol (`Range 18`, `Brightness 0.8`, `#CFE8FF`) |
| Collisions | `CanCollide = false` (relief `≤ 0.9` : ne doit jamais faire trébucher) |
| Ancres fonctionnelles | `Anchor_SpawnMedallion`, `HubSpawnLocation` en `(0, 12.90, 8)` |
| Noms d'instances | `HubSpawnMedallion` → `Ring`, `Star`, `NeonCore` |
| Emplacement | `…CentralHubVisual.HubSpawnMedallion` |

### 3.11 `HubLightFixtures` — priorité 9

| Champ | Valeur |
|---|---|
| Rôle visuel | Toutes les sources lumineuses et leurs luminaires : projecteurs d'auvents, bornes basses du deck, lanternes de poteaux, lueur du médaillon, halo du portail |
| Bounding box | volume englobant `84 × 12 × 60` (module éclaté) |
| Centre monde | `(0, 18.0, 0)` (organisationnel) |
| Orientation | yaw `0°` |
| Pivot | `(0, 12.0, 0)` |
| Contenu imposé | 12 lanternes de poteaux (périmètre) · 4 projecteurs d'auvents (2 Sell, 2 Shop) · 2 projecteurs de panneaux arrière · 6 bornes basses `0.8 × 1.6 × 0.8` le long des arêtes latérales · 1 lueur de médaillon · 1 halo de portail |
| Budget triangles | `3 000` (luminaires uniquement) |
| Matériaux | `Metal` (corps), `Neon` (diffuseurs) |
| Couleurs | corps `#31353F` · diffuseur `#DCEEFF` · variantes `#B8FFD4` (Sell), `#F0C8FF` (Shop), `#FFE7B0` (classement) |
| Éclairage | budget total : **`≤ 20` sources** dont `≤ 6` `SpotLight` ; `Shadows = false` sur toutes sauf les 4 projecteurs d'auvents ; `Brightness ≤ 1.4`, `Range ≤ 18` |
| Collisions | `CanCollide = false` |
| Noms d'instances | `HubLightFixtures` → `PostLanterns`, `CanopySpots`, `BoardSpots`, `DeckBollards`, `MedallionGlow`, `PortalGlow` |
| Emplacement | `…CentralHubVisual.HubLightFixtures` |

### 3.12 `HubDecorProps` — priorité 9

| Champ | Valeur |
|---|---|
| Rôle visuel | Accessoires décoratifs : caisses et liasses de billets du Sell, objets exposés du Shop, panier au sol, plantes / bornes d'angle, chevrons du sol |
| Bounding box | pièces indépendantes, aucune plus grande que `4 × 4 × 4` |
| Centres monde | Sell : autour de `(-35 ± 3, 17.4, ±5)` · Shop : étagères en `(35.5, 15.6 / 18.4, ±6)` · panier au sol `(30, 13.25, 3.5)` · chevrons du palier `(0, 7.36, 44 / 48)` |
| Orientation | héritée du kiosque parent |
| Pivot | base de chaque prop (contact au sol) |
| Zones à laisser libres | jamais dans le volume de vente `11 × 8 × 12`, jamais dans le passage central du Shop de `6` studs, jamais à moins de `1.5` d'un `PromptAnchor` |
| Budget triangles | `8 000` pour l'ensemble (aucun prop `> 900` tris) |
| Matériaux | `Wood`, `Metal`, `Plastic` mat, `Neon` ponctuel |
| Couleurs | palette §10 uniquement, saturation modérée |
| Textures | atlas commun `1024²` `ColorMap` + `NormalMap` + `RoughnessMap` |
| Collisions | `CanCollide = false` |
| Noms d'instances | `HubDecorProps` → `SellCrates`, `SellBills`, `ShopGoods`, `ShopBasket`, `DeckPlants`, `FloorChevrons` |
| Emplacement | `…CentralHubVisual.HubDecorProps` |

## 4. Fidélité de la plateforme (critères contraignants)

1. **Base graphite foncé** : aucune surface du deck au-dessus de `#4A505E` en luminance.
   Le blanc bleuté `214,220,232` du prototype est interdit.
2. **Niveaux superposés visibles** : au minimum 4 strates (jupe, socle, dalle, nez de
   dalle) avec des retraits de `2.5` puis `0.6` et une gorge d'ombre de `0.25`.
3. **Bordures et moulures** : nez de dalle en surplomb sur tout le périmètre, y compris sur
   les 4 chanfreins ; la moulure s'interrompt proprement à l'ouverture frontale.
4. **Angles coupés ou arrondis** : les 4 chanfreins de `16.97` doivent être adoucis par un
   congé vertical de rayon `0.5` minimum ; aucune arête vive à 90° visible en silhouette.
5. **Accents cyan intégrés dans la bordure** : liseré de `0.3` maximum, encastré dans la
   gorge. Aucun aplat néon horizontal. La dalle `HubFoundationGlow` `73 × 0.6 × 49` du
   prototype doit disparaître.
6. **Centre légèrement plus élevé** : rehaussement de `+0.25` sur `Ø26` centré `(0, ·, 8)`.
7. **Ailes Sell et Shop intégrées** : jupe et moulure continues entre la dalle et les
   plateaux `24 × 1.2 × 22` ; aucun plateau posé.
8. **Escalier central frontal** : la descente reste centrée, `26` de large, alignée sur
   l'ouverture de `28`.
9. **Poteaux lumineux bas** : `4.2` de haut maximum, jamais au-dessus de la ligne de
   lecture des kiosques.
10. **Aucune grande surface blanche**, **aucune fondation cyan massive**, **aucun effet de
    plateforme flottante** : la jupe doit descendre jusqu'à `Y = 4.5` et le vide latéral de
    7 studs sous le deck doit être comblé visuellement (jupe évasée ou contreforts).

## 5. Fidélité du `SELL`

- Cadre épais gris foncé (`≥ 1.2` d'épaisseur apparente) formant un U autour de l'alcôve.
- Enseigne `SELL` **intégrée au fronton** (encastrée dans le cadre, pas posée dessus), texte
  en `SurfaceGui` sur `SellSignFace`.
- Intérieur vert : fond `#1E4B33` → `#2FA96A`, éclairé par l'intérieur.
- Comptoir présent, hauteur `4.2`, avec panneau frontal décoré.
- Alcôve **ouverte** sur le centre du hub : aucune paroi côté `+Z` local.
- Caisses / piles de billets décoratives dans `HubDecorProps` (jamais de disques néon
  flottants).
- Pad de vente **intégré au sol** : décor plat de `11 × 9` en `(-23.6, 13.5, 0)`, épaisseur
  `≤ 0.3`, avec liseré vert et pictogramme en relief léger.
- Bordures lumineuses fines uniquement.
- Profondeur réelle : au moins 3 plans de profondeur (fronton, auvent, fond) visibles depuis
  la caméra de référence.
- Interdit : gros cube noir en guise de comptoir ; enseigne posée sur un rectangle.
- La vente automatique reste autoritative : `SellZone` `11 × 8 × 12` en `(-23.6, 16.8, 0)`
  demeure une Part **invisible** générée par le code, indépendante du mesh.

## 6. Fidélité du `SHOP`

- Structure **symétrique** du Sell : même bounding box `18 × 14 × 22`, même hauteur de
  fronton, même épaisseur de cadre. L'asymétrie actuelle (`16` contre `24` de profondeur)
  doit disparaître.
- Enseigne `SHOP` intégrée au fronton, texte en `SurfaceGui` sur `ShopSignFace`.
- Alcôve ouverte, jamais une boutique dans laquelle on entre : profondeur utile `≤ 8`
  studs, passage central de `6` studs.
- 2 étagères garnies de petits objets exposés (décoratifs).
- Comptoir compact, hauteur `3.4`, en deux tronçons laissant le passage central.
- Pad / icône de panier intégré au sol en `(30, 13.25, 3.5)`, empreinte `9 × 9`,
  épaisseur `≤ 0.3`.
- Accents violets et roses (`#9664FF`, `#E65FD7`) **en liserés**, pas en volumes.
- Interdit : gros bloc noir, gros bloc rose, cubes néon en guise de marchandise.
- Le système de boutique reste fonctionnel et inchangé : `PromptAnchor_*`,
  `CameraPoint_*`, `Display_*` restent générés par `ItemShopBuilder`.

## 7. Panneau central

- Véritable module 3D : caisson de `2.0` d'épaisseur, cadre large, coins arrondis
  (rayon `≥ 1.2`), fond bleu nuit `#101A34`.
- Bordure lumineuse **discrète** : liseré en retrait, jamais un halo plein écran.
- Pieds / supports intégrés au socle `36 × 1.5 × 4` (`Y 12.00 → 13.50`).
- Proportions cibles `34 × 9.5` (rapport `3.6:1`), contre `30 × 6.4` (`4.7:1`) au
  prototype : le panneau doit gagner en hauteur pour coller à la maquette.
- **Le texte et les icônes dynamiques restent dans un `SurfaceGui`** monté sur
  `LoopPanelFace` (plan plat `30 × 7`). Rien n'est gravé ni texturé dans le mesh.

## 8. `TOP 3` et `RULES`

- Même famille de formes : cadre identique, socle identique, seule la couleur d'accent et
  l'icône changent.
- Sommet arrondi : arc de rayon `10` sur les `4` studs supérieurs.
- Base solide : socle `20 × 3 × 4` plus jambes intégrées descendant à `Y = 12.00`, plus une
  plinthe basse commune de `X = -29` à `X = +29` à `Z = -23`, hauteur `1.5`.
- Plus hauts que le panneau central : sommet à `Y = 36.00` contre `Y = 23.00` pour la
  boucle.
- Séparés mais visuellement liés (plinthe commune, même cadre, même hauteur).
- Cadre épais : `≥ 1.5` d'épaisseur apparente, contre `0.8` au prototype.
- Zone réservée aux icônes : `4 × 4` au sommet de chaque panneau (trophée pour `TOP 3`,
  presse-papiers pour `RULES`).
- Contenus dynamiques en `SurfaceGui` : `Top3Face` (rempli par `LeaderboardService`,
  `BPW_Rows = 3`) et `RulesFace`.

## 9. Bubble Transit

- Compact (`10 × 11 × 10`), placé à l'arrière-droit en `(34, ·, -19)`, derrière la ligne des
  panneaux arrière — exactement comme la maquette.
- Petite arche + portail cyan translucide + enseigne intégrée + profondeur réelle
  (arche en 2 plans, socle mouluré).
- Taille secondaire : hauteur totale `11` contre `15.5` pour les panneaux arrière et `14`
  pour les kiosques ; ne domine jamais la composition.
- Ne recouvre ni ne bloque la pastille fonctionnelle : cylindre `Ø6 × 8` centré
  `(34, 12.6, -19)` laissé totalement libre.

## 10. Palette et matériaux

| Rôle | Couleur | Hex | Emploi |
|---|---|---|---|
| Graphite foncé | `35,38,46` | `#23262E` | jupe, contremarches, volumes de fond |
| Graphite moyen | `46,50,60` | `#2E323C` | cadres de kiosques, arche transit |
| Gris métallique | `74,80,94` | `#4A505E` | moulures, nez de dalle, anneaux |
| Gris composite | `58,63,75` | `#3A3F4B` | dalle du deck, marches |
| Bleu nuit | `16,26,52` | `#101A34` | fonds de panneaux |
| Cyan lumineux | `79,216,255` | `#4FD8FF` | liserés, portail, cœur du médaillon |
| Vert Sell | `90,230,140` | `#5AE68C` | accents Sell |
| Vert Sell profond | `30,75,51` | `#1E4B33` | intérieur d'alcôve Sell |
| Magenta Shop | `230,95,215` | `#E65FD7` | accents Shop |
| Violet Shop | `150,100,255` | `#9664FF` | accents secondaires Shop |
| Or classement | `255,205,80` | `#FFCD50` | cadre et icône `TOP 3` |
| Ambre règles | `255,170,60` | `#FFAA3C` | cadre `RULES` |
| Blanc bleuté | `220,238,255` | `#DCEEFF` | diffuseurs de lumière, pictogrammes |

Interdits explicites :

- blanc pur ou quasi blanc sur de grandes surfaces (le `214,220,232` actuel du deck) ;
- cyan pur comme matériau principal (le prototype a 26 pièces cyan sur 126) ;
- couleurs sans variation (chaque grande surface doit avoir au moins 2 valeurs) ;
- gros volumes uniformes non détaillés ;
- `Plastic` / `SmoothPlastic` partout.

Matériaux attendus : métal peint mat (`Metal` + `RoughnessMap` `0.55-0.75`), pierre ou
composite sombre (`Concrete` / `Slate`, roughness `0.8`), surfaces mates dominantes,
détails métalliques brossés (roughness `0.3`, metalness `0.8`), accents `Neon` en meshes
séparés, variation de roughness de `±0.15` sur les grandes surfaces via `RoughnessMap`.

Ratio de matériaux visé sur le hub complet : `≥ 70 %` mat non émissif, `≤ 8 %` de surface
émissive (contre 44 % de pièces néon au prototype).

## 11. Textures et export

### Maps par module

| Module | ColorMap | NormalMap | RoughnessMap | MetalnessMap | Résolution | UV |
|---|---|---|---|---|---|---|
| `HubDeckShell` | oui | oui | oui | moulures seulement | `1024²` | atlas `HubStructureAtlas` partagé avec stairs/railings |
| `HubFrontStairs` | oui | oui | oui | non | `1024²` | `HubStructureAtlas` |
| `HubRailingsAndPosts` | oui | non | oui | oui | `512²` | `HubStructureAtlas` |
| `HubSellStandShell` | oui | oui | oui | oui | `1024²` | UV uniques (`HubSellAtlas`) |
| `HubShopStandShell` | oui | oui | oui | oui | `1024²` | UV uniques (`HubShopAtlas`) |
| `HubLoopPanelFrame` | oui | oui | oui | non | `1024²` | UV uniques |
| `HubTop3BoardFrame` | oui | oui | oui | oui | `1024²` | atlas `HubBoardsAtlas` |
| `HubRulesBoardFrame` | oui | oui | oui | oui | `1024²` | `HubBoardsAtlas` |
| `HubTransitShell` | oui | oui | oui | non | `512²` | UV uniques |
| `HubSpawnMedallion` | oui | oui | oui | oui | `512²` | UV uniques |
| `HubLightFixtures` | oui | non | oui | non | `512²` | atlas commun |
| `HubDecorProps` | oui | oui | oui | non | `1024²` | atlas `HubPropsAtlas` |

Règles :

- `1024²` est le maximum utile (Roblox redimensionne au-delà) ;
- tous les éléments **émissifs sont exportés comme meshes séparés** (matériau `Neon`
  appliqué dans Studio, jamais une texture émissive) ;
- les surfaces GUI (`*Face`) sont des plans nus, sans texture ni relief ;
- pas de `SurfaceAppearance` sur les meshes `Neon` ;
- budget total du pack : `≤ 12` textures, `≤ 90 000` triangles.

### Blender → Roblox

1. Scène en unités métriques, `Unit Scale = 1.0`, **1 unité Blender = 1 stud**.
2. Modéliser à l'origine, face avant vers `-Y` Blender (qui devient `-Z` Roblox après
   conversion d'axes), haut vers `+Z` Blender.
3. Appliquer toutes les échelles (`Ctrl+A → Scale`) et toutes les rotations avant export.
4. Origine de chaque objet placée au pivot demandé (`Object → Set Origin`).
5. Trianguler explicitement (modificateur `Triangulate`, `Quad Method: Fixed`) pour éviter
   toute retriangulation surprise à l'import.
6. Normales recalculées vers l'extérieur, pas de faces doubles, pas de géométrie interne.
7. Un seul UV set par mesh, nommé `UVMap`, sans chevauchement (hors éléments symétriques
   volontairement superposés).
8. Inclure le cube témoin `ScaleCheck_10` dans le premier export de chaque module.

Export FBX (réglages de départ) : `Forward: -Z Forward`, `Up: Y Up`,
`Apply Scalings: FBX Units Scale`, `Apply Transform` activé, `Mesh` + `Empty` uniquement,
`Tangent Space` exporté, animations désactivées.

Export OBJ : `Forward: -Z`, `Up: Y`, `Triangulated Mesh` activé, écriture des normales et
des UV, `Objects as OBJ Groups`.

### FBX ou OBJ, module par module

| Module | Format | Raison |
|---|---|---|
| `HubDeckShell` | **FBX** | 4 meshes + hiérarchie + pivots à conserver |
| `HubFrontStairs` | **FBX** | 3 meshes, pivot décalé sur l'arête haute |
| `HubRailingsAndPosts` | **FBX** | nombreuses instances, hiérarchie utile |
| `HubSellStandShell` | **FBX** | multi-mesh + plans GUI nommés |
| `HubShopStandShell` | **FBX** | multi-mesh + plans GUI nommés |
| `HubLoopPanelFrame` | **FBX** | cadre + néon + plan GUI |
| `HubTop3BoardFrame` | **FBX** | cadre + socle + icône |
| `HubRulesBoardFrame` | **FBX** | idem |
| `HubTransitShell` | **FBX** | 4 meshes dont un translucide |
| `HubSpawnMedallion` | **OBJ** possible | 3 meshes simples, pivot centré ; FBX reste préférable si les 3 doivent rester séparés |
| `HubLightFixtures` | **OBJ** | luminaires simples, réassemblés dans Studio |
| `HubDecorProps` | **OBJ** par prop | props indépendants, un fichier par prop, pivot en base |

Règle générale : **FBX dès qu'il y a plusieurs meshes, une hiérarchie, un pivot non centré
ou des matériaux PBR à mapper**. OBJ uniquement pour un prop isolé sans hiérarchie.

### Import dans Studio

1. `Avatar → 3D Importer`, sélectionner le FBX.
2. Vérifier `ScaleCheck_10` : `Size` doit valoir `10, 10, 10`. Sinon corriger l'échelle
   d'import (et non le modèle) puis réimporter.
3. `Anchored = true`, `CanCollide = false`, `CollisionFidelity = Box` sur tous les meshes
   visuels ; `CastShadow` selon le module.
4. Renommer strictement selon la colonne « noms d'instances ».
5. Poser le `Model` sous `Workspace.StudioDecoration.CentralHubVisual`.
6. Aligner le `WorldPivot` du `Model` sur l'ancre correspondante
   (`CentralHub.HubAnchors.Anchor_<Module>`, attributs `TargetSize` et `YawDegrees`).
7. Créer les `SurfaceAppearance` avec les 4 maps, `AlphaMode = Overlay` uniquement si
   nécessaire.
8. Supprimer `ScaleCheck_10`.

## 12. Pipeline Roblox

```text
Workspace
└── StudioDecoration
    └── CentralHubVisual
        ├── HubDeckShell
        ├── HubFrontStairs
        ├── HubRailingsAndPosts
        ├── HubSellStandShell
        ├── HubShopStandShell
        ├── HubLoopPanelFrame
        ├── HubTop3BoardFrame
        ├── HubRulesBoardFrame
        ├── HubTransitShell
        ├── HubSpawnMedallion
        ├── HubLightFixtures
        ├── HubDecorProps
        └── ValidationCameras
            ├── CentralHubConcept2ReferenceCamera
            ├── ValidationCam_Spawn
            ├── ValidationCam_FromBubbles
            ├── ValidationCam_Back
            ├── ValidationCam_Top
            └── ValidationCam_Mobile
```

Règles de pipeline :

- chaque module est un `Model` **indépendant et remplaçable** ; jamais de regroupement en un
  seul mesh monolithique ;
- le nom du `Model` est la clé lue par le pipeline existant
  (`GameConfig.Hub.Visual.VisualFolder` = `CentralHubVisual`) ;
- l'activation se fait module par module via `GameConfig.Hub.Assets.<Clé>.UseImported`, ce
  qui permet d'intégrer les assets progressivement sans jamais casser le hub ;
- la correspondance clé d'asset ↔ nom de modèle sera mise à jour lors de l'intégration
  (voir §15 : les noms actuels sont `HubDeck`, `HubSellStand`, `HubShopStand`, `HubLoopPanel`,
  `HubTopBoard`, `HubRulesBoard`, `HubTransitAlcove`, `HubStairs`, `HubSpawnMedallion`,
  `HubDeckRim`) ;
- aucun module importé ne doit être parenté sous `Workspace.BubblePopWorld.CentralHub` :
  ce dossier est reconstruit à chaque démarrage.

## 13. Gameplay strictement séparé du visuel

Les éléments suivants restent générés et gérés par le code, indépendants des meshes, et ne
doivent **jamais** être dupliqués, remplacés ou recouverts par un asset :

| Élément | Source | Emplacement runtime |
|---|---|---|
| `HubSpawnLocation` (`SpawnLocation`) | `CentralHubBuilder.ensureSpawn` | `CentralHub.HubFunction` |
| `HubSpawnMarker` | idem | `CentralHub.HubFunction` |
| `SellZone` (`11 × 8 × 12`, invisible) | `CentralHubBuilder.buildSellFunctional` | `CentralHub.HubFunction` |
| Pastille Bubble Transit + arrivées | `BubbleTransitBuilder` / `TravelConfig` | `Workspace` |
| `ProximityPrompt` de boutique (`PromptAnchor_*`) | `ItemShopBuilder` | `Workspace.ItemShop` |
| `CameraPoint_Skills/Items/Cosmetics` | `ItemShopBuilder` | `Workspace.ItemShop` |
| `Display_*` + `FocusAnchor` | `ItemShopBuilder` | `Workspace.ItemShop` |
| Volumes de collision et sol jouable | `CentralHubBuilder` (Parts invisibles) | `CentralHub.HubStructure` |
| Ancres d'import (`Anchor_*`) | `CentralHubBuilder.buildAnchors` | `CentralHub.HubAnchors` |
| `SurfaceGui` de la boucle, des règles, du classement, de la valeur du sac | `CentralHubBuilder` / `LeaderboardService` | montés sur les surfaces `*Face` |
| Données de classement (`BPW_Rows = 3`) | `LeaderboardService` | attribut sur la surface |
| Textes localisés (`AutoLocalize`) | `LocalizationStrings` / `LocalizationUtil` | `TextLabel` des `SurfaceGui` |
| Logique d'achat / vente / économie | `ShopService`, `BackpackService` | serveur |

Contraintes :

- **aucun script dans les meshes** (ni `Script`, ni `ModuleScript`, ni `LocalScript`) ;
- aucun `SurfaceGui` livré dans les meshes : seulement des plans nus nommés `*Face` ;
- aucun attribut de gameplay sur les meshes ;
- les meshes sont `Anchored = true` et `CanCollide = false` par défaut.

## 14. Critères d'acceptation artistique (checklist bloquante)

Le hub est **refusé** tant qu'au moins un de ces points est vrai :

1. la silhouette frontale depuis `CentralHubConcept2ReferenceCamera` s'écarte visiblement
   de la maquette (base sombre, deux tours arrondies à l'arrière, deux frontons de
   kiosques, arche de transit à droite) ;
2. la plateforme est encore blanche, quasi blanche ou cyan ;
3. le `SELL` se lit comme un gros bloc ;
4. le `SHOP` se lit comme un gros bloc ;
5. les cadres sont plats (épaisseur apparente `< 1.2`) ;
6. les panneaux manquent de profondeur (moins de 3 plans lisibles) ;
7. les proportions gauche/droite sont asymétriques sans raison (Sell et Shop doivent
   partager la même bounding box `18 × 14 × 22`) ;
8. la plateforme semble flotter (vide visible sous la dalle) ;
9. les marches ne rejoignent pas proprement les bulles (le palier doit toucher `Z = 51.3`
   au niveau `Y = 7.35`) ;
10. aucune source lumineuse n'est présente (minimum : 12 lanternes, 4 projecteurs
    d'auvents, 2 projecteurs de panneaux) ;
11. les matériaux paraissent uniformes (aucune variation de roughness, `Plastic` dominant) ;
12. le rendu ressemble encore à un prototype de Parts (arêtes vives à 90°, aplats néon,
    volumes non détaillés) ;
13. plus de 8 % de la surface visible est émissive ;
14. un mesh contient un script, un `SurfaceGui` ou recouvre une zone fonctionnelle.

### Validation par captures (obligatoire à chaque livraison)

| Capture | Caméra | Contrôle |
|---|---|---|
| Vue de référence frontale | `CentralHubConcept2ReferenceCamera` | comparaison côte à côte avec la maquette |
| Vue joueur au spawn | `ValidationCam_Spawn` | lisibilité de la boucle, Sell à gauche, Shop à droite |
| Vue depuis les bulles | `ValidationCam_FromBubbles` | jonction escalier / bulles, absence d'effet flottant |
| Vue arrière | `ValidationCam_Back` | cohérence des faces non visibles dans la maquette |
| Vue de dessus | `ValidationCam_Top` | symétrie stricte, alignements, emprise octogonale |
| Vue mobile | `ValidationCam_Mobile` | lisibilité en `20:9` |

Chaque capture est archivée dans `docs/superpowers/specs/renders/2026-08-01-hub-<vue>.png`.

## 15. Points à confirmer avant production

1. **Capture Studio** : seule la maquette `Concept 2` était jointe à la demande. La
   comparaison de la §1 est donc établie sur la géométrie **réellement générée** (inventaire
   mesuré depuis `CentralHubBuilder` + `HubLayout`). À confirmer : aucune modification
   manuelle du hub n'a été faite dans le fichier Studio.
2. **Panneau de boucle** : la fidélité demande `34 × 9.5 × 2.0` au lieu de `30 × 6.4 × 0.8`
   → nécessitera `GameConfig.Hub.LoopPanel.Size` et `PlinthHeight` (changement de config à
   valider, pas fait dans cette étape).
3. **Panneaux arrière** : `20 × 15.5` au lieu de `17 × 13` → `GameConfig.Hub.Boards.Size`.
4. **Symétrie des kiosques** : le Shop passe de `16 × 9 × 22` à `18 × 14 × 22` et le Sell de
   `24 × 8.2 × 22` à `18 × 14 × 22` → `GameConfig.Hub.Shop` et `GameConfig.Hub.Sell`.
   Impact à vérifier sur `ItemShopBuilder` (ancres de prompts) et sur `HubLayoutTests`.
5. **Palette** : la nouvelle palette graphite remplace `GameConfig.Hub.Colors`. À confirmer
   avant de l'appliquer, car le fallback prototype utilise les mêmes couleurs.
6. **Bubble Transit** : la pastille elle-même est produite par `BubbleTransitBuilder`
   (module partagé avec les autres zones). Confirmer si elle doit aussi être remodelée ou si
   seule l'arche du hub est concernée.
7. **Budget performance cible** : `90 000` triangles et `≤ 20` lumières supposent une cible
   PC/console + mobile récent. À confirmer si le mobile bas de gamme doit être couvert
   (auquel cas : `≤ 55 000` triangles, `≤ 10` lumières, `Shadows = false` partout).
8. **Orientation du spawn** : le regard `-Z` (face aux panneaux) reste l'arbitrage documenté
   dans le plan du 2026-08-01. Si la production des assets suppose l'inverse, le trancher
   avant modélisation des faces arrière.

## 16. Ordre de production recommandé

1. `HubDeckShell` — détermine la lecture générale et sert de référence de matériaux.
2. `HubSellStandShell`
3. `HubShopStandShell`
4. `HubLoopPanelFrame`
5. `HubTop3BoardFrame`
6. `HubRulesBoardFrame`
7. `HubFrontStairs`
8. `HubTransitShell`
9. `HubLightFixtures` + `HubRailingsAndPosts` + `HubDecorProps`
10. `HubSpawnMedallion`

La plateforme, le Sell et le Shop déterminent l'essentiel de la qualité perçue : leur
validation depuis `CentralHubConcept2ReferenceCamera` conditionne le lancement des modules
suivants.

## 17. Statut du système actuel

Le hub généré par script **n'est pas supprimé**. Il conserve les rôles suivants :

- architecture et source unique des positions (`HubLayout`) ;
- gameplay, repères, collisions, zones fonctionnelles ;
- solution de debug et de secours si un asset manque.

Action à appliquer **à l'étape d'intégration** (pas dans cette étape, aucun script modifié
ici) : marquer explicitement la géométrie générée comme
`PrototypeVisualFallback` — attribut `BPW_PrototypeVisualFallback = true` sur les pièces
visuelles générées, et renommage du commentaire de `CentralHubBuilder` pour indiquer que le
rendu final approuvé provient de `CentralHubVisual`.
