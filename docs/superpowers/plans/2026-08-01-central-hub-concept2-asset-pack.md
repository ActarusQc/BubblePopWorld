# Plan de production et d'intégration — Asset pack du hub central « Concept 2 »

Spécification de référence :
`docs/superpowers/specs/2026-08-01-central-hub-concept2-asset-pack-design.md`.

Statut de départ : le hub généré en Parts (126 pièces visibles) est un **prototype
fonctionnel rejeté visuellement**. Il reste disponible comme `PrototypeVisualFallback`
(architecture, ancres, collisions, gameplay, debug) et n'est plus le rendu final.

Ce document est un **plan**. Il ne produit aucun asset et ne modifie aucun script de
production. Chaque phase se termine par un point d'arrêt : rien ne démarre à la phase
suivante avant validation visuelle explicite.

## Décisions approuvées intégrées à ce plan

| Sujet | Décision |
|---|---|
| Dimensions | celles de la spec, approuvées (voir tableau §Transformations) |
| Palette | palette graphite de la spec ; cyan / vert / violet = accents, éclairage et identification fonctionnelle uniquement |
| Bubble Transit | le visuel complet (cylindre + anneau générés) est remplacé par `HubTransitShell` ; le pad fonctionnel devient invisible sous le modèle |
| Performance | **mobile-first** : `55 000` triangles pour tout le hub visible, `10 000` par MeshPart, `10` vraies sources lumineuses, textures `1024²`, atlas partagés, aucune texture 4K, aucune animation permanente coûteuse |
| LOD PC | variante secondaire optionnelle ; le modèle mobile doit déjà être proche de la maquette |
| Orientation | `-Z` = face avant du module, `+Y` = haut ; validation Studio de l'orientation réelle **avant** de détailler les faces arrière |
| Caméras | aucune caméra joueur forcée ; les caméras de validation sont des repères Studio inertes |

## Partage des responsabilités

- **Code** : ancres, positions, collisions invisibles, zones fonctionnelles, vente
  automatique, boutique, prompts, spawn, leaderboard dynamique, localisation, Bubble
  Transit, `SurfaceGui`, tests, fallback prototype.
- **Assets importés** : silhouettes, moulures, chanfreins, cadres, alcôves, comptoirs,
  étagères, accessoires, détails, matériaux, textures, pièces `Neon`, éclairages décoratifs.

## Transformations monde approuvées (source : ancres réelles)

Repère : `+Z` avant (vers les bulles), `-X` = `SELL`, `+X` = `SHOP`, deck à `Y = 12.00`,
surface de marche sur les bulles à `Y = 7.35`.

| Module | Bounding box | Centre monde | Pivot d'import | Yaw | Ancre |
|---|---|---|---|---|---|
| `HubDeckShell` | `84 × 7.5 × 60` | `(0, 8.25, 0)` | `(0, 8.25, 0)` | `0°` | `Anchor_Deck` |
| `HubFrontStairs` | `26 × 4.65 × 20.8` | `(0, 9.675, 40.9)` | `(0, 12.00, 30.5)` | `0°` | `Anchor_Stairs`, `Anchor_StairsLanding` |
| `HubRailingsAndPosts` | `84 × 4.2 × 60` (coque) | `(0, 14.10, 0)` | `(0, 12.00, 0)` | `0°` | périmètre du deck |
| `HubSellStandShell` | `18 × 14 × 22` | `(-33.0, 20.20, 0)` | `(-30.0, 13.20, 0)` | `90°` | `Anchor_SellStand` |
| `HubShopStandShell` | `18 × 14 × 22` | `(33.0, 20.20, 0)` | `(30.0, 13.20, 0)` | `270°` | `Anchor_ShopStand` |
| `HubLoopPanelFrame` | `34 × 9.5 × 2.0` | `(0, 18.25, -4.0)` | `(0, 13.50, -4.0)` | `180°` | `Anchor_LoopPanel` |
| `HubTop3BoardFrame` | `20 × 15.5 × 2.0` + socle `20 × 3 × 4` | cadre `(-19, 28.25, -23)` · socle `(-19, 19.00, -23)` | `(-19, 20.50, -23)` | `180°` | `Anchor_TopBoard` |
| `HubRulesBoardFrame` | `20 × 15.5 × 2.0` + socle `20 × 3 × 4` | cadre `(19, 28.25, -23)` · socle `(19, 19.00, -23)` | `(19, 20.50, -23)` | `180°` | `Anchor_RulesBoard` |
| `HubTransitShell` | `10 × 11 × 10` | `(34, 17.50, -19)` | `(34, 12.00, -19)` | `180°` | `Anchor_TransitAlcove` |
| `HubSpawnMedallion` | `⌀18 × 0.9` | `(0, 12.45, 8)` | `(0, 12.00, 8)` | `0°` | `Anchor_SpawnMedallion` |
| `HubLightFixtures` | module éclaté | `(0, 18.0, 0)` | `(0, 12.00, 0)` | `0°` | — |
| `HubDecorProps` | props `≤ 4³` | par prop | base du prop | héritée | — |

