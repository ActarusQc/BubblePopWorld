--!strict
-- Activation outils : souris, tactile et manette (Xbox RT = ButtonR2).
-- Une seule entrée : ActivateEquippedTool() — PC / manette / bouton mobile.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ToolDefs = require(Shared.ToolDefs)

local player = Players.LocalPlayer
local toolActivate = Remotes.Event("ToolActivate")

local ToolClient = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

local ACTION_NAME = "BPW_ActivateTool"
local lastActivate = 0
local ACTIVATE_GAP = 0.12

local BTN_BG = Color3.fromRGB(22, 28, 40)
local BTN_BG_PRESS = Color3.fromRGB(14, 18, 28)
local BTN_BG_DISABLED = Color3.fromRGB(36, 40, 50)
local BTN_STROKE = Color3.fromRGB(120, 200, 255)
local BTN_STROKE_OK = Color3.fromRGB(120, 255, 170)
local BTN_STROKE_BAD = Color3.fromRGB(255, 90, 100)

local clickSound = Instance.new("Sound")
clickSound.Name = "ToolClick"
clickSound.SoundId = "rbxassetid://9114224704"
clickSound.Volume = 0.35
clickSound.Parent = SoundService

local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local equipConns: { [Tool]: { RBXScriptConnection } } = setmetatable({}, { __mode = "k" }) :: any

local gui: ScreenGui? = nil
local actionBtn: TextButton? = nil
local iconLabel: TextLabel? = nil
local iconImage: ImageLabel? = nil
local labelText: TextLabel? = nil
local cooldownFill: Frame? = nil
local reticle: Frame? = nil
local reticleDot: Frame? = nil
local activeTool: Tool? = nil
local cooldownUntil = 0
local crosshairConn: RBXScriptConnection? = nil
local hasValidTarget = true

local function camera(): Camera?
	return Workspace.CurrentCamera
end

local function equippedTool(): Tool?
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Tool")
end

local function toolSupportsMobile(tool: Tool): boolean
	if tool:GetAttribute("SupportsMobileAction") == true then
		return true
	end
	local id = tool:GetAttribute("ToolId")
	if type(id) == "string" then
		local def = ToolDefs.Get(id)
		if def and def.SupportsMobileAction == true then
			return true
		end
	end
	return false
end

local function toolRequiresTarget(tool: Tool): boolean
	if tool:GetAttribute("RequiresTarget") == true then
		return true
	end
	if tool:GetAttribute("SelfCentered") == true then
		return false
	end
	local id = tool:GetAttribute("ToolId")
	if type(id) == "string" then
		local def = ToolDefs.Get(id)
		if def then
			return def.RequiresTarget == true
		end
	end
	return false
end

local function centerScreenRay(): Ray?
	local cam = camera()
	if not cam then
		return nil
	end
	local viewport = cam.ViewportSize
	return cam:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
end

local function mouseOrCenterRay(): Ray?
	local cam = camera()
	if not cam then
		return nil
	end
	local viewport = cam.ViewportSize
	local mouse = UserInputService:GetMouseLocation()
	local screenX, screenY = mouse.X, mouse.Y
	if (UserInputService.GamepadEnabled and not UserInputService.MouseEnabled)
		or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
	then
		screenX, screenY = viewport.X * 0.5, viewport.Y * 0.5
	end
	return cam:ViewportPointToRay(screenX, screenY)
end

local function aimPosition(range: number, useCenter: boolean): Vector3?
	local ray = if useCenter then centerScreenRay() else mouseOrCenterRay()
	if not ray then
		return nil
	end
	params.FilterDescendantsInstances = { player.Character }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * range, params)
	return if result then result.Position else ray.Origin + ray.Direction * range
end

