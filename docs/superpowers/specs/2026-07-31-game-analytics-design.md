# Design — Phase 1 Game Analytics (parcours nouveaux joueurs)

**Date :** 2026-07-31  
**Projet :** Bubble Pop World (`BubblePopWorld`)  
**Approche retenue :** A — `GameAnalyticsService` central ; funnels First séparés des usages session ; économie journalisée uniquement par les services métier.

## 1. Objectif

Instrumenter le parcours des nouveaux joueurs via `AnalyticsService` pour mesurer :

- combien commencent réellement à jouer ;
- à quelle étape ils abandonnent ;
- délais avant première bulle / sac plein / première vente / première amélioration ;
- atteinte de la première vente et du premier upgrade ;
- progression vers et dans la Summer Zone.

Cette phase **ne modifie pas** l’équilibrage, les prix, la progression, la monétisation, le gameplay visible ni les décors. Elle fournit uniquement des données fiables pour optimiser ensuite les trois premières minutes.

## 2. Hors scope

- Aucun changement de prix, XP, niveaux, drops, outils ou UI joueur (hors logs Studio debug).
- Aucun RemoteEvent client → serveur dédié analytics (pas de falsification possible).
- Pas de rejeu du funnel d’onboarding Roblox pour les joueurs existants via bump de version.
- Pas d’event Analytics par bulle normale (compteurs + deltas uniquement).
- Pas de backfill artificiel d’une étape onboarding qui ne s’est jamais produite.

## 3. Contexte architecture existante

Aucun `AnalyticsService` n’existe aujourd’hui. Hooks naturels :

| Domaine | Module |
|---|---|
| Bulles | `BubbleService` |
| Sac | `BackpackService` |
| Vente auto / kiosque | `ZoneService` → `BackpackService.Sell` |
| Améliorations / items | `ShopService` |
| Niveaux / coins | `DataService` |
| Bubble Transit | `TravelService` + `BubbleTransitBuilder` |
| Zones / `PlayerArea` / boards | `ZoneService`, `ZoneAccess`, `ZoneDefs`, `BubbleService` (`zoneId`) |
| Outils | `ToolService` |

Réutiliser ces services ; ne pas dupliquer leur logique métier.

## 4. Architecture

```
src/Shared/AnalyticsConfig.lua
src/Server/GameAnalyticsService.lua
src/Server/GameAnalyticsServiceTests.lua
src/Shared/AnalyticsConfigTests.lua   -- validations config / limites

Hooks post-succès (appels minces) :
  DataService, BubbleService, BackpackService,
  ShopService, TravelService, ZoneService, ZoneAccess, ToolService
```

```
Gameplay validé (serveur)
        │
        ▼
GameAnalyticsService  (état session + flags profil)
        │  pcall synchrone pour funnels
        ▼
AnalyticsService (Roblox — publié uniquement)
```

**Règle d’or :** seul `GameAnalyticsService` appelle `AnalyticsService`.

### 4.1 Ordre de démarrage

Dans `init.server.lua` / orchestrateur :

1. Charger / configurer `GameAnalyticsService` (require + infrastructure session / Heartbeat flush). **Ne pas** enregistrer de `BindToClose` dans ce service (§18).
2. Démarrer `GameAnalyticsService.Start()`.
3. Démarrer `DataService.Start()` (ou l’orchestrateur qui possède déjà le shutdown).
4. Après chaque profil chargé avec succès, appeler explicitement `GameAnalyticsService.InitPlayer(player, profile, isNewProfile)`.

API exposée pour le shutdown / leave (pas d’enregistrement lifecycle autonome) :

```lua
GameAnalyticsService.FlushAndRemovePlayer(player)
GameAnalyticsService.FlushAllPlayers()
```

Un événement analytics **critique** reçu sans session ne doit **pas** être silencieusement ignoré en Studio : `warn` clair (`[GameAnalytics] no session for …`). Aucune erreur gameplay.

## 5. Responsabilités

