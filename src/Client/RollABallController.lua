--!strict
-- Interface arcade Roll-A-Ball. Logique inchangée; seul le look est reconstruit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local RollABallConfig = require(ReplicatedStorage:WaitForChild("Shared").RollABallConfig)
local Controller = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local scoreLabel: TextLabel? = nil
local ballsLabel: TextLabel? = nil
local powerNeedle: Frame? = nil
local rollButton: TextButton? = nil
local ballToken: Frame? = nil
local playfield: Frame? = nil
local active = false
local rolling = false
local power = 0
local powerEpoch = 0
local powerPhase = 0
local ringFrames: { [number]: Frame } = {}

-- Positions relatives à la zone de jeu uniquement.
local RING_LAYOUT = {
	[50] = { x = 0.50, y = 0.13, w = 0.36, h = 0.145 },
	[40] = { x = 0.50, y = 0.31, w = 0.50, h = 0.155 },
	[30] = { x = 0.50, y = 0.50, w = 0.64, h = 0.165 },
	[20] = { x = 0.50, y = 0.70, w = 0.78, h = 0.175 },
	[10] = { x = 0.50, y = 0.90, w = 0.92, h = 0.185 },
}

local C = {
	Gold = Color3.fromRGB(255, 209, 46),
	GoldLight = Color3.fromRGB(255, 236, 140),
	Red = Color3.fromRGB(230, 42, 54),
	RedDeep = Color3.fromRGB(168, 16, 32),
	RedField = Color3.fromRGB(198, 24, 40),
	RedRay = Color3.fromRGB(148, 10, 26),
	Blue = Color3.fromRGB(22, 92, 188),
	BlueDeep = Color3.fromRGB(10, 46, 118),
	Navy = Color3.fromRGB(8, 30, 78),
	Ink = Color3.fromRGB(12, 6, 10),
	White = Color3.fromRGB(255, 255, 255),
}

local function zOf(parent: Instance): number
	return if parent:IsA("GuiObject") then (parent :: GuiObject).ZIndex else 1
end

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local value = Instance.new("UIStroke")
	value.Color = color
	value.Thickness = thickness
	value.Transparency = transparency or 0
	value.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	value.LineJoinMode = Enum.LineJoinMode.Round
	value.Parent = parent
	return value
end

local function gradient(parent: Instance, a: Color3, b: Color3, rotation: number): UIGradient
	local value = Instance.new("UIGradient")
	value.Color = ColorSequence.new(a, b)
	value.Rotation = rotation
	value.Parent = parent
	return value
end

local function pad(parent: Instance, l: number, t: number, r: number, b: number)
	local value = Instance.new("UIPadding")
	value.PaddingLeft = UDim.new(l, 0)
	value.PaddingTop = UDim.new(t, 0)
	value.PaddingRight = UDim.new(r, 0)
	value.PaddingBottom = UDim.new(b, 0)
	value.Parent = parent
end

local function frame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, radius: number, zi: number): Frame
	local value = Instance.new("Frame")
	value.Name = name
	value.Size = size
	value.Position = position
	value.BackgroundColor3 = color
	value.BorderSizePixel = 0
	value.ZIndex = zi
	value.Parent = parent
	if radius > 0 then corner(value, radius) end
	return value
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
	value.ZIndex = zOf(parent) + 1
	value.Parent = parent
	return value
end

local function dropShadow(host: GuiObject, offset: number, radius: number)
	local shadow = Instance.new("Frame")
	shadow.Name = "DropShadow"
	shadow.AnchorPoint = host.AnchorPoint
	shadow.Position = host.Position + UDim2.fromOffset(offset, offset)
	shadow.Size = host.Size
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.62
	shadow.BorderSizePixel = 0
	shadow.ZIndex = math.max(1, host.ZIndex - 1)
	shadow.Parent = host.Parent
	corner(shadow, radius)
	return shadow
end

