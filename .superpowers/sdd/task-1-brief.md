### Task 1: Config & BubbleTypes

**Files:**
- Modify: `src/Shared/GameConfig.lua`
- Modify: `src/Shared/BubbleTypes.lua`

**Interfaces:**
- Produces: `GameConfig.Backpack`, `GameConfig.Lobby`, `GameConfig.GameRoom`, `GameConfig.World`, `GameConfig.GetGridBounds()` (ou Ã©quivalent) ; `BubbleTypes.*.StorageValue/SellValue`

- [ ] **Step 1: Ajouter blocs config + bounds**

```lua
GameConfig.Backpack = {
	DefaultCapacity = 25,
	MaxCapacity = 1000,
	NearlyFullRatio = 0.75,
	FullNotifyCooldown = 3,
}

GameConfig.World = {
	FallResetY = -25,
	FallResetDestination = "GameRoom",
	RebuildGeneratedLayout = false,
	TeleportCooldown = 1.5,
	SellMaxDistance = 16,
	BorderHeight = 28,
	BorderThickness = 3,
	BorderTransparency = 0.45,
	BorderColor = Color3.fromRGB(80, 200, 255),
	MutationLockTimeout = 5,
}

-- Bounds grille (half-extent approx centres Â± Spacing/2)
function GameConfig.GetGridBounds()
	local G = GameConfig.Grid
	local halfX = (G.SizeX * G.Spacing) / 2
	local halfZ = (G.SizeZ * G.Spacing) / 2
	return {
		MinX = G.Origin.X - halfX,
		MaxX = G.Origin.X + halfX,
		MinZ = G.Origin.Z - halfZ,
		MaxZ = G.Origin.Z + halfZ,
		MinY = G.Origin.Y - 2,
		Origin = G.Origin,
	}
end

-- Lobby HORS de la grille : RootOffset.Z doit Ãªtre < MinZ - marge (ex. 40 studs)
-- Valeurs par dÃ©faut calculÃ©es / documentÃ©es pour Size 40, Spacing 6 â†’ halfZ=120
-- RootOffset Z â‰ˆ -(halfZ + 60) = -180 (marge 60 hors bordure)
GameConfig.Lobby = {
	RootOffset = Vector3.new(0, 0, -180), -- validÃ© vs GetGridBounds + marge
	FloorSize = Vector3.new(80, 2, 60),
	FloorColor = Color3.fromRGB(60, 100, 160),
	SpawnOffset = Vector3.new(0, 4, 0),
	SellZoneOffset = Vector3.new(-20, 2, 10),
	SellZoneSize = Vector3.new(12, 4, 12),
	EntranceOffset = Vector3.new(0, 2, 28), -- vers +Z direction grille, toujours hors MinZ
	EntranceSize = Vector3.new(14, 6, 8),
	ClearanceFromGrid = 40,
	SignText = "1. Entre dans la salle\n2. Fais Ã©clater des bulles\n3. Remplis ton sac\n4. Reviens vendre tes bulles",
}

local halfZ = (GameConfig.Grid.SizeZ * GameConfig.Grid.Spacing) / 2
GameConfig.GameRoom = {
	-- Pad au sud de la grille (Z nÃ©gatif), hors bulles
	SpawnOffset = Vector3.new(0, 8, -(halfZ + 24)),
	ExitOffset = Vector3.new(0, 6, -(halfZ + 36)),
	ExitSize = Vector3.new(14, 6, 8),
	PadSize = Vector3.new(24, 2, 24),
	PadColor = Color3.fromRGB(50, 140, 180),
}
```

Ajouter un assert / warn au chargement config (ou dans ZoneService Task 4) :

```lua
local function assertOutsideGrid(worldPos: Vector3, label: string)
	local b = GameConfig.GetGridBounds()
	local margin = GameConfig.Lobby.ClearanceFromGrid
	if worldPos.X > b.MinX - margin and worldPos.X < b.MaxX + margin
		and worldPos.Z > b.MinZ - margin and worldPos.Z < b.MaxZ + margin then
		warn("[BPW] layout overlap risk:", label, worldPos)
	end
end
```

Les pads/lobby ne doivent pas chevaucher les bulles, ni les SafetyBorders, ni passer sous la grille, ni bloquer la chute entre bulles.

- [ ] **Step 2: Ã‰tendre BubbleTypes**

Chaque entrÃ©e : `StorageValue = 1`, `SellValue = <ancien Coins>`, garder `Coins = SellValue` legacy.

- [ ] **Step 3: VÃ©rifier** â€” require Shared OK ; Normal StorageValue/SellValue = 1.

- [ ] **Step 4: Commit**

```bash
git add src/Shared/GameConfig.lua src/Shared/BubbleTypes.lua
git commit -m "feat: add backpack and lobby world config"
```

---