| Module | Rôle |
|---|---|
| `AnalyticsConfig` | Versions, noms, numéros d’étapes, `DebugEnabled`, intervalle flush, allowlists SKU / custom event names, constantes de limites |
| `GameAnalyticsService` | Init/cleanup session, gates, files d’observation onboarding **et** Summer, funnels, custom, economy, progression, flush deltas, debug Studio, dump ; expose `FlushAndRemovePlayer` / `FlushAllPlayers` — **sans** `BindToClose` propre |
| Services gameplay | Après succès métier uniquement : un appel analytics ; jamais de double journalisation |
| Orchestrateur / `DataService` | Unique `BindToClose` ; `PlayerRemoving` : `FlushAndRemovePlayer` puis save/release ; `isNewProfile` ; **ne journalise pas** l’économie |

## 6. API Roblox (signatures actuelles)

| Besoin | API |
|---|---|
| Onboarding nouveaux joueurs | `LogOnboardingFunnelStepEvent(player, step, stepName, customFields?)` |
| Summer unlock | `LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields?)` |
| Timings, usage, résumés, Saw Summer | `LogCustomEvent(player, eventName, value?, customFields?)` |
| Économie | `LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSku?, customFields?)` |
| Niveau | `LogProgressionCompleteEvent(player, "PlayerLevel", level, "Level_" .. level, customFields?)` |

Ne pas utiliser `FireEvent` / `FireCustomEvent` (dépréciés).

`LogProgressionCompleteEvent` est conservé (API spécialisée) mais **ne s’affiche actuellement dans aucun graphique Roblox** — compléter systématiquement par le custom Explore `PlayerLevelReached` (§14).  
`ReachedLevel2FirstTime` : retiré (redondant avec `PlayerLevelReached` value=2) sauf besoin explicite ultérieur de conversion niveau 2.

### 6.1 Limites Roblox à respecter

| Limite | Valeur |
|---|---|
| Types de ressources économiques | ≤ 10 |
| Custom fields par événement | ≤ 3 |
| Noms de custom events | ≤ 100 |
| Funnels | ≤ 10 |
| Requêtes / minute | `120 + 20 × CCU` |
| Steps par funnel | 1–100 |
| SKUs économiques uniques | ≤ 100 (budget projet) |

`AnalyticsConfig` doit lister explicitement les noms d’events / SKUs prévus pour rester sous ces plafonds.

### 6.2 Studio vs publié

- Les vrais événements `AnalyticsService` doivent provenir du **serveur**.
- Ils ne sont **transmis que dans une expérience publiée**.
- Ils **ne sont pas envoyés depuis Studio**.
- En Studio, le mode debug **simule** les gates, affiche les payloads, permet les tests unitaires / manuels locaux.
- Validation finale Creator Hub : outil **View Events** sur une version publiée.

## 7. Init joueur et onboarding réservé aux nouveaux profils

```lua
GameAnalyticsService.InitPlayer(player, profile, isNewProfile)
```

`DataService.Load` doit déterminer `isNewProfile` de façon explicite :

- `true` si aucune donnée sauvegardée valide n’existait (création à partir du template) ;
- `false` si un profil existant a été chargé puis reconcilié.

**Important :** l’ajout de la table `Analytics` par `reconcile` ne constitue **pas** un nouveau joueur.

Règles onboarding (continuité multi-session) :

- Si `isNewProfile == true` : `profile.Analytics.OnboardingStarted = true` ; marquer observé `JoinedGame`.
- Profils existants ajoutés par reconcile : `OnboardingStarted` reste `false` (template) — jamais inscrit automatiquement.
- À chaque connexion :

```lua
session.onboardingActive =
  profile.Analytics.OnboardingStarted == true
  and profile.Analytics.OnboardingCompleted ~= true
```

- Si `onboardingActive` : peupler `onboardingObserved` avec les clés déjà présentes dans `profile.Analytics.Onboarding` (continuité), puis drain (§10.1.1).
- Après envoi réussi de `PurchasedFirstUpgrade` : `OnboardingCompleted = true` ; `onboardingActive = false`.
- Un joueur ayant commencé le funnel peut le poursuivre en session ultérieure ; Roblox ignore les étapes onboarding déjà enregistrées — notre gate locale ne doit pas couper cette continuité.
- Timings `SecondsToFirst*` / `FirstSessionDuration` : **uniquement** session initiale de création de profil (§12.3).

Tous les joueurs reçoivent une session analytics (compteurs, Summer, économie, résumés).

Après traitement `SummerZoneAnalyticsVersion` (§9.2), si `currentLevel >= ZoneDefs.GetRequiredLevel("SummerZone")` : appeler `GameAnalyticsService.OnSummerRequiredLevelReached(player)`.

