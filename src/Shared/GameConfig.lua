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
	-- Dev : true une fois pour reconstruire le layout GeneratedByCode, puis false.
	RebuildGeneratedLayout = true,
	TeleportCooldown = 1.5,
	SellMaxDistance = 16,
	-- Z < AreaSplitZ → Lobby ; sinon GameRoom (détection sans téléport).
	AreaSplitZ = -198,
	-- Legacy (collision invisible) — préférer InvisibleCollisionHeight.
	BorderHeight = 22,
	BorderThickness = 2,
	BorderTransparency = 0.72,
	BorderColor = Color3.fromRGB(40, 140, 200),
	VisibleBorderHeight = 10,
	InvisibleCollisionHeight = 22,
	MutationLockTimeout = 5,
}

-- Lobby HORS de la grille ET au sud des pads de la salle : le plancher (Z ∈ [-280, -200])
-- ne doit jamais recouvrir SpawnPad / ExitPad (Z ∈ [-192, -152]).
-- Size 40, Spacing 6 → halfZ=120, MinZ=-120.
local lobbyRoot = Vector3.new(0, 0, -240)
local lobbySellOffset = Vector3.new(-34, 2, 6)
local lobbyEntranceOffset = Vector3.new(0, 3, 36)
-- Yaw 90° = façade tournée à droite (vers le spawn / +X local après rotation).
local sellBoothYawDegrees = 90
local sellPadLocalOffset = Vector3.new(0, 0.15, 6.8)
local sellBoothOrigin = lobbyRoot + lobbySellOffset
local sellBoothCF = CFrame.new(sellBoothOrigin) * CFrame.Angles(0, math.rad(sellBoothYawDegrees), 0)
local sellPadWorld = (sellBoothCF * CFrame.new(sellPadLocalOffset)).Position

GameConfig.Lobby = {
	RootOffset = lobbyRoot,
	FloorSize = Vector3.new(110, 2, 80), -- ~110×80 studs
	FloorColor = Color3.fromRGB(28, 38, 68),
	AccentColor = Color3.fromRGB(90, 210, 255),
	VioletAccent = Color3.fromRGB(160, 110, 255),
	SpawnOffset = Vector3.new(0, 4, 0),
	SellZoneOffset = lobbySellOffset,
	SellZoneSize = Vector3.new(12, 7, 10),
	SellPosition = sellPadWorld,
	SellBooth = {
		-- "Code" : kiosque assemblé par ZoneService.buildSellBooth.
		-- "StudioModel" : kiosque = Model manuel Lobby.SellKiosk, branché par SellKioskBuilder.
		Mode = "Code",
		YawDegrees = sellBoothYawDegrees,
		OriginOffset = lobbySellOffset,
		PadLocalOffset = sellPadLocalOffset,
		TankBubbleCount = 10,
		CounterSize = Vector3.new(16.5, 4.2, 6.2),
		CanopySize = Vector3.new(18.5, 1.1, 10.5),
		SignSize = Vector3.new(15.5, 4.0, 1.15),
		PadSize = Vector3.new(11, 0.4, 9),
	},
	-- Utilisé uniquement quand SellBooth.Mode == "StudioModel".
	SellKiosk = {
		MainSignGuiFace = "Back",
		ValueDisplayGuiFace = "Back",
		FrontDisplayGuiFace = "Back", -- alias legacy
		TerminalGuiFace = "Back",
	},
	EntranceOffset = lobbyEntranceOffset,
	EntrancePosition = lobbyRoot + lobbyEntranceOffset,
	EntranceSize = Vector3.new(16, 10, 6),
	ClearanceFromGrid = 40,
	RailingHeight = 4,
	SignText = "1. Entre dans la salle\n2. Fais éclater des bulles\n3. Remplis ton sac\n4. Reviens vendre tes bulles",
}

local halfZ = (GameConfig.Grid.SizeZ * GameConfig.Grid.Spacing) / 2
local gameOrigin = GameConfig.Grid.Origin
-- Bande sud, du nord au sud : passerelle → SpawnPad → ExitPad → (vide) → lobby.
-- SpawnPad Z ∈ [-176, -152], ExitPad Z ∈ [-192, -176] : jointifs, jamais sécants,
-- et tous deux au nord du plancher du lobby (bord nord à Z = -200).
local gameSpawnOffset = Vector3.new(0, 8, -(halfZ + 44))
local gameExitOffset = Vector3.new(0, 6, -(halfZ + 64))

