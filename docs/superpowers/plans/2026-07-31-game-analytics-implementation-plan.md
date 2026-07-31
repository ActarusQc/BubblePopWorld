# Game Analytics Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instrumenter le parcours nouveaux joueurs et Summer Zone via un `GameAnalyticsService` central (`AnalyticsService`), sans modifier gameplay, prix ni décors.

**Architecture:** `AnalyticsConfig` (Shared) + `GameAnalyticsService` (Server, seul appelant Roblox). Hooks post-succès dans les services métier. Profil `Analytics` reconcilié. Funnels drainés dans l’ordre. Flush deltas. Leave/close : analytics → save → release. Un seul `BindToClose` (DataService).

**Tech Stack:** Luau `--!strict`, Rojo, Roblox `AnalyticsService`, DataStore profil existant, tests `Run()` comme les suites Shared/Server actuelles.

**Spec de référence :** `docs/superpowers/specs/2026-07-31-game-analytics-design.md`

## Global Constraints

- Pas de Remote analytics client → serveur
- Pas d’event Analytics par bulle normale (compteurs + deltas)
- Pas de backfill d’étape jamais observée
- Pas de `BindToClose` dans `GameAnalyticsService`
- Pas de `UserId` dans `funnelSessionId`
- `SecondsToFirst*` uniquement si `isInitialProfileSession`
- `ReachedMainBubbleRoom` seulement si `zoneId == "GameRoom"`
- Économie : propriétaire = service métier ; `DataService` ne logue pas
- Studio : simuler + logs ; vrais events seulement en expérience publiée
- Limites : ≤10 currency types, ≤3 custom fields, ≤100 custom event names, ≤10 funnels, rate `120 + 20×CCU`/min
- Devise phase 1 : `"Coins"` uniquement

## File map

| Fichier | Rôle |
|---|---|
| `src/Shared/AnalyticsConfig.lua` | Versions, steps, noms events/SKU, flush, debug, limites |
| `src/Shared/AnalyticsConfigTests.lua` | Validations config |
| `src/Server/GameAnalyticsService.lua` | Session, drains, API publique, wrap AnalyticsService |
| `src/Server/GameAnalyticsServiceTests.lua` | Tests mock couche d’envoi |
| `src/Server/DataService.lua` | TEMPLATE Analytics, `isNewProfile`, InitPlayer, flush avant release, AddCoins→solde, BindToClose |
| `src/Server/init.server.lua` | Ordre Start + Run tests |
| `src/Server/BubbleService.lua` | Hook pops |
| `src/Server/BackpackService.lua` | Full / fill Summer / BagValueByZone / sell économie |
| `src/Server/ShopService.lua` | Upgrade/item sinks + PurchasedFirstUpgrade |
| `src/Server/TravelService.lua` | Transit / Selected / Arrived / Saw |
| `src/Server/ZoneService.lua` | PlayerArea / zoneId GameRoom / lobby après full |
| `src/Server/ZoneAccess.lua` | NotifyBlocked → Saw |
| `src/Server/ToolService.lua` | Compteur outils |
| `src/Server/ChestService.lua` (si AddCoins) | LogCoinSource après crédit |

---

### Task 0: Commit de sauvegarde (avant toute implémentation)

**1. Objectif**  
Figer l’état du dépôt (spec + plan + WIP non lié) avant le code analytics.

**2. Fichiers**  
Aucun code modifié dans cette tâche — git seulement.

**3. Modifications**  
- Commit snapshot demandé par le user avant implémentation analytics.  
- Inclure au minimum la spec et ce plan s’ils ne sont pas déjà commités ; ne pas mélanger avec du code analytics (il n’existe pas encore).

**4. Tests**  
`git status` / `git log -1` pour confirmer le commit.

**5. Résultat attendu**  
HEAD contient un commit de sauvegarde clairement messagé (ex. `chore: snapshot before game analytics phase 1`).

**6. Checkpoint**  
Ne pas écrire de Luau analytics tant que ce commit n’existe pas.

- [ ] **Step 1:** `git status` + `git diff` + `git log -5 --oneline`
- [ ] **Step 2:** Stager spec + plan (+ autres fichiers seulement si le user confirme un snapshot large)
- [ ] **Step 3:** Commit sauvegarde
- [ ] **Step 4:** Vérifier `git status` clean pour les fichiers commités

---

### Task 1: `AnalyticsConfig` + tests config

**1. Objectif**  
Centraliser versions, steps, allowlists et limites avant tout service.

**2. Fichiers**  
- Create: `src/Shared/AnalyticsConfig.lua`  
- Create: `src/Shared/AnalyticsConfigTests.lua`

**3. Modifications précises**

`AnalyticsConfig` doit exposer au minimum :

