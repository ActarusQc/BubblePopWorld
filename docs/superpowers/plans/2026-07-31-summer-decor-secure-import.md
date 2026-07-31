# Summer Decor Secure Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pipeline Studio Edit-only d’import décor Summer avec quarantaine, rebuild whitelist, pending/promote par révision (empreinte), cache `.rbxm` persistant, et guirlandes sans repli Marketplace.

**Architecture:** `SummerDecorConfig` (Rojo) est la source d’IDs. `SummerDecorSecurity` sanitize/rebuild. `SummerDecorAssetImporter` orchestre Import → Pending et Promote → `assets/summer-decor` + `ServerStorage.SummerDecorAssets`. Plugin : ViewportFrame preview. `SummerZoneStringLights` clone uniquement le cache promu.

**Tech Stack:** Luau `--!strict`, Rojo, AssetService (Studio Edit), ServerStorage, DockWidgetPluginGui / ViewportFrame, fichiers `.rbxm`.

## Global Constraints

- Spec : `docs/superpowers/specs/2026-07-31-summer-decor-secure-import-design.md`
- Import / Preview / Promote : `RunService:IsStudio() and RunService:IsEdit()` uniquement
- Jamais `LoadAssetAsync` / `InsertService` / `GetObjects` en jeu publié ni comme repli StringLights
- Tout import → `SummerDecorPendingApproval` seulement ; **jamais** écraser `SummerDecorAssets` à l’import
- Promote = seule voie vers cache ; utilise la copie pending exacte (pas de nouveau load)
- `ApprovedAssetIds` autorise usage/promote d’un ID, pas toutes les versions futures
- Cache manquant + ID approuvé → warn bloquant, **pas** de retéléchargement
- Quarantaine vidée après `xpcall` (succès ou erreur) — pas de `finally` Luau
- Preview : **aucun** descendant créé dans `Workspace`
- Ne jamais vider `SummerZoneDecor` entier
- Commits : fichiers liés à cette feature uniquement (pas `git add -A`)
- Commits seulement si l’utilisateur le demande explicitement pendant l’exécution

## File Structure

| Fichier | Rôle |
|---|---|
| `src/Shared/SummerDecorConfig.lua` | Assets, ApprovedAssetIds, Security, placement lights |
| `src/Shared/SummerDecorSecurity.lua` | Classes, fingerprint, rebuild, validate |
| `src/Shared/SummerDecorAssetImporter.lua` | Import / promote / folders / persist rbxm |
| `src/Shared/SummerDecorSecurityTests.lua` | Tests sécurité / edit / fingerprint / quarantine |
| `src/Shared/SummerZoneStringLights.lua` | Templates depuis cache ; IDs depuis config |
| `src/Shared/SummerZoneStringLightsTests.lua` | Refuse génération si non approuvé / cache absent |
| `assets/summer-decor/.gitkeep` | Dossier cache (rbxm ajoutés à la promote) |
| `default.project.json` | Map `ServerStorage.SummerDecorAssets` → `assets/summer-decor` |
| `studio-plugins/LobbyEditingPreview.plugin.lua` | Boutons Import / Preview / Promote |
| `src/Server/init.server.lua` | Enregistrer les nouveaux tests Shared |

---

### Task 1: SummerDecorConfig + mapping Rojo

**Files:**
- Create: `src/Shared/SummerDecorConfig.lua`
- Create: `assets/summer-decor/.gitkeep`
- Modify: `default.project.json`
- Create: `src/Shared/SummerDecorConfigTests.lua`
- Modify: `src/Server/init.server.lua` (hook test)

**Interfaces:**
- Produces:
  - `SummerDecorConfig.Assets` — table catégories → `{ number }`
  - `SummerDecorConfig.ApprovedAssetIds: { [number]: boolean }` — `{}` initial
  - `SummerDecorConfig.Security = { RejectAssetsContainingScripts = true, RequireManualApproval = true, SanitizerVersion = 1 }`
  - `SummerDecorConfig.Placement` — `PostAssetId`, `StringAssetId`, `LightPerimeterSpacing` (+ constantes lumières migrées si déjà dans SummerZoneConfig)
  - `SummerDecorConfig.IsApproved(assetId: number): boolean`
  - `SummerDecorConfig.ListCandidateAssetIds(): { number }` — IDs uniques aplatis
  - `SummerDecorConfig.GetCategoryForAssetId(assetId: number): string?`