local function marqueeLights(parent: GuiObject, count: number, inset: number)
	for i = 1, count do
		local t = (i - 0.5) / count
		local edge = t * 4
		local x, y
		if edge < 1 then
			x, y = edge, 0
		elseif edge < 2 then
			x, y = 1, edge - 1
		elseif edge < 3 then
			x, y = 1 - (edge - 2), 1
		else
			x, y = 0, 1 - (edge - 3)
		end
		local bulb = Instance.new("Frame")
		bulb.Name = "MarqueeBulb"
		bulb.AnchorPoint = Vector2.new(0.5, 0.5)
		bulb.Position = UDim2.fromScale(inset + x * (1 - 2 * inset), inset + y * (1 - 2 * inset))
		bulb.Size = UDim2.new(0.034, 0, 0.12, 0)
		bulb.BackgroundColor3 = C.GoldLight
		bulb.BorderSizePixel = 0
		bulb.ZIndex = parent.ZIndex + 3
		bulb.Parent = parent
		corner(bulb, 99)
		local glow = Instance.new("UIStroke")
		glow.Color = C.Gold
		glow.Thickness = 1.5
		glow.Transparency = 0.25
		glow.Parent = bulb
	end
end

local function arcadeTitle(parent: Instance, text: string, size: UDim2, position: UDim2): TextLabel
	local shadow = label(parent, text, size, position + UDim2.fromScale(0.006, 0.08), Enum.Font.FredokaOne, C.RedDeep)
	shadow.TextXAlignment = Enum.TextXAlignment.Left
	shadow.TextStrokeTransparency = 1
	local title = label(parent, text, size, position, Enum.Font.FredokaOne, C.Gold)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextStrokeColor3 = C.Red
	title.TextStrokeTransparency = 0
	local outline = stroke(title, C.RedDeep, 2.5)
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return title
end

local function stripedBanner(parent: Instance, position: UDim2, size: UDim2, zi: number)
	local banner = frame(parent, "StripeBanner", size, position, C.Red, 8, zi)
	banner.ClipsDescendants = true
	banner.Rotation = 18
	for i = 0, 7 do
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.fromScale(0.34, 1.8)
		stripe.Position = UDim2.fromScale(-0.2 + i * 0.28, -0.4)
		stripe.Rotation = -28
		stripe.BackgroundColor3 = if i % 2 == 0 then C.Gold else C.Red
		stripe.BorderSizePixel = 0
		stripe.ZIndex = zi
		stripe.Parent = banner
	end
end

local function confetti(parent: Instance, position: UDim2, color: Color3, rotation: number, zi: number)
	local bit = frame(parent, "Confetti", UDim2.fromScale(0.028, 0.018), position, color, 2, zi)
	bit.Rotation = rotation
	bit.BackgroundTransparency = 0.08
end

local function candySkirt(parent: Instance, zi: number)
	local skirt = frame(parent, "CandySkirt", UDim2.fromScale(1, 0.042), UDim2.fromScale(0, 0.958), C.White, 20, zi)
	skirt.ClipsDescendants = true
	for i = 0, 20 do
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.fromScale(0.08, 2.6)
		stripe.Position = UDim2.fromScale(-0.05 + i * 0.075, -0.8)
		stripe.Rotation = 32
		stripe.BackgroundColor3 = if i % 2 == 0 then C.Red else C.White
		stripe.BorderSizePixel = 0
		stripe.ZIndex = zi
		stripe.Parent = skirt
	end
end

local function close(sendExit: boolean)
	if sendExit and active then Remotes.Event("RollABallExit"):FireServer() end
	active = false
	rolling = false
	ringFrames = {}
	GuiService.SelectedObject = nil
	if gui then gui:Destroy() end
	gui = nil
	scoreLabel = nil
	ballsLabel = nil
	powerNeedle = nil
	rollButton = nil
	ballToken = nil
	playfield = nil
end

local function makeRing(parent: Frame, points: number, layout: { x: number, y: number, w: number, h: number })
	local ring = Instance.new("Frame")
	ring.Name = "Ring" .. points
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(layout.x, layout.y)
	ring.Size = UDim2.fromScale(layout.w, layout.h)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 6
	ring.Parent = parent
	local outline = stroke(ring, C.White, if points == 50 then 5 else 4)
	outline.LineJoinMode = Enum.LineJoinMode.Round
	corner(ring, 999)
	local number = label(ring, tostring(points), UDim2.fromScale(0.28, 0.70), UDim2.fromScale(0.36, 0.15), Enum.Font.FredokaOne, C.White)
	number.ZIndex = 7
	local numberStroke = stroke(number, Color3.fromRGB(80, 8, 18), 1.5, 0.35)
	numberStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ringFrames[points] = ring
	return ring
