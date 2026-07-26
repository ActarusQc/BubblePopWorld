# Review package Task 1 (re-review)
BASE: 1519860
HEAD: d535cebe5a2019a95b7089a4b30d9f576f2d7c08

## Commits
d535ceb fix: move GameRoom pads outside grid clearance
4211338 feat: add backpack and lobby world config


## Stat
 src/Shared/BubbleTypes.lua | 10 +++----
 src/Shared/GameConfig.lua  | 75 ++++++++++++++++++++++++++++++++++++++++++++++
 2 files changed, 80 insertions(+), 5 deletions(-)


## Diff
```diff
diff --git a/src/Shared/BubbleTypes.lua b/src/Shared/BubbleTypes.lua
index 782f88d..ca581a6 100644
--- a/src/Shared/BubbleTypes.lua
+++ b/src/Shared/BubbleTypes.lua
@@ -1,22 +1,22 @@
 --!strict
 -- Table de raret├⌐s des bulles + tirage pond├⌐r├⌐.
 
 local BubbleTypes = {}
 
 BubbleTypes.List = {
 	-- Teintes bulle de savon (pas de blanc opaque)
-	{ Id = "Normal",    Label = "Bulle",             Weight = 1000, Coins = 1,    XP = 1,   Color = Color3.fromRGB(145, 225, 255) },
-	{ Id = "Rare",      Label = "Bulle rare",        Weight = 110,  Coins = 8,    XP = 5,   Color = Color3.fromRGB(90, 170, 255) },
-	{ Id = "Golden",    Label = "Bulle dor├⌐e",       Weight = 30,   Coins = 45,   XP = 22,  Color = Color3.fromRGB(255, 200, 70) },
-	{ Id = "Diamond",   Label = "Bulle diamant",     Weight = 7,    Coins = 220,  XP = 95,  Color = Color3.fromRGB(100, 240, 230) },
-	{ Id = "Legendary", Label = "Bulle l├⌐gendaire",  Weight = 1,    Coins = 1800, XP = 700, Color = Color3.fromRGB(255, 110, 210), Announce = true },
+	{ Id = "Normal",    Label = "Bulle",             Weight = 1000, StorageValue = 1, SellValue = 1,    Coins = 1,    XP = 1,   Color = Color3.fromRGB(145, 225, 255) },
+	{ Id = "Rare",      Label = "Bulle rare",        Weight = 110,  StorageValue = 1, SellValue = 8,    Coins = 8,    XP = 5,   Color = Color3.fromRGB(90, 170, 255) },
+	{ Id = "Golden",    Label = "Bulle dor├⌐e",       Weight = 30,   StorageValue = 1, SellValue = 45,   Coins = 45,   XP = 22,  Color = Color3.fromRGB(255, 200, 70) },
+	{ Id = "Diamond",   Label = "Bulle diamant",     Weight = 7,    StorageValue = 1, SellValue = 220,  Coins = 220,  XP = 95,  Color = Color3.fromRGB(100, 240, 230) },
+	{ Id = "Legendary", Label = "Bulle l├⌐gendaire",  Weight = 1,    StorageValue = 1, SellValue = 1800, Coins = 1800, XP = 700, Color = Color3.fromRGB(255, 110, 210), Announce = true },
 }
 
 BubbleTypes.ById = {}
 local total = 0
 for _, def in ipairs(BubbleTypes.List) do
 	BubbleTypes.ById[def.Id] = def
 	total += def.Weight
 end
 
 function BubbleTypes.Roll(rng: Random?)
diff --git a/src/Shared/GameConfig.lua b/src/Shared/GameConfig.lua
index f2380a8..2acd51c 100644
--- a/src/Shared/GameConfig.lua
+++ b/src/Shared/GameConfig.lua
@@ -5,20 +5,81 @@
 local GameConfig = {}
 
 GameConfig.Grid = {
 	SizeX = 40,                              -- nombre de bulles en X
 	SizeZ = 40,                              -- nombre de bulles en Z
 	Spacing = 6,                             -- distance entre 2 centres de bulle (studs)
 	BubbleSize = Vector3.new(5.4, 2.0, 5.4), -- hitbox de la bulle (d├┤me papier bulle)
 	Origin = Vector3.new(0, 6, 0),           -- centre de la grille
 }
 
+-- Bounds grille (half-extent approx centres ┬▒ Spacing/2)
+function GameConfig.GetGridBounds()
+	local G = GameConfig.Grid
+	local halfX = (G.SizeX * G.Spacing) / 2
+	local halfZ = (G.SizeZ * G.Spacing) / 2
+	return {
+		MinX = G.Origin.X - halfX,
+		MaxX = G.Origin.X + halfX,
+		MinZ = G.Origin.Z - halfZ,
+		MaxZ = G.Origin.Z + halfZ,
+		MinY = G.Origin.Y - 2,
+		Origin = G.Origin,
+	}
+end
+
+GameConfig.Backpack = {
+	DefaultCapacity = 25,
+	MaxCapacity = 1000,
+	NearlyFullRatio = 0.75,
+	FullNotifyCooldown = 3,
+}
+
+GameConfig.World = {
+	FallResetY = -25,
+	FallResetDestination = "GameRoom",
+	RebuildGeneratedLayout = false,
+	TeleportCooldown = 1.5,
+	SellMaxDistance = 16,
+	BorderHeight = 28,
+	BorderThickness = 3,
+	BorderTransparency = 0.45,
+	BorderColor = Color3.fromRGB(80, 200, 255),
+	MutationLockTimeout = 5,
+}
+
+-- Lobby HORS de la grille : RootOffset.Z doit ├¬tre < MinZ - marge (ex. 40 studs)
+-- Valeurs par d├⌐faut calcul├⌐es / document├⌐es pour Size 40, Spacing 6 ΓåÆ halfZ=120
+-- RootOffset Z Γëê -(halfZ + 60) = -180 (marge 60 hors bordure)
+GameConfig.Lobby = {
+	RootOffset = Vector3.new(0, 0, -180), -- valid├⌐ vs GetGridBounds + marge
+	FloorSize = Vector3.new(80, 2, 60),
+	FloorColor = Color3.fromRGB(60, 100, 160),
+	SpawnOffset = Vector3.new(0, 4, 0),
+	SellZoneOffset = Vector3.new(-20, 2, 10),
+	SellZoneSize = Vector3.new(12, 4, 12),
+	EntranceOffset = Vector3.new(0, 2, 28), -- vers +Z direction grille, toujours hors MinZ
+	EntranceSize = Vector3.new(14, 6, 8),
+	ClearanceFromGrid = 40,
+	SignText = "1. Entre dans la salle\n2. Fais ├⌐clater des bulles\n3. Remplis ton sac\n4. Reviens vendre tes bulles",
+}
+
+local halfZ = (GameConfig.Grid.SizeZ * GameConfig.Grid.Spacing) / 2
+GameConfig.GameRoom = {
+	-- Pad au sud de la grille (Z n├⌐gatif), hors bulles
+	SpawnOffset = Vector3.new(0, 8, -(halfZ + 44)),
+	ExitOffset = Vector3.new(0, 6, -(halfZ + 56)),
+	ExitSize = Vector3.new(14, 6, 8),
+	PadSize = Vector3.new(24, 2, 24),
+	PadColor = Color3.fromRGB(50, 140, 180),
+}
+
 GameConfig.Bubble = {
 	RegenTime = 30,          -- secondes avant r├⌐apparition
 	PressDepth = 0.7,        -- enfoncement visuel quand on marche dessus
 	MaxPopRange = 18,        -- port├⌐e max sans objet (anti-triche serveur)
 	WingPopRange = 48,       -- port├⌐e pendant le vol avec Ailes
 	PopCooldown = 0.10,      -- d├⌐lai mini entre 2 requ├¬tes client
 	MaxPopsPerSecond = 45,   -- budget anti-exploit par joueur
 	EffectFlushRate = 0.1,   -- fr├⌐quence d'envoi des effets aux clients (batch)
 	WingFlightSeconds = 0.9, -- dur├⌐e du vol horizontal (ailes)
 
@@ -131,11 +192,25 @@ GameConfig.Worlds = {
 	{ Id = "Forest",     Label = "For├¬t",          LevelReq = 20,  Mult = 2.4,  Sky = Color3.fromRGB(120, 190, 150), Ground = Color3.fromRGB(60, 130, 70) },
 	{ Id = "Ice",        Label = "Glace",          LevelReq = 35,  Mult = 3.5,  Sky = Color3.fromRGB(200, 240, 255), Ground = Color3.fromRGB(180, 230, 250) },
 	{ Id = "Volcano",    Label = "Volcan",         LevelReq = 55,  Mult = 5.0,  Sky = Color3.fromRGB(255, 120, 80),  Ground = Color3.fromRGB(90, 40, 40) },
 	{ Id = "Clouds",     Label = "Nuages",         LevelReq = 80,  Mult = 7.5,  Sky = Color3.fromRGB(240, 240, 255), Ground = Color3.fromRGB(230, 230, 245) },
 	{ Id = "Space",      Label = "Espace",         LevelReq = 110, Mult = 11.0, Sky = Color3.fromRGB(20, 15, 45),    Ground = Color3.fromRGB(40, 35, 80) },
 	{ Id = "Future",     Label = "Futuriste",      LevelReq = 150, Mult = 16.0, Sky = Color3.fromRGB(40, 200, 220),  Ground = Color3.fromRGB(30, 60, 90) },
 	{ Id = "Candy",      Label = "Bonbons",        LevelReq = 200, Mult = 24.0, Sky = Color3.fromRGB(255, 190, 230), Ground = Color3.fromRGB(255, 150, 200) },
 	{ Id = "Underwater", Label = "Sous-marin",     LevelReq = 260, Mult = 35.0, Sky = Color3.fromRGB(30, 120, 180),  Ground = Color3.fromRGB(25, 90, 140) },
 }
 
+local function assertOutsideGrid(worldPos: Vector3, label: string)
+	local b = GameConfig.GetGridBounds()
+	local margin = GameConfig.Lobby.ClearanceFromGrid
+	if worldPos.X > b.MinX - margin and worldPos.X < b.MaxX + margin
+		and worldPos.Z > b.MinZ - margin and worldPos.Z < b.MaxZ + margin then
+		warn("[BPW] layout overlap risk:", label, worldPos)
+	end
+end
+
+assertOutsideGrid(GameConfig.Lobby.RootOffset, "Lobby.RootOffset")
+local gridOrigin = GameConfig.Grid.Origin
+assertOutsideGrid(gridOrigin + GameConfig.GameRoom.SpawnOffset, "GameRoom.SpawnOffset")
+assertOutsideGrid(gridOrigin + GameConfig.GameRoom.ExitOffset, "GameRoom.ExitOffset")
+
 return GameConfig

```