```lua
--!strict
local RunService = game:GetService("RunService")

local AnalyticsConfig = {
  OnboardingAnalyticsVersion = 1,
  SummerZoneAnalyticsVersion = 1,
  FlushIntervalSeconds = 60,
  CurrencyType = "Coins",
  DebugEnabled = RunService:IsStudio(), -- override possible
  FunnelOnboarding = "NewPlayerOnboarding", -- logique locale ; API = LogOnboardingFunnelStepEvent
  FunnelSummer = "SummerZoneUnlock",
  ProgressionPath = "PlayerLevel",
}

AnalyticsConfig.OnboardingSteps = {
  { step = 1, name = "JoinedGame" },
  { step = 2, name = "ReachedMainBubbleRoom" },
  { step = 3, name = "PoppedFirstBubble" },
  { step = 4, name = "BackpackFullFirstTime" },
  { step = 5, name = "ReturnedToLobbyAfterFullBackpack" },
  { step = 6, name = "SoldFirstBackpack" },
  { step = 7, name = "PurchasedFirstUpgrade" },
}

AnalyticsConfig.SummerSteps = {
  { step = 1, name = "ReachedRequiredLevel" },
  { step = 2, name = "ArrivedAtSummerBridge" },
  { step = 3, name = "PoppedFirstSummerBubble" },
  { step = 4, name = "FilledFirstSummerBackpack" },
  { step = 5, name = "SoldFirstSummerBackpack" },
}

-- Timings First* (session initiale seulement) liés aux step names
AnalyticsConfig.FirstTimingByStep = {
  PoppedFirstBubble = "SecondsToFirstBubble",
  BackpackFullFirstTime = "SecondsToBackpackFull",
  SoldFirstBackpack = "SecondsToFirstSale",
  PurchasedFirstUpgrade = "SecondsToFirstUpgrade",
}

AnalyticsConfig.CustomEvents = {
  "SecondsToFirstBubble", "SecondsToBackpackFull", "SecondsToFirstSale",
  "SecondsToFirstUpgrade", "FirstSessionDuration",
  "SessionSecondsToFirstBubble", "SessionSecondsToFirstSale",
  "FirstSpecialBubble", "SawSummerZoneRequirement",
  "OpenedBubbleTransit", "SelectedSummerZone",
  "PlayerLevelReached",
  -- résumés deltas (noms stables, allowlist)
  "SessionNormalPops", "SessionSpecialPops",
  "SessionPopsGameRoom", "SessionPopsSummerZone",
  "SessionToolUses", "SessionSalesCount", "SessionCoinsFromSales",
  "SessionZoneSecondsLobby", "SessionZoneSecondsGameRoom", "SessionZoneSecondsSummerZone",
  "SessionZoneChanges",
}

AnalyticsConfig.EconomySkus = {
  "BubbleSale_GameRoom", "BubbleSale_SummerZone", "BubbleSale_Mixed",
  "Chest", "DailyReward", "Code", "Admin",
  -- upgrade/item ids ajoutés via ShopCatalog / Config.Upgrades allowlist helper
}

AnalyticsConfig.Limits = {
  MaxCurrencyTypes = 10,
  MaxCustomFields = 3,
  MaxCustomEventNames = 100,
  MaxFunnels = 10,
}
```

Helpers utiles : `GetOnboardingStepIndex(name)`, `IsOnboardingStepName`, `IsSummerStepName`, `VersionCustomField(version)` → dictionary avec clé `AnalyticsCustomFieldKeys.CustomField1` = `"v"..version`.

**4. Tests**  
`AnalyticsConfigTests.Run()` :  
- 7 steps onboarding ordonnés 1..7  
- 5 steps Summer 1..5  
- `#CustomEvents <= 100`  
- currency unique `"Coins"`  
- pas de step `ReachedLevel2` dans onboarding  

**5. Résultat attendu**  
Config require-able ; tests OK en Studio / via init plus tard.

**6. Checkpoint**  
Aucun service ne require encore cette config pour le gameplay.

- [ ] **Step 1:** Écrire `AnalyticsConfigTests` (fail si module absent)
- [ ] **Step 2:** Implémenter `AnalyticsConfig`
- [ ] **Step 3:** Faire passer les tests config
- [ ] **Step 4:** Commit `feat(analytics): add AnalyticsConfig`

---

### Task 2: Squelette `GameAnalyticsService` + mock d’envoi + tests socle

**1. Objectif**  
Créer le service avec injection de la couche Roblox, session vide, Init/Flush, warnings Studio.

**2. Fichiers**  
- Create: `src/Server/GameAnalyticsService.lua`  
- Create: `src/Server/GameAnalyticsServiceTests.lua`

**3. Modifications précises**

Structures session (mémoire) :

```lua
type SessionTotals = {
  normalPops: number,
  specialPops: number,
  popsGameRoom: number,
  popsSummerZone: number,
  toolUses: number,
  salesCount: number,
  coinsFromSales: number,
  zoneSeconds: { Lobby: number, GameRoom: number, SummerZone: number },
  zoneChanges: number,
}

type PlayerSession = {
  sessionId: string,
  joinClock: number,
  isInitialProfileSession: boolean,
  onboardingActive: boolean,
  onboardingObserved: { [string]: boolean },
  summerObserved: { [string]: boolean },
  sessionTotals: SessionTotals,
  lastFlushedTotals: SessionTotals,
  currentArea: string?,
  areaEnteredAt: number?,
  sessionFirstBubbleSent: boolean,
  sessionFirstSaleSent: boolean,
  -- ...
}
```

API initiale :

```lua
function GameAnalyticsService.SetSink(sink) -- tests : remplace AnalyticsService wraps
function GameAnalyticsService.Start()
function GameAnalyticsService.InitPlayer(player, profile, isNewProfile: boolean)
function GameAnalyticsService.FlushAndRemovePlayer(player)
function GameAnalyticsService.FlushAllPlayers()
function GameAnalyticsService.DumpPlayerState(player): string
function GameAnalyticsService.WarnNoSession(player, context: string)
```

Wraps internes (tous `pcall` synchrones pour funnels) :

- `_logOnboarding(player, step, stepName, fields?)`
- `_logFunnel(player, funnelName, sessionId, step, stepName, fields?)`
- `_logCustom(player, name, value?, fields?)`
- `_logEconomy(...)`
- `_logProgressionComplete(...)`

En Studio / sink mock : ne pas appeler le vrai service si `not game:GetService("RunService"):IsStudio()` wait — en Studio les vrais events ne partent pas ; toujours passer par sink qui en prod appelle AnalyticsService, en tests enregistre les appels, en Studio debug print + optional no-op réel.

