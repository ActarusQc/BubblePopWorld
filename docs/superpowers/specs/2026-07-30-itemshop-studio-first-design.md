# Design — ItemShop Studio-first

**Date :** 2026-07-30
**Projet :** Bubble Pop Simulator (`BubblePopWorld`)
**Approche retenue :** logique fonctionnelle en code, coque visuelle manuelle dans Roblox Studio

## 1. Objectif

Séparer strictement la boutique **fonctionnelle** (générée par le code, reconstructible à volonté) de la boutique **artistique** (créée et modifiée à la main dans Studio, jamais touchée par le code).

Aucune modification faite dans Studio ne doit être perdue lors d’un `rojo serve`, d’un rebuild, d’un passage en Play ou d’un appel à `ItemShopBuilder.Build()`.

## 2. Architecture Workspace

```
Workspace
├── ItemShop                    ← code, détruit et reconstruit à chaque Play
│   ├── PivotAnchor             ← référence d'alignement (invisible)
│   ├── Entrance
│   ├── PromptAnchor_Skills / _Items / _Cosmetics   (+ ProximityPrompt)
│   ├── CameraPoint_Skills / _Items / _Cosmetics
│   ├── Display_Skills / _Items / _Cosmetics        (Model + FocusAnchor)
│   └── FallbackShell           ← seulement si ItemShopVisual est absent
└── StudioDecoration            ← jamais vidé par le code
    └── ItemShopVisual          ← Studio, 100 % manuel
        ├── PivotAnchor         ← PrimaryPart : GetPivot() == pivot de configuration
        ├── Structure           ← Floor, LeftWall, BackWall, RightWall, Ceiling, FacadeBase
        ├── Exterior            ← ShopSign (placeholder) + ExteriorDraft_v1 (façade)
        ├── Interior            ← InteriorDraft_v1 (sol, plafond, trois sections, décor)
        ├── Displays            ← SkillsDisplayVisual, ItemsDisplayVisual, CosmeticsDisplayVisual
        └── Lighting
```

La hiérarchie sous `ItemShopVisual` est **artistique** : aucun script ne dépend de ces noms. Seul le nom du modèle racine `ItemShopVisual` compte.

`ItemShopVisual` ne doit **jamais** être renommé `ItemShop` : `ShopUI.findItemShop()` utilise `Workspace:FindFirstChild("ItemShop", true)` en récursif et le trouverait.

## 3. Modes de construction

`GameConfig.Lobby.ItemShop.UseStudioVisual`, résolu par `ItemShopVisualShell.ResolveEffectiveMode()` :

| `UseStudioVisual` | `ItemShopVisual` | Mode effectif | Guides fonctionnels | `FallbackShell` |
|---|---|---|---|---|
| `true` | présent | `FunctionalOnly` | oui, invisibles | non |
| `true` | absent | `FunctionalWithFallback` | oui, invisibles | oui + avertissement |
| `false` | présent | `FunctionalOnly` + avertissement | oui, invisibles | non |
| `false` | absent | `FunctionalWithFallback` + avertissement | oui, invisibles | oui |

**Valeur actuelle : `UseStudioVisual = true`.**

La décoration procédurale a été entièrement retirée du code à l’Étape 2 : le mode `Legacy` de `ResolveBuildMode()` n’a plus de décor à générer. `ResolveEffectiveMode()` le dégrade donc vers le comportement Studio-first, avec un avertissement explicite, plutôt que de produire une salle vide. Le plugin ne modifie jamais cette configuration.

Le mode retenu est écrit sur le modèle : `Workspace.ItemShop:GetAttribute("BPW_BuildMode")`.

Avertissement en mode `FunctionalWithFallback` :

```
[ItemShopBuilder] ItemShopVisual missing. Using functional fallback shell.
```

Le `FallbackShell` contient exactement neuf pièces : plancher, mur gauche, mur du fond, mur droit, plafond, deux piliers de façade, linteau et panneau `SHOP`. L’entrée reste ouverte. Il n’a aucune prétention esthétique.

## 4. Pivot commun

Source de vérité unique : `ItemShopVisualShell.GetPivotCFrame()`, dérivé de `GameConfig` seul.

- Position : `Config.Lobby.ItemShopPosition` = `(34, 0, -230)`
- Yaw : `Config.Lobby.ItemShop.YawDegrees` = `270°`
- Dimensions : `32 × 26 × 15`, entrée `13` studs