local function isBubbleHit(result: RaycastResult?): boolean
	if not result then
		return false
	end
	local part = result.Instance
	if not part then
		return false
	end
	if part:GetAttribute("BPW_Bubble") == true then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("BPW_Bubble") == true then
		return true
	end
	-- Grille : noms / parents usuels
	local parent = part.Parent
	if parent and (parent.Name == "Bubbles" or parent.Name == "BubbleGrid" or parent:GetAttribute("BPW_Zone") ~= nil) then
		return part:IsA("BasePart") and part.Shape == Enum.PartType.Ball
			or (part:IsA("BasePart") and part.Size.Y < part.Size.X)
	end
	return false
end

--- Point d'entrée unique PC / manette / mobile.
local function ActivateEquippedTool(fromMobileButton: boolean?)
	local tool = equippedTool()
	if not tool then
		return
	end

	local now = os.clock()
	if now - lastActivate < ACTIVATE_GAP then
		return
	end
	if now < cooldownUntil then
		return
	end
	lastActivate = now

	local range = (tool:GetAttribute("Range") :: any) or 60
	if type(range) ~= "number" then
		range = 60
	end
	local selfCentered = tool:GetAttribute("SelfCentered") == true
	local requiresTarget = toolRequiresTarget(tool)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	if tool:GetAttribute("ToolId") == "Ailes" then
		if not root then
			return
		end
		clickSound:Play()
		toolActivate:FireServer(tool.Name, root.Position)
		return
	end

	if selfCentered and not requiresTarget then
		if not root then
			return
		end
		clickSound:Play()
		local cd = tool:GetAttribute("Cooldown")
		if type(cd) == "number" and cd > 0 then
			cooldownUntil = now + cd
		end
		toolActivate:FireServer(tool.Name, root.Position)
		return
	end

	-- Outils ciblés : centre caméra sur mobile / bouton, souris sinon
	local useCenter = fromMobileButton == true
		or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
		or (UserInputService.GamepadEnabled and not UserInputService.MouseEnabled)
	local target = aimPosition(range, useCenter)
	if not target then
		return
	end

	if requiresTarget and fromMobileButton then
		local ray = centerScreenRay()
		if not ray then
			return
		end
		params.FilterDescendantsInstances = { player.Character }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * range, params)
		if not isBubbleHit(hit) then
			-- Feedback léger : pas d'envoi serveur
			if actionBtn then
				local stroke = actionBtn:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = BTN_STROKE_BAD
					task.delay(0.2, function()
						if stroke.Parent then
							stroke.Color = if hasValidTarget then BTN_STROKE_OK else BTN_STROKE
						end
					end)
				end
			end
			return
		end
		if hit then
			target = hit.Position
		end
	end

	clickSound:Play()
	local cd = tool:GetAttribute("Cooldown")
	if type(cd) == "number" and cd > 0 then
		cooldownUntil = now + cd
	end
	toolActivate:FireServer(tool.Name, target)
end

ToolClient.ActivateEquippedTool = function()
	ActivateEquippedTool(false)
end

local function setButtonPressed(pressed: boolean)
	local btn = actionBtn
	if not btn then
		return
	end
	btn.BackgroundColor3 = if pressed then BTN_BG_PRESS else BTN_BG
	local scale = btn:FindFirstChild("UIScale") :: UIScale?
	if scale then
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = if pressed then 0.92 else 1 }):Play()
	end
end

local function layoutMobileChrome()
	local btn = actionBtn
	local ret = reticle
	local cam = camera()
	if not btn or not cam then
		return
	end

	local vp = cam.ViewportSize
	local inset = GuiService:GetGuiInset()
	local shortSide = math.min(vp.X, vp.Y)
	local size = math.clamp(math.floor(shortSide * 0.11), 64, 84)
	local landscape = vp.X > vp.Y
	local rightPad = if landscape then 22 else 16
	-- Au-dessus / à gauche du bouton Jump Roblox (~90–120 px du coin)
	local jumpClearance = size + (if landscape then 28 else 40)
	local bottomPad = jumpClearance + math.max(8, inset.Y > 0 and 4 or 8)

	btn.Size = UDim2.fromOffset(size, size)
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -rightPad, 1, -bottomPad)

	if ret then
		local r = math.clamp(math.floor(shortSide * 0.035), 14, 22)
		ret.Size = UDim2.fromOffset(r, r)
		ret.Position = UDim2.new(0.5, 0, 0.5, 0)
	end
