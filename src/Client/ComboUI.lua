--!strict
-- Affichage du combo : compteur, multiplicateur, barre de temps restant.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10nUtil = require(Shared.LocalizationUtil)

local player = Players.LocalPlayer
local ComboUI = {}

local TIERS = {
	{ min = 0,  color = Color3.fromRGB(255, 255, 255) },
	{ min = 8,  color = Color3.fromRGB(120, 220, 255) },
	{ min = 16, color = Color3.fromRGB(255, 210, 80)  },
	{ min = 28, color = Color3.fromRGB(255, 120, 220) },
	{ min = 44, color = Color3.fromRGB(255, 80, 80)   },
}

local function tierColor(count: number): Color3
	local color = TIERS[1].color
	for _, tier in ipairs(TIERS) do
		if count >= tier.min then color = tier.color end
	end
	return color
end

function ComboUI.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BPW_Combo"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, 260, 0, 120)
	holder.Position = UDim2.new(1, -290, 0.5, -60)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	local countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.new(1, 0, 0, 62)
	countLabel.BackgroundTransparency = 1
	countLabel.TextColor3 = Color3.new(1, 1, 1)
	countLabel.TextStrokeTransparency = 0.25
	countLabel.Font = Enum.Font.GothamBlack
	countLabel.TextScaled = true
	countLabel.Parent = holder
	L10nUtil.dynamic(countLabel, "0")

	local multLabel = Instance.new("TextLabel")
	multLabel.Size = UDim2.new(1, 0, 0, 34)
	multLabel.Position = UDim2.new(0, 0, 0, 58)
	multLabel.BackgroundTransparency = 1
	multLabel.TextColor3 = Color3.new(1, 1, 1)
	multLabel.TextStrokeTransparency = 0.35
	multLabel.Font = Enum.Font.GothamBold
	multLabel.TextScaled = true
	multLabel.Parent = holder
	L10nUtil.dynamic(multLabel, "x1.0")

	local barBack = Instance.new("Frame")
	barBack.Size = UDim2.new(0.8, 0, 0, 8)
	barBack.Position = UDim2.new(0.1, 0, 0, 100)
	barBack.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	barBack.BackgroundTransparency = 0.75
	barBack.BorderSizePixel = 0
	barBack.Parent = holder
	local c1 = Instance.new("UICorner"); c1.CornerRadius = UDim.new(1, 0); c1.Parent = barBack

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.new(1, 1, 1)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(1, 0); c2.Parent = barFill

	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local expiresAt = 0
	local window = 2.5

	Remotes.Event("ComboUpdate").OnClientEvent:Connect(function(count, mult, win)
		window = win or window

		if count < 3 then
			holder.Visible = false
			expiresAt = 0
			return
		end

		local color = tierColor(count)
		holder.Visible = true
		L10nUtil.dynamic(countLabel, tostring(count))
		countLabel.TextColor3 = color
		L10nUtil.dynamic(multLabel, ("x%.1f"):format(mult))
		multLabel.TextColor3 = color
		barFill.BackgroundColor3 = color
		expiresAt = os.clock() + window

		-- Punch : la valeur grossit puis revient
		scale.Scale = 1.35
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end)

	RunService.RenderStepped:Connect(function()
		if not holder.Visible then return end
		local remaining = math.max(0, expiresAt - os.clock())
		barFill.Size = UDim2.new(math.clamp(remaining / window, 0, 1), 0, 1, 0)
		if remaining <= 0 then holder.Visible = false end
	end)
end

return ComboUI
