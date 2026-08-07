--!strict
-- Logique pure des mini-événements (testable hors services Roblox).

local MiniEventConfig = require(script.Parent.MiniEventConfig)

local MiniEventLogic = {}

MiniEventLogic.STATES = table.freeze({
	Idle = "Idle",
	Countdown = "Countdown",
	Active = "Active",
	Cleanup = "Cleanup",
	Cooldown = "Cooldown",
})

MiniEventLogic.EVENT_TYPES = table.freeze({
	"GoldenWave",
	"ColorRush",
	"GiantBubble",
})

MiniEventLogic.NETWORK_STATES = table.freeze({
	Countdown = "Countdown",
	Active = "Active",
	Ended = "Ended",
})

export type SchedulerState = string

function MiniEventLogic.IsValidEventType(eventType: string): boolean
	for _, id in ipairs(MiniEventLogic.EVENT_TYPES) do
		if id == eventType then
			return true
		end
	end
	return false
end

function MiniEventLogic.IsValidSchedulerState(state: string): boolean
	for _, s in pairs(MiniEventLogic.STATES) do
		if s == state then
			return true
		end
	end
	return false
end

-- Transition autorisée : Idle→Countdown→Active→Cleanup→Cooldown→Idle
local ALLOWED: { [string]: { [string]: boolean } } = {
	Idle = { Countdown = true },
	Countdown = { Active = true, Cleanup = true, Idle = true },
	Active = { Cleanup = true },
	Cleanup = { Cooldown = true, Idle = true },
	Cooldown = { Idle = true },
}

function MiniEventLogic.CanTransition(fromState: string, toState: string): boolean
	local row = ALLOWED[fromState]
	return row ~= nil and row[toState] == true
end

