--!strict
-- Achats d'améliorations (validation 100% serveur).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local ShopService = {}

local function getShopData(player: Player)
	local profile = DataService.Get(player)
	if not profile then return {} end
	local out = {}
	for _, id in ipairs(Config.UpgradeOrder) do
		local def = Config.Upgrades[id]
		local level = profile.Upgrades[id] or 0
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

local function buyUpgrade(player: Player, id: any)
	if type(id) ~= "string" then return false, "Requête invalide" end
	local def = Config.Upgrades[id]
	if not def then return false, "Amélioration inconnue" end

	local profile = DataService.Get(player)
	if not profile then return false, "Profil non chargé" end

	local level = profile.Upgrades[id] or 0
	if level >= def.Max then return false, "Niveau maximum atteint" end

	local cost = Config.UpgradeCost(id, level)
	if profile.Coins < cost then return false, "Pièces insuffisantes" end

	profile.Coins -= cost
	profile.Upgrades[id] = level + 1
	DataService.ApplyCharacterStats(player)
	DataService.Push(player)
	return true, ("%s niveau %d"):format(def.Label, level + 1)
end

function ShopService.Start()
	Remotes.Func("GetShopData").OnServerInvoke = getShopData
	Remotes.Func("BuyUpgrade").OnServerInvoke = buyUpgrade
end

return ShopService
