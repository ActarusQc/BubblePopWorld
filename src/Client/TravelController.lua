--!strict
-- Client Bubble Transit : détection capsule locale + UI destinations.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local TravelConfig = require(Shared.TravelConfig)

local player = Players.LocalPlayer
local TravelController = {}

local BG = Color3.fromRGB(16, 22, 36)
local CARD = Color3.fromRGB(28, 36, 54)
local CARD_LOCKED = Color3.fromRGB(34, 30, 42)
local CYAN = Color3.fromRGB(70, 210, 255)
local VIOLET = Color3.fromRGB(150, 110, 255)
local GREEN = Color3.fromRGB(90, 220, 140)
local RED = Color3.fromRGB(255, 110, 120)
local WHITE = Color3.fromRGB(245, 248, 255)
local MUTED = Color3.fromRGB(170, 185, 210)

local DISPLAY_ORDER = 110
local POLL_HZ = 10

local gui: ScreenGui
local overlay: Frame
local mainPanel: Frame
local listFrame: ScrollingFrame
local statusLabel: TextLabel
local fadeFrame: Frame
local closeBtn: TextButton

local menuOpen = false
local travelling = false
local travelSuppressedUntil = 0
local activeTransitId: string? = nil
local activeArea: string? = nil
local wasInside = false
local lastRequestedTransit: string? = nil
local cardButtons: { TextButton } = {}
local characterConns: { RBXScriptConnection } = {}
local heartbeatConn: RBXScriptConnection? = nil

local function debugLog(...: any)
	if not TravelConfig.DEBUG_TRAVEL then
		return
	end
	print("[TravelDebug]", ...)
end

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = parent
end

local function pad(parent: Instance, t: number, r: number, b: number, l: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r)
	p.PaddingBottom = UDim.new(0, b)
	p.PaddingLeft = UDim.new(0, l)
	p.Parent = parent
end

local function clearCards()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name == "DestinationCard" then
			child:Destroy()
		end
	end
	table.clear(cardButtons)
end

local function setButtonsEnabled(enabled: boolean)
	for _, btn in ipairs(cardButtons) do
		if btn:GetAttribute("CanTravel") == true then
			btn.Active = enabled
			btn.AutoButtonColor = enabled
		end
	end
end

local function tweenPanel(open: boolean, onDone: (() -> ())?)
	local targetTransparency = if open then 0.25 else 1
	local targetScale = if open then 1 else 0.92
	overlay.Visible = true
	mainPanel.Visible = true

	local scale = mainPanel:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = mainPanel
	end
	scale.Scale = if open then 0.92 else 1

	TweenService:Create(overlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = targetTransparency,
	}):Play()
	local tw = TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = targetScale,
	})
	tw:Play()
	if not open then
		tw.Completed:Once(function()
			overlay.Visible = false
			mainPanel.Visible = false
			if onDone then
				onDone()
			end
		end)
	elseif onDone then
		onDone()
	end
end

local function closeMenu()
	if not menuOpen then
		return
	end
	menuOpen = false
	travelling = false
	activeTransitId = nil
	activeArea = nil
	lastRequestedTransit = nil
	statusLabel.Text = ""
	statusLabel.Visible = false
	setButtonsEnabled(true)
	GuiService.SelectedObject = nil
	tweenPanel(false)
end

local function openMenu(transitId: string)
	if menuOpen or travelling then
		return
	end
	if os.clock() < travelSuppressedUntil then
		return
	end
	menuOpen = true
	activeTransitId = transitId
	lastRequestedTransit = transitId
	statusLabel.Text = "Loading destinations..."
	statusLabel.TextColor3 = MUTED
	statusLabel.Visible = true
	-- Ne pas clearCards ici : si la réponse serveur échoue, l'UI resterait vide.
	tweenPanel(true)
	Remotes.Event("RequestDestinationList"):FireServer(transitId)
	debugLog("Opened", "terminal=" .. transitId, "player=" .. player.Name)
end

