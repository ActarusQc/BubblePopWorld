--!strict
-- Valeurs de sac par zone : principale inchangée, SummerZone ×2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BubbleTypes = require(Shared.BubbleTypes)
local BubbleValue = require(Shared.BubbleValue)

local BubbleValueTests = {}

function BubbleValueTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[BubbleValueTests] FAIL:", msg)
			ok = false
		end
	end

	local function base(id: string): number
		return BubbleValue.GetBaseBubbleValue(id)
	end

	check(base("Normal") == 1, "Normal base = 1")
	check(base("Rare") == BubbleTypes.ById.Rare.SellValue, "Rare base = SellValue")
	check(base("Golden") == BubbleTypes.ById.Golden.SellValue, "Golden base = SellValue")
	check(base("Diamond") == BubbleTypes.ById.Diamond.SellValue, "Diamond base = SellValue")
	check(base("Legendary") == BubbleTypes.ById.Legendary.SellValue, "Legendary base = SellValue")

	-- Zone principale (ClassicZone / GameRoom)
	check(BubbleValue.GetBubbleBagValue("Normal", "ClassicZone") == base("Normal"), "Normal + GameRoom/Classic = base")
	check(BubbleValue.GetBubbleBagValue("Normal", "GameRoom") == base("Normal"), "Normal + GameRoom = base")
	check(BubbleValue.GetBubbleBagValue("Rare", "ClassicZone") == base("Rare"), "Rare + Classic = base")
	check(BubbleValue.GetBubbleBagValue("Golden", "GameRoom") == base("Golden"), "Gold + GameRoom = base")
	check(BubbleValue.GetBubbleBagValue("Diamond", "ClassicZone") == base("Diamond"), "Diamond + Classic = base")
	check(BubbleValue.GetBubbleBagValue("Legendary", "ClassicZone") == base("Legendary"), "Legendary + Classic = base")

	-- SummerZone = ×2
	check(BubbleValue.GetBubbleBagValue("Normal", "SummerZone") == base("Normal") * 2, "Normal + SummerZone = base × 2")
	check(BubbleValue.GetBubbleBagValue("Rare", "SummerZone") == base("Rare") * 2, "Rare + SummerZone = Rare × 2")
	check(BubbleValue.GetBubbleBagValue("Golden", "SummerZone") == base("Golden") * 2, "Gold + SummerZone = Gold × 2")
	check(BubbleValue.GetBubbleBagValue("Diamond", "SummerZone") == base("Diamond") * 2, "Diamond + SummerZone = Diamond × 2")
	check(BubbleValue.GetBubbleBagValue("Legendary", "SummerZone") == base("Legendary") * 2, "Legendary + SummerZone = Legendary × 2")

	-- Zone inconnue = multiplicateur 1
	check(BubbleValue.GetZoneMultiplier("UnknownZone") == 1, "zone inconnue multiplier = 1")
	check(BubbleValue.GetBubbleBagValue("Normal", "UnknownZone") == base("Normal"), "zone inconnue = base")
	check(BubbleValue.GetZoneMultiplier(nil) == 1, "nil zone multiplier = 1")

	-- RewardMultiplier reste distinct (pas de double application ici)
	check(BubbleValue.ZONE_VALUE_MULTIPLIERS.SummerZone == 2, "Summer bag mult config = 2")
	check(BubbleValue.ZONE_VALUE_MULTIPLIERS.ClassicZone == 1, "Classic bag mult config = 1")

	if ok then
		print("[BubbleValueTests] OK")
	end
	return ok
end

return BubbleValueTests
