--!strict
-- Configuration centralisée des défis quotidiens / hebdomadaires + classement.
-- Valeurs d'équilibrage uniquement ici (pas de magic numbers dans le service).

local RunService = game:GetService("RunService")

local ChallengeConfig = {}

--------------------------------------------------------------------
-- Activation
--------------------------------------------------------------------
ChallengeConfig.Enabled = true
ChallengeConfig.Version = 1

--------------------------------------------------------------------
-- Horloge & classement
--------------------------------------------------------------------
ChallengeConfig.DailyResetHourUtc = 0 -- 00:00 UTC
ChallengeConfig.WeeklyResetWeekday = 1 -- lundi (ISO : lundi = 1)
ChallengeConfig.DailyLeaderboardStorePrefix = "DailyBubblePops_v1_"
ChallengeConfig.LeaderboardTopN = 10
ChallengeConfig.LeaderboardWriteIntervalSeconds = 45
ChallengeConfig.LeaderboardRefreshIntervalSeconds = 60
ChallengeConfig.LeaderboardMaxWriteAttempts = 4
-- Giant Bubble détruite = 1 pop classement seulement si true (v1 = false).
ChallengeConfig.CountGiantDestroyAsPop = false

--------------------------------------------------------------------
-- Mini-événement vedette
--------------------------------------------------------------------
ChallengeConfig.FeaturedEventRotation = { "GoldenWave", "ColorRush" }
ChallengeConfig.FeaturedEventWeightMultiplier = 2

--------------------------------------------------------------------
-- Progress UI / notifs
--------------------------------------------------------------------
ChallengeConfig.ProgressMilestones = { 0.25, 0.5, 0.75, 1.0 }
ChallengeConfig.ClientStateThrottleSeconds = 0.35
ChallengeConfig.TrackedPrefKey = "BPW_ChallengeTracked"
ChallengeConfig.CardCollapsedPrefKey = "BPW_ChallengeCardCollapsed"

--------------------------------------------------------------------
-- Studio
--------------------------------------------------------------------
ChallengeConfig.Studio = {
	Enabled = true,
	-- Multiplie les cibles (ex. 0.1 rend les défis plus courts en dev).
	TargetScale = 1,
	ForceLowTargets = false,
	LowTargetOverride = 5,
}

--------------------------------------------------------------------
-- Récompenses (PendingSellBonus uniquement — XP gelée dans ce projet)
--------------------------------------------------------------------
ChallengeConfig.Rewards = {
	DailyEasy = { Type = "SellBonus", Amount = 250 },
	DailyMedium = { Type = "SellBonus", Amount = 400 },
	DailyEvent = { Type = "SellBonus", Amount = 500 },
	Weekly = { Type = "SellBonus", Amount = 2000 },
}

--------------------------------------------------------------------
-- Pools de défis
-- Metric : compteur interne partagé avec ChallengeLogic / ChallengeService
-- RequiresSummer : nécessite niveau / accès Summer Zone
--------------------------------------------------------------------
export type ChallengeDef = {
	Id: string,
	Metric: string,
	Target: number,
	Slot: string, -- Easy | Medium | Event | Weekly
	RequiresSummer: boolean?,
	FeaturedOnly: boolean?, -- n'utiliser que si Metric match featured event
	TitleKey: string,
	DescKey: string,
	RewardKey: string, -- clé dans ChallengeConfig.Rewards
}

