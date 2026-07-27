--!strict
-- Textes fixes visibles par le joueur (source EN pour AutoLocalize Roblox).
-- Ne pas y mettre : noms de joueurs, nombres seuls, identifiants techniques.

local LocalizationStrings = {
	-- Pancarte tutoriel lobby
	HowToPlayTitle = "HOW TO PLAY",
	HowToPlayLine1 = "1. Enter the Bubble Room",
	HowToPlayLine2 = "2. Pop bubbles to fill your backpack",
	HowToPlayLine3 = "3. Return to the lobby",
	HowToPlayLine4 = "4. Sell your bubbles for coins",
	HowToPlayLine5 = "5. Upgrade and pop even more!",

	-- Classement
	TopCoinCollectors = "TOP COIN COLLECTORS",
	GlobalLeaderboard = "GLOBAL LEADERBOARD",
	Rank = "RANK",
	Player = "PLAYER",
	Coins = "COINS",
	LoadingLeaderboard = "Loading leaderboard...",
	NoRankingsYet = "No rankings yet",
	LeaderboardUnavailable = "Leaderboard temporarily unavailable",

	-- Kiosque vente
	SellYourBubbles = "SELL YOUR BUBBLES",
	PopFillCashIn = "POP · FILL · CASH IN",
	BagValue = "Bag value:",
	CoinsUnit = "coins",
	Terminal = "TERMINAL",
	StepOnThePad = "Step on the pad",
	ThenSell = "then SELL",
	TurnBubblesIntoCoins = "Turn your bubbles into coins!",

	-- Boutique
	BubbleShop = "BUBBLE SHOP",
	BuyBubblesAndItems = "BUY BUBBLES & ITEMS",
	BuyCoolItems = "Buy cool items to boost your adventure!",
	OpenShop = "Open Shop",
	ShopObject = "Bubble Shop",
	Upgrades = "Upgrades",
	Skills = "Skills",
	Items = "Items",
	Inventory = "Inventory",
	Equip = "Equip",
	Equipped = "Equipped",
	Unequip = "Unequip",
	Owned = "Owned",
	DefaultBackpack = "Default Backpack",
	GoldBackpack = "Gold Backpack",
	EmeraldBackpack = "Emerald Backpack",
	NeonBackpack = "Neon Backpack",
	CapacityLabel = "Capacity",
	SellBeforeSwitch = "Sell bubbles first to switch backpacks.",
	ItemPurchased = "Item purchased!",
	BackpackEquipped = "Backpack equipped!",
	BackpackUnequipped = "Default backpack equipped.",
	BubbleItems = "BUBBLE ITEMS",
	ItemPotion = "Potion",
	ItemWand = "Wand",
	ItemBoost = "Boost",
	ItemMegaBubble = "Mega Bubble",
	Max = "MAX",
	Denied = "Denied",
	Close = "X",

	-- HUD
	Backpack = "Backpack:",
	BackpackFull = "Backpack full!",
	BackpackAlmostFull = "Backpack almost full",
	RoomAvailable = "Room available",
	Level = "Level",
	BubblesSold = "bubbles sold",
	LevelMax = "MAX",
	GlobalGoal = "Global goal…",
	BubblesUnit = "bubbles",

	-- Portiques / panneaux
	BubbleRoom = "BUBBLE ROOM",
	BackToLobby = "← Lobby",

	-- Notifications
	BackpackFullSell = "Your backpack is full! Go sell your bubbles.",
	BackpackEmpty = "Your backpack is empty, nothing to sell.",
	ProgressReset = "Your progress has been reset.",
	WingsOn = "Wings on — jump to fly!",
	WingsOff = "Wings off.",
	AlreadyOwnWings = "You already own Wings (use the tool to toggle them).",
	WingsUnlocked = "Wings unlocked! Equip the Wings tool, then press RT to toggle them.",
	LegendaryChestAppeared = "⭐ A legendary chest has appeared!",
	ChestSuffix = " chest",
}

return table.freeze(LocalizationStrings)
