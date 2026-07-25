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

function HUD.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Panneau stats
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 260, 0, 96)
	panel.Position = UDim2.new(0, 16, 0, 16)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, 14)

	local coinsLabel = label(panel, "0", UDim2.new(1, -20, 0, 30), UDim2.new(0, 12, 0, 8))
	coinsLabel.TextColor3 = Color3.fromRGB(255, 210, 80)

	local levelLabel = label(panel, "Niveau 1", UDim2.new(1, -20, 0, 22), UDim2.new(0, 12, 0, 42))

	local xpBack = Instance.new("Frame")
	xpBack.Size = UDim2.new(1, -24, 0, 14)
	xpBack.Position = UDim2.new(0, 12, 0, 70)
	xpBack.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
	xpBack.BorderSizePixel = 0
	xpBack.Parent = panel
	corner(xpBack, 7)

	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = ACCENT
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBack
	corner(xpFill, 7)

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

	-- Bannières d'annonce
	local toastHolder = Instance.new("Frame")
	toastHolder.Size = UDim2.new(0, 420, 0, 200)
	toastHolder.Position = UDim2.new(0.5, -210, 0, 80)
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
	}

	local function toast(text: string, kind: string?)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 34)
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

	-- Branchements
	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function(stats)
		coinsLabel.Text = comma(stats.Coins) .. " pièces"
		levelLabel.Text = ("Niveau %d  ·  %s bulles"):format(stats.Level, comma(stats.Pops))
		local ratio = if stats.XPNeeded > 0 then math.clamp(stats.XP / stats.XPNeeded, 0, 1) else 0
		TweenService:Create(xpFill, TweenInfo.new(0.25), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
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
