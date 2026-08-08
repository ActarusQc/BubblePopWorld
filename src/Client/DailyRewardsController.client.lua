--!strict
-- UI autonome Daily Rewards. Ne modifie pas la barre Challenges/HUD existante.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local stateRemote = Remotes.Event("DailyRewardsState")
local requestRemote = Remotes.Event("DailyRewardsRequestState")
local claimRemote = Remotes.Event("DailyRewardsClaim")
local panelOpenedRemote = Remotes.Event("DailyRewardsPanelOpened")

local BG = Color3.fromRGB(14, 16, 31)
local PANEL = Color3.fromRGB(31, 29, 62)
local CARD = Color3.fromRGB(34, 38, 68)
local CARD_PAST = Color3.fromRGB(27, 66, 63)
local CARD_CURRENT = Color3.fromRGB(55, 42, 96)
local ACCENT = Color3.fromRGB(142, 111, 255)
local ACCENT_LIGHT = Color3.fromRGB(210, 192, 255)
local GOLD = Color3.fromRGB(255, 209, 92)
local GOLD_LIGHT = Color3.fromRGB(255, 239, 178)
local GREEN = Color3.fromRGB(100, 231, 169)
local MUTED = Color3.fromRGB(166, 169, 199)
local WHITE = Color3.fromRGB(249, 248, 255)

local latestState: any? = nil
local cards: { [number]: { frame: Frame, stroke: UIStroke, reward: TextLabel, status: TextLabel } } = {}
local panelVisible = false
local pulseTween: Tween? = nil

local gui = Instance.new("ScreenGui")
gui.Name = "BPW_DailyRewards"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 42
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "DailyRewardsButton"
openButton.AnchorPoint = Vector2.new(0.5, 0)
openButton.Position = UDim2.new(0.5, 0, 0, 14)
openButton.Size = UDim2.fromOffset(156, 48)
openButton.BackgroundColor3 = ACCENT
openButton.AutoButtonColor = true
openButton.Text = "DAILY GIFT"
openButton.TextColor3 = WHITE
openButton.TextSize = 14
openButton.Font = Enum.Font.GothamBold
openButton.Selectable = true
openButton.ZIndex = 5
openButton.Parent = gui
local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(1, 0)
openCorner.Parent = openButton
local openGradient = Instance.new("UIGradient")
openGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(106, 76, 232)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(177, 113, 255)),
})
openGradient.Rotation = 12
openGradient.Parent = openButton
local openStroke = Instance.new("UIStroke")
openStroke.Thickness = 2
openStroke.Color = ACCENT_LIGHT
openStroke.Transparency = 0.15
openStroke.Parent = openButton

local readyBadge = Instance.new("TextLabel")
readyBadge.Name = "ReadyBadge"
readyBadge.AnchorPoint = Vector2.new(1, 0)
readyBadge.Position = UDim2.new(1, 5, 0, -5)
readyBadge.Size = UDim2.fromOffset(48, 21)
readyBadge.BackgroundColor3 = GOLD
readyBadge.TextColor3 = Color3.fromRGB(35, 29, 12)
readyBadge.Text = "CLAIM"
readyBadge.TextSize = 9
readyBadge.Font = Enum.Font.GothamBold
readyBadge.Visible = false
readyBadge.ZIndex = 6
readyBadge.Parent = openButton
local readyCorner = Instance.new("UICorner")
readyCorner.CornerRadius = UDim.new(1, 0)
readyCorner.Parent = readyBadge

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.38
overlay.BorderSizePixel = 0
overlay.Active = true
overlay.Visible = false
overlay.ZIndex = 20
overlay.Parent = gui

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(720, 390)
window.BackgroundColor3 = BG
window.BorderSizePixel = 0
window.ZIndex = 21
window.Parent = overlay
local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 18)
windowCorner.Parent = window
local windowStroke = Instance.new("UIStroke")
windowStroke.Thickness = 2
windowStroke.Color = ACCENT
windowStroke.Transparency = 0.18
windowStroke.Parent = window
local windowGradient = Instance.new("UIGradient")
windowGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 25, 52)),
	ColorSequenceKeypoint.new(0.55, BG),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(19, 27, 48)),
})
windowGradient.Rotation = 115
windowGradient.Parent = window

