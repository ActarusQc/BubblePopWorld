--!strict
-- Constantes analytics phase 1 : funnels, étapes, allowlists, limites.

local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.GameConfig)

local AnalyticsConfig = {}

AnalyticsConfig.OnboardingAnalyticsVersion = 1
AnalyticsConfig.SummerZoneAnalyticsVersion = 1
AnalyticsConfig.FlushIntervalSeconds = 60
AnalyticsConfig.CurrencyType = "Coins"
AnalyticsConfig.DebugEnabled = RunService:IsStudio()
AnalyticsConfig.FunnelOnboarding = "NewPlayerOnboarding"
AnalyticsConfig.FunnelSummer = "SummerZoneUnlock"
AnalyticsConfig.ProgressionPath = "PlayerLevel"

AnalyticsConfig.OnboardingSteps = {
	{ step = 1, name = "JoinedGame" },
	{ step = 2, name = "ReachedMainBubbleRoom" },
	{ step = 3, name = "PoppedFirstBubble" },
	{ step = 4, name = "BackpackFullFirstTime" },
	{ step = 5, name = "ReturnedToLobbyAfterFullBackpack" },
	{ step = 6, name = "SoldFirstBackpack" },
	{ step = 7, name = "PurchasedFirstUpgrade" },
}

AnalyticsConfig.SummerSteps = {
	{ step = 1, name = "ReachedRequiredLevel" },
	{ step = 2, name = "ArrivedAtSummerBridge" },
	{ step = 3, name = "PoppedFirstSummerBubble" },
	{ step = 4, name = "FilledFirstSummerBackpack" },
	{ step = 5, name = "SoldFirstSummerBackpack" },
}

AnalyticsConfig.FirstTimingByStep = {
	PoppedFirstBubble = "SecondsToFirstBubble",
	BackpackFullFirstTime = "SecondsToBackpackFull",
	SoldFirstBackpack = "SecondsToFirstSale",
	PurchasedFirstUpgrade = "SecondsToFirstUpgrade",
}

AnalyticsConfig.CustomEvents = {
	"SecondsToFirstBubble",
	"SecondsToBackpackFull",
	"SecondsToFirstSale",
	"SecondsToFirstUpgrade",
	"FirstSessionDuration",
	"SessionSecondsToFirstBubble",
	"SessionSecondsToFirstSale",
	"FirstSpecialBubble",
	"SawSummerZoneRequirement",
	"OpenedBubbleTransit",
	"SelectedSummerZone",
	"PlayerLevelReached",
	"SessionNormalPops",
	"SessionSpecialPops",
	"SessionPopsGameRoom",
	"SessionPopsSummerZone",
	"SessionToolUses",
	"SessionSalesCount",
	"SessionCoinsFromSales",
	"SessionZoneSecondsLobby",
	"SessionZoneSecondsGameRoom",
	"SessionZoneSecondsSummerZone",
	"SessionZoneChanges",
}

AnalyticsConfig.EconomySkus = {
	"BubbleSale_GameRoom",
	"BubbleSale_SummerZone",
	"BubbleSale_Mixed",
	"Chest",
	"DailyReward",
	"Code",
	"Admin",
}

AnalyticsConfig.Limits = {
	MaxCurrencyTypes = 10,
	MaxCustomFields = 3,
	MaxCustomEventNames = 100,
	MaxFunnels = 10,
}

--------------------------------------------------------------------
-- Index internes (lookup à l'init)
--------------------------------------------------------------------
local onboardingStepByName: { [string]: number } = {}
local summerStepByName: { [string]: number } = {}
local customEventAllowed: { [string]: boolean } = {}

for _, entry in ipairs(AnalyticsConfig.OnboardingSteps) do
	onboardingStepByName[entry.name] = entry.step
end

for _, entry in ipairs(AnalyticsConfig.SummerSteps) do
	summerStepByName[entry.name] = entry.step
end

for _, eventName in ipairs(AnalyticsConfig.CustomEvents) do
	customEventAllowed[eventName] = true
end

local mergedEconomySkuSet: { [string]: boolean }? = nil

function AnalyticsConfig.BuildEconomySkuSet(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, sku in ipairs(AnalyticsConfig.EconomySkus) do
		set[sku] = true
	end
	if type(GameConfig.Upgrades) == "table" then
		for upgradeId in GameConfig.Upgrades do
			if type(upgradeId) == "string" then
				set[upgradeId] = true
			end
		end
	end
	if type(GameConfig.UpgradeOrder) == "table" then
		for _, upgradeId in ipairs(GameConfig.UpgradeOrder) do
			if type(upgradeId) == "string" then
				set[upgradeId] = true
			end
		end
	end
	if type(GameConfig.ShopItemOrder) == "table" then
		for _, itemId in ipairs(GameConfig.ShopItemOrder) do
			if type(itemId) == "string" then
				set[itemId] = true
			end
		end
	end
	return set
end

local function getEconomySkuSet(): { [string]: boolean }
	if mergedEconomySkuSet == nil then
		mergedEconomySkuSet = AnalyticsConfig.BuildEconomySkuSet()
	end
	return mergedEconomySkuSet
end

function AnalyticsConfig.GetOnboardingStepIndex(name: string): number?
	return onboardingStepByName[name]
end

function AnalyticsConfig.GetSummerStepIndex(name: string): number?
	return summerStepByName[name]
end

function AnalyticsConfig.IsOnboardingStepName(name: string): boolean
	return onboardingStepByName[name] ~= nil
end

function AnalyticsConfig.IsSummerStepName(name: string): boolean
	return summerStepByName[name] ~= nil
end

function AnalyticsConfig.IsCustomEventAllowed(name: string): boolean
	return customEventAllowed[name] == true
end

function AnalyticsConfig.IsEconomySkuAllowed(sku: string): boolean
	return getEconomySkuSet()[sku] == true
end

-- Clé CustomField1 : Enum.AnalyticsCustomFieldKeys si dispo, sinon chaîne littérale.
function AnalyticsConfig.VersionCustomField(version: number): { [string]: string }
	local key = "CustomField1"
	local ok, enumItem = pcall(function()
		return Enum.AnalyticsCustomFieldKeys.CustomField1
	end)
	if ok and enumItem ~= nil then
		key = enumItem.Name
	end
	return {
		[key] = "v" .. tostring(version),
	}
end

return AnalyticsConfig
