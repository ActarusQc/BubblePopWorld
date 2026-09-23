--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = require(Shared.WorldTourLogic)
local Coaster = require(Shared.AmusementParkCoasterLogic)
local ZoneDefs = require(Shared.ZoneDefs)

local WorldTourLogicTests = {}

function WorldTourLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[WorldTourLogicTests] FAIL:", msg)
			ok = false
		end
	end

	local station = Vector3.new(-193, 26, 30)
	local islands = Logic.CollectIslands(station.X, 18)
	check(#islands >= 3, "parc + Classic + Summer")
	check(islands[1].ZoneId == "AmusementPark", "parc à l'ouest")
	check(islands[1].MaxX == station.X, "station sur le bord est du parc")
	local ids: { [string]: boolean } = {}
	for _, island in ipairs(islands) do
		ids[island.ZoneId] = true
	end
	check(ids.ClassicZone == true, "Classic dans le tour")
	check(ids.SummerZone == true, "Summer dans le tour")

	local corners = Logic.BuildOutlineCorners(islands, 16)
	check(#corners >= 8, "polygone assez détaillé")
	check(Coaster.SegmentsCrossXZ(corners) == false, "contour sans croisement")
	local cornerMaxX, cornerMinZ = -math.huge, math.huge
	for _, c in ipairs(corners) do
		cornerMaxX = math.max(cornerMaxX, c.X)
		cornerMinZ = math.min(cornerMinZ, c.Z)
	end
	local summerBounds = ZoneDefs.GetZoneBounds("SummerZone")
	local classicBounds = ZoneDefs.GetZoneBounds("ClassicZone")
	check(summerBounds ~= nil and cornerMaxX > summerBounds.MaxX, "contour coins dépasse Summer")
	check(classicBounds ~= nil and cornerMinZ < classicBounds.MinZ, "contour coins dépasse Classic")

	local points, tourIslands, stops = Logic.BuildRidePoints(station, {
		Height = 26,
		Clearance = 6,
		ScenicHeight = 12,
		CorridorHalfZ = 16,
		CornerRadius = 26,
		CornerSamples = 8,
		StationHalfLength = 16,
		HighRise = 28,
		HillPeakZ = 5,
		LoopRadius = 16,
		LoopSamples = 16,
	})
	check(#points >= 50, "tracé mondial assez long")
	check(#tourIslands >= 3, "îles renvoyées")
	check(Coaster.AreColinearXZ(points[1], points[2], points[3], 0.12) == true, "passage droit en station")
	check(math.abs(points[2].X - station.X) < 1.5, "station sur le rail")
	check(Coaster.SegmentsCrossXZ(points) == false, "rails sans croisement")

	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(points) do
		minX = math.min(minX, p.X)
		maxX = math.max(maxX, p.X)
		minZ = math.min(minZ, p.Z)
		maxZ = math.max(maxZ, p.Z)
	end
	local summer = ZoneDefs.GetZoneBounds("SummerZone")
	local classic = ZoneDefs.GetZoneBounds("ClassicZone")
	check(summer ~= nil and maxX > summer.MaxX and maxX < summer.MaxX + 24, "rails collés à l'est Summer")
	check(classic ~= nil and minZ < classic.MinZ and minZ > classic.MinZ - 24, "rails collés au sud Classic")
	check(classic ~= nil and maxZ > classic.MaxZ and maxZ < classic.MaxZ + 24, "rails collés au nord Classic")
	check(minX < tourIslands[1].MinX + 8, "contourne le parc à l'ouest")

	local hasPark = false
	local hasClassic = false
	local hasSummer = false
	for _, stop in ipairs(stops) do
		if stop.ZoneId == "AmusementPark" then
			hasPark = true
		elseif stop.ZoneId == "ClassicZone" then
			hasClassic = true
		elseif stop.ZoneId == "SummerZone" then
			hasSummer = true
		end
	end
	check(hasPark and hasClassic and hasSummer, "un arrêt par monde")
	for _, stop in ipairs(stops) do
		if stop.ZoneId == "SummerZone" and summer then
			check(stop.Position.X > summer.MaxX - 20, "arrêt Summer au bout est")
		end
	end
	local loopHigh = false
	for _, p in ipairs(points) do
		if p.Y > 26 + 20 then
			loopHigh = true
			break
		end
	end
	check(loopHigh == true, "loop verticale en O dans le parc")
	local loopOnParkSouth = false
	for _, p in ipairs(points) do
		if p.Y > 26 + 20 and math.abs(p.Z - tourIslands[1].MinZ) < 22 then
			loopOnParkSouth = true
			break
		end
	end
	check(loopOnParkSouth == true, "loop en O sur le sud du parc")
	local peakI, peakY = 1, -math.huge
	for i, p in ipairs(points) do
		if p.Y > peakY then
			peakY = p.Y
			peakI = i
		end
	end
	local reversed = false
	for i = peakI, math.min(#points, peakI + 14) do
		if math.abs(points[i].X - tourIslands[1].MinX) < 14 then
			reversed = true
			break
		end
	end
	check(reversed == false, "après la loop on continue vers l'est")
	check(Logic.ReachesOtherZones(points) == true, "le tracé sort vers Classic et Summer")

	local livePoints = Logic.BuildRidePoints(station, Logic.RideOptionsFromConfig(26))
	check(Logic.ReachesOtherZones(livePoints) == true, "config de jeu sort du parc")
	local _, liveMaxX, liveMinZ = Logic.PathExtents(livePoints)
	check(summer ~= nil and liveMaxX > summer.MaxX, "config live dépasse Summer")
	check(classic ~= nil and liveMinZ < classic.MinZ, "config live dépasse Classic")

	check(Logic.CanDisembark(1, "ClassicZone") == true, "Classic ouvert niv 1")
	check(Logic.CanDisembark(1, "AmusementPark") == true, "parc ouvert niv 1")
	check(Logic.CanDisembark(1, "SummerZone") == false, "Summer fermé niv 1")
	check(Logic.CanDisembark(3, "SummerZone") == true, "Summer ouvert niv 3")

	local total = Logic.PolylineLength(points)
	check(total > 800, "parcours plus long que le seul parc")
	local nextStop = Logic.NextUnlockedStop(stops, 0, 1, total)
	check(nextStop ~= nil and nextStop.ZoneId ~= "SummerZone", "niv 1 n'est pas débarqué à Summer")

	local phases, cycle = Logic.BuildSchedule(stops, total, 20, 7)
	check(#phases >= 6, "dwell + trajet par arrêt")
	check(cycle > 40, "cycle assez long")
	local d0, dwelling0 = Logic.SampleSchedule(0, phases, cycle, total, 0)
	check(dwelling0 == true, "train 1 à quai au départ")
	local offset = Logic.TrainOffset(2, 3, cycle)
	check(offset > 0, "2e train décalé")
	local _, dwelling2 = Logic.SampleSchedule(0, phases, cycle, total, offset)
	check(d0 == d0, "sample stable")
	-- Les 3 trains ne sont pas tous à la même distance.
	local d2 = Logic.SampleSchedule(0, phases, cycle, total, offset)
	local d3 = Logic.SampleSchedule(0, phases, cycle, total, Logic.TrainOffset(3, 3, cycle))
	check(math.abs(d2 - d0) > 20 or dwelling2 ~= dwelling0, "trains écartés")
	check(math.abs(d3 - d0) > 20, "3e train écarté")

	local tight = {
		Vector3.new(0, 0, 0),
		Vector3.new(12, 0, 0),
		Vector3.new(12, 0, 12),
		Vector3.new(0, 0, 12),
	}
	local roundedTight = Logic.RoundOutline(tight, 28, 8, 26)
	check(#roundedTight >= 8, "virage court ne plante plus")

	check(Logic.ShouldPlaceSupport(Vector3.new(-500, 26, 0), islands) == true, "support hors zone")
	check(Logic.ShouldPlaceSupport(Vector3.new(0, 26, 0), islands) == false, "pas de poteau sur Classic")

	local summerLand = Logic.GroundLanding("SummerZone", 6)
	check(summer ~= nil and summerLand.X > (summer.MinX + summer.MaxX) * 0.5, "débarquement Summer au bout est")
	check(summer ~= nil and summerLand.X < summer.MaxX - 16, "débarquement Summer sur le plateau, pas le vide")
	check(summer ~= nil and summerLand.Z > summer.MinZ + 8 and summerLand.Z < summer.MaxZ - 8, "débarquement Summer dans la largeur")
	local classicLand = Logic.GroundLanding("ClassicZone", 6)
	check(classic ~= nil and classicLand.Z > classic.MinZ, "débarquement Classic sur la planche")
	check(classic ~= nil and classicLand.Z < classic.MaxZ - 8, "débarquement Classic pas hors planche")
	check(Logic.CanDisembark(1, "SummerZone") == false, "pas de débarquement Summer niv 1")

	if ok then
		print("[WorldTourLogicTests] ALL PASS")
	else
		warn("[WorldTourLogicTests] SOME FAILED")
	end
	return ok
end

return WorldTourLogicTests
