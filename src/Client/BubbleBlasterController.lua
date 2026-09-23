--!strict
-- Interface multiplateforme du kiosque Bubble Blaster.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local BubbleBlasterConfig = require(ReplicatedStorage:WaitForChild("Shared").BubbleBlasterConfig)
local Controller = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local playfield: Frame? = nil
local scoreLabel: TextLabel? = nil
local timeLabel: TextLabel? = nil
local currentTarget: TextButton? = nil
local active = false
local localEndsAt = 0

local COLORS = {
	Color3.fromRGB(255, 83, 105),
	Color3.fromRGB(61, 211, 255),
	Color3.fromRGB(255, 210, 54),
	Color3.fromRGB(159, 92, 255),
	Color3.fromRGB(70, 224, 154),
}

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local value = Instance.new("UIStroke")
	value.Color = color
	value.Thickness = thickness
	value.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, font: Enum.Font, color: Color3): TextLabel
	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Size = size
	value.Position = position
	value.Text = text
	value.TextColor3 = color
	value.Font = font
	value.TextScaled = true
	value.Parent = parent
	return value
end

local function destroyTarget()
	if currentTarget then currentTarget:Destroy() end
	currentTarget = nil
	GuiService.SelectedObject = nil
end

local function close(sendExit: boolean)
	if sendExit and active then Remotes.Event("BubbleBlasterExit"):FireServer() end
	active = false
	destroyTarget()
	if gui then gui:Destroy() end
	gui = nil
	playfield = nil
	scoreLabel = nil
	timeLabel = nil
end

