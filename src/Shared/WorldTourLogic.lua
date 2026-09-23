--!strict
-- Circuit mondial : une boucle qui contourne chaque zone (parc, Classic, Summer, …)
-- en passant par la station du parc. Nouveaux mondes = nouvelles îles automatiquement.

local AmusementParkConfig = require(script.Parent.AmusementParkConfig)
local GameConfig = require(script.Parent.GameConfig)
local ZoneDefs = require(script.Parent.ZoneDefs)
local CoasterLogic = require(script.Parent.AmusementParkCoasterLogic)

local WorldTourLogic = {}

export type Island = {
	ZoneId: string,
	DisplayName: string,
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
}

export type StopSpec = {
	ZoneId: string,
	DisplayName: string,
	Position: Vector3,
	Distance: number,
}

export type TourOptions = {
	Height: number,
	ScenicHeight: number?,
	Clearance: number,
	CorridorHalfZ: number,
	CornerRadius: number,
	CornerSamples: number,
	StationHalfLength: number,
	HighRise: number,
	HillPeakZ: number,
	LoopRadius: number,
	LoopSamples: number,
}

export type SchedulePhase = {
	Kind: "dwell" | "travel",
	Duration: number,
	FromDistance: number,
	ToDistance: number,
	StopIndex: number?,
}

