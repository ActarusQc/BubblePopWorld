--!strict
-- Validations AnalyticsConfig (funnels, étapes, allowlists).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnalyticsConfig = require(Shared.AnalyticsConfig)

local AnalyticsConfigTests = {}

local EXPECTED_ONBOARDING = {
	"JoinedGame",
	"ReachedMainBubbleRoom",
	"PoppedFirstBubble",
	"BackpackFullFirstTime",
	"ReturnedToLobbyAfterFullBackpack",
	"SoldFirstBackpack",
	"PurchasedFirstUpgrade",
}

local EXPECTED_SUMMER = {
	"ReachedRequiredLevel",
	"ArrivedAtSummerBridge",
	"PoppedFirstSummerBubble",
	"FilledFirstSummerBackpack",
	"SoldFirstSummerBackpack",
}

function AnalyticsConfigTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[AnalyticsConfigTests] FAIL:", msg)
			ok = false
		end
	end

	check(#AnalyticsConfig.OnboardingSteps == 7, "exactly 7 onboarding steps")
	for i, expectedName in ipairs(EXPECTED_ONBOARDING) do
		local entry = AnalyticsConfig.OnboardingSteps[i]
		check(entry ~= nil, "onboarding step " .. tostring(i) .. " exists")
		if entry then
			check(entry.step == i, "onboarding step " .. expectedName .. " numbered " .. tostring(i))
			check(entry.name == expectedName, "onboarding step " .. tostring(i) .. " name")
		end
	end

	check(#AnalyticsConfig.SummerSteps == 5, "exactly 5 summer steps")
	for i, expectedName in ipairs(EXPECTED_SUMMER) do
		local entry = AnalyticsConfig.SummerSteps[i]
		check(entry ~= nil, "summer step " .. tostring(i) .. " exists")
		if entry then
			check(entry.step == i, "summer step " .. expectedName .. " numbered " .. tostring(i))
			check(entry.name == expectedName, "summer step " .. tostring(i) .. " name")
		end
	end

	for _, entry in ipairs(AnalyticsConfig.OnboardingSteps) do
		check(entry.name ~= "ReachedLevel2", "no ReachedLevel2 in onboarding")
	end

	check(#AnalyticsConfig.CustomEvents <= AnalyticsConfig.Limits.MaxCustomEventNames, "custom events within limit")
	check(AnalyticsConfig.CurrencyType == "Coins", 'CurrencyType == "Coins"')
	check(AnalyticsConfig.OnboardingAnalyticsVersion == 1, "OnboardingAnalyticsVersion == 1")
	check(AnalyticsConfig.SummerZoneAnalyticsVersion == 1, "SummerZoneAnalyticsVersion == 1")
	check(AnalyticsConfig.FlushIntervalSeconds == 60, "FlushIntervalSeconds == 60")
	check(AnalyticsConfig.FunnelOnboarding == "NewPlayerOnboarding", "FunnelOnboarding exact")
	check(AnalyticsConfig.FunnelSummer == "SummerZoneUnlock", "FunnelSummer exact")

	for stepName, eventName in pairs(AnalyticsConfig.FirstTimingByStep) do
		check(AnalyticsConfig.IsOnboardingStepName(stepName), "FirstTimingByStep key is onboarding step: " .. stepName)
		check(AnalyticsConfig.IsCustomEventAllowed(eventName), "FirstTimingByStep value allowed: " .. eventName)
	end

	check(AnalyticsConfig.GetOnboardingStepIndex("PoppedFirstBubble") == 3, "GetOnboardingStepIndex PoppedFirstBubble")
	check(AnalyticsConfig.GetOnboardingStepIndex("JoinedGame") == 1, "GetOnboardingStepIndex JoinedGame")
	check(AnalyticsConfig.GetOnboardingStepIndex("PurchasedFirstUpgrade") == 7, "GetOnboardingStepIndex PurchasedFirstUpgrade")
	check(AnalyticsConfig.GetSummerStepIndex("ArrivedAtSummerBridge") == 2, "GetSummerStepIndex ArrivedAtSummerBridge")

	check(AnalyticsConfig.IsSummerStepName("ArrivedAtSummerBridge") == true, "IsSummerStepName ArrivedAtSummerBridge")
	check(AnalyticsConfig.IsOnboardingStepName("ArrivedAtSummerBridge") == false, "IsOnboardingStepName false for summer step")

	local versionField = AnalyticsConfig.VersionCustomField(1)
	local fieldCount = 0
	local sawV1 = false
	for key, value in versionField do
		fieldCount += 1
		check(type(key) == "string", "VersionCustomField key is string")
		check(key ~= "Name" and key ~= "UserId", "VersionCustomField no player identifiers")
		check(type(value) == "string", "VersionCustomField value is string")
		if value == "v1" then
			sawV1 = true
		end
	end
	check(fieldCount == 1, "VersionCustomField returns one field")
	check(sawV1, 'VersionCustomField(1) value == "v1"')

	check(AnalyticsConfig.IsCustomEventAllowed("SessionNormalPops") == true, "IsCustomEventAllowed known event")
	check(AnalyticsConfig.IsCustomEventAllowed("NotARealEvent") == false, "IsCustomEventAllowed rejects unknown")

	check(AnalyticsConfig.IsEconomySkuAllowed("BubbleSale_GameRoom") == true, "IsEconomySkuAllowed base sku")
	check(AnalyticsConfig.IsEconomySkuAllowed("TentChest") == true, "IsEconomySkuAllowed TentChest")
	check(AnalyticsConfig.IsEconomySkuAllowed("Speed") == true, "IsEconomySkuAllowed upgrade from GameConfig")
	check(AnalyticsConfig.IsEconomySkuAllowed("BackpackGold") == true, "IsEconomySkuAllowed shop item from GameConfig")
	check(AnalyticsConfig.IsEconomySkuAllowed("InvalidSku") == false, "IsEconomySkuAllowed rejects unknown")

	if ok then
		print("[AnalyticsConfigTests] OK")
	end
	return ok
end

return AnalyticsConfigTests