## 8. Schéma profil persisté

Ajout dans `DataService.TEMPLATE` (reconcile sans écraser) :

```lua
Analytics = {
  OnboardingVersion = 1,
  SummerZoneVersion = 1,
  SummerZoneFunnelSessionId = "",
  OnboardingStarted = false,   -- true seulement à la création réelle du profil
  OnboardingCompleted = false, -- true après envoi réussi de PurchasedFirstUpgrade
  Onboarding = {
    -- [stepName] = true → étapes réellement envoyées à Roblox
  },
  SummerZone = {
    -- [stepName] = true pour la version Summer courante
    -- inclut SawSummerZoneRequirement (custom hors funnel, versionné)
  },
  -- Ventilation persistée du contenu sac (voir §11) — Unknown si restauré sans preuve
  BagValueByZone = {
    GameRoom = 0,
    SummerZone = 0,
    Unknown = 0,
  },
  Lifetime = {
    FirstSpecialBubble = false,
  },
}
```

À l’init : profils anciens / versions — règles §9. Aucun PII.

## 9. Versionnement

### 9.1 Onboarding (`OnboardingAnalyticsVersion`)

- Versionne le **schéma et l’instrumentation locale**.
- `LogOnboardingFunnelStepEvent` n’a **pas** de `funnelSessionId` ; Roblox ignore les étapes déjà enregistrées pour le même joueur.
- Un bump **ne doit pas** réinitialiser les flags puis rejouer l’onboarding.
- Nouvelle analyse = nouveaux joueurs + plage de dates post-déploiement.
- Rejeu exceptionnel existants : `LogFunnelStepEvent` distinct versionné (hors scope phase 1).

### 9.2 Summer (`SummerZoneAnalyticsVersion`)

```lua
funnelName = "SummerZoneUnlock"
funnelSessionId = profile.Analytics.SummerZoneFunnelSessionId
-- GUID généré via HttpService:GenerateGUID(false)
```

Règles GUID :

- généré à la création du bloc Analytics Summer ou au **bump** de `SummerZoneAnalyticsVersion` ;
- conservé aux reconnexions ;
- remplacé **uniquement** lors d’un nouveau bump ;
- **aucun** `UserId` ni identifiant direct du joueur dans le `funnelSessionId`.

Sur bump (`SummerZoneVersion < config`) :

1. reset table `SummerZone` ;
2. nouveau GUID → `SummerZoneFunnelSessionId` ;
3. set `SummerZoneVersion = config` ;
4. réévaluer `OnSummerRequiredLevelReached` si niveau ≥ seuil.

Sur la **première étape Roblox** du funnel réellement envoyée pour cette session funnel, custom field stable version (ex. Field1 = `"v1"`). Max 3 custom fields.

`SawSummerZoneRequirement` est versionné dans `Analytics.SummerZone` (pas `Lifetime`) : première observation réelle de l’exigence **pendant cette version** d’instrumentation. Pour les anciens joueurs, ce n’est pas forcément la première observation historique absolue — seulement depuis le déploiement de la version. Inclure le numéro de version dans un custom field stable de l’event custom.

## 10. Funnels et événements lifetime

### 10.1 `NewPlayerOnboarding` (profils avec `OnboardingStarted` et non complétés)

API : `LogOnboardingFunnelStepEvent`.  
Le funnel se termine à `PurchasedFirstUpgrade` (pas de step niveau).  
Actif tant que `OnboardingStarted and not OnboardingCompleted` (§7), y compris après reconnexion.

| Step | Nom | Trigger observé (serveur) |
|---|---|---|
| 1 | `JoinedGame` | Création profil (`isNewProfile`) — déjà dans `Onboarding` aux sessions suivantes |
| 2 | `ReachedMainBubbleRoom` | Board / zone gameplay **`zoneId == "GameRoom"`** uniquement (plateau principal). Le pont Summer et `SummerZone` ne déclenchent **jamais** cette étape |
| 3 | `PoppedFirstBubble` | Premier pop validé crédité |
| 4 | `BackpackFullFirstTime` | Ajout qui fait `current < capacity` → `current == capacity` |
| 5 | `ReturnedToLobbyAfterFullBackpack` | Premier `PlayerArea → "Lobby"` survenant alors que `BackpackFullFirstTime` est déjà dans `onboardingObserved` |
| 6 | `SoldFirstBackpack` | Première `Sell` réussie |
| 7 | `PurchasedFirstUpgrade` | Premier `BuyUpgrade` réussi |

