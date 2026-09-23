--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local HudChrome = require(Shared.HudChrome)
local Config = require(Shared.CollectionConfig)

local CollectionController = {}
local stateRemote = Remotes.Event("CollectionState")
local requestRemote = Remotes.Event("CollectionRequestState")
local discoveredRemote = Remotes.Event("CollectionDiscovered")
local targetRemote = Remotes.Event("CollectionTarget")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, radius) c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke") s.Color = color s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Transparency = transparency or 0 s.Parent = parent return s
end

function CollectionController.Start()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	if playerGui:FindFirstChild("BPW_Collection") then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_Collection" gui.ResetOnSpawn = false gui.IgnoreGuiInset = true gui.DisplayOrder = 85 gui.Parent = playerGui

	local open = Instance.new("TextButton")
	open.Name = "CollectionButton" open.Size = UDim2.fromOffset(64, 64) open.LayoutOrder = 4
	open.BackgroundColor3 = Color3.fromRGB(157, 91, 231)
	open.BackgroundColor3 = Color3.fromRGB(12, 31, 50) open.Text = "◉" open.TextSize = 34
	open.TextColor3 = Color3.new(1,1,1) open.Font = Enum.Font.GothamBlack
	open.BackgroundColor3 = Color3.fromRGB(157, 91, 231)
	open.AutoButtonColor = false open.Active = true open.Selectable = true open.SelectionOrder = 4
	open:SetAttribute("AccessibleName", "Collection")
	local openCorner = Instance.new("UICorner")
	openCorner.CornerRadius = UDim.new(0.5, 0)
	openCorner.Parent = open
	stroke(open, Color3.new(1,1,1), 2.2)
	local collectionCaption = Instance.new("TextLabel")
	collectionCaption.Name = "MenuCaption" collectionCaption.AnchorPoint = Vector2.new(0.5,0)
	collectionCaption.Position = UDim2.new(0.5,0,1,2) collectionCaption.Size = UDim2.fromOffset(100,16)
	collectionCaption.BackgroundTransparency = 1 collectionCaption.Text = "COLLECTION"
	collectionCaption.TextColor3 = Color3.new(1,1,1) collectionCaption.TextStrokeColor3 = Color3.fromRGB(12,30,48)
	collectionCaption.TextStrokeTransparency = 0.2 collectionCaption.Font = Enum.Font.GothamBlack collectionCaption.TextSize = 10
	collectionCaption.ZIndex = 8 collectionCaption.Parent = open

	local badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(1, 0) badge.Position = UDim2.new(1, 5, 0, -5) badge.Size = UDim2.fromOffset(24, 24)
	badge.BackgroundColor3 = Color3.fromRGB(255, 192, 35) badge.TextColor3 = Color3.fromRGB(30, 20, 5)
	badge.Text = "!" badge.Font = Enum.Font.GothamBlack badge.TextSize = 14 badge.Visible = false badge.ZIndex = 4 badge.Parent = open
	corner(badge, 12)

	local targetToast = Instance.new("TextLabel")
	targetToast.Name = "CollectionTargetToast"
	targetToast.AnchorPoint = Vector2.new(0.5, 0)
	targetToast.Position = UDim2.new(0.5, 0, 0, 78)
	targetToast.Size = UDim2.fromOffset(520, 64)
	targetToast.BackgroundColor3 = Color3.fromRGB(8, 55, 91)
	targetToast.BackgroundTransparency = 0.08
	targetToast.Text = "A SPECIAL BUBBLE APPEARED NEARBY!"
	targetToast.TextColor3 = Color3.fromRGB(255, 221, 62)
	targetToast.Font = Enum.Font.GothamBlack
	targetToast.TextSize = 22
	targetToast.Visible = false
	targetToast.ZIndex = 20
	targetToast.Parent = gui
	corner(targetToast, 18)
	stroke(targetToast, Color3.fromRGB(69, 222, 255), 3)

	local targetPart: BasePart? = nil
	local targetBillboard: BillboardGui? = nil
	local targetHighlight: Highlight? = nil
	local targetConnection: RBXScriptConnection? = nil
	local toastGeneration = 0

	local function clearTargetVisual()
		targetPart = nil
		if targetConnection then targetConnection:Disconnect() targetConnection = nil end
		if targetBillboard then targetBillboard:Destroy() targetBillboard = nil end
		if targetHighlight then targetHighlight:Destroy() targetHighlight = nil end
	end

	local function showTargetVisual(payload: any)
		clearTargetVisual()
		if type(payload) ~= "table" or payload.Active ~= true then return end
		local bubble = payload.Bubble
		if not bubble or not bubble:IsA("BasePart") then return end
		targetPart = bubble
		targetHighlight = Instance.new("Highlight")
		targetHighlight.Name = "PersonalCollectionHighlight"
		targetHighlight.Adornee = bubble
		targetHighlight.FillColor = Color3.fromRGB(44, 221, 255)
		targetHighlight.FillTransparency = 0.68
		targetHighlight.OutlineColor = Color3.fromRGB(255, 220, 42)
		targetHighlight.OutlineTransparency = 0
		targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		targetHighlight.Parent = bubble

		targetBillboard = Instance.new("BillboardGui")
		targetBillboard.Name = "PersonalCollectionGuide"
		targetBillboard.Size = UDim2.fromOffset(210, 68)
		targetBillboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
		targetBillboard.AlwaysOnTop = true
		targetBillboard.MaxDistance = 240
		targetBillboard.Parent = bubble
		local guide = Instance.new("TextLabel")
		guide.Name = "GuideText"
		guide.Size = UDim2.fromScale(1, 1)
		guide.BackgroundColor3 = Color3.fromRGB(7, 48, 82)
		guide.BackgroundTransparency = 0.12
		guide.TextColor3 = Color3.fromRGB(255, 225, 54)
		guide.Font = Enum.Font.GothamBlack
		guide.TextSize = 17
		guide.Text = "★ SPECIAL BUBBLE"
		guide.Parent = targetBillboard
		corner(guide, 14)
		stroke(guide, Color3.fromRGB(67, 224, 255), 2)

		toastGeneration += 1
		local generation = toastGeneration
		targetToast.Visible = true
		task.delay(4, function()
			if toastGeneration == generation then targetToast.Visible = false end
		end)

		local elapsed = 0
		targetConnection = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.15 then return end
			elapsed = 0
			if not targetPart or not targetPart.Parent or not targetBillboard then clearTargetVisual() return end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local label = targetBillboard:FindFirstChild("GuideText")
			if root and root:IsA("BasePart") and label and label:IsA("TextLabel") then
				local distance = math.floor((targetPart.Position - root.Position).Magnitude + 0.5)
				label.Text = ("★ SPECIAL BUBBLE  •  %d m"):format(distance)
			end
		end)
	end

	task.spawn(function()
		local column: Frame? = nil
		repeat
			local found = playerGui:FindFirstChild(HudChrome.ACTION_COLUMN_NAME, true)
			if found and found:IsA("Frame") then column = found else task.wait(0.1) end
		until column
		open.Parent = column
		task.wait(0.2)
		local inv = column:FindFirstChild(HudChrome.INVENTORY_BUTTON_NAME, true)
		local challenges = column:FindFirstChild(HudChrome.CHALLENGES_BUTTON_NAME, true)
		local music = column:FindFirstChild(HudChrome.MUSIC_BUTTON_NAME, true)
		local daily = column:FindFirstChild("DailyRewardsButton", true)
		if inv and inv:IsA("GuiButton") and challenges and challenges:IsA("GuiButton")
			and music and music:IsA("GuiButton") then
			inv.NextSelectionDown = challenges challenges.NextSelectionUp = inv
			challenges.NextSelectionDown = music music.NextSelectionUp = challenges
			music.NextSelectionDown = open open.NextSelectionUp = music
			if daily and daily:IsA("GuiButton") then
				open.NextSelectionDown = daily daily.NextSelectionUp = open
				daily.NextSelectionDown = inv inv.NextSelectionUp = daily
			else
				open.NextSelectionDown = inv inv.NextSelectionUp = open
			end
		end
		local list = column:FindFirstChildOfClass("UIListLayout")
		local gap = if list then list.Padding.Offset else 12
		local count = 0
		for _, child in column:GetChildren() do
			if child:IsA("GuiObject") and (child:IsA("GuiButton") or child.Name == "InventorySlot") then count += 1 end
		end
		column.Size = UDim2.fromOffset(64, 64 * count + gap * math.max(0, count - 1))
	end)

	local shade = Instance.new("TextButton")
	shade.Name = "Shade" shade.Size = UDim2.fromScale(1, 1) shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.3 shade.Text = "" shade.Visible = false shade.AutoButtonColor = false shade.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5) panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.9, 0.88) panel.BackgroundColor3 = Color3.fromRGB(4, 15, 32)
	panel.BorderSizePixel = 0 panel.ClipsDescendants = true panel.Parent = shade
	corner(panel, 24) stroke(panel, Color3.fromRGB(38, 209, 255), 3)

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 100) header.BackgroundColor3 = Color3.fromRGB(8, 37, 70) header.BorderSizePixel = 0 header.Parent = panel
	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(28, 12) title.Size = UDim2.new(1, -140, 0, 46) title.BackgroundTransparency = 1
	title.Text = "COLLECTION DE BULLES" title.TextColor3 = Color3.new(1, 1, 1) title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBlack title.TextSize = 30 title.Parent = header
	local progress = Instance.new("TextLabel")
	progress.Position = UDim2.fromOffset(30, 58) progress.Size = UDim2.new(1, -160, 0, 26) progress.BackgroundTransparency = 1
	progress.Text = "0 / 22 découvertes" progress.TextColor3 = Color3.fromRGB(117, 222, 255)
	progress.TextXAlignment = Enum.TextXAlignment.Left progress.Font = Enum.Font.GothamBold progress.TextSize = 17 progress.Parent = header
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0.5) close.Position = UDim2.new(1, -22, 0.5, 0) close.Size = UDim2.fromOffset(62, 62)
	close.BackgroundColor3 = Color3.fromRGB(33, 53, 82) close.Text = "X" close.TextColor3 = Color3.fromRGB(255, 205, 55)
	close.Font = Enum.Font.GothamBlack close.TextSize = 30 close.Selectable = true close.Parent = header
	corner(close, 14) stroke(close, Color3.fromRGB(255, 202, 50), 2)

	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.fromOffset(24, 112) tabs.Size = UDim2.new(1, -48, 0, 48) tabs.BackgroundTransparency = 1 tabs.Parent = panel
	local tabLayout = Instance.new("UIListLayout") tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder tabLayout.Padding = UDim.new(0, 12) tabLayout.Parent = tabs

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(24, 174) scroll.Size = UDim2.new(1, -48, 1, -194)
	scroll.BackgroundTransparency = 1 scroll.BorderSizePixel = 0 scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(65, 205, 245) scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new() scroll.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.235, 0, 0, 158) grid.CellPadding = UDim2.new(0.02, 0, 0, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder grid.Parent = scroll

	local currentState: any = { Catalog = Config.PublicCatalog(), Discovered = {}, FoundCounts = {} }
	local activeRarity = "Common"
	local tabsByRarity = {}
	local pendingRevealId: string? = nil

	local function render()
		for _, child in scroll:GetChildren() do if child ~= grid then child:Destroy() end end
		local foundCount = 0
		for _, def in ipairs(currentState.Catalog or {}) do
			if currentState.Discovered and currentState.Discovered[def.Id] then foundCount += 1 end
		end
		progress.Text = ("%d / %d découvertes"):format(foundCount, #(currentState.Catalog or {}))
		for rarity, tab in pairs(tabsByRarity) do
			tab.BackgroundColor3 = if rarity == activeRarity then Config.Rarities[rarity].Color else Color3.fromRGB(24, 45, 72)
		end
		for index, def in ipairs(currentState.Catalog or {}) do
			if def.Rarity ~= activeRarity then continue end
			local owned = currentState.Discovered and currentState.Discovered[def.Id] == true
			local revealThis = owned and pendingRevealId == def.Id
			local card = Instance.new("Frame") card.LayoutOrder = index card.BackgroundColor3 = if owned then Color3.fromRGB(9, 45, 75) else Color3.fromRGB(24, 39, 58)
			card.BorderSizePixel = 0 card.Parent = scroll corner(card, 16)
			stroke(card, if owned then Config.Rarities[def.Rarity].Color else Color3.fromRGB(72, 107, 139), if owned then 2 else 1)
			local image = Instance.new("ImageLabel") image.Position = UDim2.new(0.5, -43, 0, 8) image.Size = UDim2.fromOffset(86, 86)
			image.BackgroundColor3 = if owned then Color3.fromRGB(49, 76, 101) else Color3.fromRGB(9, 24, 42)
			image.BackgroundTransparency = if owned then 1 else 0.05
			-- Aucun asset réel n'est chargé avant la découverte.
			image.Image = if owned then (def.ImageId or "") else ""
			image.ImageColor3 = Color3.new(1, 1, 1)
			image.ImageTransparency = if revealThis then 1 else 0
			image.Parent = card
			corner(image, 43)
			if not owned or image.Image == "" then
				local mark = Instance.new("TextLabel") mark.Size = UDim2.fromScale(1, 1) mark.BackgroundTransparency = 1
				mark.Text = if owned then "★" else "?" mark.TextColor3 = if owned then Config.Rarities[def.Rarity].Color else Color3.fromRGB(76, 122, 164)
				mark.Font = Enum.Font.GothamBlack mark.TextScaled = true mark.Parent = image
			end
			local name = Instance.new("TextLabel") name.Position = UDim2.new(0, 8, 0, 96) name.Size = UDim2.new(1, -16, 0, 24)
			name.BackgroundTransparency = 1 name.Text = if owned then def.Name else "???" name.TextColor3 = Color3.new(1, 1, 1)
			name.TextTransparency = if revealThis then 1 else 0
			name.Font = Enum.Font.GothamBold name.TextSize = 15 name.TextWrapped = true name.Parent = card
			local foundTimes = math.max(1, math.floor(tonumber(currentState.FoundCounts and currentState.FoundCounts[def.Id]) or 1))
			local status = Instance.new("TextLabel") status.Position = UDim2.new(0, 10, 1, -30) status.Size = UDim2.new(1, -20, 0, 22)
			status.BackgroundColor3 = if owned then Color3.fromRGB(17, 113, 89) elseif def.Available then Color3.fromRGB(49, 67, 91) else Color3.fromRGB(65, 40, 80)
			status.Text = if owned
				then (if foundTimes == 1 then "✓ TROUVÉE 1 FOIS" else ("✓ TROUVÉE %d FOIS"):format(foundTimes))
				elseif def.Available then "À DÉCOUVRIR" else "ZONE À VENIR"
			status.TextColor3 = if owned then Color3.fromRGB(82, 255, 190) else Color3.fromRGB(224, 233, 246)
			status.Font = Enum.Font.GothamBold status.TextSize = 11 status.Parent = card corner(status, 10)
			if revealThis then
				pendingRevealId = nil
				image.Position = UDim2.new(0.5, -20, 0, 31) image.Size = UDim2.fromOffset(40, 40)
				card.BackgroundColor3 = Color3.fromRGB(18, 90, 120)
				task.defer(function()
					TweenService:Create(image, TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						Position = UDim2.new(0.5, -43, 0, 8), Size = UDim2.fromOffset(86, 86), ImageTransparency = 0,
					}):Play()
					TweenService:Create(name, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
					TweenService:Create(card, TweenInfo.new(0.55), { BackgroundColor3 = Color3.fromRGB(9, 45, 75) }):Play()
				end)
			end
		end
	end

	for tabIndex, rarity in ipairs(Config.RarityOrder) do
		local tab = Instance.new("TextButton") tab.Name = rarity tab.Size = UDim2.fromOffset(180, 46)
		tab.LayoutOrder = tabIndex
		tab.Text = Config.Rarities[rarity].Label tab.TextColor3 = Color3.new(1, 1, 1) tab.Font = Enum.Font.GothamBlack tab.TextSize = 17
		tab.AutoButtonColor = false tab.Selectable = true tab.Parent = tabs corner(tab, 12)
		tabsByRarity[rarity] = tab
		tab.Activated:Connect(function() activeRarity = rarity render() end)
	end
	for index, rarity in ipairs(Config.RarityOrder) do
		local tab = tabsByRarity[rarity]
		local previousRarity = Config.RarityOrder[if index == 1 then #Config.RarityOrder else index - 1]
		local nextRarity = Config.RarityOrder[if index == #Config.RarityOrder then 1 else index + 1]
		tab.NextSelectionLeft = tabsByRarity[previousRarity]
		tab.NextSelectionRight = tabsByRarity[nextRarity]
		tab.NextSelectionUp = close
	end
	close.NextSelectionDown = tabsByRarity[Config.RarityOrder[1]]

	local function setVisible(visible: boolean)
		shade.Visible = visible open.Visible = not visible
		if visible then
			requestRemote:FireServer()
			task.defer(function() GuiService.SelectedObject = close end)
		else
			GuiService.SelectedObject = nil
		end
	end
	open.Activated:Connect(function() badge.Visible = false setVisible(true) end)
	close.Activated:Connect(function() setVisible(false) end)
	shade.Activated:Connect(function() setVisible(false) end)
	stateRemote.OnClientEvent:Connect(function(newState) if type(newState) == "table" then currentState = newState render() end end)
	discoveredRemote.OnClientEvent:Connect(function(definition)
		if type(definition) == "table" and type(definition.Id) == "string" then
			pendingRevealId = definition.Id
		end
		badge.Visible = true
	end)
	targetRemote.OnClientEvent:Connect(showTargetVisual)

	local function responsive()
		local camera = workspace.CurrentCamera
		local vp = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local columns = if vp.X < 760 then 2 elseif vp.X < 1150 then 3 else 4
		grid.CellSize = UDim2.new((1 - 0.02 * (columns - 1)) / columns, 0, 0, if vp.Y < 700 then 146 else 158)
		title.TextSize = if vp.X < 760 then 22 else 30
	end
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(responsive) end
	responsive() render() requestRemote:FireServer()
end

return CollectionController
