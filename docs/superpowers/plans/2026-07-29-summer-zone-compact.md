# Summer Zone Compact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Réduire la Summer Zone à 120 × 180 studs, conserver son entrée centrée et adapter sa grille, ses structures, ses lumières et sa preview.

**Architecture:** Un nouveau module `SummerZoneConfig` porte toutes les constantes géométriques propres à la zone. `ZoneDefs` calcule un layout Summer autonome ; les builders runtime, la preview, les lumières et le transit consomment ce layout commun.

**Tech Stack:** Roblox Luau strict, Rojo, tests intégrés exécutés au démarrage serveur.

## Global Constraints

- Summer Zone : largeur Z 120, profondeur X 180.
- Bord d’entrée ouest X = 168 et axe Z = 0.
- BubbleBoard : 23 × 12, espacement 6 et bulles 5,4 × 2 × 5,4 inchangés.
- Ne jamais supprimer ou reconstruire `Workspace/StudioDecoration/SummerZoneDecor`.
- Ne modifier ni économie, ni niveaux, ni sauvegardes, ni thème.
- Ne pas publier le jeu.

---

### Task 1: Configuration et géométrie centrale

**Files:**
- Create: `src/Shared/SummerZoneConfig.lua`
- Modify: `src/Shared/ZoneAccessTests.lua:35-88`
- Modify: `src/Shared/ZoneDefs.lua:34-153,202-230,278-346`

**Interfaces:**
- Produces: `SummerZoneConfig` et `ZoneDefs.GetSummerBridgeLayout()` avec `Ex = 90`, `Ez = 60`, `BubbleColumns = 23`, `BubbleRows = 12`.
- Consumes: `GameConfig.Grid`.

- [ ] **Step 1: Écrire les assertions qui décrivent la nouvelle géométrie**

Ajouter aux tests :

```lua
check(L.OuterWidth == 180, "Summer profondeur X = 180")
check(L.OuterDepth == 120, "Summer largeur Z = 120")
check(L.BubbleColumns == 23, "BubbleColumns = 23")
check(L.BubbleRows == 12, "BubbleRows = 12")
check(math.abs(layout.SummerEdgeX - 168) < 1e-6, "bord entrée X = 168")
check(math.abs(layout.ArchZ) < 1e-6, "entrée centrée Z = 0")
```

- [ ] **Step 2: Vérifier que les anciennes constantes ne satisfont pas les nouveaux tests**

La suite Studio actuelle doit signaler les dimensions 240 × 240 et la grille 33 × 32.

- [ ] **Step 3: Ajouter la configuration Summer dédiée**

```lua
--!strict
return {
	ZoneWidth = 120,
	ZoneDepth = 180,
	SideDecorMargin = 16,
	EntranceDecorMargin = 14,
	RearDecorMargin = 24,
	BubbleRowReduction = 2,
	LightPerimeterSpacing = 30,
	EntryCenterOffset = 0,
}
```

- [ ] **Step 4: Découpler les demi-emprises Summer de la grille Classic**

Dans `ZoneDefs`, calculer :

```lua
local SUMMER_HALF_X = SummerZoneConfig.ZoneDepth / 2
local SUMMER_HALF_Z = SummerZoneConfig.ZoneWidth / 2
local classicEastEdge = classicOrigin.X + OUTER_HALF_X
local summerZoneOrigin = Vector3.new(
	classicEastEdge + INTER_ZONE_GAP + SUMMER_HALF_X,
	classicOrigin.Y,
	classicOrigin.Z + SummerZoneConfig.EntryCenterOffset
)
```

Faire retourner les demi-emprises Summer par `GetOuterHalfExtent("SummerZone")` et `GetOuterPlayExtent("SummerZone")`, sans changer celles de Classic. Dériver le board depuis les marges et conserver l’ancrage côté entrée.

- [ ] **Step 5: Vérifier la géométrie calculée**

Résultats attendus au démarrage Studio : tests de zone verts, emprise 180 × 120, grille 23 × 12, entrée X = 168/Z = 0.

### Task 2: Structures runtime, accès et preview

**Files:**
- Modify: `src/Server/ZoneBuilder.lua:158-238,241-435`
- Modify: `src/Shared/SummerZoneEditingPreview.lua:113-286`
- Modify: `src/Shared/TravelConfigTests.lua:78-97`

**Interfaces:**
- Consumes: le layout Summer de Task 1.
- Produces: Floor, Bounds, ZoneTrigger, LevelGate, pont, arrivée et preview cohérents.

