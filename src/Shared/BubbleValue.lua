--!strict
-- Valeur ajoutée au sac (PendingSellValue) selon le type de bulle et la zone.
-- Source unique pour saut, outils et tout chemin passant par BubbleService.PopCells.

local BubbleTypes = require(script.Parent.BubbleTypes)

local BubbleValue = {}

-- Logs Studio : [BubbleValueDebug] zone=... type=... base=... multiplier=... final=...
-- Temporairement ON pour validation ; passer à false pour désactiver.
BubbleValue.DEBUG_BUBBLE_VALUE = true

-- ClassicZone (planche) = GameRoom (alias palette / UI).
BubbleValue.ZONE_VALUE_MULTIPLIERS = {
	GameRoom = 1,
	ClassicZone = 1,
	SummerZone = 2,
}

function BubbleValue.GetZoneMultiplier(zoneId: string?): number
	if type(zoneId) ~= "string" or zoneId == "" then
		return 1
	end
	local mult = BubbleValue.ZONE_VALUE_MULTIPLIERS[zoneId]
	if type(mult) == "number" and mult == mult and mult > 0 then
		return mult
	end
	return 1
end

function BubbleValue.GetBaseBubbleValue(bubbleTypeId: string?): number
	if type(bubbleTypeId) ~= "string" then
		return 1
	end
	local def = BubbleTypes.ById[bubbleTypeId]
	if not def then
		return 1
	end
	local sell = tonumber(def.SellValue)
	if type(sell) == "number" and sell == sell and sell > 0 then
		return sell
	end
	local coins = tonumber(def.Coins)
	if type(coins) == "number" and coins == coins and coins > 0 then
		return coins
	end
	return 1
end

function BubbleValue.GetBubbleBagValue(bubbleTypeId: string?, zoneId: string?): number
	local baseValue = BubbleValue.GetBaseBubbleValue(bubbleTypeId)
	local multiplier = BubbleValue.GetZoneMultiplier(zoneId)
	return baseValue * multiplier
end

function BubbleValue.DebugLog(zoneId: string?, bubbleTypeId: string?, baseValue: number, multiplier: number, finalValue: number)
	if not BubbleValue.DEBUG_BUBBLE_VALUE then
		return
	end
	print(
		("[BubbleValueDebug] zone=%s type=%s base=%s multiplier=%s final=%s"):format(
			tostring(zoneId or "?"),
			tostring(bubbleTypeId or "?"),
			tostring(baseValue),
			tostring(multiplier),
			tostring(finalValue)
		)
	)
end

return BubbleValue
