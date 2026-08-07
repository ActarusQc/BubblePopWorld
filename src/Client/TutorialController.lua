--!strict
-- Client tutoriel : une consigne à la fois + guidage marteau (étape guide).
-- Aucune validation métier ici — affichage purement réactif au serveur.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local TutorialConfig = require(Shared.TutorialConfig)

local player = Players.LocalPlayer
local TutorialController = {}

local gui: ScreenGui? = nil
local bubble: Frame? = nil
local messageLabel: TextLabel? = nil
local progressLabel: TextLabel? = nil
local rewardLabel: TextLabel? = nil

local celebrateConn: RBXScriptConnection? = nil
local guideConn: RBXScriptConnection? = nil
local guideHighlight: Highlight? = nil
local guideBillboard: BillboardGui? = nil
local guideBeam: Beam? = nil
local guideAtt0: Attachment? = nil
local guideAtt1: Attachment? = nil
local guideTarget: BasePart? = nil
local guideActive = false
local guideToolId = TutorialConfig.Ids.HammerToolId
local lastScan = 0.0
local celebrateSound: Sound? = nil
local currentStepId = 0
local hideToken = 0

local UI = TutorialConfig.UI
local Guide = TutorialConfig.Guide

local function ensureGui()
	if gui and gui.Parent then
		return
	end
	local pg = player:WaitForChild("PlayerGui")
	local existing = pg:FindFirstChild(UI.ScreenName)
	if existing and existing:IsA("ScreenGui") then
		gui = existing
	else
		local screen = Instance.new("ScreenGui")
		screen.Name = UI.ScreenName
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.DisplayOrder = 40
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screen.Parent = pg
		gui = screen
	end

	local root = gui :: ScreenGui
	local frame = root:FindFirstChild(UI.MessageBubbleName)
	if not (frame and frame:IsA("Frame")) then
		if frame then
			frame:Destroy()
		end
		local f = Instance.new("Frame")
		f.Name = UI.MessageBubbleName
		f.AnchorPoint = UI.AnchorPoint
		f.Position = UI.Position
		f.Size = UDim2.new(0, UI.MaxWidthPx, 0, 72)
		f.BackgroundColor3 = UI.Background
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Visible = false
		f.Parent = root

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, UI.CornerRadius)
		corner.Parent = f

		local stroke = Instance.new("UIStroke")
		stroke.Color = UI.Stroke
		stroke.Thickness = 1.5
		stroke.Transparency = 0.25
		stroke.Parent = f

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = f

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = f

		local msg = Instance.new("TextLabel")
		msg.Name = "Message"
		msg.BackgroundTransparency = 1
		msg.Size = UDim2.new(1, 0, 0, 28)
		msg.Font = UI.Font
		msg.TextSize = UI.FontSize
		msg.TextColor3 = UI.Text
		msg.TextWrapped = true
		msg.TextXAlignment = Enum.TextXAlignment.Center
		msg.Text = ""
		msg.LayoutOrder = 1
		msg.Parent = f

		local prog = Instance.new("TextLabel")
		prog.Name = "Progress"
		prog.BackgroundTransparency = 1
		prog.Size = UDim2.new(1, 0, 0, 18)
		prog.Font = Enum.Font.Gotham
		prog.TextSize = UI.ProgressFontSize
		prog.TextColor3 = UI.ProgressMuted
		prog.TextXAlignment = Enum.TextXAlignment.Center
		prog.Text = ""
		prog.LayoutOrder = 2
		prog.Visible = false
		prog.Parent = f

		local reward = Instance.new("TextLabel")
		reward.Name = "Reward"
		reward.BackgroundTransparency = 1
		reward.Size = UDim2.new(1, 0, 0, 20)
		reward.Font = UI.Font
		reward.TextSize = UI.ProgressFontSize
		reward.TextColor3 = UI.RewardGold
		reward.TextXAlignment = Enum.TextXAlignment.Center
		reward.Text = ""
		reward.LayoutOrder = 3
		reward.Visible = false
		reward.Parent = f

		bubble = f
		messageLabel = msg
		progressLabel = prog
		rewardLabel = reward
	else
		bubble = frame
		messageLabel = frame:FindFirstChild("Message") :: TextLabel?
		progressLabel = frame:FindFirstChild("Progress") :: TextLabel?
		rewardLabel = frame:FindFirstChild("Reward") :: TextLabel?
	end

	if not celebrateSound then
		local s = Instance.new("Sound")
		s.Name = "TutorialCelebrate"
		s.SoundId = UI.SoundId
		s.Volume = UI.SoundVolume
		s.Parent = SoundService
		celebrateSound = s
	end
end

