# Design — Musique d’ambiance par zone

**Date :** 2026-07-28  
**Projet :** Bubble Pop Simulator (`BubblePopWorld`)  
**Approche retenue :** MusicController dédié (client)

## 1. Objectif

Chaque joueur entend une musique d’ambiance différente selon sa zone (`PlayerArea`), avec fondu croisé, sourdine HUD, et préférence persistée. Contrôle 100 % client pour la lecture ; serveur uniquement pour valider/sauver `MusicMuted`.

## 2. Zones détectées (`PlayerArea`)

Valeurs exactes posées par `ZoneService` :

| `PlayerArea` | Piste |
|---|---|
| `"Lobby"` | Lobby |
| `"GameRoom"` | Zone de bulles principale (Classic) |
| `"SummerZone"` | Summer Zone |
| inconnu / nil / autre | Fallback Lobby |

Le client n’estime **pas** la zone par boucle frame : il écoute `GetAttributeChangedSignal("PlayerArea")`.

Tant que le joueur n’a pas réellement `PlayerArea == "SummerZone"` (ex. bloqué devant la barrière niveau), la musique Summer ne démarre pas.

## 3. Architecture

```
src/Shared/MusicConfig.lua          — IDs, volumes, fade, mapping
src/Client/MusicController.lua      — lecture, crossfade, mute local
src/Client/HUD.lua                  — bouton mute (réutilise BPW_HUD)
src/Server/DataService.lua          — MusicMuted dans le profil
src/Shared/Remotes.lua              — SetMusicMuted (RemoteEvent)
src/Client/ZoneAmbiance.lua         — retirer UNIQUEMENT le son
src/Client/init.client.lua          — Start() MusicController
```

Pas de système parallèle de zones, DataStore, ou audio SFX. Les effets bulles / boutique / outils restent inchangés (`PopEffects`, `ToolClient`, etc.).

## 4. MusicConfig

Fichier unique pour remplacer les assets plus tard :

```lua
LOBBY_MUSIC_ID = "rbxassetid://0"              -- placeholder
MAIN_BUBBLE_ZONE_MUSIC_ID = "rbxassetid://0"   -- placeholder
SUMMER_ZONE_MUSIC_ID = "rbxassetid://0"        -- placeholder
MusicVolume = 0.25
CrossfadeSeconds = 1.5
AreaDebounceSeconds = 0.4
```

Mapping `AreaToTrackId` : Lobby / GameRoom / SummerZone → IDs ci-dessus ; défaut Lobby.

## 5. MusicController (client)

### Sons
- Instances `Sound` sous `SoundService`, non spatiales (`RollOffMode` / pas de Parent 3D).
- `Looped = true`, volume cible = `MusicVolume` (ou 0 si muted).
- Une instance par piste active ; jamais de copies permanentes multiples.
- Charge / démarre uniquement la piste nécessaire au changement de zone.

### Transition
1. Identifier la piste de la nouvelle zone.
2. Si déjà active → no-op.
3. Debounce zone (`AreaDebounceSeconds`) pour les frontières.
4. Fade-out ancienne (TweenService) + fade-in nouvelle depuis volume 0 (~1,5 s).
5. Après transition : Stop + Destroy (ou recycle) l’ancienne.
6. Au plus **deux** pistes simultanées, uniquement pendant le fondu.

### Mute
- Coupe **uniquement** la musique d’ambiance.
- Mute ON : fondu volume → 0 ; continue de suivre la zone silencieusement (change de piste sans audible).
- Mute OFF : joue uniquement la piste de la zone courante (pas les trois à la fois).
- Préférence locale immédiate + envoi serveur.

### Robustesse
- Placeholder / permissions / load fail → `warn` unique par ID, pas de spam, pas de blocage du jeu.
- Zone inconnue → Lobby.
- Respawn personnage : pas d’impact (`ResetOnSpawn = false` sur HUD ; musique hors Character).
- Reconnexion : `MusicMuted` rechargé via profil / `StatsUpdate`.

## 6. ZoneAmbiance

**Retirer :** `ensureSound`, lecture `SoundIds`, tweens volume / Stop liés à l’ambiance sonore Summer.

**Conserver :** ColorCorrection locale, bannière de zone, cadenas Summer / gate visuals, listeners `PlayerArea` / `CanEnter_SummerZone` / `PlayerLevel`.

## 7. Bouton HUD

- Intégré dans `HUD.lua` / `BPW_HUD` (pas de ScreenGui parallèle).
- Position : haut droite, sous ou à gauche du bouton Inventaire (`1, -126, 0, 16`), sans chevaucher le panneau pièces (haut gauche) ni le compteur mondial.
- Style : mêmes couleurs (`BG` ~18,20,28, coins/accent), coins arrondis, taille tactile (~40×40).
- États : icône musique / musique barrée ; feedback immédiat.
- Compatible souris, tactile, Selectable manette (`Selectable = true`).
- Appelle `MusicController.SetMuted` ; n’altère aucun autre son.

## 8. Persistance

- `DataService.TEMPLATE.MusicMuted = false`.
- Reconcile existant pour les anciens profils.
- RemoteEvent `SetMusicMuted` : serveur accepte uniquement `typeof(muted) == "boolean"`, écrit `profile.MusicMuted`, renvoie via `StatsUpdate` (champ `MusicMuted`).
- Le client ne peut pas modifier d’autres champs via ce remote.
- Pas de nouveau DataStore.

## 9. Performance

- Pas de Heartbeat / RenderStepped / while true pour la zone côté client musique.
- Pas de préchargement systématique des trois pistes au démarrage.
- Déconnexion propre des connexions si le module expose un cleanup (sinon connexions session-longues OK comme le reste du client).

## 10. Tests

Studio (manuel) : lobby → GameRoom → Lobby → Summer ; lock Summer ; mute PC/mobile/manette ; mute + change zone + unmute ; respawn ; reconnect préférences ; SFX bulles OK ; ID invalide non bloquant ; pas de copies permanentes.

Automatisés / CI locaux : vérifs Luau si présentes, `ZoneAccessTests`, `rojo build`.

## 11. Hors scope

- Remplacer les placeholders par de vrais assets audio.
- Musique 3D spatiale.
- Couper les SFX globaux.
- Renommer `PlayerArea` / `GameRoom` / zones existantes.
