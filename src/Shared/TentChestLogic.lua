--!strict
-- Tirage et placement des coffres payants du chapiteau.

local TentChestConfig = require(script.Parent.TentChestConfig)

local TentChestLogic = {}

export type Placement = {
	Id: string,
	LocalCFrame: CFrame,
}

function TentChestLogic.GetChest(chestId: string): TentChestConfig.ChestDef?
	if type(chestId) ~= "string" then
		return nil
	end
	for _, chest in ipairs(TentChestConfig.Chests) do
		if chest.Id == chestId then
			return chest
		end
	end
	return nil
end

function TentChestLogic.TotalWeight(chest: TentChestConfig.ChestDef): number
	local total = 0
	for _, prize in ipairs(chest.Prizes) do
		total += prize.Weight
	end
	return total
end

function TentChestLogic.RollPrize(chestId: string, roll01: number): number?
	local chest = TentChestLogic.GetChest(chestId)
	if not chest then
		return nil
	end
	local total = TentChestLogic.TotalWeight(chest)
	if total <= 0 then
		return nil
	end
	local t = math.clamp(roll01, 0, 0.999999)
	local pick = t * total
	local acc = 0
	for _, prize in ipairs(chest.Prizes) do
		acc += prize.Weight
		if pick < acc then
			return prize.Coins
		end
	end
	return chest.Prizes[#chest.Prizes].Coins
end

function TentChestLogic.ExpectedValue(chestId: string): number?
	local chest = TentChestLogic.GetChest(chestId)
	if not chest then
		return nil
	end
	local total = TentChestLogic.TotalWeight(chest)
	if total <= 0 then
		return nil
	end
	local sum = 0
	for _, prize in ipairs(chest.Prizes) do
		sum += prize.Coins * prize.Weight
	end
	return sum / total
end

function TentChestLogic.HasWinAndLoss(chestId: string): boolean
	local chest = TentChestLogic.GetChest(chestId)
	if not chest then
		return false
	end
	local sawWin = false
	local sawLoss = false
	for _, prize in ipairs(chest.Prizes) do
		if prize.Coins > chest.Cost then
			sawWin = true
		elseif prize.Coins < chest.Cost then
			sawLoss = true
		end
	end
	return sawWin and sawLoss
end

function TentChestLogic.NetDelta(cost: number, prize: number): number
	return prize - cost
end

function TentChestLogic.IsWin(cost: number, prize: number): boolean
	return prize > cost
end

function TentChestLogic.Placements(radius: number, entranceAngle: number): { Placement }
	local backAngle = entranceAngle + math.pi
	local entranceDir = Vector3.new(math.cos(entranceAngle), 0, math.sin(entranceAngle))
	local dist = math.clamp(
		radius * TentChestConfig.BackRadiusScale,
		TentChestConfig.MinBackDistance,
		TentChestConfig.MaxBackDistance
	)
	local spread = math.rad(TentChestConfig.SpreadDegrees)
	local out = {}
	for i, chest in ipairs(TentChestConfig.Chests) do
		local slot = i - 2
		local angle = backAngle + slot * spread
		local pos = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local origin = pos + Vector3.new(0, TentChestConfig.ChestHeight, 0)
		-- +Z du modèle (serrure) regarde l'entrée.
		local cf = CFrame.lookAt(origin, origin - entranceDir)
		table.insert(out, {
			Id = chest.Id,
			LocalCFrame = cf,
		})
	end
	return out
end

return TentChestLogic