Précision apportée par ce plan (à reporter dans la spec lors de l'intégration) :
`HubFrontStairs` occupe `Y 7.35 → 12.00` (hauteur `4.65`) et `Z 30.5 → 51.3`
(profondeur `20.8`), le dessous des marches étant porté par la jupe de `HubDeckShell`.

## Budget mobile-first réparti

| Module | Triangles | Meshes | Vraies lumières |
|---|---|---|---|
| `HubDeckShell` | `13 000` | 4 | 0 |
| `HubSellStandShell` | `8 000` | 4 | 2 (spots d'auvent) |
| `HubShopStandShell` | `8 000` | 4 | 2 (spots d'auvent) |
| `HubLoopPanelFrame` | `2 500` | 2 | 0 |
| `HubTop3BoardFrame` | `2 500` | 3 | 1 (spot de panneau) |
| `HubRulesBoardFrame` | `2 500` | 3 | 1 (spot de panneau) |
| `HubFrontStairs` | `4 000` | 3 | 2 (bas de descente) |
| `HubTransitShell` | `3 500` | 4 | 1 (portail) |
| `HubRailingsAndPosts` | `4 000` | 3 | 0 (Neon seul) |
| `HubSpawnMedallion` | `1 500` | 3 | 1 (lueur au sol) |
| `HubLightFixtures` | `1 500` | 6 | 0 (héberge les 10 sources ci-dessus) |
| `HubDecorProps` | `4 000` | props séparés | 0 |
| **Total** | **`55 000`** | **39** | **`10`** |

Toutes les autres sources de lumière apparentes sont obtenues par `Neon`, textures
émissives ou pièces lumineuses sans `PointLight` / `SpotLight`. `Shadows = false` sur les
10 sources en profil mobile ; les ombres ne sont activées que dans la variante LOD PC.

## Vue d'ensemble des phases

| Phase | Objet | Point d'arrêt |
|---|---|---|
| 0 | Référence et état initial | captures du prototype archivées |
| 1 | Contrat d'import + tests de garde | suite de tests verte, aucun script de production modifié |
| 2 | `HubDeckShell` | validation visuelle obligatoire |
| 3 | `HubSellStandShell` | validation visuelle obligatoire |
| 4 | `HubShopStandShell` | validation visuelle obligatoire |
| 5 | Panneaux (`Loop`, `Top3`, `Rules`) | validation visuelle obligatoire |
| 6 | Navigation (`Stairs`, `Railings`, `Transit`, `Medallion`) | validation visuelle + circulation |
| 7 | Lumières et accessoires | validation visuelle + budget lumières |
| 8 | Intégration finale (seule phase qui modifie la production) | recette fonctionnelle complète |

---

## Phase 0 — Référence et état initial

Aucun script de production modifié.

- **P0.1** Enregistrer l'état du dépôt : `git status`, `git rev-parse HEAD`, et lister les
  modifications non liées déjà présentes (hub central en cours, summer-decor, onboarding).
  Consigner ce relevé en tête de la section « journal » de ce plan. Aucune de ces
  modifications ne doit être annulée, déplacée ou committée par les phases suivantes.
- **P0.2** Créer `docs/superpowers/specs/renders/` et y archiver la maquette de référence
  sous `2026-08-01-concept2-reference.png` (source de vérité artistique versionnée).
- **P0.3** Créer le plugin Studio `studio-plugins/HubValidationCameras.plugin.lua`
  (outil d'édition uniquement, jamais chargé en Play) qui :
  crée `Workspace.StudioDecoration.CentralHubVisual.ValidationCameras` s'il manque ;
  y pose 7 `Part` repères inertes nommés `CentralHubConcept2ReferenceCamera`,
  `ValidationCam_Spawn`, `ValidationCam_FromBubbles`, `ValidationCam_Back`,
  `ValidationCam_Top`, `ValidationCam_Side` (position `(120, 30, 0)`, cible `(0, 16, 0)`,
  `FOV 40`), `ValidationCam_Mobile` ; expose un bouton « Aller à la vue » qui
  déplace la caméra Studio (`workspace.CurrentCamera`) sur le repère sélectionné.
  Contrainte : le plugin ne touche jamais `Players`, ni `StarterPlayer`, ni la caméra runtime.
- **P0.4** Vérifier les valeurs de `CentralHubConcept2ReferenceCamera` :
  position `(0, 74, 124)`, cible `(0, 15, 4)`, `FieldOfView = 36`, rapport `16:9`,
  rendu `1920 × 1080`.
- **P0.5** Capturer le prototype actuel depuis les 7 vues et archiver dans
  `docs/superpowers/specs/renders/2026-08-01-prototype-<vue>.png` : ce sont les images
  « avant » de toutes les comparaisons ultérieures.
- **P0.6** Inventorier les ancres réelles : exécuter `python tools\run_central_hub_tests.py`
  et coller la fiche de la section 10 dans `docs/superpowers/specs/renders/anchors.txt`.
  Vérifier que les 12 ancres attendues existent dans `CentralHub.HubAnchors`.
- **P0.7** Confirmer les transformations monde de chaque module contre le tableau
  ci-dessus ; signaler tout écart avant de modéliser (aucune cote ne doit être devinée en
  phase 2+).

Commit : `docs(hub): reference camera plugin and prototype baseline captures`

## Phase 1 — Contrat d'import des assets

Objectif : rendre l'import **impossible à casser**. Un asset mal nommé, mal dimensionné ou
mal orienté doit être refusé avec un avertissement clair et laisser le fallback en place.
Fichiers nouveaux uniquement ; aucun module de production ne les consomme avant la phase 8.

- **P1.1** Créer `src/Shared/HubAssetContract.lua` (module pur, sans dépendance runtime) :
  table des 12 modules avec `ModelName`, `AssetKey`, `TargetSize`, `Center`, `YawDegrees`,
  `PivotOffset`, `RequiredChildren`, `RequiredFaces`, `MaxTriangles`, `AllowedMaterials`.
- **P1.2** Définir les attributs obligatoires portés par chaque `Model` importé :
  `BPW_HubAsset = true`, `BPW_HubAssetKey = "<clé>"`, `BPW_AssetVersion = <entier>`,
  `BPW_AuthoredSize = Vector3`, `BPW_AuthoredYaw = <degrés>`.
- **P1.3** Définir le validateur `HubAssetContract.Validate(model)` : nom exact, attributs
  présents, bounding box dans une tolérance de `±0.5` stud sur chaque axe, yaw à `±1°`,
  pivot à `±0.25` stud de l'ancre, présence des enfants et des surfaces `*Face` requis,
  absence de `Script` / `LocalScript` / `ModuleScript` / `SurfaceGui`, aucun mesh
  `CanCollide = true` non déclaré.
- **P1.4** Définir les comportements :
  *asset absent* → le code génère la forme prototype, aucun avertissement ;
  *asset présent mais `UseImported = false`* → prototype conservé, information en Output ;
  *asset présent et valide* → prototype non généré, repères fonctionnels conservés ;
  *asset présent et invalide* → **prototype conservé**, avertissement unique et explicite
  (`[HubAssetContract] <Model> refusé : <raison>`), le hub reste jouable.
- **P1.5** Spécifier le marquage `PrototypeVisualFallback` (appliqué en phase 8) :
  attribut `BPW_PrototypeVisualFallback = true` sur chaque pièce visuelle générée, et
  dossier `CentralHub.HubStructure` documenté comme fallback, jamais comme rendu final.
- **P1.6** Créer les tests : `src/Shared/HubAssetContractTests.lua` +
  harnais `tools/test_hub_asset_contract.lua` + runner `tools/run_hub_asset_tests.py`.
  Cas couverts : nom correct/incorrect, bbox hors tolérance, yaw inversé (`0°` au lieu de
  `180°`), pivot décalé, surface `*Face` manquante, script interdit présent, `SurfaceGui`
  livré dans le mesh, collision non déclarée, module absent, double import.
- **P1.7** Revue du contrat : vérifier que les 12 fiches de modélisation des phases 2 à 7
  sont dérivables du contrat sans information manquante.

Commit : `feat(hub): hub asset import contract and guard tests`

---

## Phase 2 — `HubDeckShell` (priorité 1)

- **P2.1 Fiche de modélisation.** Octogone `84 × 60`, chanfreins de `12` de jambe
  (arêtes de `16.97` à `±45°`, centres `(±36, ·, ±24)`), hauteur totale `7.5`
  (`Y 4.50 → 12.00`). Quatre strates obligatoires : jupe `4.50 → 8.20` évasée vers le bas
  (aucun vide latéral, aucun effet de flottement), socle `8.20 → 10.00` rentré de `2.5`,
  dalle `10.00 → 12.00`, nez de dalle en surplomb de `0.6` avec gorge d'ombre de `0.25`.
  Congé vertical de rayon `≥ 0.5` sur les 8 arêtes verticales.
- **P2.2 Décomposition en MeshParts.** `Base` (jupe + socle + dalle, `6 000`),
  `Moulding` (nez, gorges, moulures, `4 000`), `Wings` (2 ailes, `2 000`),
  `NeonTrim` (liserés cyan, `1 000`). Total `13 000`, aucun mesh au-dessus de `10 000`.
- **P2.3 Matériaux et couleurs.** Jupe `Slate` `#23262E`, socle `Metal` mat `#31353F`,
  dalle composite `#3A3F4B`, nez `#4A505E`, liserés `Neon` `#4FD8FF`. Aucune surface
  au-dessus de `#4A505E` en luminance ; interdiction formelle du blanc bleuté actuel.
- **P2.4 Accents Neon.** Liseré de `0.3` maximum encastré dans la gorge, sur tout le
  périmètre **sauf l'ouverture frontale**. Aucun aplat horizontal : la dalle néon
  `73 × 0.6 × 49` du prototype disparaît définitivement.
- **P2.5 Fondation.** Jupe pleine descendant à `Y = 4.50`, avec contreforts sous les
  chanfreins ; le surplomb de 7 studs du prototype doit être comblé visuellement.
- **P2.6 Ailes Sell et Shop.** Plateaux `24 × 1.2 × 22` centrés `(±30, 12.60, 0)`,
  dessus `Y = 13.20`, raccordés à la dalle par une jupe et une moulure **continues**.
- **P2.7 Zones à laisser libres.** Ouverture frontale `28` de large à `Z = +30` ;
  disque `⌀18` en `(0, ·, 8)` ; empreinte `11 × 9` en `(-23.6, ·, 0)` ;
  empreinte `9 × 9` en `(30, ·, 3.5)` ; disque `⌀9` en `(34, ·, -19)`.
- **P2.8 Emplacement de l'escalier et raccord aux bulles.** Réservation `26` de large
  centrée `X = 0`, de `Z = 30` à `Z = 51.3` ; rehaussement central `+0.25` sur `⌀26`
  centré `(0, ·, 8)`.
- **P2.9 Textures.** `ColorMap` + `NormalMap` + `RoughnessMap` `1024²`,
  `MetalnessMap` sur `Moulding` uniquement, atlas `HubStructureAtlas` partagé avec
  `HubFrontStairs` et `HubRailingsAndPosts`.
- **P2.10 Export et import.** FBX, cube témoin `ScaleCheck_10`, contrôle du pivot
  `(0, 8.25, 0)`, `Anchored = true`, `CanCollide = false`, `CollisionFidelity = Box`,
  `CastShadow = true` sur `Base` et `Moulding` uniquement.
- **P2.11 Positionnement.** `Model` sous `CentralHubVisual`, `WorldPivot` aligné sur
  `Anchor_Deck` (`TargetSize`, `YawDegrees`), validation par
  `HubAssetContract.Validate`.
- **P2.12 Comparaison et point d'arrêt.** 6 captures + comparaison côte à côte avec la
  maquette depuis `CentralHubConcept2ReferenceCamera`. **Le Sell ne démarre pas avant
  approbation du Deck.**

Commit : `assets(hub): deck shell model, textures and import sheet`

## Phase 3 — `HubSellStandShell` (priorité 2)

- **P3.1 Coque extérieure.** Cadre épais en U (`≥ 1.2` d'épaisseur apparente),
  bbox `18 × 14 × 22`, façade ouverte vers `+Z` local (vers le centre du hub), auvent
  mouluré, fronton. Trois plans de profondeur minimum lisibles depuis la caméra de
  référence.
- **P3.2 Enseigne.** Fronton avec logement d'enseigne **encastré** (jamais posé), plan
  `SellSignFace` de `13 × 3` à `y = 11.8` local pour le `SurfaceGui` du texte.
- **P3.3 Comptoir.** Hauteur `4.2`, panneau frontal décoré, centré `z = -3` local ;
  mesh `Counter` séparé.
- **P3.4 Alcôve et étagères.** Fond `z = -8` local, intérieur vert
  `#1E4B33 → #2FA96A`, 1 étagère basse, éclairé de l'intérieur.
- **P3.5 Billets et caisses décoratifs.** Meshes séparés (`SellCrates`, `SellBills`)
  livrés en phase 7 dans `HubDecorProps` ; les disques néon flottants du prototype sont
  supprimés.
- **P3.6 Pièces Neon.** Liseré de cadre `0.25`, bandeau sous auvent, halo derrière
  l'enseigne. Mesh `NeonTrim` distinct.
- **P3.7 Surfaces de texte.** `SellSignFace` et `SellValueFace` (`7 × 3` à `y = 5.8`) :
  plans strictement plats, sans relief ni texture, sans `SurfaceGui` livré.
- **P3.8 Zone fonctionnelle invisible.** Volume de vente `11 × 8 × 12` centré
  `(-23.6, 16.8, 0)` : aucun mesh à l'intérieur. Pad au sol `11 × 9` en
  `(-23.6, 13.5, 0)`, décor plat d'épaisseur `≤ 0.3`.
- **P3.9 Collision.** `CanCollide = false` sur tout le module ; `Counter` en
  `CollisionFidelity = Box` uniquement si l'on décide de bloquer le comptoir (option, à
  trancher au point d'arrêt).
- **P3.10 Décor sans script.** Aucun script, aucun attribut de gameplay, aucun
  `SurfaceGui` dans le module.
- **P3.11 Export, import, validation.** FBX, budget `8 000` triangles, 4 meshes,
  atlas `HubSellAtlas` `1024²` (`ColorMap`, `NormalMap`, `RoughnessMap`, `MetalnessMap`).
- **P3.12 Point d'arrêt Studio.** 6 captures + comparaison. Refus si le kiosque se lit
  comme un bloc ou si l'alcôve paraît vide.

Commit : `assets(hub): sell stand shell model and textures`

## Phase 4 — `HubShopStandShell` (priorité 3)

- **P4.1 Coque symétrique.** Même bbox `18 × 14 × 22`, même épaisseur de cadre, même
  hauteur de fronton que le Sell : la symétrie gauche/droite est un critère bloquant.
- **P4.2 Enseigne.** `ShopSignFace` `13 × 3` à `y = 12.2` local, logement encastré.
- **P4.3 Alcôve ouverte.** Profondeur utile `≤ 8` studs, **passage central de `6` studs
  libre sur toute la profondeur** : jamais une boutique dans laquelle on entre.
- **P4.4 Étagères.** 2 niveaux à `y = 2.4` et `y = 5.2` local, adossés au fond
  (`z = -7.5`).
- **P4.5 Objets décoratifs distincts.** Objets exposés variés (coffres, fioles, sacs),
  visuellement différents des props du Sell, livrés en phase 7 (`ShopGoods`). Les cubes
  néon `1.5³` du prototype sont supprimés.
- **P4.6 Comptoir.** Hauteur `3.4`, deux tronçons laissant le passage central, mesh
  `Counter` séparé.
- **P4.7 Accents magenta / violet.** `#E65FD7` et `#9664FF` en liserés et halos
  uniquement ; interdiction du volume magenta plein.
- **P4.8 Surfaces de texte.** `ShopSignFace` + `DisplaySkillsFace`, `DisplayItemsFace`,
  `DisplayCosmeticsFace` (`3.4 × 4` à `y = 4.6`), alignées sur les `Display_*` générés.
- **P4.9 Zones interactives indépendantes.** Cylindre `⌀3` libre autour de chaque
  `PromptAnchor_*`, empreinte `9 × 9` du pad panier en `(30, 13.25, 3.5)`.
- **P4.10 Export, import, validation.** FBX, `8 000` triangles, 4 meshes, atlas
  `HubShopAtlas` `1024²`.
- **P4.11 Point d'arrêt Studio.** 6 captures + comparaison, plus contrôle explicite de la
  symétrie Sell/Shop en vue de dessus.

Commit : `assets(hub): shop stand shell model and textures`

## Phase 5 — Panneaux

Trois modèles **séparés**, jamais fusionnés. Contenu 100 % dynamique en `SurfaceGui`.

- **P5.1 `HubLoopPanelFrame` — modélisation.** Caisson `34 × 9.5 × 2.0`, cadre large,
  coins arrondis (rayon `≥ 1.2`), fond `#101A34`, liseré cyan discret en retrait de `0.4`,
  socle mouluré `36 × 1.5 × 4` (`Y 12.00 → 13.50`) et 2 jambes obliques au dos.
- **P5.2 `HubLoopPanelFrame` — surface d'affichage.** `LoopPanelFace` : plan strictement
  plat `30 × 7`, centré `(0, 18.25, -3.0)`, normale `+Z`. Aucun texte gravé ni texturé.
- **P5.3 `HubTop3BoardFrame` — modélisation.** Cadre `20 × 15.5 × 2.0`, sommet arrondi
  (arc de rayon `10` sur les `4` studs supérieurs), socle `20 × 3 × 4` plus jambes
  intégrées jusqu'à `Y = 12.00`, logement d'icône trophée `4 × 4` au sommet.
- **P5.4 `HubTop3BoardFrame` — surface.** `Top3Face` : plan plat `17 × 11.5` centré
  `(-19, 27.5, -22.0)`, normale `+Z` ; l'instance cible du `LeaderboardService` conserve le
  nom `GlobalLeaderboardBoard`.
- **P5.5 `HubRulesBoardFrame` — modélisation.** Miroir du Top 3 sur `X`, accent ambre
  `#FFAA3C`, logement d'icône presse-papiers.
- **P5.6 `HubRulesBoardFrame` — surface.** `RulesFace` : plan plat `17 × 11.5` centré
  `(19, 27.5, -22.0)`, normale `+Z`.
- **P5.7 Lien visuel.** Plinthe basse commune de `1.5` de haut, de `X = -29` à `X = +29`
  à `Z = -23` : les deux panneaux restent séparés mais visuellement liés. Sommet des
  panneaux arrière à `Y = 36.00`, donc nettement plus hauts que la boucle (`Y = 23.00`).
- **P5.8 Textures.** Atlas `HubBoardsAtlas` `1024²` partagé Top 3 / Rules ;
  `HubLoopPanelFrame` en UV uniques `1024²`.
- **P5.9 Export, import, validation.** 3 FBX distincts, `2 500` triangles chacun,
  contrôle : aucun texte dans les meshes ni dans les textures.
- **P5.10 Point d'arrêt Studio.** 6 captures + lisibilité des 3 panneaux depuis
  `ValidationCam_Spawn` ; refus si un cadre paraît plat.

Commit : `assets(hub): loop, top3 and rules panel frames`

## Phase 6 — Navigation et modules secondaires

- **P6.1 `HubFrontStairs`.** 3 marches `26` de large, `3.5` de profondeur, dessus à
  `10.45` / `8.90` / `7.35` ; palier `26 × 1.2 × 10.8` jusqu'à `Z = 51.3` ; joues
  latérales `≤ 1.2` ; nez de marche `Neon` `0.2`. Meshes : `Steps`, `Landing`,
  `NeonNosing`. FBX, `4 000` triangles.
- **P6.2 `HubRailingsAndPosts`.** Segments exacts du périmètre (avant gauche/droite
  `16 × 3.5 × 1` en `(∓22, 13.75, 29.5)`, arrière `60 × 3.5 × 1`, latéraux
  `1 × 3.5 × 36` en `(±41.5, ·, 0)`, 4 chanfreins `17 × 3.5 × 1` à `±45°`), 12 poteaux
  `1.6 × 4.2 × 1.6`, capuchons `Neon` **sans** source lumineuse. FBX, `4 000` triangles.
- **P6.3 `HubTransitShell`.** Arche `10 × 11 × 10`, portail cyan translucide
  (`Neon` + transparence `0.45`), enseigne intégrée (`TransitSignFace` `6 × 1.6`),
  socle mouluré. Le cylindre et l'anneau générés ne doivent plus être visibles une fois ce
  shell actif. Cylindre `⌀6 × 8` centré `(34, 12.6, -19)` laissé libre pour la pastille
  fonctionnelle, qui devient invisible. FBX, `3 500` triangles.
- **P6.4 `HubSpawnMedallion`.** `⌀18 × 0.9`, anneau mouluré, étoile en relief, cœur
  `Neon` `⌀3`, relief total `≤ 0.9`. Volume `12 × 5 × 12` au-dessus laissé totalement
  libre. FBX, `1 500` triangles.
- **P6.5 Validation circulation.** Marcher du spawn aux bulles : largeur utile `≥ 24`
  studs dans l'escalier, aucun obstacle, aucune marche de plus de `2` studs de hauteur
  effective (compatibilité avatars R6/R15), arrivée exacte sur la première rangée de bulles
  conservée (`Z = 51.3`, `Y = 7.35`).
- **P6.6 Validation collisions.** Les collisions restent portées par les Parts invisibles :
  vérifier qu'aucun mesh n'introduit de collision parasite ni de blocage au niveau du
  médaillon, du pad de vente ou du passage de la boutique.
- **P6.7 Validation hiérarchie visuelle.** Transit visuellement secondaire (hauteur `11`
  contre `15.5` pour les panneaux et `14` pour les kiosques), spawn dégagé.
- **P6.8 Point d'arrêt Studio.** 6 captures + un aller-retour spawn → bulles → vente
  filmé ou décrit.

Commit : `assets(hub): stairs, railings, transit shell and spawn medallion`

## Phase 7 — Lumières et accessoires

- **P7.1 `HubLightFixtures` — luminaires.** 12 lanternes de poteaux, 6 bornes basses
  `0.8 × 1.6 × 0.8`, 4 diffuseurs d'auvents, 2 projecteurs de panneaux, 1 lueur de
  médaillon, 1 halo de portail. Corps `Metal` `#31353F`, diffuseurs `Neon` `#DCEEFF`.
- **P7.2 `HubLightFixtures` — budget lumières.** Exactement `10` vraies sources :
  2 spots Sell, 2 spots Shop, 2 spots panneaux, 1 point médaillon, 1 point portail,
  2 points bas de descente. `Brightness ≤ 1.4`, `Range ≤ 18`, `Shadows = false` en profil
  mobile. Toutes les autres lumières apparentes sont `Neon` ou émissives.
- **P7.3 `HubDecorProps` — props indépendants.** `SellCrates`, `SellBills`, `ShopGoods`,
  `ShopBasket`, `DeckPlants` (petits arbustes), `FloorChevrons`, petits modules
  métalliques. Un fichier OBJ par prop, pivot en base, `≤ 900` triangles chacun,
  `4 000` triangles au total. **Jamais un seul bloc de décoration.**
- **P7.4 Variations gauche/droite.** Limitées : mêmes familles de props, teintes et
  disposition différentes, jamais de silhouette asymétrique.
- **P7.5 Zones interdites aux props.** Volume de vente `11 × 8 × 12`, passage central de
  `6` studs du Shop, `1.5` stud autour de chaque `PromptAnchor`, volume de spawn.
- **P7.6 Textures.** Atlas `HubPropsAtlas` `1024²`, atlas commun `512²` pour les
  luminaires.
- **P7.7 Point d'arrêt Studio.** 6 captures de nuit et de jour, contrôle du plafond de
  `10` lumières, contrôle de la part émissive (`≤ 8 %` de la surface visible).

Commit : `assets(hub): light fixtures and decor props`

## Phase 8 — Intégration finale

Seule phase autorisée à modifier des scripts de production, et **uniquement** après
approbation visuelle des phases 2 à 7.

- **P8.1** `GameConfig.Hub` : appliquer les dimensions approuvées
  (`LoopPanel.Size = 34 × 9.5 × 2.0` et `PlinthHeight = 1.5`,
  `Boards.Size = 20 × 15.5 × 2.0` + socle, `Sell` et `Shop` alignés sur
  `18 × 14 × 22`), la palette graphite, et le drapeau
  `Transit.UseImportedVisual = true`.
- **P8.2** `HubLayout` : recalculer les cotes dérivées, ajouter les positions des surfaces
  `*Face`, exposer `GetAssetContract()` et les nouveaux extents ; mettre à jour
  `HubLayoutTests`.
- **P8.3** `CentralHubBuilder` : consommer `HubAssetContract`, marquer les pièces générées
  `BPW_PrototypeVisualFallback = true`, monter les `SurfaceGui` sur les plans `*Face` des
  modèles importés quand ils existent (sinon sur les Parts prototype), ne plus générer
  aucune forme visible pour un module importé valide.
- **P8.4** `ItemShopBuilder` : réaligner `PromptAnchor_*`, `CameraPoint_*` et `Display_*`
  sur le stand `18 × 14 × 22` ; mettre à jour `tools/test_itemshop_builder.lua`.
- **P8.5** `LeaderboardService` : résoudre `Top3Face` en priorité, `GlobalLeaderboardBoard`
  en repli, `BPW_Rows = 3` conservé.
- **P8.6** `Client/HUD` : résoudre `SellValueFace` en priorité, panneau prototype en repli.
- **P8.7** `BubbleTransitBuilder` : pad de détection et prompts conservés, visuel du pad
  rendu invisible quand `HubTransitShell` est actif ; aucun changement de destination, de
  téléportation ni d'état d'onboarding.
- **P8.8** Zones et collisions : vérifier `SellZone`, volume de spawn, collisions
  invisibles du deck, de l'escalier et des ailes.
- **P8.9** Activer les 12 drapeaux `UseImported` module par module, en vérifiant le rendu
  après chaque activation.
- **P8.10** Masquer toute géométrie prototype visible restante ; conserver les Parts
  invisibles nécessaires aux collisions et aux repères.
- **P8.11** Vérifier le fallback : renommer temporairement un modèle importé → le
  prototype doit reprendre sa place avec un avertissement unique, sans erreur.
- **P8.12** Vérifier la restauration complète avec `GameConfig.Hub.Enabled = false`
  (lobby historique intact, décor Studio restauré depuis
  `ServerStorage.BPW_ParkedLobbyDecor`).
- **P8.13** Recette fonctionnelle : localisation (FR/EN), classement `TOP 3`, vente
  automatique, boutique (3 catégories, prompts, caméras, achats), Bubble Transit
  (aller-retour Summer Zone), spawn nouveau joueur, spawn vétéran, `FallReset`,
  Summer Zone inchangée, test à deux joueurs simultanés.
- **P8.14** Exécuter toute la batterie de tests hors Roblox
  (`run_hub_tests`, `run_central_hub_tests`, `run_hub_asset_tests`,
  `run_itemshop_builder_tests`, `run_travel_tests`, et les autres suites du dossier
  `tools/`), plus les suites Studio via `init.server.lua`.

Commits (un par bloc, jamais mélangés) :

1. `feat(hub): adopt asset pack dimensions and graphite palette in config`
2. `feat(hub): mount surface guis on imported asset faces`
3. `feat(hub): align item shop anchors on imported shop stand`
4. `feat(hub): imported transit shell replaces generated pad visual`
5. `chore(hub): mark generated geometry as prototype visual fallback`
6. `test(hub): update layout, asset contract and shop harnesses`

---

## Production des assets — Voie A : Blender

### Organisation des fichiers

```text
assets/hub-concept2/
├── blender/
│   ├── HubDeckShell.blend
│   ├── HubFrontStairs.blend
│   ├── HubRailingsAndPosts.blend
│   ├── HubSellStandShell.blend
│   ├── HubShopStandShell.blend
│   ├── HubLoopPanelFrame.blend
│   ├── HubTop3BoardFrame.blend
│   ├── HubRulesBoardFrame.blend
│   ├── HubTransitShell.blend
│   ├── HubSpawnMedallion.blend
│   └── HubSmallProps.blend        (fichier commun : luminaires + props uniquement)
├── export/                        (.fbx / .obj générés, non versionnés si > 5 Mo)
├── textures/                      (ColorMap / Normal / Roughness / Metalness)
└── reference/                     (maquette + captures de cadrage)
```

Un fichier Blender par module principal ; **un seul** fichier commun pour les petits props
et les luminaires.

### Réglages Blender obligatoires

- unités métriques, `Unit Scale = 1.0`, **1 unité Blender = 1 stud** ;
- modélisation à l'origine, face avant vers `-Y` Blender (devient `-Z` Roblox), haut vers
  `+Z` Blender ;
- `Ctrl+A → Scale` et `Rotation` appliqués avant export ;
- origine d'objet posée exactement sur le pivot du tableau des transformations ;
- modificateur `Triangulate` (`Quad Method: Fixed`) appliqué ;
- normales recalculées vers l'extérieur, pas de face double, pas de géométrie interne ;
- un seul UV set nommé `UVMap`, sans chevauchement non voulu ;
- collection par mesh final, nommée exactement comme l'instance Roblox attendue ;
- cube témoin `ScaleCheck_10` (`10 × 10 × 10`) présent dans le premier export.

### Script Blender Python facultatif

`tools/blender/hub_asset_prep.py` (à créer en phase 2, outil de modélisation, hors
production runtime) :

1. force `scene.unit_settings` en métrique, `scale_length = 1.0` ;
2. applique transformations et échelles sur toute la sélection ;
3. crée les collections manquantes d'après une table de modules ;
4. renomme les meshes selon le contrat (`HubAssetContract`) ;
5. valide les bounding boxes contre les cotes approuvées et refuse l'export au-delà de
   `±0.5` stud ;
6. contrôle le budget triangles par mesh (`≤ 10 000`) et par module ;
7. ajoute / retire `ScaleCheck_10` ;
8. lance l'export FBX avec les réglages figés
   (`-Z Forward`, `Y Up`, `Apply Scalings: FBX Units Scale`, `Apply Transform`,
   `Mesh` + `Empty`, tangentes exportées, animations désactivées).

### Procédure d'export puis d'import

1. exporter le FBX dans `assets/hub-concept2/export/` ;
2. Studio → `Avatar → 3D Importer`, sélectionner le fichier ;
3. contrôler `ScaleCheck_10` : `Size` doit valoir exactement `10, 10, 10` — sinon corriger
   le réglage d'import, jamais le modèle ;
4. `Anchored = true`, `CanCollide = false`, `CollisionFidelity = Box`, `CastShadow` selon la
   fiche du module ;
5. renommer strictement selon le contrat ;
6. poser le `Model` sous `Workspace.StudioDecoration.CentralHubVisual` ;
7. aligner le `WorldPivot` sur `CentralHub.HubAnchors.Anchor_<Module>` ;
8. créer les `SurfaceAppearance` (ColorMap / Normal / Roughness / Metalness) ;
9. supprimer `ScaleCheck_10` ;
10. lancer `HubAssetContract.Validate` via la barre de commande et corriger tout refus.

### Contrôle du pivot

Après import, la distance entre le `WorldPivot` du `Model` et l'ancre doit être
`≤ 0.25` stud, et le yaw à `±1°`. Contrôle rapide : le module doit rester en place lorsqu'on
remet manuellement `WorldPivot` sur l'ancre (aucun saut visible).

## Production des assets — Voie B : générateur 3D par IA

Un prompt **indépendant par module** (jamais un prompt global pour tout le hub). Chaque
prompt est autonome : style, proportions, matériaux, ouvertures, interdits, pivot, format.
Consignes communes à ajouter à la fin de chaque prompt :

> Neutral background, no ground plane, no character, no bubbles, no text, no logo, no
> watermark, no UI, no baked lettering. Single centered object. Real-world scale in studs
> (1 unit = 1 stud). Pivot at the point specified. Export as FBX (OBJ acceptable for a
> single-mesh prop). Game-ready, low-poly, quad-friendly topology, clean non-overlapping
> UVs, PBR maps at 1024×1024.

### Prompt — `HubDeckShell`

```text
Stylized Roblox-style octagonal hub platform, dark graphite, 84 x 7.5 x 60 studs
(width x height x depth). Regular octagon footprint: 60-stud flat front and back edges,
36-stud flat side edges, four 45-degree chamfered corners about 17 studs long.
Four stacked strata, clearly readable from the front: a flared dark slate skirt at the
bottom (2.5 studs tall), a recessed painted-metal plinth (1.8 studs, inset 2.5 studs),
a matte composite top slab (2 studs), and an overhanging deck nose with a 0.25-stud shadow
groove. Vertical edges softened with a 0.5-stud fillet. Two integrated side wings, each
24 x 1.2 x 22 studs, blended into the main slab with continuous skirt and moulding
(never separate floating pads). Slightly raised circular center, 26-stud diameter,
0.25 stud higher.
Materials: dark slate skirt (#23262E), matte painted metal plinth (#31353F), matte
composite slab (#3A3F4B), brushed metal nose (#4A505E), thin cyan emissive trim (#4FD8FF)
inset in the groove, 0.3 stud thick, running all around except a 28-stud gap centered on
the front edge.
Must stay open: 28-stud front gap, an 18-stud circle 8 studs in front of center, an
11 x 9 rectangle on the left wing, a 9 x 9 square on the right wing, a 9-stud circle at the
back right corner.
Do not generate: stairs, railings, kiosks, signs, panels, lights, props, any white or
near-white surface, any large cyan slab, any floating platform look.
Pivot: bounding box center. 4 separate meshes named Base, Moulding, Wings, NeonTrim.
Triangle budget: 13000 total, 10000 max per mesh.
```

### Prompt — `HubSellStandShell`

```text
Stylized Roblox-style open market kiosk for selling, 18 x 14 x 22 studs
(depth x height x width). Thick dark graphite U-shaped frame with a moulded canopy and a
recessed sign housing on the fronton. Fully open front face. Inside: a green glowing alcove
(deep green #1E4B33 fading to #2FA96A), one low shelf, and a 4.2-stud tall counter with a
decorated front panel. Three readable depth layers from the front: fronton, canopy, back
wall.
Materials: matte painted metal frame (#2E323C), matte composite interior, metal-and-wood
counter (#5A6172), thin emissive green trim (#5AE68C) on frame edge, under-canopy light bar
and a halo behind the sign housing.
Must stay open and empty: a 11 x 8 x 12 stud volume in front of the counter (player standing
area), and a flat 11 x 9 stud floor footprint (max 0.3 stud thick decorative pad).
Include two flat, featureless rectangular plates for later UI: 13 x 3 studs on the fronton
and 7 x 3 studs on the back wall, both facing the open side, with no relief and no texture.
Do not generate: any letter or word (no SELL text), closed walls on the front, a big black
box counter, floating coins, characters, bubbles, ground.
Pivot: bottom center of the module footprint. 4 separate meshes named Frame, Interior,
Counter, NeonTrim. Triangle budget: 8000.
```

### Prompt — `HubShopStandShell`

```text
Stylized Roblox-style open shop kiosk, mirror-symmetric twin of a selling kiosk,
18 x 14 x 22 studs (depth x height x width). Same thick dark graphite frame, same canopy
height, same fronton with a recessed sign housing. Fully open front with a 6-stud wide clear
central walkway through the whole depth. Inside: purple-magenta alcove (#3A1E4B fading to
#8E3FD1), two shelves at 2.4 and 5.2 studs high against the back wall, and a compact
3.4-stud counter split in two runs leaving the central walkway free.
Materials: matte painted metal frame (#2E323C), matte composite interior, metal counter
(#5A6172), thin emissive magenta (#E65FD7) and violet (#9664FF) trim on frame and shelf
edges only.
Must stay open: the 6-stud central walkway, three 3-stud diameter cylinders in front of the
shelves, and a 9 x 9 stud floor footprint on the front right.
Include flat featureless plates for later UI: 13 x 3 studs on the fronton and three
3.4 x 4 stud plates above the shelves, facing the open side, no relief, no texture.
Do not generate: any letter or word (no SHOP text), an enclosed shop interior, doors,
a solid magenta volume, neon cubes as merchandise, characters, bubbles, ground.
Pivot: bottom center of the module footprint. 4 separate meshes named Frame, Interior,
Counter, NeonTrim. Triangle budget: 8000.
```

### Prompt — `HubLoopPanelFrame`

```text
Stylized Roblox-style thick display panel frame, 34 x 9.5 x 2 studs
(width x height x depth). Wide chunky frame with rounded corners (1.2-stud radius) around a
deep midnight-blue recessed backplate (#101A34). Thin cyan emissive trim (#4FD8FF) set back
0.4 stud behind the frame so it reads as a soft halo, never a flat glowing plane. Integrated
moulded base 36 x 1.5 x 4 studs under the panel, plus two angled support legs at the back.
Materials: matte painted metal frame (#2A2E38), brushed metal bevel (#4A505E), matte
composite backplate.
Include one perfectly flat, featureless rectangular plate of 30 x 7 studs on the front face,
centered, with no relief, no bevel and no texture: it will receive dynamic UI later.
Do not generate: any text, arrow, icon, number or symbol on the panel; no screen content;
no characters; no ground.
Pivot: middle of the bottom edge of the frame. 2 separate meshes named Frame and NeonEdge.
Triangle budget: 2500.
```

### Prompt — `HubTop3BoardFrame`

```text
Stylized Roblox-style tall leaderboard board frame, 20 x 15.5 x 2 studs
(width x height x depth), with a rounded top (arc of 10-stud radius over the top 4 studs).
Thick dark graphite frame (at least 1.5 studs of apparent thickness) around a deep
midnight-blue recessed backplate (#101A34). Solid base 20 x 3 x 4 studs with integrated legs
going down 8.5 studs. A 4 x 4 stud recessed housing at the top for a trophy emblem, plus a
separate simple gold brushed-metal trophy emblem mesh.
Materials: matte painted metal frame (#2A2E38), matte composite backplate, thin gold
emissive trim (#FFCD50) on the frame only, brushed gold emblem (#FFD766).
Include one perfectly flat featureless plate of 17 x 11.5 studs on the front face for
dynamic UI: no relief, no texture, no border drawn on it.
Do not generate: any text, ranking rows, numbers, player names, avatars, ground, characters.
Pivot: middle of the bottom edge of the frame. 3 separate meshes named Frame, Base,
TrophyIcon. Triangle budget: 2500.
```

### Prompt — `HubRulesBoardFrame`

```text
Stylized Roblox-style tall rules board frame, 20 x 15.5 x 2 studs (width x height x depth),
identical shape family and same rounded top as a leaderboard board (arc of 10-stud radius
over the top 4 studs), mirrored on the horizontal axis. Thick dark graphite frame around a
deep midnight-blue recessed backplate (#101A34). Solid base 20 x 3 x 4 studs with integrated
legs going down 8.5 studs. A 4 x 4 stud recessed housing at the top for a clipboard emblem,
plus a separate simple clipboard emblem mesh.
Materials: matte painted metal frame (#2A2E38), matte composite backplate, thin amber
emissive trim (#FFAA3C) on the frame only, off-white clipboard (#F0F4FF).
Include one perfectly flat featureless plate of 17 x 11.5 studs on the front face for
dynamic UI: no relief, no texture.
Do not generate: any text, rule lines, numbers, icons on the plate, ground, characters.
Pivot: middle of the bottom edge of the frame. 3 separate meshes named Frame, Base,
ClipboardIcon. Triangle budget: 2500.
```

### Prompt — `HubFrontStairs`

```text
Stylized Roblox-style wide front staircase, 26 x 4.65 x 20.8 studs
(width x height x depth). Three steps, each 26 studs wide and 3.5 studs deep, with 1.55-stud
risers, followed by a flat landing 26 x 10.8 studs at the bottom. Sculpted step nosing,
thin side cheeks no wider than 1.2 studs, closed risers (no gap under the steps).
Materials: matte composite treads (#3A3F4B), darker risers (#2A2E38), brushed metal cheeks
(#4A505E), thin cyan emissive nosing strip (#4FD8FF) 0.2 stud thick on each step edge,
plus two emissive floor chevrons on the landing.
Do not generate: railings, posts, lights, platform, bubbles, ground, text, arrows with
letters, characters.
Pivot: middle of the top edge of the first step (top of the staircase). 3 separate meshes
named Steps, Landing, NeonNosing. Triangle budget: 4000.
```

### Prompt — `HubRailingsAndPosts`

```text
Stylized Roblox-style low perimeter railing kit for an octagonal platform, dark graphite.
Straight railing segments 3.5 studs tall and 1 stud thick, in these lengths: two of
16 studs, one of 60 studs, two of 36 studs, and four of 17 studs meant to sit at 45 degrees.
Twelve square posts of 1.6 x 4.2 x 1.6 studs with moulded caps.
Materials: matte painted metal (#31353F), thin emissive cyan handrail cap (#4FD8FF) and
emissive off-white lantern lens (#DCEEFF) on each post cap. Emissive parts must be separate
meshes; no light source objects.
Do not generate: the platform, the stairs, glass panels, ropes, chains, text, characters,
ground.
Pivot: bottom center of each element, kit centered on the world origin.
3 separate meshes named Segments, Posts, NeonCaps. Triangle budget: 4000.
```

### Prompt — `HubTransitShell`

```text
Stylized Roblox-style small teleport arch, 10 x 11 x 10 studs, compact and secondary in
scale. A moulded circular base 9 studs in diameter, a thick graphite arch frame, and a
translucent cyan portal disc inside the arch. A small recessed sign housing on top of the
arch.
Materials: matte painted metal arch (#2E323C), moulded composite base (#31353F),
translucent emissive cyan portal (#4FD8FF, about 45 percent transparency, separate mesh),
off-white sign plate (#DCEEFF).
Include one flat featureless plate of 6 x 1.6 studs on the front of the sign housing for
dynamic UI, and keep a free cylindrical volume 6 studs in diameter and 8 studs tall in the
center of the base (nothing may cover it).
Do not generate: any text (no BUBBLE TRANSIT lettering), vehicles, capsules, characters,
bubbles, ground, large decorative wings that would dominate the arch.
Pivot: center of the base at floor level. 4 separate meshes named Arch, Base, PortalNeon,
Sign. Triangle budget: 3500.
```

### Prompt — `HubSpawnMedallion`

```text
Stylized Roblox-style circular floor medallion, 18 studs in diameter and 0.9 stud tall,
designed to be inlaid flush into a dark platform. A moulded brushed-metal outer ring, a dark
recessed field, an eight-point star in low relief, and a small emissive core 3 studs in
diameter at the center.
Materials: brushed metal ring (#4A505E), dark matte field (#22262E), off-white star relief
(#DCEEFF), cyan emissive core and star grooves (#4FD8FF).
Total relief must never exceed 0.9 stud so a character can never trip on it. Nothing above
the medallion.
Do not generate: text, arrows with letters, pedestals, columns, characters, bubbles, ground
beyond the medallion disc.
Pivot: center of the disc at floor level. 3 separate meshes named Ring, Star, NeonCore.
Triangle budget: 1500.
```

### Prompt — `HubLightFixtures`

```text
Stylized Roblox-style set of small light fixtures for a dark graphite hub platform, sold as
separate pieces: a post lantern (1.4 x 2 x 1.4 studs) with a moulded cap and an emissive
lens, a low bollard light (0.8 x 1.6 x 0.8 studs), a recessed canopy downlight
(1.2 x 0.4 x 1.2 studs), and a small board spotlight on a short bracket
(1 x 1.4 x 1.8 studs).
Materials: matte painted metal bodies (#31353F), emissive off-white lenses (#DCEEFF) as
separate meshes; provide green (#B8FFD4), magenta (#F0C8FF) and warm gold (#FFE7B0) lens
variants.
Do not generate: light beams, volumetric cones, lens flares, wires, text, characters,
ground.
Pivot: base of each fixture. Separate meshes per fixture type. Triangle budget: 1500 total.
```

### Prompt — `HubDecorProps`

```text
Stylized Roblox-style set of small game-ready props for a hub platform, each one a separate
independent object with its own pivot at the base, no shared base plate:
a wooden crate (2.4 studs cube), a stack of banknotes (2 x 0.6 x 1.4 studs), a coin pile
(1.6 studs diameter), a potion bottle (0.9 x 1.6 x 0.9 studs), a small treasure chest
(2.2 x 1.6 x 1.6 studs), a shopping basket (2 x 1.2 x 1.6 studs), a small potted shrub
(1.8 x 2.4 x 1.8 studs), and a small metal utility module (1.6 x 1.2 x 1.2 studs).
Materials: matte wood, matte painted metal, matte plastic, with small emissive accents only
(green #5AE68C, magenta #E65FD7, gold #FFCD50).
Do not generate: a single merged block, a ground plane, text or labels on the props,
characters, bubbles, oversized items above 4 studs.
Pivot: base of each prop. One mesh per prop, max 900 triangles each, 4000 total.
```

## Formats

| Module | Format imposé |
|---|---|
| `HubDeckShell` | FBX |
| `HubSellStandShell` | FBX |
| `HubShopStandShell` | FBX |
| `HubLoopPanelFrame` | FBX |
| `HubTop3BoardFrame` | FBX |
| `HubRulesBoardFrame` | FBX |
| `HubFrontStairs` | FBX |
| `HubTransitShell` | FBX |
| `HubRailingsAndPosts` | FBX |
| `HubSpawnMedallion` | FBX |
| Luminaire isolé, caisse, pile de billets, plante, petit objet décoratif | OBJ (un fichier par objet) |

OBJ ne transporte ni hiérarchie, ni pivot d'objet, ni affectation PBR fiable : un **OBJ
unique contenant tout le hub est formellement déconseillé** (perte des pivots, des noms de
meshes et des matériaux, impossibilité de remplacer un module isolément, et budget triangles
non contrôlable module par module).

## Validation artistique bloquante

À la fin de chaque phase visuelle (2 à 7), fournir 6 captures et une comparaison explicite
avec la maquette :

1. caméra de référence frontale (`CentralHubConcept2ReferenceCamera`) ;
2. vue joueur au spawn (`ValidationCam_Spawn`) ;
3. vue depuis les bulles (`ValidationCam_FromBubbles`) ;
4. vue de dessus (`ValidationCam_Top`) ;
5. vue latérale (`ValidationCam_Side`, position `(120, 30, 0)`, cible `(0, 16, 0)`,
   `FOV 40`) ;
6. vue mobile (`ValidationCam_Mobile`, `20:9`).

Archivage : `docs/superpowers/specs/renders/2026-08-01-phase<N>-<vue>.png`.

Une phase **n'est pas acceptée** au seul motif que les tests passent, que les dimensions
sont exactes, que les collisions fonctionnent ou que le modèle est importé.
L'acceptation visuelle est obligatoire et explicite.

Refus immédiat si :

- le Deck paraît blanc ou cyan ;
- la plateforme semble flotter ;
- le Sell ou le Shop ressemblent à des boîtes ;
- les modules manquent de profondeur ;
- les panneaux sont plats ;
- les textures sont absentes ;
- les cadres sont minces ;
- la silhouette s'éloigne fortement de la maquette ;
- les assets ressemblent à un simple remplacement des Parts par des cubes MeshPart.

## Git

Un commit distinct par phase, et jamais de mélange entre production d'assets, modifications
fonctionnelles, économie, onboarding et Summer Zone.

| Phase | Message de commit |
|---|---|
| 0 | `docs(hub): reference camera plugin and prototype baseline captures` |
| 1 | `feat(hub): hub asset import contract and guard tests` |
| 2 | `assets(hub): deck shell model, textures and import sheet` |
| 3 | `assets(hub): sell stand shell model and textures` |
| 4 | `assets(hub): shop stand shell model and textures` |
| 5 | `assets(hub): loop, top3 and rules panel frames` |
| 6 | `assets(hub): stairs, railings, transit shell and spawn medallion` |
| 7 | `assets(hub): light fixtures and decor props` |
| 8 | 6 commits listés dans la phase 8 |

Règles : les modifications en cours non liées (summer-decor, onboarding, hub central
existant) restent dans l'arbre de travail et ne sont jamais incluses dans ces commits ;
les fichiers binaires lourds (`.blend` > 20 Mo, exports > 5 Mo) sont exclus ou stockés hors
dépôt selon décision au point d'arrêt de la phase 2.

## Risques et parades

| Risque | Impact | Parade prévue |
|---|---|---|
| Échelle d'import fausse (1 unité ≠ 1 stud) | tout le hub décalé | cube témoin `ScaleCheck_10` obligatoire à chaque premier import |
| Orientation réelle différente de la convention `-Z` | modules retournés, faces arrière détaillées côté caméra | validation Studio de l'orientation dès la phase 2, avant tout détail arrière |
| Pivot non centré / non aligné sur l'ancre | modules flottants ou enfoncés | tolérance `±0.25` stud contrôlée par `HubAssetContract.Validate` |
| Budget mobile dépassé | chutes de FPS sur mobile | budget par module figé, contrôle au script Blender et à l'import |
| Générateur IA produisant du texte incrusté | enseignes illisibles, doublon avec les `SurfaceGui` | interdiction explicite dans chaque prompt + contrôle au point d'arrêt |
| Générateur IA produisant un mesh unique fusionné | modules non remplaçables, matériaux impossibles | découpage en meshes nommés imposé dans chaque prompt, refusé sinon |
| Asset recouvrant une zone fonctionnelle | vente, prompts ou spawn cassés | zones libres listées par module + tests de garde |
| Changement de dimensions cassant `ItemShopBuilder` | prompts et caméras désalignés | phase 8 dédiée + harnais `run_itemshop_builder_tests` |
| Perte du fallback | hub invisible si un asset manque | comportement « asset absent / invalide » testé en phase 1 et revérifié en P8.11 |
| Mélange avec les chantiers en cours | commits illisibles, régressions croisées | un commit par phase, périmètre explicite, aucun fichier hors périmètre |

## Journal

| Date | Phase | État | Notes |
|---|---|---|---|
| 2026-08-01 | — | plan créé | aucun asset produit, aucun script de production modifié |
| 2026-08-01 | 0 | exécutée, commit en attente | P0.1 à P0.4, P0.6, P0.7 faites ; P0.2 et P0.5 bloquées sur des images à fournir |
| 2026-08-01 | 0 | **terminée** | 8 images présentes et validées, plugin testé en Edit et en Test (F5), écarts documentés, Phase 1 non commencée |

### P0.1 — État du dépôt de référence (2026-08-01)

- branche : `master` ;
- `HEAD` : `4717ef361c1a0f34e0319ea7f1d031355679cfea` —
  `fix(onboarding): restore Studio Test player via early SpawnLocation`
  (BubblePopWorld <dev@bubblepop.local>, Sat Aug 1 09:20:38 2026 -0400) ;
- index : **aucun fichier stagé** (`git diff --cached --stat` vide) ;
- 11 fichiers modifiés non stagés, `477 insertions(+)`, `67 deletions(-)` :

| Fichier | Δ | Chantier |
|---|---|---|
| `sourcemap.json` | 2 | généré par Rojo |
| `src/Client/HUD.lua` | 23 | hub central (SellValueBoard) |
| `src/Server/BubbleService.lua` | 14 | hub central (cellules réservées) |
| `src/Server/ItemShopBuilder.lua` | 63 | hub central (ancre kiosque) |
| `src/Server/LeaderboardService.lua` | 50 | hub central (TOP 3) |
| `src/Server/ZoneService.lua` | 107 | hub central (spawn, bordures, décor lobby rangé) |
| `src/Server/init.server.lua` | 3 | câblage des suites de tests |
| `src/Shared/GameConfig.lua` | 194 | hub central (`GameConfig.Hub`) |
| `src/Shared/LocalizationStrings.lua` | 22 | hub central (textes des panneaux) |
| `src/Shared/TravelConfig.lua` | 13 | hub central (destination transit) |
| `src/Shared/TravelConfigTests.lua` | 53 | tests transit |

- 6 fichiers non suivis avant la Phase 0 : `docs/superpowers/plans/2026-08-01-central-hub-concept2.md`,
  `docs/superpowers/plans/2026-08-01-central-hub-concept2-asset-pack.md`,
  `docs/superpowers/specs/2026-08-01-central-hub-concept2-asset-pack-design.md`,
  `src/Server/CentralHubBuilder.lua`, `src/Shared/HubLayout.lua`,
  `src/Shared/HubLayoutTests.lua` ;
- ces 17 entrées sont **hors périmètre du commit de Phase 0** : elles restent dans
  l'arbre de travail, aucune n'a été annulée, reformatée ni stagée.

### P0.2 — Maquette de référence

`docs/superpowers/specs/renders/` créé. L'image exacte `Concept 2 — Équilibré` n'était ni
dans le dépôt ni identifiable de façon fiable sur le disque : aucun substitut n'a été créé.
**Résolu** — l'utilisateur a fourni l'image, archivée sous
`docs/superpowers/specs/renders/2026-08-01-concept2-reference.png`
(`2 339 812` octets, `1672 × 941`, 16:9, PNG valide, non recompressée).

### P0.3 / P0.4 — Caméras de validation

`studio-plugins/HubValidationCameras.plugin.lua` créé, puis corrigé pour l'usage réel :
5 actions, dont 2 réservées à l'édition (`Create/Refresh`, `Remove`) et 3 utilisables
pendant un test (`Go To Selected View`, `List Views`, `Restore Test Camera`), puisque le hub
central n'est construit qu'au lancement du serveur. Idempotent, 7 repères inertes sous
`Workspace.StudioDecoration.CentralHubVisual.ValidationCameras`. Pendant un test, le premier
cadrage mémorise `CameraType`, `CameraSubject`, `CFrame`, `Focus` et `FieldOfView` et n'écrase
plus cet état ensuite ; `Restore Test Camera` le rétablit puis l'efface. Cadrages imposés
respectés
(référence `(0, 74, 124) → (0, 15, 4)`, FOV 36, 1920 × 1080 ; latérale
`(120, 30, 0) → (0, 16, 0)`, FOV 40). Les 5 autres cadrages sont calculés depuis les
ancres réelles, dérivation documentée dans le plugin, dans
`docs/superpowers/specs/renders/README.md` et exposée en attribut `BPW_Derivation`.

### P0.5 — Captures du prototype

Aucun fichier factice n'a été créé : piloter Studio n'est pas automatisable ici, seule la
procédure a été fournie (`docs/superpowers/specs/renders/README.md`). **Résolu** — les
7 captures ont été prises manuellement pendant un test `F5` et vérifiées :

| Fichier | Octets | Pixels | PNG |
|---|---|---|---|
| `2026-08-01-prototype-reference.png` | 444 349 | 1077 × 737 | valide |
| `2026-08-01-prototype-spawn.png` | 212 077 | 1067 × 701 | valide |
| `2026-08-01-prototype-from-bubbles.png` | 302 185 | 1065 × 707 | valide |
| `2026-08-01-prototype-back.png` | 246 020 | 1070 × 717 | valide |
| `2026-08-01-prototype-top.png` | 512 586 | 1073 × 716 | valide |
| `2026-08-01-prototype-side.png` | 408 074 | 1071 × 716 | valide |
| `2026-08-01-prototype-mobile.png` | 187 326 | 1077 × 715 | valide |

Écart accepté pour la ligne de base : les 7 captures sont en ~`1070 × 715` (≈ 3:2) au lieu
de `1920 × 1080` (16:9), et la vue mobile n'est pas en 20:9 ; l'interface Roblox et
l'avatar sont visibles. Suffisant comme référence « avant », mais pour les captures de
validation des phases 2 à 7 il faudra fixer la fenêtre 3D au bon rapport et masquer
l'interface pendant le test (`game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false)`
depuis la barre de commande client, sans modifier aucun script).

Contenu confirmé par lecture des images : la maquette est bien `CONCEPT 2 — ÉQUILIBRÉ`, et
les captures du prototype montrent exactement les défauts qui ont motivé le refus — deck
blanc bleuté et cyan dominants, plateforme qui paraît flotter au-dessus d'une fondation
plus étroite (vue latérale), kiosques en boîtes noire et magenta, panneaux plats de
`0.8` d'épaisseur, aucun MeshPart, aucun accessoire.

### P0.6 / P0.7 — Ancres et transformations monde

`python tools\run_central_hub_tests.py` : **129 réussis, 0 échoué, 141 pièces générées**.
Inventaire relevé depuis le code dans `docs/superpowers/specs/renders/anchors.txt` :
12 ancres sur 12 attendues sous `CentralHub.HubAnchors`, 3 repères fonctionnels,
126 pièces visibles de prototype, 0 MeshPart, 0 source lumineuse, 176 cellules de bulles
réservées.

Écarts confirmés entre les ancres actuelles (prototype) et les cotes approuvées : le deck
est un plateau de `2.0` de haut au lieu d'une masse de `7.5`, les stands sont
`24 × 8.2 × 22` et `16 × 9 × 22` au lieu de `18 × 14 × 22` symétriques, les panneaux ont
`0.8` d'épaisseur au lieu de `2.0`, l'alcôve Transit est une pastille de `0.6` au lieu
d'une arche de `11`. Ces écarts sont **normaux** : les modeleurs travaillent sur les cotes
approuvées, et l'alignement des ancres se fait en `P8.1` / `P8.2`. La table complète des
écarts et la liste des invariants intouchables (deck à `12.00`, marche des bulles à
`7.35`, palier à `51.30`, ouverture frontale de `28`, volume de vente, pad Transit, spawn)
figurent dans `anchors.txt`, et la validation module par module dans
`docs/superpowers/specs/renders/transform-validation.txt` (statut, attendu, mesuré, écart,
impact sur la modélisation pour les 12 modules).

Point d'attention reporté en Phase 2 : les ancres `Sign` portent un yaw de `180°`, donc
leur `LookVector` pointe vers `+Z`. La convention « `-Z` = face avant du module » doit être
confirmée en Studio sur le premier asset importé avant de détailler les faces arrière.

### État final de la Phase 0 (2026-08-01)

- maquette exacte présente : `2026-08-01-concept2-reference.png`, `1672 × 941`, PNG valide,
  ni redimensionnée ni recompressée ;
- 7 captures réelles du prototype présentes et lisibles comme PNG (tableau ci-dessus) ;
- plugin testé en mode Edit (création et suppression des repères) **et** pendant
  `Test (F5)` (cadrage des 7 vues, liste des vues) ;
- `Restore Test Camera` testé avec succès : `CameraType`, `CameraSubject`, `CFrame`,
  `Focus` et `FieldOfView` rétablis, mémoire effacée ensuite ;
- `python tools\run_central_hub_tests.py` : **129 réussis, 0 échoué** ;
- `luau-compile` sur `studio-plugins/HubValidationCameras.plugin.lua` : succès ;
- **12 ancres sur 12** inventoriées dans `CentralHub.HubAnchors` ;
- écarts documentés pour les 12 modules dans `transform-validation.txt`, invariants
  vérifiés `MATCH` (deck `12.00`, bulles `7.35`, palier `51.30`, ouverture `28`,
  spawn `(0, 12, 8)`, volume de vente, pad Transit, 176 cellules réservées) ;
- orientation des panneaux à confirmer au premier import, avant les faces arrière ;
- **aucune ancre modifiée, aucun script de production modifié** : `git diff --stat` est
  identique au relevé d'ouverture (11 fichiers, `477+ / 67-`), `git diff --check` propre ;
- livrables : `studio-plugins/HubValidationCameras.plugin.lua`,
  `docs/superpowers/specs/renders/{README.md, anchors.txt, transform-validation.txt}`
  et les 8 images ;
- **Phase 1 non commencée** ; prochain pas : commit
  `docs(hub): reference camera plugin and prototype baseline captures`.
