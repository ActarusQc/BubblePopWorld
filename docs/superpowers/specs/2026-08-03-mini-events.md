# Mini-événements — Bubble Pop Simulator

## Architecture

| Couche | Module | Rôle |
|--------|--------|------|
| Config | `Shared/MiniEventConfig.lua` | Durées, multi, contributions, zones, Studio |
| Logique pure | `Shared/MiniEventLogic.lua` | État, choix, multiplicateurs, récompenses (testable) |
| Serveur | `Server/MiniEventService.lua` | FSM Idle→Countdown→Active→Cleanup→Cooldown, autorité |
| Client | `Client/MiniEventController.lua` | Bandeau compact haut/centre (objectif, timer, progress, bonus, résultat 4 s) |
| Réseau | `Remotes.MiniEventState` | Payload structuré serveur → client |
| Intégration | `BubbleService`, `ToolService`, `BackpackService`, `DataService` | Multi pop, Giant hits, `PendingSellBonus` |

Un seul événement actif à la fois. Les clients ne décident jamais des multi/récompenses.

## Les trois événements

1. **Golden Wave** (~45 s) — ~18 % des normales vivantes deviennent dorées (×5). Chance sur regen.
2. **Color Rush** (~60 s) — couleur cible choisie parmi les normales actives (×3 si match).
3. **Giant Bubble** (~75 s) — une geante par zone avec joueurs ; hits collectifs ; bonus de vente.

Valeurs de sac : toujours `BubbleValue` (zone) × multi d’événement. Jamais de duplication des tables de zone.

## Ajouter une zone

1. Enregistrer la zone dans `ZoneDefs` + planche `BubbleService`.
2. Ajouter l’id dans `MiniEventConfig.ParticipatingZones`.
3. Rien d’autre dans le service (pas de positions hardcodées).

## Ajouter un événement

1. Entrée dans `MiniEventConfig.Events` + `MiniEventLogic.EVENT_TYPES`.
2. Branche dans `beginActive` / cleanup / multi si besoin.
3. Textes `LocalizationStrings` + client.
4. Tests dans `MiniEventLogicTests`.

## Studio — forcer un événement

Console **serveur** (Command Bar) :

```lua
_G.MiniEventForceStart("GoldenWave")
_G.MiniEventForceStart("ColorRush")
_G.MiniEventForceStart("GiantBubble")
_G.MiniEventForceStop()
```

Ou :

```lua
require(game.ServerScriptService.Server.MiniEventService):ForceStartForTesting("GoldenWave")
```

Uniquement en Studio (aucun RemoteEvent). Accélération via `MiniEventConfig.Studio`.

## Analytics

Événements custom (allowlist `AnalyticsConfig`) :

- `MiniEventCountdownStarted`
- `MiniEventStarted`
- `MiniEventParticipationStarted`
- `MiniEventProgress` (jalons 25/50/75/100 Giant)
- `MiniEventCompleted` / `MiniEventFailed`
- `MiniEventRewardGranted`

## Sécurité

- Multi / hits / bonus uniquement serveur.
- Distance + cooldown Giant.
- Niveau zone via `ZoneDefs.CanLevelEnter`.
- Récompense unique (`rewardedUserIds`).
- Pas de backdoor Remote.

## Tests

Suite auto (Studio au lancement serveur) :

- `MiniEventLogicTests`
- suites existantes (BubbleValue, Backpack, Analytics, …)

```bash
rojo build -o BubblePopWorld.rbxlx
```

## Récompense Giant / économie

`PendingSellBonus` (profil, reconcilé) s’ajoute à la **prochaine vente** au kiosque, sans capacité sac. Remis à 0 après vente réussie. XP gelée dans ce projet → pas d’XP d’événement.