Précision step 5 : un retour lobby **avant** sac plein n’est **pas** marqué observé pour ce step. Le trigger n’est armé qu’après observation de `BackpackFullFirstTime` ; seul le premier retour lobby ultérieur compte. L’envoi Roblox de step 5 attend toujours que steps 1–4 soient dans `profile.Analytics.Onboarding` (§10.1.1).

**Hors funnel Roblox :**

| Event | Stockage | Trigger |
|---|---|---|
| `FirstSpecialBubble` | `Lifetime.FirstSpecialBubble` | Premier pop rareté ≠ normale |
| Progression niveau | n/a | `LogProgressionCompleteEvent` + custom `PlayerLevelReached` (§14) |
| Timings First* | session initiale seulement | §12.3 |

`PoppedFirstSpecialBubble` n’est **pas** une étape numérotée du funnel (évite faux positifs Roblox sur steps sautés).

#### 10.1.1 File d’observation — ordre logique garanti

Deux états :

```lua
session.onboardingObserved = {}           -- observés (re-seed depuis Onboarding à l’init)
profile.Analytics.Onboarding = {}         -- étapes réellement envoyées à Roblox
```

À `InitPlayer` si `onboardingActive` : pour chaque clé de `Onboarding`, marquer `onboardingObserved[step] = true` (continuité sans rejouer les events métier).

Quand un événement onboarding arrive :

1. le marquer dans `onboardingObserved` ;
2. tant que la **prochaine** étape attendue (1…7) est observée **et** non encore dans `Onboarding`, tenter l’envoi ;
3. avancer uniquement dans l’ordre ;
4. **ne jamais** envoyer le step N si N−1 n’est pas dans `profile.Analytics.Onboarding` ;
5. **aucun backfill** d’une étape jamais observée.

Les `pcall` d’envoi funnel restent synchrones et séquentiels lors du drain.  
Échec API → ne pas marquer `Onboarding[N]`.  
Succès de `PurchasedFirstUpgrade` → `OnboardingCompleted = true`.  
Timings `SecondsToFirst*` : seulement si `session.isInitialProfileSession == true` (§12.3) ; sinon envoyer l’étape funnel sans le timing.

### 10.2 `SawSummerZoneRequirement` (custom, versionné Summer)

- Hors funnel Roblox `SummerZoneUnlock`.
- Flag : `Analytics.SummerZone.SawSummerZoneRequirement`.
- Event : `LogCustomEvent(player, "SawSummerZoneRequirement", 1, { … version … })`.
- Triggers (interaction réelle) :
  - liste Transit avec Summer `IsLocked` ;
  - `RequestTravel` → `DESTINATION_LOCKED` Summer ;
  - `ZoneAccess.NotifyBlocked("SummerZone")`.

### 10.3 `SummerZoneUnlock` (funnel Roblox)

API : `LogFunnelStepEvent` + GUID persisté (§9.2).

| Step | Nom | Trigger |
|---|---|---|
| 1 | `ReachedRequiredLevel` | Niveau ≥ requis Summer — y compris à `InitPlayer` (§7) et aux level-ups |
| 2 | `ArrivedAtSummerBridge` | Personnage **réellement** positionné à la destination Summer et arrivée confirmée (§17) |
| 3 | `PoppedFirstSummerBubble` | Pop validé `zoneId == "SummerZone"` |
| 4 | `FilledFirstSummerBackpack` | §11 |
| 5 | `SoldFirstSummerBackpack` | §11 |

**Session (hors funnel) :**

- `OpenedBubbleTransit`
- `SelectedSummerZone` : requête serveur **valide et acceptée** vers Summer, **avant** le déplacement (§17)

Ventes / fills suivants : compteurs + économie, sans réutiliser les steps `First*`.

#### 10.3.1 File d’observation Summer — drain obligatoire

Le funnel Summer utilise **obligatoirement** une file d’observation et un drain ordonné analogue à l’onboarding :

```lua
session.summerObserved = {}
profile.Analytics.SummerZone = {} -- steps / Saw réellement envoyés pour la version
```

