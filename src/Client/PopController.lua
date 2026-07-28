--!strict
-- Détection d'atterrissage sur une bulle : rebond immédiat, puis éclatement.
-- Avec Ailes : vol horizontal sur N bulles + pop des bulles sous le joueur.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local ToolDefs = require(Shared.ToolDefs)

local player = Players.LocalPlayer
local popRequest = Remotes.Event("PopRequest")

local PopController = {}
local lastBounce = 0

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

type FlightState = {
	dir: Vector3,
	start: Vector3,
	maxDist: number,
	speed: number,
	popped: { [string]: boolean },
	endsAt: number,
}

local flight: FlightState? = nil

local function squash(part: BasePart)
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if not mesh then return end
	local home = Config.Bubble.MeshScale
	mesh.Scale = Vector3.new(home.X * 1.2, home.Y * 0.35, home.Z * 1.2)
	TweenService:Create(mesh, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = home,
	}):Play()
end

local function hasWings(): boolean
	return player:GetAttribute("HasWings") == true
end

local function wingCellCount(): number
	local def = ToolDefs.List.Ailes
	return (def and def.WingCells) or 5
end

local function cellKey(zoneId: string, x: number, z: number): string
	return zoneId .. ":" .. x .. "_" .. z
end

local function tryPopBubble(part: BasePart, state: FlightState?)
	local x = part:GetAttribute("CellX")
	local z = part:GetAttribute("CellZ")
	if typeof(x) ~= "number" or typeof(z) ~= "number" then return end
	if part:GetAttribute("Alive") ~= true then return end

	local zoneId = part:GetAttribute("ZoneId")
	if typeof(zoneId) ~= "string" then
		zoneId = "ClassicZone"
	end

	if state then
		local key = cellKey(zoneId, x, z)
		if state.popped[key] then return end
		state.popped[key] = true
	end

	squash(part)
	popRequest:FireServer(x, z, zoneId)
end

local function beginWingFlight(root: BasePart, takeoff: BasePart)
	local cells = wingCellCount()
	local maxDist = Config.Grid.Spacing * cells
	local duration = Config.Bubble.WingFlightSeconds or 0.9
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	flight = {
		dir = flat,
		start = root.Position,
		maxDist = maxDist,
		speed = maxDist / duration,
		popped = {},
		endsAt = os.clock() + duration + 0.15,
	}

	tryPopBubble(takeoff, flight)

	-- Impulsion nette : montée + avance (Humanoid ne doit pas écraser ça tout de suite)
	root.AssemblyLinearVelocity = Vector3.new(flat.X * flight.speed, 55, flat.Z * flight.speed)
end

local function updateWingFlight(root: BasePart, hum: Humanoid, char: Model): boolean
	local state = flight
	if not state then return false end

	local now = os.clock()
	local offset = root.Position - state.start
	local horiz = Vector3.new(offset.X, 0, offset.Z).Magnitude

	if horiz >= state.maxDist or now >= state.endsAt then
		flight = nil
		return false
	end

	-- Maintient le vol : avance constante, reste en l'air jusqu'à ~85% du trajet
	local progress = horiz / state.maxDist
	local vy = root.AssemblyLinearVelocity.Y
	if progress < 0.85 then
		vy = math.max(vy, 12)
	elseif progress < 0.95 then
		vy = math.max(vy, 2)
	end

	root.AssemblyLinearVelocity = Vector3.new(state.dir.X * state.speed, vy, state.dir.Z * state.speed)
	hum:ChangeState(Enum.HumanoidStateType.Freefall)

	params.FilterDescendantsInstances = { char }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -14, 0), params)
	if result and result.Instance:IsA("BasePart") then
		local part = result.Instance
		if part:GetAttribute("CellX") ~= nil and part:GetAttribute("Alive") == true then
			tryPopBubble(part, state)
		end
	end

	return true
end

function PopController.Start()
	RunService.Heartbeat:Connect(function()
		local char = player.Character
		if not char then return end

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then
			flight = nil
			return
		end

		-- Vol en cours (ailes) : priorité sur le rebond normal
		if updateWingFlight(root, hum, char) then
			return
		end

		local velocity = root.AssemblyLinearVelocity
		if velocity.Y > 1 then return end

		local now = os.clock()
		if now - lastBounce < Config.Bubble.BounceCooldown then return end

		params.FilterDescendantsInstances = { char }
		local result = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
		if not result then return end

		local part = result.Instance
		if not part or not part:IsA("BasePart") then return end
		if part:GetAttribute("CellX") == nil or part:GetAttribute("CellZ") == nil then return end
		if part:GetAttribute("Alive") ~= true then return end
		if not part.CanCollide or part.Transparency >= 1 then return end
		if result.Distance > Config.Bubble.ContactDistance then return end

		lastBounce = now

		if hasWings() then
			beginWingFlight(root, part)
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
			return
		end

		local power = hum.JumpPower * Config.Bubble.BounceMultiplier
		if hum.Jump or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			power *= Config.Bubble.ChargedBounceMultiplier
		end
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, power, velocity.Z)
		hum:ChangeState(Enum.HumanoidStateType.Freefall)

		squash(part)
		local x, z = part:GetAttribute("CellX"), part:GetAttribute("CellZ")
		local zoneId = part:GetAttribute("ZoneId")
		if typeof(zoneId) ~= "string" then
			zoneId = "ClassicZone"
		end
		task.delay(Config.Bubble.PopDelay, function()
			if part.Parent and part:GetAttribute("Alive") == true then
				popRequest:FireServer(x, z, zoneId)
			end
		end)
	end)
end

return PopController