end

local function refreshMobileChrome()
	local btn = actionBtn
	local ret = reticle
	if not btn or not gui then
		return
	end

	local tool = activeTool
	local showTouch = UserInputService.TouchEnabled
	local show = showTouch and tool ~= nil and toolSupportsMobile(tool)

	btn.Visible = show
	btn.Active = show
	gui.Enabled = true

	if ret then
		ret.Visible = show and tool ~= nil and toolRequiresTarget(tool)
	end

	if not show or not tool then
		if crosshairConn then
			crosshairConn:Disconnect()
			crosshairConn = nil
		end
		return
	end

	local label = tool:GetAttribute("MobileActionLabel")
	if type(label) ~= "string" or label == "" then
		local id = tool:GetAttribute("ToolId")
		local def = if type(id) == "string" then ToolDefs.Get(id) else nil
		label = (def and def.MobileActionLabel) or "USE"
	end
	if labelText then
		labelText.Text = tostring(label)
	end

	local imageId = tool:GetAttribute("IconImage")
	local glyph = tool:GetAttribute("IconGlyph")
	if type(glyph) ~= "string" or glyph == "" then
		local id = tool:GetAttribute("ToolId")
		local def = if type(id) == "string" then ToolDefs.Get(id) else nil
		glyph = (def and def.IconGlyph) or "✦"
	end

	if iconImage and iconLabel then
		if type(imageId) == "string" and imageId ~= "" then
			iconImage.Image = imageId
			iconImage.Visible = true
			iconLabel.Visible = false
		else
			iconImage.Visible = false
			iconLabel.Text = tostring(glyph)
			iconLabel.Visible = true
		end
	end

	layoutMobileChrome()

	if toolRequiresTarget(tool) then
		if not crosshairConn then
			crosshairConn = RunService.RenderStepped:Connect(function()
				local current = activeTool
				if not current or not toolRequiresTarget(current) then
					return
				end
				local range = (current:GetAttribute("Range") :: any) or 60
				if type(range) ~= "number" then
					range = 60
				end
				local ray = centerScreenRay()
				if not ray then
					return
				end
				params.FilterDescendantsInstances = { player.Character }
				local hit = Workspace:Raycast(ray.Origin, ray.Direction * range, params)
				hasValidTarget = isBubbleHit(hit)
				if reticleDot then
					reticleDot.BackgroundColor3 = if hasValidTarget then BTN_STROKE_OK else Color3.fromRGB(230, 240, 255)
				end
				local stroke = actionBtn and actionBtn:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = if hasValidTarget then BTN_STROKE_OK else BTN_STROKE
				end
				if actionBtn then
					local onCd = os.clock() < cooldownUntil
					actionBtn.BackgroundColor3 = if onCd then BTN_BG_DISABLED else BTN_BG
					actionBtn.Active = not onCd
				end
				if cooldownFill then
					local cd = current:GetAttribute("Cooldown")
					if type(cd) == "number" and cd > 0 and os.clock() < cooldownUntil then
						local remain = (cooldownUntil - os.clock()) / cd
						cooldownFill.Size = UDim2.new(1, 0, math.clamp(remain, 0, 1), 0)
						cooldownFill.Visible = true
					else
						cooldownFill.Visible = false
					end
				end
			end)
		end
	else
		if crosshairConn then
			crosshairConn:Disconnect()
			crosshairConn = nil
		end
		hasValidTarget = true
		-- Cooldown UI léger sans RenderStepped permanent : pulse à l'activation
		if cooldownFill then
			cooldownFill.Visible = false
		end
	end
end

