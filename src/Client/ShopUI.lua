--!strict
-- Boutique : onglets Compétences / Items. Ouverte depuis le kiosque ItemShop.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local player = Players.LocalPlayer
local ShopUI = {}

local BG = Color3.fromRGB(18, 20, 28)
local ROW = Color3.fromRGB(30, 34, 44)
local ROW_MAX = Color3.fromRGB(42, 46, 58)
local TAB_ON = Color3.fromRGB(120, 200, 255)
local TAB_OFF = Color3.fromRGB(50, 56, 70)

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

function ShopUI.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_Shop"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0.42, 0, 0.68, 0)
	panel.Position = UDim2.new(0.29, 0, 0.16, 0)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 16)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(360, 360)
	constraint.MaxSize = Vector2.new(560, 560)
	constraint.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -56, 0, 40)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	L10nUtil.localize(title, L10n.BubbleShop)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, 4)
	closeBtn.BackgroundColor3 = Color3.fromRGB(50, 56, 70)
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0
	closeBtn.Selectable = true
	closeBtn.Parent = panel
	L10nUtil.dynamic(closeBtn, L10n.Close)
	corner(closeBtn, 8)

	local tabSkills = Instance.new("TextButton")
	tabSkills.Size = UDim2.new(0.5, -16, 0, 34)
	tabSkills.Position = UDim2.new(0, 12, 0, 44)
	tabSkills.BackgroundColor3 = TAB_ON
	tabSkills.TextColor3 = Color3.fromRGB(10, 12, 18)
	tabSkills.Font = Enum.Font.GothamBold
	tabSkills.TextSize = 14
	tabSkills.BorderSizePixel = 0
	tabSkills.Parent = panel
	L10nUtil.localize(tabSkills, L10n.Skills)
	corner(tabSkills, 8)

	local tabItems = Instance.new("TextButton")
	tabItems.Size = UDim2.new(0.5, -16, 0, 34)
	tabItems.Position = UDim2.new(0.5, 4, 0, 44)
	tabItems.BackgroundColor3 = TAB_OFF
	tabItems.TextColor3 = Color3.new(1, 1, 1)
	tabItems.Font = Enum.Font.GothamBold
	tabItems.TextSize = 14
	tabItems.BorderSizePixel = 0
	tabItems.Parent = panel
	L10nUtil.localize(tabItems, L10n.Items)
	corner(tabItems, 8)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -96)
	scroll.Position = UDim2.new(0, 12, 0, 86)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll

	local activeTab = "skills"
	local firstButton: TextButton? = nil
	local render: () -> ()

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

	local function renderSkills(upgrades: { any })
		for _, item in ipairs(upgrades) do
			local isMax = item.Cost < 0 or item.Level >= item.Max

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 54)
			row.BackgroundColor3 = if isMax then ROW_MAX else ROW
			row.BorderSizePixel = 0
			row.Parent = scroll
			corner(row, 10)

			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(0.42, 0, 1, 0)
			name.Position = UDim2.new(0, 12, 0, 0)
			name.BackgroundTransparency = 1
			name.TextColor3 = if isMax then Color3.fromRGB(170, 178, 196) else Color3.new(1, 1, 1)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Parent = row
			L10nUtil.localize(name, item.Label)

			local level = Instance.new("TextLabel")
			level.Size = UDim2.new(0.28, 0, 1, 0)
			level.Position = UDim2.new(0.42, 0, 0, 0)
			level.BackgroundTransparency = 1
			level.TextColor3 = if isMax then Color3.fromRGB(170, 178, 196) else Color3.fromRGB(180, 190, 210)
			level.Font = Enum.Font.GothamMedium
			level.TextSize = 14
			level.TextXAlignment = Enum.TextXAlignment.Left
			level.Parent = row
			L10nUtil.dynamic(level, ("Lv. %d/%d"):format(item.Level, item.Max))

			local buy = Instance.new("TextButton")
			buy.Size = UDim2.new(0, 130, 0, 38)
			buy.Position = UDim2.new(1, -140, 0.5, -19)
			buy.BackgroundColor3 = if isMax then Color3.fromRGB(60, 66, 80) else Color3.fromRGB(120, 200, 255)
			buy.TextColor3 = if isMax then Color3.fromRGB(190, 198, 214) else Color3.fromRGB(10, 12, 18)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = 14
			buy.BorderSizePixel = 0
			buy.AutoButtonColor = not isMax
			buy.Active = not isMax
			buy.Selectable = not isMax
			buy.SelectionOrder = 1
			buy.Parent = row
			if isMax then
				L10nUtil.localize(buy, L10n.Max)
			else
				L10nUtil.dynamic(buy, comma(item.Cost) .. " " .. L10n.CoinsUnit)
			end
			corner(buy, 8)

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
			row.Size = UDim2.new(1, -8, 0, 64)
			row.BackgroundColor3 = if isEquipped then ROW_MAX else ROW
			row.BorderSizePixel = 0
			row.Parent = scroll
			corner(row, 10)

			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(0.55, 0, 0, 28)
			name.Position = UDim2.new(0, 12, 0, 6)
			name.BackgroundTransparency = 1
			name.TextColor3 = Color3.new(1, 1, 1)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Parent = row
			L10nUtil.localize(name, L10n.DefaultBackpack)

			local cap = Instance.new("TextLabel")
			cap.Size = UDim2.new(0.55, 0, 0, 22)
			cap.Position = UDim2.new(0, 12, 0, 34)
			cap.BackgroundTransparency = 1
			cap.TextColor3 = Color3.fromRGB(180, 190, 210)
			cap.Font = Enum.Font.GothamMedium
			cap.TextSize = 13
			cap.TextXAlignment = Enum.TextXAlignment.Left
			cap.Parent = row
			L10nUtil.dynamic(cap, ("%s: %d"):format(L10n.CapacityLabel, defaultCapacity or 25))

			local action = Instance.new("TextButton")
			action.Size = UDim2.new(0, 120, 0, 38)
			action.Position = UDim2.new(1, -132, 0.5, -19)
			action.BorderSizePixel = 0
			action.Font = Enum.Font.GothamBold
			action.TextSize = 14
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
		end

		for _, item in ipairs(items) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 64)
			row.BackgroundColor3 = if item.Equipped then ROW_MAX else ROW
			row.BorderSizePixel = 0
			row.Parent = scroll
			corner(row, 10)

			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(0.55, 0, 0, 28)
			name.Position = UDim2.new(0, 12, 0, 6)
			name.BackgroundTransparency = 1
			name.TextColor3 = Color3.new(1, 1, 1)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Parent = row
			L10nUtil.localize(name, item.Label)

			local cap = Instance.new("TextLabel")
			cap.Size = UDim2.new(0.55, 0, 0, 22)
			cap.Position = UDim2.new(0, 12, 0, 34)
			cap.BackgroundTransparency = 1
			cap.TextColor3 = Color3.fromRGB(180, 190, 210)
			cap.Font = Enum.Font.GothamMedium
			cap.TextSize = 13
			cap.TextXAlignment = Enum.TextXAlignment.Left
			cap.Parent = row
			L10nUtil.dynamic(cap, ("%s: %d"):format(L10n.CapacityLabel, item.Capacity or 50))

			local action = Instance.new("TextButton")
			action.Size = UDim2.new(0, 120, 0, 38)
			action.Position = UDim2.new(1, -132, 0.5, -19)
			action.BorderSizePixel = 0
			action.Font = Enum.Font.GothamBold
			action.TextSize = 14
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

	local function setOpen(open: boolean)
		panel.Visible = open
		if open then
			render()
			if firstButton then
				GuiService.SelectedObject = firstButton
			end
		else
			GuiService.SelectedObject = nil
		end
	end

	function ShopUI.Open()
		setOpen(true)
	end

	function ShopUI.Close()
		setOpen(false)
	end

	function ShopUI.Toggle()
		setOpen(not panel.Visible)
	end

	tabSkills.Activated:Connect(function()
		activeTab = "skills"
		render()
	end)

	tabItems.Activated:Connect(function()
		activeTab = "items"
		render()
	end)

	closeBtn.Activated:Connect(function()
		setOpen(false)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= player then
			return
		end
		if prompt:GetAttribute("BPW_OpenShop") == true then
			setOpen(true)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if not panel.Visible then return end
		if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
	end)
end

return ShopUI