La boutique est le **miroir exact du kiosque de vente** par rapport à l’allée centrale du lobby (axe `X = 0`) : `lobbyItemShopOffset` est calculé depuis `lobbySellOffset` et le yaw vaut `sellBoothYawDegrees + 180`. Déplacer le kiosque déplace symétriquement la boutique ; aucune coordonnée de boutique n’est écrite en dur.

| Repère | X | Z |
|---|---|---|
| Kiosque de vente (ouest) | `-34` | `-230` |
| Boutique (est) | `34` | `-230` |
| Emprise boutique + parvis | `[15, 47.5]` | `[-246.5, -213.5]` |
| Passage central (estrade de vente → parvis) | `37.4 studs` | — |

Les deux modèles portent un `PivotAnchor` placé exactement sur ce CFrame, et `ItemShopVisual.PrimaryPart = PivotAnchor`. Donc `ItemShopVisual:GetPivot()` est égal au pivot de configuration.

Attributs de secours posés sur `ItemShopVisual` :

| Attribut | Valeur |
|---|---|
| `ManualDecor` | `true` |
| `BPW_ItemShopVisual` | `true` |
| `BPW_PivotPosition` | `Vector3(34, 0, -230)` |
| `BPW_PivotYaw` | `270` |
| `BPW_ShellVersion` | `1` |

`ItemShopVisual.ModelStreamingMode = Enum.ModelStreamingMode.Atomic` (la place a `StreamingEnabled = true`).

**Migration du pivot.** `ItemShopVisual` vit dans le fichier de place, pas dans les sources Rojo : changer `GameConfig` ne peut pas le déplacer tout seul. `ItemShopVisualShell.EnsureVisualModelPivot()` comble l’écart. Elle compare le pivot réel et les attributs `BPW_PivotPosition` / `BPW_PivotYaw` à la configuration, et ne fait un unique `PivotTo()` rigide que s’ils divergent, puis réécrit les deux attributs. Aucun descendant n’est modifié, supprimé ni recréé, et un second appel ne fait plus rien.

`ItemShopBuilder.Build()` et `BuildGuides()` l’appellent avant de générer les guides, ce qui garantit que modèle visuel et modèle fonctionnel partagent toujours le même pivot.

**Attention** : un déplacement fait en mode Play est perdu à l’arrêt. Après un changement de coordonnées dans `GameConfig`, il faut cliquer **Align ItemShop (Visual + Guides)** en mode Edit puis **sauvegarder la place**, sinon le décor manuel reste à l’ancien emplacement.

Réalignement manuel du seul visuel — barre de commande Studio, mode Edit :

```lua
require(game.ReplicatedStorage.Shared.ItemShopVisualShell).RealignVisualModel()
```

## 5. Protection du décor manuel

Cinq garanties, indépendantes les unes des autres :

1. **Rojo ne gère pas le Workspace.** Dans `default.project.json`, `Workspace` n’a que `$className` et `$properties`, aucun `$path`. Rojo ne synchronise que `ReplicatedStorage.Shared`, `ServerScriptService.Server` et `StarterPlayerScripts.Client`.
2. **`ItemShopBuilder.destroyExisting()`** ignore tout ce que `ItemShopVisualShell.IsProtectedInstance()` déclare protégé : `StudioDecoration`, ses descendants, et toute instance portant `ManualDecor` ou `BPW_ItemShopVisual`.
3. **`ItemShopBuilder` n’obtient jamais de référence en écriture** vers `ItemShopVisual` : il n’appelle que `Shell.IsVisualPresent()`, qui retourne un booléen.
4. **`ZoneService.clearGeneratedChildren()`** contient déjà une garde explicite sur `StudioDecoration`.
5. **Aucun script de Play ne supprime `ItemShopVisual`.** Contrairement à `SummerZonePreview` (supprimé au démarrage par `ZoneService.EnsureWorld()`), `ItemShopVisual` suit le modèle de `SummerZoneDecor` : il reste présent en Play.

`CreateEditableShell()` refuse tout écrasement si le modèle existe déjà, sans modifier un seul descendant :

```
ItemShopVisual already exists. No changes were made.
```

Aucun bouton « Refresh Visual » n’existe et il ne faut pas en créer.

## 6. Outils Studio

Plugin `studio-plugins/LobbyEditingPreview.plugin.lua`, barre d’outils **BubblePopWorld**.

### Create ItemShop Editable Shell

