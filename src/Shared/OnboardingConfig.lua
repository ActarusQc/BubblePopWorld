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

-- Politique de spawn : le personnage ne doit jamais charger avant le SpawnLocation.
OnboardingConfig.DeferCharacterLoadUntilWorldReady = true
-- Distance horizontale max (studs) au SpawnPad avant repositionnement de secours.
OnboardingConfig.GameRoomSnapMaxDistance = 24
-- Rayon autour de l'origine monde considéré comme spawn parasite.
OnboardingConfig.WorldOriginRejectRadius = 40

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

function OnboardingConfig.HorizontalDistance(ax: number, az: number, bx: number, bz: number): number
	local dx = ax - bx
	local dz = az - bz
	return math.sqrt(dx * dx + dz * dz)
end

-- true si le joueur destiné à la salle n'est pas déjà sur le SpawnPad.
function OnboardingConfig.NeedsGameRoomSnap(horizontalDistance: number, maxDistance: number?): boolean
	local maxD = if type(maxDistance) == "number" then maxDistance else OnboardingConfig.GameRoomSnapMaxDistance
	if type(horizontalDistance) ~= "number" or horizontalDistance ~= horizontalDistance then
		return true
	end
	if horizontalDistance == math.huge then
		return true
	end
	return horizontalDistance > maxD
end

-- true si la position horizontale est encore près de l'origine monde (spawn parasite).
function OnboardingConfig.IsNearWorldOrigin(x: number, z: number, radius: number?): boolean
	local r = if type(radius) == "number" then radius else OnboardingConfig.WorldOriginRejectRadius
	return OnboardingConfig.HorizontalDistance(x, z, 0, 0) < r
end

return OnboardingConfig
