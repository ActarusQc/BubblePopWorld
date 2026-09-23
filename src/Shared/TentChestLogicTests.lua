--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.TentChestConfig)
local Logic = require(Shared.TentChestLogic)

local TentChestLogicTests = {}

function TentChestLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[TentChestLogicTests] FAIL:", msg)
			ok = false
		end
	end

	check(#Config.Chests == 3, "3 coffres configurés")
	check(Logic.GetChest("Bronze") ~= nil, "Bronze existe")
	check(Logic.GetChest("Silver") ~= nil, "Silver existe")
	check(Logic.GetChest("Gold") ~= nil, "Gold existe")
	check(Logic.GetChest("Unknown") == nil, "id inconnu rejeté")

	for _, chest in ipairs(Config.Chests) do
		check(Logic.HasWinAndLoss(chest.Id), chest.Id .. " a un gain et une perte")
		local ev = Logic.ExpectedValue(chest.Id)
		check(type(ev) == "number" and ev > chest.Cost, chest.Id .. " EV favorable au joueur")
		local totalW = Logic.TotalWeight(chest)
		local lossW, smallW, bigW = 0, 0, 0
		for _, prize in ipairs(chest.Prizes) do
			if prize.Coins < chest.Cost then
				lossW += prize.Weight
			elseif prize.Coins <= chest.Cost * 2.2 then
				smallW += prize.Weight
			else
				bigW += prize.Weight
			end
		end
		check(math.abs(lossW / totalW - 0.10) < 0.02, chest.Id .. " ~10% perte")
		check(math.abs(smallW / totalW - 0.70) < 0.05, chest.Id .. " ~70% petit gain")
		check(math.abs(bigW / totalW - 0.20) < 0.05, chest.Id .. " ~20% gros gain")
		local low = Logic.RollPrize(chest.Id, 0)
		local mid = Logic.RollPrize(chest.Id, 0.5)
		local high = Logic.RollPrize(chest.Id, 0.999)
		check(low == chest.Prizes[1].Coins, chest.Id .. " roll 0 = plus petit lot")
		check(type(mid) == "number" and mid > 0, chest.Id .. " roll milieu valide")
		check(high == chest.Prizes[#chest.Prizes].Coins, chest.Id .. " roll haut = jackpot")
		check(Logic.IsWin(chest.Cost, chest.Cost + 1) == true, chest.Id .. " IsWin")
		check(Logic.NetDelta(chest.Cost, 10) == 10 - chest.Cost, chest.Id .. " NetDelta")
	end

	local placements = Logic.Placements(15.5, -math.pi / 2)
	check(#placements == 3, "3 placements")
	local ids = {}
	local flat = {}
	for _, placement in ipairs(placements) do
		ids[placement.Id] = true
		local pos = placement.LocalCFrame.Position
		check(pos.Y > 1.5, placement.Id .. " au-dessus du sol")
		check(pos.Magnitude < 14, placement.Id .. " dans le rayon")
		table.insert(flat, Vector3.new(pos.X, 0, pos.Z))
	end
	check(ids.Bronze and ids.Silver and ids.Gold, "les 3 ids sont placés")
	for i = 1, #flat do
		for j = i + 1, #flat do
			check((flat[i] - flat[j]).Magnitude >= 8, "coffres espacés d'au moins 8 studs")
		end
	end

	if ok then
		print("[TentChestLogicTests] ALL PASS")
	else
		warn("[TentChestLogicTests] SOME FAILED")
	end
	return ok
end

return TentChestLogicTests
