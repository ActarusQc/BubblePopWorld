--!strict
-- Boutique walk-in : browse local par mur (Skills / Items / Cosmetics).
-- Caméra inchangée, freeze personnage et boutique premium sont 100% locaux :
-- aucun remote enter/exit browse, aucune mutation de Display_*/Wall_* serveur.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)
local ShopBrowseLogic = require(Shared.ShopBrowseLogic)
local ShopBrowseLayout = require(Shared.ShopBrowseLayout)
local ShopViewportModels = require(Shared.ShopViewportModels)
local ShopAvatarVisibility = require(script.Parent.ShopAvatarVisibility)

local player = Players.LocalPlayer
local ShopUI = {}

type CategoryId = "Skills" | "Items" | "Cosmetics"

type ShopRow = {
	Id: string,
	Label: string,
	Description: string?,
	Type: string?,
	Available: boolean,
	Equipable: boolean?,
	IconKey: string?,
	ButtonState: string,
	Level: number?,
	Max: number?,
	Cost: number?,
	Capacity: number?,
	Owned: boolean?,
	Equipped: boolean?,
}

type SavedState = {
	WalkSpeed: number,
	JumpPower: number,
	JumpHeight: number,
	UseJumpPower: boolean,
	AutoRotate: boolean,
	-- PlayerModule.Controls n'expose pas de getter : on mémorise l'état
	-- juste avant notre Disable (Enabled=true en pratique à l'entrée browse).
	ControlsEnabled: boolean,
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	FieldOfView: number,
}

local CATEGORY_IDS: { CategoryId } = { "Skills", "Items", "Cosmetics" }

local CATEGORY_LABEL_KEY: { [string]: string } = {
	Skills = "Skills",
	Items = "Items",
	Cosmetics = "Cosmetics",
}

local BUTTON_LABEL_KEY: { [string]: string } = {
	Buy = "Buy",
	Upgrade = "Upgrade",
	Equip = "Equip",
	Equipped = "Equipped",
	TooExpensive = "TooExpensive",
	ComingSoon = "ComingSoon",
	Locked = "Locked",
	Max = "Max",
}

local BG = Color3.fromRGB(16, 20, 30)
local CARD = Color3.fromRGB(26, 32, 46)
local MUTED = Color3.fromRGB(175, 185, 205)
local WHITE = Color3.fromRGB(245, 248, 255)
local ARROW_BG = Color3.fromRGB(38, 46, 64)
local ARROW_BG_DISABLED = Color3.fromRGB(28, 32, 42)
local ACTION_ON = Color3.fromRGB(120, 220, 160)
local ACTION_OFF = Color3.fromRGB(58, 64, 78)

local DISPLAY_ORDER = 105
local TWEEN_TIME = 0.55

local function corner(parent: Instance, r: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = parent
	return c
end

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function localized(key: string?): string
	if type(key) ~= "string" then
		return ""
	end
	local value = (L10n :: any)[key]
	return if type(value) == "string" then value else key
end

--------------------------------------------------------------------
-- État browse (100% local)
--------------------------------------------------------------------

local browse = {
	active = false,
	category = nil :: CategoryId?,
	index = 1,
	items = {} :: { ShopRow },
	coins = 0,
	saved = nil :: SavedState?,
	controls = nil :: any,
	promptEnabled = {} :: { [ProximityPrompt]: boolean },
	localTransparency = {} :: { [BasePart]: number },
	tempConns = {} :: { RBXScriptConnection },
	cameraTween = nil :: Tween?,
	actionGeneration = 0,
}

local exiting = false

function ShopUI.Start()
	--------------------------------------------------------------------
	-- UI (ScreenGui compacte, non plein écran, non opaque)
	--------------------------------------------------------------------

	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_ShopBrowse"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "BrowsePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.52, 0)
	panel.Size = UDim2.new(0.92, 0, 0.82, 0)
	panel.BackgroundColor3 = Color3.fromRGB(27, 22, 58)
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 2
	panel.Parent = gui
	local panelCorner = corner(panel, 18)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(320, 360)
	sizeConstraint.MaxSize = Vector2.new(1180, 720)
	sizeConstraint.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(164, 104, 255)
	stroke.Thickness = 4
	stroke.Transparency = 0.08
	stroke.Parent = panel

	-- Header : catégorie + position + solde coins + fermer
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -48, 0, 92)
	header.Position = UDim2.new(0, 24, 0, 18)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = panel

	local categoryTitle = Instance.new("TextLabel")
	categoryTitle.Name = "CategoryTitle"
	categoryTitle.Size = UDim2.new(0.28, 0, 1, 0)
	categoryTitle.BackgroundTransparency = 1
	categoryTitle.Font = Enum.Font.GothamBlack
	categoryTitle.TextSize = 18
	categoryTitle.TextXAlignment = Enum.TextXAlignment.Left
	categoryTitle.TextColor3 = WHITE
	categoryTitle.Text = "PREMIUM SHOP"
	categoryTitle.ZIndex = 3
	categoryTitle.Parent = header

	local categoryTabs = Instance.new("Frame")
	categoryTabs.Name = "CategoryTabs"
	categoryTabs.Size = UDim2.new(0.42, 0, 1, 0)
	categoryTabs.Position = UDim2.new(0.28, 4, 0, 0)
	categoryTabs.BackgroundTransparency = 1
	categoryTabs.ZIndex = 3
	categoryTabs.Parent = header
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 4)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = categoryTabs

	local categoryTabButtons: { [CategoryId]: TextButton } = {}
	for i, catId in ipairs(CATEGORY_IDS) do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. catId
		tab.Size = UDim2.new(0.33, -4, 1, 0)
		tab.BackgroundColor3 = Color3.fromRGB(40, 50, 70)
		tab.TextColor3 = WHITE
		tab.Font = Enum.Font.GothamBold
		tab.TextSize = 12
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = true
		tab.Selectable = true
		tab.LayoutOrder = i
		tab.ZIndex = 4
		tab.Parent = categoryTabs
		corner(tab, 8)
		L10nUtil.localize(tab, localized(CATEGORY_LABEL_KEY[catId]))
		categoryTabButtons[catId] = tab
	end

	local positionLabel = Instance.new("TextLabel")
	positionLabel.Name = "Position"
	positionLabel.Size = UDim2.new(0.12, 0, 1, 0)
	positionLabel.Position = UDim2.new(0.70, 0, 0, 0)
	positionLabel.BackgroundTransparency = 1
	positionLabel.Font = Enum.Font.GothamMedium
	positionLabel.TextSize = 14
	positionLabel.TextColor3 = MUTED
	positionLabel.Text = ""
	positionLabel.ZIndex = 3
	positionLabel.Parent = header
	L10nUtil.dynamic(positionLabel, "")

	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "Coins"
	coinsLabel.Size = UDim2.new(0.18, -44, 1, 0)
	coinsLabel.Position = UDim2.new(0.82, 0, 0, 0)
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Font = Enum.Font.GothamBold
	coinsLabel.TextSize = 16
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Right
	coinsLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	coinsLabel.Text = ""
	coinsLabel.ZIndex = 3
	coinsLabel.Parent = header
	L10nUtil.dynamic(coinsLabel, "")

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(40, 40)
	closeBtn.Position = UDim2.new(1, -40, 0, -4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 74)
	closeBtn.TextColor3 = WHITE
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = true
	closeBtn.Selectable = true
	closeBtn.ZIndex = 4
	closeBtn.Parent = header
	L10nUtil.dynamic(closeBtn, L10n.Close)
	local closeCorner = corner(closeBtn, 10)

	-- Corps : flèche gauche | viewport + texte | flèche droite
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -48, 1, -148)
	body.Position = UDim2.new(0, 24, 0, 124)
	body.BackgroundTransparency = 1
	body.ZIndex = 3
	body.Parent = panel

	local itemGrid = Instance.new("ScrollingFrame")
	itemGrid.Name = "ItemGrid"
	itemGrid.Size = UDim2.new(0.58, -10, 1, 0)
	itemGrid.BackgroundColor3 = Color3.fromRGB(42, 34, 82)
	itemGrid.BackgroundTransparency = 0.08
	itemGrid.BorderSizePixel = 0
	itemGrid.ScrollBarThickness = 8
	itemGrid.ScrollBarImageColor3 = Color3.fromRGB(196, 128, 255)
	itemGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	itemGrid.CanvasSize = UDim2.new()
	itemGrid.ZIndex = 3
	itemGrid.Parent = body
	corner(itemGrid, 16)
	local itemGridPadding = Instance.new("UIPadding")
	itemGridPadding.PaddingTop = UDim.new(0, 12)
	itemGridPadding.PaddingBottom = UDim.new(0, 12)
	itemGridPadding.PaddingLeft = UDim.new(0, 12)
	itemGridPadding.PaddingRight = UDim.new(0, 12)
	itemGridPadding.Parent = itemGrid
	local itemGridLayout = Instance.new("UIGridLayout")
	itemGridLayout.CellSize = UDim2.new(0.5, -8, 0, 116)
	itemGridLayout.CellPadding = UDim2.fromOffset(12, 12)
	itemGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	itemGridLayout.Parent = itemGrid

	local leftBtn = Instance.new("TextButton")
	leftBtn.Name = "LeftArrow"
	leftBtn.Size = UDim2.fromOffset(56, 56)
	leftBtn.AnchorPoint = Vector2.new(0, 0.5)
	leftBtn.Position = UDim2.new(0, 0, 0.5, 0)
	leftBtn.BackgroundColor3 = ARROW_BG
	leftBtn.TextColor3 = WHITE
	leftBtn.Font = Enum.Font.GothamBlack
	leftBtn.TextSize = 26
	leftBtn.Text = "<"
	leftBtn.BorderSizePixel = 0
	leftBtn.AutoButtonColor = true
	leftBtn.Selectable = true
	leftBtn.ZIndex = 4
	leftBtn.Parent = body
	leftBtn.Visible = false
	local leftCorner = corner(leftBtn, 14)

	local rightBtn = Instance.new("TextButton")
	rightBtn.Name = "RightArrow"
	rightBtn.Size = UDim2.fromOffset(56, 56)
	rightBtn.AnchorPoint = Vector2.new(1, 0.5)
	rightBtn.Position = UDim2.new(1, 0, 0.5, 0)
	rightBtn.BackgroundColor3 = ARROW_BG
	rightBtn.TextColor3 = WHITE
	rightBtn.Font = Enum.Font.GothamBlack
	rightBtn.TextSize = 26
	rightBtn.Text = ">"
	rightBtn.BorderSizePixel = 0
	rightBtn.AutoButtonColor = true
	rightBtn.Selectable = true
	rightBtn.ZIndex = 4
	rightBtn.Parent = body
	rightBtn.Visible = false
	local rightCorner = corner(rightBtn, 14)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(0.42, -10, 1, 0)
	content.Position = UDim2.new(0.58, 20, 0, 0)
	content.BackgroundColor3 = Color3.fromRGB(51, 42, 94)
	content.BackgroundTransparency = 0.08
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = body
	corner(content, 16)

	-- Présentoir local : ViewportFrame + modèle stylisé (jamais Display_* serveur).
	local VIEWPORT_SIZE = 190
	local VIEWPORT_FOV = 40

	local defaultBackground = ShopViewportModels.GetBackground(nil)

	-- Le dégradé vit sur ce Frame, jamais sur le ViewportFrame : un UIGradient
	-- enfant d'un ViewportFrame multiplie aussi l'image 3D rendue.
	local previewBackground = Instance.new("Frame")
	previewBackground.Name = "PreviewBackground"
	previewBackground.Size = UDim2.fromOffset(VIEWPORT_SIZE, VIEWPORT_SIZE)
	previewBackground.AnchorPoint = Vector2.new(0.5, 0)
	previewBackground.Position = UDim2.new(0.5, 0, 0, 18)
	previewBackground.BackgroundColor3 = Color3.new(1, 1, 1)
	previewBackground.BackgroundTransparency = 0
	previewBackground.BorderSizePixel = 0
	previewBackground.ZIndex = 3
	previewBackground.Parent = content
	local previewCorner = corner(previewBackground, 14)

	local viewportGradient = Instance.new("UIGradient")
	viewportGradient.Color = ColorSequence.new(defaultBackground.Top, defaultBackground.Bottom)
	viewportGradient.Rotation = 90
	viewportGradient.Parent = previewBackground

	local backgroundStroke = Instance.new("UIStroke")
	backgroundStroke.Thickness = 1
	backgroundStroke.Color = Color3.fromRGB(96, 116, 150)
	backgroundStroke.Transparency = 0.3
	backgroundStroke.Parent = previewBackground

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Presentation"
	viewport.Size = UDim2.fromOffset(VIEWPORT_SIZE - 6, VIEWPORT_SIZE - 6)
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.Position = UDim2.new(0.5, 0, 0, 21)
	viewport.BackgroundColor3 = ShopViewportModels.GetViewportBackground(nil)
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.ZIndex = 4
	viewport.Parent = content
	local viewportCorner = corner(viewport, 12)

	local vpCamera = Instance.new("Camera")
	vpCamera.FieldOfView = VIEWPORT_FOV
	vpCamera.Parent = viewport
	viewport.CurrentCamera = vpCamera
	vpCamera.CFrame = CFrame.new(Vector3.new(0, 0, 6), Vector3.new(0, 0, 0))

	-- Modèle courant de la preview : reconstruit à chaque changement d'item.
	-- Le fond (halo + socle) est un modèle distinct : il ne tourne pas.
	local previewModel: Model? = nil
	local previewBackdrop: Model? = nil
	local previewSpin = 0

	local function clearPreview()
		if previewModel then
			previewModel:Destroy()
			previewModel = nil
		end
		if previewBackdrop then
			previewBackdrop:Destroy()
			previewBackdrop = nil
		end
	end

	local textArea = Instance.new("Frame")
	textArea.Name = "TextArea"
	textArea.Size = UDim2.new(1, -32, 0, 138)
	textArea.Position = UDim2.new(0, 16, 0, 220)
	textArea.BackgroundTransparency = 1
	textArea.ZIndex = 3
	textArea.Parent = content

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.new(1, 0, 0, 26)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = WHITE
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = ""
	nameLabel.ZIndex = 3
	nameLabel.Parent = textArea
	L10nUtil.dynamic(nameLabel, "")

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "ItemDescription"
	descLabel.Size = UDim2.new(1, 0, 0, 40)
	descLabel.Position = UDim2.new(0, 0, 0, 28)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 13
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextColor3 = MUTED
	descLabel.Text = ""
	descLabel.ZIndex = 3
	descLabel.Parent = textArea
	L10nUtil.dynamic(descLabel, "")

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.new(0.55, 0, 0, 20)
	priceLabel.Position = UDim2.new(0, 0, 1, -20)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextSize = 14
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	priceLabel.Text = ""
	priceLabel.ZIndex = 3
	priceLabel.Parent = textArea
	L10nUtil.dynamic(priceLabel, "")

	-- Bouton action (Buy / Upgrade / Equip / états non actionnables)
	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "ActionButton"
	actionBtn.Size = UDim2.new(0, 168, 0, 40)
	actionBtn.AnchorPoint = Vector2.new(1, 1)
	actionBtn.Position = UDim2.new(1, 0, 1, 4)
	actionBtn.BackgroundColor3 = ACTION_ON
	actionBtn.TextColor3 = Color3.fromRGB(10, 14, 20)
	actionBtn.Font = Enum.Font.GothamBold
	actionBtn.TextSize = 15
	actionBtn.BorderSizePixel = 0
	actionBtn.AutoButtonColor = true
	actionBtn.Selectable = true
	actionBtn.ZIndex = 3
	actionBtn.Parent = content
	local actionCorner = corner(actionBtn, 10)
	L10nUtil.dynamic(actionBtn, "")

	--------------------------------------------------------------------
	-- Disposition responsive : Mobile / Desktop / Console (ten-foot UI)
	--------------------------------------------------------------------

	local currentLayout = ShopBrowseLayout.Resolve(ShopBrowseLayout.Modes.Desktop, { X = 1280, Y = 720 })
	local layoutPending = false

	-- PreferredInput n'existe pas sur les clients les plus anciens : on retombe
	-- alors sur TouchEnabled, ce qui préserve le comportement actuel.
	local function readPreferredInput(): string?
		local ok, value = pcall(function()
			return (UserInputService :: any).PreferredInput
		end)
		if ok and typeof(value) == "EnumItem" then
			return value.Name
		end
		return nil
	end

	local function readViewportSize(): Vector2
		local camera = Workspace.CurrentCamera
		if camera then
			return camera.ViewportSize
		end
		return Vector2.new(1280, 720)
	end

	-- AbsoluteSize du ScreenGui : tient déjà compte de l'inset supérieur, donc
	-- l'échelle calculée correspond au panneau réellement affiché.
	local function readContainerSize(): Vector2
		local size = gui.AbsoluteSize
		if size.X >= 1 and size.Y >= 1 then
			return size
		end
		return readViewportSize()
	end

	local appliedMode: string? = nil
	local appliedWidth = 0
	local appliedHeight = 0

	local function applyResponsiveBrowseLayout(force: boolean?)
		local mode = ShopBrowseLayout.ResolveMode(readPreferredInput(), readViewportSize(), UserInputService.TouchEnabled)
		local container = readContainerSize()
		if force ~= true and mode == appliedMode and container.X == appliedWidth and container.Y == appliedHeight then
			return
		end
		appliedMode = mode
		appliedWidth = container.X
		appliedHeight = container.Y

		local layout = ShopBrowseLayout.Resolve(mode, container)
		currentLayout = layout

		local p = layout.Panel
		local compact = container.X < 760 or container.Y < 560
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Size = if compact then UDim2.new(0.96, 0, 0.88, 0) else UDim2.new(0.92, 0, 0.82, 0)
		panel.Position = UDim2.new(0.5, 0, 0.52, 0)
		sizeConstraint.MinSize = Vector2.new(320, 360)
		sizeConstraint.MaxSize = Vector2.new(1180, 720)
		panelCorner.CornerRadius = UDim.new(0, if compact then 14 else 22)

		local h = layout.Header
		header.Size = UDim2.new(1, -h.InsetX * 2, 0, h.Height)
		header.Position = UDim2.new(0, h.InsetX, 0, h.OffsetY)
		categoryTitle.Size = UDim2.new(h.TitleWidthScale, 0, 1, 0)
		categoryTitle.TextSize = h.TitleSize
		positionLabel.Size = UDim2.new(h.CounterWidthScale, 0, 1, 0)
		positionLabel.Position = UDim2.new(h.CounterXScale, 0, 0, 0)
		positionLabel.TextSize = h.CounterSize
		coinsLabel.Size = UDim2.new(h.CoinsWidthScale, -h.CoinsInset, 1, 0)
		coinsLabel.Position = UDim2.new(h.CoinsXScale, 0, 0, 0)
		coinsLabel.TextSize = h.CoinsSize
		closeBtn.Size = UDim2.fromOffset(h.CloseSize, h.CloseSize)
		closeBtn.Position = UDim2.new(1, -h.CloseSize, 0, h.CloseOffsetY)
		closeBtn.TextSize = h.CloseTextSize
		closeCorner.CornerRadius = UDim.new(0, h.CloseCorner)

		local b = layout.Body
		body.Size = UDim2.new(1, -48, 1, -148)
		body.Position = UDim2.new(0, 24, 0, 124)
		itemGrid.Size = if compact then UDim2.new(1, 0, 0.48, 0) else UDim2.new(0.58, -10, 1, 0)
		itemGridLayout.CellSize = if compact then UDim2.new(1, -4, 0, 100) else UDim2.new(0.5, -8, 0, 116)
		content.Size = if compact then UDim2.new(1, 0, 0.49, 0) else UDim2.new(0.42, -10, 1, 0)
		content.Position = if compact then UDim2.new(0, 0, 0.51, 0) else UDim2.new(0.58, 20, 0, 0)

		local a = layout.Arrow
		leftBtn.Size = UDim2.fromOffset(a.Size, a.Size)
		leftBtn.TextSize = a.TextSize
		leftCorner.CornerRadius = UDim.new(0, a.Corner)
		rightBtn.Size = UDim2.fromOffset(a.Size, a.Size)
		rightBtn.TextSize = a.TextSize
		rightCorner.CornerRadius = UDim.new(0, a.Corner)

		local v = layout.Preview
		previewBackground.Size = UDim2.fromOffset(v.Width, v.Height)
		previewBackground.Position = UDim2.new(0, 0, 0.5, -v.Height / 2)
		previewCorner.CornerRadius = UDim.new(0, v.Corner)
		local innerWidth = v.Width - v.Inset * 2
		local innerHeight = v.Height - v.Inset * 2
		viewport.Size = UDim2.fromOffset(innerWidth, innerHeight)
		viewport.Position = UDim2.new(0, v.Inset, 0.5, -innerHeight / 2)
		viewportCorner.CornerRadius = UDim.new(0, v.InnerCorner)

		local t = layout.Text
		textArea.Size = UDim2.new(1, -t.InsetX, 1, 0)
		textArea.Position = UDim2.new(0, t.InsetX, 0, 0)
		nameLabel.Size = UDim2.new(1, 0, 0, t.NameHeight)
		nameLabel.TextSize = t.NameSize
		descLabel.Size = UDim2.new(1, 0, 0, t.DescHeight)
		descLabel.Position = UDim2.new(0, 0, 0, t.DescOffsetY)
		descLabel.TextSize = t.DescSize
		priceLabel.Size = UDim2.new(t.PriceWidthScale, 0, 0, t.PriceHeight)
		priceLabel.Position = UDim2.new(0, 0, t.PriceYScale, t.PriceYOffset)
		priceLabel.TextSize = t.PriceSize

		local act = layout.Action
		actionBtn.AnchorPoint = Vector2.new(act.AnchorX, act.AnchorY)
		actionBtn.Size = UDim2.fromOffset(act.Width, act.Height)
		actionBtn.Position = UDim2.new(act.XScale, act.XOffset, act.YScale, act.YOffset)
		actionBtn.TextSize = act.TextSize
		actionBtn.AnchorPoint = Vector2.new(0.5, 1)
		actionBtn.Size = UDim2.new(1, -32, 0, if compact then 44 else 54)
		actionBtn.Position = UDim2.new(0.5, 0, 1, -16)
		actionBtn.TextSize = if compact then 16 else 20
		actionCorner.CornerRadius = UDim.new(0, 12)

		local previewSize = if compact then 104 else math.clamp(math.floor(content.AbsoluteSize.Y * 0.42), 150, 210)
		previewBackground.Size = UDim2.fromOffset(previewSize, previewSize)
		previewBackground.AnchorPoint = Vector2.new(0.5, 0)
		previewBackground.Position = UDim2.new(0.5, 0, 0, 16)
		viewport.Size = UDim2.fromOffset(previewSize - 8, previewSize - 8)
		viewport.AnchorPoint = Vector2.new(0.5, 0)
		viewport.Position = UDim2.new(0.5, 0, 0, 20)
		textArea.Size = UDim2.new(1, -32, 0, if compact then 92 else 138)
		textArea.Position = UDim2.new(0, 16, 0, previewSize + 24)
	end

	-- Plusieurs événements d'entrée peuvent arriver en rafale : on temporise, et
	-- on ne reconstruit jamais la preview 3D.
	local function requestLayoutRefresh()
		if layoutPending then
			return
		end
		layoutPending = true
		task.delay(0.1, function()
			layoutPending = false
			applyResponsiveBrowseLayout()
		end)
	end

	--------------------------------------------------------------------
	-- Navigation manette : graphe fermé, aucune sortie du panneau
	--------------------------------------------------------------------

	local function selectionStroke(button: GuiButton): UIStroke
		local outline = Instance.new("UIStroke")
		outline.Name = "SelectionOutline"
		outline.Thickness = 3
		outline.Color = Color3.fromRGB(255, 255, 255)
		outline.Transparency = 1
		outline.Parent = button

		button.SelectionGained:Connect(function()
			outline.Transparency = 0.1
		end)
		button.SelectionLost:Connect(function()
			outline.Transparency = 1
		end)
		return outline
	end

	for _, button in ipairs({ leftBtn, rightBtn, actionBtn, closeBtn }) do
		selectionStroke(button)
	end

	leftBtn.NextSelectionLeft = leftBtn
	leftBtn.NextSelectionRight = actionBtn
	leftBtn.NextSelectionUp = closeBtn
	leftBtn.NextSelectionDown = leftBtn

	actionBtn.NextSelectionLeft = leftBtn
	actionBtn.NextSelectionRight = rightBtn
	actionBtn.NextSelectionUp = closeBtn
	actionBtn.NextSelectionDown = actionBtn

	rightBtn.NextSelectionLeft = actionBtn
	rightBtn.NextSelectionRight = rightBtn
	rightBtn.NextSelectionUp = closeBtn
	rightBtn.NextSelectionDown = rightBtn

	closeBtn.NextSelectionLeft = closeBtn
	closeBtn.NextSelectionRight = closeBtn
	closeBtn.NextSelectionUp = closeBtn
	closeBtn.NextSelectionDown = actionBtn

	local function isPanelButton(instance: Instance?): boolean
		return instance == leftBtn or instance == rightBtn or instance == actionBtn or instance == closeBtn
	end

	--------------------------------------------------------------------
	-- Présentoir : rotation douce pendant le browse (connexion temporaire)
	--------------------------------------------------------------------

	local function startSpin()
		local conn = RunService.RenderStepped:Connect(function(dt)
			previewSpin = (previewSpin + dt * 0.55) % (math.pi * 2)
			local model = previewModel
			if model then
				model:PivotTo(CFrame.Angles(0, previewSpin, 0))
			end
		end)
		table.insert(browse.tempConns, conn)
	end

	--------------------------------------------------------------------
	-- Contrôles joueur (PlayerModule.Controls) — best-effort, jamais requis
	--------------------------------------------------------------------

	local function tryGetControls(): any
		local ok, controls = pcall(function()
			local playerScripts = player:WaitForChild("PlayerScripts", 2)
			local moduleScript = playerScripts and playerScripts:WaitForChild("PlayerModule", 2)
			if not moduleScript then
				return nil
			end
			local playerModule = require(moduleScript :: any)
			return playerModule:GetControls()
		end)
		if ok then
			return controls
		end
		return nil
	end

	--------------------------------------------------------------------
	-- Recherche des instances ItemShop (peut être sous BubblePopWorld.Lobby)
	--------------------------------------------------------------------

	local function findItemShop(): Model?
		local found = Workspace:FindFirstChild("ItemShop", true)
		if found and found:IsA("Model") then
			return found
		end
		return nil
	end

	--------------------------------------------------------------------
	-- Rendu
	--------------------------------------------------------------------

	local presentedKey: string? = nil

	local function updatePresentation(item: ShopRow?)
		local wantedId = if item then item.Id else nil
		local key = (wantedId or "-") .. "|" .. (browse.category or "-")
		if previewModel and presentedKey == key then
			return
		end
		presentedKey = key

		clearPreview()

		local category = browse.category
		local background = ShopViewportModels.GetBackground(category)
		viewportGradient.Color = ColorSequence.new(background.Top, background.Bottom)
		viewport.BackgroundColor3 = ShopViewportModels.GetViewportBackground(category)

		local lighting = ShopViewportModels.GetLighting(category)
		viewport.Ambient = lighting.Ambient
		viewport.LightColor = lighting.LightColor
		viewport.LightDirection = lighting.LightDirection

		local model, bounds = ShopViewportModels.Build(wantedId, if item then item.Type else nil, category)
		vpCamera.CFrame = ShopViewportModels.GetCameraCFrame(bounds, VIEWPORT_FOV)
		model:PivotTo(CFrame.Angles(0, previewSpin, 0))
		model.Parent = viewport
		previewModel = model

		local backdrop = ShopViewportModels.BuildBackdrop(category, bounds, VIEWPORT_FOV)
		backdrop.Parent = viewport
		previewBackdrop = backdrop
	end

	local function refreshPresentation()
		local count = #browse.items
		local item: ShopRow? = if count > 0 then browse.items[browse.index] else nil

		local categoryKey = if browse.category then CATEGORY_LABEL_KEY[browse.category] else nil
		L10nUtil.localize(categoryTitle, localized(categoryKey))
		for catId, tab in pairs(categoryTabButtons) do
			local active = catId == browse.category
			tab.BackgroundColor3 = if active
				then Color3.fromRGB(70, 140, 220)
				else Color3.fromRGB(40, 50, 70)
		end
		L10nUtil.dynamic(positionLabel, if count > 0 then string.format("%d / %d", browse.index, count) else "")
		L10nUtil.dynamic(coinsLabel, comma(browse.coins) .. " " .. L10n.CoinsUnit)

		updatePresentation(item)

		for _, child in ipairs(itemGrid:GetChildren()) do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		for itemIndex, row in ipairs(browse.items) do
			local card = Instance.new("TextButton")
			card.Name = "ItemCard_" .. row.Id
			card.LayoutOrder = itemIndex
			card.BackgroundColor3 = if itemIndex == browse.index then Color3.fromRGB(101, 66, 170) else Color3.fromRGB(58, 47, 105)
			card.Text = ""
			card.BorderSizePixel = 0
			card.AutoButtonColor = true
			card.Selectable = true
			card.ZIndex = 4
			card.Parent = itemGrid
			corner(card, 12)
			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = if itemIndex == browse.index then Color3.fromRGB(255, 201, 74) else Color3.fromRGB(131, 101, 191)
			cardStroke.Thickness = if itemIndex == browse.index then 3 else 1.5
			cardStroke.Transparency = 0.08
			cardStroke.Parent = card
			local cardName = Instance.new("TextLabel")
			cardName.Size = UDim2.new(1, -20, 0, 42)
			cardName.Position = UDim2.fromOffset(10, 10)
			cardName.BackgroundTransparency = 1
			cardName.Font = Enum.Font.GothamBlack
			cardName.TextSize = 16
			cardName.TextWrapped = true
			cardName.TextColor3 = WHITE
			cardName.Text = row.Label
			cardName.ZIndex = 5
			cardName.Parent = card
			local cardPrice = Instance.new("TextLabel")
			cardPrice.Size = UDim2.new(1, -20, 0, 26)
			cardPrice.Position = UDim2.new(0, 10, 1, -38)
			cardPrice.BackgroundColor3 = Color3.fromRGB(91, 186, 73)
			cardPrice.BorderSizePixel = 0
			cardPrice.Font = Enum.Font.GothamBold
			cardPrice.TextSize = 15
			cardPrice.TextColor3 = Color3.fromRGB(255, 255, 255)
			cardPrice.Text = if type(row.Cost) == "number" then comma(row.Cost) .. " " .. L10n.CoinsUnit else "—"
			cardPrice.ZIndex = 5
			cardPrice.Parent = card
			corner(cardPrice, 8)
			card.Activated:Connect(function()
				browse.index = itemIndex
				refreshPresentation()
			end)
		end

		if not item then
			L10nUtil.dynamic(nameLabel, "")
			L10nUtil.dynamic(descLabel, "")
			L10nUtil.dynamic(priceLabel, "—")
			L10nUtil.dynamic(actionBtn, "")
			actionBtn.Active = false
			actionBtn.AutoButtonColor = false
			actionBtn.BackgroundColor3 = ACTION_OFF
			leftBtn.Active = false
			rightBtn.Active = false
			leftBtn.BackgroundColor3 = ARROW_BG_DISABLED
			rightBtn.BackgroundColor3 = ARROW_BG_DISABLED
			return
		end

		L10nUtil.dynamic(nameLabel, item.Label)
		L10nUtil.dynamic(descLabel, item.Description or "")

		if item.Available ~= true or type(item.Cost) ~= "number" or item.Cost < 0 then
			L10nUtil.dynamic(priceLabel, "—")
		else
			local priceText = comma(item.Cost) .. " " .. L10n.CoinsUnit
			if item.Type == "Upgrade" and type(item.Level) == "number" and type(item.Max) == "number" then
				priceText ..= string.format("  (Lv %d/%d)", item.Level, item.Max)
			end
			L10nUtil.dynamic(priceLabel, priceText)
		end

		local buttonState = item.ButtonState
		local labelKey = BUTTON_LABEL_KEY[buttonState] or "Locked"
		L10nUtil.localize(actionBtn, localized(labelKey))

		local canInvoke = ShopBrowseLogic.CanInvokeAction(item)
		actionBtn.Active = canInvoke
		actionBtn.Selectable = canInvoke
		actionBtn.AutoButtonColor = canInvoke
		actionBtn.BackgroundColor3 = if canInvoke then ACTION_ON else ACTION_OFF
		actionBtn.TextColor3 = if canInvoke then Color3.fromRGB(10, 14, 20) else Color3.fromRGB(190, 198, 214)

		local canNavigate = count > 1
		leftBtn.Active = canNavigate
		rightBtn.Active = canNavigate
		leftBtn.Selectable = canNavigate
		rightBtn.Selectable = canNavigate
		leftBtn.AutoButtonColor = canNavigate
		rightBtn.AutoButtonColor = canNavigate
		leftBtn.BackgroundColor3 = if canNavigate then ARROW_BG else ARROW_BG_DISABLED
		rightBtn.BackgroundColor3 = if canNavigate then ARROW_BG else ARROW_BG_DISABLED

		if UserInputService.GamepadEnabled and canInvoke then
			GuiService.SelectedObject = actionBtn
		end

		-- Console : la sélection ne doit jamais rester sur un bouton inactif.
		if currentLayout.Mode == ShopBrowseLayout.Modes.Console then
			local selected = GuiService.SelectedObject
			local stale = selected == nil
				or (isPanelButton(selected) and not (selected :: GuiButton).Selectable)
			if stale then
				GuiService.SelectedObject = if canInvoke
					then actionBtn
					elseif canNavigate then rightBtn
					else closeBtn
			end
		end
	end

	--------------------------------------------------------------------
	-- ExitBrowse() — unique, idempotente, tous les chemins de sortie
	--------------------------------------------------------------------

	local function exitBrowse()
		if exiting then
			return
		end
		exiting = true

		local ok = pcall(function()
			for _, conn in ipairs(browse.tempConns) do
				if conn.Connected then
					conn:Disconnect()
				end
			end
			table.clear(browse.tempConns)

			ShopAvatarVisibility.Restore(browse.localTransparency)

			if browse.cameraTween then
				browse.cameraTween:Cancel()
				browse.cameraTween = nil
			end

			local saved = browse.saved
			if saved then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.WalkSpeed = saved.WalkSpeed
					humanoid.UseJumpPower = saved.UseJumpPower
					humanoid.JumpPower = saved.JumpPower
					humanoid.JumpHeight = saved.JumpHeight
					humanoid.AutoRotate = saved.AutoRotate
				end

				if browse.controls and saved.ControlsEnabled then
					pcall(function()
						(browse.controls :: any):Enable()
					end)
				end

				local cam = Workspace.CurrentCamera
				if cam then
					cam.CameraType = saved.CameraType
					cam.CameraSubject = saved.CameraSubject
					cam.FieldOfView = saved.FieldOfView
				end
			end

			for prompt, wasEnabled in pairs(browse.promptEnabled) do
				if prompt and prompt.Parent then
					prompt.Enabled = wasEnabled
				end
			end

			panel.Visible = false
			GuiService.SelectedObject = nil
			clearPreview()
			presentedKey = nil
		end)

		-- Filet de sécurité idempotent si une autre restauration a levé une erreur.
		ShopAvatarVisibility.Restore(browse.localTransparency)

		if not ok then
			warn("[ShopUI] ExitBrowse restore error (best-effort)")
		end

		table.clear(browse.promptEnabled)
		table.clear(browse.tempConns)
		browse.active = false
		browse.category = nil
		browse.items = {}
		browse.index = 1
		browse.saved = nil
		browse.controls = nil
		browse.cameraTween = nil
		browse.actionGeneration += 1

		exiting = false
	end

	--------------------------------------------------------------------
	-- Fetch + refresh serveur (sans fermer le browse)
	--------------------------------------------------------------------

	local function refreshFromServer(preserveId: string?)
		local ok, data = pcall(function()
			return Remotes.Func("GetShopData"):InvokeServer()
		end)
		if not ok or type(data) ~= "table" or not browse.category then
			return false
		end

		local categories = data.Categories
		local rows: { ShopRow } = if type(categories) == "table" and type(categories[browse.category]) == "table"
			then categories[browse.category]
			else {}

		browse.items = rows
		browse.coins = if type(data.Coins) == "number" then data.Coins else browse.coins
		browse.index = ShopBrowseLogic.FindIndexById(rows, preserveId, browse.index)
		refreshPresentation()
		return true
	end

	--------------------------------------------------------------------
	-- EnterBrowse(category) — protégé xpcall, jamais de mutation serveur
	--------------------------------------------------------------------

	local function enterBrowse(category: CategoryId)
		local itemShop = findItemShop()
		if not itemShop then
			error("ItemShop introuvable dans Workspace")
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (character and humanoid) then
			error("Character/Humanoid introuvable")
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			error("CurrentCamera introuvable")
		end

		-- 1) Mémoriser EXACTEMENT l'état avant freeze (jamais hardcodé à la restauration).
		-- ControlsEnabled : PlayerModule n'a pas de getter public ; on capture l'état
		-- juste avant notre Disable (Enabled en pratique quand le joueur ouvre le browse).
		local controls = tryGetControls()
		browse.saved = {
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
			UseJumpPower = humanoid.UseJumpPower,
			AutoRotate = humanoid.AutoRotate,
			ControlsEnabled = controls ~= nil,
			CameraType = camera.CameraType,
			CameraSubject = camera.CameraSubject,
			FieldOfView = camera.FieldOfView,
		}
		browse.controls = controls

		-- 2) Mémoriser puis masquer localement corps, accessoires et outils équipés.
		table.clear(browse.localTransparency)
		-- Le personnage reste visible : la caméra du joueur n'est plus remplacée.
		table.insert(
			browse.tempConns,
			character.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("BasePart") then
					ShopAvatarVisibility.HidePart(descendant, browse.localTransparency)
				end
			end)
		)

		-- 3) Mémoriser Enabled original de CHAQUE prompt boutique avant de tout désactiver.
		table.clear(browse.promptEnabled)
		local promptRoots: { Instance } = { itemShop }
		local world = Workspace:FindFirstChild("BubblePopWorld")
		local hub = world and world:FindFirstChild("CentralHub")
		local functional = hub and hub:FindFirstChild("HubFunction")
		if functional then
			table.insert(promptRoots, functional)
		end
		for _, root in ipairs(promptRoots) do
			for _, descendant in ipairs(root:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") then
					browse.promptEnabled[descendant] = descendant.Enabled
				end
			end
		end

		-- 4) Freeze local (pas de téléport).
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
		if browse.controls then
			pcall(function()
				(browse.controls :: any):Disable()
			end)
		end

		-- 5) Désactiver localement tous les prompts boutique (jamais côté serveur).
		for prompt in pairs(browse.promptEnabled) do
			prompt.Enabled = false
		end

		-- 6) La caméra reste strictement inchangée pendant l'ouverture de la boutique.

		-- 7) Charger les données catégorie, index 1, UI compacte visible.
		local ok, data = pcall(function()
			return Remotes.Func("GetShopData"):InvokeServer()
		end)
		if not ok or type(data) ~= "table" then
			error("GetShopData a échoué")
		end

		local categories = data.Categories
		local rows: { ShopRow } = if type(categories) == "table" and type(categories[category]) == "table"
			then categories[category]
			else {}

		browse.active = true
		browse.category = category
		browse.items = rows
		browse.index = 1
		browse.coins = if type(data.Coins) == "number" then data.Coins else 0

		panel.Visible = true
		applyResponsiveBrowseLayout(true)
		startSpin()
		refreshPresentation()

		-- Personnage : sortir proprement sur mort / respawn / Humanoid disparu pendant le browse.
		table.insert(
			browse.tempConns,
			humanoid.Died:Connect(function()
				exitBrowse()
			end)
		)
		table.insert(
			browse.tempConns,
			humanoid.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					exitBrowse()
				end
			end)
		)
		table.insert(
			browse.tempConns,
			player.CharacterRemoving:Connect(function(removedCharacter)
				if removedCharacter == character then
					exitBrowse()
				end
			end)
		)
	end

	--------------------------------------------------------------------
	-- Navigation / action / catégories
	--------------------------------------------------------------------

	local function tweenCameraToCategory(category: CategoryId)
		local itemShop = findItemShop()
		if not itemShop then
			return
		end
		local cameraPoint = itemShop:FindFirstChild("CameraPoint_" .. category)
		local display = itemShop:FindFirstChild("Display_" .. category)
		local camera = Workspace.CurrentCamera
		if not (camera and cameraPoint and cameraPoint:IsA("BasePart")) then
			return
		end
		local lookAtPos = cameraPoint.Position + cameraPoint.CFrame.LookVector * 5
		if display then
			local displayModel = display :: Instance
			if displayModel:IsA("Model") then
				local primary = displayModel.PrimaryPart
				lookAtPos = if primary then primary.Position else displayModel:GetPivot().Position
			elseif displayModel:IsA("BasePart") then
				lookAtPos = displayModel.Position
			end
		end
		local targetCFrame = CFrame.lookAt(cameraPoint.Position, lookAtPos)
		if browse.cameraTween then
			browse.cameraTween:Cancel()
		end
		local tween = TweenService:Create(
			camera,
			TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = targetCFrame }
		)
		browse.cameraTween = tween
		tween:Play()
	end

	local function switchCategory(category: CategoryId)
		if not browse.active or browse.category == category then
			return
		end
		local ok, data = pcall(function()
			return Remotes.Func("GetShopData"):InvokeServer()
		end)
		if not ok or type(data) ~= "table" then
			warn("[ShopUI] switchCategory GetShopData failed")
			return
		end
		local categories = data.Categories
		local rows: { ShopRow } = if type(categories) == "table" and type(categories[category]) == "table"
			then categories[category]
			else {}
		browse.category = category
		browse.items = rows
		browse.index = 1
		browse.coins = if type(data.Coins) == "number" then data.Coins else browse.coins
		refreshPresentation()
	end

	local function navigate(direction: number)
		if not browse.active then
			return
		end
		local count = #browse.items
		if count <= 1 then
			return
		end
		if direction < 0 then
			browse.index = ShopBrowseLogic.PrevIndex(browse.index, count)
		else
			browse.index = ShopBrowseLogic.NextIndex(browse.index, count)
		end
		refreshPresentation()
	end

	local function invokeAction()
		if not browse.active then
			return
		end
		local item = browse.items[browse.index]
		if not ShopBrowseLogic.CanInvokeAction(item) then
			return
		end
		local remoteName = ShopBrowseLogic.RemoteForButtonState(item.ButtonState)
		if not remoteName then
			return
		end

		browse.actionGeneration += 1
		local generation = browse.actionGeneration
		actionBtn.Active = false
		local id = item.Id
		local ok, success, message = pcall(function()
			return Remotes.Func(remoteName):InvokeServer(id)
		end)

		if generation ~= browse.actionGeneration or not browse.active then
			return
		end

		if ok and success == true then
			refreshFromServer(id)
			return
		end

		L10nUtil.dynamic(actionBtn, if type(message) == "string" then message else L10n.Denied)
		task.wait(1)
		if generation ~= browse.actionGeneration or not browse.active then
			return
		end
		refreshFromServer(id)
	end

	--------------------------------------------------------------------
	-- Connexions permanentes (ProximityPrompt, entrées, personnage)
	--------------------------------------------------------------------

	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= player then
			return
		end
		local category = prompt:GetAttribute("BPW_ShopCategory")
		if category ~= "Skills" and category ~= "Items" and category ~= "Cosmetics" then
			return
		end

		if browse.active then
			exitBrowse()
		end

		local ok = xpcall(function()
			enterBrowse(category :: CategoryId)
		end, function(err)
			warn("[ShopUI] EnterBrowse error:", err)
			return err
		end)
		if not ok then
			exitBrowse()
		end
	end)

	for catId, tab in pairs(categoryTabButtons) do
		tab.Activated:Connect(function()
			switchCategory(catId)
		end)
	end

	leftBtn.Activated:Connect(function()
		navigate(-1)
	end)
	rightBtn.Activated:Connect(function()
		navigate(1)
	end)
	actionBtn.Activated:Connect(invokeAction)
	closeBtn.Activated:Connect(exitBrowse)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not browse.active then
			return
		end
		if processed then
			return
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if GuiService.MenuIsOpen then
			return
		end

		local keyCode = input.KeyCode
		if keyCode == Enum.KeyCode.Escape or keyCode == Enum.KeyCode.ButtonB then
			exitBrowse()
		elseif
			keyCode == Enum.KeyCode.Left
			or keyCode == Enum.KeyCode.Q
			or keyCode == Enum.KeyCode.DPadLeft
			or keyCode == Enum.KeyCode.ButtonL1
		then
			navigate(-1)
		elseif
			keyCode == Enum.KeyCode.Right
			or keyCode == Enum.KeyCode.E
			or keyCode == Enum.KeyCode.DPadRight
			or keyCode == Enum.KeyCode.ButtonR1
		then
			navigate(1)
		end
	end)

	--------------------------------------------------------------------
	-- Suivi des changements d'entrée et d'écran (jamais de rebuild 3D)
	--------------------------------------------------------------------

	applyResponsiveBrowseLayout(true)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(requestLayoutRefresh)
	UserInputService.GamepadConnected:Connect(requestLayoutRefresh)
	UserInputService.GamepadDisconnected:Connect(requestLayoutRefresh)
	UserInputService.LastInputTypeChanged:Connect(requestLayoutRefresh)

	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(requestLayoutRefresh)
	end)

	local cameraConnection: RBXScriptConnection? = nil
	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(requestLayoutRefresh)
		end
		requestLayoutRefresh()
	end

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	player.CharacterAdded:Connect(function()
		if browse.active then
			exitBrowse()
		end
	end)

	Players.PlayerRemoving:Connect(function(removingPlayer)
		if removingPlayer == player and browse.active then
			exitBrowse()
		end
	end)
end

return ShopUI
