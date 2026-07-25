--!strict
-- Configuration centrale de Bubble Pop World.
-- Tout l'équilibrage se change ici, jamais dans le code des services.

local GameConfig = {}

GameConfig.Grid = {
	SizeX = 40,                              -- nombre de bulles en X
	SizeZ = 40,                              -- nombre de bulles en Z
	Spacing = 6,                             -- distance entre 2 centres de bulle (studs)
	BubbleSize = Vector3.new(5.4, 2.0, 5.4), -- hitbox de la bulle (dôme papier bulle)
	Origin = Vector3.new(0, 6, 0),           -- centre de la grille
}

-- Bounds grille (half-extent approx centres ± Spacing/2)
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

-- Lobby HORS de la grille : RootOffset.Z doit être < MinZ - marge (ex. 40 studs)
-- Valeurs par défaut calculées / documentées pour Size 40, Spacing 6 → halfZ=120
-- RootOffset Z ≈ -(halfZ + 60) = -180 (marge 60 hors bordure)
GameConfig.Lobby = {
	RootOffset = Vector3.new(0, 0, -180), -- validé vs GetGridBounds + marge
	FloorSize = Vector3.new(80, 2, 60),
	FloorColor = Color3.fromRGB(60, 100, 160),
	SpawnOffset = Vector3.new(0, 4, 0),
	SellZoneOffset = Vector3.new(-20, 2, 10),
	SellZoneSize = Vector3.new(12, 4, 12),
	EntranceOffset = Vector3.new(0, 2, 28), -- vers +Z direction grille, toujours hors MinZ
	EntranceSize = Vector3.new(14, 6, 8),
	ClearanceFromGrid = 40,
	SignText = "1. Entre dans la salle\n2. Fais éclater des bulles\n3. Remplis ton sac\n4. Reviens vendre tes bulles",
}

local halfZ = (GameConfig.Grid.SizeZ * GameConfig.Grid.Spacing) / 2
GameConfig.GameRoom = {
	-- Pad au sud de la grille (Z négatif), hors bulles
	SpawnOffset = Vector3.new(0, 8, -(halfZ + 44)),
	ExitOffset = Vector3.new(0, 6, -(halfZ + 56)),
	ExitSize = Vector3.new(14, 6, 8),
	PadSize = Vector3.new(24, 2, 24),
	PadColor = Color3.fromRGB(50, 140, 180),
}

GameConfig.Bubble = {
	RegenTime = 30,          -- secondes avant réapparition
	PressDepth = 0.7,        -- enfoncement visuel quand on marche dessus
	MaxPopRange = 18,        -- portée max sans objet (anti-triche serveur)
	WingPopRange = 48,       -- portée pendant le vol avec Ailes
	PopCooldown = 0.10,      -- délai mini entre 2 requêtes client
	MaxPopsPerSecond = 45,   -- budget anti-exploit par joueur
	EffectFlushRate = 0.1,   -- fréquence d'envoi des effets aux clients (batch)
	WingFlightSeconds = 0.9, -- durée du vol horizontal (ailes)

	-- MeshScale < 1 pour laisser un espace visible entre bulles (Spacing = 6)
	MeshScale = Vector3.new(0.92, 0.98, 0.92),

	-- Apparence bulle de savon (uniquement visuel)
	Appearance = {
		Material = Enum.Material.Glass,
		BaseColor = Color3.fromRGB(145, 225, 255),
		Transparency = 0.35,
		Reflectance = 0.05,
		CastShadow = false,

		TintVariants = {
			Color3.fromRGB(135, 220, 255),
			Color3.fromRGB(160, 235, 255),
			Color3.fromRGB(175, 220, 255),
			Color3.fromRGB(150, 245, 235),
		},

		OutlineColor = Color3.fromRGB(70, 190, 230),
		OutlineTransparency = 0.35,
		-- false : 1600 Highlights = trop coûteux / limite Roblox
		EnableHighlight = false,
		-- false : évite +1600 Parts ; Glass suffit pour le reflet
		EnableReflection = false,
		ReflectionTransparency = 0.85,
		ReflectionSize = Vector3.new(0.7, 0.45, 0.7),
	},

	-- Rebond
	BounceMultiplier = 1.45,        -- hauteur du rebond (x JumpPower du joueur)
	ChargedBounceMultiplier = 1.6,  -- bonus si le joueur maintient Saut à l'impact
	BounceCooldown = 0.15,          -- délai mini entre 2 rebonds
	ContactDistance = 4.2,          -- distance sol-torse considérée comme un contact
	PopDelay = 0.06,                -- délai avant éclatement (on voit la bulle céder)
}

GameConfig.XP = {
	Base = 100,
	Growth = 1.16,
	MaxLevel = 500,
}

function GameConfig.XPForLevel(level: number): number
	return math.floor(GameConfig.XP.Base * (GameConfig.XP.Growth ^ (level - 1)))
end

-- Améliorations achetables. PerLevel = gain par niveau d'amélioration.
GameConfig.Upgrades = {
	Speed     = { Label = "Vitesse",              Max = 20, BaseCost = 150, Growth = 1.35, PerLevel = 1.5 },
	Jump      = { Label = "Saut",                 Max = 20, BaseCost = 200, Growth = 1.40, PerLevel = 2.5 },
	Power     = { Label = "Puissance (rayon)",    Max = 8,  BaseCost = 800, Growth = 1.75, PerLevel = 1 },
	CoinMult  = { Label = "Multiplicateur pièces",Max = 30, BaseCost = 300, Growth = 1.45, PerLevel = 0.10 },
	XPMult    = { Label = "Multiplicateur XP",    Max = 30, BaseCost = 300, Growth = 1.45, PerLevel = 0.10 },
}

