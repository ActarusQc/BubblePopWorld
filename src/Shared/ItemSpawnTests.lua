--!strict
-- Validations du planificateur d'apparition des objets (multi-zones).
-- Simule les planches GameRoom (ClassicZone) et SummerZone hors Roblox.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local ZoneDefs = require(Shared.ZoneDefs)
local ToolDefs = require(Shared.ToolDefs)
local ItemSpawnPlanner = require(Shared.ItemSpawnPlanner)

local ItemSpawnTests = {}

local function makeQuery(sizeX: number, sizeZ: number, dead: { [string]: boolean }?)
	return {
		SizeX = sizeX,
		SizeZ = sizeZ,
		IsAlive = function(x: number, z: number): boolean
			if dead and dead[x .. ":" .. z] then
				return false
			end
			return true
		end,
	}
end

function ItemSpawnTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[ItemSpawnTests] FAIL:", msg)
			ok = false
		end
	end

	local D = GameConfig.Drops
	local margin = D.EdgeMargin

	check(D.ItemSpawnDebug == false, "ItemSpawnDebug désactivé par défaut")
	check(D.MaxActivePerZone >= 1, "MaxActivePerZone >= 1")
	check(D.DebugMinInterval >= 5 and D.DebugMaxInterval <= 20, "intervalle debug 5..20 s")

	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local classicQuery = makeQuery(classic.SizeX, classic.SizeZ)
	local summerQuery = makeQuery(summer.SizeX, summer.SizeZ)

	-- Cellules éligibles : la grille complète moins le pourtour.
	local classicCells = ItemSpawnPlanner.CollectEligibleCells(classicQuery)
	local summerCells = ItemSpawnPlanner.CollectEligibleCells(summerQuery)
	local expectedClassic = (classic.SizeX - margin * 2) * (classic.SizeZ - margin * 2)
	local expectedSummer = (summer.SizeX - margin * 2) * (summer.SizeZ - margin * 2)
	check(#classicCells == expectedClassic, "cellules éligibles GameRoom")
	check(#summerCells == expectedSummer, "cellules éligibles SummerZone")
	check(#summerCells > 0, "SummerZone a des cellules éligibles")

	-- Les bulles éclatées sont exclues.
	local dead = {}
	for z = 1 + margin, summer.SizeZ - margin do
		dead["5:" .. z] = true
	end
	local partial = ItemSpawnPlanner.CollectEligibleCells(makeQuery(summer.SizeX, summer.SizeZ, dead))
	check(#partial == expectedSummer - (summer.SizeZ - margin * 2), "bulles éclatées exclues")

	-- Plans réels : cellule valide + objet issu du pool de la zone.
	local rng = Random.new(7)
	local zoneQueries = {
		{ Id = "ClassicZone", Query = classicQuery, Def = classic },
		{ Id = "SummerZone", Query = summerQuery, Def = summer },
	}
	local seenPowerfulSummer = false
	for _, entry in ipairs(zoneQueries) do
		local spawned = 0
		for _ = 1, 60 do
			local plan, reason = ItemSpawnPlanner.Plan(entry.Id, entry.Query, rng)
			if not plan then
				check(false, ("plan %s échoué: %s"):format(entry.Id, tostring(reason)))
				break
			end
			spawned += 1
			check(plan.X >= 1 + margin and plan.X <= entry.Def.SizeX - margin, "cellule X dans la planche " .. entry.Id)
			check(plan.Z >= 1 + margin and plan.Z <= entry.Def.SizeZ - margin, "cellule Z dans la planche " .. entry.Id)
			check(entry.Query.IsAlive(plan.X, plan.Z), "cellule vivante " .. entry.Id)
			check(ToolDefs.IsInZonePool(entry.Id, plan.ItemId), "objet du pool " .. entry.Id)
			if entry.Id == "ClassicZone" then
				check(plan.ItemId == "Epingle" or plan.ItemId == "Marteau", "GameRoom : objets faibles seulement")
			elseif plan.ItemId == "MegaRouleau" or plan.ItemId == "Laser" or plan.ItemId == "Singularite" then
				seenPowerfulSummer = true
			end
		end
		check(spawned == 60, "60 plans produits pour " .. entry.Id)
	end
	check(seenPowerfulSummer, "SummerZone peut produire un objet puissant")

	-- Échecs explicites (debug off : aucun log).
	local allDead = {
		SizeX = summer.SizeX,
		SizeZ = summer.SizeZ,
		IsAlive = function(): boolean
			return false
		end,
	}
	local plan, reason = ItemSpawnPlanner.Plan("SummerZone", allDead, rng)
	check(plan == nil and reason == "no eligible cells", "échec explicite sans cellule vivante")

	local unknownPlan, unknownReason = ItemSpawnPlanner.Plan("LobbyZone", summerQuery, rng)
	check(unknownPlan == nil and unknownReason == "no item pool configured", "zone sans pool refusée")

	-- Cadence : intervalle global conservé (× nombre de zones actives).
	for _ = 1, 20 do
		local delay = ItemSpawnPlanner.NextDelay(2, rng)
		check(delay >= D.MinInterval * 2 - 1e-6 and delay <= D.MaxInterval * 2 + 1e-6, "délai production 2 zones")
	end

	-- Objet posé au-dessus de la bulle et à portée de ramassage.
	local G = GameConfig.Grid
	local bubbleTopY = summer.Origin.Y + 0.35 + G.BubbleSize.Y / 2
	local cellWorld = ZoneDefs.CellToWorld(10, 8, "SummerZone")
	local dropPos = cellWorld + Vector3.new(0, ItemSpawnPlanner.SpawnHeightOffset, 0)
	check(dropPos.Y > bubbleTopY, "objet au-dessus de la bulle")
	local rootOnCell = cellWorld + Vector3.new(0, (bubbleTopY - summer.Origin.Y) + 3, 0)
	check((rootOnCell - dropPos).Magnitude <= D.PickupRadius, "ramassable depuis la cellule")
	local rootNextCell = cellWorld + Vector3.new(G.Spacing, (bubbleTopY - summer.Origin.Y) + 3, 0)
	check((rootNextCell - dropPos).Magnitude <= D.PickupRadius, "ramassable depuis la cellule voisine")

	-- Mode diagnostic : cadence rapide + logs, puis retour à l'état production.
	GameConfig.Drops.ItemSpawnDebug = true
	check(ItemSpawnPlanner.IsDebug() == true, "debug activable")
	for _ = 1, 10 do
		local delay = ItemSpawnPlanner.NextDelay(2, rng)
		check(delay >= D.DebugMinInterval - 1e-6 and delay <= D.DebugMaxInterval + 1e-6, "délai debug 10..15 s")
	end
	print("-- Exemple de logs [ItemSpawnDebug] --")
	for _, entry in ipairs(zoneQueries) do
		local debugPlan = ItemSpawnPlanner.Plan(entry.Id, entry.Query, rng)
		if debugPlan then
			ItemSpawnPlanner.Log(
				"Spawned %s in %s at cell (%d, %d)",
				debugPlan.ItemName, debugPlan.ZoneId, debugPlan.X, debugPlan.Z
			)
		else
			check(false, "plan debug manquant pour " .. entry.Id)
		end
	end
	GameConfig.Drops.ItemSpawnDebug = false
	check(ItemSpawnPlanner.IsDebug() == false, "debug remis à false")

	if ok then
		print("[ItemSpawnTests] OK")
	end
	return ok
end

return ItemSpawnTests