local topGlow = Instance.new("Frame")
topGlow.Name = "TopGlow"
topGlow.Position = UDim2.fromOffset(20, 0)
topGlow.Size = UDim2.new(1, -40, 0, 4)
topGlow.BackgroundColor3 = ACCENT
topGlow.BorderSizePixel = 0
topGlow.ZIndex = 22
topGlow.Parent = window
local topGlowCorner = Instance.new("UICorner")
topGlowCorner.CornerRadius = UDim.new(1, 0)
topGlowCorner.Parent = topGlow
local topGlowGradient = Instance.new("UIGradient")
topGlowGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, ACCENT),
	ColorSequenceKeypoint.new(0.55, GOLD),
	ColorSequenceKeypoint.new(1, ACCENT),
})
topGlowGradient.Parent = topGlow

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(24, 17)
title.Size = UDim2.new(1, -80, 0, 30)
title.BackgroundTransparency = 1
title.Text = "DAILY REWARDS"
title.TextColor3 = WHITE
title.TextSize = 26
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 22
title.Parent = window

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Position = UDim2.fromOffset(25, 49)
subtitle.Size = UDim2.new(1, -50, 0, 22)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Come back every day • Unlock the exclusive shirt on Day 7"
subtitle.TextColor3 = MUTED
subtitle.TextSize = 12
subtitle.Font = Enum.Font.Gotham
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 22
subtitle.Parent = window

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -14, 0, 14)
closeButton.Size = UDim2.fromOffset(38, 38)
closeButton.BackgroundColor3 = Color3.fromRGB(44, 42, 72)
closeButton.Text = "×"
closeButton.TextColor3 = WHITE
closeButton.TextSize = 15
closeButton.Font = Enum.Font.GothamBold
closeButton.Selectable = true
closeButton.ZIndex = 23
closeButton.Parent = window
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 10)
closeCorner.Parent = closeButton

local gridHost = Instance.new("Frame")
gridHost.Name = "RewardsGrid"
gridHost.Position = UDim2.fromOffset(22, 84)
gridHost.Size = UDim2.new(1, -44, 0, 214)
gridHost.BackgroundTransparency = 1
gridHost.ZIndex = 22
gridHost.Parent = window

local grid = Instance.new("UIGridLayout")
grid.FillDirection = Enum.FillDirection.Horizontal
grid.FillDirectionMaxCells = 4
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.VerticalAlignment = Enum.VerticalAlignment.Center
grid.CellPadding = UDim2.fromOffset(8, 8)
grid.CellSize = UDim2.new(0.25, -7, 0, 100)
grid.Parent = gridHost

for day = 1, 7 do
	local card = Instance.new("Frame")
	card.Name = "Day" .. tostring(day)
	card.LayoutOrder = day
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	card.ZIndex = 22
	card.Parent = gridHost
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(80, 96, 132)
	stroke.Transparency = 0.3
	stroke.Parent = card
	local cardGradient = Instance.new("UIGradient")
	cardGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(49, 52, 88)),
		ColorSequenceKeypoint.new(1, CARD),
	})
	cardGradient.Rotation = 90
	cardGradient.Parent = card

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Position = UDim2.fromOffset(8, 7)
	dayLabel.Size = UDim2.new(1, -16, 0, 18)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = "DAY " .. tostring(day)
	dayLabel.TextColor3 = WHITE
	dayLabel.TextSize = 12
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.ZIndex = 23
	dayLabel.Parent = card

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Position = UDim2.fromOffset(7, 29)
	rewardLabel.Size = UDim2.new(1, -14, 0, 39)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = "..."
	rewardLabel.TextColor3 = if day == 7 then GOLD else ACCENT_LIGHT
	rewardLabel.TextSize = if day == 7 then 15 else 14
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextWrapped = true
	rewardLabel.ZIndex = 23
	rewardLabel.Parent = card

	local status = Instance.new("TextLabel")
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -7)
	status.Size = UDim2.new(1, -12, 0, 17)
	status.BackgroundTransparency = 1
	status.Text = "LOCKED"
	status.TextColor3 = MUTED
	status.TextSize = 9
	status.Font = Enum.Font.GothamBold
	status.ZIndex = 23
	status.Parent = card

	cards[day] = { frame = card, stroke = stroke, reward = rewardLabel, status = status }
end

local streakLabel = Instance.new("TextLabel")
streakLabel.Name = "Streak"
streakLabel.Position = UDim2.fromOffset(24, 309)
streakLabel.Size = UDim2.new(0.55, -24, 0, 25)
streakLabel.BackgroundTransparency = 1
streakLabel.Text = "Streak: --"
streakLabel.TextColor3 = WHITE
streakLabel.TextSize = 15
streakLabel.Font = Enum.Font.GothamBold
streakLabel.TextXAlignment = Enum.TextXAlignment.Left
streakLabel.ZIndex = 22
streakLabel.Parent = window

