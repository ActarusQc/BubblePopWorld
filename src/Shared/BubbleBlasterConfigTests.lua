--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.BubbleBlasterConfig)

local BubbleBlasterConfigTests = {}

function BubbleBlasterConfigTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[BubbleBlasterConfigTests] FAIL:", msg)
			ok = false
		end
	end

	local name, coins = Config.ResultFor(0)
	check(name == "PARTICIPATION" and coins == 75, "0 point = participation 75")
	name, coins = Config.ResultFor(7)
	check(name == "PARTICIPATION" and coins == 75, "7 points = participation")
	name, coins = Config.ResultFor(8)
	check(name == "BRONZE" and coins == 175, "8 points = bronze 175")
	name, coins = Config.ResultFor(15)
	check(name == "SILVER" and coins == 350, "15 points = silver 350")
	name, coins = Config.ResultFor(22)
	check(name == "GOLD" and coins == 700, "22 points = gold 700")
	name, coins = Config.ResultFor(28)
	check(name == "PERFECT" and coins == 1200, "28 points = perfect 1200")

	local rows = Config.PrizeRows()
	check(#rows == 5, "5 paliers affichés")
	check(rows[1].Name == "PARTICIPATION" and rows[#rows].Name == "PERFECT", "affichage du plus bas au plus haut")

	if ok then
		print("[BubbleBlasterConfigTests] ALL PASS")
	else
		warn("[BubbleBlasterConfigTests] SOME FAILED")
	end
	return ok
end

return BubbleBlasterConfigTests