À l’init (après bump éventuel) : re-seed `summerObserved` depuis les steps déjà dans `SummerZone` (hors clés non-step comme métadonnées si besoin).

Règles identiques : marquer observé → drain 1…N dans l’ordre → jamais envoyer N sans N−1 envoyé → aucun backfill d’étape jamais observée.

Roblox considère les étapes intermédiaires comme complétées si une étape supérieure est envoyée directement ; le drain strict est donc obligatoire pour éviter des conversions artificielles.

## 11. Attribution sac Summer (funnel First) vs économie

Ne **pas** utiliser `PlayerArea` au moment de la vente pour le funnel First.

### Funnel — `pendingSummerFullBackpackSale`

`FilledFirstSummerBackpack` : ajout réussi de bulles **provenant de Summer** qui fait `current < capacity` → `current == capacity`.

```lua
profile.Analytics.SummerZone.pendingSummerFullBackpackSale = true
-- miroir session ok ; source de vérité = profil (sac persisté entre sessions)
```

`SoldFirstSummerBackpack` : prochaine `Sell` réussie si ce flag profil est actif ; clear après vente réussie ou reset sac confirmé.

Ce flag **ne détermine pas** le SKU économique de la vente.

### Économie — provenance par zone (persistée)

**Constat code :** `CurrentBubbles` et `PendingSellValue` sont dans le profil DataStore et **persistent** entre sessions. Un sac non vide peut donc être restauré à la connexion.

Décision phase 1 : persister la ventilation dans `profile.Analytics.BagValueByZone` (`GameRoom`, `SummerZone`, `Unknown`) — analytics-only, pas d’équilibrage.

Règles :

- Après chaque ajout validé : incrémenter `BagValueByZone[zoneId]` (`GameRoom` ou `SummerZone`) du `sellValue` réel.
- Miroir session optionnel pour le flush ; source de vérité = profil (sauvé avec le reste).
- À `InitPlayer`, si `CurrentBubbles > 0` (ou `PendingSellValue > 0`) et que la somme des provenances connues + Unknown ne couvre pas `PendingSellValue` (profil pré-instrumentation ou incohérence) : placer le **reliquat** (ou le total manquant) dans `Unknown`. **Ne jamais** attribuer un ancien contenu restauré à `GameRoom` ou `SummerZone` sans preuve.
- Lors de la vente réussie :
  - portion `GameRoom` > 0 → `BubbleSale_GameRoom` ;
  - portion `SummerZone` > 0 → `BubbleSale_SummerZone` ;
  - portion `Unknown` > 0 → `BubbleSale_Mixed` ;
  - reset des trois compteurs + clear flag First si applicable, uniquement après succès.
- Si un chemin d’ajout ne peut pas fournir la zone : incrémenter `Unknown` (pas de défaut GameRoom).

## 12. Événements session et résumés (deltas)

### 12.1 Compteurs session (`sessionTotals`)

- `normalPops`, `specialPops`
- `popsGameRoom`, `popsSummerZone`
- `specialByType` (agrégé allowlist)
- `toolUses` (Pin, Hammer, …)
- `salesCount`, `coinsFromSales`
- `zoneSeconds.Lobby`, `zoneSeconds.GameRoom`, `zoneSeconds.SummerZone`
- `zoneChanges`

Pas d’appel Analytics par bulle normale.

### 12.2 Flush — deltas uniquement

```lua
sessionTotals
lastFlushedTotals
```

Intervalle : `AnalyticsConfig.FlushIntervalSeconds` (défaut 60).

```lua
delta = sessionTotals - lastFlushedTotals
-- LogCustomEvent seulement si delta > 0
lastFlushedTotals = copy(sessionTotals)
```

Durées de zone = secondes depuis le dernier flush, pas le cumul absolu rejoué.

### 12.3 Timings — First* vs Session*

**Strictement liés à la session initiale de création du profil** (`session.isInitialProfileSession == true`, posé seulement si `isNewProfile` à l’init) — une seule fois, avec l’envoi de l’étape onboarding correspondante :

| Custom | Lié à |
|---|---|
| `SecondsToFirstBubble` | step `PoppedFirstBubble` |
| `SecondsToBackpackFull` | step `BackpackFullFirstTime` |
| `SecondsToFirstSale` | step `SoldFirstBackpack` |
| `SecondsToFirstUpgrade` | step `PurchasedFirstUpgrade` |
| `FirstSessionDuration` | leave de cette session initiale uniquement |