local function playTravelFx(thenFn: () -> ())
	fadeFrame.Visible = true
	fadeFrame.BackgroundTransparency = 1
	local twIn = TweenService:Create(fadeFrame, TweenInfo.new(0.2), { BackgroundTransparency = 0.05 })
	twIn:Play()
	twIn.Completed:Once(function()
		thenFn()
		task.wait(0.05)
		local twOut = TweenService:Create(fadeFrame, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
		twOut:Play()
		twOut.Completed:Once(function()
			fadeFrame.Visible = false
		end)
	end)

	local soundId = TravelConfig.TravelSoundId
	if type(soundId) == "string" and soundId ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = soundId
		s.Volume = 0.35
		s.Parent = gui
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
end

local function requestTravel(destinationId: string)
	if not menuOpen or travelling or not activeTransitId then
		return
	end
	travelling = true
	setButtonsEnabled(false)
	statusLabel.Visible = true
	statusLabel.TextColor3 = CYAN
	statusLabel.Text = "TRAVELLING..."

	task.delay(TravelConfig.TravelAnimSeconds * 0.35, function()
		if not travelling or not activeTransitId then
			return
		end
		Remotes.Event("RequestTravel"):FireServer(destinationId, activeTransitId)
	end)
end

local function buildCard(dest: any): Frame
	local locked = dest.IsLocked == true
	local current = dest.IsCurrent == true
	local isLobby = dest.IsLobby == true

	local card = Instance.new("Frame")
	card.Name = "DestinationCard"
	card.Size = UDim2.new(1, 0, 0, 108)
	card.BackgroundColor3 = if locked then CARD_LOCKED else CARD
	card.BorderSizePixel = 0
	card.Parent = listFrame
	corner(card, 14)

	local stroke = Instance.new("UIStroke")
	stroke.Color = if current then GREEN elseif locked then VIOLET else CYAN
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = card

	pad(card, 12, 12, 12, 14)

	local title = Instance.new("TextLabel")
	title.Name = "Name"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -120, 0, 28)
	title.Position = UDim2.fromOffset(0, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = WHITE
	title.Text = if isLobby then string.upper(dest.DisplayName) else dest.DisplayName
	title.Parent = card

	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, -120, 0, 36)
	desc.Position = UDim2.fromOffset(0, 30)
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 15
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextColor3 = MUTED
	desc.Text = dest.Description or ""
	desc.Parent = card

	local meta = Instance.new("TextLabel")
	meta.Name = "Meta"
	meta.BackgroundTransparency = 1
	meta.Size = UDim2.new(1, -120, 0, 20)
	meta.Position = UDim2.fromOffset(0, 72)
	meta.Font = Enum.Font.GothamMedium
	meta.TextSize = 14
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.TextColor3 = if locked then VIOLET else MUTED
	if current then
		meta.Text = "YOU ARE HERE"
		meta.TextColor3 = GREEN
	elseif locked then
		meta.Text = string.format("Requires Level %d", dest.RequiredLevel)
	else
		meta.Text = "Available"
	end
	meta.Parent = card

	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.Size = UDim2.fromOffset(108, 44)
	action.Position = UDim2.new(1, -108, 0.5, -22)
	action.BackgroundColor3 = CYAN
	action.TextColor3 = Color3.fromRGB(10, 20, 35)
	action.Font = Enum.Font.GothamBlack
	action.TextSize = 15
	action.AutoButtonColor = true
	action.Selectable = true
	action.ZIndex = 6
	action.Parent = card
	corner(action, 10)

	local canTravel = (not locked) and (not current)
	action:SetAttribute("CanTravel", canTravel)
	action:SetAttribute("IsLocked", locked)
	action:SetAttribute("IsAvailable", canTravel)

	if current then
		action.Text = "HERE"
		action.BackgroundColor3 = Color3.fromRGB(50, 70, 60)
		action.TextColor3 = GREEN
		action.Active = false
		action.AutoButtonColor = false
	elseif locked then
		action.Text = "LOCKED"
		action.BackgroundColor3 = Color3.fromRGB(55, 40, 70)
		action.TextColor3 = Color3.fromRGB(220, 190, 255)
		action.Active = false
		action.AutoButtonColor = false
	elseif isLobby then
		action.Text = "RETURN TO LOBBY"
		action.Size = UDim2.fromOffset(132, 44)
		action.Position = UDim2.new(1, -132, 0.5, -22)
		action.BackgroundColor3 = VIOLET
		action.TextColor3 = WHITE
		action.TextSize = 12
	else
		action.Text = "TRAVEL"
	end

	table.insert(cardButtons, action)
	if canTravel then
		-- Activated couvre souris, tactile et manette (éviter MouseButton1Click en double).
		action.Activated:Connect(function()
			requestTravel(dest.Id)
		end)
		action.MouseEnter:Connect(function()
			TweenService:Create(action, TweenInfo.new(0.1), {
				BackgroundColor3 = if isLobby then Color3.fromRGB(170, 130, 255) else Color3.fromRGB(120, 230, 255),
			}):Play()
		end)
		action.MouseLeave:Connect(function()
			TweenService:Create(action, TweenInfo.new(0.1), {
				BackgroundColor3 = if isLobby then VIOLET else CYAN,
			}):Play()
		end)
	end

	card.ZIndex = 5
	return card
