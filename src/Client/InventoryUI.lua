--!strict
-- Inventaire HUD : équiper / retirer les sacs possédés.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)
local HudChrome = require(Shared.HudChrome)

local player = Players.LocalPlayer
local InventoryUI = {}

local BG = Color3.fromRGB(12, 16, 28)
local BG_BUTTON = Color3.fromRGB(14, 18, 30)
local ACCENT = Color3.fromRGB(90, 220, 255)
local ROW = Color3.fromRGB(30, 34, 44)
local ROW_ON = Color3.fromRGB(42, 46, 58)

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
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

local function resolveActionColumn(): (Instance?, Instance?)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil, nil
	end
	local hud = playerGui:FindFirstChild(HudChrome.SCREEN_NAME)
	if not hud then
		return nil, nil
	end
	local column = hud:FindFirstChild(HudChrome.ACTION_COLUMN_NAME)
	local slot = column and column:FindFirstChild("InventorySlot")
	return column, slot
end

function InventoryUI.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_Inventory"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	local openBtn = Instance.new("TextButton")
	openBtn.Name = HudChrome.INVENTORY_BUTTON_NAME
	openBtn.LayoutOrder = 1
	openBtn.Size = UDim2.fromOffset(HudChrome.ACTION_BUTTON_SIZE, HudChrome.ACTION_BUTTON_SIZE)
	openBtn.BackgroundColor3 = Color3.fromRGB(74, 145, 242)
	openBtn.BackgroundTransparency = 0.08
	openBtn.BorderSizePixel = 0
	openBtn.Text = "" -- pas de libellé permanent « Inventory »
	openBtn.AutoButtonColor = false
	openBtn.Selectable = true
	openBtn.Active = true
	openBtn.ZIndex = 5
	openBtn:SetAttribute("AccessibleName", L10n.Inventory)

	local column, slot = resolveActionColumn()
	if slot then
		openBtn.Size = UDim2.fromScale(1, 1)
		openBtn.Parent = slot
	elseif column then
		openBtn.Parent = column
	else
		-- Fallback si le HUD n'est pas encore monté.
		openBtn.AnchorPoint = Vector2.new(1, 0)
		openBtn.Position = UDim2.new(1, -HudChrome.ACTION_COLUMN_RIGHT, 0, HudChrome.ACTION_COLUMN_TOP)
		openBtn.Parent = gui
	end

	local openCorner = Instance.new("UICorner")
	openCorner.CornerRadius = UDim.new(0.5, 0)
	openCorner.Parent = openBtn
	local border = stroke(openBtn, Color3.new(1,1,1), 2.2, 0.06)

	local icon = Instance.new("TextLabel")
	icon.Name = "IconGlyph"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Font = Enum.Font.GothamBold
	icon.Text = HudChrome.ICON_INVENTORY
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.TextScaled = true
	icon.ZIndex = openBtn.ZIndex + 1
	icon.Parent = openBtn
	L10nUtil.markNoLocalize(icon)
	local iconConstraint = Instance.new("UITextSizeConstraint")
	iconConstraint.MinTextSize = 18
	iconConstraint.MaxTextSize = 32
	iconConstraint.Parent = icon
	icon.Size = UDim2.new(1,-14,1,-14); icon.Position = UDim2.fromOffset(7,7)
	local menuCaption = Instance.new("TextLabel")
	menuCaption.Name = "MenuCaption"; menuCaption.AnchorPoint = Vector2.new(0.5,0)
	menuCaption.Position = UDim2.new(0.5,0,1,2); menuCaption.Size = UDim2.fromOffset(92,16)
	menuCaption.BackgroundTransparency = 1; menuCaption.TextColor3 = Color3.new(1,1,1)
	menuCaption.TextStrokeColor3 = Color3.fromRGB(12,30,48); menuCaption.TextStrokeTransparency = 0.2
	menuCaption.Font = Enum.Font.GothamBlack; menuCaption.TextSize = 10; menuCaption.ZIndex = 8; menuCaption.Parent = openBtn
	L10nUtil.localize(menuCaption, L10n.Inventory)

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
	tip.Parent = openBtn
	L10nUtil.localize(tip, L10n.Inventory)
	corner(tip, 6)
	stroke(tip, ACCENT, 1, 0.35)
	local tipPad = Instance.new("UIPadding")
	tipPad.PaddingLeft = UDim.new(0, 8)
	tipPad.PaddingRight = UDim.new(0, 8)
	tipPad.Parent = tip

	local function setHover(on: boolean)
		border.Thickness = if on then 2.2 else 1.4
		border.Transparency = if on then 0 else 0.12
		tip.Visible = false
		openBtn.BackgroundTransparency = if on then 0 else 0.08
	end

	openBtn.MouseEnter:Connect(function()
		setHover(true)
	end)
	openBtn.MouseLeave:Connect(function()
		setHover(false)
	end)
	openBtn.SelectionGained:Connect(function()
		setHover(true)
	end)
	openBtn.SelectionLost:Connect(function()
		setHover(false)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "InventoryPanel"
	panel.Size = UDim2.new(0, 340, 0, 360)
	panel.Position = UDim2.new(1, -356, 0, 64)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)
	stroke(panel, ACCENT, 1.2, 0.25)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -52, 0, 40)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	L10nUtil.localize(title, L10n.Inventory)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 34, 0, 34)
	closeBtn.Position = UDim2.new(1, -42, 0, 4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(50, 56, 70)
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 15
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = panel
	L10nUtil.dynamic(closeBtn, L10n.Close)
	corner(closeBtn, 8)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -56)
	scroll.Position = UDim2.new(0, 12, 0, 46)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.Parent = scroll

	local render: () -> ()

	local function clearRows()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	local function addRow(labelText: string, detailText: string, equipped: boolean, equipId: string, kind: string, canAct: boolean, cosmeticSlot: string?)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 58)
		row.BackgroundColor3 = if equipped then ROW_ON else ROW
		row.BorderSizePixel = 0
		row.Parent = scroll
		corner(row, 10)

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.58, 0, 0, 26)
		name.Position = UDim2.new(0, 10, 0, 4)
		name.BackgroundTransparency = 1
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Font = Enum.Font.GothamMedium
		name.TextSize = 14
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = row
		L10nUtil.localize(name, labelText)

		local cap = Instance.new("TextLabel")
		cap.Size = UDim2.new(0.58, 0, 0, 20)
		cap.Position = UDim2.new(0, 10, 0, 30)
		cap.BackgroundTransparency = 1
		cap.TextColor3 = Color3.fromRGB(180, 190, 210)
		cap.Font = Enum.Font.GothamMedium
		cap.TextSize = 12
		cap.TextXAlignment = Enum.TextXAlignment.Left
		cap.Parent = row
		L10nUtil.localize(cap, detailText)

		local action = Instance.new("TextButton")
		action.Size = UDim2.new(0, 100, 0, 34)
		action.Position = UDim2.new(1, -112, 0.5, -17)
		action.BorderSizePixel = 0
		action.Font = Enum.Font.GothamBold
		action.TextSize = 13
		action.Parent = row
		corner(action, 8)

		if equipped then
			action.BackgroundColor3 = Color3.fromRGB(255, 170, 100)
			action.TextColor3 = Color3.fromRGB(10, 12, 18)
			L10nUtil.localize(action, L10n.Unequip)
			action.Active = canAct and equipId ~= ""
			action.AutoButtonColor = action.Active
			if action.Active then
				action.Activated:Connect(function()
					local remoteName = if kind == "Cosmetic" then "EquipCosmetic" else "EquipBackpack"
					local unequipId = if kind == "Cosmetic" and cosmeticSlot then "__unequip:" .. cosmeticSlot else ""
					local ok, msg = Remotes.Func(remoteName):InvokeServer(unequipId)
					if not ok then
						L10nUtil.localize(action, msg or L10n.Denied)
						task.wait(1.2)
					end
					render()
				end)
			else
				action.BackgroundColor3 = Color3.fromRGB(60, 66, 80)
				action.TextColor3 = Color3.fromRGB(190, 198, 214)
				L10nUtil.localize(action, L10n.Equipped)
			end
		else
			action.BackgroundColor3 = Color3.fromRGB(120, 255, 170)
			action.TextColor3 = Color3.fromRGB(10, 12, 18)
			L10nUtil.localize(action, L10n.Equip)
			action.Activated:Connect(function()
				local remoteName = if kind == "Cosmetic" then "EquipCosmetic" else "EquipBackpack"
				local ok, msg = Remotes.Func(remoteName):InvokeServer(equipId)
				if not ok then
					L10nUtil.localize(action, msg or L10n.Denied)
					task.wait(1.2)
				end
				render()
			end)
		end
	end

	render = function()
		local data = Remotes.Func("GetShopData"):InvokeServer()
		clearRows()
		if type(data) ~= "table" then
			return
		end

		local equipped = data.EquippedBackpack or ""
		local defaultCap = data.DefaultCapacity or 25
		addRow(L10n.DefaultBackpack, ("%s: %d"):format(L10n.CapacityLabel, defaultCap), equipped == "", "", "Backpack", true)

		for _, item in ipairs(data.Items or {}) do
			if item.Owned and item.Kind == "Backpack" then
				addRow(item.Label, ("%s: %d"):format(L10n.CapacityLabel, item.Capacity or 50), equipped == item.Id, item.Id, "Backpack", true)
			elseif item.Owned and item.Kind == "Cosmetic" then
				local slot = item.Slot or "Hat"
				local detail = if slot == "Shirt" then L10n.Shirts elseif slot == "Pet" then L10n.CosmeticPet else L10n.CosmeticHat
				addRow(item.Label, detail, item.Equipped == true, item.Id, "Cosmetic", true, slot)
			end
		end
	end

	local function setOpen(open: boolean)
		panel.Visible = open
		if open then
			render()
		end
	end

	openBtn.Activated:Connect(function()
		local willOpen = not panel.Visible
		setOpen(willOpen)
		if willOpen then
			pcall(function()
				local CC = require(script.Parent.ChallengeController)
				if type(CC) == "table" and type(CC.Close) == "function" then
					CC.Close()
				end
			end)
		end
	end)

	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if not panel.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
	end)

	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function()
		if panel.Visible then
			render()
		end
	end)
end

return InventoryUI