local shirtStatus = Instance.new("TextLabel")
shirtStatus.Name = "ShirtStatus"
shirtStatus.Position = UDim2.fromOffset(24, 334)
shirtStatus.Size = UDim2.new(0.56, -24, 0, 25)
shirtStatus.BackgroundTransparency = 1
shirtStatus.Text = "Day 7: Exclusive Shirt"
shirtStatus.TextColor3 = GOLD
shirtStatus.TextSize = 11
shirtStatus.Font = Enum.Font.Gotham
shirtStatus.TextXAlignment = Enum.TextXAlignment.Left
shirtStatus.TextWrapped = true
shirtStatus.ZIndex = 22
shirtStatus.Parent = window

local claimButton = Instance.new("TextButton")
claimButton.Name = "Claim"
claimButton.AnchorPoint = Vector2.new(1, 1)
claimButton.Position = UDim2.new(1, -22, 1, -20)
claimButton.Size = UDim2.fromOffset(220, 52)
claimButton.BackgroundColor3 = GOLD
claimButton.TextColor3 = Color3.fromRGB(47, 34, 12)
claimButton.Text = "CLAIM"
claimButton.TextSize = 15
claimButton.Font = Enum.Font.GothamBold
claimButton.AutoButtonColor = true
claimButton.Selectable = true
claimButton.ZIndex = 23
claimButton.Parent = window
local claimCorner = Instance.new("UICorner")
claimCorner.CornerRadius = UDim.new(1, 0)
claimCorner.Parent = claimButton
local claimGradient = Instance.new("UIGradient")
claimGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, GOLD_LIGHT),
	ColorSequenceKeypoint.new(1, GOLD),
})
claimGradient.Rotation = 90
claimGradient.Parent = claimButton
local claimStroke = Instance.new("UIStroke")
claimStroke.Color = GOLD_LIGHT
claimStroke.Transparency = 0.25
claimStroke.Thickness = 1.5
claimStroke.Parent = claimButton

local function setPanelVisible(visible: boolean)
	panelVisible = visible
	overlay.Visible = visible
	openButton.Visible = not visible
	if visible then
		pcall(function()
			panelOpenedRemote:FireServer()
		end)
		task.defer(function()
			GuiService.SelectedObject = if latestState and latestState.CanClaim == true then claimButton else closeButton
		end)
	else
		if GuiService.SelectedObject == claimButton or GuiService.SelectedObject == closeButton then
			GuiService.SelectedObject = openButton
		end
	end
end

local function stopPulse()
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	openButton.Size = UDim2.fromOffset(156, 48)
end

local function refreshPulse(canClaim: boolean)
	readyBadge.Visible = canClaim
	stopPulse()
	if not canClaim then
		openButton.Size = UDim2.fromOffset(108, 38)
		openButton.Text = "REWARDS"
		openButton.TextSize = 11
		openButton.BackgroundColor3 = PANEL
		openGradient.Enabled = false
		openStroke.Color = Color3.fromRGB(104, 98, 148)
		openStroke.Transparency = 0.42
		return
	end
	openButton.Text = "DAILY GIFT"
	openButton.TextSize = 14
	openButton.BackgroundColor3 = ACCENT
	openGradient.Enabled = true
	openStroke.Color = ACCENT_LIGHT
	openStroke.Transparency = 0.15
	if pulseTween then
		return
	end
	pulseTween = TweenService:Create(
		openButton,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = UDim2.fromOffset(164, 52) }
	)
	pulseTween:Play()
end

local function applyState(state: any)
	if type(state) ~= "table" then
		return
	end
	latestState = state
	local streak = math.max(0, math.floor(tonumber(state.Streak) or 0))
	local currentDay = math.clamp(math.floor(tonumber(state.CycleDay) or 1), 1, 7)
	local canClaim = state.CanClaim == true
	local shirtUnlocked = state.ShirtUnlocked == true
	local rewards = if type(state.Rewards) == "table" then state.Rewards else {}

	streakLabel.Text = ("Login streak: %d day%s  •  Current: Day %d"):format(streak, if streak == 1 then "" else "s", currentDay)
	shirtStatus.Text = if shirtUnlocked
		then "Exclusive shirt milestone: UNLOCKED"
		else "Reach Day 7 without missing a day to unlock the exclusive shirt."
	shirtStatus.TextColor3 = if shirtUnlocked then GREEN else GOLD

	for day = 1, 7 do
		local refs = cards[day]
		local reward = rewards[day]
		if refs then
			if type(reward) == "table" then
				refs.reward.Text = tostring(reward.ShortLabel or reward.Title or "REWARD")
			else
				refs.reward.Text = "REWARD"
			end

			if day < currentDay then
				refs.frame.BackgroundColor3 = CARD_PAST
				refs.stroke.Color = GREEN
				refs.stroke.Thickness = 1
				refs.status.Text = "VISITED"
				refs.status.TextColor3 = GREEN
			elseif day == currentDay then
				refs.frame.BackgroundColor3 = CARD_CURRENT
				refs.stroke.Color = if day == 7 then GOLD else ACCENT_LIGHT
				refs.stroke.Thickness = 2.5
				if canClaim then
					refs.status.Text = if day == 7 and shirtUnlocked then "SHIRT UNLOCKED" else "READY"
					refs.status.TextColor3 = if day == 7 then GOLD else ACCENT_LIGHT
				else
					refs.status.Text = "CLAIMED"
					refs.status.TextColor3 = GREEN
				end
			else
				refs.frame.BackgroundColor3 = CARD
				refs.stroke.Color = Color3.fromRGB(80, 96, 132)
				refs.stroke.Thickness = 1
				refs.status.Text = "LOCKED"
				refs.status.TextColor3 = MUTED
			end
		end
	end

	claimButton.Active = canClaim
	claimButton.AutoButtonColor = canClaim
	claimButton.BackgroundColor3 = if canClaim then GOLD else Color3.fromRGB(65, 66, 88)
	claimButton.TextColor3 = if canClaim then Color3.fromRGB(47, 34, 12) else MUTED
	claimGradient.Enabled = canClaim
	claimStroke.Transparency = if canClaim then 0.25 else 0.65
	claimButton.Text = if canClaim then ("CLAIM DAY %d"):format(currentDay) else "CLAIMED TODAY"
	refreshPulse(canClaim)
