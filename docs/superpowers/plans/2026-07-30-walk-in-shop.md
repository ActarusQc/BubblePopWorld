# Walk-in ItemShop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer le kiosque d’achat par un bâtiment walk-in `ItemShop` avec 3 murs browse (Skills / Items / Cosmetics), achats live sécurisés, Coming Soon sans persistence.

**Architecture:** `ShopCatalog` (Shared) définit catégories/items + `Available`. `ItemShopBuilder` génère le bâtiment idempotent. `ShopService` enrichit `GetShopData` et rejette les IDs non disponibles. `ShopUI` gère un browse 100 % local (caméra, freeze, UI) avec `ExitBrowse()` unique.

**Tech Stack:** Luau `--!strict`, Rojo, ProximityPrompt, TweenService, Remotes existants (`GetShopData`, `BuyUpgrade`, `BuyItem`, `EquipBackpack`).

## Global Constraints

- SellBooth / AutoSell / téléporteur : **ne pas modifier**
- Modèle racine : `Workspace.ItemShop` uniquement (destroy legacy `BubbleShop` si présent)
- Browse local uniquement — aucun remote enter/exit browse
- Restaurer WalkSpeed / JumpPower|JumpHeight / AutoRotate / contrôles **mémorisés**, jamais hardcodés
- Mémoriser/restaurer aussi : `Camera.CameraType`, `Camera.CameraSubject`, `Camera.FieldOfView`, `Humanoid.UseJumpPower`
- ProximityPrompt : mémoriser l’état original de chaque `Enabled`, restaurer **exactement** cet état (jamais forcer `Enabled = true`)
- `ExitBrowse()` unique, idempotente, tous chemins de sortie
- `Available = false` : pas de bouton achat client ; rejet serveur ; pas de mutation profil
- Prix / effets Speed, Jump, Power, CoinMult + 3 sacs : **inchangés**
- Textes EN via `LocalizationStrings`
- Exécution **séquentielle uniquement** — Task N+1 seulement après Task N validée (T3/T4 dépendent de T1/T2)
- Commits : **jamais** `git add -A` ; ajouter uniquement les fichiers liés à la boutique
- Spec : `docs/superpowers/specs/2026-07-30-walk-in-shop-design.md`

---

### Task 1: ShopCatalog + LocalizationStrings

**Files:**
- Create: `src/Shared/ShopCatalog.lua`
- Modify: `src/Shared/LocalizationStrings.lua`
- Create: `src/Shared/ShopCatalogTests.lua`

**Interfaces:**
- Produces:
  - `ShopCatalog.Categories: { "Skills", "Items", "Cosmetics" }`
  - `ShopCatalog.GetCategoryItems(category: string): { ShopItemDef }`
  - `ShopCatalog.GetItem(id: string): ShopItemDef?`
  - `ShopCatalog.IsPurchasable(id: string): boolean` — true seulement si `Available == true` et id live (upgrade order ou ShopItems)
  - Type `ShopItemDef` : `Id`, `NameKey`, `Category`, `DescriptionKey`, `IconKey`, `ModelName`, `Type`, `Equipable`, `Available`, `UpgradeId?`, `ShopItemId?`

- [ ] **Step 1: Écrire le test catalogue**

```lua
--!strict
local ShopCatalog = require(script.Parent.ShopCatalog)

local function check(cond: boolean, msg: string)
	if not cond then error(msg, 2) end
end

check(ShopCatalog.IsPurchasable("Speed") == true, "Speed purchasable")
check(ShopCatalog.IsPurchasable("BackpackGold") == true, "BackpackGold purchasable")
check(ShopCatalog.IsPurchasable("Magnet") == false, "Magnet not purchasable")
check(ShopCatalog.IsPurchasable("Cap") == false, "Cap not purchasable")
check(#ShopCatalog.GetCategoryItems("Skills") >= 5, "Skills has live + coming soon")
check(#ShopCatalog.GetCategoryItems("Cosmetics") >= 3, "Cosmetics populated")
print("ShopCatalogTests OK")
return true
```

- [ ] **Step 2: Implémenter `ShopCatalog.lua`**

