# Mini-Event Banner UX — Design

## Goal

Replace the sparse mini-event title with a compact top/center banner: name, objective, timer, progress, bonus coins, and a 4s end result. Do not change Daily/Weekly Challenges.

## Placement (A)

- Always use the floating top/center banner (`MiniEventController`).
- `ChallengeController.UsesEmbeddedMiniEvent()` returns `false`.
- No mini-event card in the right Challenges panel.

## Mechanics (authoritative)

| Event | Rule | Pass/fail | Progress | Bonus coins |
|-------|------|-----------|----------|-------------|
| GoldenWave | ~18% normals → golden; ×5 bag value on golden pops | None → OVER | Personal golden pops | `sellWithMult − sellWithoutMult` |
| ColorRush | Target color; ×3 on match | None → OVER | Personal matching pops | same |
| GiantBubble | Collective hits (disabled by default) | Complete/Failed | current/required (+ personal) | `PendingSellBonus` / `rewardHint.sellBonus` |

Server owns start/end, progress, rewards, coins. Client renders + local countdown from `endTime`.

## Payload (extends `MiniEventState`)

Keep existing fields. Add / standardize:

- `displayName`, `objectiveText`
- `progressCurrent`, `progressTarget` (optional)
- `bonusCoins`
- `hasPassCondition`, `completed` (on Ended)

Progress/bonus updates: FireClient to that player on change (throttled), not every frame.

## UI

During: title, objective, timer `⏱ m:ss`, progress, `Bonus Coins: +N` (gold).

End (~4s): COMPLETE / FAILED / OVER + summary + bonus; fade/scale out.

## Copy (EN)

- GoldenWave objective: `Pop golden bubbles to earn extra Coins!`
- ColorRush objective: `Pop the target color for bonus Coins!`
- Giant objective: `Hit the giant bubble together!`

## Out of scope

Daily/Weekly panel redesign, HUD buttons, analytics schema overhaul, new event types.