Règle : **aucun** `BindToClose` ici. Heartbeat/task pour flush périodique OK.

**4. Tests**  
- Init crée session  
- FlushAndRemovePlayer purge  
- Event critique sans session → warning (spy `warn` ou flag test) sans error  
- Sink error dans pcall → pas de throw vers caller  

**5. Résultat attendu**  
Service chargeable ; pas encore branché dans init.

**6. Checkpoint**  
Mock sink obligatoire avant d’écrire les drains.

- [ ] **Step 1:** Tests socle (fail)
- [ ] **Step 2:** Squelette + sink injectable
- [ ] **Step 3:** Tests verts
- [ ] **Step 4:** Commit `feat(analytics): scaffold GameAnalyticsService`

---

### Task 3: Migration profil `Analytics` + `isNewProfile` + reconcile Unknown

**1. Objectif**  
Préparer DataService pour le schéma persisté et l’init analytics.

**2. Fichiers**  
- Modify: `src/Server/DataService.lua`  
- Modify: `src/Server/GameAnalyticsServiceTests.lua` (helpers profil fake)  
- Optionally: tests reconcile dans `GameAnalyticsServiceTests` ou petit test DataService

**3. Modifications précises**

Ajouter au `TEMPLATE` :

```lua
Analytics = {
  OnboardingVersion = 1,
  SummerZoneVersion = 1,
  SummerZoneFunnelSessionId = "",
  OnboardingStarted = false,
  OnboardingCompleted = false,
  Onboarding = {},
  SummerZone = {}, -- steps + SawSummerZoneRequirement + pendingSummerFullBackpackSale
  BagValueByZone = { GameRoom = 0, SummerZone = 0, Unknown = 0 },
  Lifetime = { FirstSpecialBubble = false },
},
```

`Load` :

```lua
local isNewProfile = not (ok and type(saved) == "table")
local data = if not isNewProfile then reconcile(saved, TEMPLATE) else deepCopy(TEMPLATE)
-- reconcileOwnedItems / backpack / progression existants
-- NE PAS set OnboardingStarted ici (seulement InitPlayer si isNewProfile)
```

Changer signature publique :

```lua
function DataService.AddCoins(player, amount, source?): (boolean, number?)
-- return true, d.Coins  ou false, nil
```

Mettre à jour tous les call sites internes pour ignorer le 2e retour tant que Task économie n’est pas faite.

Exposer si besoin :

```lua
function DataService.GetIsNewProfileFlag -- NON : passer isNewProfile à InitPlayer depuis Load/bindPlayer
```

Dans `bindPlayer` après `Load` :

```lua
local profile = DataService.Get(player)
-- isNewProfile doit être connu : stocker profile.__isNewProfile pendant Load
GameAnalyticsService.InitPlayer(player, profile, profile.__isNewProfile == true)
profile.__isNewProfile = nil -- optionnel clear
```

**Note ordre Start :** Task 8 réordonnera init.server ; pour l’instant garder DataService fonctionnel même si InitPlayer no-op-safe.

Helper dans GameAnalyticsService (appelé depuis InitPlayer) :

```lua
local function ensureBagValueCoverage(profile)
  local pending = profile.PendingSellValue or 0
  local bag = profile.Analytics.BagValueByZone
  local sum = (bag.GameRoom or 0) + (bag.SummerZone or 0) + (bag.Unknown or 0)
  if pending > sum then
    bag.Unknown = (bag.Unknown or 0) + (pending - sum)
    profile.__dirty = true
  end
end
```

**4. Tests**  
- Reconcile ajoute Analytics sans `OnboardingStarted=true`  
- Sac `PendingSellValue=50`, BagValue tout 0 → après ensure, Unknown=50  
- `AddCoins` retourne endingBalance  

**5. Résultat attendu**  
Anciens profils migrent sans inscription onboarding.

**6. Checkpoint**  
`OnboardingStarted` false pour reconcile-only vérifié avant Task 4.

- [ ] **Step 1:** Tests migration / AddCoins tuple
- [ ] **Step 2:** TEMPLATE + Load `__isNewProfile` + ensure coverage dans InitPlayer
- [ ] **Step 3:** Tests verts
- [ ] **Step 4:** Commit `feat(analytics): profile Analytics schema and isNewProfile`

---

### Task 4: InitPlayer — onboarding multi-session, Summer version/GUID, level gate

**1. Objectif**  
Implémenter les règles §7 / §9 de la spec dans `InitPlayer`.

**2. Fichiers**  
- Modify: `src/Server/GameAnalyticsService.lua`  
- Modify: `src/Server/GameAnalyticsServiceTests.lua`

**3. Modifications précises**

```lua
function GameAnalyticsService.InitPlayer(player, profile, isNewProfile: boolean)
  -- create session
  if isNewProfile then
    profile.Analytics.OnboardingStarted = true
    session.isInitialProfileSession = true
    observeOnboarding(player, "JoinedGame")
  else
    session.isInitialProfileSession = false
  end

  session.onboardingActive =
    profile.Analytics.OnboardingStarted == true
    and profile.Analytics.OnboardingCompleted ~= true

  if session.onboardingActive then
    for stepName, v in pairs(profile.Analytics.Onboarding) do
      if v == true then session.onboardingObserved[stepName] = true end
    end
    drainOnboarding(player) -- JoinedGame s'envoie si observé
  end

  -- Summer version bump
  if profile.Analytics.SummerZoneVersion < AnalyticsConfig.SummerZoneAnalyticsVersion then
    profile.Analytics.SummerZone = {}
    profile.Analytics.SummerZoneFunnelSessionId = HttpService:GenerateGUID(false)
    profile.Analytics.SummerZoneVersion = AnalyticsConfig.SummerZoneAnalyticsVersion
    profile.__dirty = true
  elseif profile.Analytics.SummerZoneFunnelSessionId == "" then
    profile.Analytics.SummerZoneFunnelSessionId = HttpService:GenerateGUID(false)
    profile.__dirty = true
  end

  -- re-seed summerObserved from SummerZone step keys only (not pending*/Saw if not in SummerSteps)
  ensureBagValueCoverage(profile)

  local level = profile.Level or 1
  if level >= ZoneDefs.GetRequiredLevel("SummerZone") then
    GameAnalyticsService.OnSummerRequiredLevelReached(player)
  end
end
```

