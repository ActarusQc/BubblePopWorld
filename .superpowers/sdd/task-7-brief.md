### Task 7: HUD attributs + PopEffects

**Files:**
- Modify: `src/Client/HUD.lua`
- Modify: `src/Client/PopEffects.lua`

- [ ] **Step 1: Jauge sac** â€” lire **uniquement** :

```lua
player:GetAttribute("CurrentBubbles")
player:GetAttribute("BackpackCapacity")
player:GetAttribute("PendingSellValue") -- lobby only
player:GetAttribute("PlayerArea")
```

via `GetAttributeChangedSignal` / dÃ©marrage. **Ne pas** mettre Ã  jour la jauge depuis `StatsUpdate`.

- [ ] **Step 2:** `StatsUpdate` reste pour XP/Level/Upgrades/libellÃ© piÃ¨ces si dÃ©jÃ  branchÃ© ; piÃ¨ces HUD peuvent suivre attribut `Coins` aussi pour cohÃ©rence (prÃ©fÃ©rer attribut `Coins` pour le label piÃ¨ces si simple).

- [ ] **Step 3: PopEffects** â€” `+"..storage` ; plus de `+Coins` comme piÃ¨ces

- [ ] **Step 4â€“5:** Test UI + commit `feat: show backpack gauge from player attributes`

---
