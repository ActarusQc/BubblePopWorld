--!strict
-- Rotation du manège à sa position Studio actuelle (y compris après un déplacement).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollisionLogic = require(Shared:WaitForChild("AmusementParkCollisionLogic"))

local CarouselRide = {}
CarouselRide.CODE_VERSION = "carousel-ride-2026-08-19-v3"

local function isInsideGenerated(inst: Instance, generated: Instance): boolean
	return inst == generated or inst:IsDescendantOf(generated)
end

local function instanceBounds(inst: Instance): (CFrame?, Vector3?)
	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	end
	local minY, maxY = math.huge, -math.huge
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local any = false
	local function accumulate(part: BasePart)
		any = true
		local p = part.Position
		local h = part.Size / 2
		minX = math.min(minX, p.X - h.X)
		maxX = math.max(maxX, p.X + h.X)
		minY = math.min(minY, p.Y - h.Y)
		maxY = math.max(maxY, p.Y + h.Y)
		minZ = math.min(minZ, p.Z - h.Z)
		maxZ = math.max(maxZ, p.Z + h.Z)
	end
	if inst:IsA("BasePart") then
		accumulate(inst)
	end
	for _, descendant in ipairs(inst:GetDescendants()) do
		if descendant:IsA("BasePart") then
			accumulate(descendant)
		end
	end
	if not any then
		return nil, nil
	end
	return CFrame.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2),
		Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
end

local function collectParts(root: Instance): { BasePart }
	local parts = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Point d'ancrage du parc : sert à écarter les manèges restés à l'origine du monde.
local function parkReference(park: Instance): Vector3?
	local regions = park:FindFirstChild("BubbleRegions")
	local ground = regions and regions:FindFirstChild("Ground")
	if ground and ground:IsA("BasePart") then
		return ground.Position
	end
	for _, name in ipairs({ "GrandeRoue", "Chapiteau2", "Chapiteau", "EntreeParc", "Ascenceur" }) do
		local anchor = park:FindFirstChild(name)
		if anchor then
			local cf = instanceBounds(anchor)
			if cf then
				return cf.Position
			end
		end
	end
	return nil
end

local function findVisual(park: Instance, generated: Instance): Instance?
	-- Plusieurs modèles peuvent porter un nom de manège (import Tripo + version
	-- générée). On retient celui qui se trouve réellement dans le parc.
	local reference = parkReference(park)
	local named: Instance? = nil
	local namedDistance = math.huge
	for _, child in ipairs(park:GetChildren()) do
		if child ~= generated
			and CollisionLogic.MatchesCarouselName(child.Name)
			and CollisionLogic.IsCarouselSourceClass(child.ClassName) then
			local cf = instanceBounds(child)
			local distance = if reference and cf then (cf.Position - reference).Magnitude else 0
			if distance < namedDistance then
				named = child
				namedDistance = distance
			end
		end
	end
	if named then
		return named
	end
	for _, candidate in ipairs(park:GetDescendants()) do
		if isInsideGenerated(candidate, generated) then
			continue
		end
		if CollisionLogic.IsKnownNonCarouselAsset(candidate.Name) then
			continue
		end
		if candidate:GetAttribute("AnimatedAttraction") == "Carousel"
			or candidate:GetAttribute("ParkImportedAsset") == "Carousel" then
			return candidate
		end
		if CollisionLogic.MatchesCarouselName(candidate.Name)
			and CollisionLogic.IsCarouselSourceClass(candidate.ClassName) then
			return candidate
		end
	end
	local best: Instance? = nil
	local bestScore = -1
	for _, candidate in ipairs(park:GetDescendants()) do
		if isInsideGenerated(candidate, generated) then
			continue
		end
		if CollisionLogic.IsKnownNonCarouselAsset(candidate.Name) then
			continue
		end
		if not (candidate:IsA("Model") or candidate:IsA("Folder") or candidate:IsA("MeshPart")) then
			continue
		end
		local _, size = instanceBounds(candidate)
		if size and CollisionLogic.LooksLikeCarouselBounds(size) then
			local score = math.min(size.X, size.Z)
			if score > bestScore then
				bestScore = score
				best = candidate
			end
		end
	end
	if best then
		return best
	end
	for _, child in ipairs(generated:GetChildren()) do
		if CollisionLogic.MatchesCarouselName(child.Name)
			or child:GetAttribute("AnimatedAttraction") == "Carousel" then
			return child
		end
	end
	return nil
end