ChallengeConfig.DailyEasyPool = {
	{
		Id = "PopBubbles_50",
		Metric = "PopBubbles",
		Target = 50,
		Slot = "Easy",
		TitleKey = "ChallengePopBubbles",
		DescKey = "ChallengePopBubblesDesc",
		RewardKey = "DailyEasy",
	},
	{
		Id = "SellFull_3",
		Metric = "SellFullBackpack",
		Target = 3,
		Slot = "Easy",
		TitleKey = "ChallengeSellFull",
		DescKey = "ChallengeSellFullDesc",
		RewardKey = "DailyEasy",
	},
	{
		Id = "PopSpecial_5",
		Metric = "PopSpecial",
		Target = 5,
		Slot = "Easy",
		TitleKey = "ChallengePopSpecial",
		DescKey = "ChallengePopSpecialDesc",
		RewardKey = "DailyEasy",
	},
	{
		Id = "SellValue_500",
		Metric = "SellValue",
		Target = 500,
		Slot = "Easy",
		TitleKey = "ChallengeSellValue",
		DescKey = "ChallengeSellValueDesc",
		RewardKey = "DailyEasy",
	},
} :: { ChallengeDef }

ChallengeConfig.DailyMediumPool = {
	{
		Id = "PopBubbles_200",
		Metric = "PopBubbles",
		Target = 200,
		Slot = "Medium",
		TitleKey = "ChallengePopBubbles",
		DescKey = "ChallengePopBubblesDesc",
		RewardKey = "DailyMedium",
	},
	{
		Id = "SellFull_8",
		Metric = "SellFullBackpack",
		Target = 8,
		Slot = "Medium",
		TitleKey = "ChallengeSellFull",
		DescKey = "ChallengeSellFullDesc",
		RewardKey = "DailyMedium",
	},
	{
		Id = "PopSpecial_20",
		Metric = "PopSpecial",
		Target = 20,
		Slot = "Medium",
		TitleKey = "ChallengePopSpecial",
		DescKey = "ChallengePopSpecialDesc",
		RewardKey = "DailyMedium",
	},
	{
		Id = "MiniEventComplete_2",
		Metric = "MiniEventComplete",
		Target = 2,
		Slot = "Medium",
		TitleKey = "ChallengeMiniEvents",
		DescKey = "ChallengeMiniEventsDesc",
		RewardKey = "DailyMedium",
	},
	{
		Id = "SellValue_2000",
		Metric = "SellValue",
		Target = 2000,
		Slot = "Medium",
		TitleKey = "ChallengeSellValue",
		DescKey = "ChallengeSellValueDesc",
		RewardKey = "DailyMedium",
	},
} :: { ChallengeDef }

ChallengeConfig.DailyEventPool = {
	{
		Id = "FeaturedGolden_15",
		Metric = "PopGoldenWave",
		Target = 15,
		Slot = "Event",
		FeaturedOnly = true,
		TitleKey = "ChallengeGoldenWave",
		DescKey = "ChallengeGoldenWaveDesc",
		RewardKey = "DailyEvent",
	},
	{
		Id = "FeaturedColor_25",
		Metric = "PopColorRush",
		Target = 25,
		Slot = "Event",
		FeaturedOnly = true,
		TitleKey = "ChallengeColorRush",
		DescKey = "ChallengeColorRushDesc",
		RewardKey = "DailyEvent",
	},
	-- Remplace l'ancien challenge "Giant Bubble hits" (spawn mini-événement peu fiable).
	-- Métrique PopSpecial : Rare/Golden/Diamond/Legendary déjà comptés dans ChallengeService.
	{
		Id = "PopSpecial_10",
		Metric = "PopSpecial",
		Target = 10,
		Slot = "Event",
		TitleKey = "ChallengePopSpecial",
		DescKey = "ChallengePopSpecialDesc",
		RewardKey = "DailyEvent",
	},
	{
		Id = "FeaturedParticipate_1",
		Metric = "FeaturedEventJoin",
		Target = 1,
		Slot = "Event",
		TitleKey = "ChallengeFeaturedJoin",
		DescKey = "ChallengeFeaturedJoinDesc",
		RewardKey = "DailyEvent",
	},
	{
		Id = "PopSummer_30",
		Metric = "PopSummer",
		Target = 30,
		Slot = "Event",
		RequiresSummer = true,
		TitleKey = "ChallengePopSummer",
		DescKey = "ChallengePopSummerDesc",
		RewardKey = "DailyEvent",
	},
	{
		Id = "MiniEventJoin_3",
		Metric = "MiniEventJoin",
		Target = 3,
		Slot = "Event",
		TitleKey = "ChallengeMiniEventJoin",
		DescKey = "ChallengeMiniEventJoinDesc",
		RewardKey = "DailyEvent",
	},
} :: { ChallengeDef }