end

local function applyResponsive()
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local width = math.clamp(vp.X - 28, 320, 720)
	local mobile = vp.X < 700 or vp.Y < 600
	local height = if mobile then math.clamp(vp.Y - 32, 350, 430) else 390
	window.Size = UDim2.fromOffset(width, height)

	if mobile then
		gridHost.Position = UDim2.fromOffset(14, 80)
		gridHost.Size = UDim2.new(1, -28, 0, 220)
		grid.CellPadding = UDim2.fromOffset(5, 7)
		grid.CellSize = UDim2.new(0.25, -5, 0, 102)
		title.Position = UDim2.fromOffset(16, 14)
		title.TextSize = 20
		subtitle.Position = UDim2.fromOffset(17, 43)
		subtitle.Size = UDim2.new(1, -60, 0, 31)
		subtitle.TextSize = 10
		streakLabel.Position = UDim2.new(0, 16, 1, -112)
		streakLabel.Size = UDim2.new(1, -32, 0, 20)
		streakLabel.TextSize = 12
		shirtStatus.Position = UDim2.new(0, 16, 1, -90)
		shirtStatus.Size = UDim2.new(1, -32, 0, 30)
		shirtStatus.TextSize = 9
		claimButton.AnchorPoint = Vector2.new(0.5, 1)
		claimButton.Position = UDim2.new(0.5, 0, 1, -12)
		claimButton.Size = UDim2.new(1, -32, 0, 44)
	else
		gridHost.Position = UDim2.fromOffset(22, 84)
		gridHost.Size = UDim2.new(1, -44, 0, 214)
		grid.CellPadding = UDim2.fromOffset(8, 8)
		grid.CellSize = UDim2.new(0.25, -7, 0, 100)
		title.Position = UDim2.fromOffset(24, 17)
		title.TextSize = 24
		subtitle.Position = UDim2.fromOffset(25, 49)
		subtitle.Size = UDim2.new(1, -50, 0, 22)
		subtitle.TextSize = 12
		streakLabel.Position = UDim2.fromOffset(24, 309)
		streakLabel.Size = UDim2.new(0.55, -24, 0, 25)
		streakLabel.TextSize = 15
		shirtStatus.Position = UDim2.fromOffset(24, 334)
		shirtStatus.Size = UDim2.new(0.56, -24, 0, 25)
		shirtStatus.TextSize = 11
		claimButton.AnchorPoint = Vector2.new(1, 1)
		claimButton.Position = UDim2.new(1, -22, 1, -20)
		claimButton.Size = UDim2.fromOffset(220, 52)
	end
end

openButton.Activated:Connect(function()
	setPanelVisible(true)
end)

closeButton.Activated:Connect(function()
	setPanelVisible(false)
end)

claimButton.Activated:Connect(function()
	if latestState and latestState.CanClaim == true then
		claimButton.Active = false
		claimButton.Text = "CLAIMING..."
		pcall(function()
			claimRemote:FireServer()
		end)
	end
end)

overlay.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- L'overlay absorbe les clics derrière la fenêtre; fermeture via X explicite.
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or not panelVisible then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
		setPanelVisible(false)
	end
end)

stateRemote.OnClientEvent:Connect(function(state: any)
	applyState(state)
end)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsive)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	applyResponsive()
end)

applyResponsive()
task.defer(function()
	pcall(function()
		requestRemote:FireServer()
	end)
end)
