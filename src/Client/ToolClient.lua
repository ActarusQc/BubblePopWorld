--!strict
-- Activation outils : souris, tactile et manette (Xbox RT = ButtonR2).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local toolActivate = Remotes.Event("ToolActivate")

local ToolClient = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

local ACTION_NAME = "BPW_ActivateTool"
local lastActivate = 0
local ACTIVATE_GAP = 0.12

local clickSound = Instance.new("Sound")
clickSound.Name = "ToolClick"
clickSound.SoundId = "rbxassetid://9114224704"
clickSound.Volume = 0.35
clickSound.Parent = SoundService

local function equippedTool(): Tool?
	local char = player.Character
	if not char then return nil end
	local tool = char:FindFirstChildOfClass("Tool")
	return tool
end

local function screenRay(): Ray
	local viewport = camera.ViewportSize
	local mouse = UserInputService:GetMouseLocation()
	local screenX, screenY = mouse.X, mouse.Y
	if UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		screenX, screenY = viewport.X / 2, viewport.Y / 2
	end
	return camera:ViewportPointToRay(screenX, screenY)
end

local function aimPosition(range: number): Vector3
	local ray = screenRay()
	params.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * range, params)
	return if result then result.Position else ray.Origin + ray.Direction * range
end

local function fireTool(tool: Tool)
	local now = os.clock()
	if now - lastActivate < ACTIVATE_GAP then return end
	lastActivate = now

	local range = tool:GetAttribute("Range") or 60
	local selfCentered = tool:GetAttribute("SelfCentered") == true
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Ailes : RT/clic = mettre ou retirer (serveur)
	if tool:GetAttribute("ToolId") == "Ailes" then
		if not root then return end
		clickSound:Play()
		toolActivate:FireServer(tool.Name, root.Position)
		return
	end

	if selfCentered then
		if not root then return end
		clickSound:Play()
		toolActivate:FireServer(tool.Name, root.Position)
		return
	end

	clickSound:Play()
	toolActivate:FireServer(tool.Name, aimPosition(range))
end

local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function hook(tool: Tool)
	if hooked[tool] then return end
	hooked[tool] = true
	tool.Activated:Connect(function()
		fireTool(tool)
	end)
end

local function onAction(_name: string, state: Enum.UserInputState, _input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local tool = equippedTool()
	if not tool then
		return Enum.ContextActionResult.Pass
	end
	fireTool(tool)
	return Enum.ContextActionResult.Sink
end

function ToolClient.Start()
	local function watch(container: Instance)
		container.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then hook(child) end
		end)
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then hook(child) end
		end
	end

	watch(player:WaitForChild("Backpack"))
	player.CharacterAdded:Connect(function(char)
		watch(char)
	end)
	if player.Character then watch(player.Character) end

	-- Xbox / manette : RT (ButtonR2) + X (ButtonX) pour utiliser l'outil équipé
	ContextActionService:BindAction(
		ACTION_NAME,
		onAction,
		false,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonX,
		Enum.UserInputType.MouseButton1
	)
end

return ToolClient