Si une étape funnel est terminée lors d’une **session suivante** (`OnboardingStarted` mais pas `isInitialProfileSession`) : envoyer l’étape onboarding, **sans** son timing `SecondsToFirst*`.

**Tous joueurs, chaque session** (noms distincts) :

- `SessionSecondsToFirstBubble`
- `SessionSecondsToFirstSale`
- (autres `SessionSecondsTo*` au besoin, allowlist config)

## 13. Économie — un seul propriétaire par événement

1. `DataService` mute et retourne succès + solde.
2. Le service métier appelle une fois `GameAnalyticsService` avec contexte structuré.

```lua
local success, endingBalance = DataService.AddCoins(player, amount)
if success then
  GameAnalyticsService.LogCoinSource(player, {
    amount = amount,
    endingBalance = endingBalance,
    transactionType = "Gameplay",
    itemSku = "BubbleSale_GameRoom",
  })
end
```

Pas de journalisation auto dans `DataService`. Pas de `skipAnalytics`.

| Flux | flow | transactionType | itemSku |
|---|---|---|---|
| Portion vente GameRoom | Source | `Gameplay` | `BubbleSale_GameRoom` |
| Portion vente Summer | Source | `Gameplay` | `BubbleSale_SummerZone` |
| Portion Unknown / non ventilable | Source | `Gameplay` | `BubbleSale_Mixed` |
| Coffres / bonus | Source | `Gameplay` | SKU allowlist |
| Upgrade / item | Sink | `Shop` | id stable |

Devise : `"Coins"`. Après succès uniquement.  
`pendingSummerFullBackpackSale` ≠ attribution SKU (§11).

## 14. Progression

Après chaque level-up réel, **deux** appels (spécialisé + Explore) :

```lua
AnalyticsService:LogProgressionCompleteEvent(
  player,
  "PlayerLevel",
  level,
  "Level_" .. tostring(level),
  customFields
)
AnalyticsService:LogCustomEvent(player, "PlayerLevelReached", level)
```

Règles :

- un seul nom stable `PlayerLevelReached` (pas un event name par niveau) ;
- `value = level` ;
- la doc Roblox indique que `LogProgressionCompleteEvent` **ne s’affiche actuellement dans aucun graphique** fourni — le custom Explore couvre la visibilité ;
- **aucun** effet sur le funnel `NewPlayerOnboarding` si niveau 2 avant vente / upgrade ;
- `ReachedLevel2FirstTime` retiré (redondant) ;
- Summer : `OnSummerRequiredLevelReached` si seuil atteint (level-up ou init).

## 15. Identifiants et durée de vie

| ID | Génération | Durée |
|---|---|---|
| `sessionId` analytics | `GenerateGUID(false)` à `InitPlayer` | Mémoire jusqu’à `FlushAndRemovePlayer` |
| `SummerZoneFunnelSessionId` | GUID profil, régénéré au bump Summer | Persisté ; stable entre reconnexions |
| Onboarding | N/A | Roblox + `Onboarding` / `onboardingObserved` |

## 16. Ordre des envois et `pcall`

- Drain onboarding / steps Summer : `pcall` **directs** séquentiels (pas de `task.spawn` concurrent sur les steps).
- Erreurs avalées ; gameplay non bloqué.
- Échec API → flag « envoyé » non persisté.
- Succès → marquer `Onboarding` / `SummerZone` + `__dirty`.
- Résumés deltas : file séparée OK.
- Pas de retry agressif.

## 17. Hooks précis

