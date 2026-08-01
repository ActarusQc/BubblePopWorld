--!strict
-- Achats d'améliorations et d'items (validation 100% serveur).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local ShopCatalog = require(Shared.ShopCatalog)
local DataService = require(script.Parent.DataService)
local BackpackVisual = require(script.Parent.BackpackVisual)

local ShopService = {}

-- Seam tests (harness externe) : évite require GameAnalyticsService hors Roblox.
type AnalyticsHooksForTests = {
	onUpgradePurchased: ((player: Player, ctx: any) -> ())?,
	logCoinSink: ((player: Player, ctx: any) -> ())?,
}
local analyticsHooksForTests: AnalyticsHooksForTests? = nil

function ShopService.SetAnalyticsHooksForTests(hooks: AnalyticsHooksForTests?)
	analyticsHooksForTests = hooks
end

local function notifyUpgradePurchased(player: Player, ctx: any)
	if analyticsHooksForTests and analyticsHooksForTests.onUpgradePurchased then
		analyticsHooksForTests.onUpgradePurchased(player, ctx)
		return
	end
	pcall(function()
		local GameAnalyticsService = require(script.Parent.GameAnalyticsService)
		GameAnalyticsService.OnUpgradePurchased(player, ctx)
	end)
end

local function notifyItemCoinSink(player: Player, ctx: any)
	if analyticsHooksForTests and analyticsHooksForTests.logCoinSink then
		analyticsHooksForTests.logCoinSink(player, ctx)
		return
	end
	pcall(function()
		local GameAnalyticsService = require(script.Parent.GameAnalyticsService)
		GameAnalyticsService.LogCoinSink(player, ctx)
	end)
end

local ITEM_LABELS: { [string]: string } = {
	BackpackGold = L10n.GoldBackpack,
	BackpackEmerald = L10n.EmeraldBackpack,
	BackpackNeon = L10n.NeonBackpack,
}

local function refreshBackpackVisual(player: Player)
	local char = player.Character
	if char then
		BackpackVisual.Refresh(char)
	end
end

local function getUpgradeRows(profile: any)
	local out = {}
	for _, id in ipairs(Config.UpgradeOrder) do
		local def = Config.Upgrades[id]
		local stored = profile.Upgrades[id] or 0
		local level = Config.EffectiveUpgradeLevel(id, stored)
		table.insert(out, {
			Id = id,
			Label = def.Label,
			Level = level,
			Max = def.Max,
			Cost = if level >= def.Max then -1 else Config.UpgradeCost(id, level),
		})
	end
	return out
end

local function getItemRows(profile: any)
	local equipped = profile.EquippedBackpack or ""
	local owned = profile.OwnedItems or {}
	local out = {}
	for _, id in ipairs(Config.ShopItemOrder) do
		local def = Config.ShopItems[id]
		if def then
			table.insert(out, {
				Id = id,
				Label = ITEM_LABELS[id] or def.Label,
				Kind = def.Kind,
				Capacity = def.Capacity,
				Cost = def.Cost,
				Style = def.Style,
				IconKey = def.IconKey,
				Owned = owned[id] == true,
				Equipped = equipped == id,
			})
		end
	end
	return out
end

local function localized(key: string): string
	local value = (L10n :: any)[key]
	return if type(value) == "string" then value else key
end

local function getCategoryRows(profile: any)
	local categories = {
		Skills = {},
		Items = {},
		Cosmetics = {},
	}
	local coins = if type(profile.Coins) == "number" then profile.Coins else 0
	local equipped = profile.EquippedBackpack or ""
	local owned = if type(profile.OwnedItems) == "table" then profile.OwnedItems else {}

	for _, category in ipairs(ShopCatalog.Categories) do
		local rows = categories[category]
		if rows then
			for _, catalogItem in ipairs(ShopCatalog.GetCategoryItems(category)) do
				local row = {
					Id = catalogItem.Id,
					Label = localized(catalogItem.NameKey),
					Description = localized(catalogItem.DescriptionKey),
					Type = catalogItem.Type,
					Available = catalogItem.Available,
					Equipable = catalogItem.Equipable,
					IconKey = catalogItem.IconKey,
					ButtonState = "ComingSoon",
				}

				if catalogItem.Available and catalogItem.Type == "Upgrade" then
					local upgradeId = catalogItem.UpgradeId or catalogItem.Id
					local def = Config.Upgrades[upgradeId]
					if def then
						local stored = profile.Upgrades[upgradeId] or 0
						local level = Config.EffectiveUpgradeLevel(upgradeId, stored)
						row.Level = level
						row.Max = def.Max
						if level >= def.Max then
							row.ButtonState = "Max"
						else
							local cost = Config.UpgradeCost(upgradeId, level)
							row.Cost = cost
							row.ButtonState = if coins < cost then "TooExpensive" else "Upgrade"
						end
					end
				elseif catalogItem.Available and catalogItem.Type == "Backpack" then
					local shopItemId = catalogItem.ShopItemId or catalogItem.Id
					local def = Config.ShopItems[shopItemId]
					if def then
						local isOwned = owned[shopItemId] == true
						local isEquipped = equipped == shopItemId
						row.Cost = def.Cost
						row.Capacity = def.Capacity
						row.Owned = isOwned
						row.Equipped = isEquipped
						if isEquipped then
							row.ButtonState = "Equipped"
						elseif isOwned then
							row.ButtonState = "Equip"
						else
							row.ButtonState = if coins < def.Cost then "TooExpensive" else "Buy"
						end
					end
				end

				table.insert(rows, row)
			end
		end
	end
	return categories
