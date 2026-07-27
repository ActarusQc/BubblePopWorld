--!strict
-- Achats d'améliorations et d'items (validation 100% serveur).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local DataService = require(script.Parent.DataService)
local BackpackVisual = require(script.Parent.BackpackVisual)

local ShopService = {}

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
				Owned = owned[id] == true,
				Equipped = equipped == id,
			})
		end
	end
	return out
end

local function getShopData(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return { Upgrades = {}, Items = {}, EquippedBackpack = "" }
	end
	return {
		Upgrades = getUpgradeRows(profile),
		Items = getItemRows(profile),
		EquippedBackpack = profile.EquippedBackpack or "",
		DefaultCapacity = Config.Backpack.DefaultCapacity,
	}
end

local function buyUpgrade(player: Player, id: any)
	if type(id) ~= "string" then return false, "Invalid request" end
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
	return true, ("%s level %d"):format(def.Label, level + 1)
end

local function buyItem(player: Player, id: any)
	if type(id) ~= "string" then return false, "Invalid request" end
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
	return true, L10n.ItemPurchased
end

local function equipBackpack(player: Player, id: any)
	if type(id) ~= "string" then return false, "Invalid request" end

	local profile = DataService.Get(player)
	if not profile then return false, "Profile not loaded" end

	if id ~= "" then
		local def = Config.ShopItems[id]
		if not def or def.Kind ~= "Backpack" then
			return false, "Unknown backpack"
		end
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