Aligner `OnboardingVersion` profil sur config **sans** reset flags (§9.1).

**4. Tests**  
1. `isNewProfile=true` → Started + JoinedGame envoyé  
2. reconcile `isNewProfile=false` → pas Started, pas onboarding  
3. Reconnexion Started ∧ ¬Completed → active + re-seed  
4. Après Completed → inactive  
5. Bump Summer → nouveau GUID ; reconnexion sans bump → même GUID  
6. Level déjà ≥ seuil → observe/drain ReachedRequiredLevel  

**5. Résultat attendu**  
Continuité onboarding + Summer init level OK.

**6. Checkpoint**  
Tests 1–6 verts avant drains métier complets.

- [ ] **Step 1:** Écrire tests Init (fail)
- [ ] **Step 2:** Implémenter InitPlayer + version Summer
- [ ] **Step 3:** Tests verts
- [ ] **Step 4:** Commit `feat(analytics): InitPlayer onboarding and summer versioning`

---

### Task 5: Drain ordonné onboarding (+ timings First* / Session*)

**1. Objectif**  
File `onboardingObserved` → envoi strict 1..7 ; timings conditionnels.

**2. Fichiers**  
- Modify: `src/Server/GameAnalyticsService.lua`  
- Modify: `src/Server/GameAnalyticsServiceTests.lua`

**3. Modifications précises**

```lua
function GameAnalyticsService.ObserveOnboarding(player, stepName: string)
  local session = sessions[player]
  if not session or not session.onboardingActive then
    if not session then WarnNoSession(player, "ObserveOnboarding:" .. stepName) end
    return
  end
  session.onboardingObserved[stepName] = true
  drainOnboarding(player)
end

local function drainOnboarding(player)
  -- for each step in order:
  --   if observed and not profile.Onboarding[name]:
  --     if previous not sent: break
  --     pcall log onboarding
  --     on success: profile.Onboarding[name]=true; __dirty
  --     if isInitialProfileSession and FirstTimingByStep[name]: log custom seconds
  --     if name == PurchasedFirstUpgrade: OnboardingCompleted=true; onboardingActive=false
end
```

API wrappers métier (stubs appelés plus tard) :

- `OnReachedMainBubbleRoom(player)` → Observe `ReachedMainBubbleRoom` seulement si appelé avec preuve zoneId (hook ZoneService)
- `OnBubblePopped(player, ctx)`  
- `OnBackpackBecameFull(player, ctx)`  
- `OnReturnedToLobby(player)` — observe step 5 **seulement si** `onboardingObserved.BackpackFullFirstTime`  
- `OnBackpackSold(player, ctx)`  
- `OnUpgradePurchased(player, ctx)`

**4. Tests**  
- Hors ordre : observe 3 avant 2 → aucun envoi 3 ; puis observe 2 → drain 2 puis 3  
- Lobby avant full → step 5 non observé  
- 2e session : step envoyé sans `SecondsToFirst*`  
- Level 2 n’appelle pas Observe onboarding  
- Doublon step : no-op  

**5. Résultat attendu**  
Drain déterministe ; pas de faux positifs Roblox via sauts.

**6. Checkpoint**  
Tous les tests d’ordre onboarding verts.

- [ ] **Step 1:** Tests drain onboarding
- [ ] **Step 2:** Implémenter Observe/drain/timings
- [ ] **Step 3:** Tests verts
- [ ] **Step 4:** Commit `feat(analytics): onboarding ordered drain`

---

### Task 6: Drain ordonné Summer + Saw custom + pending fill sale

**1. Objectif**  
Même modèle pour `SummerZoneUnlock` ; Saw hors funnel versionné.

**2. Fichiers**  
- Modify: `src/Server/GameAnalyticsService.lua`  
- Modify: `src/Server/GameAnalyticsServiceTests.lua`

**3. Modifications précises**

```lua
function GameAnalyticsService.ObserveSummer(player, stepName: string)
  -- mark summerObserved; drainSummer ordered 1..5
  -- funnelSessionId = profile.Analytics.SummerZoneFunnelSessionId
  -- on first successful funnel step this drain wave / ever for version: attach version custom field
end

function GameAnalyticsService.OnSawSummerZoneRequirement(player)
  -- if SummerZone.SawSummerZoneRequirement then return
  -- LogCustomEvent Saw + version field; set flag; __dirty
end

function GameAnalyticsService.OnSummerRequiredLevelReached(player)
  ObserveSummer(player, "ReachedRequiredLevel")
end

function GameAnalyticsService.OnSelectedSummerZone(player) -- session custom, every time OK
function GameAnalyticsService.OnArrivedAtSummerBridge(player) -- ObserveSummer Arrived
function GameAnalyticsService.OnSummerBubblePopped(player)
function GameAnalyticsService.OnSummerBackpackFilled(player)
  -- Observe Filled; profile.Analytics.SummerZone.pendingSummerFullBackpackSale = true
function GameAnalyticsService.OnBackpackSoldAnalytics(player, ctx)
  -- if pending flag: Observe SoldFirstSummerBackpack; clear flag after success path
end
```

