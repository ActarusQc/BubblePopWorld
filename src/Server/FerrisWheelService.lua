--!strict
-- Rojo sync marker: ferris wheel collision fixes (2026-08-18)

-- Assemble et anime la grande roue importee en trois morceaux dans Studio.
-- Les nacelles recoivent deja un siege, mais celui-ci demeure desactive tant
-- que la phase d'embarquement n'est pas branchee.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("AmusementParkConfig"))
local CollisionLogic = require(Shared:WaitForChild("AmusementParkCollisionLogic"))

local FerrisWheelService = {}
local CODE_VERSION = "ferris-collision-2026-08-19-v2"

local RUNTIME_FOLDER = "AnimatedGondolas"
local GONDOLA_COLORS = {
	Color3.fromRGB(36, 210, 255),
	Color3.fromRGB(255, 72, 77),
	Color3.fromRGB(255, 201, 46),
	Color3.fromRGB(177, 79, 255),
}

local function getPivot(instance: Instance): CFrame
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	assert(instance:IsA("BasePart"))
	return instance.CFrame
end

local function pivotTo(instance: Instance, cframe: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

local function getBounds(instance: Instance): (CFrame, Vector3)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end
	assert(instance:IsA("BasePart"))
	return instance.CFrame, instance.Size
end

local function scaleToHeight(instance: Instance, targetHeight: number)
	local _, size = getBounds(instance)
	if size.Y < 0.01 then
		return
	end
	local factor = targetHeight / size.Y
	if instance:IsA("Model") then
		instance:ScaleTo(instance:GetScale() * factor)
	elseif instance:IsA("BasePart") then
		instance.Size *= factor
	end
end

local function scaleWheel(instance: Instance, targetDiameter: number)
	local _, size = getBounds(instance)
	local diameter = math.max(size.X, size.Y)
	if diameter < 0.01 then
		return
	end
	local factor = targetDiameter / diameter
	if instance:IsA("Model") then
		instance:ScaleTo(instance:GetScale() * factor)
	elseif instance:IsA("BasePart") then
		instance.Size *= factor
	end
end

local function placeBounds(instance: Instance, desiredBounds: CFrame): CFrame
	local currentBounds = select(1, getBounds(instance))
	local newPivot = desiredBounds * currentBounds:Inverse() * getPivot(instance)
	pivotTo(instance, newPivot)
	return desiredBounds:Inverse() * newPivot
end

local function configureParts(instance: Instance, canCollide: boolean)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = canCollide
			descendant.CanTouch = false
			descendant.CanQuery = true
			descendant.CollisionGroup = "Default"
			if canCollide and descendant:IsA("MeshPart") then
				descendant.DoubleSided = true
				pcall(function()
					descendant.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
				end)
			end
		end
	end
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = canCollide
		instance.CanTouch = false
		instance.CollisionGroup = "Default"
		if canCollide and instance:IsA("MeshPart") then
			instance.DoubleSided = true
			pcall(function()
				instance.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
			end)
		end
	end
end

local function setVisible(instance: Instance, visible: boolean)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = if visible then 0 else 1
		end
	end
	if instance:IsA("BasePart") then
		instance.Transparency = if visible then 0 else 1
	end
end

local function tint(instance: Instance, color: Color3)
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
	if instance:IsA("BasePart") then
		instance.Color = color
	end
end

local function findChild(parent: Instance, names: { string }): Instance?
	for _, name in names do
		local found = parent:FindFirstChild(name)
		if found and (found:IsA("Model") or found:IsA("BasePart")) then
			return found
		end
	end
	return nil
end

local function dismount(player: Player, seat: Seat, exitCFrame: CFrame)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or seat.Occupant ~= humanoid then return end
	humanoid.Sit = false
	seat.Disabled = true
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = exitCFrame
	end
	task.delay(0.5, function()
		if seat.Parent then seat.Disabled = false end
	end)
end

function FerrisWheelService.Start()
	local park = Workspace:WaitForChild("ParcAttractions", 10)
	if not park then
		warn("[FerrisWheel] ParcAttractions introuvable")
		return
	end

	local root = park:FindFirstChild("GrandeRoue", true) or park:FindFirstChild("granderoue", true)
	if not root then
		warn("[FerrisWheel] dossier GrandeRoue introuvable")
		return
	end
	local generated = park:FindFirstChild(Config.GeneratedFolderName)
	local editorPreview = generated and generated:FindFirstChild("GrandeRouePreview")
	if editorPreview then editorPreview:Destroy() end

	local base = findChild(root, { "Base", "base" })
	local wheel = findChild(root, { "Roue", "roue", "Wheel" })
	local gondolaSource = findChild(root, { "NacelleModele", "Nacelle", "Gondola" })
	if not base or not wheel or not gondolaSource then
		warn("[FerrisWheel] Base, Roue ou NacelleModele manquant")
		return
	end

	local oldRuntime = root:FindFirstChild(RUNTIME_FOLDER)
	if oldRuntime then
		oldRuntime:Destroy()
	end
	local runtime = Instance.new("Folder")
	runtime.Name = RUNTIME_FOLDER
	runtime.Parent = root

	local settings = Config.FerrisWheel
	local placement = Config.Placements.GrandeRoue
	local configuredRootCF = CFrame.new(placement.Position) * CFrame.Angles(0, math.rad(placement.Yaw), 0)
	local rootCF = configuredRootCF
	local hubCF = rootCF * CFrame.new(0, settings.HubHeight, 0)
	local hubHeight = settings.HubHeight
	if placement.PreserveStudioTransform == true then
		local baseBounds, baseSize = getBounds(base)
		local wheelBounds = select(1, getBounds(wheel))
		local groundPosition = Vector3.new(baseBounds.Position.X, baseBounds.Position.Y - baseSize.Y / 2, baseBounds.Position.Z)
		-- La rotation du pivot racine est plus fiable que celle du bounding box
		-- pour les modèles image-vers-3D importés par Tripo.
		local rootRotation = getPivot(base).Rotation
		rootCF = CFrame.new(groundPosition) * rootRotation
		hubCF = CFrame.new(wheelBounds.Position) * rootRotation
		hubHeight = math.max(1, wheelBounds.Position.Y - groundPosition.Y)
	end
	local studioDelta = rootCF.Position - configuredRootCF.Position
	local horizontalDelta = Vector3.new(studioDelta.X, 0, studioDelta.Z)

	-- La base (marches + quai) colle au mesh visible. La roue tournante reste
	-- non solide pour ne pas éjecter le joueur.
	configureParts(base, CollisionLogic.FerrisBaseShouldCollide())
	configureParts(wheel, CollisionLogic.FerrisSpinningWheelShouldCollide())
	configureParts(gondolaSource, false)
	if placement.PreserveStudioTransform ~= true then
		scaleToHeight(base, settings.BaseHeight)
		placeBounds(base, rootCF * CFrame.new(0, settings.BaseHeight / 2, 0))
		scaleWheel(wheel, settings.WheelDiameter)
	end
	local wheelPivotOffset = placeBounds(wheel, hubCF)

	local template = gondolaSource:Clone()
	setVisible(gondolaSource, false)

	-- Les marches du mesh Tripo ne possèdent pas une collision assez fidèle.
	-- Des marches rectangulaires invisibles suivent exactement l'accès visuel :
	-- contrairement à une rampe inclinée, elles ne peuvent pas être traversées.
	local stairBottom = Vector3.new(-297, rootCF.Position.Y + 0.4, 5) + horizontalDelta
	local stairCount = 10
	local stepRun = 1.9
	local stepRise = 0.9
	for index = 1, stairCount do
		local height = index * stepRise
		local step = Instance.new("Part")
		step.Name = string.format("FerrisWheelCollisionStep%02d", index)
		step.Size = Vector3.new(stepRun + 0.12, height, 12)
		step.CFrame = CFrame.new(stairBottom.X - (index - 0.5) * stepRun, stairBottom.Y + height / 2, stairBottom.Z)
		step.Anchored = true
		step.CanCollide = true
		step.CanTouch = false
		step.Transparency = 1
		step.Parent = runtime
	end
	local rampTop = Vector3.new(stairBottom.X - stairCount * stepRun - 4, stairBottom.Y + stairCount * stepRise, stairBottom.Z)
	local topLanding = Instance.new("Part")
	topLanding.Name = "FerrisWheelTopLanding"
	topLanding.Size = Vector3.new(34, 1.2, 22)
	topLanding.CFrame = CFrame.new(-310 + horizontalDelta.X, rampTop.Y, rampTop.Z)
	topLanding.Anchored = true
	topLanding.CanCollide = true
	topLanding.Transparency = 1
	topLanding.Parent = runtime

	-- Le mesh décoratif Tripo doit rester non solide pour ne pas fermer les
	-- marches. Un noyau simple empêche toutefois le joueur de traverser la base
	-- et de se retrouver à l'intérieur de la grande roue.
	local baseBounds, baseSize = getBounds(base)
	local baseBottomY = baseBounds.Position.Y - baseSize.Y / 2
	-- Seulement la zone sous le quai est fermée. Le palier supérieur invisible
	-- reste libre et collidable pour l'embarquement.
	local blockerHeight = math.clamp(rampTop.Y - baseBottomY - 2, 4, 9)
	local coreBlocker = Instance.new("Part")
	coreBlocker.Name = "FerrisWheelCoreCollision"
	coreBlocker.Size = Vector3.new(
		math.clamp(baseSize.X * 0.48, 12, 30),
		blockerHeight,
		math.clamp(baseSize.Z * 0.58, 12, 24)
	)
	coreBlocker.CFrame = CFrame.new(baseBounds.Position.X, baseBottomY + blockerHeight / 2, baseBounds.Position.Z) * rootCF.Rotation
	coreBlocker.Anchored = true
	coreBlocker.CanCollide = true
	coreBlocker.CanTouch = false
	coreBlocker.CanQuery = true
	coreBlocker.Transparency = 1
	coreBlocker.Parent = runtime

	type GondolaState = { Instance: Instance, PivotOffset: CFrame, AngleOffset: number, Seat: Seat, Hanger: BasePart }
	local gondolas: { GondolaState } = {}
	for index = 1, settings.GondolaCount do
		local gondola = template:Clone()
		gondola.Name = string.format("Gondola%02d", index)
		gondola.Parent = runtime
		configureParts(gondola, false)
		for _, descendant in gondola:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanQuery = false
			end
		end
		scaleToHeight(gondola, settings.GondolaHeight)
		tint(gondola, GONDOLA_COLORS[((index - 1) % #GONDOLA_COLORS) + 1])
		local colorAccent = Instance.new("Highlight")
		colorAccent.Name = "GondolaColorAccent"
		colorAccent.FillColor = GONDOLA_COLORS[((index - 1) % #GONDOLA_COLORS) + 1]
		colorAccent.FillTransparency = 0.42
		colorAccent.OutlineColor = GONDOLA_COLORS[((index - 1) % #GONDOLA_COLORS) + 1]
		colorAccent.OutlineTransparency = 0.08
		colorAccent.DepthMode = Enum.HighlightDepthMode.Occluded
		colorAccent.Parent = gondola

		local angleOffset = ((index - 1) / settings.GondolaCount) * math.pi * 2
		local attachment = rootCF * CFrame.new(
			math.cos(angleOffset) * settings.GondolaRadius,
			hubHeight + math.sin(angleOffset) * settings.GondolaRadius,
			0
		)
		local cabinPosition = attachment.Position - Vector3.new(0, settings.HangerLength + settings.GondolaHeight / 2, 0)
		local desired = CFrame.new(cabinPosition) * rootCF.Rotation
		local pivotOffset = placeBounds(gondola, desired)
		local hanger = Instance.new("Part")
		hanger.Name = "GondolaHanger"
		hanger.Size = Vector3.new(0.45, settings.HangerLength, 0.45)
		hanger.Anchored = true
		hanger.CanCollide = false
		hanger.Material = Enum.Material.Metal
		hanger.Color = Color3.fromRGB(230, 238, 255)
		hanger.CFrame = CFrame.new(attachment.Position - Vector3.new(0, settings.HangerLength / 2, 0))
		hanger.Parent = runtime

		local seat = Instance.new("Seat")
		seat.Name = "RideSeat"
		seat.Size = Vector3.new(2.4, 0.5, 2.2)
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanTouch = false
		seat.Disabled = false
		seat:SetAttribute("FerrisWheelSeat", true)
		seat.CFrame = desired * CFrame.new(0, -0.8, 0)
		seat.Parent = gondola
		table.insert(gondolas, { Instance = gondola, PivotOffset = pivotOffset, AngleOffset = angleOffset, Seat = seat, Hanger = hanger })
	end
	template:Destroy()

	local boarding = Instance.new("Part")
	boarding.Name = "FerrisWheelBoarding"
	boarding.Size = Vector3.new(12, 1, 10)
	boarding.CFrame = CFrame.new(
		settings.BoardingPosition.X + horizontalDelta.X,
		rampTop.Y + 1.6,
		settings.BoardingPosition.Z + horizontalDelta.Z
	)
	boarding.Anchored = true
	boarding.Transparency = 1
	boarding.CanCollide = false
	boarding.Parent = runtime
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ride"
	prompt.ObjectText = "Ferris Wheel"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = boarding
	-- Sortie sur le sol, assez loin de la base pour ne jamais tomber sous le quai.
	local exitCFrame = CFrame.new(-292 + horizontalDelta.X, rootCF.Position.Y + 4, 20 + horizontalDelta.Z)
	for _, state in gondolas do
		local exitPrompt = Instance.new("ProximityPrompt")
		exitPrompt.Name = "ExitFerrisWheel"
		exitPrompt.ActionText = "Exit"
		exitPrompt.ObjectText = "Ferris Wheel"
		exitPrompt.KeyboardKeyCode = Enum.KeyCode.E
		exitPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		exitPrompt.HoldDuration = 0.1
		exitPrompt.MaxActivationDistance = 8
		exitPrompt.RequiresLineOfSight = false
		exitPrompt.Parent = state.Seat
		exitPrompt.Triggered:Connect(function(player)
			dismount(player, state.Seat, exitCFrame)
		end)
	end
	prompt.Triggered:Connect(function(player)
		local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid then return end
		local nearest = nil
		local nearestDistance = math.huge
		for _, state in gondolas do
			if state.Seat.Occupant == nil then
				local distance = (state.Seat.Position - boarding.Position).Magnitude
				if distance < nearestDistance then
					nearest = state.Seat
					nearestDistance = distance
				end
			end
		end
		if nearest then
			local character = player.Character
			local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
			if playerRoot and playerRoot:IsA("BasePart") then
				playerRoot.AssemblyLinearVelocity = Vector3.zero
				playerRoot.AssemblyAngularVelocity = Vector3.zero
				playerRoot.CFrame = nearest.CFrame * CFrame.new(0, 2.4, 0)
			end
			-- Sit après le déplacement pour que la nacelle ne puisse pas quitter le
			-- joueur entre l'activation du prompt et la création du joint de siège.
			task.defer(function()
				if nearest.Parent and nearest.Occupant == nil then nearest:Sit(humanoid) end
			end)
			-- Sortie de sécurité après un tour complet si le joueur n'utilise pas E/X.
			task.delay(settings.RotationSeconds, function()
				if nearest.Parent then dismount(player, nearest, exitCFrame) end
			end)
		end
	end)

	local elapsed = 0
	local accumulator = 0
	local interval = 1 / settings.UpdateRate
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		accumulator += deltaTime
		if accumulator < interval then
			return
		end
		accumulator %= interval

		local angle = (elapsed / settings.RotationSeconds) * math.pi * 2
		pivotTo(wheel, hubCF * CFrame.Angles(0, 0, -angle) * wheelPivotOffset)
		for _, state in gondolas do
			local gondolaAngle = state.AngleOffset - angle
			local attachment = rootCF * CFrame.new(
				math.cos(gondolaAngle) * settings.GondolaRadius,
				hubHeight + math.sin(gondolaAngle) * settings.GondolaRadius,
				0
			)
			local cabinPosition = attachment.Position - Vector3.new(0, settings.HangerLength + settings.GondolaHeight / 2, 0)
			local desired = CFrame.new(cabinPosition) * rootCF.Rotation
			-- La nacelle se deplace avec la roue, mais reste toujours droite.
			pivotTo(state.Instance, desired * state.PivotOffset)
			state.Hanger.CFrame = CFrame.new(attachment.Position - Vector3.new(0, settings.HangerLength / 2, 0))
		end
	end)

	print(string.format("[FerrisWheel] grande roue active avec %d nacelles (%s)", #gondolas, CODE_VERSION))
end

return FerrisWheelService