Live Skills mappent `UpgradeId` ∈ `Config.UpgradeOrder` (`Speed`, `Jump`, `Power`, `CoinMult`).  
Live Items mappent `ShopItemId` ∈ `Config.ShopItemOrder`.  
Coming Soon : Magnet, Luck, CapacityBoost, Pin, Hammer, MultiPopTool, SpecialTool, Cap, Hat, Vest, Shirt, Accessory — `Available = false`.  
Ne pas inventer de prix persistés pour Coming Soon (Price affiché optionnel / `nil` → UI masque ou montre "—").

- [ ] **Step 3: Ajouter clés L10n EN**

Au minimum : `BrowseSkills`, `BrowseItems`, `BrowseCosmetics`, `Cosmetics`, `ComingSoon`, `Locked`, `TooExpensive`, `Buy`, `Upgrade`, `ShopSign` (si besoin), descriptions courtes pour chaque nouvel item catalogue.

- [ ] **Step 4: Exécuter le test**

Run (selon runner projet, ex. `tools` / require Studio) : charger `ShopCatalogTests`.  
Expected: `ShopCatalogTests OK`.

- [ ] **Step 5: Commit**

```bash
git add src/Shared/ShopCatalog.lua src/Shared/ShopCatalogTests.lua src/Shared/LocalizationStrings.lua
git commit -m "$(cat <<'EOF'
feat(shop): add ShopCatalog and Coming Soon localization keys

EOF
)"
```

---

### Task 2: ItemShopBuilder walk-in

**Files:**
- Rewrite: `src/Server/ItemShopBuilder.lua`
- Modify: `src/Shared/GameConfig.lua` — uniquement `Lobby.ItemShop` (dims, offsets, prompt texts, wall labels)

**Interfaces:**
- Consumes: `Config.Lobby.ItemShop`, `Config.Lobby.ItemShopPosition`
- Produces: `Workspace.ItemShop` avec enfants nommés exactement :
  `Entrance`, `Wall_Skills`, `Wall_Items`, `Wall_Cosmetics`,
  `PromptAnchor_Skills|Items|Cosmetics`,
  `CameraPoint_Skills|Items|Cosmetics`,
  `Display_Skills|Items|Cosmetics`
- Chaque `PromptAnchor_*` contient un `ProximityPrompt` (ActionText L10n Browse*, ObjectText catégorie)
- Attribute `BPW_ItemShop = true`
- Prompt attribute `BPW_ShopCategory = "Skills"|"Items"|"Cosmetics"`

- [ ] **Step 1: Étendre `GameConfig.Lobby.ItemShop`**

Ajouter champs de footprint (ex. Width, Depth, Height, DoorWidth, WallThickness) et textes enseignes.  
**Ne pas** changer `SellBooth` / offsets sell. Vérifier footprint vs `lobbySellOffset` (−34, 2, −27) : pas de chevauchement Z/X avec shop à (−34, 0, 6).

- [ ] **Step 2: Réécrire Build idempotent**

```lua
local function destroyExisting()
	for _, name in ipairs({ "ItemShop", "BubbleShop" }) do
		local old = Workspace:FindFirstChild(name)
		if old then old:Destroy() end
	end
end
```

Générer : plaza/plancher collision, murs 3 côtés + façade avec trou d’entrée large, toit optionnel simple, enseignes SurfaceGui/Billboard EN, 3 PromptAnchors (parts semi-invisibles ou bornes larges, `CanCollide = false`), CameraPoints (parts invisibles Anchored), Displays (socles simples).  
Déco : `CanCollide = false`. Structure : collide. Tout `Anchored = true`.  
Retirer l’ancien prompt unique « Open Shop » du comptoir.

- [ ] **Step 3: Vérifier en Studio / play solo**

Checklist manuelle :
1. Un seul `ItemShop` après 2× `Start`/`Build`
2. Entrée traversable sans snag
3. SellBooth intact
4. Noms enfants exacts présents
5. 3 prompts visibles / activables

- [ ] **Step 4: Commit**

```bash
git add src/Server/ItemShopBuilder.lua src/Shared/GameConfig.lua
git commit -m "$(cat <<'EOF'
feat(shop): replace purchase kiosk with walk-in ItemShop building

EOF
)"
```

---

### Task 3: ShopService — GetShopData + garde Available

