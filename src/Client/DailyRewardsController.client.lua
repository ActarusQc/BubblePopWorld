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
local HudChrome = require(Shared.HudChrome)

local stateRemote = Remotes.Event("DailyRewardsState")
local requestRemote = Remotes.Event("DailyRewardsRequestState")
local claimRemote = Remotes.Event("DailyRewardsClaim")
local panelOpenedRemote = Remotes.Event("DailyRewardsPanelOpened")

local BG = Color3.fromRGB(14, 16, 31)
local PANEL = Color3.fromRGB(31, 29, 62)
local CARD = Color3.fromRGB(34, 38, 68)
local CARD_PAST = Color3.fromRGB(27, 66, 63)
local CARD_CURRENT = Color3.fromRGB(55, 42, 96)
local ACCENT = Color3.fromRGB(0, 211, 255)
local ACCENT_LIGHT = Color3.fromRGB(116, 235, 255)
local GOLD = Color3.fromRGB(255, 209, 92)
local GOLD_LIGHT = Color3.fromRGB(255, 239, 178)
local GREEN = Color3.fromRGB(100, 231, 169)
local MUTED = Color3.fromRGB(166, 169, 199)
local WHITE = Color3.fromRGB(249, 248, 255)

local latestState: any? = nil
local cards: { [number]: { frame: Frame, stroke: UIStroke, icon: ImageLabel, reward: TextLabel, status: TextLabel, claimedTint: Frame, claimedSeal: TextLabel } } = {}
local panelVisible = false
local pulseTween: Tween? = nil
local previousCanClaim: boolean? = nil

local gui = Instance.new("ScreenGui")
gui.Name = "BPW_DailyRewards"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 42
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "DailyRewardsButton"
openButton.AnchorPoint = Vector2.new(0, 0)
openButton.Position = UDim2.fromOffset(0, 0)
openButton.Size = UDim2.fromOffset(HudChrome.ACTION_BUTTON_SIZE, HudChrome.ACTION_BUTTON_SIZE)
openButton.BackgroundColor3 = HudChrome.BG_BUTTON
openButton.BackgroundTransparency = 0.08
openButton.BorderSizePixel = 0
openButton.AutoButtonColor = false
openButton.Text = ""
openButton.Font = Enum.Font.GothamBold
openButton.Selectable = true
openButton.Active = true
openButton.LayoutOrder = 4
openButton.ZIndex = 5
openButton.Visible = false
openButton.Parent = gui
openButton:SetAttribute("AccessibleName", "Daily Rewards")
local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 16)
openCorner.Parent = openButton
local openGradient = Instance.new("UIGradient")
openGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(106, 76, 232)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(177, 113, 255)),
})
openGradient.Rotation = 12
openGradient.Enabled = false
openGradient.Parent = openButton
local openStroke = Instance.new("UIStroke")
openStroke.Thickness = 1.4
openStroke.Color = HudChrome.ACCENT
openStroke.Transparency = 0.12
openStroke.Parent = openButton

local calendarIcon = Instance.new("TextLabel")
calendarIcon.Name = "IconGlyph"
calendarIcon.Size = UDim2.fromScale(1, 1)
calendarIcon.BackgroundTransparency = 1
calendarIcon.Text = "📅"
calendarIcon.TextColor3 = WHITE
calendarIcon.TextScaled = true
calendarIcon.Font = Enum.Font.GothamBold
calendarIcon.ZIndex = 6
calendarIcon.Parent = openButton
local calendarConstraint = Instance.new("UITextSizeConstraint")
calendarConstraint.MinTextSize = 18
calendarConstraint.MaxTextSize = 32
calendarConstraint.Parent = calendarIcon