end

local function eachDestination(destinations: any, visit: (any) -> ())
	if type(destinations) ~= "table" then
		return
	end
	-- ipairs d'abord (tableau dense), puis pairs pour tolérer une désérialisation map.
	local seen: { [any]: boolean } = {}
	for _, dest in ipairs(destinations) do
		if type(dest) == "table" and type(dest.Id) == "string" and not seen[dest] then
			seen[dest] = true
			visit(dest)
		end
	end
	for _, dest in pairs(destinations) do
		if type(dest) == "table" and type(dest.Id) == "string" and not seen[dest] then
			seen[dest] = true
			visit(dest)
		end
	end
end

local function populateDestinations(payload: any)
	if not menuOpen then
		return
	end
	if type(payload) ~= "table" then
		return
	end
	if type(payload.TransitId) == "string" and activeTransitId and payload.TransitId ~= activeTransitId then
		return
	end
	activeArea = if type(payload.CurrentArea) == "string" then payload.CurrentArea else activeArea
	clearCards()
	local destinations = payload.Destinations
	local count = 0
	eachDestination(destinations, function(dest)
		buildCard(dest)
		count += 1
	end)

	if count == 0 then
		statusLabel.Visible = true
		statusLabel.TextColor3 = RED
		statusLabel.Text = "No destinations available"
	else
		statusLabel.Text = ""
		statusLabel.Visible = false
	end

	-- Manette : première dispo, sinon première verrouillée, sinon X.
	if UserInputService.GamepadEnabled then
		local pick: TextButton? = nil
		for _, btn in ipairs(cardButtons) do
			if btn:GetAttribute("IsAvailable") == true then
				pick = btn
				break
			end
		end
		if not pick then
			for _, btn in ipairs(cardButtons) do
				pick = btn
				break
			end
		end
		GuiService.SelectedObject = pick or closeBtn
	end
end

