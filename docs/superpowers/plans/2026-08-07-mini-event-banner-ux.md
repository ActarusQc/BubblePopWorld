# Mini-Event Banner UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compact top/center mini-event banner with objective, timer, progress, bonus coins, and end result — without touching Daily/Weekly Challenges.

**Architecture:** Extend `MiniEventLogic` payload helpers + per-player session stats in `MiniEventService`; always render via `MiniEventController`; disable Challenges embedding.

**Tech Stack:** Luau, Rojo, existing Remotes.MiniEventState, HudChrome.

## Global Constraints

- Server-authoritative coins/progress; client never invents bonus.
- No per-frame remotes; client countdown from `endTime`.
- Do not modify Daily/Weekly challenge list UI.
- Reuse existing mini-event system (no parallel stack).

---

### Task 1: Pure logic — bonus + UI payload fields

**Files:** `src/Shared/MiniEventLogic.lua`, `src/Shared/MiniEventLogicTests.lua`

- [x] RED: tests for `ComputeEventBonusCoins`, `BuildUiState`, pass-condition flags
- [x] GREEN: implement helpers
- [x] Run `MiniEventLogicTests`

### Task 2: Server session tracking + broadcast

**Files:** `src/Server/MiniEventService.lua`, `src/Server/BubbleService.lua`, `src/Shared/MiniEventConfig.lua`, `src/Shared/LocalizationStrings.lua`

- [x] Track per-player `progressCurrent` / `bonusCoins` on event pops
- [x] Pass bonus from BubbleService pop path
- [x] Enrich broadcast payload with UI fields; Ended includes personal summary
- [x] `EndedBannerSeconds = 4`

### Task 3: Floating banner UX

**Files:** `src/Client/MiniEventController.lua`

- [x] Compact layout + animations
- [x] Always use floating banner (ignore embedded)
- [x] DEV logs: Started / Progress / Ended

### Task 4: Detach Challenges embedding

**Files:** `src/Client/ChallengeController.lua`

- [x] `UsesEmbeddedMiniEvent` → false
- [x] Keep Daily/Weekly unchanged; mini-event slot stays empty

### Task 5: Verify

- [x] Run MiniEventLogicTests (Studio auto au boot serveur)
- [x] Document Studio force: `_G.MiniEventForceStart("GoldenWave")`