local openTooltip = Instance.new("TextLabel")
openTooltip.Name = "Tooltip"
openTooltip.Visible = false
openTooltip.AnchorPoint = Vector2.new(1, 0.5)
openTooltip.Position = UDim2.new(0, -8, 0.5, 0)
openTooltip.Size = UDim2.fromOffset(104, 24)
openTooltip.BackgroundColor3 = HudChrome.BG
openTooltip.BackgroundTransparency = 0.1
openTooltip.BorderSizePixel = 0
openTooltip.Text = "Daily Rewards"
openTooltip.TextColor3 = WHITE
openTooltip.TextSize = 12
openTooltip.Font = Enum.Font.GothamMedium
openTooltip.ZIndex = 70
openTooltip.Parent = openButton
local tooltipCorner = Instance.new("UICorner")
tooltipCorner.CornerRadius = UDim.new(0, 6)
tooltipCorner.Parent = openTooltip

openButton.MouseEnter:Connect(function()
	openTooltip.Visible = true
	openStroke.Thickness = 2.2
	openButton.BackgroundTransparency = 0
end)
openButton.MouseLeave:Connect(function()
	openTooltip.Visible = false
	openStroke.Thickness = 1.4
	openButton.BackgroundTransparency = 0.08
end)

local readyBadge = Instance.new("TextLabel")
readyBadge.Name = "ReadyBadge"
readyBadge.AnchorPoint = Vector2.new(1, 0)
readyBadge.Position = UDim2.new(1, 3, 0, -3)
readyBadge.Size = UDim2.fromOffset(18, 18)
readyBadge.BackgroundColor3 = GOLD
readyBadge.TextColor3 = Color3.fromRGB(35, 29, 12)
readyBadge.Text = "!"
readyBadge.TextSize = 12
readyBadge.Font = Enum.Font.GothamBold
readyBadge.Visible = false
readyBadge.ZIndex = 6
readyBadge.Parent = openButton
local readyCorner = Instance.new("UICorner")
readyCorner.CornerRadius = UDim.new(1, 0)
readyCorner.Parent = readyBadge

task.spawn(function()
	local actionColumn: Frame? = nil
	while not actionColumn do
		local candidate = playerGui:FindFirstChild(HudChrome.ACTION_COLUMN_NAME, true)
		if candidate and candidate:IsA("Frame") then
			actionColumn = candidate
			break
		end
		task.wait(0.1)
	end

	openButton.Parent = actionColumn
	openButton.AnchorPoint = Vector2.new(0, 0)
	openButton.Position = UDim2.fromOffset(0, 0)
	openButton.ZIndex = math.max(actionColumn.ZIndex + 1, 61)
	calendarIcon.ZIndex = openButton.ZIndex + 1
	readyBadge.ZIndex = openButton.ZIndex + 2

	local list = actionColumn:FindFirstChildOfClass("UIListLayout")
	local buttonSize = openButton.Size.X.Offset
	local gap = if list then list.Padding.Offset else HudChrome.ACTION_BUTTON_GAP
	local visibleButtons = 0
	for _, child in actionColumn:GetChildren() do
		if child:IsA("GuiObject") and (child:IsA("TextButton") or child.Name == "InventorySlot") then
			visibleButtons += 1
			buttonSize = math.max(buttonSize, child.Size.X.Offset)
		end
	end
	actionColumn.Size = UDim2.fromOffset(
		buttonSize,
		buttonSize * visibleButtons + gap * math.max(0, visibleButtons - 1)
	)
	openButton.Visible = not panelVisible
end)

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
window.Size = UDim2.fromOffset(980, 560)
window.BackgroundColor3 = BG
window.BorderSizePixel = 0
window.ZIndex = 21
window.Parent = overlay
local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 26)
windowCorner.Parent = window
local windowStroke = Instance.new("UIStroke")
windowStroke.Thickness = 3
windowStroke.Color = ACCENT
windowStroke.Transparency = 0.02
windowStroke.Parent = window
local windowGradient = Instance.new("UIGradient")
windowGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(5, 27, 55)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(5, 16, 37)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 12, 29)),
})
windowGradient.Rotation = 115
windowGradient.Parent = window