end

local function flashRing(points: number)
	local ring = ringFrames[points]
	if not ring then return end
	local outline = ring:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = C.Gold
		outline.Thickness = 8
		task.delay(0.45, function()
			if outline.Parent then
				outline.Color = C.White
				outline.Thickness = if points == 50 then 5 else 4
			end
		end)
	end
end

local function resetBall()
	if not ballToken then return end
	ballToken.Position = UDim2.fromScale(0.50, 0.90)
	ballToken.Size = UDim2.fromScale(0.13, 0.145)
	ballToken.BackgroundTransparency = 0
	ballToken.Visible = true
end

local function animateBall(points: number)
	if not ballToken then return end
	local layout = RING_LAYOUT[points] or RING_LAYOUT[10]
	resetBall()
	local mid = TweenService:Create(ballToken, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.50, layout.y + 0.12),
		Size = UDim2.fromScale(0.10, 0.11),
	})
	local land = TweenService:Create(ballToken, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(layout.x, layout.y),
		Size = UDim2.fromScale(0.08, 0.09),
	})
	mid:Play()
	mid.Completed:Connect(function()
		if not active or not ballToken then return end
		land:Play()
		land.Completed:Connect(function()
			if not active or not ballToken then return end
			flashRing(points)
			TweenService:Create(ballToken, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Size = UDim2.fromScale(0, 0),
				BackgroundTransparency = 0.4,
			}):Play()
		end)
	end)
end

local function fireRoll()
	if not active or rolling then return end
	rolling = true
	if rollButton then
		rollButton.Text = "ROLLING"
		rollButton.AutoButtonColor = false
	end
	Remotes.Event("RollABallRoll"):FireServer()
end

local function buildHeader(parent: Frame)
	local header = frame(parent, "Header", UDim2.fromScale(1, 0.125), UDim2.fromScale(0, 0), Color3.new(), 0, 20)
	header.BackgroundTransparency = 1
	pad(header, 0.02, 0.10, 0.02, 0.08)

	arcadeTitle(header, "ROLL-A-BALL", UDim2.fromScale(0.40, 0.86), UDim2.fromScale(0.01, 0.06))

	local scoreWrap = frame(header, "ScoreMarquee", UDim2.fromScale(0.24, 0.92), UDim2.fromScale(0.42, 0.04), C.BlueDeep, 16, 21)
	stroke(scoreWrap, C.Gold, 3)
	gradient(scoreWrap, C.Blue, C.BlueDeep, 90)
	marqueeLights(scoreWrap, 18, 0.07)
	local scoreWell = frame(scoreWrap, "ScoreWell", UDim2.fromScale(0.78, 0.62), UDim2.fromScale(0.11, 0.19), C.Ink, 10, 22)
	stroke(scoreWell, Color3.fromRGB(90, 18, 28), 2)
	scoreLabel = label(scoreWell, "000", UDim2.fromScale(0.92, 0.88), UDim2.fromScale(0.04, 0.06), Enum.Font.RobotoMono, Color3.fromRGB(255, 64, 72))
	scoreLabel.ZIndex = 23

	local ballsWrap = frame(header, "Balls", UDim2.fromScale(0.16, 0.92), UDim2.fromScale(0.68, 0.04), Color3.fromRGB(18, 62, 148), 16, 21)
	stroke(ballsWrap, C.Gold, 2)
	gradient(ballsWrap, Color3.fromRGB(42, 108, 210), Color3.fromRGB(14, 48, 128), 90)
	for _, pos in ipairs({ Vector2.new(0.12, 0.18), Vector2.new(0.78, 0.22), Vector2.new(0.20, 0.72), Vector2.new(0.84, 0.68) }) do
		local starMark = label(ballsWrap, "★", UDim2.fromScale(0.18, 0.22), UDim2.fromScale(pos.X, pos.Y), Enum.Font.GothamBlack, Color3.fromRGB(120, 180, 255))
		starMark.TextTransparency = 0.35
		starMark.ZIndex = 21
	end
	label(ballsWrap, "BALLS", UDim2.fromScale(0.80, 0.30), UDim2.fromScale(0.10, 0.06), Enum.Font.GothamBlack, C.White)
	ballsLabel = label(ballsWrap, "5", UDim2.fromScale(0.70, 0.58), UDim2.fromScale(0.15, 0.34), Enum.Font.FredokaOne, C.White)

	local exit = Instance.new("TextButton")
	exit.Name = "Close"
	exit.AnchorPoint = Vector2.new(1, 0)
	exit.Position = UDim2.fromScale(0.995, 0.04)
	exit.Size = UDim2.fromScale(0.105, 0.92)
	exit.BackgroundColor3 = C.Red
	exit.Text = "X"
	exit.TextColor3 = C.White
	exit.Font = Enum.Font.FredokaOne
	exit.TextScaled = true
	exit.AutoButtonColor = true
	exit.ZIndex = 21
	exit.Parent = header
	corner(exit, 14)
	stroke(exit, C.White, 3)
	gradient(exit, Color3.fromRGB(255, 86, 98), C.RedDeep, 90)
	exit.Activated:Connect(function() close(true) end)
