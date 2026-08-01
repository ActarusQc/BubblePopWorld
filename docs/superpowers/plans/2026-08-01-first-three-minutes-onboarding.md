# Première session — Plan d'implémentation (3 premières minutes)

> **For agentic workers:** REQUIRED SUB-SKILL — utiliser `superpowers:subagent-driven-development` ou `superpowers:executing-plans`. Les étapes utilisent la syntaxe checkbox (`- [ ]`). **Un point d'arrêt obligatoire termine chaque phase** : ne pas commencer la phase suivante avant validation Studio par le propriétaire.

**Spec de référence** : `docs/superpowers/specs/2026-08-01-first-three-minutes-onboarding-design.md` (décisions §14 approuvées et verrouillées).

**Objectif** : amener un nouveau joueur à son premier pop en < 10 s, à sa première vente en < 80 s et à son premier achat d'amélioration en < 180 s, sans casser les joueurs existants, l'économie, les sauvegardes ni les funnels analytics.

**Architecture** : un module partagé pur (`OnboardingConfig`) porte la machine à états ; un service serveur (`OnboardingService`) est la **seule** autorité et publie l'objectif via l'attribut joueur `OnboardingObjective` ; deux modules client (`OnboardingGuide`, `SellFeedback`) ne font que du rendu. Aucun nouveau canal de persistance, aucun nouveau funnel.

---

## Contraintes globales (valables pour les 7 phases)

- **Aucun système parallèle.** Réutiliser `DataService`, `BackpackService`, `ShopService`, `ZoneService`, `GameAnalyticsService`, `Remotes`, `LocalizationStrings`.
- **Autorité serveur stricte.** Le client ne décide jamais qu'une étape est franchie. Aucun Remote client → serveur n'est ajouté.
- **Canal de réplication** : attribut joueur `OnboardingObjective` (même patron que `Coins`, `CurrentBubbles`, `PlayerArea`, `HasWings`).
- **Aucun polling permanent.** Le serveur recalcule sur événement métier. Le client s'abonne à `GetAttributeChangedSignal` et ne connecte `RenderStepped` **que** pendant qu'un objectif est actif.
- **Analytics** : aucun renommage, aucune émission directe vers `AnalyticsService`, tout passe par `GameAnalyticsService`. `OnboardingAnalyticsVersion` reste à `1`.
- **Données** : `GameConfig.Data.StoreVersion` reste `"v2"`. Aucun nouveau champ persisté hors `Analytics.Lifetime` (réconcilié automatiquement).
- **Économie** : ne pas toucher `BubbleTypes` `SellValue`, `Backpack.DefaultCapacity`, `GameConfig.Combo`, ni les coûts de `Jump` / `Power` / `CoinMult`. Vente toujours automatique, pièces créditées uniquement dans `BackpackService.doSell`.
- **Textes** : anglais, via `src/Shared/LocalizationStrings.lua` uniquement.
- **Guidage** : jamais de capture d'input, jamais de contrôle caméra, jamais de `Modal`. Uniquement des `ImageLabel` / `TextLabel` avec `Active = false`.
- **StreamingEnabled = true** : les cibles de guidage viennent de `GameConfig` / `ZoneDefs`, jamais d'une instance du Workspace.
- **Joueurs existants** : `Analytics.OnboardingStarted == false` ou `OnboardingCompleted == true` → comportement bit-à-bit identique à aujourd'hui.
- **Nettoyage client** : toute instance et toute connexion créée est détruite sur changement d'objectif, `CharacterRemoving`, et `Stop()` du module.
- **Avant la fin de la Phase 7** : `GameConfig.World.RebuildGeneratedLayout = false` et `BubbleValue.DEBUG_BUBBLE_VALUE = false`.

---

## Commandes de vérification réelles du dépôt

Vérifiées le 2026-08-01 sur cette machine. **Ne pas en inventer d'autres.**

### Tests unitaires hors Roblox (harnais Python + `tools/luau/luau.exe`)

| Commande | Couvre |
|---|---|
| `python tools\run_progression_tests.py` | `GameConfig` : seuils de niveau, `UpgradeCost`, `PlayerMovement`, implantation lobby/ItemShop |
| `python tools\run_shop_service_tests.py` | `ShopService` (achats, `GetShopData`, `ButtonState`) |
| `python tools\run_shop_catalog_tests.py` | `ShopCatalog` |
| `python tools\run_shop_browse_logic_tests.py` | Logique de navigation boutique |
| `python tools\run_shop_layout_tests.py` | Mise en page boutique |
| `python tools\run_shop_viewport_tests.py` | Viewports boutique |
| `python tools\run_shop_avatar_visibility_tests.py` | Visibilité avatar boutique |
| `python tools\run_itemshop_builder_tests.py` | `ItemShopBuilder` |
| `python tools\run_itemshop_visual_tests.py` | Visuel ItemShop |
| `python tools\run_travel_tests.py` | `TravelConfig` |
| `python tools\run_summer_lights_tests.py` | Guirlandes Summer Zone |

Sortie attendue : `N réussis, 0 échoués` puis code retour `0`.

### Contrôle statique

```powershell
.\tools\luau\luau-compile.exe --binary <fichier.lua>
```

Code retour `0` = syntaxe valide. C'est **le** gate statique fiable : `luau-analyze.exe` fonctionne mais produit du bruit sur les globals Roblox (`game`, `script`, `Enum`) et sur `Unknown require: unsupported path` — l'utiliser en information seulement, jamais comme critère de blocage.

### Suites exécutées dans Roblox Studio

Elles sont enregistrées par `runSuite()` dans `src/Server/init.server.lua` et se lancent **automatiquement au Play Solo en Studio**. Vérification = lire la fenêtre Output, chercher `FAIL`.

- Bloc destructif (avant sessions joueur) : `AnalyticsConfigTests`, `DataServiceAnalyticsTests`, `GameAnalyticsServiceTests`.
- Bloc validations : `ZoneAccessTests`, `MusicConfigTests`, `LeaderboardTests`, `SummerZoneStringLightsTests`, `TravelConfigTests`, `BubbleValueTests`, `ZoneGameplayTests`, `SummerDecorConfigTests`, `SummerDecorSecurityTests`, `SummerDecorPropSplitTests`, `SummerDecorSceneClassifierTests`, `ShopCatalogTests`, `ShopBrowseLogicTests`, `ShopBrowseLayoutTests`, `ShopViewportModelsTests`, `ItemShopVisualTests`, `ItemSpawnTests`, `ShopServiceTests`, `BackpackServiceTests`, `ChestServiceTests`.

### Build Rojo

```powershell
rojo build --output build.rbxlx
```

⚠️ **`rojo` n'est pas actuellement dans le PATH de cette machine** (`Get-Command rojo` → introuvable). Avant la Phase 1, installer selon le README : `aftman add rojo-rbx/rojo` (ou `cargo install rojo`). Si l'installation est refusée, le substitut de gate est : `luau-compile` sur **tous** les fichiers touchés + Play Solo en Studio sans erreur de chargement. Le plan considère `rojo build` comme obligatoire dès qu'il est disponible.

---

## Carte des fichiers

### À créer

| Fichier | Rôle | Phase |
|---|---|---|
| `src/Shared/OnboardingConfig.lua` | Machine à états **pure**, objectifs, clés de texte, constantes UI | 1 |
| `src/Shared/OnboardingConfigTests.lua` | Suite `Run()` de la machine à états | 1 |
| `tools/test_onboarding.lua` | Harnais Luau hors Roblox | 1 |
| `tools/run_onboarding_tests.py` | Lanceur Python | 1 |
| `src/Server/OnboardingService.lua` | Autorité serveur, publication de l'attribut | 1 |
| `src/Client/OnboardingGuide.lua` | Waypoint 3D + flèche écran | 3 |
| `src/Client/SellFeedback.lua` | FX de vente | 4 |

### À modifier

| Fichier | Modification | Phase |
|---|---|---|
| `src/Server/ZoneService.lua` | `SpawnLocation` sur le SpawnPad ; branchement spawn première session | 1 |
| `src/Server/init.server.lua` | `OnboardingService.Start()` + `runSuite("OnboardingConfigTests", ...)` | 1 |
| `src/Server/BubbleService.lua` | Refresh onboarding après pop ; `GameConfig.PowerRadius` | 1, 5 |
| `src/Shared/BubbleTypes.lua` | Couleur `Rare`, flags visuels Golden+ | 2 |
| `src/Client/PopEffects.lua` | Texte flottant = valeur de vente | 2 |
| `src/Server/BackpackService.lua` | Refresh onboarding ; émission `SellResult` | 3, 4 |
| `src/Shared/LocalizationStrings.lua` | Nouvelles chaînes anglaises | 3, 4, 5, 6 |
| `src/Client/init.client.lua` | Démarrage des nouveaux modules client | 3, 4 |
| `src/Shared/Remotes.lua` | Ajout de `SellResult` dans `EVENTS` | 4 |
| `src/Client/HUD.lua` | Compteur de pièces animé convergent | 4 |
| `src/Shared/GameConfig.lua` | `FirstLevelCost`, `Speed.PerLevel`, `PowerRadius`, flags dev | 5, 7 |
| `src/Server/ShopService.lua` | Champ `Recommended` ; refresh onboarding après achat | 5 |
| `src/Client/ShopUI.lua` | Badge `RECOMMENDED` | 5 |
| `src/Client/TravelController.lua` | Neutralisation de l'auto-ouverture | 5 |
| `tools/test_progression.lua` | Mise à jour des assertions Speed + nouvelles assertions Power | 5 |
| `src/Server/ZoneBuilder.lua` | Bannière teaser Summer Zone | 6 |
| `src/Shared/AnalyticsConfig.lua` | 3 custom events + 1 mapping timing | 7 |
| `src/Server/GameAnalyticsService.lua` | `Lifetime` guides + API `OnOnboardingGuideShown` | 7 |
| `src/Server/DataService.lua` | `TEMPLATE.Analytics.Lifetime` étendu | 7 |
| `src/Shared/BubbleValue.lua` | `DEBUG_BUBBLE_VALUE = false` | 7 |

---

## Phase 0 — Commit de sauvegarde

**Objectif** : figer l'état du dépôt avant toute modification de production.

**Dépendances** : aucune.

- [ ] **Step 0.1** : `git status`, `git diff --stat`, `git log -5 --oneline`.
- [ ] **Step 0.2** : Stager **uniquement** la spec et ce plan (`docs/superpowers/specs/2026-08-01-*.md`, `docs/superpowers/plans/2026-08-01-*.md`). Ne pas embarquer le WIP non lié listé dans `git status` sans accord explicite du propriétaire.
- [ ] **Step 0.3** : commit.

**Commit** : `docs(onboarding): add first three minutes spec and implementation plan`