local innerBorder = Instance.new("Frame")
innerBorder.Name = "InnerBorder"
innerBorder.Position = UDim2.fromOffset(10, 10)
innerBorder.Size = UDim2.new(1, -20, 1, -20)
innerBorder.BackgroundTransparency = 1
innerBorder.ZIndex = 21
innerBorder.Parent = window
local innerCorner = Instance.new("UICorner")
innerCorner.CornerRadius = UDim.new(0, 20)
innerCorner.Parent = innerBorder
local innerStroke = Instance.new("UIStroke")
innerStroke.Color = Color3.fromRGB(31, 113, 178)
innerStroke.Transparency = 0.45
innerStroke.Thickness = 1
innerStroke.Parent = innerBorder

local topGlow = Instance.new("Frame")
topGlow.Name = "TopGlow"
topGlow.Position = UDim2.fromOffset(30, 0)
topGlow.Size = UDim2.new(1, -60, 0, 5)
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
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(117, 86, 255)),
	ColorSequenceKeypoint.new(1, ACCENT),
})
topGlowGradient.Parent = topGlow

local headerIcon = Instance.new("ImageLabel")
headerIcon.Name = "HeaderIcon"
headerIcon.Position = UDim2.fromOffset(32, 24)
headerIcon.Size = UDim2.fromOffset(68, 68)
headerIcon.BackgroundColor3 = ACCENT
headerIcon.BackgroundTransparency = 0.15
headerIcon.BorderSizePixel = 0
headerIcon.Image = "rbxassetid://125048443338815"
headerIcon.ScaleType = Enum.ScaleType.Fit
headerIcon.ZIndex = 23
headerIcon.Parent = window
local headerIconCorner = Instance.new("UICorner")
headerIconCorner.CornerRadius = UDim.new(0, 20)
headerIconCorner.Parent = headerIcon
local headerIconStroke = Instance.new("UIStroke")
headerIconStroke.Color = ACCENT_LIGHT
headerIconStroke.Transparency = 0.25
headerIconStroke.Thickness = 1.5
headerIconStroke.Parent = headerIcon
local headerIconGradient = Instance.new("UIGradient")
headerIconGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(177, 113, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 76, 218)),
})
headerIconGradient.Rotation = 90
headerIconGradient.Parent = headerIcon

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(118, 25)
title.Size = UDim2.fromOffset(125, 42)
title.BackgroundTransparency = 1
title.Text = "DAILY"
title.TextColor3 = WHITE
title.TextSize = 34
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 22
title.Parent = window

local titleAccent = Instance.new("TextLabel")
titleAccent.Name = "TitleAccent"
titleAccent.Position = UDim2.fromOffset(242, 25)
titleAccent.Size = UDim2.fromOffset(230, 42)
titleAccent.BackgroundTransparency = 1
titleAccent.Text = "REWARDS"
titleAccent.TextColor3 = ACCENT
titleAccent.TextSize = 34
titleAccent.Font = Enum.Font.GothamBlack
titleAccent.TextXAlignment = Enum.TextXAlignment.Left
titleAccent.ZIndex = 22
titleAccent.Parent = window
local titleAccentGradient = Instance.new("UIGradient")
titleAccentGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(73, 239, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 149, 232)),
})
titleAccentGradient.Rotation = 90
titleAccentGradient.Parent = titleAccent

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Position = UDim2.fromOffset(120, 67)
subtitle.Size = UDim2.new(1, -390, 0, 22)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Come back every day • Unlock the exclusive shirt on Day 7"
subtitle.TextColor3 = MUTED
subtitle.TextSize = 12
subtitle.Font = Enum.Font.Gotham
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 22
subtitle.Parent = window