end

local function buildPlayfield(parent: Frame)
	local field = frame(parent, "Playfield", UDim2.fromScale(1, 0.545), UDim2.fromScale(0, 0.125), C.RedField, 22, 12)
	field.ClipsDescendants = true
	stroke(field, Color3.fromRGB(255, 210, 120), 2, 0.35)
	gradient(field, Color3.fromRGB(220, 48, 62), Color3.fromRGB(150, 8, 24), 90)
	playfield = field

	for i = 0, 17 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 1)
		ray.Position = UDim2.fromScale(0.50, 0.52)
		ray.Size = UDim2.fromScale(0.045, 0.92)
		ray.Rotation = i * 10
		ray.BackgroundColor3 = C.RedRay
		ray.BackgroundTransparency = 0.82
		ray.BorderSizePixel = 0
		ray.ZIndex = 12
		ray.Parent = field
	end
	for _, pos in ipairs({
		UDim2.fromScale(0.08, 0.18),
		UDim2.fromScale(0.90, 0.14),
		UDim2.fromScale(0.12, 0.72),
		UDim2.fromScale(0.88, 0.68),
		UDim2.fromScale(0.18, 0.42),
		UDim2.fromScale(0.82, 0.46),
	}) do
		local starMark = label(field, "★", UDim2.fromScale(0.045, 0.06), pos, Enum.Font.GothamBlack, Color3.fromRGB(120, 16, 28))
		starMark.TextTransparency = 0.45
		starMark.ZIndex = 13
	end

	makeRing(field, 50, RING_LAYOUT[50])
	makeRing(field, 40, RING_LAYOUT[40])
	makeRing(field, 30, RING_LAYOUT[30])
	makeRing(field, 20, RING_LAYOUT[20])
	makeRing(field, 10, RING_LAYOUT[10])

	local ball = frame(field, "Ball", UDim2.fromScale(0.13, 0.145), UDim2.fromScale(0.50, 0.90), Color3.fromRGB(255, 214, 64), 999, 18)
	ball.AnchorPoint = Vector2.new(0.5, 0.5)
	stroke(ball, C.GoldLight, 3)
	gradient(ball, Color3.fromRGB(255, 240, 150), Color3.fromRGB(224, 140, 24), 130)
	local shine = frame(ball, "Shine", UDim2.fromScale(0.36, 0.28), UDim2.fromScale(0.14, 0.12), C.White, 999, 19)
	shine.BackgroundTransparency = 0.12
	ballToken = ball
end

