# Design — Import sécurisé des décors Summer Zone

**Date :** 2026-07-31  
**Projet :** Bubble Pop Simulator (`BubblePopWorld`)  
**Approche retenue :** modules Shared (config + sécurité + importer) + plugin Studio mince

## 1. Objectif

Traiter tous les assets décoratifs Summer (nouveaux props + poteaux/guirlandes) comme **non fiables** :

1. Import uniquement en **mode Edit Studio** vers une quarantaine.
2. Rejet total si code exécutable détecté.
3. Reconstruction par **liste blanche** (jamais le modèle original « nettoyé »).
4. Approbation manuelle d’une **révision précise** (empreinte) avant usage.
5. Générateurs (dont `SummerZoneStringLights`) ne consomment que le cache approuvé persistant.

Aucun chargement d’asset Marketplace pendant une partie publiée. Aucun retéléchargement automatique d’un asset manquant sous prétexte que son ID est approuvé.

## 2. Architecture

```
src/Shared/SummerDecorConfig.lua       — source de vérité Rojo (IDs, sécurité, placement)
src/Shared/SummerDecorSecurity.lua     — scan, reject, whitelist rebuild, validation finale
src/Shared/SummerDecorAssetImporter.lua— orchestration Studio (import → pending ; promote)
src/Shared/SummerZoneStringLights.lua  — lit templates depuis cache approuvé uniquement
assets/summer-decor/*.rbxm             — cache approuvé versionné (persistant)
studio-plugins/LobbyEditingPreview.plugin.lua — Import / Preview (ViewportFrame) / Promote / Lights
```

### 2.1 Dossiers ServerStorage (runtime Studio)

| Dossier | Persistance | Rôle |
|---|---|---|
| `SummerDecorQuarantine` | Éphémère, non versionné | Import brut temporaire ; **toujours vide** en fin d’opération |
| `SummerDecorPendingApproval` | Éphémère, non versionné | Copies nettoyées en attente de revue / promotion |
| `SummerDecorAssets` | **Persistant** (voir §8) | Copies nettoyées **promues** ; source unique pour les générateurs |

Interdit d’importer directement dans : `Workspace`, `ReplicatedStorage`, `ServerScriptService`, `StarterPlayer`, `StarterGui`, ou tout dossier du jeu publié.

## 3. SummerDecorConfig (source de vérité)

Fichier unique versionné. Contient :

- `Assets` — catégories → listes d’IDs **candidats**
- `ApprovedAssetIds` — `{ [assetId] = true }` : autorise l’**usage** d’un ID après promotion d’une révision revue. **Ne valide jamais** automatiquement toutes les versions futures Marketplace.
- IDs guirlandes / poteaux (via `Assets.StringLightPosts` / `Assets.StringLights`)
- catégories d’assets
- paramètres de placement (périmètre lumières, etc.)
- `Security` :

```lua
SummerDecorConfig.Security = {
	RejectAssetsContainingScripts = true,
	RequireManualApproval = true,
	SanitizerVersion = 1, -- bump si la whitelist / règles changent
}
```

### 3.1 Candidats initiaux

```lua
SummerDecorConfig.Assets = {
	StringLightPosts = { 18953379883 },
	StringLights = { 93169410099587 },
	PalmTrees = { 762353835 },
	Rocks = { 4453595550, 16810807451 },
	TropicalPlants = { 101615260056563, 121730956352570 },
	Parasols = { 898706770, 140479009547664 },
	LoungeChairs = { 962686574 },
	Surfboards = { 5561729910, 5295475675, 132165054275404 },
	BeachBalls = { 12355957802, 735737347 },
	Sandcastles = { 89138199 },
	BeachProps = { 4757336022, 5633800112 },
	TikiLights = { 9560932611 },
}

SummerDecorConfig.ApprovedAssetIds = {}
```

`SummerZoneStringLights` ne conserve plus d’IDs en dur : lecture depuis `SummerDecorConfig`.

## 4. Précondition Edit obligatoire

Toute action **Import**, **Preview** ou **Promote** exige :

```lua
RunService:IsStudio() and RunService:IsEdit()
```

Ne pas utiliser `not RunService:IsRunning()` : une simulation mise en pause peut avoir `IsRunning() == false` sans être en mode Edit.

Hors Edit → échec immédiat + warn, aucune mutation.

## 5. Pipeline d’import (Edit uniquement)

Pour chaque ID candidat :

1. Vérifier précondition Edit (§4).
2. **Load** : `AssetService:LoadAssetAsync(assetId)` uniquement ; parent sous `ServerStorage/SummerDecorQuarantine`. Conserver le modèle chargé avec `Sandboxed = true` ; ne jamais lui accorder de capacités de script. Le modèle reste en quarantaine pendant toute l’analyse ; jamais exécuté, activé, ni déplacé dans `Workspace`.
3. Compter les instances d’origine ; log `Scanning asset: ID`.
4. **Scan scripts** : si ≥ 1 `Script` / `LocalScript` / `ModuleScript` → rejet total (ne pas stripper pour accepter le reste). Logger chaque chemin, détruire la quarantaine de cet ID, continuer.
5. **Rebuild whitelist** (§7) → nouveau `Model` vide ; recopier uniquement les objets / propriétés autorisés.
6. Attributs **contrôlés uniquement** (aucun attribut / tag original) :

