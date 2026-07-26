--!strict
-- Interface principale construite en code (aucun asset requis).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local HUD = {}

local ACCENT = Color3.fromRGB(120, 200, 255)
local BG = Color3.fromRGB(18, 20, 28)

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, scaled: boolean?)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = scaled ~= false
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

local function findSellValueLabel(): TextLabel?
	local root = workspace:FindFirstChild("BubblePopWorld")
	if not root then
		return nil
	end
	local lobby = root:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	local decor = lobby:FindFirstChild("LobbyDecor")
	local kiosk = lobby:FindFirstChild("SellKiosk")
	local board = (decor and decor:FindFirstChild("SellValueBoard"))
		or (kiosk and kiosk:FindFirstChild("SellValueBoard", true))
		or (kiosk and kiosk:FindFirstChild("ValueDisplaySurface", true))
		or lobby:FindFirstChild("SellValueBoard", true)
	if not (board and board:IsA("BasePart")) then
		return nil
	end
	local gui = board:FindFirstChild("SellValueGui")
		or board:FindFirstChildWhichIsA("SurfaceGui")
		or board:FindFirstChildWhichIsA("BillboardGui")
	if not gui then
		return nil
	end
	if not (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui")) then
		return nil
	end
	local textLabel = gui:FindFirstChild("Label", true)
	if textLabel and textLabel:IsA("TextLabel") then
		return textLabel
	end
	return nil
end

function HUD.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Panneau unique (stats + sac) — hors zone chat Roblox (bas-gauche).
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 270, 0, 148)
	panel.Position = UDim2.new(0, 16, 0, 16)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, 14)

	local coinsLabel = label(panel, "0 pièces", UDim2.new(1, -20, 0, 28), UDim2.new(0, 12, 0, 6))
	coinsLabel.TextColor3 = Color3.fromRGB(255, 210, 80)

	local levelLabel = label(panel, "Niveau 1  ·  0 bulles", UDim2.new(1, -20, 0, 20), UDim2.new(0, 12, 0, 36))

	local xpBack = Instance.new("Frame")
	xpBack.Size = UDim2.new(1, -24, 0, 8)
	xpBack.Position = UDim2.new(0, 12, 0, 58)
	xpBack.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	xpBack.BorderSizePixel = 0
	xpBack.Parent = panel
	corner(xpBack, 4)

	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = ACCENT
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBack
	corner(xpFill, 4)

	local backpackLabel = label(panel, "Sac : 0 / 0", UDim2.new(1, -24, 0, 22), UDim2.new(0, 12, 0, 72))
	backpackLabel.TextColor3 = ACCENT

	local backpackBack = Instance.new("Frame")
	backpackBack.Size = UDim2.new(1, -24, 0, 14)
	backpackBack.Position = UDim2.new(0, 12, 0, 98)
	backpackBack.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	backpackBack.BorderSizePixel = 0
	backpackBack.Parent = panel
	corner(backpackBack, 7)

	local backpackFill = Instance.new("Frame")
	backpackFill.Size = UDim2.new(0, 0, 1, 0)
	backpackFill.BackgroundColor3 = ACCENT
	backpackFill.BorderSizePixel = 0
	backpackFill.Parent = backpackBack
	corner(backpackFill, 7)

	local backpackStatus = label(panel, "Place disponible", UDim2.new(1, -24, 0, 18), UDim2.new(0, 12, 0, 118), false)
	backpackStatus.TextColor3 = ACCENT
	backpackStatus.TextSize = 13

	-- Compteur mondial
	local globalFrame = Instance.new("Frame")
	globalFrame.Size = UDim2.new(0, 320, 0, 52)
	globalFrame.Position = UDim2.new(0.5, -160, 0, 12)
	globalFrame.BackgroundColor3 = BG
	globalFrame.BackgroundTransparency = 0.2
	globalFrame.BorderSizePixel = 0
	globalFrame.Parent = gui
	corner(globalFrame, 12)

	local globalLabel = label(globalFrame, "Objectif mondial…", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 0, 5))
	globalLabel.TextXAlignment = Enum.TextXAlignment.Center

	local goalBack = Instance.new("Frame")
	goalBack.Size = UDim2.new(1, -20, 0, 12)
	goalBack.Position = UDim2.new(0, 10, 0, 32)
	goalBack.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	goalBack.BorderSizePixel = 0
	goalBack.Parent = globalFrame
	corner(goalBack, 6)

	local goalFill = Instance.new("Frame")
	goalFill.Size = UDim2.new(0, 0, 1, 0)
	goalFill.BackgroundColor3 = Color3.fromRGB(120, 255, 170)
	goalFill.BorderSizePixel = 0
	goalFill.Parent = goalBack
	corner(goalFill, 6)

	-- Bannières d'annonce (centre haut, hors chat)
	local toastHolder = Instance.new("Frame")
	toastHolder.Size = UDim2.new(0, 460, 0, 200)
	toastHolder.Position = UDim2.new(0.5, -230, 0, 78)
	toastHolder.BackgroundTransparency = 1
	toastHolder.Parent = gui
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Parent = toastHolder

	local TOAST_COLORS = {
		legendary = Color3.fromRGB(255, 180, 40),
		level = Color3.fromRGB(120, 255, 170),
		world = Color3.fromRGB(180, 140, 255),
		item = Color3.fromRGB(120, 200, 255),
		sell = Color3.fromRGB(255, 220, 100),
		backpack_full = Color3.fromRGB(255, 140, 100),
	}

	local function toast(text: string, kind: string?)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 36)
		frame.BackgroundColor3 = BG
		frame.BackgroundTransparency = 0.1
		frame.BorderSizePixel = 0
		frame.Parent = toastHolder
		corner(frame, 8)

		local l = label(frame, text, UDim2.new(1, -16, 1, 0), UDim2.new(0, 8, 0, 0))
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.TextColor3 = TOAST_COLORS[kind or ""] or Color3.new(1, 1, 1)

		task.delay(4, function()
			TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			frame:Destroy()
		end)
	end

	local function attributeNumber(name: string): number
		local value = player:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end

	local function refreshBackpack()
		local current = math.max(0, attributeNumber("CurrentBubbles"))
		local capacity = math.max(0, attributeNumber("BackpackCapacity"))
		local pendingSellValue = math.max(0, attributeNumber("PendingSellValue"))
		local ratio = if capacity > 0 then math.clamp(current / capacity, 0, 1) else 0

		backpackLabel.Text = ("Sac : %s / %s"):format(comma(current), comma(capacity))
		backpackFill.Size = UDim2.new(ratio, 0, 1, 0)

		if ratio >= 1 then
			backpackFill.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
			backpackStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
			backpackStatus.Text = "Sac plein !"
		elseif ratio >= Config.Backpack.NearlyFullRatio then
			backpackFill.BackgroundColor3 = Color3.fromRGB(255, 190, 70)
			backpackStatus.TextColor3 = Color3.fromRGB(255, 210, 90)
			backpackStatus.Text = "Sac presque plein"
		else
			backpackFill.BackgroundColor3 = ACCENT
			backpackStatus.TextColor3 = ACCENT
			backpackStatus.Text = "Place disponible"
		end

		-- Valeur du sac : écran du kiosque (monde), pas dans le HUD.
		local sellLabel = findSellValueLabel()
		if sellLabel then
			-- SurfaceGui du kiosque : Label = montant seul ; Billboard legacy = phrase complète.
			if sellLabel.Parent and sellLabel.Parent:IsA("Frame") then
				sellLabel.Text = comma(pendingSellValue)
			else
				sellLabel.Text = ("Valeur du sac : %s pièces"):format(comma(pendingSellValue))
			end
		end
	end

	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function(stats)
		coinsLabel.Text = comma(stats.Coins) .. " pièces"
		levelLabel.Text = ("Niveau %d  ·  %s bulles"):format(stats.Level, comma(stats.Pops))
		local ratio = if stats.XPNeeded > 0 then math.clamp(stats.XP / stats.XPNeeded, 0, 1) else 0
		TweenService:Create(xpFill, TweenInfo.new(0.25), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
	end)

	for _, attributeName in { "CurrentBubbles", "BackpackCapacity", "PendingSellValue", "PlayerArea" } do
		player:GetAttributeChangedSignal(attributeName):Connect(refreshBackpack)
	end
	refreshBackpack()

	-- Le panneau vente peut apparaître après le HUD (sync Rojo / EnsureWorld).
	task.spawn(function()
		for _ = 1, 40 do
			if findSellValueLabel() then
				refreshBackpack()
				break
			end
			task.wait(0.25)
		end
	end)

	Remotes.Event("GlobalCounter").OnClientEvent:Connect(function(total, target)
		globalLabel.Text = ("%s / %s bulles"):format(comma(total), comma(target))
		goalFill.Size = UDim2.new(math.clamp(total / target, 0, 1), 0, 1, 0)
	end)

	Remotes.Event("Announce").OnClientEvent:Connect(toast)

	HUD.Toast = toast
	return HUD
end

return HUD
