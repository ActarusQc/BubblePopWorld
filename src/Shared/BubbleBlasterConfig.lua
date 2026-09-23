--!strict
-- Palier de récompenses du kiosque Bubble Blaster.

export type Tier = {
	MinScore: number,
	Name: string,
	Coins: number,
	Color: Color3,
}

local BubbleBlasterConfig = {
	Duration = 30,
	ReplayCooldown = 8,
	GoldenChance = 0.12,
	GoldenPoints = 2,
	NormalPoints = 1,
	AbandonMaxCoins = 75,
	Tiers = {
		{ MinScore = 28, Name = "PERFECT", Coins = 1200, Color = Color3.fromRGB(255, 207, 61) },
		{ MinScore = 22, Name = "GOLD", Coins = 700, Color = Color3.fromRGB(255, 190, 38) },
		{ MinScore = 15, Name = "SILVER", Coins = 350, Color = Color3.fromRGB(205, 225, 245) },
		{ MinScore = 8, Name = "BRONZE", Coins = 175, Color = Color3.fromRGB(226, 143, 79) },
		{ MinScore = 0, Name = "PARTICIPATION", Coins = 75, Color = Color3.fromRGB(90, 220, 245) },
	} :: { Tier },
}

function BubbleBlasterConfig.ResultFor(score: number): (string, number, Color3)
	local value = math.max(0, math.floor(score))
	for _, tier in ipairs(BubbleBlasterConfig.Tiers) do
		if value >= tier.MinScore then
			return tier.Name, tier.Coins, tier.Color
		end
	end
	local last = BubbleBlasterConfig.Tiers[#BubbleBlasterConfig.Tiers]
	return last.Name, last.Coins, last.Color
end

function BubbleBlasterConfig.PrizeRows(): { Tier }
	local rows = {}
	for i = #BubbleBlasterConfig.Tiers, 1, -1 do
		table.insert(rows, BubbleBlasterConfig.Tiers[i])
	end
	return rows
end

return BubbleBlasterConfig