```lua
CleanModel:SetAttribute("AssetId", assetId)
CleanModel:SetAttribute("SanitizedSummerAsset", true)
CleanModel:SetAttribute("GeneratedBy", "SummerDecorAssetImporter")
CleanModel:SetAttribute("SanitizerVersion", SummerDecorConfig.Security.SanitizerVersion)
CleanModel:SetAttribute("ImportedAt", os.time())
CleanModel:SetAttribute("SanitizedFingerprint", fingerprint)
```

`SanitizedFingerprint` = empreinte stable du contenu nettoyé (structure + propriétés whitelistées pertinentes). Changement d’empreinte = **nouvelle révision**.

7. Physique sur chaque `BasePart` de la copie : `Anchored = true`, `CanTouch = false`, `CanQuery = false`, `Massless = true`, `CanCollide = false` (sauf liste explicite de gros éléments — vide au départ). Petits éléments : `CastShadow = false`. Supprimer pièces 100 % transparentes / sans rôle visuel / > 500 studs du centre / taille démesurée.
8. **Validation finale** (second balayage) — échec si `LuaSourceContainer`, remotes, interactifs, forces non autorisées, ou classe hors whitelist.
9. **Routage import (toujours pending)** :
   - Tout nouvel import réussi va dans `SummerDecorPendingApproval`, **même si** l’ID est déjà dans `ApprovedAssetIds`.
   - **Ne jamais** écrire ni remplacer `SummerDecorAssets` pendant l’import.
   - Si un asset approuvé existe déjà en cache avec une empreinte différente → log `UPDATE REQUIRES REVIEW: ID` ; l’ancien cache reste intact.
10. Logs (jamais le mot « APPROVED » pour une simple sanitisation) :

```text
[SummerDecorSecurity] Scanning asset: ID
[SummerDecorSecurity] Original instances: X
[SummerDecorSecurity] Removed instances: X
[SummerDecorSecurity] Clean instances: X
[SummerDecorSecurity] SANITIZED asset: ID
[SummerDecorSecurity] PENDING MANUAL APPROVAL: ID
[SummerDecorSecurity] REJECTED asset: ID
[SummerDecorSecurity] UPDATE REQUIRES REVIEW: ID
```

11. **Nettoyage quarantaine** : Luau n’a pas de `finally`. Utiliser `xpcall` pour le corps d’import, puis **toujours** vider `SummerDecorQuarantine` après l’appel protégé (succès ou erreur).

Ne jamais démarrer automatiquement une session Play.

## 6. Promotion (seule voie vers le cache approuvé)

Bouton **Promote Approved Summer Assets** :

1. Précondition Edit (§4).
2. Pour chaque modèle dans `SummerDecorPendingApproval` dont `AssetId` ∈ `ApprovedAssetIds` :
   - Utiliser **exactement** cette copie pending (celle prévisualisable) — **aucun** nouvel appel `LoadAssetAsync`.
   - Remplacer (ou créer) l’entrée correspondante dans `SummerDecorAssets`.
   - Persister sur disque (§8).
   - Log : `[SummerDecorSecurity] PROMOTED approved asset: ID`
3. Si ID ∈ `ApprovedAssetIds` mais aucune copie pending / cache manquant → **validation bloquante**, pas de retéléchargement :

```text
[SummerDecorAssets] Approved asset missing from persistent cache: ID
```

`ApprovedAssetIds` autorise la promotion / l’usage ; il ne déclenche jamais un import silencieux ni un écrasement automatique.

## 7. Reconstruction whitelist (détail)

- Créer un nouveau `Model` ; ne pas réutiliser le modèle quarantaine comme résultat.
- Conserver la **hiérarchie** (parenté relative des nœuds autorisés).
- Remapper `Part0` / `Part1` / `Attachment0` / `Attachment1` (et équivalents weld/constraint) **uniquement** si la cible a été copiée dans le modèle propre ; sinon omettre la contrainte.
- **Aucune** référence vers le modèle de quarantaine.
- Recopier uniquement une **liste blanche de propriétés sûres** (CFrame, Size, Color, Material, Transparency, MeshId, TextureID, Light properties pertinentes, etc. — détail dans le plan).
- Supprimer tous les attributs et tags originaux avant/pendant la copie ; n’appliquer que les attributs générateur (§5.6).
- Modèle source : `Sandboxed = true` ; aucune capacité de script.

### Classes

**Rejet total de l’asset :**

```lua
FORBIDDEN_CLASSES = { Script = true, LocalScript = true, ModuleScript = true }
```

**Non recopiés (retirés du parcours) :**