Re-seed : copier seulement les noms présents dans `AnalyticsConfig.SummerSteps` (+ éventuellement marquer Saw comme non-step).

**4. Tests**  
- Pop Summer observé avant Arrived → pas de step 3 ; après Arrived → drain 2 puis 3 si 1 déjà OK  
- Saw custom une fois par version ; bump → peut revoir  
- pending flag persisté sur profil ; vente → Sold + clear  
- Selected sans Arrived  

**5. Résultat attendu**  
Funnel Summer sans conversions artificielles.

**6. Checkpoint**  
Test hors-ordre Summer (§21.26 spec) vert.

- [ ] **Step 1:** Tests Summer drain / Saw / pending
- [ ] **Step 2:** Implémenter
- [ ] **Step 3:** Tests verts
- [ ] **Step 4:** Commit `feat(analytics): summer ordered drain and saw`

---

### Task 7: Compteurs session, deltas, flush périodique, FirstSessionDuration

**1. Objectif**  
Résumés sans double comptage.

**2. Fichiers**  
- Modify: `src/Server/GameAnalyticsService.lua`  
- Modify: `src/Server/GameAnalyticsServiceTests.lua`

**3. Modifications précises**

```lua
function GameAnalyticsService.RecordPop(player, info) -- increments totals; session first bubble custom
function GameAnalyticsService.RecordToolUse(player, toolId)
function GameAnalyticsService.RecordZoneTime(player, newArea) -- accumulate previous area seconds; zoneChanges++
function flushDeltas(player) -- emit positive deltas only; copy lastFlushed
```

`Start()` : boucle `task.wait(FlushIntervalSeconds)` ou Heartbeat accumulé → `flushDeltas` pour chaque session (spawn OK pour résumés).

`FlushAndRemovePlayer` :

1. Accumuler zone courante  
2. `flushDeltas`  
3. Si `isInitialProfileSession` : `FirstSessionDuration`  
4. Clear session  

**4. Tests**  
- Deux flush sans activité → pas de 2e envoi cumulatif  
- Activité entre flush → delta correct  
- Leave envoie reste  

**5. Résultat attendu**  
Pas de double comptage bulles/secondes.

**6. Checkpoint**  
Test delta §21.7 vert.

- [ ] **Step 1:** Tests deltas
- [ ] **Step 2:** Implémenter compteurs + flush
- [ ] **Step 3:** Tests verts
- [ ] **Step 4:** Commit `feat(analytics): session counters and delta flush`

---

### Task 8: Économie + progression API publique

**1. Objectif**  
`LogCoinSource` / `LogCoinSink` + `OnLevelReached`.

**2. Fichiers**  
- Modify: `src/Server/GameAnalyticsService.lua`  
- Modify: `src/Server/GameAnalyticsServiceTests.lua`  
- Modify: `src/Server/DataService.lua` (`AddBubblesSold` → hook level)

**3. Modifications précises**

```lua
function GameAnalyticsService.LogCoinSource(player, ctx: {
  amount: number,
  endingBalance: number,
  transactionType: string,
  itemSku: string,
})
function GameAnalyticsService.LogCoinSink(player, ctx) -- same shape, Sink flow

function GameAnalyticsService.OnLevelReached(player, level: number)
  -- LogProgressionCompleteEvent + LogCustomEvent PlayerLevelReached
  -- OnSummerRequiredLevelReached if level >= required
  -- NE PAS toucher onboarding funnel
end

function GameAnalyticsService.LogBackpackSaleEconomy(player, profile)
  -- read BagValueByZone portions; emit 0..3 economy events; reset bag values; clear pending summer flag handling coordinated with Observe
end
```

Valider SKU ∈ allowlist (warn Studio sinon, still send or drop — **retenir : drop + warn** pour éviter explosion SKU).

**4. Tests**  
- Source/Sink une fois  
- Multi portions GameRoom+Summer+Unknown  
- Level n’avance pas onboarding  
- Payload sans player.Name  

**5. Résultat attendu**  
Économie et progression centralisées.

**6. Checkpoint**  
Aucun double log DataService.

- [ ] **Step 1:** Tests économie/progression
- [ ] **Step 2:** Implémenter API
- [ ] **Step 3:** Hook `AddBubblesSold` → `OnLevelReached` quand level up (après mutation)
- [ ] **Step 4:** Commit `feat(analytics): economy and progression APIs`

---

### Task 9: Orchestration Start / leave / BindToClose

**1. Objectif**  
Ordre analytics → save → release ; un seul BindToClose.

**2. Fichiers**  
- Modify: `src/Server/init.server.lua`  
- Modify: `src/Server/DataService.lua`  
- Modify: `src/Server/GameAnalyticsService.lua` (Start sans BindToClose)

**3. Modifications précises**

`init.server.lua` services order :

```lua
local GameAnalyticsService = require(script.GameAnalyticsService)
local DataService = require(script.DataService)
-- Start GameAnalyticsService BEFORE DataService
GameAnalyticsService.Start()
-- then other services; DataService.Start() early after analytics
```

Ordre concret recommandé :

1. Remotes (déjà)  
2. `GameAnalyticsService.Start()`  
3. `DataService.Start()`  
4. Backpack, Zone, Travel, …  

`DataService.PlayerRemoving` :

```lua
Players.PlayerRemoving:Connect(function(player)
  bound[player] = nil
  pcall(function()
    GameAnalyticsService.FlushAndRemovePlayer(player)
  end)
  DataService.Release(player) -- Save inside Release already
end)
```

`BindToClose` **uniquement** dans DataService (remplacer l’existant) :

