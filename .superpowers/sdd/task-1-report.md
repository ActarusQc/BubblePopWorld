# Task 1 Report — Config & BubbleTypes

**Status:** DONE  
**Commit:** `4211338` — feat: add backpack and lobby world config  
**Baseline:** 8f5ae31 | **Plan:** 1519860  
**Date:** 2026-07-25

---

## Summary

Task 1 adds shared configuration for the progression loop (backpack, lobby, game room, world physics/borders) and extends bubble type definitions with `StorageValue` / `SellValue` while preserving legacy `Coins`.

Only `src/Shared/GameConfig.lua` and `src/Shared/BubbleTypes.lua` were modified. No services, Rojo builds, or publish steps were touched.

---

## Changes

### `src/Shared/GameConfig.lua`

| Addition | Purpose |
|---|---|
| `GameConfig.GetGridBounds()` | Returns MinX/MaxX/MinZ/MaxZ/MinY/Origin from Grid config |
| `GameConfig.Backpack` | DefaultCapacity 25, MaxCapacity 1000, NearlyFullRatio 0.75, FullNotifyCooldown 3 |
| `GameConfig.World` | Fall reset, teleport cooldown, sell distance, border visuals, mutation lock |
| `GameConfig.Lobby` | RootOffset Z=-180 (outside grid with 60-stud margin beyond halfZ=120), floor/spawn/sell/entrance offsets, SignText |
| `GameConfig.GameRoom` | Spawn/exit pads south of grid at Z=-144 / -156 (relative to Origin) |
| `assertOutsideGrid()` | Load-time warn if layout positions overlap grid + ClearanceFromGrid margin |

**Grid bounds (default 40×40, spacing 6, origin Y=6):**

- halfX = halfZ = 120
- MinX/MaxX = ±120, MinZ/MaxZ = ±120, MinY = 4
- Lobby RootOffset Z = -180 < MinZ - 40 = -160 ✓ (no overlap warn expected)

**Load-time asserts called for:**

1. `Lobby.RootOffset`
2. `Grid.Origin + GameRoom.SpawnOffset` → (0, 14, -144)
3. `Grid.Origin + GameRoom.ExitOffset` → (0, 12, -156)

GameRoom spawn/exit sit 24–36 studs south of grid edge; they fall inside the expanded margin box (MinZ−40 = −160) and **may emit overlap warnings at require time** — intentional per brief (overlap risk detection, not hard fail).

### `src/Shared/BubbleTypes.lua`

All 5 entries extended:

| Id | StorageValue | SellValue | Coins (legacy) |
|---|---|---|---|
| Normal | 1 | 1 | 1 |
| Rare | 1 | 8 | 8 |
| Golden | 1 | 45 | 45 |
| Diamond | 1 | 220 | 220 |
| Legendary | 1 | 1800 | 1800 |

`Coins` equals `SellValue` on every row for backward compatibility.

---

## Verification

| Check | Result |
|---|---|
| `--!strict` on both files | ✓ |
| IDE linter (GameConfig, BubbleTypes) | No errors |
| `GetGridBounds()` math | halfZ=120, Lobby Z=-180 outside grid |
| Normal StorageValue/SellValue | Both = 1 |
| Scope | Shared only; no Server/Client changes |
| Git commit message | Matches plan exactly |

No Luau CLI / selene available in repo; static read + linter used for sanity check.

---

## Self-Review

**Strengths**

- Matches task brief interfaces exactly: Backpack, Lobby, GameRoom, World, GetGridBounds, BubbleTypes StorageValue/SellValue.
- Config placed immediately after `Grid` so `GameRoom` can use `halfZ` and `GetGridBounds` reads live Grid values.
- Legacy `Coins` preserved; downstream services can migrate to `SellValue` incrementally.
- Load-time layout guard documents overlap risk without blocking module load.

**Notes / minor concerns**

1. **GameRoom warn at load:** SpawnOffset (−144) and ExitOffset (−156) are inside `[MinZ−margin, MaxZ+margin]` on Z; Studio output may show two `[BPW] layout overlap risk` warnings on first require. Expected until Task 4 adjusts positions or margin logic.
2. **`GameConfig.World` vs `GameConfig.Worlds`:** Two distinct keys (fall/border config vs world list). No runtime conflict; naming could confuse future readers — acceptable per spec.
3. **Lobby sub-offsets not asserted:** SellZoneOffset / EntranceOffset (relative to RootOffset) not checked at load; Task 4 ZoneService may add fuller validation.

**Out of scope (correctly deferred)**

- ZoneService integration (Task 4)
- BackpackService / sell flow (later tasks)
- Runtime require test in Roblox Studio

---

## Files Touched

```
src/Shared/GameConfig.lua   (+75 lines)
src/Shared/BubbleTypes.lua  (+5 StorageValue/SellValue fields per entry, field reorder)
```

---

## Next Steps (for downstream tasks)

- Task 4: consume `GetGridBounds`, `Lobby`, `GameRoom`, `World` border fields in ZoneService
- Economy/backpack tasks: read `StorageValue` / `SellValue` instead of `Coins` where appropriate

---

## Review Fix — GameRoom clearance (2026-07-25)

**Problem:** `GameRoom.SpawnOffset` / `ExitOffset` were inside `ClearanceFromGrid` (40) of the bubble grid, causing `[BPW] layout overlap risk` warn on every require.

**Fix:** Moved pads further south in `src/Shared/GameConfig.lua`:

| Offset | Before (Z) | After (Z) |
|---|---|---|
| `SpawnOffset` | `-(halfZ + 24)` = −144 | `-(halfZ + 44)` = −164 |
| `ExitOffset` | `-(halfZ + 36)` = −156 | `-(halfZ + 56)` = −176 |

X=0 and Y values unchanged (Spawn Y=8, Exit Y=6).

**Verification (math):** With `halfZ=120`, `MinZ=-120`, `ClearanceFromGrid=40` → safe threshold `MinZ - margin = -160`. `assertOutsideGrid` warns only when `Z > -160` and `Z < 160`; spawn Z=−164 and exit Z=−176 fail the lower bound → no warn.

**Commit:** `d535ceb` — fix: move GameRoom pads outside grid clearance