local function installHull(parent: Instance, center: CFrame, diameter: number, height: number): BasePart
	for _, name in ipairs({ "CarouselCollisionBody", "CarouselCollisionDeck" }) do
		local old = parent:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local body = Instance.new("Part")
	body.Name = "CarouselCollisionBody"
	body.Shape = Enum.PartType.Cylinder
	body.Anchored = true
	body.CanCollide = true
	body.CanTouch = false
	body.CanQuery = true
	body.Transparency = 1
	body.Size = Vector3.new(height, diameter, diameter)
	body.CFrame = center * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	body:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	body.Parent = parent
	return body
end

local function promptOn(part: BasePart, action: string, object: string, distance: number): ProximityPrompt
	local existing = part:FindFirstChild("ParkPrompt")
	if existing then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ParkPrompt"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	prompt.Parent = part
	return prompt
end

local function dismount(player: Player, seat: Seat, exitCFrame: CFrame)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or seat.Occupant ~= humanoid then
		return
	end
	humanoid.Sit = false
	local seatWeld = seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = exitCFrame
	end
end

local function collectSeats(visual: Instance, center: CFrame, diameter: number): { Seat }
	local seats: { Seat } = {}
	local function consider(inst: Instance)
		if inst:IsA("Seat") or inst:IsA("VehicleSeat") then
			local seat = inst :: Seat
			seat.Anchored = true
			seat.CanCollide = false
			seat.CanTouch = false
			seat.Disabled = false
			seat.Transparency = 1
			table.insert(seats, seat)
		end
	end
	consider(visual)
	for _, descendant in ipairs(visual:GetDescendants()) do
		consider(descendant)
	end
	if #seats > 0 then
		return seats
	end
	local parent: Instance = visual
	local radius = math.max(8, diameter * 0.36)
	for i = 1, 12 do
		local angle = (i - 1) * (math.pi * 2 / 12) + math.pi / 12
		local seat = Instance.new("Seat")
		seat.Name = "CarouselSeat"
		seat.Size = Vector3.new(2.2, 0.5, 2.2)
		seat.CFrame = center * CFrame.new(math.cos(angle) * radius, 5.25, math.sin(angle) * radius) * CFrame.Angles(0, -angle + math.pi / 2, 0)
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanTouch = false
		seat.Disabled = false
		seat.Transparency = 1
		seat:SetAttribute("CarouselControlledSeat", true)
		seat.Parent = parent
		table.insert(seats, seat)
	end
	return seats
end