ChallengeConfig.WeeklyPool = {
	{
		Id = "WeeklyPop_1500",
		Metric = "PopBubbles",
		Target = 1500,
		Slot = "Weekly",
		TitleKey = "ChallengeWeeklyPop",
		DescKey = "ChallengeWeeklyPopDesc",
		RewardKey = "Weekly",
	},
	{
		Id = "WeeklySellFull_30",
		Metric = "SellFullBackpack",
		Target = 30,
		Slot = "Weekly",
		TitleKey = "ChallengeWeeklySellFull",
		DescKey = "ChallengeWeeklySellFullDesc",
		RewardKey = "Weekly",
	},
	{
		Id = "WeeklyMiniJoin_12",
		Metric = "MiniEventJoin",
		Target = 12,
		Slot = "Weekly",
		TitleKey = "ChallengeWeeklyMiniJoin",
		DescKey = "ChallengeWeeklyMiniJoinDesc",
		RewardKey = "Weekly",
	},
	-- Remplace WeeklyGiant (dépendait du mini-événement Giant Bubble non fiable).
	{
		Id = "WeeklySpecial_100",
		Metric = "PopSpecial",
		Target = 100,
		Slot = "Weekly",
		TitleKey = "ChallengeWeeklySpecial",
		DescKey = "ChallengeWeeklySpecialDesc",
		RewardKey = "Weekly",
	},
	{
		Id = "WeeklySellValue_25000",
		Metric = "SellValue",
		Target = 25000,
		Slot = "Weekly",
		TitleKey = "ChallengeWeeklySellValue",
		DescKey = "ChallengeWeeklySellValueDesc",
		RewardKey = "Weekly",
	},
} :: { ChallengeDef }

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
function ChallengeConfig.IsStudio(): boolean
	return RunService:IsStudio() and ChallengeConfig.Studio.Enabled == true
end

function ChallengeConfig.ScaleTarget(rawTarget: number): number
	local t = math.max(1, math.floor(rawTarget))
	if ChallengeConfig.IsStudio() then
		if ChallengeConfig.Studio.ForceLowTargets then
			return math.max(1, math.floor(ChallengeConfig.Studio.LowTargetOverride))
		end
		local scale = ChallengeConfig.Studio.TargetScale
		if type(scale) == "number" and scale > 0 and scale ~= 1 then
			t = math.max(1, math.floor(t * scale + 0.5))
		end
	end
	return t
end

function ChallengeConfig.RewardForKey(rewardKey: string): { Type: string, Amount: number }
	local r = ChallengeConfig.Rewards[rewardKey]
	if type(r) ~= "table" then
		return { Type = "SellBonus", Amount = 0 }
	end
	return {
		Type = if type(r.Type) == "string" then r.Type else "SellBonus",
		Amount = math.max(0, math.floor(tonumber(r.Amount) or 0)),
	}
end

function ChallengeConfig.FindDefById(id: string): ChallengeDef?
	local pools = {
		ChallengeConfig.DailyEasyPool,
		ChallengeConfig.DailyMediumPool,
		ChallengeConfig.DailyEventPool,
		ChallengeConfig.WeeklyPool,
	}
	for _, pool in ipairs(pools) do
		for _, def in ipairs(pool) do
			if def.Id == id then
				return def
			end
		end
	end
	return nil
end

function ChallengeConfig.DailyLeaderboardStoreName(dailyKey: string): string
	return ChallengeConfig.DailyLeaderboardStorePrefix .. tostring(dailyKey)
end

return ChallengeConfig
