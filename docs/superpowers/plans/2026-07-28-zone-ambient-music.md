# Zone Ambient Music Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Musique d’ambiance client par `PlayerArea` (Lobby / GameRoom / SummerZone), fondu 1,5 s, mute HUD, `MusicMuted` persisté via DataService.

**Architecture:** `MusicConfig` (Shared) + `MusicController` (Client, sons non spatiaux SoundService) écoute `PlayerArea`. Bouton dans `HUD`. Remote `SetMusicMuted`. Retirer uniquement le son de `ZoneAmbiance`.

**Tech Stack:** Luau strict, Rojo, TweenService, DataStore existant, Remotes.

## Global Constraints

- `PlayerArea` : `"Lobby"` | `"GameRoom"` | `"SummerZone"` ; fallback Lobby
- Ne pas toucher SFX bulles / boutique / outils
- Pas de Heartbeat client pour la zone
- Placeholders audio centralisés dans `MusicConfig.lua`
- `MusicVolume = 0.25`, crossfade 1,5 s, debounce ~0,4 s
- `MusicMuted = false` par défaut

---

### Task 1: MusicConfig + MusicController + ZoneAmbiance son retiré

**Files:**
- Create: `src/Shared/MusicConfig.lua`
- Create: `src/Client/MusicController.lua`
- Modify: `src/Client/ZoneAmbiance.lua` (retirer son uniquement)
- Modify: `src/Client/init.client.lua` (require MusicController)

- [ ] **Step 1:** Créer `MusicConfig` avec IDs placeholders, volumes, mapping Area→track
- [ ] **Step 2:** Créer `MusicController` (crossfade, debounce, mute, warn unique)
- [ ] **Step 3:** Retirer ensureSound / SoundIds de ZoneAmbiance ; garder CC/bannière/cadenas
- [ ] **Step 4:** Enregistrer `MusicController.Start` dans init.client.lua

### Task 2: Persistance MusicMuted

**Files:**
- Modify: `src/Shared/Remotes.lua` — event `SetMusicMuted`
- Modify: `src/Server/DataService.lua` — TEMPLATE, Push, handler

- [ ] **Step 1:** Ajouter RemoteEvent `SetMusicMuted`
- [ ] **Step 2:** `TEMPLATE.MusicMuted = false` ; Push inclut `MusicMuted`
- [ ] **Step 3:** Handler serveur : `typeof == boolean` uniquement

### Task 3: Bouton mute HUD

**Files:**
- Modify: `src/Client/HUD.lua`

- [ ] **Step 1:** Bouton haut-droite (sous Inventaire), style HUD, Selectable
- [ ] **Step 2:** Brancher MusicController + StatsUpdate MusicMuted

### Task 4: Vérifications + commit

- [ ] **Step 1:** `rojo build` + tests ZoneAccessTests si possible
- [ ] **Step 2:** Commit feat musique ambiance