```lua
game:BindToClose(function()
  pcall(function()
    GameAnalyticsService.FlushAllPlayers()
  end)
  for _, player in ipairs(Players:GetPlayers()) do
    DataService.Save(player)
    -- release locks as today
  end
  task.wait(3)
end)
```

`bindPlayer` : après Load succès → `InitPlayer(player, profile, isNewProfile)`.

Brancher `AnalyticsConfigTests` + `GameAnalyticsServiceTests` dans le bloc tests de `init.server.lua`.

**4. Tests**  
- Contrat testable : spy ordre Flush puis Release (inject ou flag)  
- GameAnalyticsService n’appelle pas `BindToClose` (grep / assert absence)

**5. Résultat attendu**  
Pas de course leave ; flush avant save.

**6. Checkpoint**  
Serveur démarre ; tests Run() OK.

- [ ] **Step 1:** Réordonner init + leave/close
- [ ] **Step 2:** Brancher tests Run
- [ ] **Step 3:** Vérifier démarrage Studio / rojo
- [ ] **Step 4:** Commit `feat(analytics): wire start order and shutdown flush`

---

### Task 10: Hooks `BubbleService` + `ToolService`

**1. Objectif**  
Pops / outils → analytics post-succès.

**2. Fichiers**  
- Modify: `src/Server/BubbleService.lua`  
- Modify: `src/Server/ToolService.lua`

**3. Modifications précises**

Après pop crédité (sac accepté) dans `PopCells` / chemin succès :

```lua
GameAnalyticsService.OnBubblePopped(player, {
  zoneId = zoneId,           -- "GameRoom" | "SummerZone" | ...
  rarityId = rarityId,       -- normal vs special
  isSpecial = rarityId ~= "Normal", -- adapter à BubbleTypes réel
})
```

Implémentation `OnBubblePopped` :

- `RecordPop`  
- Si onboarding : Observe `PoppedFirstBubble`  
- Si special + not Lifetime.FirstSpecialBubble : custom + flag  
- Si zoneId == SummerZone : ObserveSummer `PoppedFirstSummerBubble`  
- SessionSecondsToFirstBubble une fois / session  

`ToolService` après usage validé : `RecordToolUse(player, toolId)`.

**4. Tests**  
Unitaires déjà dans GameAnalytics ; smoke manuel Studio optionnel.  
Vérifier noms rareté réels dans `BubbleTypes` / config avant d’écrire `isSpecial`.

**5. Résultat attendu**  
Pops instrumentés sans spam.

**6. Checkpoint**  
Pop Studio affiche debug onboarding step 3 pour nouveau profil.

- [ ] **Step 1:** Lire BubbleTypes pour rareté normale
- [ ] **Step 2:** Brancher hooks
- [ ] **Step 3:** Commit `feat(analytics): hook BubbleService and ToolService`

---

### Task 11: Hooks `BackpackService` (full, provenance, sell)

**1. Objectif**  
Sac plein, BagValueByZone, économie vente, flags First.

**2. Fichiers**  
- Modify: `src/Server/BackpackService.lua`  
- Modify: `src/Server/GameAnalyticsService.lua` si helpers manquants

**3. Modifications précises**

Étendre `AddBubbles` / `doAddBubbles` pour accepter `zoneId: string?` **ou** wrapper appelé depuis BubbleService :

Préférence minimale gameplay : BubbleService après `AddBubbles` succès appelle :

```lua
GameAnalyticsService.OnBubblesAddedToBag(player, {
  storageAdded = storage,
  sellValueAdded = sellValue,
  zoneId = zoneId,
  becameFull = (current == capacity),
  wasBelowCapacity = true,
})
```

Si `AddBubbles` ne retourne pas `becameFull`, calculer côté BubbleService via Get avant/après.

`OnBubblesAddedToBag` :

- Incrémenter `BagValueByZone[zone]` ou Unknown  
- Si becameFull : Observe onboarding BackpackFull ; si zone Summer : OnSummerBackpackFilled  

`Sell` succès :

```lua
local sold, earned, err = ...
if sold and earned then
  GameAnalyticsService.OnBackpackSold(player, {
    sold = sold,
    earned = earned,
    endingBalance = select(2, DataService.AddCoins(...)) -- ATTENTION: AddCoins déjà appelé dans doSell
  })
end
```

**Important :** `doSell` appelle déjà `AddCoins` — modifier pour récupérer `endingBalance` :

```lua
local credited, endingBalance = DataService.AddCoins(player, earned, "BubbleSale")
```

Puis `OnBackpackSold` :

- LogBackpackSaleEconomy (portions)  
- Observe onboarding SoldFirstBackpack  
- Si pendingSummerFullBackpackSale : ObserveSummer Sold + clear flag  
- Record sale counters  
- SessionSecondsToFirstSale  

`ResetSession` : clear BagValueByZone + pending flag via `GameAnalyticsService.OnBackpackReset(player)`.

**4. Tests**  
Étendre tests GameAnalytics pour Add/Sell scenarios ; ShopServiceTests ne doivent pas casser (AddCoins tuple).

**5. Résultat attendu**  
Ventes ventilées ; Mixed si Unknown.

**6. Checkpoint**  
Test multi-zone + restored Unknown verts ; Sell gameplay inchangé.

- [ ] **Step 1:** Adapter AddCoins call sites Backpack
- [ ] **Step 2:** Hooks add/sell/reset
- [ ] **Step 3:** Relancer tests backpack/shop/analytics
- [ ] **Step 4:** Commit `feat(analytics): hook BackpackService economy and fill`

---

### Task 12: Hooks `ShopService` + sources coins restantes

**1. Objectif**  
Sinks shop ; sources Chest/etc.

