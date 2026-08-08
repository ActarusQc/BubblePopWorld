--!strict
-- Corrige la caméra initiale au spawn hub (évite vue derrière les tableaux Rear Hub).
-- One-shot client-side : Scriptable brief → Custom. Pas de boucle permanente.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HubSpawnCamera = {}

local MAX_DISTANCE = 24
local CAMERA_BACK_DISTANCE = 14
local CAMERA_HEIGHT = 7
local CAMERA_LOOK_HEIGHT = 2
local HOLD_SCRIPTABLE_SEC = 0.35

local player = Players.LocalPlayer

local function findHubSpawnLocation(): BasePart?
	local world = Workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	local spawn = hub and hub:FindFirstChild("HubSpawnLocation")
	if spawn and spawn:IsA("BasePart") then
		return spawn
	end
	return nil
end

local function isNearHubSpawn(position: Vector3): boolean
	local spawn = findHubSpawnLocation()
	if not spawn then
		return false
	end
	return (position - spawn.Position).Magnitude <= MAX_DISTANCE
end

local function waitForCamera(): Camera?
	local camera = Workspace.CurrentCamera
	if camera then
		return camera
	end
	local deadline = os.clock() + 5
	while os.clock() < deadline do
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
		camera = Workspace.CurrentCamera
		if camera then
			return camera
		end
	end
	return Workspace.CurrentCamera
end

local function applySpawnCamera(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 8) :: BasePart?
	local humanoid = character:WaitForChild("Humanoid", 8) :: Humanoid?
	if not root or not humanoid then
		return
	end

	-- Laisser le personnage / spawn se stabiliser une frame.
	RunService.Heartbeat:Wait()
	if character.Parent == nil or player.Character ~= character then
		return
	end
	local camera = waitForCamera()
	if not camera then
		return
	end

	-- Au démarrage, un autre contrôleur peut brièvement laisser la caméra Scriptable.
	-- Cette correction de spawn est prioritaire et rend ensuite le contrôle à Roblox.
	-- Séquence validée manuellement : Scriptable → hold → Custom.
	local lookAt = root.Position + Vector3.new(0, CAMERA_LOOK_HEIGHT, 0)
	local desiredPosition = root.Position
		- root.CFrame.LookVector * CAMERA_BACK_DISTANCE
		+ Vector3.new(0, CAMERA_HEIGHT, 0)

	-- Ne jamais placer la caméra à l'intérieur d'un panneau ou d'un décor.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	local direction = desiredPosition - lookAt
	local obstruction = Workspace:Raycast(lookAt, direction, rayParams)
	if obstruction then
		desiredPosition = obstruction.Position + obstruction.Normal * 0.8
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = humanoid
	camera.CFrame = CFrame.lookAt(desiredPosition, lookAt)
	print("[HubSpawnCamera] safe initial camera applied")

	task.wait(HOLD_SCRIPTABLE_SEC)

	if character.Parent == nil or player.Character ~= character then
		return
	end

	camera = Workspace.CurrentCamera or camera
	camera.CameraSubject = humanoid
	camera.CameraType = Enum.CameraType.Custom
	print("[HubSpawnCamera] released to Custom")
end

local function onCharacter(character: Model)
	task.spawn(function()
		applySpawnCamera(character)
	end)
end

function HubSpawnCamera.Start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

return HubSpawnCamera