- [ ] **Step 1: Test config**

```lua
--!strict
local Config = require(script.Parent.SummerDecorConfig)
local function check(c: boolean, m: string)
	if not c then warn("[SummerDecorConfigTests] FAIL:", m); return false end
	return true
end
local ok = true
ok = check(Config.ApprovedAssetIds[18953379883] == nil, "posts not approved") and ok
ok = check(Config.IsApproved(18953379883) == false, "IsApproved false") and ok
ok = check(Config.Assets.StringLightPosts[1] == 18953379883, "post id") and ok
ok = check(Config.Assets.StringLights[1] == 93169410099587, "string id") and ok
ok = check(Config.Security.RequireManualApproval == true, "manual approval") and ok
ok = check(Config.Security.SanitizerVersion >= 1, "sanitizer version") and ok
local ids = Config.ListCandidateAssetIds()
ok = check(#ids >= 18, "all candidates listed") and ok
if ok then print("[SummerDecorConfigTests] OK") end
return ok
```

- [ ] **Step 2: Implémenter `SummerDecorConfig.lua`** avec la liste Assets complète de la spec et `ApprovedAssetIds = {}`.

- [ ] **Step 3: Rojo** — dans `default.project.json`, sous DataModel, ajouter :

```json
"ServerStorage": {
  "$className": "ServerStorage",
  "SummerDecorAssets": { "$path": "assets/summer-decor" }
}
```

Créer `assets/summer-decor/.gitkeep`.

- [ ] **Step 4: Brancher le test** dans `init.server.lua` (pcall require + `Run()` comme les autres).

- [ ] **Step 5: Vérifier** — require/tests OK ; `rojo build` OK.

---

### Task 2: SummerDecorSecurity (classes, fingerprint, rebuild)

**Files:**
- Create: `src/Shared/SummerDecorSecurity.lua`
- Create: `src/Shared/SummerDecorSecurityTests.lua`

**Interfaces:**
- Produces:
  - `SummerDecorSecurity.FORBIDDEN_CLASSES` / `REMOVE_CLASSES` / `ALLOWED_CLASSES`
  - `SummerDecorSecurity.FindForbiddenScripts(root: Instance): { string }` — chemins complets
  - `SummerDecorSecurity.ComputeFingerprint(cleanRoot: Instance): string`
  - `SummerDecorSecurity.RebuildWhitelisted(sourceRoot: Instance, assetId: number): (Model?, string?)` — model ou nil + reason
  - `SummerDecorSecurity.ValidateCleanModel(clean: Instance): (boolean, string?)`
  - `SummerDecorSecurity.CountInstances(root: Instance): number`
  - Propriétés BasePart copiées (min) : `Name`, `CFrame`, `Size`, `Color`, `Material`, `Transparency`, `Reflectance`, `Anchored`, `CanCollide`, `CanTouch`, `CanQuery`, `CastShadow`, `Massless`, `Shape` (si Part)
  - MeshPart : + `MeshId`, `TextureID` si exposés
  - Lights : `Brightness`, `Color`, `Range`, `Shadows` (+ `Angle`/`Face` selon type)
  - WeldConstraint : remap `Part0`/`Part1` ; Weld/Motor6D : remap parts/attachments ; sinon omettre
  - Attributs posés uniquement après rebuild : `AssetId`, `SanitizedSummerAsset`, `GeneratedBy`, `SanitizerVersion`, `ImportedAt`, `SanitizedFingerprint`
  - Source : tenter `Sandboxed = true` via pcall si la propriété existe

- [ ] **Step 1: Tests unitaires** (instances synthétiques créées en mémoire dans le test) :
  - script enfant → `FindForbiddenScripts` non vide
  - rebuild ignore `Sound` / `ProximityPrompt`
  - weld dont `Part1` non autorisé → contrainte absente du clean
  - aucun attribut original recopié
  - `ValidateCleanModel` échoue si on parent un `Script` après coup
  - fingerprint change si Size change