local function setActiveTool(tool: Tool?)
	activeTool = tool
	cooldownUntil = 0
	refreshMobileChrome()
end

local function hook(tool: Tool)
	if hooked[tool] then
		return
	end
	hooked[tool] = true

	-- Tool.Activated (si Activate() appelé) → même pipeline
	tool.Activated:Connect(function()
		ActivateEquippedTool(false)
	end)

	local conns = {}
	table.insert(conns, tool.Equipped:Connect(function()
		setActiveTool(tool)
	end))
	table.insert(conns, tool.Unequipped:Connect(function()
		if activeTool == tool then
			setActiveTool(nil)
		end
	end))
	table.insert(conns, tool.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if activeTool == tool then
				setActiveTool(nil)
			end
		elseif parent == player.Character then
			setActiveTool(tool)
		elseif activeTool == tool and parent ~= player.Character then
			setActiveTool(nil)
		end
	end))
	equipConns[tool] = conns

	if tool.Parent == player.Character then
		setActiveTool(tool)
	end
end

local function onAction(_name: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	-- Mobile tactile : MouseButton1 synthétisé par le touch → laisser le bouton custom
	-- (évite double activation + pops accidentels en déplaçant la caméra).
	if input.UserInputType == Enum.UserInputType.MouseButton1
		and UserInputService.TouchEnabled
		and not UserInputService.MouseEnabled
	then
		return Enum.ContextActionResult.Pass
	end
	local tool = equippedTool()
	if not tool then
		return Enum.ContextActionResult.Pass
	end
	ActivateEquippedTool(false)
	return Enum.ContextActionResult.Sink
end

local function buildMobileGui()
	local screen = Instance.new("ScreenGui")
	screen.Name = "BPW_ToolAction"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 40
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	local btn = Instance.new("TextButton")
	btn.Name = "MobileToolActionButton"
	btn.BackgroundColor3 = BTN_BG
	btn.BackgroundTransparency = 0.08
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Visible = false
	btn.Active = false
	btn.Selectable = false -- pas de focus manette indésirable
	btn.ZIndex = 10
	btn.Parent = screen
	actionBtn = btn

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = BTN_STROKE
	stroke.Thickness = 2
	stroke.Parent = btn

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = btn

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(64, 64)
	sizeConstraint.MaxSize = Vector2.new(84, 84)
	sizeConstraint.Parent = btn

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = btn

	local cd = Instance.new("Frame")
	cd.Name = "CooldownFill"
	cd.AnchorPoint = Vector2.new(0, 1)
	cd.Position = UDim2.new(0, 0, 1, 0)
	cd.Size = UDim2.new(1, 0, 0, 0)
	cd.BackgroundColor3 = Color3.fromRGB(8, 12, 20)
	cd.BackgroundTransparency = 0.35
	cd.BorderSizePixel = 0
	cd.Visible = false
	cd.ZIndex = 11
	cd.Parent = btn
	cooldownFill = cd
	local cdCorner = Instance.new("UICorner")
	cdCorner.CornerRadius = UDim.new(1, 0)
	cdCorner.Parent = cd

	local icon = Instance.new("TextLabel")
	icon.Name = "IconGlyph"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 0.55, 0)
	icon.Position = UDim2.new(0, 0, 0.05, 0)
	icon.Font = Enum.Font.GothamBold
	icon.Text = "📍"
	icon.TextScaled = true
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.ZIndex = 12
	icon.Parent = btn
	iconLabel = icon

	local img = Instance.new("ImageLabel")
	img.Name = "IconImage"
	img.BackgroundTransparency = 1
	img.Size = UDim2.new(0.5, 0, 0.45, 0)
	img.Position = UDim2.new(0.25, 0, 0.08, 0)
	img.ScaleType = Enum.ScaleType.Fit
	img.Visible = false
	img.ZIndex = 12
	img.Parent = btn
	iconImage = img

	local caption = Instance.new("TextLabel")
	caption.Name = "ActionLabel"
	caption.BackgroundTransparency = 1
	caption.Size = UDim2.new(1, -8, 0.32, 0)
	caption.Position = UDim2.new(0, 4, 0.62, 0)
	caption.Font = Enum.Font.GothamBold
	caption.Text = "POP"
	caption.TextScaled = true
	caption.TextColor3 = Color3.fromRGB(180, 230, 255)
	caption.ZIndex = 12
	caption.Parent = btn
	labelText = caption
	local tConstraint = Instance.new("UITextSizeConstraint")
	tConstraint.MinTextSize = 10
	tConstraint.MaxTextSize = 16
	tConstraint.Parent = caption

	-- Réticule centre (outils RequiresTarget uniquement)
	local ret = Instance.new("Frame")
	ret.Name = "ToolReticle"
	ret.AnchorPoint = Vector2.new(0.5, 0.5)
	ret.BackgroundTransparency = 1
	ret.Visible = false
	ret.ZIndex = 5
	ret.Parent = screen
	reticle = ret

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Parent = ret
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(230, 240, 255)
	ringStroke.Thickness = 1.5
	ringStroke.Transparency = 0.35
	ringStroke.Parent = ring
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(4, 4)
	dot.BackgroundColor3 = Color3.fromRGB(230, 240, 255)
	dot.BorderSizePixel = 0
	dot.Parent = ret
	reticleDot = dot
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	btn.MouseButton1Down:Connect(function()
		setButtonPressed(true)
	end)
	btn.MouseButton1Up:Connect(function()
		setButtonPressed(false)
	end)
	btn.MouseLeave:Connect(function()
		setButtonPressed(false)
	end)

	-- Une seule activation par pression (pas Tool:Activate → évite double feu)
	btn.Activated:Connect(function()
		if os.clock() < cooldownUntil then
			return
		end
		ActivateEquippedTool(true)
		-- Remplissage cooldown local (miroir client ; serveur reste autoritaire)
		local tool = equippedTool()
		local cdAttr = tool and tool:GetAttribute("Cooldown")
		if type(cdAttr) == "number" and cdAttr > 0 and cooldownFill then
			cooldownFill.Visible = true
			cooldownFill.Size = UDim2.new(1, 0, 1, 0)
			local tween = TweenService:Create(
				cooldownFill,
				TweenInfo.new(cdAttr, Enum.EasingStyle.Linear),
				{ Size = UDim2.new(1, 0, 0, 0) }
			)
			tween:Play()
			tween.Completed:Connect(function()
				if cooldownFill then
					cooldownFill.Visible = false
				end
			end)
		end
	end)

	layoutMobileChrome()
