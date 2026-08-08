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
local MODAL_WAIT_TIMEOUT_SEC = 15
local RESET_ZOOM_DISTANCE = 12
local MIN_ZOOM_DISTANCE = 6
local MAX_ZOOM_DISTANCE = 18

local player = Players.LocalPlayer
local initialCameraCompleted = false

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

	-- Le SpawnLocation manuel regarde vers les bulles (+Z), mais les panneaux sont
	-- immédiatement derrière lui. Inverser l'orientation initiale place la caméra
	-- Roblox normale du côté ouvert (escaliers) au lieu de l'enfoncer dans les panneaux.
	local initialLook = root.CFrame.LookVector
	root.CFrame = CFrame.lookAt(root.Position, root.Position - initialLook)

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

	local safeCFrame = CFrame.lookAt(desiredPosition, lookAt)
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = MIN_ZOOM_DISTANCE
	player.CameraMaxZoomDistance = MAX_ZOOM_DISTANCE
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = humanoid
	camera.CFrame = safeCFrame
	print("[HubSpawnCamera] safe initial camera applied")

	-- Le contrôleur caméra Roblox réutilisait ensuite son ancienne distance et repartait
	-- derrière les panneaux. Garder cette vue pendant le modal d'arrivée, puis libérer.
	local sawDailyModal = false
	local deadline = os.clock() + MODAL_WAIT_TIMEOUT_SEC
	while character.Parent and player.Character == character do
		local modalOpen = player:GetAttribute("DailyRewardsModalOpen") == true
		if modalOpen then
			sawDailyModal = true
		elseif sawDailyModal or os.clock() >= deadline then
			break
		end
		camera = Workspace.CurrentCamera or camera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = humanoid
		camera.CFrame = safeCFrame
		RunService.RenderStepped:Wait()
	end

	if character.Parent == nil or player.Character ~= character then
		return
	end

	camera = Workspace.CurrentCamera or camera
	camera.CameraSubject = humanoid
	camera.Focus = CFrame.new(lookAt)

	-- Réinitialiser aussi la distance mémorisée à l'intérieur du contrôleur Roblox.
	-- Une simple CameraMaxZoomDistance ne réduit pas toujours un ancien zoom déjà actif.
	player.CameraMinZoomDistance = RESET_ZOOM_DISTANCE
	player.CameraMaxZoomDistance = RESET_ZOOM_DISTANCE
	camera.CFrame = safeCFrame
	camera.CameraType = Enum.CameraType.Custom
	for _ = 1, 12 do
		RunService.RenderStepped:Wait()
		camera = Workspace.CurrentCamera or camera
		camera.CameraSubject = humanoid
		camera.Focus = CFrame.new(lookAt)
		camera.CFrame = safeCFrame
	end
	player.CameraMinZoomDistance = MIN_ZOOM_DISTANCE
	player.CameraMaxZoomDistance = MAX_ZOOM_DISTANCE
	initialCameraCompleted = true
	print("[HubSpawnCamera] released to Custom after forced zoom reset")
end

local function onCharacter(character: Model)
	if initialCameraCompleted then
		return
	end
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