local function tweenBubble(show: boolean, onDone: (() -> ())?)
	ensureGui()
	local f = bubble
	if not f then
		if onDone then
			onDone()
		end
		return
	end
	f.Visible = true
	local goalT = if show then UI.BackgroundTransparency else 1
	local goalScale = if show then 1 else 0.92
	local goalText = if show then 0 else 1

	if messageLabel then
		TweenService:Create(messageLabel, TweenInfo.new(if show then UI.TweenIn else UI.TweenOut), {
			TextTransparency = goalText,
		}):Play()
	end
	if progressLabel then
		TweenService:Create(progressLabel, TweenInfo.new(if show then UI.TweenIn else UI.TweenOut), {
			TextTransparency = goalText,
		}):Play()
	end

	local tw = TweenService:Create(f, TweenInfo.new(if show then UI.TweenIn else UI.TweenOut, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = goalT,
	})
	tw:Play()

	-- Micro scale via UIScale
	local scale = f:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = f
	end
	scale.Scale = if show then 0.94 else 1
	TweenService:Create(scale, TweenInfo.new(if show then UI.TweenIn else UI.TweenOut), {
		Scale = goalScale,
	}):Play()

	if onDone then
		tw.Completed:Once(function()
			if not show then
				f.Visible = false
			end
			onDone()
		end)
	elseif not show then
		tw.Completed:Once(function()
			f.Visible = false
		end)
	end
end

local function setProgressText(progress: number, progressMax: number)
	local pl = progressLabel
	if not pl then
		return
	end
	if progressMax > 1 then
		pl.Visible = true
		pl.Text = string.format("%d / %d", math.floor(progress), math.floor(progressMax))
	elseif progressMax == 1 then
		pl.Visible = false
		pl.Text = ""
	else
		pl.Visible = false
		pl.Text = ""
	end
end

local function showMessage(message: string, progress: number, progressMax: number)
	ensureGui()
	hideToken += 1
	if messageLabel then
		messageLabel.Text = message
		messageLabel.TextTransparency = 0
	end
	setProgressText(progress, progressMax)
	if rewardLabel then
		rewardLabel.Visible = false
		rewardLabel.Text = ""
	end
	tweenBubble(true, nil)
end

local function playCelebrate(rewardCoins: number)
	ensureGui()
	if celebrateSound then
		celebrateSound:Play()
	end
	if rewardLabel then
		if rewardCoins > 0 then
			rewardLabel.Text = ("+ %d coins"):format(rewardCoins)
			rewardLabel.Visible = true
			rewardLabel.TextTransparency = 0
		else
			rewardLabel.Text = "✓"
			rewardLabel.Visible = true
			rewardLabel.TextTransparency = 0
		end
	end
	if bubble then
		local stroke = bubble:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = UI.RewardGold
			task.delay(UI.CelebrateDuration, function()
				if stroke.Parent then
					stroke.Color = UI.Stroke
				end
			end)
		end
	end
end

local function hideAll()
	hideToken += 1
	local token = hideToken
	tweenBubble(false, function()
		if token ~= hideToken then
			return
		end
	end)
	if messageLabel then
		messageLabel.Text = ""
	end
	if rewardLabel then
		rewardLabel.Visible = false
	end
end

local function clearGuideVisuals()
	if guideHighlight then
		guideHighlight:Destroy()
		guideHighlight = nil
	end
	if guideBillboard then
		guideBillboard:Destroy()
		guideBillboard = nil
	end
	if guideBeam then
		guideBeam:Destroy()
		guideBeam = nil
	end
	if guideAtt0 then
		guideAtt0:Destroy()
		guideAtt0 = nil
	end
	if guideAtt1 then
		guideAtt1:Destroy()
		guideAtt1 = nil
	end
	guideTarget = nil
end

local function stopGuide()
	guideActive = false
	if guideConn then
		guideConn:Disconnect()
		guideConn = nil
	end
	clearGuideVisuals()
end

local function findNearestDrop(toolId: string): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	local origin = if root then root.Position else Vector3.zero

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") then
			local tid = inst:GetAttribute("ToolId")
			if tid == toolId then
				local d = (inst.Position - origin).Magnitude
				if d < bestDist then
					bestDist = d
					best = inst
				end
			end
		end
	end
	return best
end

