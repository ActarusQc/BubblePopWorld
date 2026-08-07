# Défis quotidiens & hebdomadaires — Bubble Pop Simulator

## Architecture

| Couche | Module | Rôle |
|--------|--------|------|
| Config | `Shared/ChallengeConfig.lua` | Cibles, récompenses, pools, LB, featured weight |
| Logique pure | `Shared/ChallengeLogic.lua` | Clés UTC, sélection déterministe, progression, claim |
| Serveur | `Server/ChallengeService.lua` | Autorité, DataStore LB, remotes, studio cmds |
| Client | `Client/ChallengeController.lua` | Panneau, carte compacte, CLAIM, track |
| Tests | `Shared/ChallengeLogicTests.lua` | Resets, sélection, progression, rewards, LB rules |
| Intégration | `MiniEventService`, `BubbleService`, `BackpackService`, `DataService` | Events gameplay |

Le serveur est la seule source de vérité. Le client affiche l’état reçu via `ChallengeState`.

## Structure données profil (`profile.Challenges`)

```lua
Challenges = {
  Version = 1,
  DailyKey = "20260803",      -- YYYYMMDD UTC
  WeeklyKey = "2026-W32",     -- ISO week
  DailyBubblePops = 1421,
  Daily = { { Id, Metric, Target, Progress, Completed, Claimed, Slot, TitleKey, DescKey, RewardType, RewardAmount }, ... },
  Weekly = { ... } | nil,
  TrackedId = "PopBubbles_50",
  MilestoneNotified = { ["PopBubbles_50"] = { ["0.25"] = true } },
}
```

Réconciliation au login et toutes les ~15 s pour les joueurs connectés (reset sans reconnexion).

## Défis configurés

### Daily Easy
- Pop 50 bubbles  
- Sell 3 full backpacks  
- Pop 5 special bubbles  
- Earn 500 total sell value  

### Daily Medium
- Pop 200 / Sell 8 full / Pop 20 special / Complete 2 mini-events / Sell value 2000  

### Daily Event / variety
- Featured Golden 15 / Color Rush 25 / Giant 10 hits  
- Participate featured / Pop 30 Summer (si unlocked) / Join 3 mini-events  

### Weekly
- Pop 1500 / Sell 30 full / Join 12 events / Complete 5 giants / Pop 100 special / Sell value 25k  

Sélection déterministe par `DailyKey` / `WeeklyKey` + slot ; métriques uniques si possible ; pas de Summer sans accès.

## Récompenses (v1)

Toutes en **`PendingSellBonus`** (prochaine vente) :

| Slot | Montant |
|------|---------|
| Easy | 250 |
| Medium | 400 |
| Event | 500 |
| Weekly | 2000 |

Pas de monnaie Spin. Claim manuel, idempotent (`Claimed`).

## Mini-événement vedette

- Rotation quotidienne déterministe `FeaturedEventForDay(YYYYMMDD)`  
- `MiniEventConfig.FeaturedEventWeightMultiplier = 2`  
- `MiniEventLogic.PickNextEvent(..., featured, weight)` — poids supérieur, jamais forcé chaque cycle  

## Classement DAILY BUBBLE CHAMPIONS

- OrderedDataStore : `DailyBubblePops_v1_<YYYYMMDD>`  
- +1 par bulle validée serveur (normal/special/summer/golden/color)  
- Exclus : giant hits, giant body (v1), tutoriel, rejects  
- Flush score : ~45 s, leave, BindToClose (pas à chaque pop)  
- Top 10 cache ~60 s  

## Remotes

- `ChallengeState` (S→C)  
- `ChallengeRequestState` / `ChallengeClaim` / `ChallengeTrack` / `ChallengePanelOpened` (C→S)  
- `ChallengeNotify` (S→C toasts)  

## Studio (_G, serveur uniquement)

```lua
_G.ChallengesShowState()
_G.ChallengesForceDailyReset()
_G.ChallengesForceWeeklyReset()
_G.ChallengesSetProgress("PopBubbles_50", 49)
_G.ChallengesComplete("PopBubbles_50")
_G.ChallengesClearCurrentPeriod()
_G.ChallengesRefreshLeaderboard()
_G.ChallengesSetLowTargets(true) -- cibles basses
```

## Analytics

`ChallengeAssigned`, `ChallengeProgressMilestone`, `ChallengeCompleted`, `ChallengeRewardClaimed`,  
`WeeklyChallengeCompleted`, `FeaturedEventParticipated`, `DailyLeaderboardScoreUpdated`,  
`DailyLeaderboardTop10Entered`, `ChallengesPanelOpened`, `ChallengePinned`.

## Ajouter un défi

1. Entrée dans le pool `ChallengeConfig` (Id, Metric, Target, Slot, keys L10n, RewardKey).  
2. Si nouvelle métrique : l’ajouter dans `ChallengeLogic.METRICS` + hook serveur.  
3. Clés dans `LocalizationStrings`.  
4. Test unitaire dans `ChallengeLogicTests`.  

## Ajouter une récompense

1. `ChallengeConfig.Rewards`  
2. Branche grant dans `ChallengeService` claim (aujourd’hui `SellBonus` seulement).  

## Tests

```bash
python tools/run_challenge_tests.py
python tools/run_mini_event_tests.py
rojo build -o BubblePopWorld.rbxlx
```

Suite Studio au boot serveur : `ChallengeLogicTests`.

## Validation Studio (manuel)

1. Profil neuf → Challenges → 3 daily + 1 weekly + Event of the Day + countdown.  
2. Pop bulle → carte + panneau progressent.  
3. Claim une fois → PendingSellBonus ; second claim bloqué.  
4. Quitter / revenir → weekly conserve.  
5. Featured identique sur deux serveurs même jour UTC.  
6. LB top 10 + your pops ; coins LB permanent intact.  
7. Mobile : panneau non bloquant ; carte collapsable.  