1. Refuse de s’exécuter en Play.
2. Si `ItemShopVisual` existe → arrêt immédiat avec l’avertissement ci-dessus.
3. Crée `Workspace.StudioDecoration` si nécessaire.
4. Crée `ItemShopVisual`, aligné sur le pivot, avec les cinq sections, le `PivotAnchor`, les attributs et `ModelStreamingMode = Atomic`.
5. Pose une coque sobre mais utilisable : plancher, trois murs, plafond, façade en trois pièces avec l’ouverture de 13 studs, panneau d’enseigne, trois socles de présentoir alignés sur les `FocusAnchor`, un luminaire central.

### Create ItemShop Exterior Draft

`ItemShopVisualShell.CreateExteriorDraft()`, mode Edit uniquement, jamais appelé en Play.

1. Refuse de s’exécuter en Play, et refuse de s’exécuter si `ItemShopVisual` est absent.
2. Si `Exterior.ExteriorDraft_v1` existe → arrêt immédiat avec `[ItemShopVisualShell] ExteriorDraft_v1 already exists. No changes were made.` Pour recommencer, supprimer le modèle à la main dans Studio.
3. Sinon crée `ItemShopVisual/Exterior/ExteriorDraft_v1`, aligné sur le pivot commun (toutes les pièces sont posées via `pivotCF * CFrame.new(offset)`, aucune coordonnée mondiale en dur).

Ne touche jamais `Workspace.ItemShop`, ni les guides fonctionnels, ni `Structure`, ni `Interior`, ni `Displays`. Aucun bouton de rafraîchissement n’existe : la façade appartient à Studio dès sa création.

Contenu (83 Parts, 4 `PointLight`, 3 `SurfaceGui`, aucun script) :

```
ExteriorDraft_v1
├── FacadeStructure
│   ├── LeftColumn / RightColumn   ← deux pilastres par côté : base, fût, chapiteau, filet cyan
│   ├── UpperBand                  ← bandeau deux couches, retrait central, corniche, filet doré
│   ├── EntranceFrame              ← montants, linteau, encadrement en retrait, bordure cyan
│   └── ArchitecturalTrims         ← épaulements, retours de corniche, ailerons d'enseigne (inclinés)
├── ShopSign                       ← BackPlate, OuterFrame, CyanTrim (4 barres), InnerPanel, TextSurface, BagIcon
├── SkillsWindow                   ← Frame, Glass, InteriorBox, Pedestal, AccentLighting, SkillSymbol, LabelPlate
├── CosmeticsWindow                ← idem, accents violet / rose
├── EntranceDecor                  ← Forecourt, Threshold, ThresholdGlow, LeftPost, RightPost
└── ExteriorLighting               ← EntranceLightHost, SignLightHost
```

Règles vérifiées par `ItemShopVisualTests` : hiérarchie complète, 60 à 100 Parts, au plus 4 lumières et 3 `SurfaceGui`, une seule vitre par vitrine, `Neon` réservé aux accents fins (épaisseur ≤ 0,4 stud), symétrie gauche / droite, emprise dans `Width/2 + ExteriorSideOverhang` et dans le parvis, couloir d’entrée de 13 studs entièrement libre sur les 6 studs de parvis, parvis collisionnable, seuil et vitres traversants.

L’ancien `Exterior/ShopSign/SignBoard` de la coque initiale reste en place mais se retrouve entièrement masqué derrière la nouvelle enseigne et le bandeau ; il peut être supprimé à la main.

### Polish ItemShop Exterior

`ItemShopVisualShell.PolishExteriorDraftV1()`, mode Edit uniquement. Retouche la façade existante au lieu de la reconstruire.

1. Refuse de s’exécuter en Play.
2. Si `ExteriorDraft_v1` est absent → `[ItemShopVisualShell] ExteriorDraft_v1 not found. No changes were made.`
3. Si l’attribut `BPW_ExteriorPolishVersion` vaut déjà 1 → `[ItemShopVisualShell] Exterior polish version 1 is already applied. No changes were made.`
4. Sinon applique 79 retouches et ajoute 20 pièces, puis pose `BPW_ExteriorPolishVersion = 1`.

Aucune suppression, aucune reconstruction : les retouches ne changent que `Size`, la position (l’orientation d’origine est conservée), `Color`, `Material`, `Transparency` et les réglages de `PointLight`. Une retouche dont la cible a été supprimée ou renommée à la main est ignorée avec un avertissement, sans interrompre le reste.

Contenu du polish v1 :