- [ ] **Step 2: Implémenter rebuild** avec map `source → clone`, hiérarchie, remap références, physique par défaut (Anchored, Massless, CanTouch/CanQuery false, CanCollide false, CastShadow false pour petites pièces).

- [ ] **Step 3: Exécuter tests** — Expected: `[SummerDecorSecurityTests] OK`.

---

### Task 3: SummerDecorAssetImporter (import / promote / quarantine)

**Files:**
- Create: `src/Shared/SummerDecorAssetImporter.lua`
- Modify: `src/Shared/SummerDecorSecurityTests.lua` (ou `SummerDecorAssetImporterTests.lua`)

**Interfaces:**
- Produces:
  - `SummerDecorAssetImporter.FOLDER_QUARANTINE = "SummerDecorQuarantine"`
  - `SummerDecorAssetImporter.FOLDER_PENDING = "SummerDecorPendingApproval"`
  - `SummerDecorAssetImporter.FOLDER_ASSETS = "SummerDecorAssets"`
  - `SummerDecorAssetImporter.AssertEditMode(): boolean`
  - `SummerDecorAssetImporter.EnsureFolders()`
  - `SummerDecorAssetImporter.ClearQuarantine()`
  - `SummerDecorAssetImporter.ImportAssetId(assetId: number): string` — `"sanitized_pending" | "rejected" | "blocked_not_edit" | "error"`
  - `SummerDecorAssetImporter.ImportAllCandidates(): { [number]: string }`
  - `SummerDecorAssetImporter.PromotePendingApproved(): { promoted: { number }, missing: { number } }`
  - `SummerDecorAssetImporter.GetPendingModels(): { Model }`
  - Persist promote : écrire `assets/summer-decor/<assetId>.rbxm` via plugin/API Studio disponible (`SerializationService` / `plugin:PromptSaveSelection` **non** — préférer API capable d’écrire le fichier projet si accessible depuis module ; sinon expose `BuildPromotePayload` et laisse le plugin appeler `WriteFile` / flux documenté). **Minimum plan :** Promote clone vers `ServerStorage.SummerDecorAssets` + log ; persistance fichier via plugin `writefile` si Studio le permet, sinon documenter export manuel `.rbxm` dans `assets/summer-decor/` immédiatement après promote.
  - Logs exacts spec : `SANITIZED`, `PENDING MANUAL APPROVAL`, `REJECTED`, `UPDATE REQUIRES REVIEW`, `PROMOTED`, et `[SummerDecorAssets] Approved asset missing from persistent cache: ID`

**Règles ImportAssetId :**
1. Si pas Edit → `"blocked_not_edit"`
2. `xpcall` corps : load → quarantine parent → scan scripts → rebuild → validate → parent sous Pending (remplacer pending même ID) → si cache Assets existe et fingerprint ≠ → `UPDATE REQUIRES REVIEW`
3. **Ne pas** toucher `SummerDecorAssets`
4. Après `xpcall` : `ClearQuarantine()` inconditionnel

**Règles PromotePendingApproved :**
1. Edit only
2. Pour chaque pending avec `AssetId` approuvé : cloner/déplacer **cette** instance vers Assets (remplace ancienne)
3. IDs approuvés sans pending ni cache → missing warn, pas de LoadAsset

- [ ] **Step 1: Tests** (mocks : stubs `AssertEditMode`, instances locales sans AssetService) :
  - `AssertEditMode` false → import bloqué
  - import ne mute pas un modèle déjà sous Assets
  - promote copie le pending exact (même Fingerprint)
  - erreur simulée dans corps → ClearQuarantine quand même appelé
  - fingerprint différente + cache existant → UPDATE REQUIRES REVIEW (flag/log)

- [ ] **Step 2: Implémenter importer** avec `AssetService:LoadAssetAsync` derrière pcall uniquement si Edit.

- [ ] **Step 3: Tests OK**.

---

### Task 4: Brancher SummerZoneStringLights sur config + cache

**Files:**
- Modify: `src/Shared/SummerZoneStringLights.lua`
- Modify: `src/Shared/SummerZoneStringLightsTests.lua`

