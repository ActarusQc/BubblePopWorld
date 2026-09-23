--!strict
-- HUD compact haut/centre des mini-événements (payload UI standardisé serveur).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local MiniEventConfig = require(Shared.MiniEventConfig)
local MiniEventLogic = require(Shared.MiniEventLogic)
local HudChrome = require(Shared.HudChrome)

local player = Players.LocalPlayer
local MiniEventController = {}

local gui: ScreenGui? = nil
local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local descLabel: TextLabel? = nil
local timerLabel: TextLabel? = nil
local progressLabel: TextLabel? = nil
local bonusLabel: TextLabel? = nil
local colorSwatch: Frame? = nil
local resultMode = false
local statePayload: any? = nil
local hideAt = 0.0
local lastLoggedEvent: string? = nil
local lastLoggedProgress = -1
local lastSoundAt: { [string]: number } = {}
local animToken = 0

local COIN_GOLD = HudChrome.COIN_YELLOW or Color3.fromRGB(255, 210, 70)
local DEV = RunService:IsStudio()
local EVENT_LEFT = 16
local EVENT_TOP = 182

local function isMuted(): boolean
	return player:GetAttribute("MusicMuted") == true
end

local function playSound(key: string)
	if isMuted() then
		return
	end
	local id = MiniEventConfig.Sounds[key]
	if type(id) ~= "string" or id == "" then
		return
	end
	local now = os.clock()
	if (lastSoundAt[key] or 0) + 0.4 > now then
		return
	end
	lastSoundAt[key] = now
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = MiniEventConfig.Sounds.Volume
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function formatTimer(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local m = math.floor(s / 60)
	local r = s % 60
	return string.format("⏱ %d:%02d", m, r)
end

local function panelWidth(): number
	local cam = Workspace.CurrentCamera
	local vw = if cam then cam.ViewportSize.X else 1280
	if vw < 500 then
		return math.clamp(math.floor(vw * 0.62), 210, 260)
	end
	return 250
end

local function ensureUI()
	if gui and gui.Parent and panel and panel.Parent then
		return
	end
	local pg = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "BPW_MiniEvent"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 25
	g.Parent = pg
	gui = g

	local p = Instance.new("Frame")
	p.Name = "MiniEventPanel"
	p.AnchorPoint = Vector2.new(0, 0)
	p.Position = UDim2.fromOffset(EVENT_LEFT, EVENT_TOP)
	p.Size = UDim2.fromOffset(panelWidth(), 128)
	p.BackgroundColor3 = Color3.fromRGB(18, 91, 150)
	p.BackgroundTransparency = 0.02
	p.BorderSizePixel = 0
	p.Visible = false
	p.ClipsDescendants = true
	p.Parent = g
	panel = p

	local corn = Instance.new("UICorner")
	corn.CornerRadius = UDim.new(0, 20)
	corn.Parent = p

	local str = Instance.new("UIStroke")
	str.Name = "Stroke"
	str.Color = Color3.fromRGB(140, 235, 255)
	str.Thickness = 2.5
	str.Transparency = 0
	str.Parent = p

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 133, 201)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(17, 75, 132)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(52, 43, 133)),
	})
	gradient.Rotation = 10
	gradient.Parent = p

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = p

	local swatch = Instance.new("Frame")
	swatch.Name = "ColorSwatch"
	swatch.Size = UDim2.fromOffset(12, 12)
	swatch.Position = UDim2.fromOffset(0, 4)
	swatch.BackgroundColor3 = Color3.new(1, 1, 1)
	swatch.BorderSizePixel = 0
	swatch.Visible = false
	swatch.ZIndex = 2
	swatch.Parent = p
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(1, 0)
	sc.Parent = swatch
	colorSwatch = swatch

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = 2
	title.Parent = p
	titleLabel = title

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.BackgroundTransparency = 1
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, 0, 0, 44)
	timer.Size = UDim2.fromOffset(78, 24)
	timer.BackgroundColor3 = Color3.fromRGB(8, 35, 68)
	timer.BackgroundTransparency = 0.04
	timer.Font = Enum.Font.GothamBlack
	timer.TextSize = 16
	timer.TextXAlignment = Enum.TextXAlignment.Right
	timer.TextColor3 = HudChrome.ACCENT
	timer.Text = ""
	timer.ZIndex = 2
	timer.Parent = p
	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(1, 0)
	timerCorner.Parent = timer
	local timerPadding = Instance.new("UIPadding")
	timerPadding.PaddingLeft = UDim.new(0, 8)
	timerPadding.PaddingRight = UDim.new(0, 8)
	timerPadding.Parent = timer
	timerLabel = timer

	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromOffset(0, 28)
	desc.Size = UDim2.new(1, 0, 0, 38)
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 13
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextColor3 = HudChrome.TEXT_SECONDARY
	desc.TextWrapped = true
	desc.Text = ""
	desc.ZIndex = 2
	desc.Parent = p
	descLabel = desc

	local progress = Instance.new("TextLabel")
	progress.Name = "Progress"
	progress.BackgroundTransparency = 1
	progress.Position = UDim2.fromOffset(0, 74)
	progress.Size = UDim2.new(1, 0, 0, 20)
	progress.Font = Enum.Font.GothamBold
	progress.TextSize = 14
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.TextColor3 = Color3.new(1, 1, 1)
	progress.Text = ""
	progress.ZIndex = 2
	progress.Parent = p
	progressLabel = progress

	local bonus = Instance.new("TextLabel")
	bonus.Name = "BonusCoins"
	bonus.BackgroundTransparency = 1
	bonus.Position = UDim2.fromOffset(0, 96)
	bonus.Size = UDim2.new(1, 0, 0, 18)
	bonus.Font = Enum.Font.GothamBold
	bonus.TextSize = 14
	bonus.TextXAlignment = Enum.TextXAlignment.Left
	bonus.TextColor3 = COIN_GOLD
	bonus.Text = ""
	bonus.ZIndex = 2
	bonus.Parent = p
	bonusLabel = bonus