| Zone | Retouches | Ajouts |
|---|---|---|
| Enseigne | 22,5 × 6,0 studs (+25 % / +20 %), descendue à `y = 19`, avancée devant la corniche, cadre cyan trois fois plus épais, panneau intérieur bleu-gris, texte agrandi, sac +35 % intégré au bord haut | — |
| Volumes | quatre valeurs distinctes : `NavyDeep` → `Navy` → `Panel` → `Steel` → `PanelSoft`, jamais deux couches adjacentes identiques | — |
| Entrée | montants et linteau éclaircis, bordure cyan de 0,14 → 0,26 stud | soffite clair, deux tableaux intérieurs bleu-gris, nappe chaude au sol, deux filets dorés |
| Vitrines | cadre affiné (0,7 → 0,5), ouverture 5,7 × 6,8 studs, fond `WindowBack`, podium et symboles +35 % | contour d’accent quatre barres par vitrine, halo de podium |
| Accents dorés | filet de corniche 0,14 → 0,30 stud | quatre bandeaux dorés sur les pilastres |
| Éclairage | entrée chaude 0,9 / 15, enseigne blanc-cyan 0,45 / 11, vitrines 0,5 / 9 | aucune nouvelle lumière |

Total après polish : **103 Parts, 4 lumières, 3 SurfaceGui, 2 vitres**. Le couloir de 13 studs et les 6 studs de parvis restent entièrement libres ; les ajouts sont tous `CanCollide = false`.

### Create ItemShop Interior Draft

`ItemShopVisualShell.CreateInteriorDraft()`, mode Edit uniquement.

1. Refuse de s’exécuter en Play, et refuse si `ItemShopVisual` est absent.
2. Si `Interior.InteriorDraft_v1` existe → `[ItemShopVisualShell] InteriorDraft_v1 already exists. No changes were made.`
3. Sinon crée `ItemShopVisual/Interior/InteriorDraft_v1`, posé sur le même pivot que la façade.

Ne touche ni à `ExteriorDraft_v1`, ni à `Structure`, ni à `Workspace.ItemShop`.

Contenu (128 Parts, 6 `PointLight`, 3 `SurfaceGui`, aucun script) :

```
InteriorDraft_v1
├── Floor              ← dalle de base collisionnable, 4 grandes dalles teintées,
│                        5 joints, médaillon circulaire devant ITEMS, 2 filets d'accent
├── Ceiling            ← panneau, cadre périphérique, 3 caissons, 3 lignes douces
├── EntryTransition    ← soffite clair, panneaux latéraux, bande au sol, lumière chaude
├── SkillsSection      ← WallPanels, Header, MainDisplayBackdrop, deux niches,
│                        SkillSymbols, AccentLights, MainPodium (cyan)
├── ItemsSection       ← idem + CentralArch, accents dorés, socle plus imposant
├── CosmeticsSection   ← miroir de Skills, accents violet / rose
├── CentralDecor       ← deux banquettes collisionnables, hors des axes de caméra
└── InteriorLighting   ← deux plafonniers blanc chaud
```

Les trois `MainPodium` sont centrés exactement sur `GetDisplayCenters()`, donc sur les `FocusAnchor` de `Display_*`, et recouvrent les socles simples de la coque initiale (qui peuvent être supprimés à la main).

Règles vérifiées par les tests : hiérarchie complète, 100 à 160 Parts, 6 à 8 lumières, 3 à 6 `SurfaceGui`, aucun script, couloir central de 13 studs libre depuis l’entrée jusqu’au socle ITEMS, entrée dégagée, sol plat (rien au-dessus de `y = 1,3` dans `Floor`), tout le décor contenu entre les murs et sous le plafond, collisions limitées au sol et aux banquettes, banquettes à plus de 6 studs de chaque prompt, symétrie stricte Skills / Cosmetics, et surtout **aucun élément sur les trois segments caméra → présentoir**.

`GetCameraRays()` recalcule les axes validés (distance 8,8 / 10, hauteur 5,4 / 5,7, cible à 3,3 studs) à partir de `GetDisplayCenters()`, tronqués 2,2 studs avant la cible pour laisser l’objet exposé occuper le cadre. `ItemShopBuilder` reste seul propriétaire des `CameraPoint_*` réels.

### Align ItemShop (Visual + Guides)

Appelle `ItemShopBuilder.BuildGuides()` (mode Edit uniquement). Deux effets, dans cet ordre :

1. `EnsureVisualModelPivot()` déplace `ItemShopVisual` en bloc si son pivot diverge de `GameConfig` — un seul `PivotTo()`, aucun descendant touché.
2. Reconstruit `Workspace.ItemShop` avec uniquement les repères fonctionnels, rendus visibles et sélectionnables (`Transparency = 0.6`, couleur par catégorie, `CanCollide = false`).