**Interfaces:**
- Consumes: `SummerDecorConfig.Assets.StringLightPosts[1]`, `StringLights[1]`, `IsApproved`, `SummerDecorAssetImporter.FOLDER_ASSETS`
- Change: supprimer `InsertService` / `GetObjects` / `LoadAssetTemplate` Marketplace
- Produce: `SummerZoneStringLights.GetApprovedTemplate(assetId: number): Instance?` — cherche sous `ServerStorage.SummerDecorAssets` un Model avec `AssetId` + `SanitizedSummerAsset` ; sinon nil + warn
- `CreateSummerPerimeterLights` : si posts/strings non approuvés **ou** template nil → warn et return nil **sans** générer

- [ ] **Step 1: Test** — avec `ApprovedAssetIds` vide, une fonction pure `CanGenerateLights()` / appel Create en mode mock retourne false / nil.

- [ ] **Step 2: Remplacer** chargement template ; garder géométrie périmètre / sag / prepareDecorModel sur le **clone** du cache.

- [ ] **Step 3: Exposer** toujours `POST_ASSET_ID` / `STRING_ASSET_ID` comme alias lus depuis config (compat tests existants).

- [ ] **Step 4: Tests StringLights + rojo build**.

---

### Task 5: Plugin — Import / Preview ViewportFrame / Promote

**Files:**
- Modify: `studio-plugins/LobbyEditingPreview.plugin.lua`

**Interfaces:**
- Boutons toolbar :
  - `Import Summer Decor Candidates` → `SummerDecorAssetImporter.ImportAllCandidates()`
  - `Preview Pending Summer Asset` → ouvre/focus DockWidget ; **interdit** `Parent = workspace`
  - `Promote Approved Summer Assets` → `PromotePendingApproved()` (+ écriture rbxm si API dispo)
- DockWidget : liste pending, ViewportFrame + WorldModel, Camera, drag rotation / molette zoom
- Clone pending **uniquement** sous `WorldModel` du ViewportFrame ; destroy à la fermeture / changement de sélection
- Toutes actions : early-out si `not (IsStudio() and IsEdit())`

- [ ] **Step 1: Ajouter boutons + handlers** require Shared.

- [ ] **Step 2: Implémenter UI preview** sans Workspace.

- [ ] **Step 3: Checklist manuelle Studio** (documenter dans commentaire plugin) :
  - Import en Edit → pending
  - Pause Play → Import échoue
  - Preview → Explorer Workspace inchangé
  - Promote sans ApprovedAssetIds → rien / missing
  - Après ajout IDs config + Promote → Assets + lights OK

---

### Task 6: Tests finaux + validation build

**Files:**
- Modify: `src/Server/init.server.lua` (tous les nouveaux `*Tests`)
- Verify: couverture liste §13 de la spec

- [ ] **Step 1: Matrice de tests** — cocher chaque cas spec §13 dans les modules de test (ajouter les manquants).

- [ ] **Step 2: `rojo build -o BubblePopWorld.rbxlx`** — Expected: succès.

- [ ] **Step 3: Rapport** — lister fichiers touchés + procédure Studio courte (import → preview → approuver IDs dans config → promote → refresh lights).

---

## Spec coverage (self-check)

| Spec | Task |
|---|---|
| Config unique + candidats | T1 |
| Edit via `IsEdit()` | T3, T5 |
| Quarantaine + xpcall cleanup | T3 |
| Reject scripts + logs | T2, T3 |
| Rebuild whitelist + remap + Sandboxed | T2 |
| Import toujours pending | T3 |
| Fingerprint / UPDATE REQUIRES REVIEW | T2, T3 |
| Promote seule écriture Assets | T3 |
| Persist rbxm + Rojo map | T1, T3 |
| Missing cache warn | T3, T4 |
| Preview ViewportFrame | T5 |
| StringLights no InsertService | T4 |
| Logs SANITIZED / PENDING / PROMOTED / REJECTED | T3 |
| Tests additionnels | T2–T6 |

## Execution

Plan saved. Deux options :

1. **Subagent-Driven** (recommandé) — un sous-agent par tâche + review
2. **Inline Execution** — exécution dans cette session avec checkpoints

Laquelle préfères-tu ?
