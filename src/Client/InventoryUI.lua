--!strict
-- Inventaire HUD : équiper / retirer les sacs possédés.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local player = Players.LocalPlayer
local InventoryUI = {}

local BG = Color3.fromRGB(18, 20, 28)
local ROW = Color3.fromRGB(30, 34, 44)
local ROW_ON = Color3.fromRGB(42, 46, 58)

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
end

function InventoryUI.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_Inventory"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	local openBtn = Instance.new("TextButton")
	openBtn.Name = "InventoryButton"
	openBtn.Size = UDim2.new(0, 110, 0, 40)
	openBtn.Position = UDim2.new(1, -126, 0, 16)
	openBtn.BackgroundColor3 = Color3.fromRGB(40, 48, 64)
	openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold
	openBtn.TextSize = 14
	openBtn.BorderSizePixel = 0
	openBtn.Parent = gui
	L10nUtil.localize(openBtn, L10n.Inventory)
	corner(openBtn, 10)

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 340, 0, 360)
	panel.Position = UDim2.new(1, -356, 0, 64)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)

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

	local function addRow(labelText: string, capacity: number, equipped: boolean, equipId: string, canAct: boolean)
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
		L10nUtil.dynamic(cap, ("%s: %d"):format(L10n.CapacityLabel, capacity))

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
					local ok, msg = Remotes.Func("EquipBackpack"):InvokeServer("")
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
				local ok, msg = Remotes.Func("EquipBackpack"):InvokeServer(equipId)
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
		addRow(L10n.DefaultBackpack, defaultCap, equipped == "", "", true)

		for _, item in ipairs(data.Items or {}) do
			if item.Owned then
				addRow(item.Label, item.Capacity or 50, item.Equipped == true, item.Id, true)
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
		setOpen(not panel.Visible)
	end)

	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if not panel.Visible then return end
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