end

function ToolClient.Start()
	buildMobileGui()

	local function watch(container: Instance)
		container.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				hook(child)
			end
		end)
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				hook(child)
			end
		end
	end

	watch(player:WaitForChild("Backpack"))
	player.CharacterAdded:Connect(function(char)
		setActiveTool(nil)
		watch(char)
		-- Outil déjà équipé au spawn
		task.defer(function()
			local tool = char:FindFirstChildOfClass("Tool")
			if tool then
				hook(tool)
				setActiveTool(tool)
			end
		end)
	end)
	if player.Character then
		watch(player.Character)
		local tool = player.Character:FindFirstChildOfClass("Tool")
		if tool then
			hook(tool)
			setActiveTool(tool)
		end
	end

	-- Xbox / manette : RT + X. Souris : clic gauche (PC).
	-- createTouchButton = false → on utilise notre bouton custom, pas le défaut CAS.
	ContextActionService:BindAction(
		ACTION_NAME,
		onAction,
		false,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.ButtonX,
		Enum.UserInputType.MouseButton1
	)

	local cam = camera()
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutMobileChrome)
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local nextCam = camera()
		if nextCam then
			nextCam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutMobileChrome)
			layoutMobileChrome()
		end
	end)

	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refreshMobileChrome)
end

return ToolClient
