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

type CategoryId = "Skills" | "Items" | "Hats" | "Vests" | "Shirts" | "Accessories" | "Shoes"

type ShopRow = {
	Id: string,
	Label: string,
	Description: string?,
	Type: string?,
	Available: boolean,
	Equipable: boolean?,
	IconKey: string?,
	ModelName: string?,
	ButtonState: string,
	Level: number?,
	Max: number?,
	Cost: number?,
	Capacity: number?,
	Owned: boolean?,
	Equipped: boolean?,
	Slot: string?,
	Rarity: string?,
}

local function buildImportedAccessoryPreview(modelName: string?): (Model?, ShopViewportModels.Bounds?)
	if type(modelName) ~= "string" or modelName == "" then
		return nil, nil
	end
	local shopAssets = ReplicatedStorage:FindFirstChild("ShopAssets")
	local hats = if shopAssets then shopAssets:FindFirstChild("Hats") else nil
	local accessory = if hats then hats:FindFirstChild(modelName) else nil
	local sourceHandle = if accessory then accessory:FindFirstChild("Handle") else nil
	if not sourceHandle or not sourceHandle:IsA("BasePart") then
		return nil, nil
	end

	local model = Instance.new("Model")
	model.Name = "Preview_" .. modelName
	-- Imported hat assets face away from the shop camera in their attachment
	-- orientation. Keep that orientation for gameplay and only turn the preview.
	model:SetAttribute("ShopPreviewYaw", math.pi)
	local handle = sourceHandle:Clone()
	handle.Name = "PreviewHandle"
	handle.Anchored = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.CastShadow = false
	for _, descendant in handle:GetDescendants() do
		if descendant:IsA("Weld") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end

	-- Reproduce Roblox's accessory alignment: the HatAttachment defines which
	-- way is up and which way is the front, regardless of the imported mesh axes.
	local hatAttachment = handle:FindFirstChild("HatAttachment")
	local attachmentRotation = if hatAttachment and hatAttachment:IsA("Attachment")
		then hatAttachment.CFrame.Rotation
		else CFrame.new()
	handle.CFrame = attachmentRotation:Inverse()
	handle.Parent = model

	-- An invisible fixed pivot lets the model spin without replacing the
	-- attachment-derived orientation of the visible handle.
	local pivot = Instance.new("Part")
	pivot.Name = "PreviewPivot"
	pivot.Size = Vector3.new(0.05, 0.05, 0.05)
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanTouch = false
	pivot.CanQuery = false
	pivot.CastShadow = false
	pivot.CFrame = CFrame.new()
	pivot.Parent = model
	model.PrimaryPart = pivot
	local size = handle.Size
	local bounds: ShopViewportModels.Bounds = {
		Center = Vector3.new(),
		Size = size,
		Radius = math.max(0.5, size.Magnitude * 0.5),
	}
	return model, bounds
end