end

local function animateIn()
	if not panel then
		return
	end
	animToken += 1
	local token = animToken
	panel.Visible = true
	panel.BackgroundTransparency = 1
	panel.Size = UDim2.fromOffset(panelWidth(), 120)
	local stroke = panel:FindFirstChild("Stroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Transparency = 1
	end
	panel.Position = UDim2.fromOffset(EVENT_LEFT - 10, EVENT_TOP)
	local goal = {
		BackgroundTransparency = 0.02,
		Position = UDim2.fromOffset(EVENT_LEFT, EVENT_TOP),
		Size = UDim2.fromOffset(panelWidth(), 128),
	}
	local tw = TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tw:Play()
	if stroke and stroke:IsA("UIStroke") then
		TweenService:Create(stroke, TweenInfo.new(0.28), { Transparency = 0.2 }):Play()
	end
	task.delay(0.3, function()
		if token ~= animToken or not panel then
			return
		end
		panel.BackgroundTransparency = 0.02
	end)
end

local function animateOut(thenHide: boolean)
	if not panel then
		return
	end
	animToken += 1
	local token = animToken
	local tw = TweenService:Create(
		panel,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(EVENT_LEFT - 10, EVENT_TOP),
			Size = UDim2.fromOffset(math.floor(panelWidth() * 0.96), 120),
		}
	)
	tw:Play()
	local stroke = panel:FindFirstChild("Stroke")
	if stroke and stroke:IsA("UIStroke") then
		TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end
	tw.Completed:Connect(function()
		if token ~= animToken then
			return
		end
		if thenHide and panel then
			panel.Visible = false
		end
	end)
end

local function animateSuccessPulse()
	if not panel then
		return
	end
	local stroke = panel:FindFirstChild("Stroke")
	if not stroke or not stroke:IsA("UIStroke") then
		return
	end
	stroke.Color = COIN_GOLD
	local tw = TweenService:Create(stroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Thickness = 2.2,
		Transparency = 0.05,
	})
	tw:Play()
	tw.Completed:Connect(function()
		if stroke.Parent then
			TweenService:Create(stroke, TweenInfo.new(0.4), {
				Thickness = 1.4,
				Transparency = 0.2,
				Color = HudChrome.ACCENT,
			}):Play()
		end
	end)
end

local function progressText(payload: any): string
	local et = tostring(payload.eventType or "")
	local cur = tonumber(payload.progressCurrent)
	if cur == nil and type(payload.progress) == "table" then
		cur = tonumber(payload.progress.current) or tonumber(payload.progress.personal)
	end
	cur = cur or 0
	local target = payload.progressTarget
	if target == nil and type(payload.progress) == "table" then
		target = payload.progress.required
	end
	if type(target) == "number" and target > 0 then
		return ("⭐ %s"):format(L10n.MiniEventProgressRatio:format(cur, target))
	end
	if et == "ColorRush" then
		return L10n.MiniEventProgressColor:format(cur)
	end
	if et == "GoldenWave" then
		return L10n.MiniEventProgressGolden:format(cur)
	end
	if cur > 0 then
		return tostring(cur)
	end
	return ""
end

