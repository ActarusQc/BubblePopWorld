--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = require(Shared.AmusementParkCoasterLogic)

local AmusementParkCoasterLogicTests = {}

function AmusementParkCoasterLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[AmusementParkCoasterLogicTests] FAIL:", msg)
			ok = false
		end
	end

	local bounds = {
		MinX = -362,
		MaxX = -154,
		MinZ = -88,
		MaxZ = 88,
		Height = 12,
	}

	check(Logic.NearestEdge(Vector3.new(-160, 12, 30), bounds) == "MaxX", "station collée au mur est")
	check(Logic.EdgeTravel("MaxX") == Vector3.new(0, 0, 1), "est vers le nord")

	local function checkFacing(dir: Vector3, label: string)
		local cf = Logic.AlignFrame(Vector3.zero, dir, Vector3.yAxis)
		check(cf.LookVector:Dot(dir.Unit) > 0.98, "avance vers " .. label)
		check((cf.RightVector:Cross(cf.UpVector) + cf.LookVector).Magnitude < 0.08, "pas de réflexion " .. label)
		check(math.abs(cf.RightVector.Y) < 0.08, "pas de roulis " .. label)
	end
	checkFacing(Vector3.zAxis, "+Z")
	checkFacing(-Vector3.zAxis, "-Z")
	checkFacing(Vector3.xAxis, "+X")
	checkFacing(-Vector3.xAxis, "-X")

	local points = Logic.BuildLoopPoints(bounds, Vector3.new(-160, 12, 30), 14, 26, 8)
	check(#points >= 20, "assez de points pour des virages")
	check(Logic.AreColinearXZ(points[1], points[2], points[3], 0.05) == true, "passage droit dans la station")
	check(math.abs(points[1].X - points[3].X) < 0.05, "entrée et sortie sur le même rail")
	check(points[1].Z < points[2].Z and points[2].Z < points[3].Z, "le train traverse d'un côté à l'autre")
	check(Logic.SegmentsCrossXZ(points) == false, "aucun croisement de rails")

	local sharp = Vector3.new(bounds.MaxX, 12, bounds.MaxZ)
	local nearestCorner = math.huge
	for _, point in ipairs(points) do
		nearestCorner = math.min(nearestCorner, (Vector3.new(point.X, 0, point.Z) - Vector3.new(sharp.X, 0, sharp.Z)).Magnitude)
	end
	check(nearestCorner > 8, "le coin nord-est n'est plus en L")

	local maxTurn = 0
	for i = 1, #points do
		local prev = points[i]
		local curr = points[(i % #points) + 1]
		local nextp = points[((i + 1) % #points) + 1]
		local d1 = Vector3.new(curr.X - prev.X, 0, curr.Z - prev.Z)
		local d2 = Vector3.new(nextp.X - curr.X, 0, nextp.Z - curr.Z)
		if d1.Magnitude > 0.4 and d2.Magnitude > 0.4 then
			maxTurn = math.max(maxTurn, math.acos(math.clamp(d1.Unit:Dot(d2.Unit), -1, 1)))
		end
	end
	check(maxTurn < math.rad(50), "virages progressifs plutôt que des L")

	local southStation = Logic.BuildLoopPoints(bounds, Vector3.new(-250, 12, -80), 14, 26, 8)
	check(Logic.SegmentsCrossXZ(southStation) == false, "pas de croisement si la station est au sud")
	check(Logic.AreColinearXZ(southStation[1], southStation[2], southStation[3], 0.05) == true, "passage droit au sud")

	local orientedFlat = Logic.OrientPath(points)
	check(#orientedFlat == #points, "un CFrame par point")
	local face = (points[2] - points[1])
	if face.Magnitude > 0.05 then
		check(orientedFlat[1].LookVector:Dot(face.Unit) > 0.5, "wagon face à la marche")
	end
	check(math.abs(orientedFlat[1].RightVector.Y) < 0.12, "pas de roulis sur la station")

	local ride = Logic.BuildRidePoints(bounds, Vector3.new(-160, 22, 30), {
		HalfLength = 14,
		CornerRadius = 26,
		CornerSamples = 8,
		BigLoopRadius = 0,
		SmallLoopRadius = 0,
		HighRise = 26,
		LowDrop = 10,
		SAmplitude = 0,
		SSamples = 12,
		HillPeakZ = 5,
	})
	check(#ride >= 40, "circuit assez détaillé")
	check(Logic.AreColinearXZ(ride[1], ride[2], ride[3], 0.08) == true, "station toujours en ligne droite")
	local peak = ride[1]
	local minY, maxY = math.huge, -math.huge
	for _, point in ipairs(ride) do
		minY = math.min(minY, point.Y)
		maxY = math.max(maxY, point.Y)
		if point.Y > peak.Y then
			peak = point
		end
	end
	check(maxY - minY > 16, "une vraie montée")
	check(peak.X < bounds.MinX + 55, "colline à l'ouest derrière la grande roue")
	check(math.abs(peak.Z - 5) < 40, "sommet aligné sur la grande roue")
	local rideCfs = Logic.OrientPath(ride)
	local rideDir = ride[2] - ride[1]
	if rideDir.Magnitude > 0.05 then
		check(rideCfs[1].LookVector:Dot(rideDir.Unit) > 0.5, "sens du train sur le circuit varié")
	end
	check(math.abs(rideCfs[1].RightVector.Y) < 0.12, "wagons à plat sur les rails à la station")
	local sampled = Logic.SampleOnSegment(rideCfs[1], rideCfs[2], 0.5)
	check(math.abs(sampled.RightVector.Y) < 0.15, "interpolation sans basculer sur le côté")
	local rolledOffTrack = false
	for _, cf in ipairs(rideCfs) do
		if cf.UpVector.Y > 0.85 and math.abs(cf.RightVector.Y) > 0.18 then
			rolledOffTrack = true
			break
		end
	end
	check(rolledOffTrack == false, "les wagons restent à plat sur les rails")

	local withLoop = Logic.BuildRidePoints(bounds, Vector3.new(-160, 22, 30), {
		HalfLength = 14,
		CornerRadius = 26,
		CornerSamples = 8,
		BigLoopRadius = 16,
		SmallLoopRadius = 0,
		HighRise = 26,
		LowDrop = 10,
		SAmplitude = 0,
		SSamples = 12,
		HillPeakZ = 5,
		LoopSamples = 16,
	})
	check(Logic.AreColinearXZ(withLoop[1], withLoop[2], withLoop[3], 0.08) == true, "station intacte avec une loop")
	local loopCfs = Logic.OrientPath(withLoop)
	local inverted = false
	local loopOnSouth = false
	local loopBehindWheel = false
	for i, point in ipairs(withLoop) do
		if point.Y > bounds.Height + 30 then
			if point.Z < -20 and point.X > bounds.MinX + 40 then
				loopOnSouth = true
			end
			if point.X < bounds.MinX + 40 then
				loopBehindWheel = true
			end
		end
		local cf = loopCfs[i]
		if cf and cf.UpVector.Y < -0.35 then
			inverted = true
		end
	end
	check(loopOnSouth == true, "une loop sur le côté sud")
	check(loopBehindWheel == false, "pas derrière la grande roue")
	check(inverted == true, "tête en bas au sommet de la loop")
	check(loopCfs[1].LookVector:Dot((withLoop[2] - withLoop[1]).Unit) > 0.5, "toujours face à la marche")
	check(math.abs(loopCfs[1].RightVector.Y) < 0.12, "pas de roulis à la station avec loop")

	if ok then
		print("[AmusementParkCoasterLogicTests] ALL PASS")
	else
		warn("[AmusementParkCoasterLogicTests] SOME FAILED")
	end
	return ok
end

return AmusementParkCoasterLogicTests
