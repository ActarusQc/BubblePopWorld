--!strict
-- Planification de l'apparition des objets : zone → cellules éligibles → objet.
-- Module pur (aucun service Roblox) partagé par DropService et les tests.

local GameConfig = require(script.Parent.GameConfig)
local ToolDefs = require(script.Parent.ToolDefs)

export type CellQuery = {
	SizeX: number,
	SizeZ: number,
	IsAlive: (number, number) -> boolean,
}

export type SpawnPlan = {
	ZoneId: string,
	ItemId: string,
	ItemName: string,
	X: number,
	Z: number,
	EligibleCount: number,
}

local ItemSpawnPlanner = {}

-- Hauteur de l'objet au-dessus du centre de la cellule (bulle ~1.35 studs de haut).
ItemSpawnPlanner.SpawnHeightOffset = 4

function ItemSpawnPlanner.IsDebug(): boolean
	return GameConfig.Drops.ItemSpawnDebug == true
end

function ItemSpawnPlanner.MaxActivePerZone(): number
	return GameConfig.Drops.MaxActivePerZone or 2
end

function ItemSpawnPlanner.Log(fmt: string, ...: any)
	if ItemSpawnPlanner.IsDebug() then
		print("[ItemSpawnDebug] " .. string.format(fmt, ...))
	end
end

function ItemSpawnPlanner.LogFailure(zoneId: string, reason: string)
	if ItemSpawnPlanner.IsDebug() then
		warn(("[ItemSpawnDebug] %s spawn failed: %s"):format(zoneId, reason))
	end
end

local function nextNumber(rng: Random?, a: number, b: number): number
	if rng then
		return rng:NextNumber(a, b)
	end
	return a + math.random() * (b - a)
end

-- Délai avant la prochaine tentative d'une zone donnée.
function ItemSpawnPlanner.NextDelay(activeZoneCount: number, rng: Random?): number
	local D = GameConfig.Drops
	if ItemSpawnPlanner.IsDebug() then
		return nextNumber(rng, D.DebugMinInterval, D.DebugMaxInterval)
	end
	return nextNumber(rng, D.MinInterval, D.MaxInterval) * math.max(1, activeZoneCount)
end

-- Cellules de la planche réellement utilisables : dans la grille de la zone,
-- hors pourtour, et portant une bulle vivante (jamais lobby / pont / hors grille).
function ItemSpawnPlanner.CollectEligibleCells(query: CellQuery): { { number } }
	local margin = GameConfig.Drops.EdgeMargin or 0
	local minX, maxX = 1 + margin, query.SizeX - margin
	local minZ, maxZ = 1 + margin, query.SizeZ - margin
	if maxX < minX or maxZ < minZ then
		minX, maxX, minZ, maxZ = 1, query.SizeX, 1, query.SizeZ
	end

	local cells: { { number } } = {}
	for x = minX, maxX do
		for z = minZ, maxZ do
			if query.IsAlive(x, z) then
				table.insert(cells, { x, z })
			end
		end
	end
	return cells
end

function ItemSpawnPlanner.Plan(zoneId: string, query: CellQuery, rng: Random?): (SpawnPlan?, string?)
	ItemSpawnPlanner.Log("Zone selected: %s", zoneId)

	if not ToolDefs.GetZonePool(zoneId) then
		return nil, "no item pool configured"
	end

	local cells = ItemSpawnPlanner.CollectEligibleCells(query)
	ItemSpawnPlanner.Log("Eligible cells in %s: %d", zoneId, #cells)
	if #cells == 0 then
		return nil, "no eligible cells"
	end

	local index = if rng then rng:NextInteger(1, #cells) else math.random(1, #cells)
	local cell = cells[index]

	local itemId, def = ToolDefs.RollForZone(zoneId, rng)
	if not def then
		return nil, "unknown item id " .. tostring(itemId)
	end
	ItemSpawnPlanner.Log("Selected item: %s", def.Name)

	return {
		ZoneId = zoneId,
		ItemId = itemId,
		ItemName = def.Name,
		X = cell[1],
		Z = cell[2],
		EligibleCount = #cells,
	}, nil
end

return ItemSpawnPlanner