C’est le bouton à utiliser après tout changement de position dans `GameConfig` : il garantit que visuel et fonctionnel repartent du même pivot. **Sauvegarder la place ensuite.** En Play, `Build()` détruit ces guides et les recrée entièrement invisibles.

### Realign ItemShop Visual Only

Appelle `ItemShopVisualShell.RealignVisualModel()` : force le `PivotTo()` du seul modèle visuel, sans toucher à `Workspace.ItemShop`. Utile si le pivot a été bougé par accident dans Studio.

## 7. Collisions

| Élément | `Anchored` | `CanCollide` | `CanTouch` | `CanQuery` | `Transparency` |
|---|---|---|---|---|---|
| `ItemShopVisual` — plancher, murs, façade | `true` | `true` | `false` | `true` | libre |
| `ItemShopVisual` — plafond | `true` | `false` | `false` | `false` | libre |
| `ItemShopVisual` — décoration | `true` | `false` | `false` | `false` | libre |
| `Workspace.ItemShop` en mode Studio-first | `true` | `false` | `false` | `false` | `1` |
| `FallbackShell` (visuel absent seulement) | `true` | `true` (sauf plafond) | `false` | `true` | `0` |

Aucun doublon de collision possible : la structure collisionnable vient soit d’`ItemShopVisual`, soit du `FallbackShell`, jamais des deux. L’ouverture d’entrée (13 studs de large, 10 studs de haut) ne contient aucun élément collisionnable ; un test automatisé le vérifie.

## 8. Ce qui vient d’où

| Origine | Contenu | Reconstructible |
|---|---|---|
| **Rojo** | `src/Shared`, `src/Server`, `src/Client` | oui, à chaque sync |
| **Code (Play)** | `Workspace.ItemShop` et tout son contenu | oui, à chaque démarrage |
| **Code (Edit, bouton)** | coque initiale `ItemShopVisual`, une seule fois | non — jamais régénérée |
| **Studio (manuel)** | toute la décoration sous `ItemShopVisual` | **jamais** — à ne jamais supprimer |

Les modifications faites dans Studio vivent dans le fichier de place `.rbxl` et dans la place publiée. **Il faut sauvegarder la place après chaque session de décoration** ; Rojo ne les sauvegarde pas.

## 9. Fichiers

```
src/Shared/ItemShopVisualShell.lua   — pivot, modes, spec de coque, spec de façade, commandes Studio
src/Shared/ItemShopVisualTests.lua   — tests purs
src/Shared/GameConfig.lua            — UseStudioVisual, VisualModelName, StudioDecorationRoot, ShellVersion
src/Server/ItemShopBuilder.lua       — repères fonctionnels, protections, guides Edit, FallbackShell
src/Shared/ShopViewportModels.lua    — specs des modèles de preview + construction client
src/Shared/ShopViewportModelsTests.lua — tests purs des previews
src/Shared/ShopBrowseLayout.lua      — dispositions Mobile / Desktop / Console (nombres purs)
src/Shared/ShopBrowseLayoutTests.lua — tests purs des dispositions
src/Client/ShopUI.lua                — rendu du ViewportFrame et application des dispositions
studio-plugins/LobbyEditingPreview.plugin.lua — cinq boutons boutique
tools/run_itemshop_visual_tests.py   — tests de la spec partagée
tools/run_itemshop_builder_tests.py  — tests structurels du modèle fonctionnel
tools/run_shop_viewport_tests.py     — tests des modèles de preview
tools/run_shop_layout_tests.py       — tests des dispositions responsive
tools/test_itemshop_visual.lua       — harnais spec
tools/test_itemshop_builder.lua      — harnais Instance / Workspace simulé
tools/test_shop_viewport.lua         — harnais previews
tools/test_shop_layout.lua           — harnais dispositions
```

`ItemShopBuilder.lua` fait 525 lignes après l’Étape 2, contre 1 715 avant la conversion. Le modèle fonctionnel contient 11 pièces invisibles, contre environ 170 auparavant.

Intouchés : `ShopService.lua`, `ShopCatalog.lua`, `Remotes.lua`, `SellKioskBuilder.lua`, `ZoneService.lua`, `ZoneBuilder.lua`. `ShopUI.lua` n’est modifié que pour l’affichage des previews (section 11) et la disposition responsive (section 12) : aucune logique fonctionnelle touchée.

Le cadrage caméra validé, le masquage local de l’avatar et `ExitBrowse()` ne sont modifiés à aucun moment. En mode Studio-first, `Display_*.PrimaryPart` (le `FocusAnchor`) reprend exactement la position de l’ancien `Base` de présentoir, ce qui préserve le `lookAt` de `ShopUI`.

