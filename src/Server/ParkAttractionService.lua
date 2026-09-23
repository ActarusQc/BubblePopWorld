--!strict
-- Rojo sync marker: park ride interaction fixes (2026-08-18)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("AmusementParkConfig"))
local CoasterLogic = require(Shared:WaitForChild("AmusementParkCoasterLogic"))
local WorldTourLogic = require(Shared:WaitForChild("WorldTourLogic"))
local ZoneDefs = require(Shared:WaitForChild("ZoneDefs"))
local L10n = require(Shared:WaitForChild("LocalizationStrings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local CarouselRide = require(script.Parent:WaitForChild("CarouselRide"))
local ZoneAccess = require(script.Parent:WaitForChild("ZoneAccess"))

local ParkAttractionService = {}
local CODE_VERSION = "park-rides-2026-08-23-v14"

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local elevatorCameraEvent = remotes:FindFirstChild("ElevatorCamera") :: RemoteEvent?
if not elevatorCameraEvent then
	elevatorCameraEvent = Instance.new("RemoteEvent")
	elevatorCameraEvent.Name = "ElevatorCamera"
	elevatorCameraEvent.Parent = remotes
end


local function promptOn(part: BasePart, action: string, object: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ParkPrompt"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

local function dismount(player: Player, seat: Seat, exitCFrame: CFrame, reenableSeat: boolean?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or seat.Occupant ~= humanoid then return end
	humanoid.Sit = false
	seat.Disabled = true
	local seatWeld = seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = exitCFrame
	end
	if reenableSeat ~= false then
		task.delay(0.5, function()
			if seat.Parent then seat.Disabled = false end
		end)
	end
end

local function setupElevators(generated: Instance)
	local ground = generated:FindFirstChild("ElevatorGroundPad")
	local high = generated:FindFirstChild("ElevatorHighPad")
	if not (ground and ground:IsA("BasePart") and high and high:IsA("BasePart")) then return end
	-- Le bâtisseur synchronise déjà ces deux pads avec le modèle Studio. Ne pas
	-- les recalculer ici : l'ancien second calcul annulait le déplacement manuel
	-- de l'ascenseur et plaçait parfois la commande dans le mesh Tripo.
	-- Le pad supérieur est solide : c'est le palier d'arrivée. Une commande placée
	-- en son centre se retrouve donc sous le plancher où le joueur se tient, et le
	-- test de ligne de vue la masque. On accroche la commande à un repère
	-- non collidable à hauteur de torse au-dessus du pad.
	local function promptAnchor(pad: BasePart): BasePart
		local stale = pad:FindFirstChild("ParkPrompt")
		if stale then stale:Destroy() end
		local existing = pad:FindFirstChild("ElevatorPromptAnchor")
		local anchor: BasePart
		if existing and existing:IsA("BasePart") then
			anchor = existing
		else
			if existing then existing:Destroy() end
			local created = Instance.new("Part")
			created.Name = "ElevatorPromptAnchor"
			created.Size = Vector3.new(1, 1, 1)
			created.Transparency = 1
			created.CanCollide = false
			created.CanTouch = false
			created.CanQuery = false
			created.Anchored = true
			created.Parent = pad
			anchor = created
		end
		anchor.CFrame = pad.CFrame + Vector3.new(0, 3, 0)
		return anchor
	end

	local busy: { [Player]: boolean } = {}
	local function connect(from: BasePart, to: BasePart, action: string, label: string, adjustCamera: boolean, distance: number?, landOffset: number?)
		local prompt = promptOn(promptAnchor(from), action, label)
		prompt.MaxActivationDistance = distance or 10
		prompt.RequiresLineOfSight = false
		prompt.Triggered:Connect(function(player)
			if busy[player] then return end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then return end
			busy[player] = true
			root.CFrame = to.CFrame + Vector3.new(0, landOffset or 4, 0)
			if adjustCamera then
				elevatorCameraEvent:FireClient(player)
			end
			task.delay(1, function() busy[player] = nil end)
		end)
	end
	connect(ground, high, "Go Up", "Sky Elevator", true)
	connect(high, ground, "Go Down", "Ground Floor", false)

	local coasterGround = generated:FindFirstChild("CoasterElevatorGroundPad", true)
	local coasterHigh = generated:FindFirstChild("CoasterElevatorHighPad", true)
	if coasterGround and coasterGround:IsA("BasePart") and coasterHigh and coasterHigh:IsA("BasePart") then
		connect(coasterGround, coasterHigh, "Go Up", L10n.WorldTourName, false, 8, 3)
		connect(coasterHigh, coasterGround, "Go Down", "Ground Floor", false, 5, 3)
	end

	local pairsByZone: { [string]: { Ground: BasePart?, High: BasePart? } } = {}
	for _, desc in ipairs(generated:GetDescendants()) do
		if desc:IsA("BasePart") then
			local zoneId = desc:GetAttribute("TourElevatorPair")
			local role = desc:GetAttribute("TourElevatorRole")
			if type(zoneId) == "string" and type(role) == "string" then
				local pair = pairsByZone[zoneId]
				if not pair then
					pair = { Ground = nil, High = nil }
					pairsByZone[zoneId] = pair
				end
				if role == "Ground" then
					pair.Ground = desc
				elseif role == "High" then
					pair.High = desc
				end
			end
		end
	end
	for zoneId, pair in pairs(pairsByZone) do
		if pair.Ground and pair.High then
			connect(pair.Ground, pair.High, "Go Up", L10n.WorldTourName, false, 10, 3)
			connect(pair.High, pair.Ground, "Go Down", "Ground Floor", false, 8, 3)
		end
	end
end


type Segment = { A: CFrame, B: CFrame, Length: number, Start: number }

local function findWagonTemplate(park: Instance): Instance?
	for _, name in ipairs({ "WagonModele", "Wagon", "wagon", "TrainCar", "RollerCoasterCar" }) do
		local found = park:FindFirstChild(name, true)
		if found and (found:IsA("Model") or found:IsA("BasePart")) then return found end
	end
	return nil
end

local function configureWagon(instance: Instance)
	local function configure(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
	end
	if instance:IsA("BasePart") then configure(instance) end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then configure(descendant) end
	end
end

local function setWagonVisible(instance: Instance, visible: boolean)
	if instance:IsA("BasePart") then instance.Transparency = if visible then 0 else 1 end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.Transparency = if visible then 0 else 1 end
	end
end

local function scaleWagon(instance: Instance, targetLength: number)
	local size = if instance:IsA("Model") then select(2, instance:GetBoundingBox()) else (instance :: BasePart).Size
	local length = math.max(size.X, size.Z)
	if length < 0.05 then return end
	local factor = targetLength / length
	if instance:IsA("Model") then
		instance:ScaleTo(instance:GetScale() * factor)
	else
		(instance :: BasePart).Size *= factor
	end
end

local function wagonFacingCorrection(instance: Instance): CFrame
	if not instance:IsA("Model") then
		return CFrame.new()
	end
	local nose = instance:FindFirstChild("Nose", true)
	if nose and nose:IsA("BasePart") then
		local localNose = instance:GetPivot():PointToObjectSpace(nose.Position)
		if math.abs(localNose.X) > math.abs(localNose.Z) + 0.5 then
			return CFrame.Angles(0, if localNose.X > 0 then math.rad(90) else math.rad(-90), 0)
		end
		if localNose.Z > 0.5 then
			return CFrame.Angles(0, math.pi, 0)
		end
		return CFrame.new()
	end
	local _, size = instance:GetBoundingBox()
	if size.X > size.Z * 1.12 then
		return CFrame.Angles(0, math.rad(-90), 0)
	end
	return CFrame.new()
end

local function wagonPivotTo(instance: Instance, cf: CFrame)
	if instance:IsA("Model") then instance:PivotTo(cf) else (instance :: BasePart).CFrame = cf end
end

local function fallbackWagonTemplate(): Model
	local model = Instance.new("Model")
	model.Name = "TemporaryWagonTemplate"
	local function piece(name: string, size: Vector3, cf: CFrame, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local body = piece("Body", Vector3.new(4.8, 1.5, 5.8), CFrame.new(0, 0, 0), Color3.fromRGB(239, 55, 67))
	piece("Nose", Vector3.new(4.4, 1.1, 1.2), CFrame.new(0, 0.25, -3.1), Color3.fromRGB(255, 194, 36))
	piece("SeatBack", Vector3.new(4.1, 2.4, 0.6), CFrame.new(0, 1.45, 1.75), Color3.fromRGB(35, 82, 156))
	for _, x in ipairs({ -2.25, 2.25 }) do
		piece("GoldRail", Vector3.new(0.3, 1.7, 4.6), CFrame.new(x, 1.05, 0), Color3.fromRGB(255, 206, 53))
	end
	model.PrimaryPart = body
	model.WorldPivot = body.CFrame
	return model
end

local function collectNodePoints(nodes: { Instance }): { Vector3 }
	local points: { Vector3 } = {}
	for _, node in ipairs(nodes) do
		if node:IsA("BasePart") then
			table.insert(points, node.Position)
		end
	end
	return points
end

local function collectTourStops(generated: Instance, points: { Vector3 }): { WorldTourLogic.StopSpec }
	local stops: { WorldTourLogic.StopSpec } = {}
	local seen: { [string]: boolean } = {}
	local function consider(part: BasePart, zoneId: string, displayName: string)
		if seen[zoneId] then
			return
		end
		seen[zoneId] = true
		table.insert(stops, {
			ZoneId = zoneId,
			DisplayName = displayName,
			Position = part.Position,
			Distance = WorldTourLogic.DistanceToPoint(points, part.Position),
		})
	end
	for _, desc in ipairs(generated:GetDescendants()) do
		if desc:IsA("BasePart") then
			local zoneId = desc:GetAttribute("TourZoneId")
			if type(zoneId) == "string" and (desc.Name == "CoasterBoarding" or string.sub(desc.Name, 1, 12) == "TourStation_") then
				local display = desc:GetAttribute("TourDisplayName")
				consider(desc, zoneId, if type(display) == "string" then display else zoneId)
			end
		end
	end
	table.sort(stops, function(a, b)
		return a.Distance < b.Distance
	end)
	return stops
end

local function clampOntoPart(part: BasePart, x: number, z: number, inset: number): (number, number)
	local hx = math.max(4, part.Size.X / 2 - inset)
	local hz = math.max(4, part.Size.Z / 2 - inset)
	return math.clamp(x, part.Position.X - hx, part.Position.X + hx), math.clamp(z, part.Position.Z - hz, part.Position.Z + hz)
end

local function landingCFrame(generated: Instance, zoneId: string, fallback: CFrame): CFrame
	if zoneId == "AmusementPark" then
		local highPad = generated:FindFirstChild("CoasterElevatorHighPad", true)
		if highPad and highPad:IsA("BasePart") then
			return highPad.CFrame + Vector3.new(0, 3, 0)
		end
	end
	local wanted = WorldTourLogic.GroundLanding(zoneId, Config.Origin.Y)
	local gameZones = Workspace:FindFirstChild("GameZones")
	local zoneFolder = gameZones and gameZones:FindFirstChild(zoneId)
	if zoneFolder then
		local floor = zoneFolder:FindFirstChild("ZoneFloor", true) or zoneFolder:FindFirstChild("PlayFloor", true)
		if floor and floor:IsA("BasePart") then
			local x, z = clampOntoPart(floor, wanted.X, wanted.Z, 10)
			local topY = floor.Position.Y + floor.Size.Y / 2
			return CFrame.new(x, topY + 3.4, z)
		end
	end
	local landing = generated:FindFirstChild("TourLanding_" .. zoneId, true)
	if landing and landing:IsA("BasePart") then
		local x, z = clampOntoPart(landing, wanted.X, wanted.Z, 4)
		return CFrame.new(x, landing.Position.Y + landing.Size.Y / 2 + 3.2, z)
	end
	return CFrame.new(wanted.X, wanted.Y, wanted.Z)
end

local function notifyTourLocked(player: Player, zoneId: string, displayName: string)
	local required = ZoneDefs.GetRequiredLevel(zoneId)
	local level = ZoneAccess.GetPlayerLevel(player)
	Remotes.Event("Announce"):FireClient(
		player,
		string.format(L10n.WorldTourLockedFmt, required, displayName, level, required),
		"zone_locked"
	)
end

local function buildCoasterTrain(generated: Instance)
	local coaster = generated:FindFirstChild("RollerCoaster")
	local nodesFolder = coaster and coaster:FindFirstChild("CoasterNodes")
	if not nodesFolder then return nil end
	local nodes = nodesFolder:GetChildren()
	table.sort(nodes, function(a, b) return a.Name < b.Name end)
	if #nodes < 2 then return nil end

	local firstNode = nodes[1]
	local stationPos = if firstNode:IsA("BasePart") then firstNode.Position else Vector3.new(-193, 26, 30)
	local boarding = generated:FindFirstChild("CoasterBoarding", true)
	if boarding and boarding:IsA("BasePart") then
		stationPos = Vector3.new(boarding.Position.X, stationPos.Y, boarding.Position.Z)
	end
	local logicPoints, _, logicStops = WorldTourLogic.BuildRidePoints(stationPos, WorldTourLogic.RideOptionsFromConfig(stationPos.Y))
	local nodePoints = collectNodePoints(nodes)
	local pathPoints = if WorldTourLogic.ReachesOtherZones(logicPoints) then logicPoints else nodePoints
	local pMinX, pMaxX, pMinZ, pMaxZ = WorldTourLogic.PathExtents(pathPoints)
	print(("[ParkAttractions] circuit X[%.0f..%.0f] Z[%.0f..%.0f] (%d pts)"):format(pMinX, pMaxX, pMinZ, pMaxZ, #pathPoints))
	if not WorldTourLogic.ReachesOtherZones(pathPoints) then
		warn("[ParkAttractions] circuit parc seulement — les rails ne sortent pas")
	end
	local cframes = CoasterLogic.OrientPath(pathPoints)
	if #cframes < 2 then
		return nil
	end

	local segments: { Segment } = {}
	local total = 0
	for i, cf in ipairs(cframes) do
		local nextCf = cframes[(i % #cframes) + 1]
		local length = (nextCf.Position - cf.Position).Magnitude
		table.insert(segments, { A = cf, B = nextCf, Length = length, Start = total })
		total += length
	end
	if total <= 0 then return nil end

	local stops = collectTourStops(generated, pathPoints)
	if #logicStops > #stops then
		stops = logicStops
	end
	if #stops == 0 then
		local created = Instance.new("Part")
		created.Name = "CoasterBoarding"
		created.Size = Vector3.new(16, 10, 16)
		local first = nodes[1]
		created.CFrame = if first:IsA("BasePart") then first.CFrame else CFrame.new()
		created.Anchored = true
		created.Transparency = 1
		created.CanCollide = false
		created.Parent = coaster
		created:SetAttribute("TourZoneId", "AmusementPark")
		table.insert(stops, {
			ZoneId = "AmusementPark",
			DisplayName = Config.DisplayName,
			Position = created.Position,
			Distance = 0,
		})
	end

	local park = generated.Parent
	local wagonTemplate = park and findWagonTemplate(park)
	local usingFallback = false
	if not wagonTemplate then
		warn("[ParkAttractions] WagonModele absent: train temporaire utilisé; importez le FBX sous ParcAttractions/WagonModele")
		wagonTemplate = fallbackWagonTemplate()
		usingFallback = true
	end
	configureWagon(wagonTemplate)
	setWagonVisible(wagonTemplate, false)
	local facingFix = wagonFacingCorrection(wagonTemplate)

	type CarState = { Body: Instance, Seat: Seat, ExitAnchor: BasePart? }
	type TrainState = {
		Cars: { CarState },
		Index: number,
	}
	local trains: { TrainState } = {}
	local trainCount = math.max(1, Config.Coaster.TrainCount)
	for trainIndex = 1, trainCount do
		local train = Instance.new("Model")
		train.Name = if trainIndex == 1 then "CoasterTrain" else ("CoasterTrain" .. trainIndex)
		train.Parent = coaster
		local cars: { CarState } = {}
		for i = 1, Config.Coaster.CarCount do
			local car = wagonTemplate:Clone()
			car.Name = "Car" .. i
			configureWagon(car)
			scaleWagon(car, Config.Coaster.CarLength)
			setWagonVisible(car, true)
			car.Parent = train
			local seat = Instance.new("Seat")
			seat.Name = "RideSeat"
			seat.Size = Vector3.new(2.8, 0.6, 2.4)
			seat.Transparency = 1
			seat.Anchored = true
			seat.CanCollide = false
			seat.CFrame = CFrame.new(0, -1000, 0)
			seat.Parent = train
			table.insert(cars, { Body = car, Seat = seat, ExitAnchor = nil })
		end
		table.insert(trains, { Cars = cars, Index = trainIndex })
	end
	if usingFallback then wagonTemplate:Destroy() end

	local phases, cycle = WorldTourLogic.BuildSchedule(stops, total, Config.Coaster.Speed, Config.Coaster.StationDwell)
	local currentElapsed = 0
	local sitAt: { [Player]: number } = {}
	local boardedStop: { [Player]: number } = {}
	local justLeft: { [Player]: boolean } = {}

	local function sample(distance: number): CFrame
		distance %= total
		for _, segment in ipairs(segments) do
			if distance <= segment.Start + segment.Length then
				local alpha = math.clamp((distance - segment.Start) / math.max(segment.Length, 0.001), 0, 1)
				return CoasterLogic.SampleOnSegment(segment.A, segment.B, alpha)
			end
		end
		return segments[1].A
	end

	local function trainSample(elapsed: number, trainIndex: number): (number, boolean, number?)
		local offset = WorldTourLogic.TrainOffset(trainIndex, trainCount, cycle)
		return WorldTourLogic.SampleSchedule(elapsed, phases, cycle, total, offset)
	end

	local function resolveExit(player: Player, distance: number): (WorldTourLogic.StopSpec?, boolean)
		local nearest = WorldTourLogic.NearestStop(stops, distance, total)
		if not nearest then
			return nil, false
		end
		if ZoneAccess.CanPlayerEnter(player, nearest.ZoneId) then
			return nearest, true
		end
		return nearest, false
	end

	local function leaveRide(player: Player, seat: Seat, stop: WorldTourLogic.StopSpec?)
		justLeft[player] = true
		sitAt[player] = nil
		boardedStop[player] = nil
		local dest = if stop
			then landingCFrame(generated, stop.ZoneId, CFrame.new(WorldTourLogic.GroundLanding(stop.ZoneId, Config.Origin.Y)))
			else landingCFrame(generated, "AmusementPark", CFrame.new(WorldTourLogic.GroundLanding("AmusementPark", Config.Origin.Y)))
		dismount(player, seat, dest)
		task.delay(1.2, function()
			justLeft[player] = nil
		end)
	end

	for _, train in ipairs(trains) do
		for _, car in ipairs(train.Cars) do
			local exitAnchor = Instance.new("Part")
			exitAnchor.Name = "ExitAnchor"
			exitAnchor.Size = Vector3.new(1, 1, 1)
			exitAnchor.Transparency = 1
			exitAnchor.Anchored = true
			exitAnchor.CanCollide = false
			exitAnchor.CanTouch = false
			exitAnchor.CanQuery = true
			exitAnchor.Parent = car.Seat.Parent
			car.ExitAnchor = exitAnchor
			local exitPrompt = promptOn(exitAnchor, L10n.WorldTourExit, L10n.WorldTourName)
			exitPrompt.Name = "ExitCoaster"
			exitPrompt.MaxActivationDistance = 10
			exitPrompt.Enabled = false
			exitPrompt.Triggered:Connect(function(player)
				local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
				if not humanoid then return end
				local seated = humanoid.SeatPart
				if not (seated and seated:IsA("Seat")) then return end
				local lead = trainSample(currentElapsed, train.Index)
				local stop, allowed = resolveExit(player, lead)
				if not allowed or not stop then
					if stop then
						notifyTourLocked(player, stop.ZoneId, stop.DisplayName)
					end
					return
				end
				leaveRide(player, seated, stop)
			end)
			car.Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				exitPrompt.Enabled = car.Seat.Occupant ~= nil
			end)
		end
	end

	type StationPrompt = { Part: BasePart, Prompt: ProximityPrompt, Stop: WorldTourLogic.StopSpec }
	local stationPrompts: { StationPrompt } = {}
	for _, stop in ipairs(stops) do
		local partName = if stop.ZoneId == "AmusementPark" then "CoasterBoarding" else ("TourStation_" .. stop.ZoneId)
		local station = generated:FindFirstChild(partName, true)
		if not (station and station:IsA("BasePart")) then
			continue
		end
		local existingPrompt = station:FindFirstChildWhichIsA("ProximityPrompt")
		if existingPrompt then existingPrompt:Destroy() end
		local ridePrompt = promptOn(station, L10n.WorldTourRide, L10n.WorldTourName)
		ridePrompt.MaxActivationDistance = 16
		ridePrompt.RequiresLineOfSight = false
		ridePrompt.Enabled = true
		ridePrompt.Triggered:Connect(function(player)
			if justLeft[player] then return end
			local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
			if not humanoid or humanoid.SeatPart then return end
			for _, train in ipairs(trains) do
				local _lead, dwelling, stopIndex = trainSample(currentElapsed, train.Index)
				if not dwelling or not stopIndex or not stops[stopIndex] or stops[stopIndex].ZoneId ~= stop.ZoneId then
					continue
				end
				for _, car in ipairs(train.Cars) do
					if car.Seat.Occupant == nil then
						car.Seat:Sit(humanoid)
						sitAt[player] = currentElapsed
						boardedStop[player] = stopIndex
						return
					end
				end
			end
		end)
		table.insert(stationPrompts, { Part = station, Prompt = ridePrompt, Stop = stop })
	end

	return function(elapsed: number)
		currentElapsed = elapsed
		local dwellingZones: { [string]: boolean } = {}
		for _, train in ipairs(trains) do
			local lead, dwelling, stopIndex = trainSample(elapsed, train.Index)
			if dwelling and stopIndex and stops[stopIndex] then
				dwellingZones[stops[stopIndex].ZoneId] = true
				for _, car in ipairs(train.Cars) do
					local occupant = car.Seat.Occupant
					if occupant then
						local player = Players:GetPlayerFromCharacter(occupant.Parent)
						if
							player
							and sitAt[player]
							and boardedStop[player] == stopIndex
							and (elapsed - sitAt[player]) > Config.Coaster.StationDwell + 2
						then
							if ZoneAccess.CanPlayerEnter(player, stops[stopIndex].ZoneId) then
								leaveRide(player, car.Seat, stops[stopIndex])
							end
						end
					end
				end
			end
			for i, car in ipairs(train.Cars) do
				local cf = sample(lead - (i - 1) * Config.Coaster.CarSpacing)
					* CFrame.Angles(0, math.rad(Config.Coaster.WagonYaw), 0)
					* facingFix
				wagonPivotTo(car.Body, cf)
				car.Seat.CFrame = cf * CFrame.new(0, 1.35, 0)
				if car.ExitAnchor then
					car.ExitAnchor.CFrame = cf * CFrame.new(0, 2.2, 0)
				end
			end
		end
		for _, station in ipairs(stationPrompts) do
			local parked = dwellingZones[station.Stop.ZoneId] == true
			station.Prompt.ActionText = if parked then L10n.WorldTourRide else L10n.WorldTourWait
			station.Prompt.Enabled = true
		end
	end
end

local function setupFallRecovery()
	RunService.Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and root.Position.Y < -18
				and root.Position.X < -155 and root.Position.X > -365
				and math.abs(root.Position.Z) < 105 then
				root.CFrame = CFrame.new(-170, 12, 0)
			end
		end
	end)
end

function ParkAttractionService.Start()
	local park = Workspace:WaitForChild("ParcAttractions", 10)
	local generated = park and park:WaitForChild("GeneratedLayout", 10)
	if not generated then
		warn("[ParkAttractions] GeneratedLayout introuvable")
		return
	end
	local elevatorOk, elevatorError = pcall(setupElevators, generated)
	if not elevatorOk then warn("[ParkAttractions] ascenseur désactivé: " .. tostring(elevatorError)) end
	local carouselOk, updateCarousel = pcall(CarouselRide.Bind, park, generated)
	if not carouselOk then
		warn("[ParkAttractions] carrousel désactivé: " .. tostring(updateCarousel))
		updateCarousel = nil
	elseif updateCarousel == nil then
		warn("[ParkAttractions] carrousel Bind a renvoyé nil")
	end
	local coasterOk, updateCoaster = pcall(buildCoasterTrain, generated)
	if not coasterOk then
		warn("[ParkAttractions] train désactivé: " .. tostring(updateCoaster))
		updateCoaster = nil
	end
	if updateCarousel then updateCarousel(0) end
	if updateCoaster then updateCoaster(0) end
	setupFallRecovery()

	local elapsed, accumulator = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		accumulator += dt
		if accumulator < 1 / 30 then return end
		accumulator %= 1 / 30
		if updateCarousel then updateCarousel(elapsed) end
		if updateCoaster then updateCoaster(elapsed) end
	end)
	print(("[ParkAttractions] ascenseur, carrousel et world tour actifs (%s / %s)"):format(CODE_VERSION, CarouselRide.CODE_VERSION))
end

return ParkAttractionService
