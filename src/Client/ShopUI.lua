--!strict
-- Boutique d'améliorations. Clavier (B), tactile, et manette (Y).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local ShopUI = {}

local BG = Color3.fromRGB(18, 20, 28)

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
end

function ShopUI.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_Shop"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.new(0, 130, 0, 44)
	toggle.Position = UDim2.new(0, 16, 0, 124)
	toggle.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	toggle.Text = "Shop"
	toggle.TextColor3 = Color3.fromRGB(10, 12, 18)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 16
	toggle.BorderSizePixel = 0
	toggle.Selectable = false
	toggle.Parent = gui
	corner(toggle, 12)

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0.42, 0, 0.62, 0)
	panel.Position = UDim2.new(0.29, 0, 0.19, 0)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 16)

	-- Marge de sécurité pour les téléviseurs (10-foot UI)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(360, 320)
	constraint.MaxSize = Vector2.new(560, 520)
	constraint.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 46)
	title.BackgroundTransparency = 1
	title.Text = "Upgrades"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -64)
	scroll.Position = UDim2.new(0, 12, 0, 52)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll

	local firstButton: TextButton? = nil

	local function render()
		local data = Remotes.Func("GetShopData"):InvokeServer()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		firstButton = nil

		for _, item in ipairs(data or {}) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 54)
			row.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
			row.BorderSizePixel = 0
			row.Parent = scroll
			corner(row, 10)

			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(1, -150, 1, 0)
			name.Position = UDim2.new(0, 12, 0, 0)
			name.BackgroundTransparency = 1
			name.Text = ("%s  ·  lv. %d/%d"):format(item.Label, item.Level, item.Max)
			name.TextColor3 = Color3.new(1, 1, 1)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Parent = row

			local buy = Instance.new("TextButton")
			buy.Size = UDim2.new(0, 130, 0, 38)
			buy.Position = UDim2.new(1, -140, 0.5, -19)
			buy.BackgroundColor3 = if item.Cost < 0 then Color3.fromRGB(60, 66, 80) else Color3.fromRGB(120, 200, 255)
			buy.TextColor3 = Color3.fromRGB(10, 12, 18)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = 14
			buy.Text = if item.Cost < 0 then "MAX" else (tostring(item.Cost) .. " coins")
			buy.BorderSizePixel = 0
			buy.Selectable = true
			buy.SelectionOrder = 1
			buy.Parent = row
			corner(buy, 8)

			if not firstButton then firstButton = buy end

			buy.Activated:Connect(function()
				if item.Cost < 0 then return end
				local ok, msg = Remotes.Func("BuyUpgrade"):InvokeServer(item.Id)
				if not ok then
					buy.Text = msg or "Denied"
					task.wait(1)
				end
				render()
			end)
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

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(0, 130, 0, 16)
	hint.Position = UDim2.new(0, 16, 0, 168)
	hint.BackgroundTransparency = 1
	hint.Text = "PC: B   ·   Xbox: Y"
	hint.TextColor3 = Color3.fromRGB(200, 210, 230)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.Parent = gui

	toggle.Activated:Connect(function() setOpen(not panel.Visible) end)

	-- B (clavier) OU Y (manette) — un seul bouton suffit, pas les deux en même temps
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.B then
			setOpen(not panel.Visible)
		elseif input.KeyCode == Enum.KeyCode.ButtonY then
			setOpen(not panel.Visible)
		elseif input.KeyCode == Enum.KeyCode.ButtonB and panel.Visible then
			setOpen(false)
		end
	end)
end

return ShopUI