## 10. Migration

**Étape 1 (faite).** Outillage complet, `UseStudioVisual = false`, décor procédural intégralement conservé. Aucun changement visuel. Validé dans Studio : création de la coque, refus d’écrasement, survie à un cycle Play → Stop.

**Étape 2 (faite).** `UseStudioVisual = true` et suppression de toute la génération décorative : façade, vitrines, murs visuels, plafond, plancher visuel, éclairage, podiums, objets de présentation, corniches et anneaux lumineux. `Workspace.ItemShop` ne contient plus que `PivotAnchor`, `Entrance`, les trois `PromptAnchor_*`, les trois `CameraPoint_*` et les trois `Display_*`.

**Étape 3 — façade (faite).** `CreateExteriorDraft()` et son bouton produisent `Exterior/ExteriorDraft_v1` : façade à plusieurs profondeurs, enseigne SHOP multicouche avec icône de sac, deux vitrines décoratives encastrées, parvis et bornes, quatre lumières. Créée une seule fois en Edit, puis entièrement modifiable à la main.

**Étape 3b — polish de façade (faite).** `PolishExteriorDraftV1()` et son bouton appliquent une passe de finition versionnée sur `ExteriorDraft_v1` : enseigne agrandie et descendue, hiérarchie de valeurs entre les couches, entrée éclaircie, vitrines élargies, accents dorés épaissis, éclairage adouci. Idempotent grâce à `BPW_ExteriorPolishVersion`.

**Étape 4 — intérieur (faite).** `CreateInteriorDraft()` et son bouton produisent `Interior/InteriorDraft_v1` : sol à grandes dalles avec médaillon, plafond structuré, transition d’entrée éclairée, trois sections murales complètes avec podiums à quatre niveaux, décor central et éclairage général. Créé une seule fois en Edit, puis modifiable à la main.

**Étape 5 — visuels des produits (faite).** Voir la section 11. Aucun changement dans `Workspace.ItemShop`, `ItemShopVisual` ni dans la logique d’achat.

**Étape 6 — disposition console (faite).** Voir la section 12. Ajout d’une ten-foot UI pour les joueurs à la manette sur grand écran, sans toucher aux dispositions Desktop et Mobile validées.

**Suite (non commencée).** Objets décoratifs des podiums alignés sur les modèles de preview, puis refonte de `ShopUI`.

## 11. Visuels des articles (browse UI)

`src/Shared/ShopViewportModels.lua` décrit chaque article du catalogue sous forme de spec pure : une liste de pièces (taille, décalage, rotation, couleur, matériau, forme, transparence) autour de l’origine, plus une couleur d’accent. Le module est purement visuel : il ne lit pas le Workspace, n’écrit rien dedans, ignore prix, niveaux et états d’achat, et n’ouvre aucun remote. `ShopUI` appelle `Build()` côté client pour peupler le `ViewportFrame` du browse.

**Modèles dédiés (18, tout le catalogue).** Skills : `Speed` (botte ailée), `Jump` (botte à ressort), `Power` (gantelet), `CoinMult` (pile de pièces), `Magnet` (aimant en U), `Luck` (trèfle), `CapacityBoost` (caisse fléchée). Items : `BackpackGold`, `BackpackEmerald`, `BackpackNeon` (même silhouette de sac, trois palettes), `Hammer`, `Pin`, `MultiPopTool`, `SpecialTool`. Cosmetics : `Cap`, `Hat`, `Vest`, `Shirt`, `Accessory`.

**Replis par famille.** `Skill`, `Item`, `Cosmetic`, `Tool` : socle, halo néon et cœur coloré. Résolus par `Type` puis par catégorie, jamais par une forme nue.

**Cadrage.** `GetBounds()` calcule la boîte englobante en tenant compte des rotations, puis le rayon de la sphère qui contient le modèle sous tous les angles de rotation. `GetCameraDistance()` en déduit une distance qui remplit le cadre avec 12 % de marge, et `GetCameraCFrame()` place la caméra en trois-quarts légèrement plongeant (lacet −26°, site +16°). Le modèle est recentré sur l’origine à la construction, donc la rotation lente du browse ne le décadre jamais.

**Budget.** Quatre à huit pièces par article, 122 au total, aucune pièce au-delà de 3,2 studs, aucun script, aucun asset externe, aucune texture.