**Files:**
- Modify: `src/Server/ShopService.lua`
- Modify: `src/Shared/ShopCatalogTests.lua` (ou petit test logique serveur pur si extractable)

**Interfaces:**
- Consumes: `ShopCatalog.IsPurchasable`, `ShopCatalog.GetCategoryItems`
- Produces `GetShopData` shape :

```lua
{
  Categories = {
    Skills = { { Id, Label, Description, Type, Available, Equipable, Level?, Max?, Cost, Owned?, Equipped?, ButtonState } },
    Items = { ... },
    Cosmetics = { ... },
  },
  EquippedBackpack = string,
  DefaultCapacity = number,
  Coins = number, -- pour refresh UI immédiat
}
```

`ButtonState` calculé serveur : `"Buy"|"Upgrade"|"Equip"|"Equipped"|"TooExpensive"|"ComingSoon"|"Locked"|"Max"`  
Pour upgrades live : Cost via `Config.UpgradeCost` ; Coming Soon : Cost = -1 ou nil, ButtonState = ComingSoon.

- [ ] **Step 1: Enrichir `getShopData`**

Construire les 3 listes depuis `ShopCatalog`. Pour live upgrades/items, réutiliser la logique actuelle de niveaux/owned/equipped.  
Garder rétrocompat soft si `InventoryUI` lit encore `Upgrades`/`Items` : **soit** conserver aussi les clés legacy `Upgrades`/`Items` dans la réponse, **soit** adapter `InventoryUI` minimalement pour continuer à équiper les sacs.

Recommandation : conserver `Upgrades` + `Items` legacy **et** ajouter `Categories` pour ShopUI.

- [ ] **Step 2: Gardes d’achat**

Au début de `buyUpgrade` / `buyItem` :

```lua
if not ShopCatalog.IsPurchasable(id) then
	return false, "Coming soon"
end
```

`equipBackpack` : uniquement sacs live déjà possédés (inchangé + rejeter ids inconnus).

- [ ] **Step 3: Smoke test manuel**

Remote cheat Coming Soon → message Denied / Coming soon, coins inchangés.  
Buy Speed / BackpackGold → comportement identique à avant.

- [ ] **Step 4: Commit**

```bash
git add src/Server/ShopService.lua
git commit -m "$(cat <<'EOF'
feat(shop): catalog-aware GetShopData and reject unavailable purchases

EOF
)"
```

---

### Task 4: ShopUI browse local + ExitBrowse

**Files:**
- Rewrite: `src/Client/ShopUI.lua`
- Touch if needed: `src/Client/init.client.lua` (déjà require ShopUI)

**Interfaces:**
- Consumes: prompts `BPW_ShopCategory`, Remotes `GetShopData`/`BuyUpgrade`/`BuyItem`/`EquipBackpack`, CameraPoints/Displays
- Produces: `ShopUI.Start()`, browse state machine locale, `ExitBrowse()`

- [ ] **Step 1: State + mémoire contrôles**

```lua
local browse = {
	active = false,
	category = nil :: string?,
	index = 1,
	items = {} :: { any },
	saved = nil :: {
		WalkSpeed: number,
		JumpPower: number?,
		JumpHeight: number?,
		UseJumpPower: boolean?,
		AutoRotate: boolean,
		ControlsEnabled: boolean,
		CameraType: Enum.CameraType,
		CameraSubject: Instance?,
		FieldOfView: number,
	}?,
	promptEnabled = {} :: { [ProximityPrompt]: boolean },
}
```

Avant freeze : lire Humanoid + Controls + Camera (`CameraType`, `CameraSubject`, `FieldOfView`) + `UseJumpPower` ; stocker dans `browse.saved`.  
Pour chaque ProximityPrompt sous `ItemShop` : mémoriser `Enabled` original dans `promptEnabled`.

- [ ] **Step 2: EnterBrowse(category)**

1. Si déjà active → `ExitBrowse()` d’abord ou ignore.
2. Sauver contrôles/caméra ; freeze ; pour chaque prompt ItemShop mémoriser `Enabled` puis mettre `Enabled = false` (local).
3. Tween `CurrentCamera` Scriptable vers `CameraPoint_<cat>`, LookAt `Display_<cat>`.
4. Fetch `GetShopData` ; remplir liste catégorie ; index 1 ; `RefreshPresentation()`.
5. UI compacte visible (pas plein écran opaque bloquant tout).