local function applyResult(payload: any)
	resultMode = true
	local et = tostring(payload.eventType or "")
	local hasPass = payload.hasPassCondition == true
	local completed = payload.completed
	local bonus = tonumber(payload.bonusCoins) or 0
	if payload.rewardHint and type(payload.rewardHint.bonusCoins) == "number" then
		bonus = payload.rewardHint.bonusCoins
	elseif payload.rewardHint and type(payload.rewardHint.sellBonus) == "number" then
		bonus = payload.rewardHint.sellBonus
	end
	local cur = tonumber(payload.progressCurrent) or 0
	local target = tonumber(payload.progressTarget)

	local title = tostring(payload.displayName or et)
	if hasPass then
		if completed == true then
			if et == "GiantBubble" then
				title = L10n.MiniEventGiantBubbleComplete
			elseif et == "GoldenWave" then
				title = L10n.MiniEventGoldenWaveComplete
			elseif et == "ColorRush" then
				title = L10n.MiniEventColorRushComplete
			else
				title = L10n.MiniEventComplete
			end
		else
			title = L10n.MiniEventFailed
		end
	else
		if et == "GoldenWave" then
			title = L10n.MiniEventGoldenWaveOver
		elseif et == "ColorRush" then
			title = L10n.MiniEventColorRushOver
		else
			title = L10n.MiniEventComplete
		end
	end

	local line2 = ""
	if hasPass and completed == false and type(target) == "number" then
		line2 = L10n.MiniEventResultRatio:format(cur, target)
	elseif et == "GoldenWave" then
		line2 = L10n.MiniEventResultPopsGolden:format(cur)
	elseif et == "ColorRush" then
		line2 = L10n.MiniEventResultPopsColor:format(cur)
	elseif type(target) == "number" then
		line2 = L10n.MiniEventResultRatio:format(cur, target)
	end

	local line3 = ""
	if bonus > 0 then
		if hasPass and completed == false then
			line3 = L10n.MiniEventResultBonusEarned:format(bonus)
		else
			line3 = L10n.MiniEventResultBonus:format(bonus)
		end
	end

	if titleLabel then
		titleLabel.Text = title
		titleLabel.TextColor3 = if hasPass and completed == false
			then Color3.fromRGB(255, 140, 140)
			else COIN_GOLD
	end
	if descLabel then
		descLabel.Text = line2
		descLabel.TextColor3 = Color3.new(1, 1, 1)
	end
	if progressLabel then
		progressLabel.Text = ""
	end
	if bonusLabel then
		bonusLabel.Text = line3
		bonusLabel.TextColor3 = COIN_GOLD
	end
	if timerLabel then
		timerLabel.Text = ""
	end
	if colorSwatch then
		colorSwatch.Visible = false
	end
	if panel then
		panel.Size = UDim2.fromOffset(panelWidth(), if line3 ~= "" then 96 else 78)
		panel.Visible = true
	end
	if completed == true or (not hasPass and bonus > 0) then
		animateSuccessPulse()
	end
end

local function applyActiveLabels(payload: any, remaining: number)
	resultMode = false
	local et = tostring(payload.eventType or "")
	local displayName = tostring(payload.displayName or "")
	if displayName == "" then
		if et == "GoldenWave" then
			displayName = L10n.MiniEventGoldenWave
		elseif et == "ColorRush" then
			displayName = L10n.MiniEventColorRush
		elseif et == "GiantBubble" then
			displayName = L10n.MiniEventGiantBubble
		else
			displayName = et
		end
	end
	local objective = tostring(payload.objectiveText or "")
	if objective == "" then
		if et == "GoldenWave" then
			objective = L10n.MiniEventGoldenWaveObjective
		elseif et == "ColorRush" then
			objective = L10n.MiniEventColorRushObjective
		elseif et == "GiantBubble" then
			objective = L10n.MiniEventGiantBubbleObjective
		end
	end

	if payload.state == "Countdown" then
		if et == "GoldenWave" then
			displayName = L10n.MiniEventGoldenWaveIn:format(math.ceil(remaining))
		elseif et == "ColorRush" then
			displayName = L10n.MiniEventColorRushIn:format(math.ceil(remaining))
		elseif et == "GiantBubble" then
			displayName = L10n.MiniEventGiantBubbleIn:format(math.ceil(remaining))
		end
	end

	if titleLabel then
		titleLabel.Text = displayName
		titleLabel.TextColor3 = Color3.new(1, 1, 1)
		titleLabel.Position = if colorSwatch and colorSwatch.Visible
			then UDim2.fromOffset(18, 0)
			else UDim2.fromOffset(0, 0)
	end
	if descLabel then
		descLabel.Text = objective
		descLabel.TextColor3 = HudChrome.TEXT_SECONDARY
	end
	if timerLabel then
		timerLabel.Text = formatTimer(remaining)
	end
	if progressLabel then
		progressLabel.Text = if payload.state == "Active" then progressText(payload) else ""
	end
	if bonusLabel then
		local bonus = tonumber(payload.bonusCoins) or 0
		if payload.state == "Active" and bonus > 0 then
			bonusLabel.Text = L10n.MiniEventBonusCoinsFmt:format(bonus)
		else
			bonusLabel.Text = ""
		end
	end
	if panel then
		local h = if payload.state == "Active" and (tonumber(payload.bonusCoins) or 0) > 0 then 144 else 128
		panel.Size = UDim2.fromOffset(panelWidth(), h)
	end