**Critère de réussite** : HEAD contient spec + plan ; aucun fichier `src/` modifié.

**Point d'arrêt** : ne pas écrire de Luau tant que ce commit n'existe pas.

---

## Phase 1 — Première bulle en moins de 10 secondes

### 1.1 Objectif

Le nouveau joueur apparaît **directement sur le `SpawnPad` de la salle de bulles**, tourné vers la grille, sans apparition parasite au centre du plateau et sans téléport visible. Les joueurs existants gardent exactement le spawn lobby actuel. La machine à états d'onboarding est créée et testée, mais ne pilote encore aucun affichage.

### 1.2 Fichiers à créer

- `src/Shared/OnboardingConfig.lua`
- `src/Shared/OnboardingConfigTests.lua`
- `tools/test_onboarding.lua`
- `tools/run_onboarding_tests.py`
- `src/Server/OnboardingService.lua`

### 1.3 Fichiers à modifier

- `src/Server/ZoneService.lua`
- `src/Server/init.server.lua`
- `src/Server/BubbleService.lua`

### 1.4 Ordre exact des modifications

#### Étape A — `src/Shared/OnboardingConfig.lua` (module pur, aucun `require`)

Le module ne doit dépendre d'**aucun** service Roblox et d'aucun autre module, pour rester trivialement testable.

```lua
--!strict
-- Machine à états d'onboarding : fonction pure, sans dépendance Roblox.

local OnboardingConfig = {}

OnboardingConfig.AttributeName = "OnboardingObjective"

OnboardingConfig.Objective = {
	None = "",
	Pop = "Pop",
	Sell = "Sell",
	Shop = "Shop",
}

export type Snapshot = {
	OnboardingStarted: boolean?,
	OnboardingCompleted: boolean?,
	PoppedFirstBubble: boolean?,
	SoldFirstBackpack: boolean?,
	PurchasedFirstUpgrade: boolean?,
	CurrentBubbles: number?,
	BackpackCapacity: number?,
	Coins: number?,
	CheapestUpgradeCost: number?,
}

local function boolOf(value: any): boolean
	return value == true
end

local function numberOf(value: any, fallback: number): number
	if type(value) ~= "number" then return fallback end
	if value ~= value then return fallback end          -- NaN
	if value == math.huge or value == -math.huge then return fallback end
	return value
end

function OnboardingConfig.ResolveObjective(snapshot: Snapshot?): string
	local O = OnboardingConfig.Objective
	if type(snapshot) ~= "table" then
		return O.None
	end

	if not boolOf(snapshot.OnboardingStarted) then return O.None end
	if boolOf(snapshot.OnboardingCompleted) then return O.None end
	if boolOf(snapshot.PurchasedFirstUpgrade) then return O.None end

	if not boolOf(snapshot.PoppedFirstBubble) then
		return O.Pop
	end

	if not boolOf(snapshot.SoldFirstBackpack) then
		local capacity = numberOf(snapshot.BackpackCapacity, 0)
		local current = numberOf(snapshot.CurrentBubbles, 0)
		-- Capacité invalide (<= 0) : jamais de faux « sac plein ».
		if capacity > 0 and current >= capacity then
			return O.Sell
		end
		return O.None
	end

	local cost = numberOf(snapshot.CheapestUpgradeCost, -1)
	local coins = numberOf(snapshot.Coins, 0)
	if cost > 0 and coins >= cost then
		return O.Shop
	end
	return O.None
end

-- Le spawn salle n'est accordé qu'avant le tout premier pop d'un profil neuf.
function OnboardingConfig.ShouldSpawnInGameRoom(snapshot: Snapshot?): boolean
	return OnboardingConfig.ResolveObjective(snapshot) == OnboardingConfig.Objective.Pop
end

return OnboardingConfig
```

Ajouter également dans ce module les constantes UI consommées en Phase 3 (aucune valeur en dur côté client) :

```lua
OnboardingConfig.Guide = {
	ArrowEdgeMarginRatio = 0.12,   -- marge écran, fraction du petit côté
	ArrowEdgeMarginMinPx = 48,
	TouchBottomSafeRatio = 0.22,   -- bande basse réservée joystick / saut
	BillboardStudsOffset = 8,
	BillboardMaxDistance = 0,      -- 0 = toujours visible
	UpdateWhileIdle = false,       -- pas de RenderStepped sans objectif actif
}
```

#### Étape B — `src/Shared/OnboardingConfigTests.lua`

Suite au format du dépôt : table avec `Run()` retournant `true`/`false`, affichage `PASS` / `FAIL`, comme `ShopServiceTests`. Cas obligatoires (§1.7).

#### Étape C — Harnais hors Roblox

`tools/test_onboarding.lua` : suivre le patron `tools/test_shop_service.lua` (marqueur `--@MODULES@`, `MODULE_LOADERS`, `moduleProxy`, `harnessRequire`). Aucun stub Roblox n'est nécessaire puisque `OnboardingConfig` est pur — se limiter à `warn = print` et au proxy de `require`.

`tools/run_onboarding_tests.py` : copie de `tools/run_shop_service_tests.py` avec

```python
MODULES = [
    ("OnboardingConfig", ROOT / "src" / "Shared" / "OnboardingConfig.lua"),
    ("OnboardingConfigTests", ROOT / "src" / "Shared" / "OnboardingConfigTests.lua"),
]
BUNDLE = ROOT / "tools" / "_onboarding_bundle.lua"
```

#### Étape D — `src/Server/OnboardingService.lua`

Responsabilités, et rien d'autre :

1. `OnboardingService.BuildSnapshot(player): Snapshot?` — lit `DataService.Get(player)`, retourne `nil` si absent. Remplit le snapshot depuis `profile.Analytics.OnboardingStarted`, `.OnboardingCompleted`, `.Onboarding.PoppedFirstBubble`, `.Onboarding.SoldFirstBackpack`, `.Onboarding.PurchasedFirstUpgrade`, `profile.CurrentBubbles`, `profile.BackpackCapacity`, `profile.Coins`, et `OnboardingService.CheapestUpgradeCost(profile)`.
   - **Défensif** : si `profile.Analytics` ou `.Onboarding` est absent (profil pas encore réconcilié), traiter les champs manquants comme `false`. Ne jamais écrire dans le profil ici.
2. `OnboardingService.CheapestUpgradeCost(profile): number` — minimum de `Config.UpgradeCost(id, Config.EffectiveUpgradeLevel(id, stored))` sur `Config.UpgradeOrder`, en ignorant les upgrades déjà au `Max`. Retourne `-1` si aucune n'est achetable.
3. `OnboardingService.Refresh(player)` — calcule l'objectif via `OnboardingConfig.ResolveObjective`, compare à `player:GetAttribute(OnboardingConfig.AttributeName)`, **n'écrit que si la valeur change**. En Phase 7 seulement, notifie `GameAnalyticsService` sur transition vers `Sell` / `Shop`.
4. `OnboardingService.ShouldSpawnInGameRoom(player): boolean` — `OnboardingConfig.ShouldSpawnInGameRoom(BuildSnapshot(player))`, `false` si le snapshot est `nil`.
5. `OnboardingService.Start()` — sur `Players.PlayerAdded` initialise l'attribut à `""` ; sur `PlayerRemoving` nettoie les tables internes.

**Interdits explicites** : aucun `RunService.Heartbeat`, aucun `while true`, aucune écriture dans `profile.Analytics`, aucun `RemoteEvent`.

#### Étape E — `src/Server/init.server.lua`

- Démarrer `OnboardingService.Start()` **après** `DataService` et `GameAnalyticsService`, **avant** `ZoneService`.
- Ajouter `runSuite("OnboardingConfigTests", function() return require(Shared.OnboardingConfigTests) end)` dans le bloc de validations (celui qui contient déjà `ZoneAccessTests`).

#### Étape F — `src/Server/ZoneService.lua`

1. Dans la fonction qui construit la salle (celle contenant `ensurePart(gameRoom, "GameRoomSpawn", ...)`, autour de la ligne 2273), ajouter juste après :

```lua
ensurePart(gameRoom, "GameRoomSpawnLocation", function()
	local p = Instance.new("SpawnLocation")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(12, 1, 12)
	p.Neutral = true
	p.Duration = 0
	p.AllowTeamChangeOnTouch = false
	p.Enabled = true
	-- Face au plateau : la grille est au nord (+Z) du SpawnPad.
	local base = Vector3.new(spawnPos.X, padTopY + 0.5, spawnPos.Z)
	p.CFrame = CFrame.lookAt(base, base + Vector3.new(0, 0, 10))
	return p
end)
```

   - Réutiliser les variables locales déjà présentes dans cette fonction (`spawnPos`, `padTopY`) ; **aucune coordonnée en dur**.
   - Marquer l'instance `GeneratedByCode` comme les autres parties générées (suivre exactement ce que fait `ensurePart` / `makePart` dans ce fichier).
   - ⚠️ En Studio, vérifier le sens réel du `lookAt` : si le personnage apparaît dos à la grille, remplacer par `CFrame.new(base) * CFrame.Angles(0, math.rad(180), 0)`. Le test manuel 1.9 couvre ce point.

2. Remplacer le corps de `onCharacterAdded` (ligne ~2492) :

```lua
local function onCharacterAdded(player: Player)
	if spawningInProgress[player] then
		return
	end
	spawningInProgress[player] = true
	task.spawn(function()
		local deadline = os.clock() + 10
		while not DataService.Get(player) and os.clock() < deadline do
			task.wait()
		end
		-- Profil non chargé → traité comme vétéran : repli sur le comportement actuel.
		local stayInRoom = false
		pcall(function()
			local OnboardingService = require(script.Parent.OnboardingService)
			stayInRoom = OnboardingService.ShouldSpawnInGameRoom(player)
		end)
		if not stayInRoom then
			ZoneService.TeleportToLobby(player, true)
		end
		spawningInProgress[player] = nil
	end)
end
```

   - Le `SpawnLocation` place déjà le personnage sur le pad : pour un nouveau joueur, **aucun téléport n'est appelé**.
   - Pour un vétéran, l'unique téléport d'aujourd'hui subsiste, mais il part du pad et non du centre de la grille : le flash disparaît aussi pour eux.
   - Le `pcall` protège d'une dépendance circulaire au chargement.

3. Ne rien changer à `TeleportToLobby`, `TeleportToGameRoom`, `fallResetToLobby` ni à `resolveAreaFromPosition`.

#### Étape G — `src/Server/BubbleService.lua`

Au même endroit que le hook analytics existant `notifyBubblePoppedAnalytics`, ajouter un rafraîchissement onboarding, protégé et sans coût quand il n'y a rien à faire :

```lua
pcall(function()
	require(script.Parent.OnboardingService).Refresh(player)
end)
```

Ne modifier ni la validation de distance, ni le token bucket, ni la logique de pop.

