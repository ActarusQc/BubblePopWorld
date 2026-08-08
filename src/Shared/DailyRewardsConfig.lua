--!strict
-- Configuration du cycle de récompenses de connexion.
-- La frontière d'une journée est UTC et toute l'autorité reste côté serveur.

local DailyRewardsConfig = {}

DailyRewardsConfig.Enabled = true
DailyRewardsConfig.Version = 1
DailyRewardsConfig.CycleLength = 7
DailyRewardsConfig.StateRequestThrottleSeconds = 0.5
DailyRewardsConfig.ClaimCooldownSeconds = 0.75

-- Les boosts temporaires ne sont pas encore un système de gameplay persistant dans
-- Bubble Pop Simulator. On garde donc des Coins pour J1-J6 et un unlock durable J7.
-- La structure RewardType est volontairement extensible pour ajouter de vrais boosts plus tard.
DailyRewardsConfig.Rewards = {
	{
		Day = 1,
		RewardType = "Coins",
		Amount = 250,
		Title = "250 Coins",
		ShortLabel = "+250",
	},
	{
		Day = 2,
		RewardType = "Coins",
		Amount = 400,
		Title = "400 Coins",
		ShortLabel = "+400",
	},
	{
		Day = 3,
		RewardType = "Coins",
		Amount = 650,
		Title = "650 Coins",
		ShortLabel = "+650",
	},
	{
		Day = 4,
		RewardType = "Coins",
		Amount = 900,
		Title = "900 Coins",
		ShortLabel = "+900",
	},
	{
		Day = 5,
		RewardType = "Coins",
		Amount = 1250,
		Title = "1,250 Coins",
		ShortLabel = "+1.25K",
	},
	{
		Day = 6,
		RewardType = "Coins",
		Amount = 1800,
		Title = "1,800 Coins",
		ShortLabel = "+1.8K",
	},
	{
		Day = 7,
		RewardType = "ExclusiveShirt",
		Amount = 2500,
		Title = "Exclusive Shirt + 2,500 Coins",
		ShortLabel = "SHIRT",
		UnlockId = "BubblePopExclusiveShirt",
	},
}

function DailyRewardsConfig.GetReward(day: number): any?
	if type(day) ~= "number" then
		return nil
	end
	day = math.floor(day)
	if day < 1 or day > DailyRewardsConfig.CycleLength then
		return nil
	end
	return DailyRewardsConfig.Rewards[day]
end

function DailyRewardsConfig.PublicRewards(): { any }
	local out = {}
	for _, reward in ipairs(DailyRewardsConfig.Rewards) do
		table.insert(out, {
			Day = reward.Day,
			RewardType = reward.RewardType,
			Amount = reward.Amount,
			Title = reward.Title,
			ShortLabel = reward.ShortLabel,
			UnlockId = reward.UnlockId,
		})
	end
	return out
end

return DailyRewardsConfig
