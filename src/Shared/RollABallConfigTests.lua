--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.RollABallConfig)

local RollABallConfigTests = {}

function RollABallConfigTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[RollABallConfigTests] FAIL:", msg)
			ok = false
		end
	end

	local name, coins = Config.ResultFor(0)
	check(name == "PARTICIPATION" and coins == 75, "0 point = participation 75")
	name, coins = Config.ResultFor(49)
	check(name == "PARTICIPATION" and coins == 75, "49 points = participation")
	name, coins = Config.ResultFor(50)
	check(name == "BRONZE" and coins == 175, "50 points = bronze 175")
	name, coins = Config.ResultFor(90)
	check(name == "SILVER" and coins == 350, "90 points = silver 350")
	name, coins = Config.ResultFor(140)
	check(name == "GOLD" and coins == 700, "140 points = gold 700")
	name, coins = Config.ResultFor(180)
	check(name == "PERFECT" and coins == 1200, "180 points = perfect 1200")
	name, coins = Config.ResultFor(250)
	check(name == "PERFECT" and coins == 1200, "score max reste perfect")

	local rows = Config.PrizeRows()
	check(#rows == 5, "5 paliers affichés")
	check(rows[1].Name == "PARTICIPATION" and rows[#rows].Name == "PERFECT", "affichage du plus bas au plus haut")

	check(Config.ScoreForPower(0.00, 0) == 10, "puissance basse = 10")
	check(Config.ScoreForPower(0.20, 0) == 20, "bande 20")
	check(Config.ScoreForPower(0.35, 0) == 30, "bande 30")
	check(Config.ScoreForPower(0.50, 0) == 40, "bande 40")
	check(Config.ScoreForPower(0.62, 0) == 50, "sweet spot = 50")
	check(Config.ScoreForPower(0.74, 0) == 40, "après 50 = 40")
	check(Config.ScoreForPower(0.85, 0) == 20, "trop fort = 20")
	check(Config.ScoreForPower(0.96, 0) == 10, "overshoot = 10")
	check(Config.ScoreForPower(1.4, 0) == 10, "puissance clampée")
	check(Config.ScoreForPower(0.62, 0.10) == 40, "jitter peut quitter le 50")
	local p0 = Config.PowerAt(0, 0)
	local p1 = Config.PowerAt(0.4, 0)
	local p2 = Config.PowerAt(1.1, 0)
	check(p0 >= 0 and p0 <= 1, "PowerAt borné à 0")
	check(p1 >= 0 and p1 <= 1 and p2 >= 0 and p2 <= 1, "PowerAt borné dans le temps")
	check(Config.PowerAt(0.8, 1.2) == Config.PowerAt(0.8, 1.2), "PowerAt déterministe")
	check(math.abs(p1 - p0) > 0.01 or math.abs(p2 - p0) > 0.01, "le curseur bouge")
	local maxDelta = 0
	local minDelta = 1
	for i = 0, 24 do
		local t = i * 0.07
		local delta = math.abs(Config.PowerAt(t + 0.05, 0.4) - Config.PowerAt(t, 0.4))
		if delta > maxDelta then maxDelta = delta end
		if delta < minDelta then minDelta = delta end
	end
	check(maxDelta > minDelta * 1.6, "la vitesse du curseur n'est pas constante")
	check(Config.BallsPerGame == 5, "5 balles par partie")
	check(Config.BallsPerGame * 50 >= Config.Tiers[1].MinScore, "perfect atteignable")
	check(not Config.WinsPrizePet(179), "179 points ne gagne pas le toutou")
	check(Config.WinsPrizePet(180), "180 points gagne le toutou")

	if ok then
		print("[RollABallConfigTests] ALL PASS")
	else
		warn("[RollABallConfigTests] SOME FAILED")
	end
	return ok
end

return RollABallConfigTests