GameConfig.UpgradeOrder = { "Speed", "Jump", "Power", "CoinMult", "XPMult" }

function GameConfig.UpgradeCost(id: string, currentLevel: number): number
	local def = GameConfig.Upgrades[id]
	if not def then return math.huge end
	return math.floor(def.BaseCost * (def.Growth ^ currentLevel))
end

GameConfig.Character = {
	BaseWalkSpeed = 20,
	BaseJumpPower = 55,
}

GameConfig.Combo = {
	Window = 2.5,   -- secondes pour enchaîner sans perdre le combo
	Step = 4,       -- nb de rebonds par palier
	Bonus = 0.5,    -- multiplicateur gagné par palier
	Max = 6,        -- multiplicateur maximum
}

GameConfig.Drops = {
	MinInterval = 25,
	MaxInterval = 55,
	Lifetime = 45,
	PickupRadius = 8,   -- ramassage automatique : distance joueur-objet (studs)
	PickupRate = 0.08,  -- fréquence de vérification côté serveur
}

GameConfig.Chest = {
	MinInterval = 100,
	MaxInterval = 210,
	Lifetime = 50,
	Tiers = {
		{ Id = "Common",    Label = "Commun",     Weight = 60, Coins = {150, 400},     XP = 60,  Color = Color3.fromRGB(190,190,190) },
		{ Id = "Rare",      Label = "Rare",       Weight = 25, Coins = {600, 1500},    XP = 250, Color = Color3.fromRGB(70,150,255) },
		{ Id = "Epic",      Label = "Épique",     Weight = 12, Coins = {2500, 6000},   XP = 900, Color = Color3.fromRGB(180,80,255) },
		{ Id = "Legendary", Label = "Légendaire", Weight = 3,  Coins = {12000, 30000}, XP = 4000,Color = Color3.fromRGB(255,180,40), Announce = true },
	},
}

GameConfig.Global = {
	Target = 1_000_000_000,      -- objectif communautaire
	FlushInterval = 30,          -- écriture DataStore groupée
	Topic = "BPW_Global",        -- canal MessagingService
}

-- Mondes (le monde 1 est généré par défaut ; les autres réutilisent le même
-- générateur avec une palette et un multiplicateur différents).
GameConfig.Worlds = {
	{ Id = "Prairie",    Label = "Prairie",        LevelReq = 1,   Mult = 1.0,  Sky = Color3.fromRGB(150, 220, 255), Ground = Color3.fromRGB(120, 200, 120) },
	{ Id = "Desert",     Label = "Désert",         LevelReq = 10,  Mult = 1.6,  Sky = Color3.fromRGB(255, 220, 160), Ground = Color3.fromRGB(230, 200, 130) },
	{ Id = "Forest",     Label = "Forêt",          LevelReq = 20,  Mult = 2.4,  Sky = Color3.fromRGB(120, 190, 150), Ground = Color3.fromRGB(60, 130, 70) },
	{ Id = "Ice",        Label = "Glace",          LevelReq = 35,  Mult = 3.5,  Sky = Color3.fromRGB(200, 240, 255), Ground = Color3.fromRGB(180, 230, 250) },
	{ Id = "Volcano",    Label = "Volcan",         LevelReq = 55,  Mult = 5.0,  Sky = Color3.fromRGB(255, 120, 80),  Ground = Color3.fromRGB(90, 40, 40) },
	{ Id = "Clouds",     Label = "Nuages",         LevelReq = 80,  Mult = 7.5,  Sky = Color3.fromRGB(240, 240, 255), Ground = Color3.fromRGB(230, 230, 245) },
	{ Id = "Space",      Label = "Espace",         LevelReq = 110, Mult = 11.0, Sky = Color3.fromRGB(20, 15, 45),    Ground = Color3.fromRGB(40, 35, 80) },
	{ Id = "Future",     Label = "Futuriste",      LevelReq = 150, Mult = 16.0, Sky = Color3.fromRGB(40, 200, 220),  Ground = Color3.fromRGB(30, 60, 90) },
	{ Id = "Candy",      Label = "Bonbons",        LevelReq = 200, Mult = 24.0, Sky = Color3.fromRGB(255, 190, 230), Ground = Color3.fromRGB(255, 150, 200) },
	{ Id = "Underwater", Label = "Sous-marin",     LevelReq = 260, Mult = 35.0, Sky = Color3.fromRGB(30, 120, 180),  Ground = Color3.fromRGB(25, 90, 140) },
}

local function assertOutsideGrid(worldPos: Vector3, label: string)
	local b = GameConfig.GetGridBounds()
	local margin = GameConfig.Lobby.ClearanceFromGrid
	if worldPos.X > b.MinX - margin and worldPos.X < b.MaxX + margin
		and worldPos.Z > b.MinZ - margin and worldPos.Z < b.MaxZ + margin then
		warn("[BPW] layout overlap risk:", label, worldPos)
	end
end

assertOutsideGrid(GameConfig.Lobby.RootOffset, "Lobby.RootOffset")
local gridOrigin = GameConfig.Grid.Origin
assertOutsideGrid(gridOrigin + GameConfig.GameRoom.SpawnOffset, "GameRoom.SpawnOffset")
assertOutsideGrid(gridOrigin + GameConfig.GameRoom.ExitOffset, "GameRoom.ExitOffset")

return GameConfig