| Service | Moment | Analytics |
|---|---|---|
| Orchestrateur / `DataService` | Après Load succès | `InitPlayer` ; éventuel `OnSummerRequiredLevelReached` |
| | Avant save/release leave | `FlushAndRemovePlayer` **puis** save/release |
| | Unique `BindToClose` | `FlushAllPlayers()` puis save/release tous |
| | Level-up | `OnLevelReached` → progression API + `PlayerLevelReached` + Summer level |
| | `AddCoins` / spend | pas d’économie ici ; retour solde |
| `BubbleService` | Pop crédité | compteurs ; observe onboarding / Summer pops |
| `BackpackService` | Ajout | capacité pleine ; Summer fill ; incrément `BagValueByZone` |
| | `Sell` succès | SoldFirst* ; portions économie (dont Unknown→Mixed) ; clear |
| | `ResetSession` | clear flag Summer + `BagValueByZone` |
| `ShopService` | upgrade/item succès | observe `PurchasedFirstUpgrade` ; sinks |
| `TravelService` | Liste | `OpenedBubbleTransit` ; Saw si Summer locked |
| | Travel accepté Summer **avant** PivotTo | `SelectedSummerZone` |
| | PivotTo / arrivée confirmée | `ArrivedAtSummerBridge` seulement si succès position |
| | Échec téléport après acceptation | **uniquement** `SelectedSummerZone` déjà envoyé ; pas d’Arrived |
| `ZoneService` | Changement zone / board | temps zone ; observe `ReachedMainBubbleRoom` seulement si `zoneId == "GameRoom"` ; observe retour lobby pour step 5 si sac plein déjà observé |
| `ZoneAccess` | `NotifyBlocked("SummerZone")` | Saw versionné |
| `ToolService` | Usage validé | compteur outil |

### Travel — définitions exactes

- **`SelectedSummerZone`** : requête serveur valide et **acceptée** vers la Summer Zone, **avant** le déplacement.
- **`ArrivedAtSummerBridge`** : personnage réellement positionné à la destination Summer et arrivée confirmée.
- Accepté puis échec téléport → seulement `SelectedSummerZone`.

## 18. Départ joueur et `BindToClose`

**Un seul propriétaire de `BindToClose`** : l’orchestrateur principal ou le propriétaire actuel du shutdown (`DataService` / `init.server.lua`).  
`GameAnalyticsService` **n’enregistre pas** son propre `BindToClose`.

API :

```lua
GameAnalyticsService.FlushAndRemovePlayer(player)
GameAnalyticsService.FlushAllPlayers()
```

Ne pas dépendre de deux `PlayerRemoving` indépendants (ordre non garanti).  
Chemin leave contrôlé par `DataService` :

1. `FlushAndRemovePlayer(player)` — temps zone → deltas → `FirstSessionDuration` seulement si `isInitialProfileSession` → `pcall` directs → `sessions[player] = nil`.
2. Sauver et libérer le profil.

`BindToClose` unique :

1. `FlushAllPlayers()` (flush analytics de toutes les sessions actives).
2. Sauvegarde et libération des profils.
3. Fermeture.

## 19. Debug Studio

```lua
AnalyticsConfig.DebugEnabled = true
-- défaut recommandé : true si RunService:IsStudio(), false en production
```

```text
[GameAnalytics] PlayerName | Funnel=NewPlayerOnboarding | Step=PoppedFirstBubble
[GameAnalytics] PlayerName | Custom=SecondsToFirstBubble | Value=12
[GameAnalytics] PlayerName | Economy=Source | SKU=BubbleSale_GameRoom | Amount=40
```

- `PlayerName` prints locaux uniquement.
- Pas de log par bulle normale.
- Warning Studio si event critique sans session.
- `DumpPlayerState` : steps envoyés, `onboardingObserved` / `summerObserved`, flags Started/Completed, `isInitialProfileSession`, temps session, zone/`zoneId`, compteurs, `BagValueByZone`, pending Summer sale, niveau.

## 20. Résilience

Ne jamais empêcher pop, vente, téléport, sauvegarde ; pas d’erreur bloquante hors `pcall` ; pas de Remote falsifiable. Events critiques = serveur post-validation.

## 21. Tests

`GameAnalyticsServiceTests` (mock couche d’envoi) :