end

local function applyPayload(payload: any)
	if type(payload) ~= "table" then
		return
	end

	local state = payload.state
	local prev = statePayload
	if state == "Countdown" or state == "Active" or state == "Ended" then
		if not prev or prev.state ~= state or prev.eventType ~= payload.eventType then
			if state == "Countdown" then
				playSound("Countdown")
			elseif state == "Active" then
				playSound("Start")
				if DEV then
					local dur = math.max(0, (tonumber(payload.endTime) or 0) - (tonumber(payload.startTime) or 0))
					print(("[MiniEventUI] Started %s duration=%.1f"):format(tostring(payload.eventType), dur))
					lastLoggedEvent = tostring(payload.eventType)
					lastLoggedProgress = -1
				end
			elseif state == "Ended" then
				if payload.outcome == "Failed" or payload.completed == false then
					playSound("Fail")
				else
					playSound("Success")
				end
				local bonus = tonumber(payload.bonusCoins) or 0
				if payload.rewardHint then
					if type(payload.rewardHint.sellBonus) == "number" then
						bonus = payload.rewardHint.sellBonus
						playSound("Reward")
					elseif type(payload.rewardHint.bonusCoins) == "number" then
						bonus = payload.rewardHint.bonusCoins
						if bonus > 0 then
							playSound("Reward")
						end
					end
				end
				if DEV then
					local success = payload.completed
					if success == nil then
						success = payload.outcome ~= "Failed"
					end
					print(
						("[MiniEventUI] Ended %s success=%s bonusCoins=%d"):format(
							tostring(payload.eventType),
							tostring(success),
							bonus
						)
					)
				end
			end
		elseif state == "Active" and DEV then
			local cur = tonumber(payload.progressCurrent) or 0
			if cur ~= lastLoggedProgress then
				lastLoggedProgress = cur
				print(
					("[MiniEventUI] Progress %s %d bonus=%d"):format(
						tostring(payload.eventType),
						cur,
						tonumber(payload.bonusCoins) or 0
					)
				)
			end
		end
	end
	statePayload = payload

	if state ~= "Countdown" and state ~= "Active" and state ~= "Ended" then
		statePayload = nil
		resultMode = false
		hideAt = 0
		animateOut(true)
		return
	end

	ensureUI()

	if colorSwatch then
		local show = payload.eventType == "ColorRush" and payload.objective and payload.objective.targetColor
		colorSwatch.Visible = show == true and state ~= "Ended"
		if show and state ~= "Ended" then
			local c = MiniEventLogic.DeserializeColor(payload.objective.targetColor)
			if c then
				colorSwatch.BackgroundColor3 = c
			end
		end
	end

	local wasHidden = panel ~= nil and panel.Visible ~= true
	if state == "Ended" then
		hideAt = os.clock() + (MiniEventConfig.EndedBannerSeconds or 4)
		applyResult(payload)
		if wasHidden then
			animateIn()
		end
		return
	end

	hideAt = 0
	resultMode = false
	if wasHidden then
		animateIn()
	elseif panel then
		panel.Visible = true
	end
end

function MiniEventController.Start()
	Remotes.Event("MiniEventState").OnClientEvent:Connect(function(payload)
		applyPayload(payload)
	end)

	RunService.RenderStepped:Connect(function()
		if hideAt > 0 and os.clock() >= hideAt then
			hideAt = 0
			statePayload = nil
			resultMode = false
			animateOut(true)
			return
		end
		local payload = statePayload
		if not payload or not panel or not panel.Visible then
			return
		end
		if payload.state == "Ended" or resultMode then
			return
		end
		local clock = Workspace:GetServerTimeNow()
		local remaining = 0
		if payload.state == "Countdown" then
			remaining = math.max(0, (payload.startTime or 0) - clock)
		else
			remaining = math.max(0, (payload.endTime or 0) - clock)
		end
		applyActiveLabels(payload, remaining)
	end)
end

return MiniEventController