```lua
REMOVE_CLASSES = {
	RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true,
	BindableEvent = true, BindableFunction = true,
	ProximityPrompt = true, ClickDetector = true, TouchTransmitter = true,
	Sound = true, Humanoid = true, AnimationController = true, Animator = true,
}
```

Aussi exclus de la copie : `ParticleEmitter`, `Trail`, `Beam`, forces physiques, sièges fonctionnels non nécessaires.

**Whitelist :**

```lua
ALLOWED_CLASSES = {
	Model = true, Folder = true,
	Part = true, MeshPart = true, UnionOperation = true,
	TrussPart = true, WedgePart = true, CornerWedgePart = true,
	SpecialMesh = true, BlockMesh = true, CylinderMesh = true,
	Decal = true, Texture = true,
	Attachment = true, Weld = true, WeldConstraint = true, Motor6D = true,
	PointLight = true, SpotLight = true, SurfaceLight = true,
}
```

Assert post-sanitisation : aucun `LuaSourceContainer` ; chaque descendant ∈ `ALLOWED_CLASSES`.

## 8. Persistance du cache approuvé (`SummerDecorAssets`)

`SummerDecorQuarantine` et `SummerDecorPendingApproval` restent temporaires / non versionnés.

`SummerDecorAssets` **doit survivre** aux refresh Rojo, builds, changements d’ordinateur, réouvertures et publication :

1. **Source de vérité disque** : fichiers `assets/summer-decor/<assetId>.rbxm` (ou `.rbxmx`) versionnés dans Git.
2. **Rojo** : mapper `ServerStorage/SummerDecorAssets` → `assets/summer-decor` dans `default.project.json` (les modèles synchronisés deviennent le cache en Studio).
3. **Promote** : écrit / met à jour le `.rbxm` **et** l’instance sous `SummerDecorAssets` à partir de la copie pending exacte.
4. **Générateurs** : lisent uniquement `ServerStorage.SummerDecorAssets` ; si ID approuvé mais fichier/instance absent → warn bloquant §6, **pas** de `LoadAssetAsync`.

## 9. Preview sans Workspace

Bouton **Preview Pending Summer Asset** :

- Précondition Edit.
- **Aucun** clone dans `Workspace` (ni ailleurs hors UI plugin).
- `DockWidgetPluginGui` + `ViewportFrame` + `Camera` de prévisualisation.
- WorldModel / clone **uniquement** comme enfant du ViewportFrame (isolé de la DataModel de jeu).
- UI : sélection de l’asset pending, rotation, zoom.
- Empêche sauvegarde / publication / décor réel / prise en compte par générateurs.

## 10. SummerZoneStringLights (migration stricte)

- Apparence, placement et rebuild périmètre conservés.
- Suppression de `InsertService:LoadAsset` / `GetObjects` comme source de templates.
- Templates = clone depuis `SummerDecorAssets` pour les IDs config.
- Si ID poteau/guirlande ∉ `ApprovedAssetIds` **ou** template absent du cache persistant → **ne rien générer** + warn (dont message cache manquant si ID approuvé). Aucun repli Marketplace.

## 11. Plugin Studio

| Bouton | Action |
|---|---|
| Import Summer Decor Candidates | Pipeline §5 → pending uniquement |
| Preview Pending Summer Asset | DockWidget + ViewportFrame (§9) |
| Promote Approved Summer Assets | §6 + persistance §8 |
| Add / Refresh / Remove Summer String Lights | Comportement actuel ; templates = cache sécurisé |

Logique métier dans Shared ; plugin = UI + appels.

## 12. Hors scope

- Placement automatique des nouveaux props (palmiers, parasols, …) dans la zone.
- Import runtime / jeu publié.
- Modification des décors manuels `SummerZoneDecor` hors LightPosts/StringLights.

## 13. Tests

- Classification FORBIDDEN / REMOVE / ALLOWED ; rejet si script.
- Whitelist : pas d’attributs/tags étrangers ; remapping weld ; weld vers objet supprimé omise.
- Import pendant simulation en pause (`IsEdit() == false`) → échec.
- Réimport d’un ID déjà approuvé avec empreinte différente → pending + `UPDATE REQUIRES REVIEW` ; cache inchangé.
- Impossibilité d’écraser le cache approuvé sans Promote.
- Promote utilise exactement la copie pending (pas de nouveau LoadAsset).
- Cache approuvé manquant → warn bloquant, pas de retéléchargement.
- Erreur pendant le scan → quarantaine quand même vidée.
- Preview : aucun nouveau descendant dans `Workspace`.
- `ApprovedAssetIds` vide → StringLights refuse de générer.

## 14. Contraintes

- Rojo sync ; pas de démarrage Play automatique.
- Ne jamais vider `SummerZoneDecor` entier.
- Une seule source d’IDs : `SummerDecorConfig`.
- Validation auto ≠ approbation ; seul Promote + `ApprovedAssetIds` autorisent l’usage.