GameConfig.GameRoom = {
	-- Pad au sud de la grille (Z négatif), hors bulles
	SpawnOffset = gameSpawnOffset,
	ExitOffset = gameExitOffset,
	SpawnPadPosition = gameOrigin + gameSpawnOffset,
	ExitPosition = gameOrigin + gameExitOffset,
	ExitSize = Vector3.new(12, 8, 8),
	PadSize = Vector3.new(28, 2, 24),
	ExitPadSize = Vector3.new(22, 2, 16),
	PadColor = Color3.fromRGB(36, 70, 110),
	-- X = largeur de la passerelle, Y = épaisseur. La longueur réelle est calculée
	-- par ZoneService (bord nord du SpawnPad → face sud des bulles) ; Z reste la
	-- valeur nominale pour la géométrie par défaut de la grille.
	PathSize = Vector3.new(16, 2, 28),
	PathColor = Color3.fromRGB(42, 80, 125),
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

-- Persistance. Roblox ne permet pas d'énumérer de façon fiable toutes les clés d'un
-- DataStore : la seule réinitialisation globale sûre est le changement de version.
-- Passer StoreVersion à "v2" crée un namespace vierge (tout le monde repart du TEMPLATE)
-- sans rien détruire ; remettre "v1" restaure intégralement les anciens profils.
GameConfig.Data = {
	PlayerStorePrefix = "BPW_PlayerData_",
	PlayerKeyPrefix = "player_",
	StoreVersion = "v2",
	LeaderboardPrefix = "BPW_LB_",
	LeaderboardVersion = "v2",
}

function GameConfig.PlayerStoreName(): string
	return GameConfig.Data.PlayerStorePrefix .. GameConfig.Data.StoreVersion
end

function GameConfig.PlayerKey(userId: number): string
	return GameConfig.Data.PlayerKeyPrefix .. tostring(userId)
end

function GameConfig.LeaderboardStoreName(boardId: string): string
	return GameConfig.Data.LeaderboardPrefix .. boardId .. "_" .. GameConfig.Data.LeaderboardVersion
end

-- Commandes d'administration (chat serveur uniquement, aucun Remote exposé).
-- Le propriétaire de l'expérience est admin d'office ; UserIds ajoute des comptes.
GameConfig.Admin = {
	UserIds = {},
	AllowPlaceOwner = true,
	CommandPrefix = "/bpwreset",
	ConfirmTimeout = 30,
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
assertOutsideGrid(GameConfig.Lobby.SellPosition, "Lobby.SellPosition")
assertOutsideGrid(GameConfig.Lobby.EntrancePosition, "Lobby.EntrancePosition")
assertOutsideGrid(GameConfig.GameRoom.SpawnPadPosition, "GameRoom.SpawnPadPosition")
assertOutsideGrid(GameConfig.GameRoom.ExitPosition, "GameRoom.ExitPosition")

-- Emprises au sol : le plancher du lobby et les pads de la salle doivent rester
-- disjoints en vue de dessus, sinon le spawn du lobby atterrit sur l'ExitPad.
local function footprintsOverlap(aCenter: Vector3, aSize: Vector3, bCenter: Vector3, bSize: Vector3): boolean
	return math.abs(aCenter.X - bCenter.X) < (aSize.X + bSize.X) / 2
		and math.abs(aCenter.Z - bCenter.Z) < (aSize.Z + bSize.Z) / 2
end

-- Centres tels que construits par ZoneService (dessus des pads aligné sur Grid.Origin.Y).
GameConfig.Lobby.FloorCenter = GameConfig.Lobby.RootOffset - Vector3.new(0, GameConfig.Lobby.FloorSize.Y / 2, 0)
GameConfig.GameRoom.PadCenter = Vector3.new(
	GameConfig.GameRoom.SpawnPadPosition.X,
	gameOrigin.Y - GameConfig.GameRoom.PadSize.Y / 2,
	GameConfig.GameRoom.SpawnPadPosition.Z
)
GameConfig.GameRoom.ExitPadCenter = Vector3.new(
	GameConfig.GameRoom.ExitPosition.X,
	gameOrigin.Y - GameConfig.GameRoom.ExitPadSize.Y / 2,
	GameConfig.GameRoom.ExitPosition.Z
)

local volumes = {
	{ "Lobby.Floor", GameConfig.Lobby.FloorCenter, GameConfig.Lobby.FloorSize },
	{ "GameRoom.SpawnPad", GameConfig.GameRoom.PadCenter, GameConfig.GameRoom.PadSize },
	{ "GameRoom.ExitPad", GameConfig.GameRoom.ExitPadCenter, GameConfig.GameRoom.ExitPadSize },
}

for i = 1, #volumes do
	for j = i + 1, #volumes do
		local a, b = volumes[i], volumes[j]
		if footprintsOverlap(a[2] :: Vector3, a[3] :: Vector3, b[2] :: Vector3, b[3] :: Vector3) then
			warn("[BPW] emprises générées sécantes :", a[1], "×", b[1])
		end
	end
end

-- Le spawn du lobby doit tomber sur le plancher du lobby, jamais sur un pad.
local lobbySpawnPos = GameConfig.Lobby.RootOffset + GameConfig.Lobby.SpawnOffset
local floorCenter = GameConfig.Lobby.FloorCenter
local floorSize = GameConfig.Lobby.FloorSize
if math.abs(lobbySpawnPos.X - floorCenter.X) > floorSize.X / 2 - 2
	or math.abs(lobbySpawnPos.Z - floorCenter.Z) > floorSize.Z / 2 - 2 then
	warn("[BPW] LobbySpawn hors du plancher du lobby :", lobbySpawnPos)
end
for _, volume in ipairs({ volumes[2], volumes[3] }) do
	local center, size = volume[2] :: Vector3, volume[3] :: Vector3
	if math.abs(lobbySpawnPos.X - center.X) < size.X / 2
		and math.abs(lobbySpawnPos.Z - center.Z) < size.Z / 2 then
		warn("[BPW] LobbySpawn au-dessus de", volume[1], lobbySpawnPos)
	end
end

return GameConfig