**2. Fichiers**  
- Modify: `src/Server/ShopService.lua`  
- Modify: `src/Server/ChestService.lua` (et tout `AddCoins` caller)  
- Grep: `AddCoins(` dans `src/Server`

**3. Modifications précises**

Après `buyUpgrade` succès :

```lua
GameAnalyticsService.ObserveOnboarding / OnUpgradePurchased
GameAnalyticsService.LogCoinSink(player, {
  amount = cost,
  endingBalance = profile.Coins,
  transactionType = Enum.AnalyticsEconomyTransactionType.Shop.Name,
  itemSku = id,
})
```

Idem `buyItem` avec SKU item.

Chaque `AddCoins` réussi hors Backpack.Sell : caller fait `LogCoinSource` avec SKU allowlist (`Chest`, …).

**4. Tests**  
ShopServiceTests existants + analytics upgrade observe.

**5. Résultat attendu**  
PurchasedFirstUpgrade + sinks.

**6. Checkpoint**  
Achat upgrade Studio → step 7 + economy sink log debug.

- [ ] **Step 1:** Grep tous AddCoins
- [ ] **Step 2:** Hooks shop + chests
- [ ] **Step 3:** Tests
- [ ] **Step 4:** Commit `feat(analytics): hook shop and coin sources`

---

### Task 13: Hooks Travel / Zone / ZoneAccess

**1. Objectif**  
Transit, Saw, Selected vs Arrived, MainBubbleRoom, lobby après full.

**2. Fichiers**  
- Modify: `src/Server/TravelService.lua`  
- Modify: `src/Server/ZoneService.lua`  
- Modify: `src/Server/ZoneAccess.lua`

**3. Modifications précises**

`TravelService` liste destinataires :

```lua
GameAnalyticsService.OnOpenedBubbleTransit(player)
-- if any card Summer IsLocked: OnSawSummerZoneRequirement(player)
```

`RequestTravel` :

- Si `DESTINATION_LOCKED` Summer → Saw  
- Quand validations OK et **avant** `PivotTo` : si dest Summer → `OnSelectedSummerZone`  
- Après PivotTo succès + area Summer/bridge confirmé → `OnArrivedAtSummerBridge`  
- Si PivotTo fail → pas Arrived  

`ZoneService` sur set `PlayerArea` / détection board :

```lua
-- Si zoneId board == "GameRoom": OnReachedMainBubbleRoom(player)
-- Si area == "Lobby": OnReturnedToLobby(player) -- gate full inside GAS
GameAnalyticsService.RecordZoneChange(player, area)
```

Appliquer **D2** (section décisions) : ne pas se fier à `PlayerArea=="GameRoom"` si le pont est inclus ; utiliser `zoneId == "GameRoom"` board ou premier pop GameRoom.  
`ArrivedAtSummerBridge` = Travel Summer + PivotTo succès seulement.

**4. Tests**  
Tests unitaires Travel via GAS mocks ; test Selected sans Arrived.

**5. Résultat attendu**  
Hooks Travel/Zone conformes spec §17.

**6. Checkpoint**  
Manuel : locked Summer → Saw ; travel fail → Selected only.

- [ ] **Step 1:** Lire GetPlayerZone / pont vs salle
- [ ] **Step 2:** Brancher Travel + ZoneAccess + ZoneService
- [ ] **Step 3:** Tests + commit `feat(analytics): hook travel and zones`

---

### Task 14: Debug Dump + Admin Studio (optionnel mince)

**1. Objectif**  
`DumpPlayerState` exploitable en Studio.

**2. Fichiers**  
- Modify: `src/Server/GameAnalyticsService.lua`  
- Modify: `src/Server/AdminService.lua` (si commande admin existe — brancher dump)

**3. Modifications**  
String dump : flags, observed, totals, BagValueByZone, pending, level, area.  
Pas de nouveau Remote public.

**4. Tests**  
Dump contient clés attendues (string.find).

**5. Résultat attendu**  
Diag Studio sans PII dans payloads analytics.

**6. Checkpoint**  
Dump manuel OK.

- [ ] **Step 1:** Dump + wire admin si trivial  
- [ ] **Step 2:** Commit `feat(analytics): studio dump helper`

---

### Task 15: Suite de tests complète + `rojo build`

**1. Objectif**  
Couvrir la checklist spec §21 ; build Rojo vert.

**2. Fichiers**  
- Modify: `src/Server/GameAnalyticsServiceTests.lua` (compléter cas manquants)  
- Modify: `src/Shared/AnalyticsConfigTests.lua`  
- Modify: `src/Server/init.server.lua` (Run)

**3. Modifications**  
S’assurer que les 26 points spec ont un test ou un sous-cas nommé.  
Exécuter :

```bash
rojo build -o BubblePopWorld_analytics.rbxlx
```

(adapter nom/sortie au projet existant si script npm/makefile).

**4. Tests**  
Tous `*Analytics*Tests.Run()` + suites impactées (Shop, Travel, Backpack).

**5. Résultat attendu**  
Build OK ; tests OK ; pas de régression.

**6. Checkpoint**  
Avant validation Studio manuelle.

- [ ] **Step 1:** Compléter gaps tests vs §21  
- [ ] **Step 2:** `rojo build`  
- [ ] **Step 3:** Commit `test(analytics): complete suite and verify rojo build`

---

### Task 16: Validation manuelle Studio + publié (checklist)

**1. Objectif**  
Valider hors unitaires selon spec §23.

**2. Fichiers**  
Aucun code sauf bugs trouvés (hotfix + tests).

**3. Modifications**  
Checklist exécution (cocher dans PR / notes) :

**Studio**