function MiniEventLogic.PickNextEvent(
	enabledTypes: { string },
	lastEventType: string?,
	rng: Random?,
	featuredEventType: string?,
	featuredWeightMultiplier: number?
): string?
	local candidates = {}
	for _, id in ipairs(enabledTypes) do
		if MiniEventLogic.IsValidEventType(id) and MiniEventConfig.IsEventEnabled(id) then
			if lastEventType == nil or id ~= lastEventType or #enabledTypes <= 1 then
				table.insert(candidates, id)
			end
		end
	end
	-- Si filtrage last a tout exclu et plusieurs types existent, retenter sans last.
	if #candidates == 0 then
		for _, id in ipairs(enabledTypes) do
			if MiniEventLogic.IsValidEventType(id) and MiniEventConfig.IsEventEnabled(id) then
				table.insert(candidates, id)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	-- Préférer éviter le last même si seul candidat restante = ok
	if lastEventType and #candidates > 1 then
		local filtered = {}
		for _, id in ipairs(candidates) do
			if id ~= lastEventType then
				table.insert(filtered, id)
			end
		end
		if #filtered > 0 then
			candidates = filtered
		end
	end

	-- Pondération optionnelle de l'événement vedette du jour (ne force jamais 100 %).
	local weightMult = tonumber(featuredWeightMultiplier)
		or MiniEventConfig.FeaturedEventWeightMultiplier
		or 1
	if type(weightMult) ~= "number" or weightMult < 1 then
		weightMult = 1
	end
	weightMult = math.floor(weightMult)

	local weighted: { string } = {}
	for _, id in ipairs(candidates) do
		local n = if featuredEventType and id == featuredEventType then weightMult else 1
		for _ = 1, n do
			table.insert(weighted, id)
		end
	end
	if #weighted == 0 then
		return nil
	end
	local index = if rng then rng:NextInteger(1, #weighted) else math.random(1, #weighted)
	return weighted[index]
end

function MiniEventLogic.RandomInterval(minSeconds: number, maxSeconds: number, rng: Random?): number
	local lo = math.min(minSeconds, maxSeconds)
	local hi = math.max(minSeconds, maxSeconds)
	if rng then
		return rng:NextNumber(lo, hi)
	end
	return lo + math.random() * (hi - lo)
end

function MiniEventLogic.CanStartScheduler(enabled: boolean, playerCount: number, minPlayers: number, playersInBubbleZones: number): boolean
	if not enabled then
		return false
	end
	if playerCount < minPlayers then
		return false
	end
	return playersInBubbleZones >= 1
end

function MiniEventLogic.IsNormalEligibleForGolden(rarityId: string?, isAlive: boolean?, alreadyEventVariant: string?): boolean
	if rarityId ~= "Normal" then
		return false
	end
	if isAlive ~= true then
		return false
	end
	if alreadyEventVariant ~= nil and alreadyEventVariant ~= "" then
		return false
	end
	return true
end

function MiniEventLogic.SelectTransformIndices(eligibleCount: number, ratio: number, rng: Random?): { number }
	local count = math.clamp(math.floor(eligibleCount * ratio + 0.5), 0, eligibleCount)
	if count <= 0 or eligibleCount <= 0 then
		return {}
	end
	local pool = {}
	for i = 1, eligibleCount do
		pool[i] = i
	end
	-- Fisher-Yates partial
	for i = eligibleCount, 2, -1 do
		local j = if rng then rng:NextInteger(1, i) else math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local picked = {}
	for i = 1, count do
		picked[i] = pool[i]
	end
	table.sort(picked)
	return picked
end

function MiniEventLogic.ShouldBecomeGoldenOnRegen(chance: number, rng: Random?): boolean
	local roll = if rng then rng:NextNumber() else math.random()
	return roll < math.clamp(chance, 0, 1)
end

function MiniEventLogic.GetPopSellMultiplier(
	eventType: string?,
	active: boolean,
	rarityId: string?,
	eventVariant: string?,
	isColorMatch: boolean?
): number
	if not active or eventType == nil then
		return 1
	end
	if eventType == "GoldenWave" then
		if eventVariant == "GoldenWave" and rarityId == "Normal" then
			return MiniEventConfig.Events.GoldenWave.SellMultiplier
		end
		return 1
	end
	if eventType == "ColorRush" then
		if rarityId == "Normal" and isColorMatch == true then
			return MiniEventConfig.Events.ColorRush.SellMultiplier
		end
		return 1
	end
	return 1
end

function MiniEventLogic.ColorDistance(a: Color3, b: Color3): number
	local dr = a.R - b.R
	local dg = a.G - b.G
	local db = a.B - b.B
	return math.sqrt(dr * dr + dg * dg + db * db)
end

function MiniEventLogic.ColorsMatch(a: Color3, b: Color3, maxDistance: number): boolean
	return MiniEventLogic.ColorDistance(a, b) <= maxDistance
end

-- colors : liste de Color3 observés sur bulles normales vivantes.
-- reserved : couleurs à exclure (spéciales).
function MiniEventLogic.PickTargetColor(
	observed: { Color3 },
	reserved: { Color3 }?,
	minDistanceFromReserved: number?,
	rng: Random?
): Color3?
	if #observed == 0 then
		return nil
	end
	local minDist = minDistanceFromReserved or 0.3
	local buckets: { { color: Color3, count: number } } = {}

	local function isReserved(c: Color3): boolean
		if not reserved then
			return false
		end
		for _, r in ipairs(reserved) do
			if MiniEventLogic.ColorDistance(c, r) < minDist then
				return true
			end
		end
		return false
	end

	for _, c in ipairs(observed) do
		if not isReserved(c) then
			local found = false
			for _, b in ipairs(buckets) do
				if MiniEventLogic.ColorDistance(b.color, c) < 0.12 then
					b.count += 1
					found = true
					break
				end
			end
			if not found then
				table.insert(buckets, { color = c, count = 1 })
			end
		end
	end
	if #buckets == 0 then
		return nil
	end
	table.sort(buckets, function(a, b)
		return a.count > b.count
	end)
	-- Parmi les buckets top, aléatoire pondéré par count.
	local total = 0
	for _, b in ipairs(buckets) do
		total += b.count
	end
	local roll = if rng then rng:NextNumber(0, total) else math.random() * total
	local acc = 0
	for _, b in ipairs(buckets) do
		acc += b.count
		if roll <= acc then
			return b.color
		end
	end
	return buckets[1].color
end

function MiniEventLogic.ComputeRequiredHits(baseHits: number, hitsPerPlayer: number, playerCount: number): number
	local n = math.max(0, math.floor(playerCount))
	return math.max(1, math.floor(baseHits + hitsPerPlayer * n))
end

function MiniEventLogic.ContributionForTool(toolId: string?, contributionMap: { [string]: number }?): number
	local map = contributionMap or MiniEventConfig.Events.GiantBubble.ContributionByTool
	local id = toolId or "Jump"
	local pts = map[id]
	if type(pts) == "number" and pts > 0 then
		return math.floor(pts)
	end
	return 1
end

function MiniEventLogic.CrossedMilestones(previousRatio: number, newRatio: number, milestones: { number }): { number }
	local crossed = {}
	for _, m in ipairs(milestones) do
		if previousRatio < m and newRatio >= m then
			table.insert(crossed, m)
		end
	end
	return crossed
end

function MiniEventLogic.ComputeSellBonus(
	contribution: number,
	requiredHits: number,
	minContribution: number,
	baseBonus: number,
	perHit: number,
	completionBonus: number,
	succeeded: boolean
): number
	if contribution < minContribution then
		return 0
	end
	if not succeeded then
		return 0
	end
	local ratio = if requiredHits > 0 then math.clamp(contribution / requiredHits, 0, 1) else 0
	local bonus = baseBonus + contribution * perHit + ratio * completionBonus
	return math.max(0, math.floor(bonus + 0.5))
end

function MiniEventLogic.SerializeColor(c: Color3): { number }
	return {
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5),
	}