1. `isNewProfile=true` → `OnboardingStarted` ; reconcile-only → `OnboardingStarted` reste false.
2. Reconnexion avec `OnboardingStarted` et non complété → `onboardingActive` ; poursuite du funnel.
3. Après `PurchasedFirstUpgrade` → `OnboardingCompleted` ; sessions suivantes sans onboarding.
4. Étape unique : 2e envoi no-op.
5. Leave / `FlushAndRemovePlayer` purge session.
6. Compteurs session s’incrémentent.
7. Flush = deltas uniquement.
8. Distinction `zoneId` GameRoom vs SummerZone.
9. Fill Summer → flag ; vente lobby → `SoldFirstSummerBackpack` ; clear.
10. Mock API error → gameplay OK ; flag non persisté.
11. Payloads sans PII / nom joueur.
12. Bump Summer → nouveau GUID ; GUID stable après reconnexion sans bump.
13. Bump onboarding → pas d’inscription des anciens (`OnboardingStarted` false).
14. Drain onboarding : ordre 1…N.
15. Economy métier une seule fois par portion.
16. Retour lobby **avant** sac plein → step 5 non avancé.
17. Events onboarding hors ordre → aucun saut ; pas de backfill.
18. Niveau 2 avant vente → aucun effet funnel ; `PlayerLevelReached` + progression OK.
19. Joueur existant ≥ niveau Summer → `ReachedRequiredLevel` à l’init.
20. Vente multi-zones → portions séparées ; Unknown → `BubbleSale_Mixed`.
21. Sac restauré non vide sans ventilation → `Unknown` ; vente → Mixed ; jamais GameRoom/Summer inventés.
22. `SelectedSummerZone` puis téléport échoué → pas d’`ArrivedAtSummerBridge`.
23. `FlushAndRemovePlayer` avant libération profil ; `FlushAllPlayers` avant saves en close.
24. Event critique sans session → warning Studio, pas d’erreur gameplay.
25. Étape onboarding en 2e session → funnel OK, **pas** de `SecondsToFirst*`.
26. Summer : observer `PoppedFirstSummerBubble` avant `ArrivedAtSummerBridge` → aucun step 3 envoyé ; après observation d’Arrived, drain envoie les étapes admissibles dans l’ordre sans inventer d’étape.

Brancher `Run()` dans `init.server.lua`.

## 22. Fichiers prévus

**Créés :** `AnalyticsConfig.lua`, `AnalyticsConfigTests.lua`, `GameAnalyticsService.lua`, `GameAnalyticsServiceTests.lua`, cette spec.

**Modifiés :** `DataService` (`isNewProfile`, template, `FlushAndRemovePlayer` avant release, retour solde), `BubbleService`, `BackpackService`, `ShopService`, `TravelService`, `ZoneService`, `ZoneAccess`, `ToolService`, `init.server.lua` (ordre Start).

**Non modifiés :** décors, prix, progression numérique, monétisation Robux, comportement visible hors debug.

## 23. Validation manuelle (Studio + publié)

**Studio**

1. Nouveau profil : onboarding ordonné ; reconnexion mid-funnel : poursuite sans `SecondsToFirst*`.
2. Ancien profil : pas d’onboarding ; Summer level à l’init si éligible.
3. Pop → full → lobby → vente → upgrade ; level 2 n’importe quand sans casser le funnel.
4. Retour lobby avant full : step 5 silencieux.
5. Special bubble + Saw versionné.
6. Travel : Selected puis fail → pas Arrived ; Selected puis OK → Arrived.
7. Vente multi-provenance / sac restauré → Mixed si Unknown.
8. Dump + warning sans session.
9. BindToClose unique : `FlushAllPlayers` puis save.

**Publié**

10. Creator Hub View Events.
11. Pas de spam 1 event / bulle.

## 24. Décisions validées

- Approche A ; Saw custom versionné Summer ; funnel Summer depuis `ReachedRequiredLevel`.
- Onboarding : `OnboardingStarted` / `OnboardingCompleted` — continuité multi-session ; anciens exclus.
- Fin onboarding = `PurchasedFirstUpgrade` ; niveau = progression API + custom `PlayerLevelReached`.
- Files d’observation **obligatoires** onboarding **et** Summer — drain strict, pas de backfill.
- `ReachedMainBubbleRoom` = `zoneId == "GameRoom"` uniquement.
- `SecondsToFirst*` / `FirstSessionDuration` = session initiale de création seulement ; `SessionSecondsTo*` sinon.
- Summer init évalue le niveau courant ; GUID funnel persisté sans UserId.
- Sac persisté → `BagValueByZone` profil ; Unknown/Mixed si pas de preuve ; First flag ≠ SKU.
- Travel : Selected avant move ; Arrived après succès.
- Start analytics avant Data ; **un seul** `BindToClose` ; `FlushAllPlayers` / `FlushAndRemovePlayer` avant save/release.
- Flush deltas ; économie propriétaire métier.