- [ ] **Step 1: Renforcer les tests d’alignement**

```lua
check(math.abs(bridgeCF.Position.Z) < 0.05, "Summer pad centré sur Z = 0")
check(math.abs(layout.ZoneOrigin.Z - layout.ArchZ) < 0.05, "arche centrée")
check(math.abs(layout.SummerEdgeX - 168) < 0.05, "pont rejoint le bord conservé")
```

- [ ] **Step 2: Faire consommer les dimensions Summer au builder**

Utiliser `GetOuterHalfExtent("SummerZone")` pour Floor et Trigger, et `layout.Ex/layout.Ez` pour les murs. Garder `GateX`, `ArchX`, `MidX` et le point d’arrivée dérivés de `SummerEdgeX`/`ArchZ`.

- [ ] **Step 3: Aligner exactement la preview sur le runtime**

Le preview Floor reprend la taille runtime :

```lua
Size = Vector3.new(layout.Ex * 2 + 4, 1.4, layout.Ez * 2 + 4)
```

Ajouter aux attributs de preview `ZoneWidth`, `ZoneDepth` et `EntryCenterOffset`. Conserver les créations/suppressions limitées à `SummerZonePreview`.

- [ ] **Step 4: Vérifier la préservation du décor**

Confirmer par inspection que `EnsureSummerZoneDecor` ne détruit aucun enfant et que `RemoveSummerZonePreview` ne cible que `SummerZonePreview`.

### Task 3: Périmètre lumineux compact

**Files:**
- Modify: `src/Shared/SummerZoneStringLightsTests.lua:21-100`
- Modify: `src/Shared/SummerZoneStringLights.lua:25-39,527-581`

**Interfaces:**
- Consumes: `SummerZoneConfig.LightPerimeterSpacing` et le layout compact.
- Produces: points de poteaux et segments de guirlandes adaptés aux bounds 180 × 120.

- [ ] **Step 1: Ajouter les assertions de configuration et de bounds**

```lua
check(Lights.POST_SPACING == 30, "espacement centralisé = 30")
check(layout.Ex == 90 and layout.Ez == 60, "périmètre compact 180x120")
```

Conserver les assertions existantes : aucun poteau sur le board ou dans l’entrée, Y au sol, attache haute, courbe descendante et point bas 7–9 studs.

- [ ] **Step 2: Centraliser l’espacement**

Remplacer la constante locale 30 par `SummerZoneConfig.LightPerimeterSpacing`, tout en continuant d’exposer `POST_SPACING` pour les tests.

- [ ] **Step 3: Vérifier le recalcul automatique**

`ComputePerimeterPoints(layout)` doit répartir ses points sur `layout.Ex/layout.Ez`, exclure le gap d’entrée et rester sous `MAX_POSTS`. Aucun offset propre à l’ancienne emprise 240 × 240 ne doit subsister.

### Task 4: Consommateurs secondaires et vérification finale

**Files:**
- Inspect: `src/Shared/SummerFireworksConfig.lua`
- Inspect: `src/Shared/EnvironmentBackdropBuilder.lua`
- Inspect: `src/Server/ZoneService.lua`
- Inspect: `studio-plugins/LobbyEditingPreview.plugin.lua`

**Interfaces:**
- Consumes: bounds/layout Summer centralisés.
- Produces: décor généré et exclusion d’horizon compatibles avec la nouvelle zone.

- [ ] **Step 1: Éliminer les anciennes dépendances implicites 240 × 240**

Confirmer que les feux d’artifice consomment déjà `GetSummerBridgeLayout`, que l’exclusion du backdrop et la résolution d’aire consomment déjà `GetZoneBounds`, et que le plugin ne contient aucune dimension. Ces fichiers ne doivent pas être modifiés. Ne pas ajouter de montagne verte.

- [ ] **Step 2: Exécuter les validations**

```powershell
rojo build -o BubblePopWorld.rbxlx
```

Résultat attendu : code de sortie 0. Démarrer ensuite une session serveur Studio reliée à Rojo et vérifier les sorties :

```text
[ZoneAccessTests] OK
[SummerZoneStringLightsTests] OK
[TravelConfigTests] OK
```

- [ ] **Step 3: Rafraîchir les artefacts Studio**

Le plugin ne change pas et ne doit pas être recopié. Connecter Rojo, cliquer **Create/Refresh Summer Preview**, puis **Refresh Summer String Lights**. Ne pas publier.
