--!strict
-- Tests d'intégration hors Roblox de ShopService via ses callbacks RemoteFunction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ShopService = require(script.Parent.ShopService)

local ShopServiceTests = {}

type Counters = {
	Get: number,
	Push: number,
	ApplyCharacterStats: number,
	NotifyCoinsChanged: number,
	Announce: number,
	Refresh: number,
}

type Context = {
	Callbacks: { [string]: (any, any) -> any },
	Profile: any,
	Counters: Counters,
	ResetCounters: () -> (),
}

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = clone(child)
	end
	return out
end

local function same(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if not same(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function rowById(rows: { any }, id: string): any
	for _, row in ipairs(rows) do
		if row.Id == id then
			return row
		end
	end
	error("ligne absente : " .. id, 2)
end

function ShopServiceTests.Run(context: Context?): boolean
	-- Suite conçue pour le harnais externe tools/run_shop_service_tests.py (pas Studio Play).
	if type(context) ~= "table" or type(context.Callbacks) ~= "table" then
		print("[ShopServiceTests] SKIP Studio: exécuter séparément via python tools/run_shop_service_tests.py")
		return true
	end

	local passed, failed = 0, 0
	local function check(condition: boolean, message: string)
		if condition then
			passed += 1
			print("  PASS  " .. message)
		else
			failed += 1
			print("  FAIL  " .. message)
		end
	end

	local callbacks = context.Callbacks
	local profile = context.Profile
	local player = { Character = {} }
	local getShopData = callbacks.GetShopData
	local buyUpgrade = callbacks.BuyUpgrade
	local buyItem = callbacks.BuyItem
	local equipBackpack = callbacks.EquipBackpack

	check(type(getShopData) == "function", "Start branche GetShopData")
	check(type(buyUpgrade) == "function", "Start branche BuyUpgrade")
	check(type(buyItem) == "function", "Start branche BuyItem")
	check(type(equipBackpack) == "function", "Start branche EquipBackpack")

	profile.Coins = 50000
	profile.Upgrades = { Speed = 1, Jump = 2, Power = 0, CoinMult = 3 }
	profile.OwnedItems = { BackpackGold = true }
	profile.EquippedBackpack = "BackpackGold"
	profile.BackpackCapacity = Config.ShopItems.BackpackGold.Capacity
	profile.CurrentBubbles = 0

	local data = getShopData(player)
	check(type(data.Categories) == "table", "GetShopData contient Categories")
	check(type(data.Upgrades) == "table" and #data.Upgrades == #Config.UpgradeOrder,
		"GetShopData conserve Upgrades legacy")
	check(type(data.Items) == "table" and #data.Items == #Config.ShopItemOrder,
		"GetShopData conserve Items legacy")
	check(data.Coins == profile.Coins, "GetShopData contient Coins")
	check(data.EquippedBackpack == "BackpackGold", "GetShopData conserve EquippedBackpack")
	check(data.DefaultCapacity == Config.Backpack.DefaultCapacity, "GetShopData conserve DefaultCapacity")

	if type(data.Categories) == "table" then
		local speed = rowById(data.Categories.Skills, "Speed")
		local gold = rowById(data.Categories.Items, "BackpackGold")
		local magnet = rowById(data.Categories.Skills, "Magnet")
		local cap = rowById(data.Categories.Cosmetics, "Cap")
		check(speed.Cost == Config.UpgradeCost("Speed", 1), "coût Speed vient de GameConfig")
		check(gold.Cost == Config.ShopItems.BackpackGold.Cost, "coût BackpackGold vient de GameConfig")
		check(speed.Level == 1 and speed.Max == Config.Upgrades.Speed.Max, "ligne upgrade contient Level/Max")
		check(gold.Capacity == Config.ShopItems.BackpackGold.Capacity, "ligne sac contient Capacity")
		check(gold.Owned == true and gold.Equipped == true, "ligne sac contient Owned/Equipped")
		check(magnet.Cost == nil and magnet.ButtonState == "ComingSoon",
			"Magnet Coming Soon sans Cost")
		check(cap.Cost == nil and cap.ButtonState == "ComingSoon", "Cap Coming Soon sans Cost")
		check(type(speed.Label) == "string" and speed.Label ~= "SkillSpeed", "NameKey résolu côté serveur")
		check(type(speed.Description) == "string" and speed.Description ~= "SkillSpeedDesc",
			"DescriptionKey résolu côté serveur")
		print(("  EXEMPLE GetShopData Coins=%d EquippedBackpack=%s Upgrades=%d Items=%d Categories={Skills=%d,Items=%d,Cosmetics=%d} Speed={Cost=%d,ButtonState=%s} Magnet={Cost=nil,ButtonState=%s}"):format(
			data.Coins,
			data.EquippedBackpack,
			#data.Upgrades,
			#data.Items,
			#data.Categories.Skills,
			#data.Categories.Items,
			#data.Categories.Cosmetics,
			speed.Cost,
			speed.ButtonState,
			magnet.ButtonState
		))
	end

	local legacyUpgrade = data.Upgrades[1]
	check(legacyUpgrade.Description == nil and legacyUpgrade.Type == nil and legacyUpgrade.ButtonState == nil,
		"structure Upgrades legacy inchangée")
	local legacyItem = data.Items[1]
	check(legacyItem.Description == nil and legacyItem.Type == nil and legacyItem.ButtonState == nil,
		"structure Items legacy inchangée")

	profile.Coins = 0
	profile.Upgrades.Speed = 0
	profile.EquippedBackpack = ""
	local poorData = getShopData(player)
	check(rowById(poorData.Categories.Skills, "Speed").ButtonState == "TooExpensive",
		"upgrade trop cher retourne TooExpensive")
	check(rowById(poorData.Categories.Items, "BackpackGold").ButtonState == "Equip",
		"sac possédé non équipé retourne Equip")
	check(rowById(poorData.Categories.Items, "BackpackEmerald").ButtonState == "TooExpensive",
		"sac non possédé trop cher retourne TooExpensive")

	profile.Coins = 50000
	local richData = getShopData(player)
	check(rowById(richData.Categories.Items, "BackpackEmerald").ButtonState == "Buy",
		"sac non possédé achetable retourne Buy")
	profile.Upgrades.Speed = Config.Upgrades.Speed.Max
	local maxData = getShopData(player)
	check(rowById(maxData.Categories.Skills, "Speed").ButtonState == "Max",
		"upgrade au maximum retourne Max")

	for _, attempt in ipairs({
		{ callback = buyUpgrade, id = 42 },
		{ callback = buyItem, id = {} },
		{ callback = buyUpgrade, id = "Unknown" },
		{ callback = buyItem, id = "Unknown" },
	}) do
		context.ResetCounters()
		local ok, message = attempt.callback(player, attempt.id)
		check(ok == false and type(message) == "string", "argument invalide/inconnu rejeté proprement")
		check(context.Counters.Get == 0 and context.Counters.Push == 0,
			"argument invalide/inconnu rejeté avant DataService.Get/Push")
	end

	for _, attempt in ipairs({
		{ callback = buyUpgrade, id = "Magnet" },
		{ callback = buyItem, id = "Pin" },
		{ callback = buyItem, id = "Hammer" },
		{ callback = buyItem, id = "Cap" },
	}) do
		context.ResetCounters()
		local before = clone(profile)
		local coinsBefore = profile.Coins
		local ok, message = attempt.callback(player, attempt.id)
		check(ok == false and type(message) == "string", attempt.id .. " échoue proprement")
		check(context.Counters.Get == 0 and context.Counters.Push == 0,
			attempt.id .. " rejeté avant DataService.Get/Push")
		check(same(profile, before), attempt.id .. " ne mute pas le profil")
		print(("  PREUVE ComingSoon id=%s ok=%s coins=%d->%d Get=%d Push=%d profilInchange=%s"):format(
			attempt.id,
			tostring(ok),
			coinsBefore,
			profile.Coins,
			context.Counters.Get,
			context.Counters.Push,
			tostring(same(profile, before))
		))
	end

	local upgradeAnalytics: { any } = {}
	local itemSinkAnalytics: { any } = {}
	ShopService.SetAnalyticsHooksForTests({
		onUpgradePurchased = function(p, ctx)
			table.insert(upgradeAnalytics, { player = p, ctx = ctx })
		end,
		logCoinSink = function(p, ctx)
			table.insert(itemSinkAnalytics, { player = p, ctx = ctx })
		end,
	})

	context.ResetCounters()
	upgradeAnalytics = {}
	itemSinkAnalytics = {}
	profile.Coins = 10000
	profile.Upgrades.Speed = 1
	local speedCost = Config.UpgradeCost("Speed", 1)
	local speedOk = buyUpgrade(player, "Speed")
	check(speedOk == true, "achat Speed réussit")
	check(profile.Coins == 10000 - speedCost and profile.Upgrades.Speed == 2,
		"achat Speed débite le coût exact et augmente le niveau")
	check(context.Counters.ApplyCharacterStats == 1 and context.Counters.Push == 1
		and context.Counters.NotifyCoinsChanged == 1, "achat Speed appelle Apply/Push/Notify")
	check(#upgradeAnalytics == 1, "Task12 achat Speed → onUpgradePurchased une fois")
	check(
		upgradeAnalytics[1] ~= nil
			and upgradeAnalytics[1].ctx ~= nil
			and upgradeAnalytics[1].ctx.upgradeId == "Speed"
			and upgradeAnalytics[1].ctx.amount == speedCost
			and upgradeAnalytics[1].ctx.endingBalance == profile.Coins,
		"Task12 achat Speed → ctx upgradeId/amount/endingBalance"
	)
	check(#itemSinkAnalytics == 0, "Task12 achat Speed → pas de logCoinSink item")
	print(("  PREUVE Speed cost=%d coins=10000->%d level=1->%d Apply=%d Push=%d Notify=%d"):format(
		speedCost,
		profile.Coins,
		profile.Upgrades.Speed,
		context.Counters.ApplyCharacterStats,
		context.Counters.Push,
		context.Counters.NotifyCoinsChanged
	))

	context.ResetCounters()
	upgradeAnalytics = {}
	itemSinkAnalytics = {}
	profile.Coins = Config.ShopItems.BackpackGold.Cost + 500
	profile.OwnedItems = {}
	profile.EquippedBackpack = ""
	profile.BackpackCapacity = Config.Backpack.DefaultCapacity
	profile.CurrentBubbles = 0
	local goldCost = Config.ShopItems.BackpackGold.Cost
	local goldOk = buyItem(player, "BackpackGold")
	check(goldOk == true, "achat BackpackGold réussit")
	check(profile.Coins == 500 and profile.OwnedItems.BackpackGold == true,
		"achat BackpackGold débite le coût exact et marque owned")
	check(profile.EquippedBackpack == "BackpackGold"
		and profile.BackpackCapacity == Config.ShopItems.BackpackGold.Capacity,
		"premier BackpackGold est auto-équipé")
	check(context.Counters.Push == 1 and context.Counters.NotifyCoinsChanged == 1
		and context.Counters.Announce == 1 and context.Counters.Refresh == 1,
		"achat BackpackGold appelle Push/Notify/Announce/Refresh")
	check(#itemSinkAnalytics == 1, "Task12 achat item → logCoinSink une fois")
	check(
		itemSinkAnalytics[1] ~= nil
			and itemSinkAnalytics[1].ctx ~= nil
			and itemSinkAnalytics[1].ctx.itemSku == "BackpackGold"
			and itemSinkAnalytics[1].ctx.amount == goldCost
			and itemSinkAnalytics[1].ctx.endingBalance == profile.Coins
			and itemSinkAnalytics[1].ctx.transactionType == "Shop",
		"Task12 achat item → sink Shop + sku id brut"
	)
	check(#upgradeAnalytics == 0, "Task12 achat item → pas d'onUpgradePurchased")
	print(("  PREUVE BackpackGold cost=%d coins=%d->%d owned=%s equipped=%s Push=%d Notify=%d Announce=%d Refresh=%d"):format(
		goldCost,
		goldCost + 500,
		profile.Coins,
		tostring(profile.OwnedItems.BackpackGold),
		profile.EquippedBackpack,
		context.Counters.Push,
		context.Counters.NotifyCoinsChanged,
		context.Counters.Announce,
		context.Counters.Refresh
	))

	upgradeAnalytics = {}
	itemSinkAnalytics = {}
	local failOk = buyUpgrade(player, "Magnet")
	check(failOk == false, "Task12 achat échoué → false")
	check(#upgradeAnalytics == 0 and #itemSinkAnalytics == 0,
		"Task12 achat échoué → aucun hook analytics")

	ShopService.SetAnalyticsHooksForTests(nil)

	context.ResetCounters()
	local comingSoonOk = equipBackpack(player, "Cap")
	check(comingSoonOk == false, "EquipBackpack rejette Coming Soon")
	local nonOwnedOk = equipBackpack(player, "BackpackEmerald")
	check(nonOwnedOk == false, "EquipBackpack rejette sac live non possédé")
	local equipOk = equipBackpack(player, "BackpackGold")
	check(equipOk == true and profile.EquippedBackpack == "BackpackGold",
		"EquipBackpack accepte sac live possédé")

	context.ResetCounters()
	profile.CurrentBubbles = 0
	local defaultOk = equipBackpack(player, "")
	check(defaultOk == true, "EquipBackpack accepte le sac par défaut")
	check(profile.EquippedBackpack == "", "sac par défaut vide EquippedBackpack")
	check(profile.BackpackCapacity == Config.Backpack.DefaultCapacity,
		"sac par défaut restaure DefaultCapacity")
	check(profile.OwnedItems.BackpackGold == true and profile.CurrentBubbles == 0,
		"sac par défaut conserve possession et bulles")
	check(context.Counters.Get == 1 and context.Counters.Push == 1
		and context.Counters.Refresh == 1 and context.Counters.Announce == 1,
		"sac par défaut appelle Get/Push/Refresh/Announce une fois")
	check(context.Counters.ApplyCharacterStats == 0 and context.Counters.NotifyCoinsChanged == 0,
		"sac par défaut n'appelle pas Apply/NotifyCoins")

	print(("\nShopServiceTests: %d réussis, %d échoués"):format(passed, failed))
	return failed == 0
end

return ShopServiceTests