local progressPill = Instance.new("Frame")
progressPill.Name = "ProgressPill"
progressPill.AnchorPoint = Vector2.new(1, 0)
progressPill.Position = UDim2.new(1, -90, 0, 35)
progressPill.Size = UDim2.fromOffset(190, 50)
progressPill.BackgroundColor3 = Color3.fromRGB(5, 29, 55)
progressPill.BorderSizePixel = 0
progressPill.ZIndex = 23
progressPill.Parent = window
local progressCorner = Instance.new("UICorner")
progressCorner.CornerRadius = UDim.new(1, 0)
progressCorner.Parent = progressPill
local progressStroke = Instance.new("UIStroke")
progressStroke.Color = ACCENT_LIGHT
progressStroke.Transparency = 0.45
progressStroke.Parent = progressPill
local progressText = Instance.new("TextLabel")
progressText.Size = UDim2.fromScale(1, 1)
progressText.BackgroundTransparency = 1
progressText.Text = "🔥  0 DAY STREAK"
progressText.TextColor3 = ACCENT_LIGHT
progressText.TextSize = 15
progressText.Font = Enum.Font.GothamBold
progressText.ZIndex = 24
progressText.Parent = progressPill

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -18, 0, 18)
closeButton.Size = UDim2.fromOffset(56, 56)
closeButton.BackgroundColor3 = Color3.fromRGB(8, 30, 61)
closeButton.Text = "×"
closeButton.TextColor3 = WHITE
closeButton.TextSize = 15
closeButton.Font = Enum.Font.GothamBold
closeButton.Selectable = true
closeButton.ZIndex = 23
closeButton.Parent = window
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 15)
closeCorner.Parent = closeButton
local closeStroke = Instance.new("UIStroke")
closeStroke.Color = ACCENT
closeStroke.Thickness = 2
closeStroke.Transparency = 0
closeStroke.Parent = closeButton

local gridHost = Instance.new("Frame")
gridHost.Name = "RewardsGrid"
gridHost.Position = UDim2.fromOffset(48, 110)
gridHost.Size = UDim2.new(1, -96, 0, 278)
gridHost.BackgroundTransparency = 1
gridHost.ZIndex = 22
gridHost.Parent = window

local bubbleGlowA = Instance.new("Frame")
bubbleGlowA.Name = "BubbleGlowA"
bubbleGlowA.Position = UDim2.new(1, -150, 0, -90)
bubbleGlowA.Size = UDim2.fromOffset(220, 220)
bubbleGlowA.BackgroundColor3 = ACCENT
bubbleGlowA.BackgroundTransparency = 0.91
bubbleGlowA.BorderSizePixel = 0
bubbleGlowA.ZIndex = 21
bubbleGlowA.Parent = window
local bubbleGlowACorner = Instance.new("UICorner")
bubbleGlowACorner.CornerRadius = UDim.new(1, 0)
bubbleGlowACorner.Parent = bubbleGlowA

local bubbleGlowB = Instance.new("Frame")
bubbleGlowB.Name = "BubbleGlowB"
bubbleGlowB.Position = UDim2.new(0, -75, 1, -100)
bubbleGlowB.Size = UDim2.fromOffset(150, 150)
bubbleGlowB.BackgroundColor3 = Color3.fromRGB(68, 205, 255)
bubbleGlowB.BackgroundTransparency = 0.94
bubbleGlowB.BorderSizePixel = 0
bubbleGlowB.ZIndex = 21
bubbleGlowB.Parent = window
local bubbleGlowBCorner = Instance.new("UICorner")
bubbleGlowBCorner.CornerRadius = UDim.new(1, 0)
bubbleGlowBCorner.Parent = bubbleGlowB

