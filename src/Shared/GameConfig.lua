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

-- Items achetables (séparés des upgrades de compétences).
-- IconKey → Shared/ShopIcons.ByKey (Image optionnelle pour assets UI).
GameConfig.ShopItems = {
	BackpackGold = {
		Label = "Gold Backpack",
		Kind = "Backpack",
		Capacity = 50,
		Cost = 10000,
		Style = "Gold",
		IconKey = "BackpackGold",
	},
	BackpackEmerald = {
		Label = "Emerald Backpack",
		Kind = "Backpack",
		Capacity = 50,
		Cost = 10000,
		Style = "Emerald",
		IconKey = "BackpackEmerald",
	},
	BackpackNeon = {
		Label = "Neon Backpack",
		Kind = "Backpack",
		Capacity = 50,
		Cost = 10000,
		Style = "Neon",
		IconKey = "BackpackNeon",
	},
}

GameConfig.ShopItemOrder = { "BackpackGold", "BackpackEmerald", "BackpackNeon" }

-- Vitrine 3D « Bubble Items » près du kiosque (affichage uniquement, pas d'achat ici).
-- LabelKey = clé LocalizationStrings. Extensible : ajouter une entrée + IconKey dans ShopIcons.
GameConfig.ShowcaseItems = {
	{ Id = "Potion", LabelKey = "ItemPotion", IconKey = "Potion" },
	{ Id = "Wand", LabelKey = "ItemWand", IconKey = "Wand" },
	{ Id = "Boost", LabelKey = "ItemBoost", IconKey = "Boost" },
	{ Id = "MegaBubble", LabelKey = "ItemMegaBubble", IconKey = "MegaBubble" },
}

-- Flags UI (masquer sans retirer la logique serveur / remotes).
GameConfig.UI = {
	-- Compteur communautaire bubbles / Target (HUD haut). Remettre true pour réafficher.
	ShowBubbleGoalUI = false,
}

function GameConfig.BackpackCapacityFor(equippedId: string?): number
	if type(equippedId) == "string" and equippedId ~= "" then
		local def = GameConfig.ShopItems[equippedId]
		if def and def.Kind == "Backpack" then
			return math.clamp(def.Capacity, GameConfig.Backpack.DefaultCapacity, GameConfig.Backpack.MaxCapacity)
		end
	end
	return GameConfig.Backpack.DefaultCapacity
end

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
-- Layout façade ouest (yaw 90°, vue joueur vers -X) :
--   GAUCHE (Z plus grand) = ItemShop / achat
--   DROITE (Z plus petit) = SellBooth / vente auto
local lobbyItemShopOffset = Vector3.new(-34, 0, 6)
local lobbySellOffset = Vector3.new(-34, 2, -27)
local lobbyEntranceOffset = Vector3.new(0, 3, 36)
-- Yaw 90° = façade tournée à droite (vers le spawn / +X local après rotation).
local sellBoothYawDegrees = 90
-- Pad posé sur le dessus de SellPlaza (plus de plancher avant flottant).
local sellPadLocalOffset = Vector3.new(0, -0.8, 6.8)
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
		-- Position DROITE du duo de kiosques (vente automatique du sac).
		Mode = "Code",
		YawDegrees = sellBoothYawDegrees,
		OriginOffset = lobbySellOffset,
		PadLocalOffset = sellPadLocalOffset,
		TankBubbleCount = 10,
		CounterSize = Vector3.new(16.5, 4.2, 6.2),
		CanopySize = Vector3.new(18.5, 1.1, 10.5),
		SignSize = Vector3.new(15.5, 4.0, 1.15),
		PadSize = Vector3.new(11, 0.4, 9),
		SignText = "SELL YOUR BUBBLES",
		TaglineText = "POP · FILL · CASH IN",
	},
	-- Vente automatique : entrer dans SellZone suffit, aucun ProximityPrompt.
	AutoSell = {
		PollInterval = 0.2, -- fréquence du test de présence dans SellZone
		ExitMargin = 3,     -- hystérésis : ré-armement seulement une fois clairement sorti
		Cooldown = 1.5,     -- délai mini entre deux ventes automatiques d'un même joueur
	},
	-- Boutique d'upgrades / items : bâtiment distinct du kiosque de vente.
	-- Aucune logique de vente de bulles (SellBooth / SellZone uniquement).
	-- Position GAUCHE du duo (même X/yaw, allée entre les plazas).
	ItemShop = {
		OriginOffset = lobbyItemShopOffset,
		YawDegrees = 90, -- même orientation que SellBooth (façade vers +X)
		-- Footprint walk-in (local X = largeur, local Z = profondeur ; entrée = +Z).
		Width = 22,
		Depth = 18,
		Height = 12,
		DoorWidth = 10,
		WallThickness = 0.6,
		SignText = "SHOP",
		TaglineText = "BUY BUBBLES & ITEMS",
		InteriorTagline = "Buy cool items to boost your adventure!",
		PromptMaxDistance = 13,
		-- Legacy (kiosque) — non utilisé par le walk-in builder :
		PromptActionText = "Open Shop",
		PromptObjectText = "Bubble Shop",
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
	SignText = "1. Enter the Bubble Room\n2. Pop bubbles to fill your backpack\n3. Return to the lobby\n4. Sell your bubbles for coins\n5. Upgrade and pop even more!",
	HowToPlayTitle = "HOW TO PLAY",
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

-- Teinte des bulles Normales par zone (salle principale = GameRoom / ClassicZone).
-- Rare / Golden / Diamond / Legendary restent sur BubbleTypes.List (config globale).
-- Common peut être un Color3 unique ou une liste de variantes (comme TintVariants).
GameConfig.ZoneBubblePalettes = {
	GameRoom = {
		Common = GameConfig.Bubble.Appearance.TintVariants,
	},
	SummerZone = {
		Common = Color3.fromRGB(255, 145, 35),
	},
}

-- Progression. Le niveau récompense la boucle complète (éclater → remplir → vendre) :
-- il dérive uniquement du cumul de bulles RÉELLEMENT vendues au kiosque, jamais des pops.
-- LevelThresholds[n] = total cumulé de bulles vendues pour atteindre le niveau n.
-- Au-delà du tableau, l'écart entre deux niveaux repart du dernier écart connu
-- (5000 - 3800 = 1200) et croît de 12 % par niveau : chaque palier coûte plus que le précédent.
GameConfig.Progression = {
	LevelThresholds = {
		0,
		125,
		300,
		550,
		900,
		1375,
		2000,
		2800,
		3800,
		5000,
	},
	PostTableIncrement = 1200,
	PostTableGrowth = 1.12,
	MaxLevel = 500,
}

local thresholdCache: { number } = {}

-- Total cumulé de bulles vendues nécessaire pour atteindre `level`.
function GameConfig.BubblesForLevel(level: number): number
	local P = GameConfig.Progression
	local table_ = P.LevelThresholds
	if level <= 1 then
		return 0
	end
	if level <= #table_ then
		return table_[level]
	end
	if level > P.MaxLevel then
		level = P.MaxLevel
	end
	if thresholdCache[level] then
		return thresholdCache[level]
	end
	local total = table_[#table_]
	local increment = P.PostTableIncrement
	for n = #table_ + 1, level do
		increment *= P.PostTableGrowth
		total += math.floor(increment + 0.5)
		thresholdCache[n] = total
	end
	return total
end

-- Niveau correspondant à un cumul de bulles vendues (1 = aucune vente).
function GameConfig.LevelForBubbles(sold: number): number
	local P = GameConfig.Progression
	local level = 1
	while level < P.MaxLevel and sold >= GameConfig.BubblesForLevel(level + 1) do
		level += 1
	end
	return level
end

-- Améliorations achetables. PerLevel = gain par niveau d'amélioration.
-- XPMult n'est plus vendue (l'XP ne pilote plus la progression) : la définition reste
-- pour que les niveaux déjà achetés se rechargent sans erreur, mais elle sort de la boutique.
GameConfig.Upgrades = {
	Speed = {
		Label = "Speed",
		Max = 15,
		BaseCost = 750,
		Growth = 1.45,
		PerLevel = 1.0,
	},
	Jump = {
		Label = "Jump",
		Max = 15,
		BaseCost = 1000,
		Growth = 1.50,
		PerLevel = 1.5,
	},
	Power = {
		Label = "Power (radius)",
		Max = 8,
		BaseCost = 3000,
		Growth = 1.75,
		PerLevel = 1,
	},
	CoinMult = {
		Label = "Coin multiplier",
		Max = 15,
		BaseCost = 2500,
		Growth = 1.65,
		PerLevel = 0.05,
	},
	XPMult = {
		Label = "XP multiplier",
		Max = 30,
		BaseCost = 300,
		Growth = 1.45,
		PerLevel = 0.10,
	},
}

GameConfig.UpgradeOrder = { "Speed", "Jump", "Power", "CoinMult" }

function GameConfig.UpgradeCost(id: string, currentLevel: number): number
	local def = GameConfig.Upgrades[id]
	if not def then return math.huge end
	return math.floor(def.BaseCost * (def.Growth ^ currentLevel))
end

-- Niveaux stockés peuvent dépasser Max (profils legacy) : effets + boutique clampés.
function GameConfig.EffectiveUpgradeLevel(id: string, storedLevel: number): number
	local def = GameConfig.Upgrades[id]
	if not def then
		return 0
	end
	local level = if type(storedLevel) == "number" then storedLevel else 0
	return math.clamp(math.floor(level), 0, def.Max)
end

-- Déplacement du personnage. Le projet utilise JumpPower (UseJumpPower = true),
-- pas JumpHeight : la hauteur du rebond sur les bulles en dépend directement
-- (Bubble.BounceMultiplier × JumpPower), donc on ne touche jamais à la gravité.
GameConfig.PlayerMovement = {
	WalkSpeed = 16,
	JumpPower = 35,
	UseJumpPower = true,
	MaxWalkSpeed = 80,
	MaxJumpPower = 120,
}

GameConfig.Combo = {
	Window = 2.5,   -- secondes pour enchaîner sans perdre le combo
	Step = 4,       -- nb de rebonds par palier
	Bonus = 0.5,    -- multiplicateur gagné par palier
	Max = 6,        -- multiplicateur maximum
}

-- Apparition des objets : une boucle par zone active, même gestionnaire
-- (DropService + ItemSpawnPlanner). MinInterval/MaxInterval sont l'intervalle
-- GLOBAL : chaque zone attend cet intervalle × nombre de zones actives, ce qui
-- conserve la fréquence globale historique tout en garantissant chaque zone.
GameConfig.Drops = {
	MinInterval = 25,
	MaxInterval = 55,
	Lifetime = 45,
	PickupRadius = 8,   -- ramassage automatique : distance joueur-objet (studs)
	PickupRate = 0.08,  -- fréquence de vérification côté serveur

	EdgeMargin = 3,       -- cellules ignorées sur le pourtour de chaque planche
	MaxActivePerZone = 2, -- objets simultanés max par zone

	-- Diagnostic serveur uniquement (jamais true en production) :
	-- cadence rapide par zone + logs préfixés [ItemSpawnDebug].
	ItemSpawnDebug = false,
	DebugMinInterval = 10,
	DebugMaxInterval = 15,
}

GameConfig.Chest = {
	MinInterval = 100,
	MaxInterval = 210,
	Lifetime = 50,
	Tiers = {
		{ Id = "Common",    Label = "Common",    Weight = 60, Coins = {150, 400},     Color = Color3.fromRGB(190,190,190) },
		{ Id = "Rare",      Label = "Rare",      Weight = 25, Coins = {600, 1500},    Color = Color3.fromRGB(70,150,255) },
		{ Id = "Epic",      Label = "Epic",      Weight = 12, Coins = {2500, 6000},   Color = Color3.fromRGB(180,80,255) },
		{ Id = "Legendary", Label = "Legendary", Weight = 3,  Coins = {12000, 30000}, Color = Color3.fromRGB(255,180,40), Announce = true },
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
	-- Classement mondial Coins (OrderedDataStore dédié, indépendant des LB legacy).
	GlobalCoinsLeaderboardStore = "GlobalCoinsLeaderboard_v1",
	LeaderboardWriteThrottle = 45, -- secondes entre écritures OrderedDataStore / joueur
	LeaderboardRefreshInterval = 60, -- secondes entre rafraîchissements du panneau
	-- Délai mini entre deux sauvegardes déclenchées par une vente : la progression
	-- est persistée vite sans épuiser le budget d'écriture DataStore.
	SaveAfterSellThrottle = 30,
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
	{ Id = "Prairie",    Label = "Meadow",     LevelReq = 1,   Mult = 1.0,  Sky = Color3.fromRGB(150, 220, 255), Ground = Color3.fromRGB(120, 200, 120) },
	{ Id = "Desert",     Label = "Desert",     LevelReq = 10,  Mult = 1.6,  Sky = Color3.fromRGB(255, 220, 160), Ground = Color3.fromRGB(230, 200, 130) },
	{ Id = "Forest",     Label = "Forest",     LevelReq = 20,  Mult = 2.4,  Sky = Color3.fromRGB(120, 190, 150), Ground = Color3.fromRGB(60, 130, 70) },
	{ Id = "Ice",        Label = "Ice",        LevelReq = 35,  Mult = 3.5,  Sky = Color3.fromRGB(200, 240, 255), Ground = Color3.fromRGB(180, 230, 250) },
	{ Id = "Volcano",    Label = "Volcano",    LevelReq = 55,  Mult = 5.0,  Sky = Color3.fromRGB(255, 120, 80),  Ground = Color3.fromRGB(90, 40, 40) },
	{ Id = "Clouds",     Label = "Clouds",     LevelReq = 80,  Mult = 7.5,  Sky = Color3.fromRGB(240, 240, 255), Ground = Color3.fromRGB(230, 230, 245) },
	{ Id = "Space",      Label = "Space",      LevelReq = 110, Mult = 11.0, Sky = Color3.fromRGB(20, 15, 45),    Ground = Color3.fromRGB(40, 35, 80) },
	{ Id = "Future",     Label = "Future",     LevelReq = 150, Mult = 16.0, Sky = Color3.fromRGB(40, 200, 220),  Ground = Color3.fromRGB(30, 60, 90) },
	{ Id = "Candy",      Label = "Candy",      LevelReq = 200, Mult = 24.0, Sky = Color3.fromRGB(255, 190, 230), Ground = Color3.fromRGB(255, 150, 200) },
	{ Id = "Underwater", Label = "Underwater", LevelReq = 260, Mult = 35.0, Sky = Color3.fromRGB(30, 120, 180),  Ground = Color3.fromRGB(25, 90, 140) },
}

GameConfig.Lobby.ItemShopPosition = lobbyRoot + GameConfig.Lobby.ItemShop.OriginOffset

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
assertOutsideGrid(GameConfig.Lobby.ItemShopPosition, "Lobby.ItemShopPosition")
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
