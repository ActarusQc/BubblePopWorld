--!strict
-- Palier de récompenses et physique du kiosque Roll-A-Ball.

export type Tier = {
	MinScore: number,
	Name: string,
	Coins: number,
	Color: Color3,
}

export type PowerBand = {
	Max: number,
	Points: number,
}

local RollABallConfig = {
	BallsPerGame = 5,
	ReplayCooldown = 8,
	RollCooldown = 0.85,
	AbandonMaxCoins = 75,
	PrizePetId = "ToutouChien",
	PrizePetName = "TOUTOU CHIEN",
	PrizePetMinScore = 180,
	JitterAmplitude = 0.035,
	PowerSweepSpeed = 4.4,
	PowerSweepWobble = 2.6,
	PowerSweepWobbleRate = 1.55,
	PowerSweepWobble2 = 1.35,
	PowerSweepWobbleRate2 = 2.35,
	Rings = { 10, 20, 30, 40, 50 },
	PowerBands = {
		{ Max = 0.14, Points = 10 },
		{ Max = 0.28, Points = 20 },
		{ Max = 0.42, Points = 30 },
		{ Max = 0.56, Points = 40 },
		{ Max = 0.68, Points = 50 },
		{ Max = 0.80, Points = 40 },
		{ Max = 0.90, Points = 20 },
		{ Max = 1.00, Points = 10 },
	} :: { PowerBand },
	Tiers = {
		{ MinScore = 180, Name = "PERFECT", Coins = 1200, Color = Color3.fromRGB(255, 207, 61) },
		{ MinScore = 140, Name = "GOLD", Coins = 700, Color = Color3.fromRGB(255, 190, 38) },
		{ MinScore = 90, Name = "SILVER", Coins = 350, Color = Color3.fromRGB(205, 225, 245) },
		{ MinScore = 50, Name = "BRONZE", Coins = 175, Color = Color3.fromRGB(226, 143, 79) },
		{ MinScore = 0, Name = "PARTICIPATION", Coins = 75, Color = Color3.fromRGB(90, 220, 245) },
	} :: { Tier },
}

function RollABallConfig.ResultFor(score: number): (string, number, Color3)
	local value = math.max(0, math.floor(score))
	for _, tier in ipairs(RollABallConfig.Tiers) do
		if value >= tier.MinScore then
			return tier.Name, tier.Coins, tier.Color
		end
	end
	local last = RollABallConfig.Tiers[#RollABallConfig.Tiers]
	return last.Name, last.Coins, last.Color
end

function RollABallConfig.PrizeRows(): { Tier }
	local rows = {}
	for i = #RollABallConfig.Tiers, 1, -1 do
		table.insert(rows, RollABallConfig.Tiers[i])
	end
	return rows
end

function RollABallConfig.PowerAt(elapsed: number, phase: number): number
	local t = math.max(0, elapsed)
	local omega0 = RollABallConfig.PowerSweepSpeed
	local a1 = RollABallConfig.PowerSweepWobble
	local o1 = RollABallConfig.PowerSweepWobbleRate
	local a2 = RollABallConfig.PowerSweepWobble2
	local o2 = RollABallConfig.PowerSweepWobbleRate2
	local angle = omega0 * t + phase
	if o1 > 0.001 then
		angle -= (a1 / o1) * math.cos(o1 * t)
	end
	if o2 > 0.001 then
		angle -= (a2 / o2) * math.cos(o2 * t + phase)
	end
	return (math.sin(angle) + 1) * 0.5
end

function RollABallConfig.ScoreForPower(power: number, jitter: number?): number
	local p = math.clamp((power or 0) + (jitter or 0), 0, 1)
	for _, band in ipairs(RollABallConfig.PowerBands) do
		if p <= band.Max then
			return band.Points
		end
	end
	return 10
end

function RollABallConfig.WinsPrizePet(score: number): boolean
	return math.max(0, math.floor(score)) >= RollABallConfig.PrizePetMinScore
end

return RollABallConfig