for day = 1, 7 do
	local card = Instance.new("Frame")
	card.Name = "Day" .. tostring(day)
	card.LayoutOrder = day
	card.BackgroundColor3 = if day == 7 then Color3.fromRGB(70, 49, 27) else CARD
	card.BorderSizePixel = 0
	card.ZIndex = 22
	card.Parent = gridHost
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = if day == 7 then GOLD else Color3.fromRGB(41, 96, 145)
	stroke.Transparency = if day == 7 then 0.05 else 0.18
	stroke.Parent = card
	local cardGradient = Instance.new("UIGradient")
	cardGradient.Color = if day == 7
		then ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(105, 72, 12)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(55, 39, 16)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 24, 34)),
		})
		else ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 61, 100)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(8, 36, 69)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 22, 47)),
		})
	cardGradient.Rotation = 90
	cardGradient.Parent = card

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Position = UDim2.fromOffset(8, 7)
	dayLabel.Size = UDim2.new(1, -16, 0, 18)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = if day == 7 then "DAY 7  •  GRAND PRIZE" else "DAY " .. tostring(day)
	dayLabel.TextColor3 = if day == 7 then GOLD_LIGHT else ACCENT_LIGHT
	dayLabel.TextSize = 14
	dayLabel.Font = Enum.Font.GothamBold
	dayLabel.ZIndex = 23
	dayLabel.Parent = card

	local rewardIcon = Instance.new("ImageLabel")
	rewardIcon.Name = "RewardIcon"
	rewardIcon.AnchorPoint = Vector2.new(0.5, 0)
	rewardIcon.Position = UDim2.new(0.5, 0, 0, 30)
	rewardIcon.Size = UDim2.fromOffset(if day == 7 then 74 else 68, if day == 7 then 74 else 68)
	rewardIcon.BackgroundTransparency = 1
	rewardIcon.BorderSizePixel = 0
	rewardIcon.Image = if day == 7
		then "rbxassetid://137664935993597"
		else "rbxassetid://100961065553997"
	rewardIcon.ScaleType = Enum.ScaleType.Fit
	rewardIcon.ZIndex = 24
	rewardIcon.Parent = card

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Position = UDim2.fromOffset(7, 65)
	rewardLabel.Size = UDim2.new(1, -14, 0, 23)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = "..."
	rewardLabel.TextColor3 = if day == 7 then GOLD else ACCENT_LIGHT
	rewardLabel.TextSize = if day == 7 then 15 else 14
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextWrapped = true
	rewardLabel.ZIndex = 23
	rewardLabel.Parent = card

	local claimedTint = Instance.new("Frame")
	claimedTint.Name = "ClaimedTint"
	claimedTint.Size = UDim2.fromScale(1, 1)
	claimedTint.BackgroundColor3 = Color3.fromRGB(28, 196, 145)
	claimedTint.BackgroundTransparency = 0.88
	claimedTint.BorderSizePixel = 0
	claimedTint.Visible = false
	claimedTint.ZIndex = 22
	claimedTint.Parent = card
	local claimedTintCorner = Instance.new("UICorner")
	claimedTintCorner.CornerRadius = UDim.new(0, 18)
	claimedTintCorner.Parent = claimedTint

	local claimedSeal = Instance.new("TextLabel")
	claimedSeal.Name = "ClaimedSeal"
	claimedSeal.Position = UDim2.fromOffset(-2, -2)
	claimedSeal.Size = UDim2.fromOffset(42, 42)
	claimedSeal.BackgroundColor3 = Color3.fromRGB(17, 190, 133)
	claimedSeal.BorderSizePixel = 0
	claimedSeal.Text = "✓"
	claimedSeal.TextColor3 = WHITE
	claimedSeal.TextSize = 23
	claimedSeal.Font = Enum.Font.GothamBlack
	claimedSeal.Visible = false
	claimedSeal.ZIndex = 27
	claimedSeal.Parent = card
	local claimedSealCorner = Instance.new("UICorner")
	claimedSealCorner.CornerRadius = UDim.new(0, 13)
	claimedSealCorner.Parent = claimedSeal
	local claimedSealStroke = Instance.new("UIStroke")
	claimedSealStroke.Color = Color3.fromRGB(109, 255, 207)
	claimedSealStroke.Thickness = 2
	claimedSealStroke.Transparency = 0.05
	claimedSealStroke.Parent = claimedSeal

	local status = Instance.new("TextLabel")
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -8)
	status.Size = UDim2.new(1, -20, 0, 20)
	status.BackgroundColor3 = Color3.fromRGB(25, 28, 50)
	status.BackgroundTransparency = 0.18
	status.BorderSizePixel = 0
	status.Text = "LOCKED"
	status.TextColor3 = MUTED
	status.TextSize = 9
	status.Font = Enum.Font.GothamBold
	status.ZIndex = 23
	status.Parent = card
	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(1, 0)
	statusCorner.Parent = status

	if day == 7 then
		local goldGlow = Instance.new("UIStroke")
		goldGlow.Name = "GoldGlow"
		goldGlow.Color = GOLD
		goldGlow.Thickness = 8
		goldGlow.Transparency = 0.6
		goldGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		goldGlow.Parent = card
		TweenService:Create(
			goldGlow,
			TweenInfo.new(1.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.82, Thickness = 5 }
		):Play()

		for sparkleIndex, sparklePosition in {
			UDim2.new(0.12, 0, 0.42, 0),
			UDim2.new(0.84, 0, 0.38, 0),
			UDim2.new(0.2, 0, 0.72, 0),
			UDim2.new(0.78, 0, 0.7, 0),
		} do
			local sparkle = Instance.new("TextLabel")
			sparkle.Name = "GoldSparkle" .. tostring(sparkleIndex)
			sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
			sparkle.Position = sparklePosition
			sparkle.Size = UDim2.fromOffset(18, 18)
			sparkle.BackgroundTransparency = 1
			sparkle.Text = "✦"
			sparkle.TextColor3 = GOLD_LIGHT
			sparkle.TextSize = 15
			sparkle.Font = Enum.Font.GothamBold
			sparkle.ZIndex = 25
			sparkle.Parent = card
		end

		local prizeTag = Instance.new("TextLabel")
		prizeTag.Name = "PrizeTag"
		prizeTag.AnchorPoint = Vector2.new(0.5, 0)
		prizeTag.Position = UDim2.new(0.5, 0, 0, 27)
		prizeTag.Size = UDim2.fromOffset(132, 22)
		prizeTag.BackgroundColor3 = Color3.fromRGB(91, 60, 11)
		prizeTag.BorderSizePixel = 0
		prizeTag.Text = "★  WEEKLY REWARD  ★"
		prizeTag.TextColor3 = GOLD_LIGHT
		prizeTag.TextSize = 9
		prizeTag.Font = Enum.Font.GothamBold
		prizeTag.ZIndex = 24
		prizeTag.Parent = card
		local prizeTagCorner = Instance.new("UICorner")
		prizeTagCorner.CornerRadius = UDim.new(1, 0)
		prizeTagCorner.Parent = prizeTag
		local prizeInnerStroke = Instance.new("UIStroke")
		prizeInnerStroke.Color = GOLD
		prizeInnerStroke.Transparency = 0.25
		prizeInnerStroke.Parent = prizeTag
	end

	cards[day] = {
		frame = card,
		stroke = stroke,
		icon = rewardIcon,
		reward = rewardLabel,
		status = status,
		claimedTint = claimedTint,
		claimedSeal = claimedSeal,
	}
