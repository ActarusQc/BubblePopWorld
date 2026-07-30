--!strict
-- Boutique walk-in : browse local par mur (Skills / Items / Cosmetics).
-- Caméra, freeze personnage, UI compacte et présentoir sont 100% locaux :
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
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	FieldOfView: number,
}

local CATEGORY_IDS: { CategoryId } = { "Skills", "Items", "Cosmetics" }

local ACCENT: { [string]: Color3 } = {
	Skills = Color3.fromRGB(80, 230, 255),
	Items = Color3.fromRGB(255, 185, 60),
	Cosmetics = Color3.fromRGB(28, 105, 255),
}

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

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 12)
	c.Parent = parent
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
	tempConns = {} :: { RBXScriptConnection },
	cameraTween = nil :: Tween?,
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
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -22)
	panel.Size = UDim2.new(0.9, 0, 0, 190)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 2
	panel.Parent = gui
	corner(panel, 18)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(300, 190)
	sizeConstraint.MaxSize = Vector2.new(640, 220)
	sizeConstraint.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 150, 210)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = panel

	-- Header : catégorie + position + solde coins + fermer
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -24, 0, 30)
	header.Position = UDim2.new(0, 12, 0, 10)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = panel

	local categoryTitle = Instance.new("TextLabel")
	categoryTitle.Name = "CategoryTitle"
	categoryTitle.Size = UDim2.new(0.5, 0, 1, 0)
	categoryTitle.BackgroundTransparency = 1
	categoryTitle.Font = Enum.Font.GothamBlack
	categoryTitle.TextSize = 20
	categoryTitle.TextXAlignment = Enum.TextXAlignment.Left
	categoryTitle.TextColor3 = WHITE
	categoryTitle.Text = ""
	categoryTitle.ZIndex = 3
	categoryTitle.Parent = header

	local positionLabel = Instance.new("TextLabel")
	positionLabel.Name = "Position"
	positionLabel.Size = UDim2.new(0.2, 0, 1, 0)
	positionLabel.Position = UDim2.new(0.5, 0, 0, 0)
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
	coinsLabel.Size = UDim2.new(0.3, -44, 1, 0)
	coinsLabel.Position = UDim2.new(0.7, 0, 0, 0)
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
	corner(closeBtn, 10)

	-- Corps : flèche gauche | viewport + texte | flèche droite
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -24, 1, -84)
	body.Position = UDim2.new(0, 12, 0, 46)
	body.BackgroundTransparency = 1
	body.ZIndex = 3
	body.Parent = panel

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
	corner(leftBtn, 14)

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
	corner(rightBtn, 14)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -144, 1, 0)
	content.Position = UDim2.new(0, 68, 0, 0)
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = body

	-- Présentoir local : ViewportFrame + part colorée (jamais Display_* serveur).
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Presentation"
	viewport.Size = UDim2.fromOffset(92, 92)
	viewport.Position = UDim2.new(0, 0, 0.5, -46)
	viewport.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
	viewport.BackgroundTransparency = 0.1
	viewport.BorderSizePixel = 0
	viewport.ZIndex = 3
	viewport.Parent = content
	corner(viewport, 12)

	local vpCamera = Instance.new("Camera")
	vpCamera.FieldOfView = 45
	vpCamera.Parent = viewport
	viewport.CurrentCamera = vpCamera
	vpCamera.CFrame = CFrame.new(Vector3.new(0, 0, 5.5), Vector3.new(0, 0, 0))

	local presentPart = Instance.new("Part")
	presentPart.Name = "PresentPart"
	presentPart.Anchored = true
	presentPart.CanCollide = false
	presentPart.CanQuery = false
	presentPart.CanTouch = false
	presentPart.CastShadow = false
	presentPart.Material = Enum.Material.Neon
	presentPart.Size = Vector3.new(2, 2, 2)
	presentPart.CFrame = CFrame.new(0, 0, 0)
	presentPart.Color = ACCENT.Skills
	presentPart.Parent = viewport

	local textArea = Instance.new("Frame")
	textArea.Name = "TextArea"
	textArea.Size = UDim2.new(1, -104, 1, 0)
	textArea.Position = UDim2.new(0, 104, 0, 0)
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
	actionBtn.Parent = panel
	corner(actionBtn, 10)
	L10nUtil.dynamic(actionBtn, "")

	--------------------------------------------------------------------
	-- Présentoir : rotation douce pendant le browse (connexion temporaire)
	--------------------------------------------------------------------

	local function startSpin()
		local conn = RunService.RenderStepped:Connect(function(dt)
			presentPart.CFrame = presentPart.CFrame * CFrame.Angles(0, dt * 0.8, 0)
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

	local function updatePresentation(item: ShopRow?)
		local accent = if browse.category then ACCENT[browse.category] else ACCENT.Skills
		presentPart.Color = accent
		if item and item.Type == "Backpack" then
			presentPart.Shape = Enum.PartType.Block
		elseif item and item.Type == "Cosmetic" then
			presentPart.Shape = Enum.PartType.Cylinder
		else
			presentPart.Shape = Enum.PartType.Ball
		end
	end

	local function refreshPresentation()
		local count = #browse.items
		local item: ShopRow? = if count > 0 then browse.items[browse.index] else nil

		local categoryKey = if browse.category then CATEGORY_LABEL_KEY[browse.category] else nil
		L10nUtil.localize(categoryTitle, localized(categoryKey))
		L10nUtil.dynamic(positionLabel, if count > 0 then string.format("%d / %d", browse.index, count) else "")
		L10nUtil.dynamic(coinsLabel, comma(browse.coins) .. " " .. L10n.CoinsUnit)

		updatePresentation(item)

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
		leftBtn.AutoButtonColor = canNavigate
		rightBtn.AutoButtonColor = canNavigate
		leftBtn.BackgroundColor3 = if canNavigate then ARROW_BG else ARROW_BG_DISABLED
		rightBtn.BackgroundColor3 = if canNavigate then ARROW_BG else ARROW_BG_DISABLED

		if UserInputService.GamepadEnabled and canInvoke then
			GuiService.SelectedObject = actionBtn
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

				if browse.controls then
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

			for _, conn in ipairs(browse.tempConns) do
				conn:Disconnect()
			end
		end)

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

		local cameraPoint = itemShop:FindFirstChild("CameraPoint_" .. category)
		local display = itemShop:FindFirstChild("Display_" .. category)
		if not (cameraPoint and cameraPoint:IsA("BasePart")) then
			error("CameraPoint_" .. category .. " introuvable")
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
		browse.saved = {
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
			UseJumpPower = humanoid.UseJumpPower,
			AutoRotate = humanoid.AutoRotate,
			CameraType = camera.CameraType,
			CameraSubject = camera.CameraSubject,
			FieldOfView = camera.FieldOfView,
		}
		browse.controls = tryGetControls()

		-- 2) Mémoriser Enabled original de CHAQUE prompt ItemShop avant de tout désactiver.
		table.clear(browse.promptEnabled)
		for _, descendant in ipairs(itemShop:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") then
				browse.promptEnabled[descendant] = descendant.Enabled
			end
		end

		-- 3) Freeze local (pas de téléport).
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
		if browse.controls then
			pcall(function()
				(browse.controls :: any):Disable()
			end)
		end

		-- 4) Désactiver localement tous les prompts ItemShop (jamais côté serveur).
		for prompt in pairs(browse.promptEnabled) do
			prompt.Enabled = false
		end

		-- 5) Tween caméra Scriptable vers CameraPoint_<Category>, LookAt Display_<Category>.
		camera.CameraType = Enum.CameraType.Scriptable
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
		local tween = TweenService:Create(
			camera,
			TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = targetCFrame }
		)
		browse.cameraTween = tween
		tween:Play()

		-- 6) Charger les données catégorie, index 1, UI compacte visible.
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
		startSpin()
		refreshPresentation()

		-- Personnage : sortir proprement sur mort / respawn pendant le browse.
		table.insert(
			browse.tempConns,
			humanoid.Died:Connect(function()
				exitBrowse()
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
	-- Navigation / action
	--------------------------------------------------------------------

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

		local previousText = actionBtn.Text
		actionBtn.Active = false
		local id = item.Id
		local ok, success, message = pcall(function()
			return Remotes.Func(remoteName):InvokeServer(id)
		end)

		if not browse.active then
			return
		end

		if ok and success == true then
			refreshFromServer(id)
			return
		end

		L10nUtil.dynamic(actionBtn, if type(message) == "string" then message else L10n.Denied)
		task.wait(1)
		if browse.active then
			refreshFromServer(id)
		else
			actionBtn.Text = previousText
		end
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
		elseif keyCode == Enum.KeyCode.Left or keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.DPadLeft then
			navigate(-1)
		elseif keyCode == Enum.KeyCode.Right or keyCode == Enum.KeyCode.E or keyCode == Enum.KeyCode.DPadRight then
			navigate(1)
		end
	end)

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
