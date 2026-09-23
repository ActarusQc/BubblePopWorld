--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ElevatorCamera = {}
local player = Players.LocalPlayer

local function showUpperLanding()
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not humanoid or not root or not root:IsA("BasePart") or not camera then return end

	-- La caméra se place du côté ouvert de la plateforme plutôt que derrière
	-- le joueur, où la structure de l'ascenseur bloquait complètement la vue.
	local focus = root.Position + Vector3.new(0, 2.5, 0)
	local cameraPosition = root.Position + Vector3.new(8, 5, 11)
	camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(
		camera,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.lookAt(cameraPosition, focus) }
	):Play()

	task.delay(0.9, function()
		if Workspace.CurrentCamera ~= camera or player.Character ~= character then return end
		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Custom
	end)
end

function ElevatorCamera.Start()
	local event = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ElevatorCamera") :: RemoteEvent
	event.OnClientEvent:Connect(showUpperLanding)
end

return ElevatorCamera