end

local function layoutRewardCards(mobile: boolean)
	for day = 1, 7 do
		local refs = cards[day]
		if refs then
			if day <= 4 then
				local col = day - 1
				refs.frame.Position = UDim2.new(col * 0.25, col * 4, 0, 0)
				refs.frame.Size = UDim2.new(0.25, -8, 0.46, -6)
			elseif day <= 6 then
				local col = day - 5
				refs.frame.Position = UDim2.new(0.08 + col * 0.255, col * 4, 0.46, 8)
				refs.frame.Size = UDim2.new(0.245, -8, 0.54, -8)
			else
				refs.frame.Position = UDim2.new(0.59, 8, 0.46, 8)
				refs.frame.Size = UDim2.new(0.41, -8, 0.54, -8)
			end
			refs.icon.Position = UDim2.new(0.5, 0, 0, if day == 7 then 43 else 31)
			refs.icon.Size = UDim2.fromOffset(if day == 7 then 66 else 74, if day == 7 then 66 else 74)
			refs.reward.Position = UDim2.new(0, 7, 0, if day == 7 then 108 else 77)
			refs.reward.TextSize = if day == 7 then 19 else 16
			refs.stroke.Thickness = if day == 7 then 3 else refs.stroke.Thickness
		end
	end
end

local infoBar = Instance.new("Frame")
infoBar.Name = "InfoBar"
infoBar.Position = UDim2.fromOffset(48, 400)
infoBar.Size = UDim2.new(1, -96, 0, 66)
infoBar.BackgroundColor3 = Color3.fromRGB(7, 30, 59)
infoBar.BackgroundTransparency = 0.08
infoBar.BorderSizePixel = 0
infoBar.ZIndex = 22
infoBar.Parent = window
local infoCorner = Instance.new("UICorner")
infoCorner.CornerRadius = UDim.new(0, 15)
infoCorner.Parent = infoBar
local infoStroke = Instance.new("UIStroke")
infoStroke.Color = Color3.fromRGB(30, 101, 158)
infoStroke.Transparency = 0.15
infoStroke.Parent = infoBar

