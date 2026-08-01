--!strict
-- Machine à états d'onboarding : fonction pure, sans dépendance Roblox.

local OnboardingConfig = {}

OnboardingConfig.AttributeName = "OnboardingObjective"

OnboardingConfig.Objective = {
	None = "",
	Pop = "Pop",
	Sell = "Sell",
	Shop = "Shop",
}

export type Snapshot = {
	OnboardingStarted: boolean?,
	OnboardingCompleted: boolean?,
	PoppedFirstBubble: boolean?,
	SoldFirstBackpack: boolean?,
	PurchasedFirstUpgrade: boolean?,
	CurrentBubbles: number?,
	BackpackCapacity: number?,
	Coins: number?,
	CheapestUpgradeCost: number?,
}

OnboardingConfig.Guide = {
	ArrowEdgeMarginRatio = 0.12,
	ArrowEdgeMarginMinPx = 48,
	TouchBottomSafeRatio = 0.22,
	BillboardStudsOffset = 8,
	BillboardMaxDistance = 0,
	UpdateWhileIdle = false,
}

local function boolOf(value: any): boolean
	return value == true
end

local function numberOf(value: any, fallback: number): number
	if type(value) ~= "number" then
		return fallback
	end
	if value ~= value then
		return fallback
	end
	if value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

function OnboardingConfig.ResolveObjective(snapshot: Snapshot?): string
	local O = OnboardingConfig.Objective
	if type(snapshot) ~= "table" then
		return O.None
	end

	if not boolOf(snapshot.OnboardingStarted) then
		return O.None
	end
	if boolOf(snapshot.OnboardingCompleted) then
		return O.None
	end
	if boolOf(snapshot.PurchasedFirstUpgrade) then
		return O.None
	end

	if not boolOf(snapshot.PoppedFirstBubble) then
		return O.Pop
	end

	if not boolOf(snapshot.SoldFirstBackpack) then
		local capacity = numberOf(snapshot.BackpackCapacity, 0)
		local current = numberOf(snapshot.CurrentBubbles, 0)
		if capacity > 0 and current >= capacity then
			return O.Sell
		end
		return O.None
	end

	local cost = numberOf(snapshot.CheapestUpgradeCost, -1)
	local coins = numberOf(snapshot.Coins, 0)
	if cost > 0 and coins >= cost then
		return O.Shop
	end
	return O.None
end

function OnboardingConfig.ShouldSpawnInGameRoom(snapshot: Snapshot?): boolean
	return OnboardingConfig.ResolveObjective(snapshot) == OnboardingConfig.Objective.Pop
end

return OnboardingConfig