local function buildImportedShirtPreview(modelName: string?): (Model?, ShopViewportModels.Bounds?)
	if type(modelName) ~= "string" or modelName == "" then return nil, nil end
	local shopAssets = ReplicatedStorage:FindFirstChild("ShopAssets")
	local shirts = if shopAssets then shopAssets:FindFirstChild("Shirts") else nil
	local source = if shirts then shirts:FindFirstChild(modelName, true) else nil
	if not source or not source:IsA("Shirt") then return nil, nil end
	local model = Instance.new("Model")
	model.Name = "Preview_" .. modelName
	local function bodyPart(name: string, size: Vector3, position: Vector3)
		local part = Instance.new("Part")
		part.Name = name; part.Size = size; part.Position = position
		part.Anchored = true; part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
		part.Color = Color3.fromRGB(235, 235, 235); part.Parent = model
		return part
	end
	local torso = bodyPart("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
	bodyPart("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0))
	bodyPart("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0))
	local shirt = source:Clone(); shirt.Parent = model
	model.PrimaryPart = torso
	return model, { Center = Vector3.new(), Size = Vector3.new(4, 2, 1), Radius = 2.3 }
end

local function getImportedShirtImage(modelName: string?): string?
	if type(modelName) ~= "string" or modelName == "" then return nil end
	local shopAssets = ReplicatedStorage:FindFirstChild("ShopAssets")
	local shirts = if shopAssets then shopAssets:FindFirstChild("Shirts") else nil
	local source = if shirts then shirts:FindFirstChild(modelName, true) else nil
	if source and source:IsA("Shirt") and source.ShirtTemplate ~= "" then
		return source.ShirtTemplate
	end
	return nil
end

local function buildImportedCosmeticPreview(modelName: string?, category: CategoryId?): (Model?, ShopViewportModels.Bounds?)
	if category == "Shirts" then return buildImportedShirtPreview(modelName) end
	return buildImportedAccessoryPreview(modelName)
end

local function getPreviewCameraCFrame(model: Model, bounds: ShopViewportModels.Bounds, fieldOfView: number): CFrame
	if type(model:GetAttribute("ShopPreviewYaw")) == "number" then
		-- Hats are shallow vertically, so the regular elevated shop camera shows
		-- mostly their crown. A level catalogue view presents their front instead.
		local yaw = math.rad(-10)
		local direction = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		local distance = ShopViewportModels.GetCameraDistance(bounds.Radius, fieldOfView)
		return CFrame.lookAt(direction * distance, Vector3.new())
	end
	return ShopViewportModels.GetCameraCFrame(bounds, fieldOfView)
end

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

local CATEGORY_IDS: { CategoryId } = { "Skills", "Items", "Hats", "Vests", "Shirts", "Accessories", "Shoes" }

local CATEGORY_LABEL_KEY: { [string]: string } = {
	Skills = "Skills",
	Items = "Items",
	Hats = "Hats",
	Vests = "Vests",
	Shirts = "Shirts",
	Accessories = "Accessories",
	Shoes = "Shoes",
}

local BUTTON_LABEL_KEY: { [string]: string } = {
	Buy = "Buy",
	Upgrade = "Upgrade",
	Equip = "Equip",
	EquipCosmetic = "Equip",
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

local function corner(parent: Instance, r: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = parent
	return c
end

local function createShirtSilhouette(parent: Instance, size: UDim2, position: UDim2, zIndex: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "ShirtSilhouette"
	holder.Size = size; holder.Position = position
	holder.BackgroundTransparency = 1; holder.ZIndex = zIndex; holder.Parent = parent
	local function panel(name: string, panelSize: UDim2, panelPosition: UDim2, rotation: number, offset: Vector2, rectSize: Vector2)
		local image = Instance.new("ImageLabel")
		image.Name = name; image.Size = panelSize; image.Position = panelPosition
		image.AnchorPoint = Vector2.new(0.5, 0.5); image.BackgroundTransparency = 1
		image.ImageRectOffset = offset; image.ImageRectSize = rectSize
		image.ScaleType = Enum.ScaleType.Stretch; image.Rotation = rotation
		image.ZIndex = zIndex; image.Parent = holder
		return image
	end
	panel("LeftSleeve", UDim2.fromScale(0.31, 0.54), UDim2.fromScale(0.20, 0.38), 18, Vector2.new(19,355), Vector2.new(64,128))
	panel("RightSleeve", UDim2.fromScale(0.31, 0.54), UDim2.fromScale(0.80, 0.38), -18, Vector2.new(503,355), Vector2.new(64,128))
	panel("Torso", UDim2.fromScale(0.57, 0.72), UDim2.fromScale(0.50, 0.52), 0, Vector2.new(231,74), Vector2.new(128,128))
	local collar = Instance.new("Frame")
	collar.Name = "Collar"; collar.Size = UDim2.fromScale(0.20,0.10); collar.Position = UDim2.fromScale(0.40,0.14)
	collar.BackgroundColor3 = Color3.fromRGB(18,48,82); collar.BorderSizePixel = 0; collar.ZIndex = zIndex + 1; collar.Parent = holder
	corner(collar, 20)
	return holder
end

local function setShirtSilhouetteImage(holder: Frame, imageId: string)
	for _, child in holder:GetChildren() do
		if child:IsA("ImageLabel") then child.Image = imageId end
	end
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
	panel.Size = UDim2.new(0.84, 0, 0.78, 0)
	panel.BackgroundColor3 = Color3.fromRGB(7, 27, 50)
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 2
	panel.Parent = gui
	local panelCorner = corner(panel, 18)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(320, 360)
	sizeConstraint.MaxSize = Vector2.new(1500, 820)
	sizeConstraint.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(235, 252, 255)
	stroke.Thickness = 3
	stroke.Transparency = 0
	stroke.Parent = panel
	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 62, 98)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 24, 46)),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = panel

	local ribbonShadow = Instance.new("Frame")
	ribbonShadow.Name = "RibbonShadow"
	ribbonShadow.AnchorPoint = Vector2.new(0.5, 0)
	ribbonShadow.Position = UDim2.new(0.5, 0, 0, -18)
	ribbonShadow.Size = UDim2.new(0.58, 0, 0, 82)
	ribbonShadow.BackgroundColor3 = Color3.fromRGB(10, 63, 145)
	ribbonShadow.BorderSizePixel = 0
	ribbonShadow.ZIndex = 4
	ribbonShadow.Parent = panel
	corner(ribbonShadow, 12)

	local ribbon = Instance.new("Frame")
	ribbon.Name = "PremiumRibbon"
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.new(0.5, 0, 0, -24)
	ribbon.Size = UDim2.new(0.54, 0, 0, 72)
	ribbon.BackgroundColor3 = Color3.fromRGB(244, 252, 255)
	ribbon.BorderSizePixel = 0
	ribbon.ZIndex = 5
	ribbon.Parent = panel
	corner(ribbon, 10)
	local ribbonStroke = Instance.new("UIStroke")
	ribbonStroke.Color = Color3.fromRGB(22, 105, 238)
	ribbonStroke.Thickness = 3
	ribbonStroke.Parent = ribbon
	local ribbonGradient = Instance.new("UIGradient")
	ribbonGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 239, 255))
	ribbonGradient.Rotation = 90
	ribbonGradient.Parent = ribbon
	local shopTitle = Instance.new("TextLabel")
	shopTitle.Size = UDim2.fromScale(1, 1)
	shopTitle.BackgroundTransparency = 1
	shopTitle.Font = Enum.Font.GothamBlack
	shopTitle.Text = "BUBBLE SHOP!"
	shopTitle.TextColor3 = Color3.fromRGB(20, 87, 218)
	shopTitle.TextStrokeTransparency = 1
	shopTitle.TextScaled = true
	shopTitle.ZIndex = 6
	shopTitle.Parent = ribbon
	local titlePadding = Instance.new("UIPadding")
	titlePadding.PaddingTop = UDim.new(0, 10)
	titlePadding.PaddingBottom = UDim.new(0, 10)
	titlePadding.PaddingLeft = UDim.new(0, 18)
	titlePadding.PaddingRight = UDim.new(0, 18)
	titlePadding.Parent = shopTitle

	-- Header : onglets, solde et fermeture
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -64, 0, 64)
	header.Position = UDim2.new(0, 32, 0, 62)
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
	categoryTitle.Visible = false

	local categoryTabs = Instance.new("ScrollingFrame")
	categoryTabs.Name = "CategoryTabs"
	categoryTabs.Size = UDim2.new(0.68, 0, 1, 0)
	categoryTabs.Position = UDim2.new(0.02, 0, 0, 0)
	categoryTabs.BackgroundTransparency = 1
	categoryTabs.BorderSizePixel = 0
	categoryTabs.ScrollBarThickness = 0
	categoryTabs.ScrollingDirection = Enum.ScrollingDirection.X
	categoryTabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	categoryTabs.CanvasSize = UDim2.new()
	categoryTabs.ZIndex = 3
	categoryTabs.Parent = header
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 12)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = categoryTabs

	local categoryTabButtons: { [CategoryId]: TextButton } = {}
	for i, catId in ipairs(CATEGORY_IDS) do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. catId
		tab.Size = UDim2.fromOffset(118, 52)
		tab.BackgroundColor3 = Color3.fromRGB(117, 205, 47)
		tab.TextColor3 = Color3.fromRGB(9, 48, 91)
		tab.TextStrokeTransparency = 1
		tab.Font = Enum.Font.GothamBlack
		tab.TextSize = 18
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = true
		tab.Selectable = true
		tab.LayoutOrder = i
		tab.ZIndex = 4
		tab.Parent = categoryTabs
		corner(tab, 18)
		local tabStroke = Instance.new("UIStroke")
		tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tabStroke.Color = Color3.fromRGB(255, 255, 255)
		tabStroke.Thickness = 3
		tabStroke.Parent = tab
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
	positionLabel.Visible = false
	L10nUtil.dynamic(positionLabel, "")

	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "Coins"
	coinsLabel.Size = UDim2.new(0.18, -44, 1, 0)
	coinsLabel.Position = UDim2.new(0.82, 0, 0, 0)
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Font = Enum.Font.GothamBold
	coinsLabel.TextSize = 16
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Right
	coinsLabel.TextColor3 = Color3.fromRGB(255, 244, 105)
	coinsLabel.TextStrokeTransparency = 1
	coinsLabel.Text = ""
	coinsLabel.ZIndex = 3
	coinsLabel.Parent = header
	L10nUtil.dynamic(coinsLabel, "")

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(40, 40)
	closeBtn.Position = UDim2.new(1, -40, 0, -4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 77, 79)
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 18
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = true
	closeBtn.Selectable = true
	closeBtn.ZIndex = 4
	closeBtn.Parent = panel
	L10nUtil.dynamic(closeBtn, L10n.Close)
	local closeCorner = corner(closeBtn, 10)

	-- Corps : flèche gauche | viewport + texte | flèche droite
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -56, 1, -164)
	body.Position = UDim2.new(0, 28, 0, 138)
	body.BackgroundColor3 = Color3.fromRGB(12, 62, 96)
	body.BackgroundTransparency = 0.04
	body.ZIndex = 3
	body.Parent = panel
	corner(body, 16)
	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Color = Color3.fromRGB(225, 249, 255)
	bodyStroke.Thickness = 3
	bodyStroke.Parent = body

	local itemGrid = Instance.new("ScrollingFrame")
	itemGrid.Name = "ItemGrid"
	itemGrid.Size = UDim2.new(1, -24, 1, -24)
	itemGrid.Position = UDim2.fromOffset(12, 12)
	itemGrid.BackgroundColor3 = Color3.fromRGB(83, 69, 137)
	itemGrid.BackgroundTransparency = 1
	itemGrid.BorderSizePixel = 0
	itemGrid.ScrollBarThickness = 8
	itemGrid.ScrollBarImageColor3 = Color3.fromRGB(235, 252, 255)
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
	itemGridLayout.CellSize = UDim2.new(0.25, -12, 0, 280)
	itemGridLayout.CellPadding = UDim2.fromOffset(16, 16)
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
	content.Visible = false
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
	local shirtPreview = createShirtSilhouette(content, UDim2.fromOffset(VIEWPORT_SIZE - 20, VIEWPORT_SIZE - 20), UDim2.new(0.5, -(VIEWPORT_SIZE - 20) / 2, 0, 28), 7)
	shirtPreview.Name = "ShirtTexturePreview"
	shirtPreview.Size = UDim2.fromOffset(VIEWPORT_SIZE - 22, VIEWPORT_SIZE - 22)
	shirtPreview.Position = UDim2.new(0.5, -(VIEWPORT_SIZE - 22) / 2, 0, 29)
	shirtPreview.BackgroundTransparency = 1
	shirtPreview.ZIndex = 7
	shirtPreview.Visible = false

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
		shirtPreview.Visible = false
		setShirtSilhouetteImage(shirtPreview, "")
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
	actionBtn.Visible = false
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
		currentLayout = ShopBrowseLayout.Resolve(mode, container)

		-- PC et console partagent la navigation verticale plus lisible.
		-- Seuls les trÃ¨s petits Ã©crans mobiles utilisent la barre horizontale.
		local compact = container.X < 760 or container.Y < 450
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Size = if compact then UDim2.new(0.94, 0, 0.86, 0) else UDim2.new(0.84, 0, 0.78, 0)
		panel.Position = UDim2.new(0.5, 0, 0.52, 0)
		sizeConstraint.MinSize = Vector2.new(320, 360)
		sizeConstraint.MaxSize = Vector2.new(1500, 820)
		panelCorner.CornerRadius = UDim.new(0, 18)

		ribbon.Size = if compact then UDim2.new(0.62, 0, 0, 58) else UDim2.new(0.46, 0, 0, 68)
		ribbon.Position = UDim2.new(0.5, 0, 0, if compact then -12 else -24)
		ribbonShadow.Size = if compact then UDim2.new(0.66, 0, 0, 66) else UDim2.new(0.58, 0, 0, 82)
		ribbonShadow.Position = UDim2.new(0.5, 0, 0, if compact then -7 else -18)

		header.Size = if compact then UDim2.new(1, -48, 0, 54) else UDim2.new(1, -48, 1, -86)
		header.Position = UDim2.new(0, 24, 0, if compact then 72 else 78)
		tabsLayout.FillDirection = if compact then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		tabsLayout.Padding = UDim.new(0, 8)
		categoryTabs.ScrollingDirection = if compact then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y
		categoryTabs.AutomaticCanvasSize = if compact then Enum.AutomaticSize.X else Enum.AutomaticSize.Y
		categoryTabs.Size = if compact then UDim2.new(1, -270, 0, 52) else UDim2.new(0, 124, 1, -8)
		categoryTabs.Position = UDim2.new(0, 0, 0, 0)
		for _, tab in pairs(categoryTabButtons) do
			tab.Size = if compact then UDim2.fromOffset(90, 52) else UDim2.new(1, -8, 0, 52)
			tab.TextSize = if compact then 13 else 15
		end
		coinsLabel.Size = UDim2.new(0, 180, 0, 54)
		coinsLabel.Position = UDim2.new(1, -246, 0, if compact then 0 else -10)
		coinsLabel.TextSize = if compact then 14 else 18
		closeBtn.Size = UDim2.fromOffset(if compact then 44 else 54, if compact then 44 else 54)
		closeBtn.Position = UDim2.new(1, -(if compact then 56 else 68), 0, 14)
		closeBtn.TextSize = if compact then 22 else 28
		closeCorner.CornerRadius = UDim.new(0, 10)

		body.Size = if compact then UDim2.new(1, -40, 1, -154) else UDim2.new(1, -180, 1, -118)
		body.Position = if compact then UDim2.new(0, 20, 0, 136) else UDim2.new(0, 150, 0, 96)
		itemGrid.Size = UDim2.new(1, -24, 1, -24)
		itemGrid.Position = UDim2.fromOffset(12, 12)
		-- Height alone must not collapse the catalogue into long horizontal rows.
		-- Desktop/console keep two product cards per row and simply scroll down.
		if container.X >= 1100 then
			itemGridLayout.CellSize = UDim2.new(0.25, -12, 0, 285)
		elseif container.X >= 760 then
			itemGridLayout.CellSize = UDim2.new(0.5, -10, 0, 285)
		else
			itemGridLayout.CellSize = UDim2.new(1, -8, 0, 250)
		end
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
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
				local yawOffset = model:GetAttribute("ShopPreviewYaw")
				model:PivotTo(CFrame.Angles(0, previewSpin + (if type(yawOffset) == "number" then yawOffset else 0), 0))
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
		local shirtImage = if category == "Shirts" then getImportedShirtImage(if item then item.ModelName else nil) else nil
		if shirtImage then
			setShirtSilhouetteImage(shirtPreview, shirtImage)
			shirtPreview.Visible = true
			viewport.Visible = false
			return
		end
		viewport.Visible = true

		local model, bounds = buildImportedCosmeticPreview(if item then item.ModelName else nil, category)
		if not model or not bounds then
			model, bounds = ShopViewportModels.Build(wantedId, if item then item.Type else nil, category)
		end
		vpCamera.CFrame = getPreviewCameraCFrame(model, bounds, VIEWPORT_FOV)
		local yawOffset = model:GetAttribute("ShopPreviewYaw")
		model:PivotTo(CFrame.Angles(0, previewSpin + (if type(yawOffset) == "number" then yawOffset else 0), 0))
		model.Parent = viewport
		previewModel = model

		local backdrop = ShopViewportModels.BuildBackdrop(category, bounds, VIEWPORT_FOV)
		backdrop.Parent = viewport
		previewBackdrop = backdrop
	end

	local invokeItemAction: ((number) -> ())? = nil

	local function getItemTier(row: ShopRow): (string, Color3, Color3)
		if browse.category == "Shirts" then
			if row.Rarity == "Epic" then return "EPIC", Color3.fromRGB(224, 126, 255), Color3.fromRGB(74, 23, 105) end
			if row.Rarity == "Rare" then return "RARE", Color3.fromRGB(83, 211, 255), Color3.fromRGB(12, 72, 111) end
			return "COMMON", Color3.fromRGB(111, 235, 132), Color3.fromRGB(22, 76, 45)
		end
		local cost = if type(row.Cost) == "number" then row.Cost else 0
		if cost >= 20000 then
			return "PRESTIGE", Color3.fromRGB(255, 196, 46), Color3.fromRGB(82, 48, 8)
		elseif cost >= 5000 then
			return "INTERMEDIATE", Color3.fromRGB(74, 215, 255), Color3.fromRGB(13, 65, 91)
		end
		return "BASIC", Color3.fromRGB(111, 235, 132), Color3.fromRGB(22, 76, 45)
	end

	local function refreshPresentation()
		local count = #browse.items
		local item: ShopRow? = if count > 0 then browse.items[browse.index] else nil

		local categoryKey = if browse.category then CATEGORY_LABEL_KEY[browse.category] else nil
		L10nUtil.localize(categoryTitle, localized(categoryKey))
		for catId, tab in pairs(categoryTabButtons) do
			local active = catId == browse.category
			local activeColors = {
				Skills = Color3.fromRGB(91, 218, 51),
				Items = Color3.fromRGB(255, 139, 39),
				Hats = Color3.fromRGB(171, 72, 235),
				Vests = Color3.fromRGB(63, 185, 242),
				Shirts = Color3.fromRGB(255, 105, 170),
				Accessories = Color3.fromRGB(255, 195, 52),
				Shoes = Color3.fromRGB(82, 220, 177),
			}
			tab.BackgroundColor3 = if active then activeColors[catId] else activeColors[catId]:Lerp(Color3.fromRGB(25, 103, 170), 0.45)
			tab.TextColor3 = Color3.fromRGB(9, 48, 91)
		end
		L10nUtil.dynamic(positionLabel, if count > 0 then string.format("%d / %d", browse.index, count) else "")
		L10nUtil.dynamic(coinsLabel, comma(browse.coins) .. " " .. L10n.CoinsUnit)

		updatePresentation(item)

		for _, child in ipairs(itemGrid:GetChildren()) do
			if child.Name:sub(1, 9) == "ItemCard_" then
				child:Destroy()
			end
		end
		local firstSelectable: GuiButton? = nil
		for itemIndex, row in ipairs(browse.items) do
			local tierName, tierColor, tierBackground = getItemTier(row)
			local card = Instance.new("Frame")
			card.Name = "ItemCard_" .. row.Id
			card.LayoutOrder = itemIndex
			card.BackgroundColor3 = Color3.fromRGB(55, 151, 205)
			card.BorderSizePixel = 0
			card.ZIndex = 4
			card.Parent = itemGrid
			corner(card, 14)
			local cardStroke = Instance.new("UIStroke")
			cardStroke.Color = Color3.fromRGB(8, 67, 135)
			cardStroke.Thickness = 3
			cardStroke.Parent = card

			local tierBadge = Instance.new("TextLabel")
			tierBadge.Name = "Tier"
			tierBadge.Size = UDim2.fromOffset(126, 26)
			tierBadge.Position = UDim2.fromOffset(12, 10)
			tierBadge.BackgroundColor3 = tierBackground
			tierBadge.BorderSizePixel = 0
			tierBadge.Font = Enum.Font.GothamBlack
			tierBadge.TextSize = 12
			tierBadge.TextColor3 = tierColor
			tierBadge.TextStrokeTransparency = 1
			tierBadge.Text = tierName
			tierBadge.ZIndex = 8
			tierBadge.Parent = card
			corner(tierBadge, 13)
			local tierStroke = Instance.new("UIStroke")
			tierStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			tierStroke.Color = tierColor
			tierStroke.Thickness = 1.5
			tierStroke.Transparency = 0.15
			tierStroke.Parent = tierBadge

			local iconBack = Instance.new("Frame")
			iconBack.Size = UDim2.new(1, -24, 0, 150)
			iconBack.Position = UDim2.fromOffset(12, 42)
			iconBack.BackgroundColor3 = Color3.fromRGB(29, 161, 224)
			iconBack.BorderSizePixel = 0
			iconBack.ZIndex = 5
			iconBack.Parent = card
			corner(iconBack, 12)

			local cardViewport = Instance.new("ViewportFrame")
			cardViewport.Size = UDim2.new(1, -8, 1, -8)
			cardViewport.Position = UDim2.fromOffset(4, 4)
			cardViewport.BackgroundColor3 = Color3.fromRGB(55, 190, 237)
			cardViewport.BorderSizePixel = 0
			cardViewport.ZIndex = 6
			cardViewport.Parent = iconBack
			corner(cardViewport, 10)
			local cardCamera = Instance.new("Camera")
			cardCamera.FieldOfView = VIEWPORT_FOV
			cardCamera.Parent = cardViewport
			cardViewport.CurrentCamera = cardCamera
			local cardLighting = ShopViewportModels.GetLighting(browse.category)
			cardViewport.Ambient = cardLighting.Ambient
			cardViewport.LightColor = cardLighting.LightColor
			cardViewport.LightDirection = cardLighting.LightDirection
			local shirtImage = if browse.category == "Shirts" then getImportedShirtImage(row.ModelName) else nil
			if shirtImage then
				local silhouette = createShirtSilhouette(cardViewport, UDim2.new(1, -28, 1, -12), UDim2.fromOffset(14, 6), 7)
				setShirtSilhouetteImage(silhouette, shirtImage)
			else
				local cardModel, cardBounds = buildImportedCosmeticPreview(row.ModelName, browse.category)
				if not cardModel or not cardBounds then
					cardModel, cardBounds = ShopViewportModels.Build(row.Id, row.Type, browse.category)
				end
				cardCamera.CFrame = getPreviewCameraCFrame(cardModel, cardBounds, VIEWPORT_FOV)
				local cardYawOffset = cardModel:GetAttribute("ShopPreviewYaw")
				cardModel:PivotTo(CFrame.Angles(0, if type(cardYawOffset) == "number" then cardYawOffset else 0, 0))
				cardModel.Parent = cardViewport
			end

			local cardName = Instance.new("TextLabel")
			cardName.Size = UDim2.new(1, -24, 0, 26)
			cardName.Position = UDim2.fromOffset(12, 198)
			cardName.BackgroundTransparency = 1
			cardName.Font = Enum.Font.GothamBlack
			cardName.TextSize = 19
			cardName.TextXAlignment = Enum.TextXAlignment.Center
			cardName.TextTruncate = Enum.TextTruncate.AtEnd
			cardName.TextColor3 = Color3.fromRGB(246, 251, 255)
			cardName.TextStrokeTransparency = 1
			cardName.Text = row.Label
			cardName.ZIndex = 5
			cardName.Parent = card

			local cardDescription = Instance.new("TextLabel")
			cardDescription.Size = UDim2.new(1, -28, 0, 28)
			cardDescription.Position = UDim2.fromOffset(14, 201)
			cardDescription.BackgroundTransparency = 1
			cardDescription.Font = Enum.Font.Gotham
			cardDescription.TextSize = 11
			cardDescription.TextWrapped = true
			cardDescription.TextXAlignment = Enum.TextXAlignment.Center
			cardDescription.TextYAlignment = Enum.TextYAlignment.Top
			cardDescription.TextColor3 = Color3.fromRGB(20, 75, 112)
			cardDescription.TextStrokeTransparency = 1
			cardDescription.Text = row.Description or ""
			cardDescription.ZIndex = 5
			cardDescription.Parent = card
			cardDescription.Visible = false

			local buttonState = row.ButtonState
			local canInvoke = ShopBrowseLogic.CanInvokeAction(row)
			local buyButton = Instance.new("TextButton")
			buyButton.Name = "Buy_" .. row.Id
			buyButton.Size = UDim2.new(1, -24, 0, 42)
			buyButton.Position = UDim2.new(0, 12, 1, -52)
			buyButton.BackgroundColor3 = if canInvoke then Color3.fromRGB(73, 239, 54) else Color3.fromRGB(79, 132, 167)
			buyButton.BorderSizePixel = 0
			buyButton.Font = Enum.Font.GothamBlack
			buyButton.TextSize = 16
			buyButton.TextColor3 = if canInvoke then Color3.fromRGB(12, 66, 18) else Color3.fromRGB(218, 239, 247)
			buyButton.TextStrokeTransparency = 1
			buyButton.AutoButtonColor = canInvoke
			buyButton.Active = canInvoke
			buyButton.Selectable = canInvoke
			buyButton.ZIndex = 6
			buyButton.Parent = card
			corner(buyButton, 9)
			local buyStroke = Instance.new("UIStroke")
			buyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			buyStroke.Color = if canInvoke then Color3.fromRGB(25, 125, 27) else Color3.fromRGB(43, 91, 128)
			buyStroke.Thickness = 2
			buyStroke.Parent = buyButton
			if canInvoke and type(row.Cost) == "number" then
				local levelText = if row.Type == "Upgrade" and type(row.Level) == "number" and type(row.Max) == "number"
					then string.format("  •  Lv %d/%d", row.Level, row.Max)
					else ""
				buyButton.Text = comma(row.Cost) .. " " .. L10n.CoinsUnit .. levelText
			else
				local labelKey = BUTTON_LABEL_KEY[buttonState] or "Locked"
				L10nUtil.localize(buyButton, localized(labelKey))
			end
			buyButton.Activated:Connect(function()
				if invokeItemAction then
					invokeItemAction(itemIndex)
				end
			end)
			selectionStroke(buyButton)
			if not firstSelectable and canInvoke then
				firstSelectable = buyButton
			end
		end
		if currentLayout.Mode == ShopBrowseLayout.Modes.Console and firstSelectable then
			GuiService.SelectedObject = firstSelectable
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

	local function invokeAction(itemIndex: number?)
		if not browse.active then
			return
		end
		if itemIndex then
			browse.index = itemIndex
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
	invokeItemAction = invokeAction

	--------------------------------------------------------------------
	-- Connexions permanentes (ProximityPrompt, entrées, personnage)
	--------------------------------------------------------------------

	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= player then
			return
		end
		local rawCategory = prompt:GetAttribute("BPW_ShopCategory")
		local category = if rawCategory == "Cosmetics" then "Hats" else rawCategory
		if not table.find(CATEGORY_IDS, category) then
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
