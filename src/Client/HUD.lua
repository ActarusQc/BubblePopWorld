--!strict
-- Interface principale construite en code (aucun asset requis).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)
local HudChrome = require(Shared.HudChrome)

local player = Players.LocalPlayer
local HUD = {}

local ACCENT = HudChrome.ACCENT
local BG = HudChrome.BG
local BG_BUTTON = HudChrome.BG_BUTTON

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1.25
	s.Transparency = transparency or 0.15
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, scaled: boolean?, localize: boolean?)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = scaled ~= false
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	if localize == false then
		L10nUtil.dynamic(l, text)
	else
		L10nUtil.localize(l, text)
	end
	return l
end

local function findSellValueLabel(): TextLabel?
	local root = workspace:FindFirstChild("BubblePopWorld")
	if not root then
		return nil
	end
	local hub = root:FindFirstChild("CentralHub")
	local board: Instance? = hub and hub:FindFirstChild("SellValueBoard", true)
	if not board then
		local lobby = root:FindFirstChild("Lobby")
		if not lobby then
			return nil
		end
		local decor = lobby:FindFirstChild("LobbyDecor")
		local kiosk = lobby:FindFirstChild("SellKiosk")
		board = (decor and decor:FindFirstChild("SellValueBoard"))
			or (kiosk and kiosk:FindFirstChild("SellValueBoard", true))
			or (kiosk and kiosk:FindFirstChild("ValueDisplaySurface", true))
			or lobby:FindFirstChild("SellValueBoard", true)
	end
	if not (board and board:IsA("BasePart")) then
		return nil
	end
	local gui = board:FindFirstChild("SellValueGui")
		or board:FindFirstChildWhichIsA("SurfaceGui")
		or board:FindFirstChildWhichIsA("BillboardGui")
	if not gui then
		return nil
	end
	if not (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui")) then
		return nil
	end
	local textLabel = gui:FindFirstChild("Label", true)
	if textLabel and textLabel:IsA("TextLabel") then
		return textLabel
	end
	return nil
end

local function createActionIcon(parent: GuiObject, glyph: string, fontSize: number?): TextLabel
	local icon = Instance.new("TextLabel")
	icon.Name = "IconGlyph"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Font = Enum.Font.GothamBold
	icon.Text = glyph
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.TextScaled = fontSize == nil
	if fontSize then
		icon.TextSize = fontSize
	end
	icon.ZIndex = parent.ZIndex + 1
	icon.Parent = parent
	L10nUtil.markNoLocalize(icon)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 18
	constraint.MaxTextSize = 32
	constraint.Parent = icon
	return icon
end

local function createIconButton(
	parent: Instance,
	name: string,
	layoutOrder: number,
	glyph: string,
	accessibleName: string,
	tooltipText: string
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.LayoutOrder = layoutOrder
	btn.Size = UDim2.fromOffset(HudChrome.ACTION_BUTTON_SIZE, HudChrome.ACTION_BUTTON_SIZE)
	btn.BackgroundColor3 = BG_BUTTON
	btn.BackgroundTransparency = 0.08
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Selectable = true
	btn.Active = true
	btn.ZIndex = 5
	btn.Parent = parent
	btn:SetAttribute("AccessibleName", accessibleName)

	local cornerRadius = 16
	corner(btn, cornerRadius)
	local border = stroke(btn, ACCENT, 1.4, 0.12)

	createActionIcon(btn, glyph)

	local tip = Instance.new("TextLabel")
	tip.Name = "Tooltip"
	tip.Visible = false
	tip.AnchorPoint = Vector2.new(1, 0.5)
	tip.Position = UDim2.new(0, -8, 0.5, 0)
	tip.Size = UDim2.fromOffset(0, 24)
	tip.AutomaticSize = Enum.AutomaticSize.X
	tip.BackgroundColor3 = BG
	tip.BackgroundTransparency = 0.1
	tip.BorderSizePixel = 0
	tip.TextColor3 = Color3.new(1, 1, 1)
	tip.Font = Enum.Font.GothamMedium
	tip.TextSize = 12
	tip.TextXAlignment = Enum.TextXAlignment.Center
	tip.ZIndex = 20
	tip.Parent = btn
	L10nUtil.localize(tip, tooltipText)
	corner(tip, 6)
	stroke(tip, ACCENT, 1, 0.35)
	local tipPad = Instance.new("UIPadding")
	tipPad.PaddingLeft = UDim.new(0, 8)
	tipPad.PaddingRight = UDim.new(0, 8)
	tipPad.Parent = tip

	local function setHover(on: boolean)
		border.Thickness = if on then 2.2 else 1.4
		border.Transparency = if on then 0 else 0.12
		tip.Visible = on
		btn.BackgroundTransparency = if on then 0 else 0.08
	end

	btn.MouseEnter:Connect(function()
		setHover(true)
	end)
	btn.MouseLeave:Connect(function()
		setHover(false)
	end)
	btn.SelectionGained:Connect(function()
		setHover(true)
	end)
	btn.SelectionLost:Connect(function()
		setHover(false)
	end)

	return btn
end

function HUD.Start()
	-- Un seul BPW_HUD (éviter double panneau si Start rappelé).
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(HudChrome.SCREEN_NAME)
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = HudChrome.SCREEN_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local panelW = HudChrome.DESKTOP_PANEL_WIDTH
	local panelH = HudChrome.DESKTOP_PANEL_HEIGHT
	local pad = HudChrome.DESKTOP_PANEL_PAD
	local barH = HudChrome.BAR_HEIGHT

	local panel = Instance.new("Frame")
	panel.Name = HudChrome.STATS_PANEL_NAME
	panel.Size = UDim2.fromOffset(panelW, panelH)
	panel.Position = UDim2.fromOffset(HudChrome.DESKTOP_PANEL_LEFT, HudChrome.DESKTOP_PANEL_TOP)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = HudChrome.DESKTOP_PANEL_BG_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = false
	panel.Parent = gui
	corner(panel, HudChrome.DESKTOP_PANEL_CORNER)
	stroke(panel, ACCENT, HudChrome.DESKTOP_PANEL_STROKE, HudChrome.DESKTOP_PANEL_STROKE_TRANSPARENCY)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
	content.Position = UDim2.fromOffset(pad, pad)
	content.Parent = panel

	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Left
	stack.VerticalAlignment = Enum.VerticalAlignment.Top
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, HudChrome.ROW_GAP)
	stack.Parent = content

	local function makeRow(name: string, height: number, order: number): Frame
		local row = Instance.new("Frame")
		row.Name = name
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, height)
		row.LayoutOrder = order
		row.Parent = content
		return row
	end

	-- 1) Coins — valeur seule (pas de mot "coins")
	local coinsRow = makeRow("CoinsRow", 20, 1)
	local coinsValue = Instance.new("TextLabel")
	coinsValue.Name = "CoinsValue"
	coinsValue.BackgroundTransparency = 1
	coinsValue.Size = UDim2.fromScale(1, 1)
	coinsValue.Font = Enum.Font.GothamBold
	coinsValue.TextSize = HudChrome.FONT_COINS
	coinsValue.TextScaled = false
	coinsValue.TextColor3 = HudChrome.COIN_YELLOW
	coinsValue.TextXAlignment = Enum.TextXAlignment.Left
	coinsValue.TextYAlignment = Enum.TextYAlignment.Center
	coinsValue.Parent = coinsRow
	L10nUtil.dynamic(coinsValue, "0")

	-- 2) Backpack + barre (priorité #2, juste sous coins)
	local packRow = makeRow("BackpackRow", 14, 2)
	local backpackLine = Instance.new("TextLabel")
	backpackLine.Name = "BackpackLine"
	backpackLine.BackgroundTransparency = 1
	backpackLine.Size = UDim2.fromScale(1, 1)
	backpackLine.Font = Enum.Font.GothamMedium
	backpackLine.TextSize = HudChrome.FONT_BACKPACK
	backpackLine.TextScaled = false
	backpackLine.TextColor3 = ACCENT
	backpackLine.TextXAlignment = Enum.TextXAlignment.Left
	backpackLine.TextYAlignment = Enum.TextYAlignment.Center
	backpackLine.TextTruncate = Enum.TextTruncate.AtEnd
	backpackLine.Parent = packRow
	L10nUtil.dynamic(backpackLine, HudChrome.FormatBackpackLine(L10n.Backpack, 0, 0))

	local packBarRow = makeRow("BackpackBarRow", barH, 3)
	local backpackBack = Instance.new("Frame")
	backpackBack.Name = "BackpackTrack"
	backpackBack.Size = UDim2.fromScale(1, 1)
	backpackBack.BackgroundColor3 = HudChrome.BAR_TRACK
	backpackBack.BorderSizePixel = 0
	backpackBack.Parent = packBarRow
	corner(backpackBack, 2)

	local backpackFill = Instance.new("Frame")
	backpackFill.Name = "BackpackFill"
	backpackFill.Size = UDim2.new(0, 0, 1, 0)
	backpackFill.BackgroundColor3 = ACCENT
	backpackFill.BorderSizePixel = 0
	backpackFill.Parent = backpackBack
	corner(backpackFill, 2)

	local gapA = makeRow("SectionGapA", math.max(1, HudChrome.SECTION_GAP - HudChrome.ROW_GAP), 4)

	-- 3) Level + XP sur une ligne compacte, puis barre XP
	local progRow = makeRow("ProgressRow", 13, 5)

	local levelLine = Instance.new("TextLabel")
	levelLine.Name = "LevelLine"
	levelLine.BackgroundTransparency = 1
	levelLine.Size = UDim2.new(0.48, 0, 1, 0)
	levelLine.Font = Enum.Font.GothamMedium
	levelLine.TextSize = HudChrome.FONT_LEVEL
	levelLine.TextScaled = false
	levelLine.TextColor3 = HudChrome.TEXT_SECONDARY
	levelLine.TextXAlignment = Enum.TextXAlignment.Left
	levelLine.TextYAlignment = Enum.TextYAlignment.Center
	levelLine.TextTruncate = Enum.TextTruncate.AtEnd
	levelLine.Parent = progRow
	L10nUtil.dynamic(levelLine, HudChrome.FormatLevelLine(L10n.Level, 1))

	local xpLine = Instance.new("TextLabel")
	xpLine.Name = "XpLine"
	xpLine.BackgroundTransparency = 1
	xpLine.Size = UDim2.new(0.52, 0, 1, 0)
	xpLine.Position = UDim2.new(0.48, 0, 0, 0)
	xpLine.Font = Enum.Font.GothamMedium
	xpLine.TextSize = HudChrome.FONT_LEVEL
	xpLine.TextScaled = false
	xpLine.TextColor3 = HudChrome.TEXT_MUTED
	xpLine.TextXAlignment = Enum.TextXAlignment.Right
	xpLine.TextYAlignment = Enum.TextYAlignment.Center
	xpLine.TextTruncate = Enum.TextTruncate.AtEnd
	xpLine.Parent = progRow
	L10nUtil.dynamic(xpLine, "0 / 0")

	local xpRow = makeRow("XpBarRow", barH, 6)
	local xpBack = Instance.new("Frame")
	xpBack.Name = "XpTrack"
	xpBack.Size = UDim2.fromScale(1, 1)
	xpBack.BackgroundColor3 = HudChrome.BAR_TRACK
	xpBack.BorderSizePixel = 0
	xpBack.Parent = xpRow
	corner(xpBack, 2)

	local xpFill = Instance.new("Frame")
	xpFill.Name = "XpFill"
	xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = ACCENT
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBack
	corner(xpFill, 2)

	-- Séparateur discret
	local sepRow = makeRow("SeparatorRow", 1 + HudChrome.SECTION_GAP, 7)
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.AnchorPoint = Vector2.new(0, 0.5)
	separator.Position = UDim2.new(0, 0, 0.5, 0)
	separator.Size = UDim2.new(1, 0, 0, 1)
	separator.BackgroundColor3 = ACCENT
	separator.BackgroundTransparency = 0.84
	separator.BorderSizePixel = 0
	separator.Parent = sepRow

	-- 4) Room available
	local statusRow = makeRow("StatusRow", 13, 8)
	local statusDot = Instance.new("Frame")
	statusDot.Name = "StatusDot"
	statusDot.Size = UDim2.fromOffset(5, 5)
	statusDot.Position = UDim2.fromOffset(0, 4)
	statusDot.BackgroundColor3 = ACCENT
	statusDot.BorderSizePixel = 0
	statusDot.Parent = statusRow
	corner(statusDot, 3)

	local backpackStatus = Instance.new("TextLabel")
	backpackStatus.Name = "BackpackStatus"
	backpackStatus.BackgroundTransparency = 1
	backpackStatus.Size = UDim2.new(1, -10, 1, 0)
	backpackStatus.Position = UDim2.fromOffset(10, 0)
	backpackStatus.Font = Enum.Font.Gotham
	backpackStatus.TextSize = HudChrome.FONT_STATUS
	backpackStatus.TextScaled = false
	backpackStatus.TextColor3 = ACCENT
	backpackStatus.TextTransparency = 0.12
	backpackStatus.TextXAlignment = Enum.TextXAlignment.Left
	backpackStatus.TextYAlignment = Enum.TextYAlignment.Center
	backpackStatus.TextTruncate = Enum.TextTruncate.AtEnd
	backpackStatus.Parent = statusRow
	L10nUtil.localize(backpackStatus, L10n.RoomAvailable)

	local panelSizeConstraint = Instance.new("UISizeConstraint")
	panelSizeConstraint.MinSize = Vector2.new(180, 108)
	panelSizeConstraint.MaxSize = Vector2.new(240, 140)
	panelSizeConstraint.Parent = panel

	local showBubbleGoalUI = Config.UI ~= nil and Config.UI.ShowBubbleGoalUI == true

	local globalFrame = Instance.new("Frame")
	globalFrame.Name = "BubbleGoal"
	globalFrame.Size = UDim2.new(0, 320, 0, 52)
	globalFrame.Position = UDim2.new(0.5, -160, 0, 12)
	globalFrame.BackgroundColor3 = BG
	globalFrame.BackgroundTransparency = 0.2
	globalFrame.BorderSizePixel = 0
	globalFrame.Visible = showBubbleGoalUI
	globalFrame.Active = false
	globalFrame.Parent = gui
	corner(globalFrame, 12)

	local globalValue = label(globalFrame, "0 / 0", UDim2.new(0.62, 0, 0, 22), UDim2.new(0, 10, 0, 5), true, false)
	globalValue.TextXAlignment = Enum.TextXAlignment.Right
	local globalUnit = label(globalFrame, L10n.BubblesUnit, UDim2.new(0.32, 0, 0, 22), UDim2.new(0.64, 0, 0, 5), true, true)
	globalUnit.TextXAlignment = Enum.TextXAlignment.Left

	local goalBack = Instance.new("Frame")
	goalBack.Size = UDim2.new(1, -20, 0, 12)
	goalBack.Position = UDim2.new(0, 10, 0, 32)
	goalBack.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	goalBack.BorderSizePixel = 0
	goalBack.Parent = globalFrame
	corner(goalBack, 6)

	local goalFill = Instance.new("Frame")
	goalFill.Size = UDim2.new(0, 0, 1, 0)
	goalFill.BackgroundColor3 = Color3.fromRGB(120, 255, 170)
	goalFill.BorderSizePixel = 0
	goalFill.Parent = goalBack
	corner(goalFill, 6)

	local toastHolder = Instance.new("Frame")
	toastHolder.Size = UDim2.new(0, 460, 0, 200)
	toastHolder.Position = UDim2.new(0.5, -230, 0, if showBubbleGoalUI then 78 else 16)
	toastHolder.BackgroundTransparency = 1
	toastHolder.Parent = gui
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Parent = toastHolder

	local TOAST_COLORS = {
		legendary = Color3.fromRGB(255, 180, 40),
		level = Color3.fromRGB(120, 255, 170),
		world = Color3.fromRGB(180, 140, 255),
		item = Color3.fromRGB(120, 200, 255),
		sell = Color3.fromRGB(255, 220, 100),
		backpack_full = Color3.fromRGB(255, 140, 100),
		zone_locked = Color3.fromRGB(255, 200, 90),
	}

	local FIXED_TOAST_KINDS = {
		backpack_full = true,
		sell = true,
		legendary = true,
		item = true,
		admin = true,
	}

	local function toast(text: string, kind: string?)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 36)
		frame.BackgroundColor3 = BG
		frame.BackgroundTransparency = 0.1
		frame.BorderSizePixel = 0
		frame.Parent = toastHolder
		corner(frame, 8)

		local localize = FIXED_TOAST_KINDS[kind or ""] == true
		local l = label(frame, text, UDim2.new(1, -16, 1, 0), UDim2.new(0, 8, 0, 0), true, localize)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.TextColor3 = TOAST_COLORS[kind or ""] or Color3.new(1, 1, 1)

		task.delay(4, function()
			TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			frame:Destroy()
		end)
	end

	local function attributeNumber(name: string): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end

	local function refreshBackpack()
		local current = math.max(0, attributeNumber("CurrentBubbles"))
		local capacity = math.max(0, attributeNumber("BackpackCapacity"))
		local pendingSellValue = math.max(0, attributeNumber("PendingSellValue"))
		local ratio = HudChrome.BackpackRatio(current, capacity)

		L10nUtil.dynamic(backpackLine, HudChrome.FormatBackpackLine(L10n.Backpack, current, capacity))
		backpackFill.Size = UDim2.new(ratio, 0, 1, 0)

		if ratio >= 1 then
			backpackFill.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
			backpackStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
			statusDot.BackgroundColor3 = Color3.fromRGB(255, 120, 120)
			L10nUtil.localize(backpackStatus, L10n.BackpackFull)
		elseif ratio >= Config.Backpack.NearlyFullRatio then
			backpackFill.BackgroundColor3 = Color3.fromRGB(255, 190, 70)
			backpackStatus.TextColor3 = Color3.fromRGB(255, 210, 90)
			statusDot.BackgroundColor3 = Color3.fromRGB(255, 210, 90)
			L10nUtil.localize(backpackStatus, L10n.BackpackAlmostFull)
		else
			backpackFill.BackgroundColor3 = ACCENT
			backpackStatus.TextColor3 = ACCENT
			statusDot.BackgroundColor3 = ACCENT
			L10nUtil.localize(backpackStatus, L10n.RoomAvailable)
		end

		local sellLabel = findSellValueLabel()
		if sellLabel then
			L10nUtil.dynamic(sellLabel, HudChrome.Comma(pendingSellValue))
		end
	end

	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function(stats)
		L10nUtil.dynamic(coinsValue, HudChrome.Comma(stats.Coins))

		local sold = stats.BubblesSold or 0
		local levelStart = stats.LevelStart or 0
		local nextAt = stats.NextLevelAt
		local ratio = HudChrome.XpRatio(sold, levelStart, nextAt)

		L10nUtil.dynamic(levelLine, HudChrome.FormatLevelLine(L10n.Level, stats.Level))
		if nextAt then
			L10nUtil.dynamic(xpLine, HudChrome.FormatXpLine(sold, nextAt))
		else
			L10nUtil.dynamic(xpLine, ("%s (%s)"):format(L10n.LevelMax, HudChrome.Comma(sold)))
		end
		TweenService:Create(xpFill, TweenInfo.new(0.25), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
	end)

	for _, attributeName in { "CurrentBubbles", "BackpackCapacity", "PendingSellValue", "PlayerArea" } do
		player:GetAttributeChangedSignal(attributeName):Connect(refreshBackpack)
	end
	refreshBackpack()

	task.spawn(function()
		for _ = 1, 40 do
			if findSellValueLabel() then
				refreshBackpack()
				break
			end
			task.wait(0.25)
		end
	end)

	Remotes.Event("GlobalCounter").OnClientEvent:Connect(function(total, target)
		L10nUtil.dynamic(globalValue, ("%s / %s"):format(HudChrome.Comma(total), HudChrome.Comma(target)))
		goalFill.Size = UDim2.new(math.clamp(total / target, 0, 1), 0, 1, 0)
	end)

	Remotes.Event("Announce").OnClientEvent:Connect(toast)

	-- Colonne d'actions : Inventory (InventoryUI) → Challenges → Music
	local actionColumn = Instance.new("Frame")
	actionColumn.Name = HudChrome.ACTION_COLUMN_NAME
	actionColumn.AnchorPoint = Vector2.new(1, 0)
	actionColumn.Position = UDim2.new(1, -HudChrome.ACTION_COLUMN_RIGHT, 0, HudChrome.ACTION_COLUMN_TOP)
	actionColumn.Size = UDim2.fromOffset(
		HudChrome.ACTION_BUTTON_SIZE,
		HudChrome.ACTION_BUTTON_SIZE * 3 + HudChrome.ACTION_BUTTON_GAP * 2
	)
	actionColumn.BackgroundTransparency = 1
	actionColumn.Parent = gui

	local actionList = Instance.new("UIListLayout")
	actionList.FillDirection = Enum.FillDirection.Vertical
	actionList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionList.VerticalAlignment = Enum.VerticalAlignment.Top
	actionList.Padding = UDim.new(0, HudChrome.ACTION_BUTTON_GAP)
	actionList.SortOrder = Enum.SortOrder.LayoutOrder
	actionList.Parent = actionColumn

	-- Placeholder LayoutOrder 1 pour réserver la place d'Inventory tant que InventoryUI n'a pas monté.
	local inventorySlot = Instance.new("Frame")
	inventorySlot.Name = "InventorySlot"
	inventorySlot.LayoutOrder = 1
	inventorySlot.Size = UDim2.fromOffset(HudChrome.ACTION_BUTTON_SIZE, HudChrome.ACTION_BUTTON_SIZE)
	inventorySlot.BackgroundTransparency = 1
	inventorySlot.Parent = actionColumn

	local function OpenChallenges()
		local ok, CC = pcall(function()
			return require(script.Parent.ChallengeController)
		end)
		if ok and type(CC) == "table" and type(CC.Toggle) == "function" then
			local okT, errT = xpcall(CC.Toggle, debug.traceback)
			if not okT then
				warn("[ChallengeButton] HUD OpenChallenges failed:\n" .. tostring(errT))
			end
		else
			warn("[ChallengeButton] ChallengeController.Toggle unavailable")
		end
	end
	local challengesBtn = createIconButton(
		actionColumn,
		HudChrome.CHALLENGES_BUTTON_NAME,
		2,
		HudChrome.ICON_CHALLENGES,
		L10n.Challenges,
		L10n.Challenges
	)
	challengesBtn.Activated:Connect(function()
		if game:GetService("RunService"):IsStudio() then
			print("[ChallengeButton] HUD Activated:", challengesBtn:GetFullName())
		end
		OpenChallenges()
	end)

	-- Bouton sourdine musique d'ambiance (uniquement — pas les SFX).
	local MusicController = require(script.Parent.MusicController)

	local musicBtn = createIconButton(
		actionColumn,
		HudChrome.MUSIC_BUTTON_NAME,
		3,
		HudChrome.ICON_MUSIC,
		L10n.MusicMute,
		L10n.MusicMute
	)
	local musicIcon = musicBtn:FindFirstChild("IconGlyph") :: TextLabel?

	local function refreshMusicButton()
		local isMuted = MusicController.IsMuted()
		if musicIcon then
			musicIcon.Text = if isMuted then HudChrome.ICON_MUSIC_MUTED else HudChrome.ICON_MUSIC
			musicIcon.TextColor3 = if isMuted
				then Color3.fromRGB(180, 190, 210)
				else Color3.fromRGB(120, 220, 180)
		end
		musicBtn.BackgroundColor3 = if isMuted then Color3.fromRGB(22, 26, 36) else BG_BUTTON
	end

	musicBtn.Activated:Connect(function()
		MusicController.SetMuted(not MusicController.IsMuted(), true)
		refreshMusicButton()
	end)

	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function(stats)
		if type(stats) == "table" and type(stats.MusicMuted) == "boolean" then
			MusicController.ApplyMutedFromServer(stats.MusicMuted)
			refreshMusicButton()
		end
	end)

	task.defer(refreshMusicButton)

	-- Responsive : colonne étroite (tailles fixes, pas de TextScaled).
	local function applyResponsive()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
		local inset = GuiService:GetGuiInset()
		local usableW = math.max(200, vp.X - inset.X)

		local width = HudChrome.DESKTOP_PANEL_WIDTH
		local height = HudChrome.DESKTOP_PANEL_HEIGHT
		local coinsSize = HudChrome.FONT_COINS
		local packSize = HudChrome.FONT_BACKPACK
		local levelSize = HudChrome.FONT_LEVEL
		local statusSize = HudChrome.FONT_STATUS

		if usableW < 700 then
			width = math.clamp(math.floor(usableW * 0.48), 188, 220)
			height = 118
			coinsSize = 18
			packSize = 11
			levelSize = 10
			statusSize = 9
		elseif usableW < 1100 then
			width = 208
			height = 122
		end

		panel.Size = UDim2.fromOffset(width, height)
		coinsValue.TextSize = coinsSize
		backpackLine.TextSize = packSize
		levelLine.TextSize = levelSize
		xpLine.TextSize = levelSize
		backpackStatus.TextSize = statusSize

		local btn = if usableW < 700 then 52 else HudChrome.ACTION_BUTTON_SIZE
		local gap = if usableW < 700 then 10 else HudChrome.ACTION_BUTTON_GAP
		-- Ne pas écraser le rail d'icônes docké par ChallengeController.
		if actionColumn:GetAttribute(HudChrome.DOCKED_ACTIONS_ATTR or "BPW_DockedActions") == true then
			return
		end
		actionColumn.Size = UDim2.fromOffset(btn, btn * 3 + gap * 2)
		actionList.Padding = UDim.new(0, gap)
		actionList.FillDirection = Enum.FillDirection.Vertical
		for _, child in ipairs(actionColumn:GetChildren()) do
			if child:IsA("GuiObject") and (child:IsA("TextButton") or child.Name == "InventorySlot") then
				child.Size = UDim2.fromOffset(btn, btn)
				if child.Name == "InventorySlot" then
					local inv = child:FindFirstChild(HudChrome.INVENTORY_BUTTON_NAME)
					if inv and inv:IsA("GuiObject") then
						inv.Size = UDim2.fromScale(1, 1)
					end
				end
			end
		end
	end

	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsive)
	end
	applyResponsive()

	HUD.Toast = toast
	HUD.OpenChallenges = OpenChallenges
	return HUD
end

return HUD