local function buildControls(parent: Frame)
	local controls = frame(parent, "Controls", UDim2.fromScale(1, 0.145), UDim2.fromScale(0, 0.68), Color3.new(), 0, 20)
	controls.BackgroundTransparency = 1
	pad(controls, 0.025, 0.06, 0.025, 0.04)

	local bar = frame(controls, "PowerBar", UDim2.fromScale(0.66, 0.90), UDim2.fromScale(0, 0.05), C.Navy, 16, 21)
	stroke(bar, C.Gold, 3)
	pad(bar, 0.012, 0.08, 0.012, 0.08)

	local BAND_COLORS = {
		[10] = Color3.fromRGB(28, 78, 168),
		[20] = Color3.fromRGB(42, 150, 214),
		[30] = Color3.fromRGB(72, 210, 230),
		[40] = Color3.fromRGB(255, 150, 42),
		[50] = C.Gold,
	}
	local prev = 0
	for index, band in ipairs(RollABallConfig.PowerBands) do
		local share = band.Max - prev
		local color = BAND_COLORS[band.Points] or C.Blue
		local tile = frame(bar, "Band" .. index, UDim2.fromScale(share, 1), UDim2.fromScale(prev, 0), color, 10, 22)
		gradient(tile, color:Lerp(C.White, 0.16), color:Lerp(Color3.new(0, 0, 0), 0.16), 90)
		stroke(tile, Color3.fromRGB(8, 20, 48), 1, 0.4)
		local tag = label(tile, tostring(band.Points), UDim2.fromScale(1, 0.70), UDim2.fromScale(0, 0.15), Enum.Font.FredokaOne, C.White)
		tag.ZIndex = 23
		prev = band.Max
	end

	local needleHost = frame(bar, "NeedleHost", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), C.White, 0, 26)
	needleHost.BackgroundTransparency = 1
	local needle = frame(needleHost, "Needle", UDim2.fromScale(0.018, 1.16), UDim2.fromScale(0, 0.5), C.White, 5, 27)
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	stroke(needle, Color3.fromRGB(20, 24, 48), 1)
	powerNeedle = needle

	local rollWrap = frame(controls, "RollWrap", UDim2.fromScale(0.305, 1), UDim2.fromScale(0.685, 0), C.RedDeep, 22, 21)
	stroke(rollWrap, C.Gold, 4)
	gradient(rollWrap, Color3.fromRGB(190, 28, 42), C.RedDeep, 90)
	marqueeLights(rollWrap, 20, 0.075)
	local button = Instance.new("TextButton")
	button.Name = "Roll"
	button.Position = UDim2.fromScale(0.07, 0.16)
	button.Size = UDim2.fromScale(0.86, 0.68)
	button.BackgroundColor3 = C.Red
	button.Text = "ROLL"
	button.TextColor3 = C.White
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.Selectable = true
	button.AutoButtonColor = true
	button.ZIndex = 24
	button.Parent = rollWrap
	corner(button, 16)
	stroke(button, Color3.fromRGB(255, 170, 180), 2, 0.35)
	gradient(button, Color3.fromRGB(255, 86, 98), C.RedDeep, 90)
	button.Activated:Connect(fireRoll)
	rollButton = button
	GuiService.SelectedObject = button
end

local function prizeTicket(parent: Instance, color: Color3, icon: string)
	local body = frame(parent, "Ticket", UDim2.fromScale(0.46, 0.34), UDim2.fromScale(0.27, 0.60), color, 7, zOf(parent) + 1)
	stroke(body, Color3.fromRGB(255, 255, 255), 1, 0.45)
	label(body, icon, UDim2.fromScale(0.84, 0.84), UDim2.fromScale(0.08, 0.08), Enum.Font.GothamBlack, C.White)
end

