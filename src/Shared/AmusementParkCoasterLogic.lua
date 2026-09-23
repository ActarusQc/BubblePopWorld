--!strict
-- Circuit périphérique : une boucle simple, passage droit dans la station,
-- coins en quart de cercle.

local AmusementParkCoasterLogic = {}

export type EdgeName = "MaxX" | "MinX" | "MaxZ" | "MinZ"

export type LoopBounds = {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	Height: number,
}

function AmusementParkCoasterLogic.NearestEdge(position: Vector3, bounds: LoopBounds): EdgeName
	local distances = {
		{ Edge = "MaxX" :: EdgeName, Value = math.abs(bounds.MaxX - position.X) },
		{ Edge = "MinX" :: EdgeName, Value = math.abs(position.X - bounds.MinX) },
		{ Edge = "MaxZ" :: EdgeName, Value = math.abs(bounds.MaxZ - position.Z) },
		{ Edge = "MinZ" :: EdgeName, Value = math.abs(position.Z - bounds.MinZ) },
	}
	table.sort(distances, function(a, b)
		return a.Value < b.Value
	end)
	return distances[1].Edge
end

-- Sens antihoraire : est→nord, nord→ouest, ouest→sud, sud→est.
function AmusementParkCoasterLogic.EdgeTravel(edge: EdgeName): Vector3
	if edge == "MaxX" then
		return Vector3.new(0, 0, 1)
	elseif edge == "MaxZ" then
		return Vector3.new(-1, 0, 0)
	elseif edge == "MinX" then
		return Vector3.new(0, 0, -1)
	end
	return Vector3.new(1, 0, 0)
end

function AmusementParkCoasterLogic.AreColinearXZ(a: Vector3, b: Vector3, c: Vector3, epsilon: number): boolean
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local bc = Vector3.new(c.X - b.X, 0, c.Z - b.Z)
	if ab.Magnitude < 1e-4 or bc.Magnitude < 1e-4 then
		return true
	end
	return math.abs(ab.Unit:Cross(bc.Unit).Y) <= epsilon
end