local function buildGui(duration: number)
	close(false)
	active = true
	localEndsAt = os.clock() + duration

	local screen = Instance.new("ScreenGui")
	screen.Name = "BubbleBlasterGui"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 220
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(3, 14, 35)
	shade.BackgroundTransparency = 0.12
	shade.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.51)
	panel.Size = UDim2.fromScale(0.86, 0.84)
	panel.BackgroundColor3 = Color3.fromRGB(14, 49, 91)
	panel.Parent = shade
	corner(panel, 24)
	stroke(panel, Color3.fromRGB(72, 220, 255), 4)

	local title = label(panel, "🎈  BUBBLE BLASTER", UDim2.fromScale(0.57, 0.11), UDim2.fromScale(0.035, 0.025), Enum.Font.GothamBlack, Color3.fromRGB(255, 216, 56))
	title.TextXAlignment = Enum.TextXAlignment.Left
	local instructions = label(panel, "POP AS MANY BALLOONS AS YOU CAN!", UDim2.fromScale(0.55, 0.045), UDim2.fromScale(0.04, 0.13), Enum.Font.GothamBold, Color3.fromRGB(226, 244, 255))
	instructions.TextXAlignment = Enum.TextXAlignment.Left

	local scorePill = Instance.new("Frame")
	scorePill.Position = UDim2.fromScale(0.62, 0.045)
	scorePill.Size = UDim2.fromScale(0.16, 0.10)
	scorePill.BackgroundColor3 = Color3.fromRGB(31, 91, 145)
	scorePill.Parent = panel
	corner(scorePill, 28)
	stroke(scorePill, Color3.fromRGB(114, 229, 255), 2)
	scoreLabel = label(scorePill, "SCORE  0", UDim2.fromScale(0.9, 0.75), UDim2.fromScale(0.05, 0.12), Enum.Font.GothamBlack, Color3.new(1, 1, 1))

	local timePill = Instance.new("Frame")
	timePill.Position = UDim2.fromScale(0.79, 0.045)
	timePill.Size = UDim2.fromScale(0.12, 0.10)
	timePill.BackgroundColor3 = Color3.fromRGB(255, 72, 91)
	timePill.Parent = panel
	corner(timePill, 28)
	timeLabel = label(timePill, "30", UDim2.fromScale(0.9, 0.75), UDim2.fromScale(0.05, 0.12), Enum.Font.GothamBlack, Color3.new(1, 1, 1))

	local exit = Instance.new("TextButton")
	exit.AnchorPoint = Vector2.new(1, 0)
	exit.Position = UDim2.fromScale(0.975, 0.04)
	exit.Size = UDim2.fromScale(0.055, 0.10)
	exit.BackgroundColor3 = Color3.fromRGB(255, 72, 91)
	exit.Text = "X"
	exit.TextColor3 = Color3.new(1, 1, 1)
	exit.Font = Enum.Font.GothamBlack
	exit.TextScaled = true
	exit.Parent = panel
	corner(exit, 18)
	exit.Activated:Connect(function() close(true) end)

	local field = Instance.new("Frame")
	field.Position = UDim2.fromScale(0.035, 0.19)
	field.Size = UDim2.fromScale(0.93, 0.62)
	field.BackgroundColor3 = Color3.fromRGB(17, 117, 173)
	field.ClipsDescendants = true
	field.Parent = panel
	corner(field, 20)
	stroke(field, Color3.fromRGB(173, 241, 255), 3)
	playfield = field

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(30, 156, 211), Color3.fromRGB(8, 65, 128))
	gradient.Rotation = 90
	gradient.Parent = field

	for i = 1, 8 do
		local pennant = Instance.new("Frame")
		pennant.Size = UDim2.fromScale(0.07, 0.035)
		pennant.Position = UDim2.fromScale(0.03 + (i - 1) * 0.135, 0.035)
		pennant.BackgroundColor3 = COLORS[((i - 1) % #COLORS) + 1]
		pennant.BorderSizePixel = 0
		pennant.Rotation = if i % 2 == 0 then 5 else -5
		pennant.Parent = field
	end
	label(field, "A / CLICK / TAP TO POP", UDim2.fromScale(0.40, 0.05), UDim2.fromScale(0.30, 0.92), Enum.Font.GothamBold, Color3.fromRGB(190, 232, 255))

	local prizes = Instance.new("Frame")
	prizes.Position = UDim2.fromScale(0.035, 0.83)
	prizes.Size = UDim2.fromScale(0.93, 0.14)
	prizes.BackgroundColor3 = Color3.fromRGB(8, 34, 71)
	prizes.Parent = panel
	corner(prizes, 16)
	stroke(prizes, Color3.fromRGB(255, 214, 58), 2)
	local prizeHint = label(prizes, "PRIZES  ·  ★ = 2 PTS", UDim2.fromScale(0.18, 0.82), UDim2.fromScale(0.012, 0.09), Enum.Font.GothamBlack, Color3.fromRGB(255, 214, 58))
	prizeHint.TextXAlignment = Enum.TextXAlignment.Left
	local rows = BubbleBlasterConfig.PrizeRows()
	local count = #rows
	for index, tier in ipairs(rows) do
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.Position = UDim2.fromScale(0.20 + (index - 1) * (0.78 / count), 0.08)
		cell.Size = UDim2.fromScale(0.78 / count - 0.01, 0.84)
		cell.Parent = prizes
		local title = label(cell, tier.Name, UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0.04), Enum.Font.GothamBlack, tier.Color)
		title.TextXAlignment = Enum.TextXAlignment.Center
		local detail = label(
			cell,
			if tier.MinScore <= 0 then ("any  ·  %d"):format(tier.Coins) else ("%d+  ·  %d"):format(tier.MinScore, tier.Coins),
			UDim2.fromScale(1, 0.42),
			UDim2.fromScale(0, 0.48),
			Enum.Font.GothamBold,
			Color3.fromRGB(230, 244, 255)
		)
		detail.TextXAlignment = Enum.TextXAlignment.Center
	end
end

local function showTarget(data: any)
	if not active or not playfield then return end
	destroyTarget()
	local target = Instance.new("TextButton")
	target.Name = "BalloonTarget"
	target.AnchorPoint = Vector2.new(0.5, 0.5)
	target.Position = UDim2.fromScale(data.x, data.y)
	target.Size = UDim2.fromScale(data.size, data.size * 1.32)
	target.BackgroundColor3 = if data.golden then Color3.fromRGB(255, 199, 32) else COLORS[data.colorIndex] or COLORS[1]
	target.Text = if data.golden then "★" else ""
	target.TextColor3 = Color3.new(1, 1, 1)
	target.Font = Enum.Font.GothamBlack
	target.TextScaled = true
	target.AutoButtonColor = true
	target.Selectable = true
	target.Parent = playfield
	corner(target, 999)
	stroke(target, if data.golden then Color3.fromRGB(255, 245, 150) else Color3.new(1, 1, 1), if data.golden then 5 else 3)
	local shine = Instance.new("Frame")
	shine.Size = UDim2.fromScale(0.22, 0.18)
	shine.Position = UDim2.fromScale(0.18, 0.12)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.18
	shine.Parent = target
	corner(shine, 999)
	currentTarget = target
	local fired = false
	target.Activated:Connect(function()
		if fired or not active then return end
		fired = true
		Remotes.Event("BubbleBlasterShoot"):FireServer(data.id)
		target:TweenSize(UDim2.fromScale(0, 0), Enum.EasingDirection.In, Enum.EasingStyle.Back, 0.09, true)
	end)
	GuiService.SelectedObject = target
end

local function showResult(data: any)
	if not gui then return end
	active = false
	destroyTarget()
	local result = Instance.new("Frame")
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.fromScale(0.5, 0.5)
	result.Size = UDim2.fromScale(0.46, 0.40)
	result.BackgroundColor3 = Color3.fromRGB(8, 34, 71)
	result.Parent = gui
	corner(result, 28)
	stroke(result, data.color or Color3.fromRGB(72, 220, 255), 5)
	label(result, data.tier or "FINISHED!", UDim2.fromScale(0.88, 0.22), UDim2.fromScale(0.06, 0.10), Enum.Font.GothamBlack, data.color or Color3.new(1, 1, 1))
	label(result, ("%d POINTS"):format(data.score or 0), UDim2.fromScale(0.80, 0.15), UDim2.fromScale(0.10, 0.37), Enum.Font.GothamBold, Color3.new(1, 1, 1))
	label(result, ("+%d COINS"):format(data.reward or 0), UDim2.fromScale(0.80, 0.17), UDim2.fromScale(0.10, 0.58), Enum.Font.GothamBlack, Color3.fromRGB(255, 214, 58))
	task.delay(3.2, function() if gui then close(false) end end)
end

function Controller.Start()
	Remotes.Event("BubbleBlasterStart").OnClientEvent:Connect(function(data)
		buildGui(data.duration or 30)
	end)
	Remotes.Event("BubbleBlasterTarget").OnClientEvent:Connect(showTarget)
	Remotes.Event("BubbleBlasterState").OnClientEvent:Connect(function(data)
		if scoreLabel then scoreLabel.Text = ("SCORE  %d"):format(data.score or 0) end
		if data.hit then destroyTarget() end
	end)
	Remotes.Event("BubbleBlasterEnd").OnClientEvent:Connect(showResult)

	RunService.RenderStepped:Connect(function()
		if active and timeLabel then
			timeLabel.Text = tostring(math.max(0, math.ceil(localEndsAt - os.clock())))
		end
	end)
end

return Controller