**Fond : deux couches distinctes.** Un `UIGradient` enfant d’un `ViewportFrame` multiplie l’image 3D rendue, pas seulement le fond — un dégradé sombre écrase donc tout le modèle, y compris les pièces blanches. Le dégradé décoratif vit sur un `Frame` `PreviewBackground` placé derrière (`ZIndex` 3, mêmes coins arrondis, `GetBackground()` : Skills `38,58,82 → 20,32,50`, Items `52,55,72 → 28,31,45`, Cosmetics `48,50,82 → 26,28,49`). Le `ViewportFrame` est posé dessus (`ZIndex` 4, 3 px de marge) avec un fond **uni et opaque** issu de `GetViewportBackground()` : Skills `52,72,96`, Items `68,66,78`, Cosmetics `62,62,92`. Le fond n’est jamais transparent, ce qui assombrirait le rendu et ajouterait un contour noir.

**Éclairage.** `GetLighting()` renvoie l’ambiante, la couleur et la direction de la clé. Un `ViewportFrame` n’accepte qu’une seule lumière directionnelle, constante ici (`-1, -1, -1`, avant-haut-droite) ; le remplissage latéral et le débouchage des ombres passent par une ambiante haute (`205,215,230` à `212,210,222`, luminance 0,75 à 0,92), et la séparation d’avec le fond par le halo plutôt que par une contre-lumière réelle. La couleur de clé reste quasi neutre (`255,250,242`) pour ne pas dénaturer les objets.

**Halo et socle.** `GetBackdropSpec()` / `BuildBackdrop()` produisent quatre disques dans un `Model` distinct qui ne tourne pas avec l’article : `Halo` et `HaloCore` derrière l’objet, face à la caméra, teintés catégorie ; `Socle` bleu-gris neutre sous l’objet et `SocleRing` néon teinté catégorie. Tous les diamètres sont bornés par le cadre calculé par `GetCameraDistance()`, donc l’ajout du fond ne change ni la caméra ni la taille apparente de l’objet.

**Tons sombres relevés.** Les entrées de palette quasi noires ont été éclaircies sans changer d’identité : `SlateDark 44,57,80 → 62,80,110`, `Navy 28,37,56 → 50,66,96`, `WoodDark 108,74,44 → 128,92,56`, `Slate 74,92,120 → 86,106,136`. Articles concernés : `Speed`, `Jump`, `Hat`, `BackpackNeon`, `MultiPopTool`, `SpecialTool`, `CapacityBoost`, `Hammer`. Les tests imposent désormais une luminance minimale de 0,20 par pièce et un écart d’au moins 0,08 avec le bas du dégradé.

**Côté `ShopUI`.** Seul l’affichage change : cadre de 116 px composé du `PreviewBackground` dégradé et du `ViewportFrame` posé dessus, fond uni et éclairage repris de la catégorie courante, caméra à 40° de champ, modèle et halo reconstruits uniquement quand l’article ou la catégorie change, rotation lente appliquée au seul modèle d’article, nettoyage dans `ExitBrowse()`. Le flux du browse, les états de bouton, les remotes et la logique d’achat sont inchangés.

Tests : `tools/run_shop_viewport_tests.py` (couverture du catalogue, budget, contraste avec le fond, luminance minimale, fonds et éclairages par catégorie, halo et socle dans le cadre, cadrage, replis, cohérence des trois sacs). Le harnais injecte la source de `ShopUI.lua` pour vérifier statiquement qu’aucun `UIGradient` n’est enfant du `ViewportFrame`, que le fond uni vient bien du module, et qu’aucun code de diagnostic ne subsiste.

## 12. Disposition responsive du browse (Mobile / Desktop / Console)

`src/Shared/ShopBrowseLayout.lua` décrit les trois dispositions du panneau de browse sous forme de nombres purs : aucune Instance, aucun accès au Workspace, aucune connaissance des prix, des états de bouton ou des remotes. `ShopUI` construit l’interface une seule fois, puis `applyResponsiveBrowseLayout()` écrit les propriétés de la disposition active.

**Détection.** `ResolveMode(preferredInput, viewportSize, touchEnabled)` renvoie `Console` quand `UserInputService.PreferredInput` vaut `Gamepad` **et** que le viewport fait au moins 1 200 × 650, `Mobile` quand l’entrée préférée est tactile, `Desktop` sinon. `GuiService:IsTenFootInterface()` n’est pas utilisé. Une manette sur petit écran reste en Desktop. Si le client n’expose pas `PreferredInput` (lecture protégée par `pcall`), le repli est `TouchEnabled`, ce qui reproduit exactement le comportement précédent.