1. Nouveau profil : onboarding ordonné + timings First*  
2. Quit mid-funnel → reconnexion : poursuite sans SecondsToFirst*  
3. Ancien profil : pas d’onboarding ; Summer level init si éligible  
4. Lobby avant full : pas step 5  
5. Level 2 avant vente : funnel intact ; `PlayerLevelReached` log  
6. Special bubble custom  
7. Saw (transit locked / gate)  
8. Selected puis fail Pivot : pas Arrived  
9. Fill Summer → vente lobby : SoldFirstSummer + portions économie  
10. Sac restauré Unknown → Mixed  
11. Dump + warning no session  
12. Stop server : FlushAllPlayers puis save (pas d’erreur)

**Publié**

13. Creator Hub → View Events : funnels, customs, economy  
14. Pas 1 event / bulle  

**4. Tests**  
Manuels + View Events.

**5. Résultat attendu**  
Phase 1 analytics fiable en prod.

**6. Checkpoint**  
Sign-off user avant optimisation 3 minutes gameplay.

- [ ] **Step 1:** Parcourir checklist Studio  
- [ ] **Step 2:** Publier place de test / View Events  
- [ ] **Step 3:** Commit docs notes si besoin `docs: analytics validation notes` (seulement si user demande)

---

## Dependency order (résumé)

```
Task 0 snapshot
 → T1 AnalyticsConfig
 → T2 GAS skeleton + sink
 → T3 DataService schema / isNewProfile / AddCoins tuple
 → T4 InitPlayer
 → T5 Onboarding drain
 → T6 Summer drain
 → T7 Deltas flush
 → T8 Economy + progression
 → T9 Wire Start/leave/close
 → T10 Bubble/Tool hooks
 → T11 Backpack hooks
 → T12 Shop/Chest hooks
 → T13 Travel/Zone hooks
 → T14 Dump
 → T15 Full tests + rojo
 → T16 Manual / published validation
```

## Décisions d’implémentation figées (anti-ambiguïté)

### D1 — Dépendances circulaires DataService ↔ GameAnalyticsService

`GameAnalyticsService` **ne** `require` **pas** `DataService` au top-level.  
Il reçoit toujours `profile` en argument, ou fait un `require` **lazy** à l’intérieur d’une fonction si un Get ponctuel est indispensable.  
`DataService` peut `require(GameAnalyticsService)` (après que le ModuleScript existe) pour Init/Flush/OnLevelReached.

### D2 — `ReachedMainBubbleRoom` vs pont Summer

Si `PlayerArea == "GameRoom"` inclut le pont d’arrivée Summer, **ne pas** utiliser seul `PlayerArea` pour le step 2.  
Déclencheurs acceptés (choisir le premier fiable trouvé dans ZoneService/BubbleService) :

1. entrée / présence sur le board dont `zoneId == "GameRoom"` (grille principale), ou  
2. à défaut : premier pop réussi avec `zoneId == "GameRoom"` **et** Observe step 2 juste avant step 3 dans le même handler (ordre drain OK).

Ne jamais observer step 2 sur `zoneId == "SummerZone"` ni sur Arrived Travel Summer.

### D3 — Clés non-step dans `Analytics.SummerZone`

`SummerZone` mélange steps funnel, `SawSummerZoneRequirement`, `pendingSummerFullBackpackSale`.  
Le re-seed de `summerObserved` et le drain n’utilisent **que** les noms de `AnalyticsConfig.SummerSteps`.  
Saw / pending sont gérés par des chemins dédiés.

### D4 — `AddCoins` source vs SKU économie

`DataService.AddCoins(..., "BubbleSale")` reste un tag interne crédit.  
Les SKUs analytics vente sont **uniquement** dérivés de `BagValueByZone` via `LogBackpackSaleEconomy`, pas du string source.

### D5 — Bump Summer et pending fill

Un bump `SummerZoneAnalyticsVersion` reset la table `SummerZone` (donc clear `pendingSummerFullBackpackSale` et Saw). Accepté : nouvelle campagne d’instrumentation.

### D6 — Call sites `AddCoins`

Tout caller doit être mis à jour pour `(ok, balance) = AddCoins(...)`. Grep obligatoire Task 12 ; tests Shop/Chest/Backpack ne doivent pas casser.

---

## Self-review checklist (plan ↔ spec)

| Exigence spec | Task |
|---|---|
| AnalyticsConfig + limites | T1 |
| GAS central + pcall + sink | T2 |
| Profil Analytics / reconcile / Unknown | T3 |
| isNewProfile ≠ reconcile | T3–T4 |
| OnboardingStarted/Completed multi-session | T4–T5 |
| SecondsToFirst* session initiale only | T5, T7 |
| Drain onboarding strict | T5 |
| Saw custom versionné | T6 |
| Drain Summer obligatoire + test hors-ordre | T6 |
| pendingSummerFullBackpackSale persisté | T6, T11 |
| BagValueByZone + Mixed | T3, T8, T11 |
| Deltas flush | T7 |
| FlushAndRemovePlayer / FlushAllPlayers | T2, T7, T9 |
| Pas de BindToClose dans GAS ; ordre close | T9 |
| Economy métier only | T8, T11–T12 |
| Progression + PlayerLevelReached | T8 |
| Hooks Bubble/Tool/Backpack/Shop/Travel/Zone/ZoneAccess | T10–T13 |
| Debug dump | T14 |
| Tests §21 + rojo | T15 |
| Validation Studio + Creator Hub | T16 |
| Snapshot commit avant code | T0 |
| zoneId GameRoom only for main room | D2 + T13 |
| GUID funnel sans UserId | T4 |
| Init Summer level | T4 |
| Selected vs Arrived | T6, T13 |
)