end

local function getShopData(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return {
			Upgrades = {},
			Items = {},
			Categories = { Skills = {}, Items = {}, Cosmetics = {} },
			Coins = 0,
			EquippedBackpack = "",
			DefaultCapacity = Config.Backpack.DefaultCapacity,
		}
	end
	return {
		Upgrades = getUpgradeRows(profile),
		Items = getItemRows(profile),
		Categories = getCategoryRows(profile),
		Coins = profile.Coins,
		EquippedBackpack = profile.EquippedBackpack or "",
		DefaultCapacity = Config.Backpack.DefaultCapacity,
	}
end

local function buyUpgrade(player: Player, id: any)
	if type(id) ~= "string" then return false, "Invalid request" end
	if not ShopCatalog.IsPurchasable(id) then return false, "Coming soon" end
	local def = Config.Upgrades[id]
	if not def then return false, "Unknown upgrade" end
	if not table.find(Config.UpgradeOrder, id) then return false, "Upgrade not for sale" end

	local profile = DataService.Get(player)
	if not profile then return false, "Profile not loaded" end

	local stored = profile.Upgrades[id] or 0
	local level = Config.EffectiveUpgradeLevel(id, stored)
	if level >= def.Max then return false, "Max level reached" end

	local cost = Config.UpgradeCost(id, level)
	if profile.Coins < cost then return false, "Not enough coins" end

	profile.Coins -= cost
	profile.Upgrades[id] = level + 1
	DataService.ApplyCharacterStats(player)
	DataService.Push(player)
	DataService.NotifyCoinsChanged(player)
	-- Analytics post-succès uniquement (SKU = id upgrade brut, allowlist BuildEconomySkuSet).
	notifyUpgradePurchased(player, {
		upgradeId = id,
		amount = cost,
		endingBalance = profile.Coins,
	})
	return true, ("%s level %d"):format(def.Label, level + 1)
end

local function buyItem(player: Player, id: any)
	if type(id) ~= "string" then return false, "Invalid request" end
	if not ShopCatalog.IsPurchasable(id) then return false, "Coming soon" end
	local def = Config.ShopItems[id]
	if not def then return false, "Unknown item" end
	if not table.find(Config.ShopItemOrder, id) then return false, "Item not for sale" end

	local profile = DataService.Get(player)
	if not profile then return false, "Profile not loaded" end

	if type(profile.OwnedItems) ~= "table" then
		profile.OwnedItems = {}
	end
	if profile.OwnedItems[id] == true then
		return false, L10n.Owned
	end
	if profile.Coins < def.Cost then
		return false, "Not enough coins"
	end

	profile.Coins -= def.Cost
	profile.OwnedItems[id] = true
	-- Premier sac acheté : équipe automatiquement si aucun autre n'est équipé.
	if def.Kind == "Backpack" and (profile.EquippedBackpack == nil or profile.EquippedBackpack == "") then
		local targetCap = Config.BackpackCapacityFor(id)
		if profile.CurrentBubbles <= targetCap then
			profile.EquippedBackpack = id
			profile.BackpackCapacity = targetCap
			refreshBackpackVisual(player)
		end
	end

	DataService.Push(player)
	DataService.NotifyCoinsChanged(player)
	Remotes.Event("Announce"):FireClient(player, L10n.ItemPurchased, "item")
	-- Analytics post-succès uniquement (SKU = id item brut ; jamais d'onboarding item).
	notifyItemCoinSink(player, {
		amount = def.Cost,
		endingBalance = profile.Coins,
		transactionType = "Shop",
		itemSku = id,
	})
	return true, L10n.ItemPurchased
end

local function equipBackpack(player: Player, id: any)
	if type(id) ~= "string" then return false, "Invalid request" end

	if id ~= "" then
		local catalogItem = ShopCatalog.GetItem(id)
		local def = Config.ShopItems[id]
		if not catalogItem or catalogItem.Type ~= "Backpack" or not catalogItem.Available
			or not ShopCatalog.IsPurchasable(id) or not def or def.Kind ~= "Backpack" then
			return false, "Unknown backpack"
		end
	end

	local profile = DataService.Get(player)
	if not profile then return false, "Profile not loaded" end

	if id ~= "" then
		if type(profile.OwnedItems) ~= "table" or profile.OwnedItems[id] ~= true then
			return false, "Not owned"
		end
	end

	local targetCap = Config.BackpackCapacityFor(id)
	if profile.CurrentBubbles > targetCap then
		return false, L10n.SellBeforeSwitch
	end

	profile.EquippedBackpack = id
	profile.BackpackCapacity = targetCap
	DataService.Push(player)
	refreshBackpackVisual(player)

	if id == "" then
		Remotes.Event("Announce"):FireClient(player, L10n.BackpackUnequipped, "item")
		return true, L10n.BackpackUnequipped
	end
	Remotes.Event("Announce"):FireClient(player, L10n.BackpackEquipped, "item")
	return true, L10n.BackpackEquipped
end

function ShopService.Start()
	Remotes.Func("GetShopData").OnServerInvoke = getShopData
	Remotes.Func("BuyUpgrade").OnServerInvoke = buyUpgrade
	Remotes.Func("BuyItem").OnServerInvoke = buyItem
	Remotes.Func("EquipBackpack").OnServerInvoke = equipBackpack
end

return ShopService
