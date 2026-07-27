--!strict
-- Boutique : onglets Compétences / Items. Ouverte depuis le kiosque ItemShop.
-- UI responsive (viewport) — aucune logique économique modifiée.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)
local ShopIcons = require(Shared.ShopIcons)

local player = Players.LocalPlayer
local ShopUI = {}

local BG = Color3.fromRGB(18, 20, 28)
local ROW = Color3.fromRGB(30, 34, 44)
local ROW_MAX = Color3.fromRGB(42, 46, 58)
local TAB_ON = Color3.fromRGB(120, 200, 255)
local TAB_OFF = Color3.fromRGB(50, 56, 70)
local CLOSE_BG = Color3.fromRGB(36, 44, 62)
local CLOSE_BG_HOVER = Color3.fromRGB(70, 160, 220)
local CLOSE_BG_PRESS = Color3.fromRGB(90, 190, 255)

local HEADER_H = 96
local MAX_PANEL_W = 560
local MAX_PANEL_H = 560
local COMPACT_BREAKPOINT = 480
local SHOP_DISPLAY_ORDER = 100

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
end

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function textConstraint(label: TextLabel | TextButton, minSize: number, maxSize: number)
	label.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize
	c.MaxTextSize = maxSize
	c.Parent = label
end

function ShopUI.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_Shop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = SHOP_DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Position = UDim2.fromScale(0, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(4, 8, 16)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.ZIndex = 1
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 2
	panel.ClipsDescendants = true
	panel.Parent = gui
	corner(panel, 16)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(260, 280)
	sizeConstraint.MaxSize = Vector2.new(MAX_PANEL_W, MAX_PANEL_H)
	sizeConstraint.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.Position = UDim2.fromScale(0, 0)
	header.BackgroundTransparency = 1
	header.ZIndex = 10
	header.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -64, 0, 40)
	title.Position = UDim2.new(0, 12, 0, 4)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 11
	title.Parent = header
	L10nUtil.localize(title, L10n.BubbleShop)
	textConstraint(title, 14, 22)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Position = UDim2.new(1, -52, 0, 6)
	closeBtn.BackgroundColor3 = CLOSE_BG
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 20
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.Selectable = true
	closeBtn.ZIndex = 30
	closeBtn.Parent = header
	L10nUtil.dynamic(closeBtn, L10n.Close)
	corner(closeBtn, 10)

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(120, 200, 255)
	closeStroke.Thickness = 1.5
	closeStroke.Parent = closeBtn

	local tabSkills = Instance.new("TextButton")
	tabSkills.Name = "TabSkills"
	tabSkills.Size = UDim2.new(0.5, -14, 0, 40)
	tabSkills.Position = UDim2.new(0, 12, 0, 48)
	tabSkills.BackgroundColor3 = TAB_ON
	tabSkills.TextColor3 = Color3.fromRGB(10, 12, 18)
	tabSkills.Font = Enum.Font.GothamBold
	tabSkills.TextSize = 14
	tabSkills.BorderSizePixel = 0
	tabSkills.ZIndex = 11
	tabSkills.Parent = header
	L10nUtil.localize(tabSkills, L10n.Skills)
	corner(tabSkills, 8)
	textConstraint(tabSkills, 12, 15)

	local tabItems = Instance.new("TextButton")
	tabItems.Name = "TabItems"
	tabItems.Size = UDim2.new(0.5, -14, 0, 40)
	tabItems.Position = UDim2.new(0.5, 2, 0, 48)
	tabItems.BackgroundColor3 = TAB_OFF
	tabItems.TextColor3 = Color3.new(1, 1, 1)
	tabItems.Font = Enum.Font.GothamBold
	tabItems.TextSize = 14
	tabItems.BorderSizePixel = 0
	tabItems.ZIndex = 11
	tabItems.Parent = header
	L10nUtil.localize(tabItems, L10n.Items)
	corner(tabItems, 8)
	textConstraint(tabItems, 12, 15)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, -24, 1, -(HEADER_H + 12))
	scroll.Position = UDim2.new(0, 12, 0, HEADER_H)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 200, 255)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ElasticBehavior = Enum.ElasticBehavior.Always
	scroll.ZIndex = 5
	scroll.Parent = panel

	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.PaddingBottom = UDim.new(0, 12)
	listPad.PaddingRight = UDim.new(0, 4)
	listPad.Parent = scroll

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local activeTab = "skills"
	local firstButton: TextButton? = nil
	local isOpen = false
	local compactLayout = false
	local render: () -> ()

	local function getViewport(): Vector2
		local cam = Workspace.CurrentCamera
		if cam then
			return cam.ViewportSize
		end
		return Vector2.new(1280, 720)
	end

	local function applyPanelLayout()
		local vp = getViewport()
		local inset = GuiService:GetGuiInset()
		-- Zone utile (IgnoreGuiInset = false) : hors barre Roblox / encoche
		local usableW = vp.X
		local usableH = math.max(1, vp.Y - inset.Y)
		local targetW = math.min(MAX_PANEL_W, math.floor(usableW * 0.92))
		local targetH = math.min(MAX_PANEL_H, math.floor(usableH * 0.84))
		targetW = math.max(260, targetW)
		targetH = math.max(280, math.min(targetH, usableH - 16))

		panel.Size = UDim2.fromOffset(targetW, targetH)
		panel.Position = UDim2.new(0.5, -math.floor(targetW / 2), 0.5, -math.floor(targetH / 2))

		local wasCompact = compactLayout
		compactLayout = targetW < COMPACT_BREAKPOINT
		if isOpen and wasCompact ~= compactLayout then
			render()
		end
	end

	local function styleTab(btn: TextButton, on: boolean)
		btn.BackgroundColor3 = if on then TAB_ON else TAB_OFF
		btn.TextColor3 = if on then Color3.fromRGB(10, 12, 18) else Color3.new(1, 1, 1)
	end

	local function clearRows()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		firstButton = nil
	end

	local function styleActionButton(btn: TextButton)
		btn.TextWrapped = true
		btn.TextTruncate = Enum.TextTruncate.None
		textConstraint(btn, 11, 14)
	end

	local function layoutItemDesktop(row: Frame, icon: Frame, name: TextLabel, detail: TextLabel, action: TextButton)
		row.Size = UDim2.new(1, -8, 0, 72)
		icon.Size = UDim2.fromOffset(48, 48)
		icon.Position = UDim2.new(0, 10, 0.5, -24)
		icon.Visible = true
		name.Size = UDim2.new(0.42, 0, 0, 28)
		name.Position = UDim2.new(0, 68, 0, 8)
		detail.Size = UDim2.new(0.42, 0, 0, 22)
		detail.Position = UDim2.new(0, 68, 0, 38)
		action.Size = UDim2.new(0, 130, 0, 38)
		action.Position = UDim2.new(1, -140, 0.5, -19)
	end

	local function layoutSkillDesktop(row: Frame, name: TextLabel, level: TextLabel, action: TextButton)
		row.Size = UDim2.new(1, -8, 0, 54)
		name.Size = UDim2.new(0.42, 0, 1, 0)
		name.Position = UDim2.new(0, 12, 0, 0)
		level.Size = UDim2.new(0.28, 0, 1, 0)
		level.Position = UDim2.new(0.42, 0, 0, 0)
		action.Size = UDim2.new(0, 130, 0, 38)
		action.Position = UDim2.new(1, -140, 0.5, -19)
	end

	local function layoutRowCompact(row: Frame, name: TextLabel, detail: TextLabel?, action: TextButton)
		row.Size = UDim2.new(1, -8, 0, if detail then 118 else 96)
		name.Size = UDim2.new(1, -24, 0, 26)
		name.Position = UDim2.new(0, 12, 0, 8)
		if detail then
			detail.Size = UDim2.new(1, -24, 0, 22)
			detail.Position = UDim2.new(0, 12, 0, 34)
			action.Position = UDim2.new(0, 12, 0, 64)
		else
			action.Position = UDim2.new(0, 12, 0, 42)
		end
		action.Size = UDim2.new(1, -24, 0, 40)
	end

	local function layoutItemCompact(row: Frame, icon: Frame, name: TextLabel, detail: TextLabel, action: TextButton)
		row.Size = UDim2.new(1, -8, 0, 132)
		icon.Size = UDim2.fromOffset(44, 44)
		icon.Position = UDim2.new(0, 10, 0, 10)
		icon.Visible = true
		name.Size = UDim2.new(1, -68, 0, 24)
		name.Position = UDim2.new(0, 62, 0, 10)
		detail.Size = UDim2.new(1, -68, 0, 20)
		detail.Position = UDim2.new(0, 62, 0, 34)
		action.Size = UDim2.new(1, -24, 0, 40)
		action.Position = UDim2.new(0, 12, 0, 80)
	end

	local function applyItemLayout(row: Frame, icon: Frame, name: TextLabel, detail: TextLabel, action: TextButton)
		if compactLayout then
			layoutItemCompact(row, icon, name, detail, action)
		else
			layoutItemDesktop(row, icon, name, detail, action)
		end
		styleActionButton(action)
	end

	local function applySkillLayout(row: Frame, name: TextLabel, level: TextLabel, action: TextButton)
		if compactLayout then
			layoutRowCompact(row, name, level, action)
		else
			layoutSkillDesktop(row, name, level, action)
		end
		styleActionButton(action)
	end

	local function renderSkills(upgrades: { any })
		for _, item in ipairs(upgrades) do
			local isMax = item.Cost < 0 or item.Level >= item.Max

			local row = Instance.new("Frame")
			row.BackgroundColor3 = if isMax then ROW_MAX else ROW
			row.BorderSizePixel = 0
			row.ZIndex = 6
			row.Parent = scroll
			corner(row, 10)

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.TextColor3 = if isMax then Color3.fromRGB(170, 178, 196) else Color3.new(1, 1, 1)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.ZIndex = 7
			name.Parent = row
			L10nUtil.localize(name, item.Label)
			textConstraint(name, 12, 15)

			local level = Instance.new("TextLabel")
			level.BackgroundTransparency = 1
			level.TextColor3 = if isMax then Color3.fromRGB(170, 178, 196) else Color3.fromRGB(180, 190, 210)
			level.Font = Enum.Font.GothamMedium
			level.TextSize = 14
			level.TextXAlignment = Enum.TextXAlignment.Left
			level.ZIndex = 7
			level.Parent = row
			L10nUtil.dynamic(level, ("Lv. %d/%d"):format(item.Level, item.Max))
			textConstraint(level, 11, 14)

			local buy = Instance.new("TextButton")
			buy.BackgroundColor3 = if isMax then Color3.fromRGB(60, 66, 80) else Color3.fromRGB(120, 200, 255)
			buy.TextColor3 = if isMax then Color3.fromRGB(190, 198, 214) else Color3.fromRGB(10, 12, 18)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = 14
			buy.BorderSizePixel = 0
			buy.AutoButtonColor = not isMax
			buy.Active = not isMax
			buy.Selectable = not isMax
			buy.SelectionOrder = 1
			buy.ZIndex = 7
			buy.Parent = row
			if isMax then
				L10nUtil.localize(buy, L10n.Max)
			else
				L10nUtil.dynamic(buy, comma(item.Cost) .. " " .. L10n.CoinsUnit)
			end
			corner(buy, 8)

			applySkillLayout(row, name, level, buy)

			if not isMax and not firstButton then
				firstButton = buy
			end

			if not isMax then
				buy.Activated:Connect(function()
					local ok, msg = Remotes.Func("BuyUpgrade"):InvokeServer(item.Id)
					if not ok then
						L10nUtil.localize(buy, msg or L10n.Denied)
						task.wait(1)
					end
					render()
				end)
			end
		end
	end

	local function renderItems(items: { any }, equippedBackpack: string, defaultCapacity: number)
		-- Sac de base (toujours disponible)
		do
			local isEquipped = equippedBackpack == "" or equippedBackpack == nil
			local row = Instance.new("Frame")
			row.BackgroundColor3 = if isEquipped then ROW_MAX else ROW
			row.BorderSizePixel = 0
			row.ZIndex = 6
			row.Parent = scroll
			corner(row, 10)

			local icon = ShopIcons.CreateBadge(row, "Icon", "BackpackDefault", 7)

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.TextColor3 = Color3.new(1, 1, 1)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.ZIndex = 7
			name.Parent = row
			L10nUtil.localize(name, L10n.DefaultBackpack)
			textConstraint(name, 12, 15)

			local cap = Instance.new("TextLabel")
			cap.BackgroundTransparency = 1
			cap.TextColor3 = Color3.fromRGB(180, 190, 210)
			cap.Font = Enum.Font.GothamMedium
			cap.TextSize = 13
			cap.TextXAlignment = Enum.TextXAlignment.Left
			cap.ZIndex = 7
			cap.Parent = row
			L10nUtil.dynamic(cap, ("%s: %d"):format(L10n.CapacityLabel, defaultCapacity or 25))
			textConstraint(cap, 11, 13)

			local action = Instance.new("TextButton")
			action.BorderSizePixel = 0
			action.Font = Enum.Font.GothamBold
			action.TextSize = 14
			action.ZIndex = 7
			action.Parent = row
			corner(action, 8)

			if isEquipped then
				action.BackgroundColor3 = Color3.fromRGB(60, 66, 80)
				action.TextColor3 = Color3.fromRGB(190, 198, 214)
				action.Active = false
				action.AutoButtonColor = false
				L10nUtil.localize(action, L10n.Equipped)
			else
				action.BackgroundColor3 = Color3.fromRGB(120, 255, 170)
				action.TextColor3 = Color3.fromRGB(10, 12, 18)
				action.Active = true
				action.Selectable = true
				L10nUtil.localize(action, L10n.Equip)
				if not firstButton then
					firstButton = action
				end
				action.Activated:Connect(function()
					local ok, msg = Remotes.Func("EquipBackpack"):InvokeServer("")
					if not ok then
						L10nUtil.localize(action, msg or L10n.Denied)
						task.wait(1.2)
					end
					render()
				end)
			end

			applyItemLayout(row, icon, name, cap, action)
		end

		for _, item in ipairs(items) do
			local row = Instance.new("Frame")
			row.BackgroundColor3 = if item.Equipped then ROW_MAX else ROW
			row.BorderSizePixel = 0
			row.ZIndex = 6
			row.Parent = scroll
			corner(row, 10)

			local icon = ShopIcons.CreateBadge(row, "Icon", item.IconKey or item.Id, 7)

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.TextColor3 = Color3.new(1, 1, 1)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.ZIndex = 7
			name.Parent = row
			L10nUtil.localize(name, item.Label)
			textConstraint(name, 12, 15)

			local cap = Instance.new("TextLabel")
			cap.BackgroundTransparency = 1
			cap.TextColor3 = Color3.fromRGB(180, 190, 210)
			cap.Font = Enum.Font.GothamMedium
			cap.TextSize = 13
			cap.TextXAlignment = Enum.TextXAlignment.Left
			cap.ZIndex = 7
			cap.Parent = row
			L10nUtil.dynamic(cap, ("%s: %d"):format(L10n.CapacityLabel, item.Capacity or 50))
			textConstraint(cap, 11, 13)

			local action = Instance.new("TextButton")
			action.BorderSizePixel = 0
			action.Font = Enum.Font.GothamBold
			action.TextSize = 14
			action.ZIndex = 7
			action.Parent = row
			corner(action, 8)

			if item.Equipped then
				action.BackgroundColor3 = Color3.fromRGB(255, 170, 100)
				action.TextColor3 = Color3.fromRGB(10, 12, 18)
				action.Active = true
				action.Selectable = true
				L10nUtil.localize(action, L10n.Unequip)
				if not firstButton then
					firstButton = action
				end
				action.Activated:Connect(function()
					local ok, msg = Remotes.Func("EquipBackpack"):InvokeServer("")
					if not ok then
						L10nUtil.localize(action, msg or L10n.Denied)
						task.wait(1.2)
					end
					render()
				end)
			elseif item.Owned then
				action.BackgroundColor3 = Color3.fromRGB(120, 255, 170)
				action.TextColor3 = Color3.fromRGB(10, 12, 18)
				action.Active = true
				action.Selectable = true
				L10nUtil.localize(action, L10n.Equip)
				if not firstButton then
					firstButton = action
				end
				action.Activated:Connect(function()
					local ok, msg = Remotes.Func("EquipBackpack"):InvokeServer(item.Id)
					if not ok then
						L10nUtil.localize(action, msg or L10n.Denied)
						task.wait(1.2)
					end
					render()
				end)
			else
				action.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
				action.TextColor3 = Color3.fromRGB(10, 12, 18)
				action.Active = true
				action.Selectable = true
				L10nUtil.dynamic(action, comma(item.Cost) .. " " .. L10n.CoinsUnit)
				if not firstButton then
					firstButton = action
				end
				action.Activated:Connect(function()
					local ok, msg = Remotes.Func("BuyItem"):InvokeServer(item.Id)
					if not ok then
						L10nUtil.localize(action, msg or L10n.Denied)
						task.wait(1.2)
					end
					render()
				end)
			end

			applyItemLayout(row, icon, name, cap, action)
		end
	end

	render = function()
		local data = Remotes.Func("GetShopData"):InvokeServer()
		clearRows()
		styleTab(tabSkills, activeTab == "skills")
		styleTab(tabItems, activeTab == "items")

		if type(data) ~= "table" then
			return
		end

		-- Compat : ancien format = tableau d'upgrades
		if data[1] ~= nil or (data.Upgrades == nil and data.Items == nil) then
			renderSkills(data :: any)
			return
		end

		if activeTab == "skills" then
			renderSkills(data.Upgrades or {})
		else
			renderItems(data.Items or {}, data.EquippedBackpack or "", data.DefaultCapacity or 25)
		end

		if firstButton and GuiService.SelectedObject then
			GuiService.SelectedObject = firstButton
		end
	end

	local function closeShop()
		if not isOpen then
			return
		end
		isOpen = false
		panel.Visible = false
		backdrop.Visible = false
		GuiService.SelectedObject = nil
	end

	local function openShop()
		if isOpen then
			return
		end
		applyPanelLayout()
		isOpen = true
		backdrop.Visible = true
		panel.Visible = true
		render()
		if firstButton then
			GuiService.SelectedObject = firstButton
		end
	end

	function ShopUI.Open()
		openShop()
	end

	function ShopUI.Close()
		closeShop()
	end

	function ShopUI.Toggle()
		if isOpen then
			closeShop()
		else
			openShop()
		end
	end

	tabSkills.Activated:Connect(function()
		activeTab = "skills"
		render()
	end)

	tabItems.Activated:Connect(function()
		activeTab = "items"
		render()
	end)

	closeBtn.Activated:Connect(closeShop)
	backdrop.Activated:Connect(closeShop)

	closeBtn.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled then
			closeBtn.BackgroundColor3 = CLOSE_BG_HOVER
		end
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.BackgroundColor3 = CLOSE_BG
	end)
	closeBtn.MouseButton1Down:Connect(function()
		closeBtn.BackgroundColor3 = CLOSE_BG_PRESS
	end)
	closeBtn.MouseButton1Up:Connect(function()
		closeBtn.BackgroundColor3 = if UserInputService.MouseEnabled then CLOSE_BG_HOVER else CLOSE_BG
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= player then
			return
		end
		if prompt:GetAttribute("BPW_OpenShop") == true then
			openShop()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if not isOpen then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then
			closeShop()
		end
	end)

	local viewportConn: RBXScriptConnection? = nil

	local function bindViewport(cam: Camera?)
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		if cam then
			viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyPanelLayout)
			applyPanelLayout()
		end
	end

	bindViewport(Workspace.CurrentCamera)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindViewport(Workspace.CurrentCamera)
	end)
end

return ShopUI