local function addPoint(points: { Vector3 }, point: Vector3)
	local last = points[#points]
	if last and (last - point).Magnitude < 0.35 then
		return
	end
	table.insert(points, point)
end

function AmusementParkCoasterLogic.AppendVerticalLoop(
	points: { Vector3 },
	origin: Vector3,
	forward: Vector3,
	radius: number,
	samples: number
)
	local fwd = Vector3.new(forward.X, 0, forward.Z)
	if fwd.Magnitude < 0.05 then
		return
	end
	fwd = fwd.Unit
	local count = math.max(12, samples)
	for i = 1, count - 1 do
		local theta = (i / count) * math.pi * 2
		addPoint(
			points,
			origin
				+ Vector3.yAxis * (radius * (1 - math.cos(theta)))
				+ fwd * (radius * math.sin(theta))
		)
	end
end

local function addEdge(points: { Vector3 }, target: Vector3, loopRadius: number, loopSamples: number)
	local from = points[#points]
	if not from or loopRadius <= 0 then
		addPoint(points, target)
		return
	end
	local delta = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	local dist = delta.Magnitude
	if dist < loopRadius * 2.8 + 18 then
		addPoint(points, target)
		return
	end
	local travel = delta.Unit
	local entry = Vector3.new(from.X, from.Y, from.Z) + travel * (dist * 0.36)
	addPoint(points, entry)
	AmusementParkCoasterLogic.AppendVerticalLoop(points, entry, travel, loopRadius, loopSamples)
	addPoint(points, target)
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

function AmusementParkCoasterLogic.BuildLoopPoints(
	bounds: LoopBounds,
	station: Vector3,
	halfLength: number,
	cornerRadius: number,
	samplesPerCorner: number,
	loopRadius: number?,
	loopSamples: number?
): { Vector3 }
	local edge = AmusementParkCoasterLogic.NearestEdge(station, bounds)
	local rails = {
		MinX = bounds.MinX,
		MaxX = bounds.MaxX,
		MinZ = bounds.MinZ,
		MaxZ = bounds.MaxZ,
	}
	if edge == "MaxX" then
		rails.MaxX = station.X
	elseif edge == "MinX" then
		rails.MinX = station.X
	elseif edge == "MaxZ" then
		rails.MaxZ = station.Z
	else
		rails.MinZ = station.Z
	end

	local spanX = rails.MaxX - rails.MinX
	local spanZ = rails.MaxZ - rails.MinZ
	local radius = math.clamp(cornerRadius, 8, math.min(spanX, spanZ) * 0.42)
	local half = math.clamp(halfLength, 8, math.min(spanX, spanZ) * 0.35)
	local clearance = radius + half + 2
	local along = if edge == "MaxX" or edge == "MinX" then station.Z else station.X
	if edge == "MaxX" or edge == "MinX" then
		along = math.clamp(along, rails.MinZ + clearance, rails.MaxZ - clearance)
	else
		along = math.clamp(along, rails.MinX + clearance, rails.MaxX - clearance)
	end

	local height = bounds.Height
	local travel = AmusementParkCoasterLogic.EdgeTravel(edge)
	local snapped = if edge == "MaxX" or edge == "MinX"
		then Vector3.new(if edge == "MaxX" then rails.MaxX else rails.MinX, height, along)
		else Vector3.new(along, height, if edge == "MaxZ" then rails.MaxZ else rails.MinZ)
	local entry = snapped - travel * half
	local exit = snapped + travel * half

	local samples = math.max(6, samplesPerCorner)
	local invertRadius = math.max(0, loopRadius or 0)
	local invertSamples = math.max(12, loopSamples or 16)
	local points: { Vector3 } = {}

	-- Passage droit dans le bâtiment, coins arrondis, looping sur les longs côtés.
	if edge == "MaxX" then
		addPoint(points, entry)
		addPoint(points, snapped)
		addPoint(points, exit)
		addPoint(points, Vector3.new(rails.MaxX, height, rails.MaxZ - radius))
		addArc(points, rails.MaxX - radius, rails.MaxZ - radius, radius, 0, math.pi / 2, samples, height)
		addEdge(points, Vector3.new(rails.MinX + radius, height, rails.MaxZ), invertRadius, invertSamples)
		addArc(points, rails.MinX + radius, rails.MaxZ - radius, radius, math.pi / 2, math.pi, samples, height)
		addEdge(points, Vector3.new(rails.MinX, height, rails.MinZ + radius), invertRadius, invertSamples)
		addArc(points, rails.MinX + radius, rails.MinZ + radius, radius, math.pi, 3 * math.pi / 2, samples, height)
		addEdge(points, Vector3.new(rails.MaxX - radius, height, rails.MinZ), invertRadius, invertSamples)
		addArc(points, rails.MaxX - radius, rails.MinZ + radius, radius, 3 * math.pi / 2, 2 * math.pi, samples, height)
	elseif edge == "MaxZ" then
		addPoint(points, entry)
		addPoint(points, snapped)
		addPoint(points, exit)
		addPoint(points, Vector3.new(rails.MinX + radius, height, rails.MaxZ))
		addArc(points, rails.MinX + radius, rails.MaxZ - radius, radius, math.pi / 2, math.pi, samples, height)
		addEdge(points, Vector3.new(rails.MinX, height, rails.MinZ + radius), invertRadius, invertSamples)
		addArc(points, rails.MinX + radius, rails.MinZ + radius, radius, math.pi, 3 * math.pi / 2, samples, height)
		addEdge(points, Vector3.new(rails.MaxX - radius, height, rails.MinZ), invertRadius, invertSamples)
		addArc(points, rails.MaxX - radius, rails.MinZ + radius, radius, 3 * math.pi / 2, 2 * math.pi, samples, height)
		addEdge(points, Vector3.new(rails.MaxX, height, rails.MaxZ - radius), invertRadius, invertSamples)
		addArc(points, rails.MaxX - radius, rails.MaxZ - radius, radius, 0, math.pi / 2, samples, height)
	elseif edge == "MinX" then
		addPoint(points, entry)
		addPoint(points, snapped)
		addPoint(points, exit)
		addPoint(points, Vector3.new(rails.MinX, height, rails.MinZ + radius))
		addArc(points, rails.MinX + radius, rails.MinZ + radius, radius, math.pi, 3 * math.pi / 2, samples, height)
		addEdge(points, Vector3.new(rails.MaxX - radius, height, rails.MinZ), invertRadius, invertSamples)
		addArc(points, rails.MaxX - radius, rails.MinZ + radius, radius, 3 * math.pi / 2, 2 * math.pi, samples, height)
		addEdge(points, Vector3.new(rails.MaxX, height, rails.MaxZ - radius), invertRadius, invertSamples)
		addArc(points, rails.MaxX - radius, rails.MaxZ - radius, radius, 0, math.pi / 2, samples, height)
		addEdge(points, Vector3.new(rails.MinX + radius, height, rails.MaxZ), invertRadius, invertSamples)
		addArc(points, rails.MinX + radius, rails.MaxZ - radius, radius, math.pi / 2, math.pi, samples, height)
	else
		addPoint(points, entry)
		addPoint(points, snapped)
		addPoint(points, exit)
		addPoint(points, Vector3.new(rails.MaxX - radius, height, rails.MinZ))
		addArc(points, rails.MaxX - radius, rails.MinZ + radius, radius, 3 * math.pi / 2, 2 * math.pi, samples, height)
		addEdge(points, Vector3.new(rails.MaxX, height, rails.MaxZ - radius), invertRadius, invertSamples)
		addArc(points, rails.MaxX - radius, rails.MaxZ - radius, radius, 0, math.pi / 2, samples, height)
		addEdge(points, Vector3.new(rails.MinX + radius, height, rails.MaxZ), invertRadius, invertSamples)
		addArc(points, rails.MinX + radius, rails.MaxZ - radius, radius, math.pi / 2, math.pi, samples, height)
		addEdge(points, Vector3.new(rails.MinX, height, rails.MinZ + radius), invertRadius, invertSamples)
		addArc(points, rails.MinX + radius, rails.MinZ + radius, radius, math.pi, 3 * math.pi / 2, samples, height)
	end

	if #points > 1 and (points[#points] - points[1]).Magnitude < 0.35 then
		table.remove(points, #points)
	end
	return points
end

export type RideOptions = {
	HalfLength: number,
	CornerRadius: number,
	CornerSamples: number,
	BigLoopRadius: number,
	SmallLoopRadius: number,
	HighRise: number,
	LowDrop: number,
	SAmplitude: number,
	SSamples: number,
	HillPeakZ: number?,
	LoopSamples: number?,
}

local function addSCurve(points: { Vector3 }, target: Vector3, samples: number, _amplitude: number, extraHill: number)
	local from = points[#points]
	if not from then
		addPoint(points, target)
		return
	end
	local planar = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	local dist = planar.Magnitude
	if dist < 5 then
		addPoint(points, target)
		return
	end
	local along = planar.Unit
	local n = math.max(8, samples)
	for i = 1, n do
		local t = i / n
		local base = from:Lerp(target, t)
		local y = from.Y + (target.Y - from.Y) * t + extraHill * math.sin(math.pi * t)
		addPoint(points, Vector3.new(base.X, y, base.Z))
	end
end

local function addArcHeight(
	points: { Vector3 },
	centerX: number,
	centerZ: number,
	radius: number,
	startAngle: number,
	endAngle: number,
	samples: number,
	startY: number,
	endY: number
)
	for sample = 0, samples do
		local alpha = sample / samples
		local angle = startAngle + (endAngle - startAngle) * alpha
		local y = startY + (endY - startY) * alpha
		addPoint(points, Vector3.new(centerX + math.cos(angle) * radius, y, centerZ + math.sin(angle) * radius))
	end
end

local function spliceSouthSideLoop(
	points: { Vector3 },
	westX: number,
	southZ: number,
	eastX: number,
	loopRadius: number,
	loopSamples: number
): { Vector3 }
	-- Côté sud du parc : opposé à l'ascenseur, pas derrière la grande roue.
	local targetX = westX + (eastX - westX) * 0.42
	local bestI = 0
	local bestDist = math.huge
	for i = 4, #points - 3 do
		local p = points[i]
		local onSouth = math.abs(p.Z - southZ) <= 14
		local notBehindWheel = p.X > westX + 32
		local notStation = p.X < eastX - 28
		if onSouth and notBehindWheel and notStation then
			local d = math.abs(p.X - targetX)
			if d < bestDist then
				bestDist = d
				bestI = i
			end
		end
	end
	if bestI == 0 then
		return points
	end
	local origin = points[bestI]
	local nxt = points[(bestI % #points) + 1]
	local fwd = Vector3.new(nxt.X - origin.X, 0, nxt.Z - origin.Z)
	if fwd.Magnitude < 0.05 then
		return points
	end
	fwd = fwd.Unit
	local loopPts: { Vector3 } = {}
	AmusementParkCoasterLogic.AppendVerticalLoop(loopPts, origin, fwd, loopRadius, loopSamples)
	local skipUntil = bestI
	local maxAlong = loopRadius * 1.7
	for i = bestI + 1, #points do
		local along = (points[i] - origin):Dot(fwd)
		if along < maxAlong and math.abs(points[i].Z - southZ) < 18 then
			skipUntil = i
		else
			break
		end
	end
	local result: { Vector3 } = {}
	for i = 1, bestI do
		table.insert(result, points[i])
	end
	for _, p in ipairs(loopPts) do
		table.insert(result, p)
	end
	for i = skipUntil + 1, #points do
		table.insert(result, points[i])
	end
	return result
end

function AmusementParkCoasterLogic.BuildRidePoints(bounds: LoopBounds, station: Vector3, options: RideOptions): { Vector3 }
	local edge = AmusementParkCoasterLogic.NearestEdge(station, bounds)
	local rails = {
		MinX = bounds.MinX,
		MaxX = bounds.MaxX,
		MinZ = bounds.MinZ,
		MaxZ = bounds.MaxZ,
	}
	if edge == "MaxX" then
		rails.MaxX = station.X
	elseif edge == "MinX" then
		rails.MinX = station.X
	elseif edge == "MaxZ" then
		rails.MaxZ = station.Z
	else
		rails.MinZ = station.Z
	end

	local spanX = rails.MaxX - rails.MinX
	local spanZ = rails.MaxZ - rails.MinZ
	local radius = math.clamp(options.CornerRadius, 8, math.min(spanX, spanZ) * 0.38)
	local half = math.clamp(options.HalfLength, 8, math.min(spanX, spanZ) * 0.32)
	local clearance = radius + half + 2
	local along = if edge == "MaxX" or edge == "MinX" then station.Z else station.X
	if edge == "MaxX" or edge == "MinX" then
		along = math.clamp(along, rails.MinZ + clearance, rails.MaxZ - clearance)
	else
		along = math.clamp(along, rails.MinX + clearance, rails.MaxX - clearance)
	end

	local h0 = bounds.Height
	local samples = math.max(6, options.CornerSamples)
	local sSamples = math.max(10, options.SSamples)
	local travel = AmusementParkCoasterLogic.EdgeTravel(edge)
	local snapped = if edge == "MaxX" or edge == "MinX"
		then Vector3.new(if edge == "MaxX" then rails.MaxX else rails.MinX, h0, along)
		else Vector3.new(along, h0, if edge == "MaxZ" then rails.MaxZ else rails.MinZ)
	local entry = snapped - travel * half
	local exit = snapped + travel * half
	local points: { Vector3 } = {}
	addPoint(points, entry)
	addPoint(points, snapped)
	addPoint(points, exit)

	-- Rectangle arrondi, tout à plat. La colline est appliquée ensuite.
	if edge == "MaxX" then
		addSCurve(points, Vector3.new(rails.MaxX, h0, rails.MaxZ - radius), 10, 0, 0)
		addArcHeight(points, rails.MaxX - radius, rails.MaxZ - radius, radius, 0, math.pi / 2, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MinX + radius, h0, rails.MaxZ), sSamples, 0, 0)
		addArcHeight(points, rails.MinX + radius, rails.MaxZ - radius, radius, math.pi / 2, math.pi, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MinX, h0, rails.MinZ + radius), sSamples, 0, 0)
		addArcHeight(points, rails.MinX + radius, rails.MinZ + radius, radius, math.pi, 3 * math.pi / 2, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MaxX - radius, h0, rails.MinZ), sSamples, 0, 0)
		addArcHeight(points, rails.MaxX - radius, rails.MinZ + radius, radius, 3 * math.pi / 2, 2 * math.pi, samples, h0, h0)
	elseif edge == "MaxZ" then
		addSCurve(points, Vector3.new(rails.MinX + radius, h0, rails.MaxZ), 10, 0, 0)
		addArcHeight(points, rails.MinX + radius, rails.MaxZ - radius, radius, math.pi / 2, math.pi, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MinX, h0, rails.MinZ + radius), sSamples, 0, 0)
		addArcHeight(points, rails.MinX + radius, rails.MinZ + radius, radius, math.pi, 3 * math.pi / 2, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MaxX - radius, h0, rails.MinZ), sSamples, 0, 0)
		addArcHeight(points, rails.MaxX - radius, rails.MinZ + radius, radius, 3 * math.pi / 2, 2 * math.pi, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MaxX, h0, rails.MaxZ - radius), sSamples, 0, 0)
		addArcHeight(points, rails.MaxX - radius, rails.MaxZ - radius, radius, 0, math.pi / 2, samples, h0, h0)
	elseif edge == "MinX" then
		addSCurve(points, Vector3.new(rails.MinX, h0, rails.MinZ + radius), 10, 0, 0)
		addArcHeight(points, rails.MinX + radius, rails.MinZ + radius, radius, math.pi, 3 * math.pi / 2, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MaxX - radius, h0, rails.MinZ), sSamples, 0, 0)
		addArcHeight(points, rails.MaxX - radius, rails.MinZ + radius, radius, 3 * math.pi / 2, 2 * math.pi, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MaxX, h0, rails.MaxZ - radius), sSamples, 0, 0)
		addArcHeight(points, rails.MaxX - radius, rails.MaxZ - radius, radius, 0, math.pi / 2, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MinX + radius, h0, rails.MaxZ), sSamples, 0, 0)
		addArcHeight(points, rails.MinX + radius, rails.MaxZ - radius, radius, math.pi / 2, math.pi, samples, h0, h0)
	else
		addSCurve(points, Vector3.new(rails.MaxX - radius, h0, rails.MinZ), 10, 0, 0)
		addArcHeight(points, rails.MaxX - radius, rails.MinZ + radius, radius, 3 * math.pi / 2, 2 * math.pi, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MaxX, h0, rails.MaxZ - radius), sSamples, 0, 0)
		addArcHeight(points, rails.MaxX - radius, rails.MaxZ - radius, radius, 0, math.pi / 2, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MinX + radius, h0, rails.MaxZ), sSamples, 0, 0)
		addArcHeight(points, rails.MinX + radius, rails.MaxZ - radius, radius, math.pi / 2, math.pi, samples, h0, h0)
		addSCurve(points, Vector3.new(rails.MinX, h0, rails.MinZ + radius), sSamples, 0, 0)
		addArcHeight(points, rails.MinX + radius, rails.MinZ + radius, radius, math.pi, 3 * math.pi / 2, samples, h0, h0)
	end
	addSCurve(points, Vector3.new(entry.X, h0, entry.Z), 10, 0, 0)

	if #points > 1 and (points[#points] - points[1]).Magnitude < 0.35 then
		table.remove(points, #points)
	end

	-- Une seule colline : montée derrière la grande roue (ouest), puis descente.
	local hPeak = h0 + math.max(8, options.HighRise)
	local peakZ = options.HillPeakZ or 5
	local westX = rails.MinX
	for i = 4, #points do
		local p = points[i]
		local west = math.exp(-((p.X - westX) / 32) ^ 2)
		local along = math.exp(-((p.Z - peakZ) / 52) ^ 2)
		points[i] = Vector3.new(p.X, h0 + (hPeak - h0) * west * along, p.Z)
	end

	local loopRadius = math.max(0, options.BigLoopRadius)
	if loopRadius >= 8 then
		points = spliceSouthSideLoop(
			points,
			westX,
			rails.MinZ,
			rails.MaxX,
			loopRadius,
			math.max(12, options.LoopSamples or 16)
		)
	end
	return points
end

function AmusementParkCoasterLogic.AlignFrame(position: Vector3, look: Vector3, upHint: Vector3): CFrame
	if look.Magnitude < 1e-4 then
		return CFrame.new(position)
	end
	local tangent = look.Unit
	local up = if upHint.Magnitude > 1e-4 then upHint.Unit else Vector3.yAxis
	if math.abs(tangent:Dot(up)) > 0.92 then
		up = if math.abs(tangent:Dot(Vector3.yAxis)) > 0.92 then Vector3.zAxis else Vector3.yAxis
	end
	-- lookAt = rotation directe. fromMatrix(right, up, -tangent) avait det = -1 :
	-- le wagon se retrouvait à reculons ou perpendiculaire après un virage.
	return CFrame.lookAt(position, position + tangent, up)
end

local function slerpUnit(a: Vector3, b: Vector3, t: number): Vector3
	local na = if a.Magnitude > 1e-4 then a.Unit else Vector3.yAxis
	local nb = if b.Magnitude > 1e-4 then b.Unit else Vector3.yAxis
	local dot = math.clamp(na:Dot(nb), -1, 1)
	if dot > 0.9995 then
		local lerped = na:Lerp(nb, t)
		return if lerped.Magnitude > 1e-4 then lerped.Unit else na
	end
	if dot < -0.9995 then
		local axis = na:Cross(Vector3.zAxis)
		if axis.Magnitude < 0.1 then
			axis = na:Cross(Vector3.xAxis)
		end
		return (CFrame.fromAxisAngle(axis.Unit, math.pi * t) * na)
	end
	local theta = math.acos(dot)
	return (na * math.sin((1 - t) * theta) + nb * math.sin(t * theta)) / math.sin(theta)
end

function AmusementParkCoasterLogic.OrientPath(points: { Vector3 }): { CFrame }
	local cframes: { CFrame } = {}
	local count = #points
	for i, curr in ipairs(points) do
		local nextp = points[(i % count) + 1]
		local delta = nextp - curr
		if delta.Magnitude < 0.05 then
			table.insert(cframes, CFrame.new(curr))
			continue
		end
		local upHint = Vector3.yAxis
		local next2 = points[((i + 1) % count) + 1]
		local look2 = next2 - nextp
		if look2.Magnitude > 0.05 then
			local t1 = delta.Unit
			local t2 = look2.Unit
			local binormal = t1:Cross(t2)
			-- Looping vertical : le haut du wagon pointe vers le centre.
			if binormal.Magnitude > 0.25 and math.abs(binormal.Unit.Y) < 0.4 then
				local normal = t2 - t1
				if normal.Magnitude > 0.02 then
					upHint = normal.Unit
				end
			end
		end
		table.insert(cframes, AmusementParkCoasterLogic.AlignFrame(curr, delta, upHint))
	end
	return cframes
end

function AmusementParkCoasterLogic.SampleOnSegment(a: CFrame, b: CFrame, alpha: number): CFrame
	local t = math.clamp(alpha, 0, 1)
	local position = a.Position:Lerp(b.Position, t)
	local look = b.Position - a.Position
	if look.Magnitude < 0.05 then
		return AmusementParkCoasterLogic.AlignFrame(position, a.LookVector, a.UpVector)
	end
	return AmusementParkCoasterLogic.AlignFrame(position, look, slerpUnit(a.UpVector, b.UpVector, t))
end

function AmusementParkCoasterLogic.SegmentsCrossXZ(points: { Vector3 }): boolean
	local function orient(a: Vector3, b: Vector3, c: Vector3): number
		return (b.X - a.X) * (c.Z - a.Z) - (b.Z - a.Z) * (c.X - a.X)
	end
	local function crosses(a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3): boolean
		local o1 = orient(a1, a2, b1)
		local o2 = orient(a1, a2, b2)
		local o3 = orient(b1, b2, a1)
		local o4 = orient(b1, b2, a2)
		return o1 * o2 < -1e-4 and o3 * o4 < -1e-4
	end
	local count = #points
	for i = 1, count do
		local a1 = points[i]
		local a2 = points[(i % count) + 1]
		for j = i + 2, count do
			if i == 1 and j == count then
				continue
			end
			local b1 = points[j]
			local b2 = points[(j % count) + 1]
			if crosses(a1, a2, b1, b2) then
				return true
			end
		end
	end
	return false
end

return AmusementParkCoasterLogic