local function buildPrizes(parent: Frame)
	local prizes = frame(parent, "Prizes", UDim2.fromScale(1, 0.145), UDim2.fromScale(0, 0.83), C.Navy, 18, 20)
	stroke(prizes, C.Gold, 2)
	gradient(prizes, Color3.fromRGB(16, 48, 112), C.Navy, 90)
	pad(prizes, 0.012, 0.10, 0.012, 0.10)

	local ribbon = frame(prizes, "Ribbon", UDim2.fromScale(0.155, 0.82), UDim2.fromScale(0.008, 0.09), C.Red, 10, 21)
	gradient(ribbon, Color3.fromRGB(255, 78, 90), C.RedDeep, 90)
	stroke(ribbon, C.White, 1.5, 0.35)
	label(ribbon, "🎪", UDim2.fromScale(0.30, 0.70), UDim2.fromScale(0.04, 0.15), Enum.Font.GothamBlack, C.White)
	label(ribbon, "PRIZES", UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.32, 0.18), Enum.Font.FredokaOne, C.White)

	local items = {
		{ Name = "PARTICIPATION", Detail = "any", Color = Color3.fromRGB(70, 170, 255), Icon = "🎟" },
		{ Name = "BRONZE", Detail = "50+", Color = Color3.fromRGB(214, 132, 64), Icon = "🎟" },
		{ Name = "SILVER", Detail = "90+", Color = Color3.fromRGB(200, 216, 230), Icon = "🎟" },
		{ Name = "GOLD", Detail = "140+", Color = C.Gold, Icon = "★" },
		{ Name = "PERFECT", Detail = "180+", Color = Color3.fromRGB(176, 92, 255), Icon = "★" },
		{ Name = "PET", Detail = ("%d+"):format(RollABallConfig.PrizePetMinScore), Color = Color3.fromRGB(255, 118, 176), Icon = "🐾" },
	}
	local row = frame(prizes, "PrizeRow", UDim2.fromScale(0.82, 1), UDim2.fromScale(0.175, 0), Color3.new(), 0, 21)
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.008, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for index, item in ipairs(items) do
		local cell = frame(row, item.Name, UDim2.fromScale(0.158, 0.92), UDim2.fromScale(0, 0), Color3.new(), 0, 21)
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = index
		if index < #items then
			local divider = frame(cell, "Divider", UDim2.new(0, 2, 0.78, 0), UDim2.fromScale(1, 0.11), Color3.fromRGB(110, 160, 220), 0, 21)
			divider.AnchorPoint = Vector2.new(1, 0)
			divider.BackgroundTransparency = 0.45
		end
		local nameLabel = label(cell, item.Name, UDim2.fromScale(1, 0.28), UDim2.fromScale(0, 0.02), Enum.Font.GothamBlack, item.Color)
		nameLabel.TextScaled = true
		label(cell, item.Detail, UDim2.fromScale(1, 0.24), UDim2.fromScale(0, 0.30), Enum.Font.GothamBold, C.White)
		prizeTicket(cell, item.Color, item.Icon)
	end
end

local function buildGui(balls: number, score: number)
	close(false)
	active = true
	rolling = false
	power = 0
	ringFrames = {}

	local screen = Instance.new("ScreenGui")
	screen.Name = "RollABallGui"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 220
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	local shade = frame(screen, "Shade", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.fromRGB(6, 14, 36), 0, 1)
	shade.BackgroundTransparency = 0.22

	local cabinet = frame(shade, "Cabinet", UDim2.fromScale(0.72, 0.90), UDim2.fromScale(0.5, 0.51), C.Blue, 30, 3)
	cabinet.AnchorPoint = Vector2.new(0.5, 0.5)
	stroke(cabinet, C.Gold, 8)
	gradient(cabinet, Color3.fromRGB(46, 122, 220), C.BlueDeep, 90)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.76
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = cabinet
	local cabinetShadow = dropShadow(cabinet, 10, 30)
	local shadowAspect = Instance.new("UIAspectRatioConstraint")
	shadowAspect.AspectRatio = 0.76
	shadowAspect.DominantAxis = Enum.DominantAxis.Height
	shadowAspect.Parent = cabinetShadow

	label(cabinet, "★", UDim2.fromScale(0.05, 0.045), UDim2.fromScale(0.012, 0.16), Enum.Font.GothamBlack, C.Gold).ZIndex = 8
	label(cabinet, "★", UDim2.fromScale(0.045, 0.04), UDim2.fromScale(0.94, 0.20), Enum.Font.GothamBlack, C.Gold).ZIndex = 8
	label(cabinet, "★", UDim2.fromScale(0.04, 0.036), UDim2.fromScale(0.015, 0.58), Enum.Font.GothamBlack, C.Gold).ZIndex = 8
	label(cabinet, "★", UDim2.fromScale(0.04, 0.036), UDim2.fromScale(0.945, 0.54), Enum.Font.GothamBlack, C.Gold).ZIndex = 8
	stripedBanner(cabinet, UDim2.fromScale(-0.01, 0.30), UDim2.fromScale(0.07, 0.16), 8)
	stripedBanner(cabinet, UDim2.fromScale(0.94, 0.62), UDim2.fromScale(0.07, 0.16), 8)
	confetti(cabinet, UDim2.fromScale(0.02, 0.42), C.Red, 25, 8)
	confetti(cabinet, UDim2.fromScale(0.96, 0.36), C.Gold, -20, 8)
	confetti(cabinet, UDim2.fromScale(0.03, 0.72), C.Gold, 40, 8)
	confetti(cabinet, UDim2.fromScale(0.95, 0.76), C.Red, -35, 8)

	local content = frame(cabinet, "Content", UDim2.fromScale(0.90, 0.90), UDim2.fromScale(0.05, 0.028), Color3.new(), 0, 10)
	content.BackgroundTransparency = 1

	buildHeader(content)
	buildPlayfield(content)
	buildControls(content)
	buildPrizes(content)
	candySkirt(cabinet, 30)

	if scoreLabel then scoreLabel.Text = string.format("%03d", score) end
	if ballsLabel then ballsLabel.Text = tostring(balls) end