### 1.5 Dépendances

Aucune (première phase de code). Phase 0 doit être commitée.

### 1.6 Ordre d'exécution

A → B → C → **exécuter les tests** → D → E → F → G.

Écrire B (tests) **avant** D/F : la machine à états doit être verte avant tout branchement.

### 1.7 Tests à écrire

`src/Shared/OnboardingConfigTests.lua` — les 12 cas exigés, plus les gardes défensives :

| # | Cas | Entrée | Attendu |
|---|---|---|---|
| 1 | Nouveau joueur avant premier pop | `Started=true`, tout le reste faux | `"Pop"` |
| 2 | Premier pop effectué, sac vide | `Popped=true`, `Current=0`, `Cap=25` | `""` |
| 3 | Sac partiellement rempli | `Popped=true`, `Current=24`, `Cap=25` | `""` |
| 4 | Sac plein | `Popped=true`, `Current=25`, `Cap=25` | `"Sell"` |
| 5 | Sac au-delà de la capacité | `Current=30`, `Cap=25` | `"Sell"` |
| 6 | Première vente effectuée, solde insuffisant | `Sold=true`, `Coins=100`, `Cost=250` | `""` |
| 7 | Première vente effectuée, solde suffisant | `Sold=true`, `Coins=250`, `Cost=250` | `"Shop"` |
| 8 | Solde très supérieur | `Sold=true`, `Coins=9999`, `Cost=250` | `"Shop"` |
| 9 | Premier achat effectué | `Purchased=true` | `""` |
| 10 | Onboarding terminé | `Completed=true`, tout le reste vrai/faux | `""` |
| 11 | Profil vétéran | `Started=false` | `""` |
| 12 | Reconnexion pendant l'onboarding | `Started=true`, `Popped=true`, `Sold=false`, `Current=25` | `"Sell"` |
| 13 | Analytics incomplet mais réconcilié | `Started=true`, table `Onboarding` vide | `"Pop"` |
| 14 | Snapshot `nil` | `nil` | `""` |
| 15 | Capacité `0` | `Popped=true`, `Current=0`, `Cap=0` | `""` (jamais `"Sell"`) |
| 16 | Coût introuvable | `Sold=true`, `Cost=-1`, `Coins=9999` | `""` |
| 17 | Valeurs NaN / infinies | `Coins=0/0`, `Cap=math.huge` | `""`, aucune erreur |
| 18 | `ShouldSpawnInGameRoom` | cas 1 → `true` ; cas 2, 9, 11 → `false` | conforme |

### 1.8 Tests existants à exécuter

```powershell
python tools\run_onboarding_tests.py
python tools\run_progression_tests.py
python tools\run_travel_tests.py
.\tools\luau\luau-compile.exe --binary src\Shared\OnboardingConfig.lua
.\tools\luau\luau-compile.exe --binary src\Shared\OnboardingConfigTests.lua
.\tools\luau\luau-compile.exe --binary src\Server\OnboardingService.lua
.\tools\luau\luau-compile.exe --binary src\Server\ZoneService.lua
.\tools\luau\luau-compile.exe --binary src\Server\init.server.lua
.\tools\luau\luau-compile.exe --binary src\Server\BubbleService.lua
rojo build --output build.rbxlx
```

Puis Play Solo en Studio : lire l'Output et confirmer `OnboardingConfigTests`, `ZoneGameplayTests`, `ZoneAccessTests`, `BackpackServiceTests` sans `FAIL`.

### 1.9 Tests manuels Roblox Studio

⚠️ Mettre temporairement `GameConfig.World.RebuildGeneratedLayout = true` pour que le `SpawnLocation` soit créé, puis le remettre à `false` en Phase 7.