local function handleTravelResult(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.Ok == true then
		local suppress = TravelConfig.ArrivalSuppressSeconds
		if type(payload.SuppressSeconds) == "number" then
			suppress = payload.SuppressSeconds
		end
		travelSuppressedUntil = os.clock() + suppress
		wasInside = true
		playTravelFx(function()
			closeMenu()
		end)
		return
	end

	travelling = false
	setButtonsEnabled(true)
	statusLabel.Visible = true
	statusLabel.TextColor3 = RED
	statusLabel.Text = if type(payload.Message) == "string" then payload.Message else "Travel is temporarily unavailable"
end

local function pointInPart(point: Vector3, part: BasePart): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function findLocalTriggerHit(): (string?, BasePart?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return nil, nil
	end
	local terminals = Workspace:FindFirstChild("GameZones")
	local root = terminals and terminals:FindFirstChild("TravelTerminals")
	if not root then
		return nil, nil
	end
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Model") then
			local trigger = child:FindFirstChild("TransitTrigger")
			if trigger and trigger:IsA("BasePart") and pointInPart(hrp.Position, trigger) then
				local transitId = trigger:GetAttribute("TransitId")
				if type(transitId) == "string" then
					return transitId, trigger
				end
			end
		end
	end
	return nil, nil
end

local function disconnectCharacter()
	for _, conn in ipairs(characterConns) do
		conn:Disconnect()
	end
	table.clear(characterConns)
end

local function onCharacter(char: Model)
	disconnectCharacter()
	closeMenu()
	wasInside = false

	local humanoid = char:WaitForChild("Humanoid", 8)
	if humanoid and humanoid:IsA("Humanoid") then
		table.insert(characterConns, humanoid.Died:Connect(function()
			closeMenu()
			wasInside = false
		end))
	end
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "BubbleTransitGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	fadeFrame = Instance.new("Frame")
	fadeFrame.Name = "TravelFade"
	fadeFrame.Size = UDim2.fromScale(1, 1)
	fadeFrame.BackgroundColor3 = Color3.fromRGB(8, 20, 40)
	fadeFrame.BackgroundTransparency = 1
	fadeFrame.BorderSizePixel = 0
	fadeFrame.Visible = false
	fadeFrame.ZIndex = 50
	fadeFrame.Parent = gui

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(4, 10, 22)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = gui

	local inset = GuiService:GetGuiInset()
	mainPanel = Instance.new("Frame")
	mainPanel.Name = "MainPanel"
	mainPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	mainPanel.Position = UDim2.new(0.5, 0, 0.5, math.floor(inset.Y * 0.15))
	mainPanel.Size = UDim2.new(0.92, 0, 0.72, 0)
	mainPanel.BackgroundColor3 = BG
	mainPanel.BackgroundTransparency = 0.05
	mainPanel.BorderSizePixel = 0
	mainPanel.Visible = false
	mainPanel.ZIndex = 2
	mainPanel.ClipsDescendants = true
	mainPanel.Parent = gui
	corner(mainPanel, 18)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(280, 320)
	sizeConstraint.MaxSize = Vector2.new(560, 640)
	sizeConstraint.Parent = mainPanel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 84)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = mainPanel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -64, 0, 36)
	title.Position = UDim2.fromOffset(18, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 26
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = WHITE
	title.Text = "BUBBLE TRANSIT"
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -64, 0, 22)
	subtitle.Position = UDim2.fromOffset(18, 48)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 16
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = MUTED
	subtitle.Text = "Choose your destination"
	subtitle.Parent = header

	closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Position = UDim2.new(1, -54, 0, 12)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 50, 70)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 20
	closeBtn.TextColor3 = WHITE
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = header
	corner(closeBtn, 10)
	closeBtn.MouseButton1Click:Connect(function()
		closeMenu()
	end)

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -24, 0, 22)
	statusLabel.Position = UDim2.new(0, 12, 0, 84)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 15
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = CYAN
	statusLabel.Text = ""
	statusLabel.Visible = false
	statusLabel.Parent = mainPanel

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "DestinationScrollingFrame"
	listFrame.Size = UDim2.new(1, -16, 1, -118)
	listFrame.Position = UDim2.new(0, 8, 0, 110)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.ScrollBarImageColor3 = CYAN
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	listFrame.ZIndex = 4
	listFrame.Visible = true
	listFrame.Parent = mainPanel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = listFrame

	pad(listFrame, 4, 8, 12, 8)

	closeBtn.Selectable = true
end

function TravelController.Start()
	buildGui()

	Remotes.Event("DestinationListUpdated").OnClientEvent:Connect(populateDestinations)
	Remotes.Event("TravelResult").OnClientEvent:Connect(handleTravelResult)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if not menuOpen then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then
			closeMenu()
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	local accum = 0
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < (1 / POLL_HZ) then
			return
		end
		accum = 0

		local transitId = findLocalTriggerHit()
		local isInside = transitId ~= nil

		if isInside and not wasInside and os.clock() >= travelSuppressedUntil then
			openMenu(transitId :: string)
		elseif isInside and menuOpen and activeTransitId and transitId ~= activeTransitId then
			activeTransitId = transitId
			if os.clock() >= travelSuppressedUntil then
				Remotes.Event("RequestDestinationList"):FireServer(transitId)
			end
		elseif (not isInside) and wasInside then
			if menuOpen and not travelling then
				closeMenu()
			end
		end

		wasInside = isInside
	end)
end

return TravelController