end

local function showResult(data: any)
	if not gui then return end
	active = false
	rolling = false
	local result = frame(gui, "Result", UDim2.fromScale(0.42, 0.34), UDim2.fromScale(0.5, 0.5), C.Navy, 28, 50)
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	stroke(result, data.color or C.Gold, 6)
	gradient(result, Color3.fromRGB(22, 64, 132), C.Navy, 90)
	label(result, data.tier or "FINISHED!", UDim2.fromScale(0.88, 0.22), UDim2.fromScale(0.06, 0.10), Enum.Font.FredokaOne, data.color or C.White)
	label(result, ("%d POINTS"):format(data.score or 0), UDim2.fromScale(0.80, 0.15), UDim2.fromScale(0.10, 0.37), Enum.Font.GothamBold, C.White)
	local rewardText = if data.petAwarded
		then ("PRIZE: %s!"):format(data.prizeName or "PET")
		else ("+%d COINS"):format(data.reward or 0)
	label(result, rewardText, UDim2.fromScale(0.84, 0.17), UDim2.fromScale(0.08, 0.58), Enum.Font.FredokaOne, C.Gold)
	task.delay(3.2, function() if gui then close(false) end end)
end

function Controller.Start()
	ContextActionService:BindAction("BPW_RollABallRoll", function(_, inputState)
		if not active then return Enum.ContextActionResult.Pass end
		if inputState == Enum.UserInputState.Begin then fireRoll() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindAction("BPW_RollABallExit", function(_, inputState)
		if not active then return Enum.ContextActionResult.Pass end
		if inputState == Enum.UserInputState.Begin then close(true) end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonB)

	Remotes.Event("RollABallStart").OnClientEvent:Connect(function(data)
		powerEpoch = data.powerEpoch or Workspace:GetServerTimeNow()
		powerPhase = data.powerPhase or 0
		buildGui(data.balls or RollABallConfig.BallsPerGame, data.score or 0)
	end)
	Remotes.Event("RollABallState").OnClientEvent:Connect(function(data)
		if scoreLabel then scoreLabel.Text = string.format("%03d", data.score or 0) end
		if ballsLabel then ballsLabel.Text = tostring(data.ballsLeft or 0) end
		animateBall(data.points or 10)
		task.delay(1.05, function()
			rolling = false
			if rollButton and active then
				rollButton.Text = "ROLL"
				rollButton.AutoButtonColor = true
				GuiService.SelectedObject = rollButton
			end
			resetBall()
		end)
	end)
	Remotes.Event("RollABallEnd").OnClientEvent:Connect(showResult)

	RunService.RenderStepped:Connect(function()
		if not active or rolling then return end
		local elapsed = Workspace:GetServerTimeNow() - powerEpoch
		power = RollABallConfig.PowerAt(elapsed, powerPhase)
		if powerNeedle then
			powerNeedle.Position = UDim2.fromScale(power, 0.5)
		end
	end)
end

return Controller