local streakLabel = Instance.new("TextLabel")
streakLabel.Name = "Streak"
streakLabel.Position = UDim2.fromOffset(78, 408)
streakLabel.Size = UDim2.new(1, -156, 0, 25)
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
shirtStatus.Position = UDim2.fromOffset(78, 434)
shirtStatus.Size = UDim2.new(1, -156, 0, 24)
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
claimButton.Position = UDim2.new(1, -48, 1, -20)
claimButton.Size = UDim2.new(1, -96, 0, 66)
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
claimCorner.CornerRadius = UDim.new(0, 18)
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
end

local function refreshPulse(canClaim: boolean)
	readyBadge.Visible = canClaim
	stopPulse()
	openGradient.Enabled = canClaim
	openButton.BackgroundColor3 = if canClaim then ACCENT else HudChrome.BG_BUTTON
	calendarIcon.TextColor3 = if canClaim then GOLD_LIGHT else WHITE
	openStroke.Color = if canClaim then GOLD else HudChrome.ACCENT
	openStroke.Transparency = if canClaim then 0.05 else 0.12
	if not canClaim then
		return
	end
	pulseTween = TweenService:Create(
		openStroke,
		TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.55 }
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
	progressText.Text = ("🔥  %d DAY STREAK"):format(math.clamp(streak, 0, 7))
	shirtStatus.Text = if shirtUnlocked
		then "Exclusive shirt milestone: UNLOCKED"
		else "Reach Day 7 without missing a day to unlock the exclusive shirt."
	shirtStatus.TextColor3 = if shirtUnlocked then GREEN else GOLD

	for day = 1, 7 do
		local refs = cards[day]
		local reward = rewards[day]
		if refs then
			if type(reward) == "table" then
				refs.reward.Text = if day == 7
					then "EXCLUSIVE SHIRT"
					else tostring(reward.ShortLabel or reward.Title or "REWARD")
			else
				refs.reward.Text = "REWARD"
			end

			if day < currentDay then
				refs.frame.BackgroundColor3 = CARD_PAST
				refs.stroke.Color = GREEN
				refs.stroke.Thickness = 1
				refs.status.Text = "✓  CLAIMED"
				refs.status.TextColor3 = GREEN
				refs.status.BackgroundColor3 = Color3.fromRGB(24, 72, 62)
				refs.icon.ImageTransparency = 0
				refs.claimedTint.Visible = true
				refs.claimedSeal.Visible = true
			elseif day == currentDay then
				refs.frame.BackgroundColor3 = CARD_CURRENT
				refs.stroke.Color = if day == 7 then GOLD else ACCENT_LIGHT
				refs.stroke.Thickness = 2.5
				if canClaim then
					refs.status.Text = if day == 7 and shirtUnlocked then "★  UNLOCKED" else "★  TODAY"
					refs.status.TextColor3 = if day == 7 then GOLD else WHITE
					refs.status.BackgroundColor3 = if day == 7 then Color3.fromRGB(91, 65, 22) else ACCENT
					refs.icon.ImageTransparency = 0
					refs.claimedTint.Visible = false
					refs.claimedSeal.Visible = false
				else
					refs.status.Text = "✓  CLAIMED"
					refs.status.TextColor3 = GREEN
					refs.status.BackgroundColor3 = Color3.fromRGB(24, 72, 62)
					refs.icon.ImageTransparency = 0
					refs.claimedTint.Visible = true
					refs.claimedSeal.Visible = true
				end
			else
				refs.frame.BackgroundColor3 = CARD
				refs.stroke.Color = Color3.fromRGB(80, 96, 132)
				refs.stroke.Thickness = 1
				refs.status.Text = "LOCKED"
				refs.status.TextColor3 = MUTED
				refs.status.BackgroundColor3 = Color3.fromRGB(25, 28, 50)
				refs.icon.ImageTransparency = 0.25
				refs.claimedTint.Visible = false
				refs.claimedSeal.Visible = false
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

	local shouldAutoOpen = canClaim and previousCanClaim ~= true
	previousCanClaim = canClaim
	if shouldAutoOpen and not panelVisible then
		task.defer(function()
			if latestState == state and latestState.CanClaim == true then
				setPanelVisible(true)
			end
		end)
	end