1. **Profil neuf** — effacer la clé DataStore du compte de test (`DataService` expose une réinitialisation ; sinon utiliser un `UserId` de test jamais utilisé). Play. Vérifier : apparition sur le `SpawnPad`, **face au plateau**, aucun passage visible par le centre de la grille, aucun déplacement forcé. Chronométrer le premier pop **5 fois**.
2. **Orientation** — si le personnage regarde le sud, appliquer la variante `CFrame.Angles` documentée à l'Étape F.1 et refaire le test.
3. **Profil vétéran** — forcer `Analytics.OnboardingCompleted = true` en mémoire, respawn : apparition lobby, comme avant.
4. **Profil sans analytics** — forcer `Analytics.OnboardingStarted = false` : apparition lobby.
5. **Mort / respawn** — nouveau joueur : respawn sur le pad. Vétéran : respawn lobby.
6. **FallReset** — tomber depuis la grille (Y < −25) : retour salle. Tomber depuis le lobby : retour lobby.
7. **Profil non chargé** — simuler une latence DataStore (désactiver l'accès API Studio) : le joueur doit finir au lobby, sans erreur ni double téléport.
8. **Deux joueurs** — deux clients simultanés en Studio : pas d'interférence, pas de warning `spawningInProgress`.
9. **`PlayerArea`** — vérifier que l'attribut vaut `"GameRoom"` sur le pad (`AreaSplitZ = -198`, pad à Z = −164).

### 1.10 Critères de réussite

- Premier pop < 10 s sur 5 essais consécutifs, profil neuf.
- Zéro apparition visible au centre du plateau.
- Vétéran : comportement de spawn identique à avant la phase.
- `OnboardingConfigTests` : 18 cas verts hors Roblox et en Studio.
- `ReachedMainBubbleRoom` et `PoppedFirstBubble` logués une seule fois (Output Studio).
- `rojo build` réussi.

### 1.11 Risques de régression

| Risque | Détection | Mitigation |
|---|---|---|
| Le `SpawnLocation` capture les respawns des vétérans | Test manuel 3 et 5 | `Duration = 0`, `Neutral = true` ; `TeleportToLobby` conservé pour eux |
| Orientation inversée | Test manuel 2 | Variante `CFrame.Angles` documentée |
| Dépendance circulaire `ZoneService` ↔ `OnboardingService` | Erreur au chargement en Studio | `require` tardif dans un `pcall`, jamais en haut de fichier |
| Doublon d'instance après rebuild | Test manuel après double Play | Passer par `ensurePart`, jamais `Instance.new` direct |
| Le pad est classé `Lobby` | Test manuel 9 | Vérifier `AreaSplitZ` |
| `Refresh` appelé à chaque pop = coût | Micro-profiler Studio | `Refresh` compare avant d'écrire ; aucune allocation si l'objectif est stable |

### 1.12 Rollback

`git revert` du commit de phase. Aucun champ persisté n'est ajouté : les profils créés pendant la phase restent valides. Le `SpawnLocation` généré disparaît au rebuild suivant (`GeneratedByCode`).

### 1.13 Résultat attendu avant la phase suivante

Nouveau joueur : premier pop < 10 s, mesuré. Vétéran : aucun changement observable. Machine à états testée mais **aucun guidage visible**. Tous les gates verts.

**Commit** : `feat(onboarding): spawn new players in the bubble room`

**🛑 POINT D'ARRÊT — validation Studio par le propriétaire avant la Phase 2.**

---

## Phase 2 — Lisibilité des bulles spéciales

### 2.1 Objectif

Rendre une bulle spéciale repérable sans effort pendant le premier sac, et afficher au pop la **valeur** obtenue plutôt qu'un marqueur générique. Aucun changement de poids ni de `SellValue`.

### 2.2 Fichiers à créer

Aucun.

### 2.3 Fichiers à modifier

- `src/Shared/BubbleTypes.lua`
- `src/Server/BubbleService.lua` (application de l'apparence)
- `src/Client/PopEffects.lua`

### 2.4 Ordre exact des modifications

#### Étape A — `src/Shared/BubbleTypes.lua`

1. `Rare` : remplacer `Color3.fromRGB(90, 170, 255)` par un bleu nettement plus saturé et plus sombre que toutes les `TintVariants` de `GameConfig.Bubble.Appearance` (cible : distance RGB ≥ 90 par rapport à chaque variante). Valeur de départ recommandée : `Color3.fromRGB(40, 90, 235)`.
2. Ajouter des flags **déclaratifs** par rareté, sans logique :

```lua
{ Id = "Rare", ..., ScaleBoost = 1.08 },
{ Id = "Golden", ..., ScaleBoost = 1.12, Glow = true },
{ Id = "Diamond", ..., ScaleBoost = 1.15, Glow = true },
{ Id = "Legendary", ..., ScaleBoost = 1.2, Glow = true, Announce = true },
```

3. Ne pas toucher `Weight`, `StorageValue`, `SellValue`, `Coins`.

#### Étape B — `src/Server/BubbleService.lua`

Dans `buildBubble` (autour de la ligne 292, là où `part.CFrame`, `Color`, `Material` sont posés) :

1. Appliquer `ScaleBoost` en multipliant la taille déjà calculée depuis `Config.Bubble.MeshScale`. Ne jamais dépasser `Config.Grid.Spacing` pour éviter le chevauchement : clamper la taille finale à `Spacing - 0.2` sur X et Z.
2. Si `def.Glow == true` : `Material = Enum.Material.Neon` et ajouter **un seul** `PointLight` (`Brightness` ≤ 1.5, `Range` ≤ 8, `Shadows = false`).
3. Sur la régénération, l'apparence doit être **réappliquée intégralement** (couleur, taille, matériau, présence/absence du `PointLight`). Le `PointLight` d'une bulle qui redevient `Normal` doit être détruit, sinon il fuit.
4. `GameConfig.ZoneBubblePalettes` ne teinte que les `Normal` : vérifier que le chemin de teinte de zone n'écrase pas les couleurs de rareté.

Budget : `Glow` concerne Golden + Diamond + Legendary = 38/1148 ≈ 3,31 % → ~53 `PointLight` sur 1600 cellules. C'est l'ordre de grandeur validé ; si le profiler montre une dégradation, retirer le `PointLight` et garder `Neon` seul.

#### Étape C — `src/Client/PopEffects.lua`

Dans le handler `PopEffects` (ligne ~112-124) : remplacer `floatingText(pos, "+" .. storageValue, def.Color)` par l'affichage de la **valeur de vente** de la bulle. Le batch d'effets doit donc transporter la rareté (déjà le cas via `entry[3]`) : lire `BubbleTypes.ById[rarity].SellValue` côté client — pas besoin d'élargir le payload réseau.

Conserver le filtre de distance à 140 studs et le seuil `special` existants.

### 2.5 Dépendances

Phase 1 commitée (pas de dépendance fonctionnelle, mais l'ordre des commits doit être respecté).

### 2.6 Tests à écrire

Ajouter à `src/Shared/ZoneGameplayTests.lua` (suite existante déjà chargée en Studio) :

- Contraste : pour chaque `TintVariants` de `GameConfig.Bubble.Appearance`, distance RGB à `BubbleTypes.ById.Rare.Color` ≥ 90.
- Contraste : `Rare` vs `Normal` ≥ 90.
- Chaque rareté non-`Normal` possède un `ScaleBoost` numérique > 1.
- `Normal` n'a ni `ScaleBoost` ni `Glow`.
- Taille finale (`MeshScale` × `ScaleBoost` × `BubbleSize`) < `Grid.Spacing` sur X et Z pour toutes les raretés.
- Nombre de raretés `Glow` ≤ 4 (garde-fou budget).

### 2.7 Tests existants à exécuter

```powershell
python tools\run_progression_tests.py
.\tools\luau\luau-compile.exe --binary src\Shared\BubbleTypes.lua
.\tools\luau\luau-compile.exe --binary src\Server\BubbleService.lua
.\tools\luau\luau-compile.exe --binary src\Client\PopEffects.lua
.\tools\luau\luau-compile.exe --binary src\Shared\ZoneGameplayTests.lua
rojo build --output build.rbxlx
```

Studio : `ZoneGameplayTests`, `BubbleValueTests`, `ItemSpawnTests`, `SummerZoneStringLightsTests` sans `FAIL`.

### 2.8 Tests manuels Roblox Studio

1. Parcourir le plateau : repérer une spéciale sans zoom depuis ~40 studs.
2. Éclater 30 bulles : au moins une spéciale nettement identifiée.
3. Vérifier le texte flottant : il affiche bien la valeur de vente (`+8`, `+45`, `+220`, `+1800`).
4. Attendre 30 s de régénération sur une cellule Golden : la bulle régénérée en `Normal` ne conserve **aucun** `PointLight` ni `Neon`.
5. Summer Zone (compte niveau ≥ 5) : la teinte orange des `Normal` n'affecte pas les couleurs de rareté.
6. FPS : émulateur mobile, comparer avant/après sur la même position.
7. Compter les instances : `#workspace:GetDescendants()` stable après plusieurs cycles de régénération (pas de fuite de `PointLight`).

### 2.9 Critères de réussite

- Une spéciale est identifiable à 40 studs sans zoom.
- Aucune fuite d'instance après 3 cycles de régénération.
- Aucune perte de FPS mesurable en émulation mobile.
- `FirstSpecialBubble` toujours logué une seule fois par profil.
- Aucune valeur économique modifiée (`run_progression_tests.py` vert).

### 2.10 Risques de régression

| Risque | Mitigation |
|---|---|
| Chevauchement visuel des bulles agrandies | Clamp à `Spacing - 0.2`, test automatisé |
| Fuite de `PointLight` à la régénération | Destruction explicite + test manuel 7 |
| Coût de rendu mobile | Test manuel 6, repli `Neon` seul |
| Palette Summer écrase les raretés | Test manuel 5 |

### 2.11 Rollback

`git revert` du commit de phase. Purement visuel, aucun impact sur les données.

### 2.12 Résultat attendu avant la phase suivante

Les spéciales se voient. Aucun changement d'économie. Tous les gates verts.

**Commit** : `feat(bubbles): make special rarities readable at a glance`

**🛑 POINT D'ARRÊT — validation Studio avant la Phase 3.**

---

## Phase 3 — Guidage vers la vente

### 3.1 Objectif

Quand le sac d'un nouveau joueur devient plein, afficher un guidage visuel non bloquant vers le kiosque, qui s'éteint dès la vente. Le joueur garde 100 % du contrôle.

### 3.2 Fichiers à créer

- `src/Client/OnboardingGuide.lua`

### 3.3 Fichiers à modifier

- `src/Server/OnboardingService.lua` (rien à ajouter si la Phase 1 est complète — sinon compléter `Refresh`)
- `src/Server/BackpackService.lua`
- `src/Client/init.client.lua`
- `src/Shared/LocalizationStrings.lua`
- `src/Shared/OnboardingConfig.lua` (table de cibles)

### 3.4 Ordre exact des modifications

#### Étape A — `src/Shared/LocalizationStrings.lua`

Ajouter, en anglais, en suivant la nomenclature de clés existante :

```
OnboardingGuideSell = "SELL"
OnboardingGuideShop = "SHOP"
OnboardingGuidePop  = "POP BUBBLES"
```

#### Étape B — `src/Shared/OnboardingConfig.lua`

Ajouter une résolution de cible **par configuration**, jamais par instance :

```lua
-- Retourne la clé de position à lire dans GameConfig / ZoneDefs. Le client
-- résout la Vector3 ; aucune instance du Workspace n'est requise (StreamingEnabled).
OnboardingConfig.TargetByObjective = {
	Pop  = "GameRoomFirstRow",
	Sell = "LobbySellPad",
	Shop = "LobbyItemShop",
}

OnboardingConfig.LabelKeyByObjective = {
	Pop  = "OnboardingGuidePop",
	Sell = "OnboardingGuideSell",
	Shop = "OnboardingGuideShop",
}
```

#### Étape C — `src/Client/OnboardingGuide.lua`

Contrat strict :

**Résolution des cibles** (StreamingEnabled-safe)

```lua
local function resolveTarget(key: string): Vector3?
	if key == "LobbySellPad" then
		return Config.Lobby.SellPosition
	elseif key == "LobbyItemShop" then
		return Config.Lobby.ItemShopPosition
	elseif key == "GameRoomFirstRow" then
		local sizeX = select(1, ZoneDefs.GetGridSize("ClassicZone"))
		return ZoneDefs.CellToWorld(math.floor(sizeX / 2), 1, "ClassicZone")
	end
	return nil
end
```

Aucun `FindFirstChild` sur le Workspace, aucun `WaitForChild` sur une pièce générée.

**Waypoint 3D**

- Un seul `Attachment` créé sous `workspace.Terrain` (jamais streamé, toujours présent), `WorldPosition = target + Vector3.new(0, Guide.BillboardStudsOffset, 0)`.
- Un `BillboardGui` avec `Adornee = attachment`, `AlwaysOnTop = true`, `MaxDistance = 0`, `Size` en `UDim2.fromScale` pour rester lisible à toute résolution, `Active = false`.
- Contenu : icône + libellé localisé. L'icône porte le sens ; le texte est un renfort.

**Flèche d'écran**

- Un `ScreenGui` dédié, `ResetOnSpawn = false`, `IgnoreGuiInset = false`, `DisplayOrder` **strictement inférieur** à celui du `ScreenGui` de `HUD.lua` (relever la valeur réelle dans `HUD.lua` et documenter le choix dans un commentaire).
- Un `ImageLabel` (`Active = false`), pivoté par `Rotation`.
- Calcul par frame : `local pos, onScreen = camera:WorldToViewportPoint(target)`. Si `onScreen == true` et `pos.Z > 0` → masquer la flèche (le waypoint suffit). Sinon, projeter la direction, clamper dans un rectangle inset de `GuiService:GetGuiInset()` et d'une marge `max(ArrowEdgeMarginMinPx, min(viewport.X, viewport.Y) * ArrowEdgeMarginRatio)`.
- Sur `UserInputService.TouchEnabled`, exclure en plus la bande basse `TouchBottomSafeRatio` de la hauteur (joystick à gauche, saut à droite).
- Console : aucune sélection `GuiObject`, aucun `SelectionGroup` — la flèche ne doit jamais entrer dans la navigation manette.

**Cycle de vie**

- `Start()` : lit l'attribut courant, s'abonne à `player:GetAttributeChangedSignal(OnboardingConfig.AttributeName)`.
- `apply(objective)` : si `objective == ""` → `teardown()` (détruit `Attachment`, `BillboardGui`, `ScreenGui`, **et déconnecte `RenderStepped`**). Sinon → `teardown()` puis reconstruction pour la nouvelle cible et connexion de `RenderStepped`.
- `RenderStepped` n'est connecté **que** tant qu'un objectif est actif — c'est la garantie « aucun polling permanent ».
- `player.CharacterRemoving` et `CharacterAdded` → `teardown()` puis réapplication de l'objectif courant.
- `Stop()` public → `teardown()` + déconnexion de tous les signaux, stockés dans une table `connections` unique.
- Aucun `ContextActionService`, aucun `UserInputService` en capture, aucun `camera.CameraType` modifié, aucun `GuiObject.Modal`.

#### Étape D — `src/Client/init.client.lua`

Ajouter `require(script.OnboardingGuide)` à la liste `modules`, **après** `HUD` (pour que le `DisplayOrder` du HUD existe déjà) et avant `TravelController`.

#### Étape E — `src/Server/BackpackService.lua`

Ajouter un `Refresh` onboarding après **chaque** mutation réussie du sac, hors du verrou :

- dans `AddBubbles`, après un retour `ok == true` ;
- dans `Sell`, après le `DataService.Push(player)` du chemin succès ;
- dans `ResetSession`, après succès.

Forme, identique aux hooks analytics déjà présents dans ce fichier :

```lua
pcall(function()
	require(script.Parent.OnboardingService).Refresh(player)
end)
```

**Ne pas** appeler `Refresh` à l'intérieur de `runLocked` : le verrou doit rester le plus court possible.

Ne modifier ni `doSell`, ni le crédit de pièces, ni `NotifyFull`, ni la vente automatique.

### 3.5 Dépendances

Phase 1 (machine à états + `OnboardingService.Refresh` + attribut).

### 3.6 Tests à écrire

Dans `src/Shared/OnboardingConfigTests.lua` :

- `TargetByObjective` et `LabelKeyByObjective` couvrent exactement `Pop`, `Sell`, `Shop` et rien d'autre.
- Chaque `LabelKeyByObjective` correspond à une clé existante de `LocalizationStrings`.
- `ResolveObjective` reste inchangée (non-régression des 18 cas de la Phase 1).

Dans `src/Shared/ZoneGameplayTests.lua` :

- `Config.Lobby.SellPosition` et `Config.Lobby.ItemShopPosition` sont hors grille (réutiliser l'assertion `assertOutsideGrid` déjà appliquée dans `GameConfig`).
- La cible `GameRoomFirstRow` calculée par `ZoneDefs.CellToWorld(20, 1, "ClassicZone")` est à moins de 60 studs du `SpawnPad`.

### 3.7 Tests existants à exécuter

```powershell
python tools\run_onboarding_tests.py
python tools\run_progression_tests.py
.\tools\luau\luau-compile.exe --binary src\Client\OnboardingGuide.lua
.\tools\luau\luau-compile.exe --binary src\Client\init.client.lua
.\tools\luau\luau-compile.exe --binary src\Server\BackpackService.lua
.\tools\luau\luau-compile.exe --binary src\Shared\OnboardingConfig.lua
.\tools\luau\luau-compile.exe --binary src\Shared\LocalizationStrings.lua
rojo build --output build.rbxlx
```

Studio : `BackpackServiceTests`, `OnboardingConfigTests`, `ZoneGameplayTests` sans `FAIL`.

### 3.8 Tests manuels Roblox Studio

1. Profil neuf : remplir 25 bulles. La flèche + le waypoint apparaissent en < 0,5 s.
2. Suivre le guidage jusqu'au kiosque. Vente automatique. Le guidage disparaît en < 0,5 s.
3. **Ignorer** la flèche : continuer à popper, sauter, courir, tourner la caméra — tout doit rester pleinement contrôlable.
4. Se déconnecter sac plein, revenir : la flèche revient (comportement attendu).
5. Vétéran : jamais de flèche.
6. Mourir avec le sac plein : après respawn, le guidage se reconstruit une seule fois, sans instance dupliquée.
7. Faire un aller-retour salle ↔ lobby avec `StreamingEnabled` : la flèche pointe correctement même quand le kiosque n'est pas streamé.
8. **PC** clavier/souris, **tactile** (émulateur, portrait et paysage), **manette** : la flèche ne prend jamais le focus, ne couvre ni le joystick ni le bouton de saut.
9. Inspecter l'Explorer après 5 cycles d'apparition/disparition : aucun `Attachment` ni `ScreenGui` orphelin.
10. Vérifier au micro-profiler que `RenderStepped` du module n'apparaît pas quand l'objectif est `""`.

### 3.9 Critères de réussite

- Apparition < 0,5 s après saturation, disparition < 0,5 s après la vente.
- Zéro guidage pour un vétéran.
- Zéro blocage de mouvement, de saut, de pop ou de caméra.
- Zéro instance orpheline, zéro connexion résiduelle.
- Vente toujours automatique, montant inchangé.
- `BackpackFullFirstTime` et `ReturnedToLobbyAfterFullBackpack` logués une seule fois.

### 3.10 Risques de régression

| Risque | Mitigation |
|---|---|
| Fuite d'instances au respawn | `teardown()` sur `CharacterRemoving`, test manuel 9 |
| Waypoint qui masque le HUD | `DisplayOrder` inférieur au HUD, test manuel 8 |
| Cible non streamée | Positions issues de `GameConfig`, test manuel 7 |
| Flèche capturée par la navigation manette | `Active = false`, aucun `Selectable`, test manuel 8 |
| `Refresh` sous verrou → deadlock | Appels hors `runLocked`, revue de code obligatoire |
| Flèche sous le joystick mobile | `TouchBottomSafeRatio`, test manuel 8 |

### 3.11 Rollback

`git revert` du commit de phase. Le serveur continue de publier l'attribut : sans le module client, il est simplement ignoré. Aucun impact données.

### 3.12 Résultat attendu avant la phase suivante

Un nouveau joueur trouve le kiosque sans aide extérieure. Vente en < 80 s. Aucun vétéran affecté.

**Commit** : `feat(onboarding): guide new players to the sell kiosk`

**🛑 POINT D'ARRÊT — validation Studio avant la Phase 4.**

---

## Phase 4 — Récompense de vente lisible

### 4.1 Objectif

Rendre la vente spectaculaire et faire comprendre que **les pièces viennent de la vente**. Le feedback est purement visuel et ne devient jamais une source de vérité économique.

### 4.2 Fichiers à créer

- `src/Client/SellFeedback.lua`

### 4.3 Fichiers à modifier

- `src/Shared/Remotes.lua`
- `src/Server/BackpackService.lua`
- `src/Client/HUD.lua`
- `src/Client/init.client.lua`
- `src/Shared/LocalizationStrings.lua`

### 4.4 Ordre exact des modifications

#### Étape A — `src/Shared/Remotes.lua`

Ajouter `"SellResult"` à la table `EVENTS` (serveur → client), avec un commentaire dans le style du fichier :

```lua
"SellResult",        -- serveur -> client : { sold, earned, balance } (FX uniquement)
```

#### Étape B — `src/Server/BackpackService.lua`

Dans `BackpackService.Sell`, chemin succès uniquement (après `DataService.Push(player)`, à côté du `safeFireClient("Announce", ...)` existant) :

```lua
safeFireClient("SellResult", player, {
	sold = sold,
	earned = earned,
	balance = DataService.GetCoins(player),
})
```

- Utiliser `safeFireClient` (déjà en place, protégé) et **jamais** `FireAllClients`.
- Si `DataService` n'expose pas de lecteur de solde public, réutiliser le `endingBalance` déjà retourné par `DataService.AddCoins` dans `doSell` en le remontant par `doSell` — **ne pas** ajouter d'accès direct au profil depuis `Sell`.
- Conserver le toast `Announce` existant : il reste le canal texte, `SellResult` est le canal FX.
- Ne rien changer au crédit, au vidage du sac, à `AddBubblesSold`, ni au hook analytics.

#### Étape C — `src/Client/SellFeedback.lua`

- Valide le payload : `type(payload) == "table"`, `sold` et `earned` entiers finis > 0, `balance` nombre fini ≥ 0. Tout payload non conforme est **ignoré silencieusement**.
- Joue au niveau de `Config.Lobby.SellPosition` (position de config, jamais une instance) : gerbe de particules dorées, texte 3D `+N COINS` (clé localisée), son.
- Limite le nombre de FX simultanés (au plus 2 gerbes actives ; au-delà, remplacer la plus ancienne) pour tenir les ventes rapprochées.
- Nettoyage : `Debris` ou `task.delay` + `Destroy()`, plus `teardown()` sur `CharacterRemoving` et `Stop()`.

#### Étape D — `src/Client/HUD.lua`

Animer le compteur de pièces avec **convergence garantie** :

- Sur `SellResult`, animer de la valeur affichée vers `payload.balance`.
- À la fin de l'animation **et** à chaque `GetAttributeChangedSignal("Coins")`, écrire la valeur **répliquée par le serveur**, pas la valeur animée.
- Si l'attribut `Coins` change pendant l'animation, l'animation est annulée et la valeur serveur s'impose immédiatement.

Cette règle est non négociable : le HUD affiche toujours, à l'état stable, l'attribut serveur.

#### Étape E — `src/Client/init.client.lua`

Ajouter `require(script.SellFeedback)` après `HUD`.

### 4.5 Dépendances

Phase 3 (le guidage doit déjà amener le joueur au kiosque pour tester le parcours complet).

### 4.6 Tests à écrire

Dans `src/Server/BackpackServiceTests.lua` (suite Studio existante) :

- Une vente réussie émet exactement **un** `SellResult`.
- Le payload `sold` et `earned` est **identique** aux valeurs retournées par `Sell` et au montant crédité.
- Une vente sur sac vide (`"empty"`) n'émet **aucun** `SellResult`.
- Un échec de crédit (`"credit_failed"`) n'émet **aucun** `SellResult`.
- Un échec de verrou n'émet **aucun** `SellResult`.
- Le montant crédité et `AddBubblesSold` sont inchangés par rapport à la version précédente de la suite.

Réutiliser `BackpackService.SetAnnounceHandlerForTests` comme modèle si un point d'injection est nécessaire pour observer `SellResult`.

### 4.7 Tests existants à exécuter

```powershell
python tools\run_progression_tests.py
python tools\run_onboarding_tests.py
.\tools\luau\luau-compile.exe --binary src\Shared\Remotes.lua
.\tools\luau\luau-compile.exe --binary src\Server\BackpackService.lua
.\tools\luau\luau-compile.exe --binary src\Server\BackpackServiceTests.lua
.\tools\luau\luau-compile.exe --binary src\Client\SellFeedback.lua
.\tools\luau\luau-compile.exe --binary src\Client\HUD.lua
rojo build --output build.rbxlx
```

Studio : `BackpackServiceTests`, `GameAnalyticsServiceTests`, `DataServiceAnalyticsTests` sans `FAIL`.

### 4.8 Tests manuels Roblox Studio

1. Vendre un petit sac (5 bulles) puis un gros sac (25) : FX proportionné et lisible dans les deux cas.
2. Vendre 3 fois en 5 s : pas d'accumulation d'instances, pas de chute de FPS.
3. Vérifier que le solde final affiché **égale** l'attribut `Coins` (comparer dans l'Explorer).
4. Provoquer un changement de solde pendant l'animation (coffre, code admin) : le HUD converge sur la valeur serveur.
5. Vendre un sac vide : aucun FX, message existant conservé.
6. Vérifier que les pièces ne sont jamais créditées ailleurs qu'à la vente (revue de `DataService.AddCoins` : sources autorisées inchangées).
7. Mobile portrait : le texte `+N COINS` reste lisible et ne sort pas de l'écran.

### 4.9 Critères de réussite

- Les pièces restent créditées **uniquement** dans `doSell`.
- Le montant affiché est toujours égal au montant crédité.
- Le HUD converge systématiquement sur l'attribut serveur.
- Aucun `SellResult` sur les chemins d'échec.
- `SoldFirstBackpack` et `LogBackpackSaleEconomy` inchangés, logués une seule fois.

### 4.10 Risques de régression

| Risque | Mitigation |
|---|---|
| Compteur animé désynchronisé | Convergence forcée sur l'attribut, test manuel 3 et 4 |
| FX utilisé comme vérité économique | Validation stricte du payload, revue de code |
| Accumulation d'instances | Plafond de 2 gerbes, test manuel 2 |
| Client ancien sans `SellResult` | Le serveur émet sans attendre de réponse ; aucun chemin serveur n'en dépend |

### 4.11 Rollback

`git revert`. Le Remote `SellResult` disparaît ; `Announce` reste le canal de secours déjà en place.

### 4.12 Résultat attendu avant la phase suivante

La vente est visiblement gratifiante et le lien pop → vente → pièces est explicite. Aucun changement économique.

**Commit** : `feat(sell): add readable coin reward feedback on sale`

**🛑 POINT D'ARRÊT — validation Studio avant la Phase 5.**

---

## Phase 5 — Guidage vers la première amélioration (Speed, Power, Transit)

### 5.1 Objectif

Rendre le premier achat atteignable en < 180 s et **perceptible**, le recommander explicitement, corriger le niveau 1 de `Power`, et neutraliser l'auto-ouverture de Bubble Transit pendant la première boucle.

### 5.2 Fichiers à créer

Aucun.

### 5.3 Fichiers à modifier

- `src/Shared/GameConfig.lua`
- `src/Server/BubbleService.lua`
- `src/Server/ShopService.lua`
- `src/Client/ShopUI.lua`
- `src/Client/TravelController.lua`
- `src/Client/OnboardingGuide.lua`
- `src/Shared/LocalizationStrings.lua`
- `tools/test_progression.lua`

### 5.4 Ordre exact des modifications

#### Étape A — `src/Shared/GameConfig.lua` : coût du premier niveau

```lua
Speed = {
	Label = "Speed",
	Max = 15,
	BaseCost = 750,
	FirstLevelCost = 250,
	Growth = 1.45,
	PerLevel = 2.0,
},
```

```lua
function GameConfig.UpgradeCost(id: string, currentLevel: number): number
	local def = GameConfig.Upgrades[id]
	if not def then return math.huge end
	if currentLevel <= 0 and def.FirstLevelCost then
		return def.FirstLevelCost
	end
	return math.floor(def.BaseCost * (def.Growth ^ currentLevel))
end
```

Conséquences arithmétiques à vérifier par test :

| Appel | Avant | Après |
|---|---|---|
| `UpgradeCost("Speed", 0)` | 750 | **250** |
| `UpgradeCost("Speed", 1)` | 1087 | **1087** (inchangé) |
| `UpgradeCost("Speed", 2)` | 1576 | **1576** (inchangé) |
| `UpgradeCost("Jump", 0)` | 1000 | 1000 |
| `UpgradeCost("Power", 0)` | 3000 | 3000 |
| `UpgradeCost("CoinMult", 0)` | 2500 | 2500 |

WalkSpeed résultant (`DataService.ApplyCharacterStats`, clamp `MaxWalkSpeed = 80`) :

| Niveau Speed | Avant | Après |
|---|---|---|
| 0 | 16 | 16 |
| 1 | 17 | **18** |
| 7 | 23 | **30** |
| 15 (max) | 31 | **46** |

`46 < 80` : le clamp n'est jamais atteint. Ne pas modifier `MaxWalkSpeed`.

#### Étape B — `src/Shared/GameConfig.lua` : rayon de Power

Extraire la formule dans la configuration centrale, pour la rendre testable par le harnais existant :

```lua
-- Rayon de pop en cellules. Niveau 1 doit produire un effet réel (rayon 1),
-- sinon l'amélioration est achetée sans conséquence.
function GameConfig.PowerRadius(effectiveLevel: number): number
	local level = if type(effectiveLevel) == "number" then math.floor(effectiveLevel) else 0
	if level <= 0 then
		return 0
	end
	return math.ceil(level / 2)
end
```

Cellules affectées = `(2r + 1)^2` :

| Niveau | Rayon | Cellules |
|---|---|---|
| 0 | 0 | 1 |
| 1 | **1** | **9** |
| 2 | 1 | 9 |
| 3 | 2 | 25 |
| 4 | 2 | 25 |
| 5 | 3 | 49 |
| 6 | 3 | 49 |
| 7 | 4 | 81 |
| 8 (max) | 4 | 81 |

#### Étape C — `src/Server/BubbleService.lua`

Ligne ~767-773, remplacer le calcul inline :

```lua
local power = Config.EffectiveUpgradeLevel("Power", profile.Upgrades.Power or 0)

local cells: { { any } } = { { x, z, zoneId } }
local r = Config.PowerRadius(power)
if r > 0 then
	cells = {}
	-- … remplissage existant, inchangé
end
```

**Conserver intégralement** la validation serveur en aval : bornes de grille (`ZoneDefs.InBounds`), `CanLevelEnter`, portée max (`MaxPopRange` / `WingPopRange`), token bucket `MaxPopsPerSecond`. Le rayon élargit la sélection de cellules, il n'assouplit aucune vérification.

#### Étape D — `src/Server/ShopService.lua`

1. Dans `getCategoryRows` (ligne ~131-146), après le calcul de `row.ButtonState` pour les upgrades, marquer la recommandation :

```lua
-- Recommandation onboarding : uniquement tant que le joueur n'a acheté aucune amélioration.
row.Recommended = false
```

puis, après la boucle de construction des lignes, une passe unique qui marque `Recommended = true` sur **la ligne d'upgrade la moins chère** si et seulement si :
- `profile.Analytics.OnboardingCompleted ~= true`, **et**
- aucun upgrade de `Config.UpgradeOrder` n'a un niveau effectif > 0.

Ne pas déduire cet état côté client.

2. Dans `buyUpgrade`, après le succès (à côté de `notifyUpgradePurchased`), ajouter :

```lua
pcall(function()
	require(script.Parent.OnboardingService).Refresh(player)
end)
```

3. Dans `src/Server/DataService.lua`, à l'endroit où le solde change (`notifyCoinsChanged`), ajouter le même `Refresh` protégé : c'est ce qui fait passer l'objectif à `Shop` dès que le solde suffit, sans polling.

#### Étape E — `src/Client/ShopUI.lua`

Afficher un badge `RECOMMENDED` (clé localisée `ShopRecommendedBadge = "RECOMMENDED"`) sur la ligne dont `row.Recommended == true`. Le client **ne calcule rien** : il lit le champ.

Contrainte de mise en page : le badge ne doit pas déborder en portrait mobile ni décaler le bouton d'achat. Utiliser le style de badge déjà présent dans le fichier si un équivalent existe.

#### Étape F — `src/Client/TravelController.lua`

Réutiliser le mécanisme **déjà présent** `travelSuppressedUntil` plutôt que d'en créer un second. Dans le `Heartbeat` (ligne ~647-661), la condition d'auto-ouverture devient :

```lua
local objective = player:GetAttribute(OnboardingConfig.AttributeName)
local suppressedByOnboarding = objective == OnboardingConfig.Objective.Pop
	or objective == OnboardingConfig.Objective.Sell

if isInside and not wasInside and os.clock() >= travelSuppressedUntil and not suppressedByOnboarding then
	openMenu(transitId :: string)
elseif …
```

Règles strictes :
- Le pad n'est **ni supprimé, ni désactivé, ni déplacé**.
- `openMenu` reste appelable manuellement et par tout autre chemin existant.
- Après la première vente, l'objectif passe à `Shop` ou `""` → l'auto-ouverture revient d'elle-même.
- Un vétéran a `objective == ""` → aucun changement de comportement.

#### Étape G — `src/Client/OnboardingGuide.lua`

Aucune modification structurelle : la cible `Shop` est déjà déclarée en Phase 3. Vérifier seulement que la transition `Sell → Shop` fait bien un `teardown()` complet avant reconstruction.

#### Étape H — `tools/test_progression.lua`

Mettre à jour l'assertion existante de la ligne 106 et ajouter les nouvelles :

```lua
check("UpgradeCost Speed lv0 (first level discount)", Config.UpgradeCost("Speed", 0), 250)
check("UpgradeCost Speed lv1 inchangé", Config.UpgradeCost("Speed", 1), 1087)
check("UpgradeCost Speed lv2 inchangé", Config.UpgradeCost("Speed", 2), 1576)
check("UpgradeCost Jump lv0 inchangé", Config.UpgradeCost("Jump", 0), 1000)
check("UpgradeCost Power lv0 inchangé", Config.UpgradeCost("Power", 0), 3000)
check("UpgradeCost CoinMult lv0 inchangé", Config.UpgradeCost("CoinMult", 0), 2500)
check("Speed PerLevel", Config.Upgrades.Speed.PerLevel, 2.0)
check("WalkSpeed niveau 1", Config.PlayerMovement.WalkSpeed + 1 * Config.Upgrades.Speed.PerLevel, 18)
check("WalkSpeed niveau max", Config.PlayerMovement.WalkSpeed + Config.Upgrades.Speed.Max * Config.Upgrades.Speed.PerLevel, 46)
check("WalkSpeed max sous plafond",
	(Config.PlayerMovement.WalkSpeed + Config.Upgrades.Speed.Max * Config.Upgrades.Speed.PerLevel) <= Config.PlayerMovement.MaxWalkSpeed, true)
check("PowerRadius(0)", Config.PowerRadius(0), 0)
check("PowerRadius(1) > 0 (niveau acheté = effet réel)", Config.PowerRadius(1), 1)
check("PowerRadius(2)", Config.PowerRadius(2), 1)
check("PowerRadius(3)", Config.PowerRadius(3), 2)
check("PowerRadius(4)", Config.PowerRadius(4), 2)
check("PowerRadius(5)", Config.PowerRadius(5), 3)
check("PowerRadius(8) max", Config.PowerRadius(8), 4)
check("cellules Power niveau 1", (2 * Config.PowerRadius(1) + 1) ^ 2, 9)
check("cellules Power niveau 3", (2 * Config.PowerRadius(3) + 1) ^ 2, 25)
```

Ajouter aussi une boucle anti-régression « niveau acheté mais sans effet » :

```lua
local allLevelsEffective = true
for level = 1, Config.Upgrades.Power.Max do
	if Config.PowerRadius(level) < 1 then allLevelsEffective = false end
end
check("aucun niveau de Power sans effet", allLevelsEffective, true)
```

Le test de saut existant (ligne 95, `57.5`) reste valide : `Jump` n'est pas modifié.

### 5.5 Dépendances

Phases 1, 3 et 4 (le guidage et le parcours de vente doivent être en place pour valider le chrono jusqu'à l'achat).

### 5.6 Ordre d'exécution

H (tests d'abord, ils échouent) → A → B → **relancer `run_progression_tests.py` jusqu'au vert** → C → D → E → F → G.

### 5.7 Tests à écrire

En plus de l'Étape H, dans `src/Server/ShopServiceTests.lua` :

- `GetShopData` marque `Recommended = true` sur exactement **une** ligne pour un profil neuf sans upgrade.
- La ligne recommandée est celle de coût minimal (`Speed` à 250).
- `Recommended` est `false` partout si `Analytics.OnboardingCompleted == true`.
- `Recommended` est `false` partout si un upgrade a un niveau > 0.
- Après achat de `Speed`, le solde et le niveau sont corrects avec le nouveau coût de 250.
- Achat impossible à 249 pièces, possible à 250.
- Aucun `ButtonState` existant n'est modifié par l'ajout du champ.

Dans `src/Shared/OnboardingConfigTests.lua` :

- Aucun changement de `ResolveObjective` (non-régression des 18 cas).

### 5.8 Tests existants à exécuter

```powershell
python tools\run_progression_tests.py
python tools\run_shop_service_tests.py
python tools\run_shop_catalog_tests.py
python tools\run_shop_browse_logic_tests.py
python tools\run_shop_layout_tests.py
python tools\run_shop_viewport_tests.py
python tools\run_onboarding_tests.py
python tools\run_travel_tests.py
.\tools\luau\luau-compile.exe --binary src\Shared\GameConfig.lua
.\tools\luau\luau-compile.exe --binary src\Server\BubbleService.lua
.\tools\luau\luau-compile.exe --binary src\Server\ShopService.lua
.\tools\luau\luau-compile.exe --binary src\Server\DataService.lua
.\tools\luau\luau-compile.exe --binary src\Client\ShopUI.lua
.\tools\luau\luau-compile.exe --binary src\Client\TravelController.lua
rojo build --output build.rbxlx
```

Studio : `ShopServiceTests`, `ShopCatalogTests`, `ShopBrowseLogicTests`, `ShopBrowseLayoutTests`, `ItemShopVisualTests`, `TravelConfigTests`, `BackpackServiceTests`, `ChestServiceTests` sans `FAIL`.

### 5.9 Tests manuels Roblox Studio

1. **Parcours complet profil neuf**, chronométré : spawn → premier pop → sac plein → vente 1 → boucle 2 → vente 2 → achat. Cible : achat en < 180 s.
2. Ressentir la différence de vitesse avant/après achat (test à l'aveugle si possible).
3. Vétéran avec `Speed = 3` : le prix affiché doit être `UpgradeCost("Speed", 3) = 2285`, inchangé ; sa vitesse passe de 19 à 22 (buff rétroactif attendu).
4. Vétéran avec `Speed = 15` : WalkSpeed = 46, aucun warning de clamp.
5. Acheter `Power` niveau 1 (en s'octroyant les pièces en Studio) : le pop affecte visiblement **9 cellules**.
6. Vérifier que `Power` ne permet pas de dépasser les bornes de grille ni la portée max (tester en bord de plateau et à 20 studs).
7. Marcher sur le pad Transit **avant** la première vente : aucune modale.
8. Marcher sur le pad Transit **après** la première vente : modale normale.
9. Vétéran sur le pad Transit : modale normale, immédiatement.
10. `ShopUI` en portrait mobile et en 4K : le badge `RECOMMENDED` ne casse pas la mise en page.
11. Navigation manette dans `ShopUI` : le badge n'entre pas dans l'ordre de sélection.

### 5.10 Critères de réussite

- Premier achat réalisable avec les gains de la vente 1 ou 2.
- Différence de vitesse perçue.
- Aucun prix modifié hors `Speed` niveau 1.
- `Power` niveau 1 affecte 9 cellules ; validation serveur intacte.
- Auto-ouverture Transit neutralisée uniquement pendant `Pop` / `Sell`, pad jamais supprimé.
- `PurchasedFirstUpgrade` logué une seule fois, `OnboardingCompleted` passe à `true`, l'objectif retombe à `""`.
- Le SKU économie reste `Speed` (allowlist `AnalyticsConfig.BuildEconomySkuSet` inchangée).

### 5.11 Risques de régression

| Risque | Mitigation |
|---|---|
| Un chemin de prix contourne `UpgradeCost` | Recherche exhaustive de `BaseCost` dans `src/` avant de coder ; tout accès direct doit passer par `UpgradeCost` |
| Buff rétroactif dépasse le plafond | Test `46 <= 80` automatisé + test manuel 4 |
| `Power` élargi devient un exploit de portée | Tests manuels 5 et 6 ; validation serveur explicitement conservée |
| Le pad Transit reste bloqué après la vente | Test manuel 8 |
| `Refresh` depuis `notifyCoinsChanged` crée une boucle | `Refresh` n'écrit que l'attribut, jamais le profil : pas de réentrance |
| Badge casse la mise en page mobile | Tests manuels 10 et 11 |

### 5.12 Rollback

`git revert` du commit de phase. Les joueurs ayant acheté `Speed` à 250 conservent leur niveau ; le prix redevient 750 pour les suivants. Aucune donnée corrompue. `Power` retrouve son comportement (buggé) d'origine.

### 5.13 Résultat attendu avant la phase suivante

Boucle complète en moins de 3 minutes, achat perceptible, Transit non intrusif, Power réparé.

**Commit** : `feat(shop): make the first upgrade reachable and noticeable`

**🛑 POINT D'ARRÊT — validation Studio avant la Phase 6.**

---

## Phase 6 — Teaser de la Summer Zone

### 6.1 Objectif

Donner un objectif à moyen terme visible depuis le plateau, sans détourner le joueur de sa première boucle et sans toucher au verrou de niveau 5.

### 6.2 Fichiers à créer

Aucun.

### 6.3 Fichiers à modifier

- `src/Server/ZoneBuilder.lua`
- `src/Shared/LocalizationStrings.lua`
- `src/Shared/ZoneDefs.lua` (**lecture seule** : source des positions)

### 6.4 Ordre exact des modifications

#### Étape A — `src/Shared/LocalizationStrings.lua`

```
SummerZoneTeaserTitle = "SUMMER ZONE"
SummerZoneTeaserRequirement = "LEVEL 5"
```

Ne pas modifier `SummerZoneUnlocksAt` (utilisé par le panneau du gate et par `ZoneAccess.NotifyBlocked`).

#### Étape B — `src/Server/ZoneBuilder.lua`

Ajouter une bannière verticale haute au-dessus du gate est :

- Position calculée **exclusivement** depuis `ZoneDefs` (origine et taille de la `ClassicZone`, position du gate). Aucune coordonnée en dur.
- Hauteur suffisante pour être lue depuis le centre du plateau ; texte sur `SurfaceGui` double face.
- Icône cadenas + `SummerZoneTeaserTitle` + `SummerZoneTeaserRequirement`.
- `Anchored = true`, `CanCollide = false`, `CanQuery = false`, `CanTouch = false`.
- **Aucun** `ProximityPrompt`, aucune interaction.
- Marquée `GeneratedByCode` et créée via le helper `ensurePart` / `makePart` du fichier, pour rester idempotente au rebuild.
- Ne pas dupliquer ni supprimer le panneau existant du gate.

### 6.5 Dépendances

Phase 1 (le nouveau spawn détermine l'angle de vue à valider).

### 6.6 Tests à écrire

Dans `src/Shared/ZoneGameplayTests.lua` :

- L'emprise de la bannière ne recouvre **aucune** cellule de la grille classique (réutiliser le patron `assertOutsideGrid`).
- La bannière ne recouvre pas le passage du gate (largeur de passage préservée).
- Sa position dérive de `ZoneDefs.Get("ClassicZone")` et de la définition du gate, pas d'une constante.

Dans `src/Shared/ZoneAccessTests.lua` : non-régression, `SummerZone.RequiredLevel` toujours `5`.

### 6.7 Tests existants à exécuter

```powershell
python tools\run_progression_tests.py
python tools\run_summer_lights_tests.py
python tools\run_travel_tests.py
.\tools\luau\luau-compile.exe --binary src\Server\ZoneBuilder.lua
.\tools\luau\luau-compile.exe --binary src\Shared\LocalizationStrings.lua
.\tools\luau\luau-compile.exe --binary src\Shared\ZoneGameplayTests.lua
rojo build --output build.rbxlx
```

Studio : `ZoneGameplayTests`, `ZoneAccessTests`, `SummerZoneStringLightsTests`, `SummerDecorConfigTests` sans `FAIL`.

### 6.8 Tests manuels Roblox Studio

⚠️ `RebuildGeneratedLayout = true` temporairement pour générer la bannière.

1. Lisible depuis le centre du plateau.
2. Lisible depuis le `SpawnPad`.
3. Ne bloque pas le passage du gate ; ne recouvre aucune bulle.
4. Compte niveau < 5 : le blocage et le message existants fonctionnent toujours.
5. Compte niveau ≥ 5 : passage libre, aucune régression.
6. Second Play avec `RebuildGeneratedLayout = true` : **aucun doublon** de bannière.
7. Impact FPS négligeable depuis le plateau.

### 6.9 Critères de réussite

- Bannière visible en première session sans quitter le trajet de la boucle.
- Verrou niveau 5 strictement inchangé.
- `SawSummerZoneRequirement` toujours logué une seule fois, par les triggers existants uniquement.
- Aucun doublon après rebuild.

### 6.10 Risques de régression

| Risque | Mitigation |
|---|---|
| Obstruction du passage | Test automatisé + test manuel 3 |
| Doublon au rebuild | `ensurePart` + `GeneratedByCode`, test manuel 6 |
| Chevauchement de cellules | Assertion `assertOutsideGrid` |
| Nouvel event analytics non demandé | Interdit : aucun nouveau trigger `SawSummerZoneRequirement` |

### 6.11 Rollback

`git revert`. La bannière disparaît au rebuild suivant. Aucun impact données.

### 6.12 Résultat attendu avant la phase suivante

Un nouveau joueur voit la Summer Zone et son niveau requis pendant ses 3 premières minutes, sans être détourné.

**Commit** : `feat(summer): add a readable level 5 teaser banner`

**🛑 POINT D'ARRÊT — validation Studio avant la Phase 7.**

---

## Phase 7 — Analytics et validation multiplateforme

### 7.1 Objectif

Instrumenter les trois nouvelles mesures approuvées, garantir l'unicité d'émission, valider les trois plateformes, et remettre les drapeaux de développement à `false`.

### 7.2 Fichiers à créer

Aucun.

### 7.3 Fichiers à modifier

- `src/Shared/AnalyticsConfig.lua`
- `src/Shared/AnalyticsConfigTests.lua`
- `src/Server/GameAnalyticsService.lua`
- `src/Server/GameAnalyticsServiceTests.lua`
- `src/Server/DataService.lua`
- `src/Server/OnboardingService.lua`
- `src/Shared/BubbleValue.lua`
- `src/Shared/GameConfig.lua`

### 7.4 Ordre exact des modifications

#### Étape A — `src/Shared/AnalyticsConfig.lua`

1. Ajouter le mapping de timing (aucune logique nouvelle, `tryFirstTiming` s'en charge déjà) :

```lua
AnalyticsConfig.FirstTimingByStep = {
	ReachedMainBubbleRoom = "SecondsToBubbleRoom",
	PoppedFirstBubble = "SecondsToFirstBubble",
	BackpackFullFirstTime = "SecondsToBackpackFull",
	SoldFirstBackpack = "SecondsToFirstSale",
	PurchasedFirstUpgrade = "SecondsToFirstUpgrade",
}
```

2. Ajouter trois entrées à `CustomEvents` : `"SecondsToBubbleRoom"`, `"OnboardingGuideSellShown"`, `"OnboardingGuideShopShown"`. Total : **25 / 100**.

3. **Ne pas toucher** : `OnboardingAnalyticsVersion` (reste `1`), `SummerZoneAnalyticsVersion`, `OnboardingSteps`, `SummerSteps`, `EconomySkus`, `FunnelOnboarding`, `ProgressionPath`.

#### Étape B — `src/Server/DataService.lua` et `src/Server/GameAnalyticsService.lua`

Étendre les **deux** templates `Analytics.Lifetime`, à l'identique :

```lua
Lifetime = {
	FirstSpecialBubble = false,
	OnboardingGuideSellShown = false,
	OnboardingGuideShopShown = false,
},
```

`ensureAnalytics` fusionne déjà les clés manquantes des sous-tables autres que `Onboarding` / `SummerZone` (`GameAnalyticsService` L110-122) : **aucune migration n'est nécessaire**, les profils existants sont complétés au chargement.

#### Étape C — `src/Server/GameAnalyticsService.lua`

Ajouter une API publique unique, calquée **exactement** sur `FirstSpecialBubble` (L797-808) :

```lua
local GUIDE_LIFETIME_KEY = {
	Sell = "OnboardingGuideSellShown",
	Shop = "OnboardingGuideShopShown",
}
local GUIDE_EVENT_NAME = {
	Sell = "OnboardingGuideSellShown",
	Shop = "OnboardingGuideShopShown",
}

function GameAnalyticsService.OnOnboardingGuideShown(player: Player, objective: string)
	local session = sessions[player]
	if not session then return end
	local key = GUIDE_LIFETIME_KEY[objective]
	if not key then return end
	local profile = session.profile
	if type(profile) ~= "table" or type(profile.Analytics) ~= "table" then return end
	local lifetime = profile.Analytics.Lifetime
	if type(lifetime) ~= "table" or lifetime[key] == true then return end
	if _logCustom(player, GUIDE_EVENT_NAME[objective], 1, nil) then
		lifetime[key] = true
		profile.__dirty = true
	end
end
```

Propriétés garanties par ce patron, déjà éprouvé :
- **Émission unique** : le drapeau `Lifetime` est persisté et vérifié avant émission.
- **Aucun doublon à la reconnexion** : le drapeau vient du profil DataStore, pas de la session.
- **Aucun contournement** : `_logCustom` est le seul chemin, il valide l'allowlist et le sink.
- **Séquence du funnel intacte** : ce sont des custom events, ils ne touchent pas `drainOnboarding`.
- **Aucune réinitialisation** : `OnboardingVersion` inchangé, donc `profile.Analytics.Onboarding` n'est jamais vidé.

Ne modifier ni `drainOnboarding`, ni `tryFirstTiming`, ni `trySessionSeconds`, ni `InitPlayer`.

#### Étape D — `src/Server/OnboardingService.lua`

Dans `Refresh`, **au moment où l'attribut change effectivement** vers `Sell` ou `Shop` :

```lua
if next ~= previous then
	player:SetAttribute(OnboardingConfig.AttributeName, next)
	if next == OnboardingConfig.Objective.Sell or next == OnboardingConfig.Objective.Shop then
		pcall(function()
			require(script.Parent.GameAnalyticsService).OnOnboardingGuideShown(player, next)
		end)
	end
end
```

L'émission est **serveur uniquement** : aucun client ne peut la déclencher.

#### Étape E — Drapeaux de développement

- `src/Shared/GameConfig.lua` : `World.RebuildGeneratedLayout = false`.
- `src/Shared/BubbleValue.lua` : `DEBUG_BUBBLE_VALUE = false`.

À faire **après** le dernier test manuel nécessitant un rebuild.

### 7.5 Dépendances

Toutes les phases précédentes.

### 7.6 Tests à écrire

Dans `src/Shared/AnalyticsConfigTests.lua` :

- `SecondsToBubbleRoom`, `OnboardingGuideSellShown`, `OnboardingGuideShopShown` sont dans l'allowlist (`IsCustomEventAllowed`).
- `#CustomEvents == 25` et `<= Limits.MaxCustomEventNames`.
- `FirstTimingByStep.ReachedMainBubbleRoom == "SecondsToBubbleRoom"`.
- Chaque valeur de `FirstTimingByStep` est dans `CustomEvents`.
- Chaque clé de `FirstTimingByStep` est un nom d'étape valide (`IsOnboardingStepName`).
- `OnboardingAnalyticsVersion == 1` (garde anti-réinitialisation).
- Les 7 noms d'étapes onboarding et leur ordre sont **inchangés**.

Dans `src/Server/GameAnalyticsServiceTests.lua` (avec le sink mock existant) :

- `OnOnboardingGuideShown(player, "Sell")` émet exactement un `OnboardingGuideSellShown`.
- Deuxième appel dans la même session : aucune émission.
- Nouvelle session avec le même profil (drapeau `Lifetime` déjà `true`) : aucune émission.
- Sink en échec : le drapeau **n'est pas** posé, une nouvelle tentative est possible.
- Objectif inconnu (`"Pop"`, `""`, `nil`) : aucune émission, aucune erreur.
- Profil sans `Lifetime` : aucune erreur (réconciliation défensive).
- La séquence du funnel onboarding reste strictement ordonnée après ces appels.

Dans `src/Server/DataServiceAnalyticsTests.lua` :

- Un profil legacy sans `Lifetime.OnboardingGuideSellShown` est réconcilié à `false` au chargement.
- Aucun champ existant n'est écrasé par la réconciliation.

### 7.7 Tests existants à exécuter

**La totalité des harnais :**

```powershell
python tools\run_progression_tests.py
python tools\run_onboarding_tests.py
python tools\run_shop_service_tests.py
python tools\run_shop_catalog_tests.py
python tools\run_shop_browse_logic_tests.py
python tools\run_shop_layout_tests.py
python tools\run_shop_viewport_tests.py
python tools\run_shop_avatar_visibility_tests.py
python tools\run_itemshop_builder_tests.py
python tools\run_itemshop_visual_tests.py
python tools\run_travel_tests.py
python tools\run_summer_lights_tests.py
rojo build --output build.rbxlx
```

Studio : **les 23 suites** listées dans la section « Commandes » doivent passer sans `FAIL`.

### 7.8 Tests manuels Roblox Studio

1. **Parcours complet clavier/souris**, profil neuf, chronométré de bout en bout.
2. **Parcours complet en émulation tactile** (portrait puis paysage) : la flèche ne recouvre ni le joystick ni le bouton de saut, le badge boutique reste lisible.
3. **Parcours complet à la manette** : prompts `ButtonX`, navigation `ShopUI`, `ButtonB` ferme la modale Transit, aucun élément de guidage dans l'ordre de sélection.
4. **Journal analytics** : dans l'Output, vérifier que chaque événement apparaît **une seule fois** et dans l'ordre `JoinedGame` → `ReachedMainBubbleRoom` → `PoppedFirstBubble` → `BackpackFullFirstTime` → `ReturnedToLobbyAfterFullBackpack` → `SoldFirstBackpack` → `PurchasedFirstUpgrade`.
5. **Timings** : `SecondsToBubbleRoom`, `SecondsToFirstBubble`, `SecondsToBackpackFull`, `SecondsToFirstSale`, `SecondsToFirstUpgrade` présents une fois chacun.
6. **Guides** : `OnboardingGuideSellShown` et `OnboardingGuideShopShown` une fois chacun.
7. **Reconnexion en cours d'onboarding** (quitter après la vente, revenir) : aucun doublon d'aucun événement.
8. **Vétéran** : aucun événement onboarding, aucun guide, aucun changement de spawn.
9. **Deux joueurs simultanés** : pas de fuite d'événement d'un joueur vers l'autre.
10. **Drapeaux** : confirmer qu'aucun log `[BubbleValue]` n'apparaît au pop et que le layout n'est pas reconstruit à chaque Play.

### 7.9 Critères de réussite

- Les 9 événements demandés apparaissent une seule fois, au bon moment, dans le bon ordre.
- Les 3 nouvelles mesures sont émises une seule fois par profil, y compris après reconnexion.
- `OnboardingAnalyticsVersion == 1`, `StoreVersion == "v2"`, funnels non réinitialisés.
- Parcours complet réalisable sur PC, tactile et manette.
- `RebuildGeneratedLayout == false`, `DEBUG_BUBBLE_VALUE == false`.
- Toutes les suites vertes, `rojo build` réussi.

### 7.10 Risques de régression

| Risque | Mitigation |
|---|---|
| Dépassement du plafond de custom events | Test automatisé `#CustomEvents <= 100` |
| Réinitialisation du funnel | Test automatisé `OnboardingAnalyticsVersion == 1` |
| Doublon à la reconnexion | Drapeau `Lifetime` persisté + test dédié |
| Émission contournant le service | Revue : aucun appel à `AnalyticsService` hors `GameAnalyticsService` |
| Drapeau posé malgré un sink en échec | Test dédié « sink en échec » |
| Oubli des flags dev | Test manuel 10 + checklist finale |

### 7.11 Rollback

`git revert`. Les drapeaux `Lifetime` déjà posés restent en base, inertes et sans effet — aucun nettoyage requis.

### 7.12 Résultat attendu

Onboarding complet, mesurable, validé sur trois plateformes, dépôt propre.

**Commit** : `feat(analytics): measure onboarding guidance and room arrival`

**🛑 POINT D'ARRÊT FINAL — validation Studio et revue globale.**

---

## Checklist de fin de phase (à appliquer aux 7 phases)

Avant de déclarer une phase terminée :

- [ ] Tests ciblés de la phase : verts, sortie collée dans le rapport.
- [ ] Tests de non-régression listés dans la phase : verts.
- [ ] `luau-compile` code retour `0` sur **chaque** fichier modifié.
- [ ] `rojo build --output build.rbxlx` réussi.
- [ ] Play Solo en Studio : aucune ligne `FAIL` dans l'Output.
- [ ] Tests manuels de la phase effectués et consignés.
- [ ] Résumé écrit des fichiers modifiés, avec le rôle de chaque changement.
- [ ] Commit unique, message conforme, **aucune** modification appartenant à une autre phase.
- [ ] **Aucun travail de la phase suivante commencé.**
- [ ] Attendre la validation Studio explicite du propriétaire.

---

## Récapitulatif des commits

| Phase | Message |
|---|---|
| 0 | `docs(onboarding): add first three minutes spec and implementation plan` |
| 1 | `feat(onboarding): spawn new players in the bubble room` |
| 2 | `feat(bubbles): make special rarities readable at a glance` |
| 3 | `feat(onboarding): guide new players to the sell kiosk` |
| 4 | `feat(sell): add readable coin reward feedback on sale` |
| 5 | `feat(shop): make the first upgrade reachable and noticeable` |
| 6 | `feat(summer): add a readable level 5 teaser banner` |
| 7 | `feat(analytics): measure onboarding guidance and room arrival` |

---

## Invariants à vérifier à chaque phase

1. Les pièces ne sont créditées que dans `BackpackService.doSell`.
2. La vente reste automatique à l'entrée de la zone.
3. Aucun Remote client → serveur n'a été ajouté.
4. Aucun client ne peut marquer une étape d'onboarding comme franchie.
5. Aucun `while true` ni `Heartbeat` permanent n'a été introduit.
6. `GameConfig.Data.StoreVersion == "v2"`.
7. `AnalyticsConfig.OnboardingAnalyticsVersion == 1`.
8. Les 7 noms d'étapes du funnel onboarding sont inchangés.
9. `BubbleTypes` `SellValue` / `Weight`, `Backpack.DefaultCapacity`, `GameConfig.Combo`, coûts `Jump` / `Power` / `CoinMult` inchangés.
10. Tout texte affiché passe par `LocalizationStrings` et est en anglais.