- [ ] **Step 3: Navigation + action**

- Left/Right (boutons UI + Q/E ou ←/→ clavier + DPad) : `index = ((index-2) % n) + 1` / `((index) % n) + 1`.
- Action button : seulement si `Available` et ButtonState ∈ Buy/Upgrade/Equip ; InvokeServer correspondant ; puis `RefreshFromServer()` sans fermer.
- ComingSoon/Locked/TooExpensive/Equipped/Max : bouton disabled ou non-achat.

- [ ] **Step 4: ExitBrowse() unique**

```lua
local exiting = false
local function ExitBrowse()
	if exiting or not browse.active then
		-- quand même best-effort restore si saved présent
	end
	exiting = true
	-- cancel tweens; restore CameraType/Subject/FOV from saved;
	-- restore humanoid/controls/UseJumpPower from browse.saved (never hardcoded);
	-- for each prompt: Enabled = promptEnabled[prompt] (exact original, never force true);
	-- hide UI, clear browse, exiting = false
end
```

Brancher : Close, Escape, Gamepad B (`Enum.KeyCode.ButtonB`), `Humanoid.Died`, `CharacterRemoving`, `CharacterAdded` (si browse actif), erreurs pcall autour des remotes.

- [ ] **Step 5: Présentoir**

Mettre à jour `Display_*` localement (clone simple / MeshPart coloré / ViewportFrame UI — préférer ViewportFrame dans UI compacte **ou** part locale dans Display folder `LocalPlayer` only via client-created model parented under Display).  
Important : modèles client-only pour ne pas affecter les autres joueurs.

- [ ] **Step 6: Tests manuels PC / mobile / console**

1. 2 joueurs : browse murs différents → OK mutuel  
2. Escape / Close / B / reset character → contrôles + caméra OK  
3. Loop gauche/droite  
4. Achat Speed → coins + niveau + bouton refresh sans close  
5. Coming Soon → pas d’appel remote  
6. SellBooth toujours fonctionnel

- [ ] **Step 7: Commit**

```bash
git add src/Client/ShopUI.lua
git commit -m "$(cat <<'EOF'
feat(shop): local wall browse UI with locked camera and ExitBrowse

EOF
)"
```

---

### Task 5: Vérification finale + polish footprint

**Files:**
- Adjust if needed: `GameConfig.Lobby.ItemShop` offsets/size only
- Docs already written

- [ ] **Step 1: Checklist spec §10**

Parcourir tous les critères de succès de la spec ; corriger écarts.

- [ ] **Step 2: Confirmer noms Workspace**

Liste exacte présente sous `ItemShop` ; aucun résidu comptoir kiosque (`Counter`, ancien `ShopPrompt` unique, etc.).

- [ ] **Step 3: Commit final si diffs**

Ajouter **uniquement** les fichiers boutique touchés (ex. `GameConfig.lua`, `ItemShopBuilder.lua`) — **jamais** `git add -A`.

```bash
git add src/Shared/GameConfig.lua src/Server/ItemShopBuilder.lua
git status
git commit -m "$(cat <<'EOF'
chore(shop): walk-in shop footprint polish after playtest

EOF
)"
```

---

## Spec coverage (self-review)

| Exigence spec | Task |
|---|---|
| Bâtiment walk-in + 3 murs + structure noms | T2 |
| ShopCatalog + Available | T1 |
| SellBooth intact / destroy ItemShop only | T2 |
| Prompts PC/mobile/console | T2 + T4 |
| Browse local caméra + freeze mémorisé | T4 |
| ExitBrowse tous chemins | T4 |
| Loop navigation | T4 |
| Refresh post-achat | T4 |
| Serveur rejette Available=false | T3 |
| Prix live inchangés | T1/T3 |
| L10n EN | T1 |
| Idempotence builder | T2 |
| Collisions / Anchored | T2 |

## Hors plan (volontaire)

Gameplay Magnet/Luck/Pin shop, équipement cosmétique, redesign SellBooth.