end

local function applyResponsive()
	local camera = workspace.CurrentCamera
	local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local width = math.clamp(vp.X - 28, 560, 980)
	local mobile = vp.X < 760
	local height = math.clamp(vp.Y - 36, 500, 560)
	window.Size = UDim2.fromOffset(width, height)

	if mobile then
		headerIcon.Position = UDim2.fromOffset(18, 18)
		headerIcon.Size = UDim2.fromOffset(48, 48)
		title.Position = UDim2.fromOffset(78, 17)
		title.Size = UDim2.fromOffset(86, 30)
		title.TextSize = 23
		titleAccent.Position = UDim2.fromOffset(164, 17)
		titleAccent.Size = UDim2.fromOffset(150, 30)
		titleAccent.TextSize = 23
		subtitle.Position = UDim2.fromOffset(79, 46)
		subtitle.Size = UDim2.new(1, -142, 0, 24)
		gridHost.Position = UDim2.fromOffset(18, 82)
		gridHost.Size = UDim2.new(1, -36, 0, 274)
		layoutRewardCards(true)
		progressPill.Visible = false
		subtitle.TextSize = 10
		infoBar.Position = UDim2.new(0, 18, 1, -130)
		infoBar.Size = UDim2.new(1, -36, 0, 58)
		streakLabel.Position = UDim2.new(0, 34, 1, -124)
		streakLabel.Size = UDim2.new(1, -68, 0, 20)
		streakLabel.TextSize = 12
		shirtStatus.Position = UDim2.new(0, 34, 1, -102)
		shirtStatus.Size = UDim2.new(1, -68, 0, 24)
		shirtStatus.TextSize = 9
		claimButton.AnchorPoint = Vector2.new(0.5, 1)
		claimButton.Position = UDim2.new(0.5, 0, 1, -12)
		claimButton.Size = UDim2.new(1, -36, 0, 54)
	else
		headerIcon.Position = UDim2.fromOffset(32, 24)
		headerIcon.Size = UDim2.fromOffset(68, 68)
		gridHost.Position = UDim2.fromOffset(48, 110)
		gridHost.Size = UDim2.new(1, -96, 0, 278)
		layoutRewardCards(false)
		progressPill.Visible = true
		title.Position = UDim2.fromOffset(118, 25)
		title.Size = UDim2.fromOffset(125, 42)
		title.TextSize = 34
		titleAccent.Position = UDim2.fromOffset(242, 25)
		titleAccent.Size = UDim2.fromOffset(230, 42)
		titleAccent.TextSize = 34
		subtitle.Position = UDim2.fromOffset(120, 67)
		subtitle.Size = UDim2.new(1, -390, 0, 22)
		subtitle.TextSize = 12
		infoBar.Position = UDim2.fromOffset(48, 400)
		infoBar.Size = UDim2.new(1, -96, 0, 66)
		streakLabel.Position = UDim2.fromOffset(78, 408)
		streakLabel.Size = UDim2.new(1, -156, 0, 25)
		streakLabel.TextSize = 15
		shirtStatus.Position = UDim2.fromOffset(78, 434)
		shirtStatus.Size = UDim2.new(1, -156, 0, 24)
		shirtStatus.TextSize = 11
		claimButton.AnchorPoint = Vector2.new(1, 1)
		claimButton.AnchorPoint = Vector2.new(0.5, 1)
		claimButton.Position = UDim2.new(0.5, 0, 1, -20)
		claimButton.Size = UDim2.new(1, -96, 0, 66)
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