local function setupBoarding(generated: Instance, visual: Instance, center: CFrame, diameter: number, hull: BasePart)
	local oldPad = generated:FindFirstChild("CarouselBoarding")
	if oldPad then
		oldPad:Destroy()
	end
	local rim = diameter / 2 + 4
	local pad = Instance.new("Part")
	pad.Name = "CarouselBoarding"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = true
	pad.Transparency = 1
	pad.Size = Vector3.new(12, 10, 10)
	pad.CFrame = center * CFrame.new(0, 4, -rim)
	pad:SetAttribute("GeneratedBy", "AmusementParkBuilder")
	pad.Parent = generated

	local seats = collectSeats(visual, center, diameter)
	local exitCFrame = pad.CFrame * CFrame.new(0, 2, -4)
	for _, seat in ipairs(seats) do
		local exitPrompt = promptOn(seat, "Exit", "Bubble Carousel", 8)
		exitPrompt.Name = "ExitCarousel"
		exitPrompt.Triggered:Connect(function(player: Player)
			dismount(player, seat, exitCFrame)
		end)
	end

	local function onRide(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid then
			return
		end
		local fromPosition = if playerRoot and playerRoot:IsA("BasePart") then playerRoot.Position else pad.Position
		local nearest: Seat? = nil
		local nearestDistance = math.huge
		for _, seat in ipairs(seats) do
			if seat.Parent and seat.Occupant == nil then
				local distance = (seat.Position - fromPosition).Magnitude
				if distance < nearestDistance then
					nearest = seat
					nearestDistance = distance
				end
			end
		end
		if not nearest then
			return
		end
		if playerRoot and playerRoot:IsA("BasePart") then
			playerRoot.AssemblyLinearVelocity = Vector3.zero
			playerRoot.AssemblyAngularVelocity = Vector3.zero
			playerRoot.CFrame = nearest.CFrame * CFrame.new(0, 2.4, 0)
		end
		local chosen = nearest
		task.defer(function()
			if chosen.Parent and chosen.Occupant == nil then
				chosen:Sit(humanoid)
			end
		end)
	end

	local rideDistance = math.max(18, diameter / 2 + 8)
	promptOn(pad, "Ride", "Bubble Carousel", rideDistance).Triggered:Connect(onRide)
	promptOn(hull, "Ride", "Bubble Carousel", rideDistance).Triggered:Connect(onRide)
end

function CarouselRide.Bind(park: Instance, generated: Instance): (number) -> ()
	for _, child in ipairs(generated:GetChildren()) do
		if child:GetAttribute("TemporaryParkClone") == true then
			child:Destroy()
		elseif CollisionLogic.MatchesCarouselName(child.Name)
			and child:GetAttribute("GeneratedBy") ~= "AmusementParkBuilder" then
			child.Parent = park
		end
	end

	local names = {}
	for _, child in ipairs(park:GetChildren()) do
		table.insert(names, child.ClassName .. ":" .. child.Name)
	end
	print("[CarouselRide] enfants ParcAttractions: " .. table.concat(names, ", "))

	local reference = parkReference(park)
	print("[CarouselRide] ancrage parc: " .. (if reference then tostring(reference) else "introuvable"))
	for _, child in ipairs(park:GetChildren()) do
		if child ~= generated and CollisionLogic.MatchesCarouselName(child.Name) then
			local cf, size = instanceBounds(child)
			if cf and size then
				print(("[CarouselRide] candidat %s pos=(%.0f, %.0f, %.0f) taille=(%.0f, %.0f, %.0f) distance=%s"):format(
					child.Name,
					cf.Position.X,
					cf.Position.Y,
					cf.Position.Z,
					size.X,
					size.Y,
					size.Z,
					if reference then ("%.0f"):format((cf.Position - reference).Magnitude) else "?"
				))
			else
				print(("[CarouselRide] candidat %s sans géométrie"):format(child.Name))
			end
		end
	end

	local visual = findVisual(park, generated)
	if not visual then
		warn("[CarouselRide] aucun manège trouvé après déplacement Studio")
		return function() end
	end

	local cf, size = instanceBounds(visual)
	if not cf or not size then
		warn("[CarouselRide] bounding box impossible: " .. visual:GetFullName())
		return function() end
	end

	-- Centre = bounding box actuelle, jamais l'ancien placement config.
	local center = CFrame.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
	local diameter = math.max(size.X, size.Z) * CollisionLogic.CarouselHullDiameterScale()
	local height = math.clamp(size.Y * 0.55, 8, 16)
	local hull = installHull(generated, center, diameter, height)

	if visual:IsA("Model") then
		local model = visual :: Model
		model:SetAttribute("AnimatedAttraction", "Carousel")
		model.PrimaryPart = nil
		model.WorldPivot = center
		local parts = collectParts(model)
		for _, name in ipairs({ "CarouselCollisionBody", "CarouselCollisionDeck", "CarouselCollisionHull" }) do
			local old = model:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
		for _, part in ipairs(parts) do
			if part.Parent then
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
			end
		end
		print(("[CarouselRide] %s visuel=%s pieces=%d centre=(%.1f, %.1f, %.1f) pivot"):format(
			CarouselRide.CODE_VERSION,
			model:GetFullName(),
			#parts,
			center.Position.X,
			center.Position.Y,
			center.Position.Z
		))
		setupBoarding(generated, model, center, diameter, hull)
		return function(elapsed: number)
			if model.Parent then
				model:PivotTo(center * CFrame.Angles(0, elapsed * 0.45, 0))
			end
		end
	end

	local rotatingParts: { { Part: BasePart, Offset: CFrame } } = {}
	for _, part in ipairs(collectParts(visual)) do
		part.Anchored = true
		table.insert(rotatingParts, { Part = part, Offset = center:ToObjectSpace(part.CFrame) })
	end
	print(("[CarouselRide] %s visuel=%s pieces=%d centre=(%.1f, %.1f, %.1f) parts"):format(
		CarouselRide.CODE_VERSION,
		visual:GetFullName(),
		#rotatingParts,
		center.Position.X,
		center.Position.Y,
		center.Position.Z
	))
	setupBoarding(generated, visual, center, diameter, hull)
	return function(elapsed: number)
		local rotated = center * CFrame.Angles(0, elapsed * 0.45, 0)
		for _, state in ipairs(rotatingParts) do
			if state.Part.Parent then
				state.Part.CFrame = rotated * state.Offset
			end
		end
	end
end

return CarouselRide
