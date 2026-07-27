--!strict
-- Boutique d'améliorations. Ouverte uniquement depuis le kiosque ItemShop (ProximityPrompt).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local ShopUI = {}

local BG = Color3.fromRGB(18, 20, 28)
local ROW = Color3.fromRGB(30, 34, 44)
local ROW_MAX = Color3.fromRGB(42, 46, 58)

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
	title.Size = UDim2.new(1, -56, 0, 46)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "Upgrades"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, 6)
	closeBtn.BackgroundColor3 = Color3.fromRGB(50, 56, 70)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.BorderSizePixel = 0
	closeBtn.Selectable = true
	closeBtn.Parent = panel
	corner(closeBtn, 8)

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
			local isMax = item.Cost < 0 or item.Level >= item.Max

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 54)
			row.BackgroundColor3 = if isMax then ROW_MAX else ROW
			row.BorderSizePixel = 0
			row.Parent = scroll
			corner(row, 10)

			local name = Instance.new("TextLabel")
			name.Size = UDim2.new(1, -150, 1, 0)
			name.Position = UDim2.new(0, 12, 0, 0)
			name.BackgroundTransparency = 1
			name.Text = ("%s · Lv. %d/%d"):format(item.Label, item.Level, item.Max)
			name.TextColor3 = if isMax then Color3.fromRGB(170, 178, 196) else Color3.new(1, 1, 1)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 15
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Parent = row

			local buy = Instance.new("TextButton")
			buy.Size = UDim2.new(0, 130, 0, 38)
			buy.Position = UDim2.new(1, -140, 0.5, -19)
			buy.BackgroundColor3 = if isMax then Color3.fromRGB(60, 66, 80) else Color3.fromRGB(120, 200, 255)
			buy.TextColor3 = if isMax then Color3.fromRGB(190, 198, 214) else Color3.fromRGB(10, 12, 18)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = 14
			buy.Text = if isMax then "MAX" else (comma(item.Cost) .. " coins")
			buy.BorderSizePixel = 0
			buy.AutoButtonColor = not isMax
			buy.Active = not isMax
			buy.Selectable = not isMax
			buy.SelectionOrder = 1
			buy.Parent = row
			corner(buy, 8)

			if not isMax and not firstButton then
				firstButton = buy
			end

			if not isMax then
				buy.Activated:Connect(function()
					local ok, msg = Remotes.Func("BuyUpgrade"):InvokeServer(item.Id)
					if not ok then
						buy.Text = msg or "Denied"
						task.wait(1)
					end
					render()
				end)
			end
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

	-- Fermeture manette / clavier uniquement (pas d'ouverture hors kiosque).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if not panel.Visible then return end
		if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
		end
	end)
end

return ShopUI