local function attachGuideTo(target: BasePart)
	if guideTarget == target and guideHighlight and guideHighlight.Parent then
		return
	end
	clearGuideVisuals()
	guideTarget = target

	local hl = Instance.new("Highlight")
	hl.Name = "TutorialHammerHighlight"
	hl.Adornee = target
	hl.FillColor = Guide.HighlightFill
	hl.OutlineColor = Guide.HighlightOutline
	hl.FillTransparency = Guide.HighlightFillTransparency
	hl.OutlineTransparency = Guide.HighlightOutlineTransparency
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = target
	guideHighlight = hl

	local bb = Instance.new("BillboardGui")
	bb.Name = "TutorialHammerArrow"
	bb.AlwaysOnTop = true
	bb.Size = Guide.BillboardSize
	bb.StudsOffset = Guide.BillboardStudsOffset
	bb.MaxDistance = 0
	bb.Parent = target
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Guide.HighlightOutline
	label.TextStrokeTransparency = 0.3
	label.Text = Guide.ArrowGlyph
	label.Parent = bb
	guideBillboard = bb

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local a0 = Instance.new("Attachment")
		a0.Name = "TutorialGuideA0"
		a0.Position = Vector3.new(0, 1.5, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "TutorialGuideA1"
		a1.Position = Vector3.new(0, 1.2, 0)
		a1.Parent = target
		local beam = Instance.new("Beam")
		beam.Name = "TutorialGuideBeam"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Guide.BeamColor0, Guide.BeamColor1)
		beam.Width0 = Guide.BeamWidth0
		beam.Width1 = Guide.BeamWidth1
		beam.FaceCamera = true
		beam.LightEmission = 0.6
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 0.45),
		})
		beam.Parent = root
		guideAtt0 = a0
		guideAtt1 = a1
		guideBeam = beam
	end
end

local function updateGuide()
	if not guideActive then
		return
	end
	local now = os.clock()
	if now - lastScan < Guide.ScanInterval then
		-- Refresh beam attachments if character respawned.
		if guideTarget and guideTarget.Parent and guideBeam and not guideBeam.Parent then
			attachGuideTo(guideTarget)
		end
		return
	end
	lastScan = now

	-- Si le joueur a déjà le marteau en main / sac, stop guide côté client.
	local function hasTool(): boolean
		local function scan(container: Instance?): boolean
			if not container then
				return false
			end
			for _, c in ipairs(container:GetChildren()) do
				if c:IsA("Tool") and c:GetAttribute("ToolId") == guideToolId then
					return true
				end
			end
			return false
		end
		return scan(player:FindFirstChildOfClass("Backpack")) or scan(player.Character)
	end
	if hasTool() then
		stopGuide()
		return
	end

	if guideTarget and guideTarget.Parent then
		-- Mettre à jour A0 si personnage changé.
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (not guideAtt0 or guideAtt0.Parent ~= root) then
			attachGuideTo(guideTarget)
		end
		return
	end

	local nearest = findNearestDrop(guideToolId)
	if nearest then
		attachGuideTo(nearest)
	else
		clearGuideVisuals()
	end
end

local function startGuide(toolId: string?)
	guideToolId = if type(toolId) == "string" and toolId ~= "" then toolId else TutorialConfig.Ids.HammerToolId
	guideActive = true
	lastScan = 0
	if guideConn then
		guideConn:Disconnect()
	end
	guideConn = RunService.Heartbeat:Connect(updateGuide)
	updateGuide()
end

local function onTutorialState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.Kind
	if kind == TutorialConfig.PayloadKind.Done or payload.Completed == true then
		stopGuide()
		currentStepId = 0
		hideAll()
		return
	end

	local stepId = math.floor(tonumber(payload.StepId) or 0)
	local message = if type(payload.Message) == "string" then payload.Message else ""
	local progress = tonumber(payload.Progress) or 0
	local progressMax = tonumber(payload.ProgressMax) or 0
	local guide = payload.Guide == true

	if kind == TutorialConfig.PayloadKind.StepComplete then
		playCelebrate(math.floor(tonumber(payload.RewardCoins) or 0))
		stopGuide()
		-- La transition soft : on laisse le message + reward un instant, le Show suivant remplace.
		return
	end

	if kind == TutorialConfig.PayloadKind.Show or kind == TutorialConfig.PayloadKind.Progress then
		if stepId ~= currentStepId and kind == TutorialConfig.PayloadKind.Show then
			-- Transition : fade out puis in si l'étape change.
			local prev = currentStepId
			currentStepId = stepId
			if prev > 0 then
				tweenBubble(false, function()
					showMessage(message, progress, progressMax)
				end)
			else
				showMessage(message, progress, progressMax)
			end
		else
			currentStepId = stepId
			if messageLabel and message ~= "" then
				messageLabel.Text = message
			end
			setProgressText(progress, progressMax)
			if bubble and not bubble.Visible then
				tweenBubble(true, nil)
			end
		end

		if guide then
			startGuide(payload.GuideToolId)
		else
			stopGuide()
		end
	end
end

function TutorialController.Start()
	if not TutorialConfig.Enabled then
		return
	end
	ensureGui()
	Remotes.Event("TutorialState").OnClientEvent:Connect(onTutorialState)

	player.CharacterAdded:Connect(function()
		if guideActive then
			task.defer(function()
				lastScan = 0
				updateGuide()
			end)
		end
	end)
end

return TutorialController