end

function MiniEventLogic.DeserializeColor(t: any): Color3?
	if type(t) ~= "table" then
		return nil
	end
	local r, g, b = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
	if not r or not g or not b then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

function MiniEventLogic.BuildNetworkPayload(
	state: string, -- Countdown | Active | Ended
	eventType: string,
	startTime: number,
	endTime: number,
	zoneIds: { string },
	objective: any?,
	progress: any?,
	outcome: string?, -- Complete | Failed | nil
	rewardHint: any?
): { [string]: any }
	return {
		state = state,
		eventType = eventType,
		startTime = startTime,
		endTime = endTime,
		zoneIds = zoneIds,
		objective = objective,
		progress = progress,
		outcome = outcome,
		rewardHint = rewardHint,
	}
end

-- Coins bonus attribuables à l'événement (serveur uniquement).
function MiniEventLogic.ComputeEventBonusCoins(sellWithMult: number, sellWithoutMult: number): number
	local withM = math.floor(tonumber(sellWithMult) or 0)
	local without = math.floor(tonumber(sellWithoutMult) or 0)
	return math.max(0, withM - without)
end

function MiniEventLogic.HasPassCondition(eventType: string): boolean
	return eventType == "GiantBubble"
end

export type UiFields = {
	displayName: string,
	objectiveText: string,
	progressCurrent: number?,
	progressTarget: number?,
	bonusCoins: number?,
	hasPassCondition: boolean,
	completed: boolean?,
}

-- Enrichit un payload réseau avec les champs UI standardisés (affichage client).
function MiniEventLogic.EnrichPayloadForUi(payload: { [string]: any }, ui: UiFields): { [string]: any }
	payload.displayName = ui.displayName
	payload.objectiveText = ui.objectiveText
	payload.progressCurrent = ui.progressCurrent
	payload.progressTarget = ui.progressTarget
	payload.bonusCoins = if ui.bonusCoins ~= nil then math.max(0, math.floor(ui.bonusCoins)) else nil
	payload.hasPassCondition = ui.hasPassCondition == true
	payload.completed = ui.completed
	return payload
end

return MiniEventLogic