local function addPoint(points: { Vector3 }, point: Vector3)
	local last = points[#points]
	if last and (last - point).Magnitude < 0.35 then
		return
	end
	table.insert(points, point)
end

local function addArc(
	points: { Vector3 },
	centerX: number,
	centerZ: number,
	radius: number,
	startAngle: number,
	endAngle: number,
	samples: number,
	height: number
)
	for sample = 0, samples do
		local alpha = sample / samples
		local angle = startAngle + (endAngle - startAngle) * alpha
		addPoint(points, Vector3.new(centerX + math.cos(angle) * radius, height, centerZ + math.sin(angle) * radius))
	end
end

function WorldTourLogic.ExpandIsland(island: Island, clearance: number, lockMaxX: number?): Island
	return {
		ZoneId = island.ZoneId,
		DisplayName = island.DisplayName,
		MinX = island.MinX - clearance,
		MaxX = if lockMaxX then lockMaxX else island.MaxX + clearance,
		MinZ = island.MinZ - clearance,
		MaxZ = island.MaxZ + clearance,
	}
end

function WorldTourLogic.CollectIslands(stationX: number, clearance: number, corridorHalfZ: number?): { Island }
	local islands: { Island } = {}
	local park = AmusementParkConfig
	local parkHalfX = park.Size.X / 2
	local parkHalfZ = park.Size.Z / 2
	local parkIsland: Island = {
		ZoneId = "AmusementPark",
		DisplayName = park.DisplayName,
		MinX = park.Origin.X - parkHalfX,
		MaxX = park.Origin.X + parkHalfX,
		MinZ = park.Origin.Z - parkHalfZ,
		MaxZ = park.Origin.Z + parkHalfZ,
	}
	-- La station doit rester sur le bord est du parc.
	table.insert(islands, WorldTourLogic.ExpandIsland(parkIsland, clearance, stationX))

	for _, def in ipairs(ZoneDefs.List) do
		if def.Id == "AmusementPark" then
			continue
		end
		local bounds = ZoneDefs.GetZoneBounds(def.Id)
		if not bounds then
			continue
		end
		table.insert(
			islands,
			WorldTourLogic.ExpandIsland({
				ZoneId = def.Id,
				DisplayName = def.DisplayName,
				MinX = bounds.MinX,
				MaxX = bounds.MaxX,
				MinZ = bounds.MinZ,
				MaxZ = bounds.MaxZ,
			}, clearance)
		)
	end

	local have: { [string]: boolean } = {}
	for _, island in ipairs(islands) do
		have[island.ZoneId] = true
	end
	for _, id in ipairs({ "ClassicZone", "SummerZone" }) do
		if not have[id] then
			local def = ZoneDefs.Get(id)
			if def then
				local o = def.ZoneOrigin or def.Origin
				local halfX, halfZ = ZoneDefs.GetOuterHalfExtent(id)
				table.insert(
					islands,
					WorldTourLogic.ExpandIsland({
						ZoneId = def.Id,
						DisplayName = def.DisplayName,
						MinX = o.X - halfX,
						MaxX = o.X + halfX,
						MinZ = o.Z - halfZ,
						MaxZ = o.Z + halfZ,
					}, clearance)
				)
			end
		end
	end

	table.sort(islands, function(a, b)
		return (a.MinX + a.MaxX) < (b.MinX + b.MaxX)
	end)
	return WorldTourLogic.StretchToCorridor(islands, corridorHalfZ or 16)
end

-- Un monde trop au nord/sud est étiré jusqu'au corridor pour rester sur la boucle.
function WorldTourLogic.StretchToCorridor(islands: { Island }, corridorHalfZ: number): { Island }
	local c = math.max(8, corridorHalfZ)
	local out: { Island } = {}
	for _, island in ipairs(islands) do
		local minZ = island.MinZ
		local maxZ = island.MaxZ
		if maxZ < -c then
			maxZ = -c
		end
		if minZ > c then
			minZ = c
		end
		table.insert(out, {
			ZoneId = island.ZoneId,
			DisplayName = island.DisplayName,
			MinX = island.MinX,
			MaxX = island.MaxX,
			MinZ = minZ,
			MaxZ = maxZ,
		})
	end
	return out
end

-- Rectangle mondial autour de tous les thèmes, avec une encoche à la station du parc.
function WorldTourLogic.BuildOutlineCorners(islands: { Island }, corridorHalfZ: number): { Vector3 }
	local corners: { Vector3 } = {}
	if #islands == 0 then
		return corners
	end
	local stationX = islands[1].MaxX
	local parkMaxZ = islands[1].MaxZ
	local worldMinX = islands[1].MinX
	local worldMinZ = islands[1].MinZ
	local worldMaxX = islands[1].MaxX
	local worldMaxZ = islands[1].MaxZ
	for _, island in ipairs(islands) do
		worldMinX = math.min(worldMinX, island.MinX)
		worldMinZ = math.min(worldMinZ, island.MinZ)
		worldMaxX = math.max(worldMaxX, island.MaxX)
		worldMaxZ = math.max(worldMaxZ, island.MaxZ)
	end
	local returnX = if #islands >= 2 then islands[2].MinX else stationX + 40
	if returnX <= stationX + 8 then
		returnX = stationX + 40
	end
	local corridorZ = math.min(math.max(8, corridorHalfZ), parkMaxZ - 24)

	local function push(x: number, z: number)
		local prev = corners[#corners]
		if prev and math.abs(prev.X - x) < 0.05 and math.abs(prev.Z - z) < 0.05 then
			return
		end
		table.insert(corners, Vector3.new(x, 0, z))
	end

	push(stationX, parkMaxZ)
	push(worldMinX, parkMaxZ)
	push(worldMinX, worldMinZ)
	push(worldMaxX, worldMinZ)
	push(worldMaxX, worldMaxZ)
	push(returnX, worldMaxZ)
	push(returnX, corridorZ)
	push(stationX, corridorZ)
	return corners
end

function WorldTourLogic.SubdivideStraights(points: { Vector3 }, maxSpan: number): { Vector3 }
	local out: { Vector3 } = {}
	local span = math.max(12, maxSpan)
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		local delta = b - a
		local dist = delta.Magnitude
		local steps = math.max(1, math.ceil(dist / span))
		for step = 0, steps - 1 do
			addPoint(out, a:Lerp(b, step / steps))
		end
	end
	return out
end

function WorldTourLogic.RoundOutline(corners: { Vector3 }, radius: number, samples: number, height: number): { Vector3 }
	local points: { Vector3 } = {}
	local count = #corners
	if count < 3 then
		return points
	end
	for i = 1, count do
		local prev = corners[((i - 2) % count) + 1]
		local curr = corners[i]
		local nextp = corners[(i % count) + 1]
		local incoming = Vector3.new(curr.X - prev.X, 0, curr.Z - prev.Z)
		local outgoing = Vector3.new(nextp.X - curr.X, 0, nextp.Z - curr.Z)
		local inLen = incoming.Magnitude
		local outLen = outgoing.Magnitude
		if inLen < 0.4 or outLen < 0.4 then
			addPoint(points, Vector3.new(curr.X, height, curr.Z))
			continue
		end
		local inDir = incoming.Unit
		local outDir = outgoing.Unit
		local maxR = math.min(inLen, outLen) * 0.42
		if maxR < 1.25 then
			addPoint(points, Vector3.new(curr.X, height, curr.Z))
			continue
		end
		local r = math.min(radius, maxR)
		local start = Vector3.new(curr.X - inDir.X * r, height, curr.Z - inDir.Z * r)
		local finish = Vector3.new(curr.X + outDir.X * r, height, curr.Z + outDir.Z * r)
		local crossY = inDir.X * outDir.Z - inDir.Z * outDir.X
		local side = if crossY >= 0
			then Vector3.new(-inDir.Z, 0, inDir.X)
			else Vector3.new(inDir.Z, 0, -inDir.X)
		local centerX = start.X + side.X * r
		local centerZ = start.Z + side.Z * r
		local a0 = math.atan2(start.Z - centerZ, start.X - centerX)
		local a1 = math.atan2(finish.Z - centerZ, finish.X - centerX)
		if crossY >= 0 then
			while a1 <= a0 + 1e-4 do
				a1 += math.pi * 2
			end
		else
			while a1 >= a0 - 1e-4 do
				a1 -= math.pi * 2
			end
		end
		addPoint(points, start)
		addArc(points, centerX, centerZ, r, a0, a1, math.max(6, samples), height)
		addPoint(points, finish)
	end
	if #points > 1 and (points[#points] - points[1]).Magnitude < 0.35 then
		table.remove(points, #points)
	end
	return points
end

function WorldTourLogic.RotateToStation(points: { Vector3 }, station: Vector3): { Vector3 }
	if #points == 0 then
		return points
	end
	local bestI = 1
	local bestDist = math.huge
	for i, p in ipairs(points) do
		local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(station.X, 0, station.Z)).Magnitude
		if d < bestDist then
			bestDist = d
			bestI = i
		end
	end
	-- Reculer d'un cran pour que la station soit le 2e point (entrée → station → sortie).
	local startAt = ((bestI - 2) % #points) + 1
	if startAt < 1 then
		startAt = #points
	end
	local rotated: { Vector3 } = {}
	for i = 0, #points - 1 do
		table.insert(rotated, points[((startAt - 1 + i) % #points) + 1])
	end
	-- Forcer le point station au milieu du passage droit.
	if #rotated >= 3 then
		rotated[2] = Vector3.new(station.X, station.Y, station.Z)
		local travel = Vector3.new(0, 0, 1)
		local half = math.max(8, (rotated[3] - rotated[1]).Magnitude * 0.35)
		rotated[1] = Vector3.new(station.X, station.Y, station.Z) - travel * half
		rotated[3] = Vector3.new(station.X, station.Y, station.Z) + travel * half
	end
	return rotated
end

function WorldTourLogic.ApplyScenicHeight(points: { Vector3 }, parkMaxX: number, scenicY: number, stationY: number)
	if scenicY <= 0 then
		return
	end
	for i = 4, #points do
		local p = points[i]
		if p.X > parkMaxX + 8 then
			local t = math.clamp((p.X - (parkMaxX + 8)) / 36, 0, 1)
			points[i] = Vector3.new(p.X, stationY + (scenicY - stationY) * t, p.Z)
		end
	end
end

function WorldTourLogic.ApplyParkWestHill(points: { Vector3 }, parkMinX: number, peakZ: number, height: number, rise: number)
	local hPeak = height + math.max(8, rise)
	for i = 4, #points do
		local p = points[i]
		local west = math.exp(-((p.X - parkMinX) / 32) ^ 2)
		local along = math.exp(-((p.Z - peakZ) / 52) ^ 2)
		points[i] = Vector3.new(p.X, height + (hPeak - height) * west * along, p.Z)
	end
end

function WorldTourLogic.PolylineLength(points: { Vector3 }): number
	local total = 0
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		total += (b - a).Magnitude
	end
	return total
end

function WorldTourLogic.DistanceToPoint(points: { Vector3 }, target: Vector3): number
	local bestDist = math.huge
	local bestAlong = 0
	local along = 0
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		local seg = b - a
		local len = seg.Magnitude
		if len > 1e-4 then
			local t = math.clamp((target - a):Dot(seg) / (len * len), 0, 1)
			local proj = a + seg * t
			local d = (proj - target).Magnitude
			if d < bestDist then
				bestDist = d
				bestAlong = along + len * t
			end
		end
		along += len
	end
	return bestAlong
end

function WorldTourLogic.PointAtDistance(points: { Vector3 }, distance: number): Vector3
	local total = WorldTourLogic.PolylineLength(points)
	if total <= 0 or #points == 0 then
		return Vector3.zero
	end
	local remain = distance % total
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		local len = (b - a).Magnitude
		if remain <= len then
			if len < 1e-4 then
				return a
			end
			return a:Lerp(b, remain / len)
		end
		remain -= len
	end
	return points[1]
end

local function preferredStopTarget(island: Island, station: Vector3): Vector3
	if island.ZoneId == "AmusementPark" then
		return station
	end
	if island.ZoneId == "SummerZone" then
		-- Bout est (fond de la zone), sur le rail est.
		return Vector3.new(island.MaxX, station.Y, (island.MinZ + island.MaxZ) * 0.5)
	end
	return Vector3.new((island.MinX + island.MaxX) * 0.5, station.Y, island.MinZ)
end

function WorldTourLogic.BuildStops(points: { Vector3 }, islands: { Island }, station: Vector3): { StopSpec }
	local stops: { StopSpec } = {}
	for _, island in ipairs(islands) do
		local target = preferredStopTarget(island, station)
		local distance = WorldTourLogic.DistanceToPoint(points, target)
		table.insert(stops, {
			ZoneId = island.ZoneId,
			DisplayName = island.DisplayName,
			Position = WorldTourLogic.PointAtDistance(points, distance),
			Distance = distance,
		})
	end
	table.sort(stops, function(a, b)
		return a.Distance < b.Distance
	end)
	-- Fusionner les arrêts trop proches (corridor étroit).
	local cleaned: { StopSpec } = {}
	for _, stop in ipairs(stops) do
		local last = cleaned[#cleaned]
		if last and math.abs(stop.Distance - last.Distance) < 36 then
			if stop.ZoneId == "AmusementPark" then
				cleaned[#cleaned] = stop
			end
		else
			table.insert(cleaned, stop)
		end
	end
	return cleaned
end

function WorldTourLogic.BuildRidePoints(station: Vector3, options: TourOptions): ({ Vector3 }, { Island }, { StopSpec })
	local islands = WorldTourLogic.CollectIslands(station.X, options.Clearance, options.CorridorHalfZ)
	local corners = WorldTourLogic.BuildOutlineCorners(islands, options.CorridorHalfZ)
	local points = WorldTourLogic.RoundOutline(corners, options.CornerRadius, options.CornerSamples, options.Height)
	points = WorldTourLogic.SubdivideStraights(points, 28)
	points = WorldTourLogic.RotateToStation(points, station)
	if #islands > 0 then
		WorldTourLogic.ApplyParkWestHill(points, islands[1].MinX, options.HillPeakZ, options.Height, options.HighRise)
		if options.ScenicHeight and options.ScenicHeight > 0 then
			WorldTourLogic.ApplyScenicHeight(points, islands[1].MaxX, options.ScenicHeight, options.Height)
		end
		if options.LoopRadius >= 8 then
			local spliced = WorldTourLogic.SpliceSouthLoop(points, islands[1], options.LoopRadius, options.LoopSamples)
			if WorldTourLogic.ReachesOtherZones(spliced) then
				points = spliced
			end
		end
	end
	local stops = WorldTourLogic.BuildStops(points, islands, station)
	return points, islands, stops
end

function WorldTourLogic.RideOptionsFromConfig(height: number): TourOptions
	local c = AmusementParkConfig.Coaster
	local tour = c.WorldTour or { Clearance = 6, CorridorHalfZ = 16, CornerRadius = 22, ScenicHeight = 12 }
	return {
		Height = height,
		ScenicHeight = tour.ScenicHeight,
		Clearance = tour.Clearance,
		CorridorHalfZ = tour.CorridorHalfZ,
		CornerRadius = tour.CornerRadius,
		CornerSamples = c.CornerSamples,
		StationHalfLength = c.StationHalfLength,
		HighRise = c.HighRise,
		HillPeakZ = AmusementParkConfig.Placements.GrandeRoue.Position.Z,
		LoopRadius = c.LoopRadius,
		LoopSamples = c.LoopSamples,
	}
end

function WorldTourLogic.PathExtents(points: { Vector3 }): (number, number, number, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(points) do
		minX = math.min(minX, p.X)
		maxX = math.max(maxX, p.X)
		minZ = math.min(minZ, p.Z)
		maxZ = math.max(maxZ, p.Z)
	end
	return minX, maxX, minZ, maxZ
end

function WorldTourLogic.ReachesOtherZones(points: { Vector3 }): boolean
	local _, maxX, minZ = WorldTourLogic.PathExtents(points)
	local classic = ZoneDefs.GetZoneBounds("ClassicZone")
	local summer = ZoneDefs.GetZoneBounds("SummerZone")
	if not classic or not summer then
		return maxX > 80
	end
	return maxX > summer.MaxX - 8 and minZ < classic.MinZ + 8
end

function WorldTourLogic.SpliceSouthLoop(points: { Vector3 }, park: Island, loopRadius: number, loopSamples: number): { Vector3 }
	-- Détour sud-parc : loop en O puis on continue vers l'est (pas de demi-tour).
	local bestI = 0
	local bestDist = math.huge
	for i = 4, #points - 3 do
		local p = points[i]
		local nxt = points[(i % #points) + 1]
		local travel = Vector3.new(nxt.X - p.X, 0, nxt.Z - p.Z)
		if travel.Magnitude > 0.4 and travel.Unit.Z < -0.7 and math.abs(p.X - park.MinX) <= 20 then
			local d = math.abs(p.Z - park.MinZ)
			if d < bestDist and p.Z > park.MinZ - 10 then
				bestDist = d
				bestI = i
			end
		end
	end
	if bestI == 0 then
		return points
	end
	local _, _, worldMinZ = WorldTourLogic.PathExtents(points)
	local height = points[bestI].Y
	local along = math.min(90, math.max(56, (park.MaxX - park.MinX) * 0.38))
	local loopAt = Vector3.new(park.MinX + along, height, park.MinZ)
	local afterX = math.min(park.MaxX - 36, loopAt.X + loopRadius * 1.8)
	if afterX < loopAt.X + 12 then
		afterX = loopAt.X + 12
	end
	local extra: { Vector3 } = {}
	addPoint(extra, Vector3.new(park.MinX, height, park.MinZ))
	addPoint(extra, loopAt)
	CoasterLogic.AppendVerticalLoop(extra, loopAt, Vector3.new(1, 0, 0), loopRadius, loopSamples)
	addPoint(extra, Vector3.new(afterX, height, park.MinZ))
	addPoint(extra, Vector3.new(afterX, height, worldMinZ))
	local rejoinI = 0
	for i = bestI + 1, #points do
		local p = points[i]
		local nxt = points[(i % #points) + 1]
		local travel = Vector3.new(nxt.X - p.X, 0, nxt.Z - p.Z)
		if math.abs(p.Z - worldMinZ) <= 18 and p.X >= afterX - 12 and travel.Magnitude > 0.4 and travel.Unit.X > 0.65 then
			rejoinI = i
			break
		end
	end
	if rejoinI == 0 then
		return points
	end
	local result: { Vector3 } = {}
	for i = 1, bestI do
		table.insert(result, points[i])
	end
	for _, p in ipairs(extra) do
		table.insert(result, p)
	end
	for i = rejoinI, #points do
		table.insert(result, points[i])
	end
	return result
end

function WorldTourLogic.ShouldPlaceSupport(position: Vector3, islands: { Island }): boolean
	for _, island in ipairs(islands) do
		local inset = 8
		if
			position.X > island.MinX + inset
			and position.X < island.MaxX - inset
			and position.Z > island.MinZ + inset
			and position.Z < island.MaxZ - inset
		then
			return false
		end
	end
	-- Lobby au sud de Classic.
	if math.abs(position.X) < 50 and position.Z < -198 and position.Z > -290 then
		return false
	end
	return true
end

function WorldTourLogic.CanDisembark(playerLevel: number, zoneId: string): boolean
	return ZoneDefs.CanLevelEnter(playerLevel, zoneId)
end

function WorldTourLogic.WalkHeight(groundY: number): number
	return WorldTourLogic.FloorTopY(nil, groundY) + 3.4
end

function WorldTourLogic.FloorTopY(_zoneId: string?, groundY: number): number
	local grid = GameConfig.Grid
	return (if groundY > 0 then groundY else grid.Origin.Y) - grid.BubbleSize.Y * 0.35
end

function WorldTourLogic.GroundLanding(zoneId: string, groundY: number): Vector3
	local zone = ZoneDefs.GetZoneBounds(zoneId)
	local topY = WorldTourLogic.FloorTopY(zoneId, if zone then zone.Origin.Y else groundY)
	local y = topY + 3.4
	if not zone then
		return Vector3.new(0, y, 0)
	end
	-- Inset vers le centre : les rails sont hors plancher, un spawn sur le bord tombe dans le vide.
	if zoneId == "SummerZone" then
		return Vector3.new(zone.MaxX - 28, y, (zone.MinZ + zone.MaxZ) * 0.5)
	end
	if zoneId == "AmusementPark" then
		return Vector3.new(zone.MaxX - 16, y, zone.Origin.Z)
	end
	return Vector3.new(zone.Origin.X, y, zone.MinZ + 22)
end

function WorldTourLogic.NextUnlockedStop(stops: { StopSpec }, fromDistance: number, playerLevel: number, totalLength: number): StopSpec?
	if #stops == 0 or totalLength <= 0 then
		return nil
	end
	local best: StopSpec? = nil
	local bestAhead = math.huge
	for _, stop in ipairs(stops) do
		if WorldTourLogic.CanDisembark(playerLevel, stop.ZoneId) then
			local ahead = (stop.Distance - fromDistance) % totalLength
			if ahead < 0.75 then
				ahead += totalLength
			end
			if ahead < bestAhead then
				bestAhead = ahead
				best = stop
			end
		end
	end
	return best
end

function WorldTourLogic.NearestStop(stops: { StopSpec }, distance: number, totalLength: number): StopSpec?
	if #stops == 0 or totalLength <= 0 then
		return nil
	end
	local best = stops[1]
	local bestD = math.huge
	for _, stop in ipairs(stops) do
		local delta = math.abs(stop.Distance - distance)
		delta = math.min(delta, totalLength - delta)
		if delta < bestD then
			bestD = delta
			best = stop
		end
	end
	return best
end

function WorldTourLogic.BuildSchedule(stops: { StopSpec }, totalLength: number, speed: number, dwell: number): ({ SchedulePhase }, number)
	local phases: { SchedulePhase } = {}
	if #stops == 0 or totalLength <= 0 or speed <= 0 then
		return phases, 0
	end
	for i, stop in ipairs(stops) do
		table.insert(phases, {
			Kind = "dwell",
			Duration = dwell,
			FromDistance = stop.Distance,
			ToDistance = stop.Distance,
			StopIndex = i,
		})
		local nxt = stops[(i % #stops) + 1]
		local travel = (nxt.Distance - stop.Distance) % totalLength
		if travel < 1 then
			travel = totalLength
		end
		table.insert(phases, {
			Kind = "travel",
			Duration = travel / speed,
			FromDistance = stop.Distance,
			ToDistance = nxt.Distance,
			StopIndex = i,
		})
	end
	local cycle = 0
	for _, phase in ipairs(phases) do
		cycle += phase.Duration
	end
	return phases, cycle
end

function WorldTourLogic.SampleSchedule(
	elapsed: number,
	phases: { SchedulePhase },
	cycle: number,
	totalLength: number,
	offset: number
): (number, boolean, number?)
	if cycle <= 0 or #phases == 0 then
		return 0, false, nil
	end
	local t = (elapsed + offset) % cycle
	for _, phase in ipairs(phases) do
		if t <= phase.Duration then
			if phase.Kind == "dwell" then
				return phase.FromDistance, true, phase.StopIndex
			end
			local alpha = if phase.Duration > 1e-4 then t / phase.Duration else 1
			local span = (phase.ToDistance - phase.FromDistance) % totalLength
			if span < 1e-3 then
				span = totalLength
			end
			return (phase.FromDistance + span * alpha) % totalLength, false, nil
		end
		t -= phase.Duration
	end
	return phases[1].FromDistance, true, phases[1].StopIndex
end

function WorldTourLogic.TrainOffset(trainIndex: number, trainCount: number, cycle: number): number
	if trainCount <= 1 then
		return 0
	end
	return ((trainIndex - 1) / trainCount) * cycle
end

return WorldTourLogic