**Réévaluation.** Le layout est recalculé sur `PreferredInput`, `ScreenGui.AbsoluteSize`, `Workspace.CurrentCamera`, `Camera.ViewportSize`, branchement et débranchement de manette. Un verrou `layoutPending` avec 100 ms de temporisation absorbe les rafales, et une mémoïsation mode + taille évite toute écriture quand rien ne change. Le changement de disposition n’appelle jamais `updatePresentation`, `ShopViewportModels.Build` ni `clearPreview` : le modèle 3D, sa rotation et son cadrage survivent au basculement, la boutique ne se ferme pas et l’article sélectionné ne change pas. Un test statique sur la source de `ShopUI` interdit ces appels dans le corps de la fonction.

**Mobile et Desktop.** Les deux dispositions sont figées sur les valeurs validées, aujourd’hui identiques : panneau `0.9` de large × 190 px, contraint entre 300 × 190 et 640 × 220, preview 116 px, nom 18, description 13, prix 14, flèches 56, bouton 168 × 40, fermeture 40. Les tests comparent chaque champ à une valeur littérale et vérifient que Mobile est structurellement identique à Desktop.

**Console.** Panneau `UDim2.fromScale(0.72, 0.33)`, ancré en bas au centre à `0.93` de la hauteur, contraint entre 900 × 300 et 2 900 × 760 : au moins 7 % de marge basse et 14 % de marge latérale, donc aucun contrôle dans la zone d’overscan. Toutes les valeurs internes sont exprimées dans le repère 1920 × 1080 puis multipliées par l’échelle réellement obtenue (hauteur du panneau ÷ 344), ce qui garantit qu’elles ne débordent jamais du panneau même quand la contrainte de taille s’applique.

| Écran | Panneau | Preview | Nom | Desc. | Prix | Flèches | Bouton | Fermeture |
|---|---|---|---|---|---|---|---|---|
| 1280 × 720 | 921 × 300 | 262 × 224 | 30 | 21 | 26 | 72 | 227 × 63 | 63 |
| 1920 × 1080 | 1382 × 344 | 300 × 257 | 34 | 24 | 30 | 82 | 260 × 72 | 72 |
| 2560 × 1440 | 1843 × 463 | 404 × 344 | 46 | 32 | 40 | 110 | 350 × 97 | 97 |
| 3840 × 2160 | 2764 × 700 | 611 × 521 | 69 | 49 | 61 | 167 | 530 × 147 | 147 |

Composition console : header (catégorie, compteur, solde, fermeture), puis flèche gauche, preview dominante, colonne texte nom / description / prix, bouton principal aligné sous la colonne texte, flèche droite. La preview passe de 116 × 116 à 300 × 257 à 1080p, soit environ 5,7 fois la surface. Les tailles de texte restent explicites plutôt que `TextScaled`, ce qui évite des tailles différentes d’un article à l’autre ; les planchers de lisibilité (nom ≥ 28, description ≥ 20, prix ≥ 24, flèches ≥ 68, fermeture ≥ 60, bouton ≥ 210 × 60) sont vérifiés à chaque résolution testée.

**Navigation manette.** Les quatre boutons sont sélectionnables et forment un graphe fermé : flèche gauche ↔ bouton principal ↔ flèche droite, fermeture accessible vers le haut depuis les trois, et retour au bouton principal vers le bas. Les directions bloquées pointent sur le bouton lui-même, donc la sélection ne sort jamais du panneau. À l’ouverture en mode Console, le focus va au bouton principal s’il est actif, sinon à la flèche suivante, sinon à la fermeture ; une sélection posée sur un bouton devenu non sélectionnable est réaffectée. Les flèches deviennent non sélectionnables quand la catégorie n’a qu’un article. Les raccourcis existants sont conservés (D-pad, `ButtonB`, Échap) et `ButtonL1` / `ButtonR1` changent d’article directement. Aucun curseur virtuel n’est requis. Un `UIStroke` blanc discret apparaît sur le bouton sélectionné via `SelectionGained` / `SelectionLost`, sans animation.

Fichiers : `src/Shared/ShopBrowseLayout.lua`, `src/Shared/ShopBrowseLayoutTests.lua`, `src/Client/ShopUI.lua`, `tools/run_shop_layout_tests.py`, `tools/test_shop_layout.lua`. Tests : `python tools\run_shop_layout_tests.py` (choix du mode, immuabilité de Desktop et Mobile, encombrement et absence de débordement aux quatre résolutions, planchers de lisibilité, cibles 1080p, proportionnalité en 4K, câblage et absence d’effets de bord dans `ShopUI`).
