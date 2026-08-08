--!strict
-- Client : Challenges — DesktopDocked | ConsoleDocked | MobileDrawer.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)
local HudChrome = require(Shared.HudChrome)
local ChallengeLogic = require(Shared.ChallengeLogic)
local MiniEventConfig = require(Shared.MiniEventConfig)
local ChallengeUIConfig = require(Shared.ChallengeUIConfig)

local player = Players.LocalPlayer
local ChallengeController = {}

local BG = Color3.fromRGB(12, 18, 30)
local BG_CARD = Color3.fromRGB(22, 30, 46)
local BG_BUTTON = Color3.fromRGB(18, 24, 38)
local ACCENT = Color3.fromRGB(90, 220, 255)
local TEXT = Color3.fromRGB(235, 242, 255)
local MUTED = Color3.fromRGB(160, 180, 200)
local GOLD = Color3.fromRGB(255, 210, 70)
local OK_GREEN = Color3.fromRGB(90, 220, 140)

local gui: ScreenGui? = nil
local dock: Frame? = nil
local dockList: UIListLayout? = nil
local panel: Frame? = nil
local actionRail: Frame? = nil
local eventSlot: Frame? = nil
local scroll: ScrollingFrame? = nil
local countdownLabel: TextLabel? = nil
local closeBtn: TextButton? = nil
local dockedMinimized = false
local challengesBtn: TextButton? = nil
local eventBadge: Frame? = nil
local tabChallenges: TextButton? = nil
local tabLeaderboard: TextButton? = nil
local headerFrame: Frame? = nil
local tabsFrame: Frame? = nil
local hTitleLabel: TextLabel? = nil
local mobileOpenBtn: TextButton? = nil
local mobileBackdrop: TextButton? = nil
local mobileClaimDot: Frame? = nil
local mobileEventDot: Frame? = nil
local mobileEventTimer: TextLabel? = nil

local activeTab = "Challenges"
local state: any = nil
local miniPayload: any = nil
local miniHideAt = 0.0
local open = false -- synchro mobile UNIQUEMENT (open == isMobileDrawerOpen); ignoré en dock permanent
local layoutMode = HudChrome.LAYOUT_DESKTOP_DOCKED
local mobileDrawerState = "Closed" -- Closed | Opening | Open | Closing
local drawerOpenedAt = 0.0
local started = false
local boundActionColumn: Frame? = nil
local panelTween: Tween? = nil
local lastMobileNotifyKey = ""
local currentPanelW = HudChrome.CHALLENGES_BAR_WIDTH_DESKTOP
local viewportConn: RBXScriptConnection? = nil
local challengesBtnConn: RBXScriptConnection? = nil
local preferredInputConn: RBXScriptConnection? = nil
local dataPhase: string = "Loading" -- Loading | Ready | Empty | Error
local dataErrorMessage = ""
local lastGamepadFocusAt = 0.0
local layoutRevision = 0
local lastLoggedLayoutMode = ""

local PANEL_W = HudChrome.CHALLENGES_BAR_WIDTH_DESKTOP or 348


local function isMobileDrawer(): boolean
	return layoutMode == HudChrome.LAYOUT_MOBILE_DRAWER
end

local function isPermanentDock(): boolean
	return HudChrome.IsPermanentDockedMode(layoutMode)
end

local function isConsoleDocked(): boolean
	return layoutMode == HudChrome.LAYOUT_CONSOLE_DOCKED
end

-- Drawer conceptuel uniquement en MobileDrawer (jamais partagé avec Console/Desktop).
local function isMobileDrawerOpen(): boolean
	return mobileDrawerState == "Open" or mobileDrawerState == "Opening"
end

local function debugLog(step: string, detail: string?)
	if ChallengeUIConfig.DebugRuntime ~= true then
		return
	end
	if detail and detail ~= "" then
		print("[ChallengeUI]", step, detail)
	else
		print("[ChallengeUI]", step)
	end
end

local function logChallengeStep(step: string, detail: string?)
	if ChallengeUIConfig.DebugRuntime ~= true then
		return
	end
	if detail and detail ~= "" then
		print("[ChallengeUI]", step, detail)
	else
		print("[ChallengeUI]", step)
	end
end

local function logRuntimeError(context: string, err: any, instancePath: string?)
	local path = instancePath or ""
	warn(string.format("[ChallengeUI] ERROR step=%s err=%s path=%s", context, tostring(err), path))
	warn(debug.traceback(nil, 2))
end

local function readPreferredInputName(): string?
	local ok, value = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if not ok or value == nil then
		return nil
	end
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	return tostring(value)
end

local function collectLayoutInputs()
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(0, 0)
	return vp, {
		touchEnabled = UserInputService.TouchEnabled,
		gamepadEnabled = UserInputService.GamepadEnabled,
		keyboardEnabled = UserInputService.KeyboardEnabled,
		mouseEnabled = UserInputService.MouseEnabled,
		preferredInput = readPreferredInputName(),
	}
end

local function resolveLayoutModeForViewport(vp: Vector2): string
	return HudChrome.ResolveLayoutMode(vp.X, vp.Y, {
		touchEnabled = UserInputService.TouchEnabled,
		gamepadEnabled = UserInputService.GamepadEnabled,
		keyboardEnabled = UserInputService.KeyboardEnabled,
		mouseEnabled = UserInputService.MouseEnabled,
		preferredInput = readPreferredInputName(),
	})
end

local function stripUiScale(inst: Instance?)
	if not inst then
		return
	end
	local s = inst:FindFirstChildOfClass("UIScale")
	if s and s:IsA("UIScale") then
		s.Scale = 1
	end
end

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1.25
	s.Transparency = transparency or 0.15
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function labelOf(key: string, fallback: string): string
	local v = (L10n :: any)[key]
	if type(v) == "string" and v ~= "" then
		return v
	end
	return fallback
end

local function eventDisplayName(eventType: string): string
	if eventType == "GoldenWave" then
		return labelOf("MiniEventGoldenWave", "GOLDEN WAVE")
	elseif eventType == "ColorRush" then
		return labelOf("MiniEventColorRush", "COLOR RUSH")
	elseif eventType == "GiantBubble" then
		return labelOf("MiniEventGiantBubble", "GIANT BUBBLE")
	end
	return eventType
end

local function eventDescLine(eventType: string, stateName: string, objective: any?): string
	if stateName == "Countdown" then
		if eventType == "GoldenWave" then
			return labelOf("MiniEventGoldenWaveDesc", "Golden bubbles are appearing!")
		elseif eventType == "ColorRush" then
			return labelOf("MiniEventColorRushDesc", "Pop the highlighted color!")
		elseif eventType == "GiantBubble" then
			return labelOf("MiniEventGiantBubbleDesc", "Pop the giant bubble together!")
		end
	end
	if eventType == "GoldenWave" then
		local mult = if objective and objective.multiplier
			then objective.multiplier
			else MiniEventConfig.Events.GoldenWave.SellMultiplier
		return labelOf("MiniEventGoldenWaveActive", "Golden bubbles worth x%d"):format(mult)
	elseif eventType == "ColorRush" then
		local mult = if objective and objective.multiplier
			then objective.multiplier
			else MiniEventConfig.Events.ColorRush.SellMultiplier
		local name = if objective and objective.colorName then objective.colorName else "Color"
		return labelOf("MiniEventColorRushActive", "Target: %s — worth x%d"):format(name, mult)
	elseif eventType == "GiantBubble" then
		return labelOf("MiniEventGiantBubbleDesc", "Pop the giant bubble together!")
	end
	return ""
end

local function challengeTitle(ch: any): string
	return labelOf(ch.TitleKey, ch.TitleKey or "Challenge")
end

local function challengeDesc(ch: any): string
	local tmpl = labelOf(ch.DescKey, "Progress: {progress}/{target}")
	return (tmpl:gsub("{progress}", tostring(ch.Progress or 0)):gsub("{target}", tostring(ch.Target or 0)))
end

local function setButtonActive(btn: GuiButton?, isActive: boolean)
	if not btn then
		return
	end
	local border = btn:FindFirstChildOfClass("UIStroke")
	if isActive then
		btn.BackgroundColor3 = Color3.fromRGB(28, 42, 62)
		if border then
			border.Color = ACCENT
			border.Thickness = 2
			border.Transparency = 0.05
		end
	else
		btn.BackgroundColor3 = BG_BUTTON
		if border then
			border.Color = ACCENT
			border.Thickness = 1.4
			border.Transparency = 0.3
		end
	end
end

local function clearChildren(parent: Instance)
	for _, c in ipairs(parent:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and not c:IsA("UISizeConstraint") then
			c:Destroy()
		end
	end
end

local function makeProgressBar(parent: Instance, ratio: number, z: number): Frame
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(30, 38, 54)
	track.BorderSizePixel = 0
	track.ZIndex = z
	track.Parent = parent
	corner(track, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.ZIndex = z + 1
	fill.Parent = track
	corner(fill, 4)
	return track
end

local function flashPanel()
	if not panel then
		return
	end
	local s = panel:FindFirstChildOfClass("UIStroke")
	if not s then
		return
	end
	TweenService:Create(s, TweenInfo.new(0.12), { Transparency = 0, Thickness = 2.2 }):Play()
	task.delay(0.25, function()
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(0.3), { Transparency = 0.12, Thickness = 1.5 }):Play()
		end
	end)
end

local function cancelPanelTween()
	if panelTween then
		panelTween:Cancel()
		panelTween = nil
	end
end

local function logChallengeButtonStudio(msg: string, detail: string?)
	if not RunService:IsStudio() then
		return
	end
	if detail and detail ~= "" then
		print("[ChallengeButton]", msg, detail)
	else
		print("[ChallengeButton]", msg)
	end
end

local function logDockedPanelStateStudio()
	if not RunService:IsStudio() then
		return
	end
	if gui then
		print("[ChallengeButton] ScreenGui Enabled:", gui.Enabled)
	end
	if dock then
		print("[ChallengeButton] Dock Class:", dock.ClassName)
		print("[ChallengeButton] Dock Visible:", dock.Visible)
		print("[ChallengeButton] Dock Position:", dock.AbsolutePosition)
		print("[ChallengeButton] Dock Size:", dock.AbsoluteSize)
	else
		print("[ChallengeButton] Dock: nil")
	end
	if panel then
		print("[ChallengeButton] Panel Visible:", panel.Visible)
		print("[ChallengeButton] Panel AbsolutePosition:", panel.AbsolutePosition)
		print("[ChallengeButton] Panel AbsoluteSize:", panel.AbsoluteSize)
	else
		print("[ChallengeButton] Panel: nil")
	end
end

-- Déclarations forward pour handlers du bouton (définis après setMobileDrawerOpen / layouts).
local showDockedChallengesPanel: () -> ()
local handleChallengeButtonActivated: () -> ()
local bindChallengeButton: (GuiButton) -> ()


local function hasClaimableChallenge(): boolean
	if type(state) ~= "table" then
		return false
	end
	local function ready(ch: any): boolean
		if type(ch) ~= "table" then
			return false
		end
		local target = math.max(1, math.floor(tonumber(ch.Target) or 1))
		local progress = math.max(0, math.floor(tonumber(ch.Progress) or 0))
		local status = ChallengeLogic.ChallengeStatus({
			Id = tostring(ch.Id or ""),
			Metric = tostring(ch.Metric or ""),
			Target = target,
			Progress = progress,
			Completed = ch.Completed == true or progress >= target,
			Claimed = ch.Claimed == true,
			Slot = tostring(ch.Slot or "Easy"),
			TitleKey = tostring(ch.TitleKey or ""),
			DescKey = tostring(ch.DescKey or ""),
			RewardType = tostring(ch.RewardType or "SellBonus"),
			RewardAmount = math.floor(tonumber(ch.RewardAmount) or 0),
		})
		return status == "ReadyToClaim"
	end
	if type(state.Daily) == "table" then
		for _, ch in ipairs(state.Daily) do
			if ready(ch) then
				return true
			end
		end
	end
	if type(state.Weekly) == "table" and ready(state.Weekly) then
		return true
	end
	return false
end

local function miniEventActive(): boolean
	if type(miniPayload) ~= "table" then
		return false
	end
	local st = miniPayload.state
	return st == "Countdown" or st == "Active"
end

local function refreshMobileOpenBadges()
	if not isMobileDrawer() then
		if mobileClaimDot then
			mobileClaimDot.Visible = false
		end
		if mobileEventDot then
			mobileEventDot.Visible = false
		end
		if mobileEventTimer then
			mobileEventTimer.Visible = false
		end
		return
	end
	local hostBtn: GuiObject? = challengesBtn
	if not hostBtn then
		return
	end
	if mobileClaimDot then
		if mobileClaimDot.Parent ~= hostBtn then
			mobileClaimDot.Parent = hostBtn
			mobileClaimDot.Position = UDim2.new(1, -4, 0, -2)
			mobileClaimDot.ZIndex = hostBtn.ZIndex + 2
		end
		mobileClaimDot.Visible = hasClaimableChallenge()
	end
	local active = miniEventActive()
	if mobileEventDot then
		if mobileEventDot.Parent ~= hostBtn then
			mobileEventDot.Parent = hostBtn
			mobileEventDot.Position = UDim2.new(1, -4, 0, -2)
			mobileEventDot.ZIndex = hostBtn.ZIndex + 2
		end
		mobileEventDot.Visible = active and not hasClaimableChallenge()
	end
	if mobileEventTimer then
		if mobileEventTimer.Parent ~= hostBtn then
			mobileEventTimer.Parent = hostBtn
			mobileEventTimer.ZIndex = hostBtn.ZIndex + 2
		end
		mobileEventTimer.Visible = active
		if active and type(miniPayload) == "table" then
			local clock = Workspace:GetServerTimeNow()
			local remaining = 0
			if miniPayload.state == "Countdown" then
				remaining = math.max(0, (tonumber(miniPayload.startTime) or 0) - clock)
			else
				remaining = math.max(0, (tonumber(miniPayload.endTime) or 0) - clock)
			end
			mobileEventTimer.Text = tostring(math.ceil(remaining)) .. "s"
		else
			mobileEventTimer.Text = ""
		end
	end
end

--------------------------------------------------------------------
-- Active mini-event slot (top of bar / drawer)
--------------------------------------------------------------------
local function rebuildEventSlot()
	if not eventSlot then
		return
	end
	clearChildren(eventSlot)

	local payload = miniPayload
	local show = false
	if type(payload) == "table" then
		local st = payload.state
		if st == "Countdown" or st == "Active" then
			show = true
		elseif st == "Ended" and miniHideAt > 0 and os.clock() < miniHideAt then
			show = true
		end
	end
	-- Sur mobile fermé : pas de carte (uniquement badge sur le bouton d'ouverture).
	if isMobileDrawer() and not isMobileDrawerOpen() then
		show = false
	end
	eventSlot.Visible = show
	if not show then
		eventSlot.Size = UDim2.new(1, 0, 0, 0)
		refreshMobileOpenBadges()
		return
	end

	if eventBadge then
		eventBadge.Visible = false
	end

	local compact = isMobileDrawer()
	eventSlot.Size = UDim2.new(1, 0, 0, 0)
	eventSlot.AutomaticSize = Enum.AutomaticSize.Y

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, if compact then 6 else 8)
	pad.PaddingBottom = UDim.new(0, if compact then 6 else 8)
	pad.PaddingLeft = UDim.new(0, if compact then 8 else 10)
	pad.PaddingRight = UDim.new(0, if compact then 8 else 10)
	pad.Parent = eventSlot

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, if compact then 3 else 4)
	list.Parent = eventSlot

	local st = payload.state
	local et = tostring(payload.eventType or "")
	local clock = Workspace:GetServerTimeNow()
	local remaining = 0
	if st == "Countdown" then
		remaining = math.max(0, (tonumber(payload.startTime) or 0) - clock)
	elseif st == "Active" then
		remaining = math.max(0, (tonumber(payload.endTime) or 0) - clock)
	end

	local card = Instance.new("Frame")
	card.Name = "ActiveEventCard"
	card.BackgroundColor3 = Color3.fromRGB(28, 40, 58)
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = 1
	card.ZIndex = 22
	card.Parent = eventSlot
	corner(card, if compact then 8 else 10)
	stroke(card, GOLD, 1.3, 0.2)

	local cPad = Instance.new("UIPadding")
	cPad.PaddingTop = UDim.new(0, if compact then 6 else 8)
	cPad.PaddingBottom = UDim.new(0, if compact then 7 else 10)
	cPad.PaddingLeft = UDim.new(0, if compact then 8 else 10)
	cPad.PaddingRight = UDim.new(0, if compact then 8 else 10)
	cPad.Parent = card

	local cList = Instance.new("UIListLayout")
	cList.SortOrder = Enum.SortOrder.LayoutOrder
	cList.Padding = UDim.new(0, if compact then 3 else 4)
	cList.Parent = card

	local topRow = Instance.new("Frame")
	topRow.BackgroundTransparency = 1
	topRow.Size = UDim2.new(1, 0, 0, if compact then 18 else 20)
	topRow.LayoutOrder = 1
	topRow.ZIndex = 23
	topRow.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "EventTitle"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -48, 1, 0)
	title.Font = Enum.Font.GothamBold
	title.TextSize = if compact then 13 else 14
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 24
	title.Parent = topRow
	L10nUtil.markNoLocalize(title)

	if st == "Ended" then
		title.Text = if payload.outcome == "Failed"
			then labelOf("MiniEventFailed", "EVENT FAILED!")
			else labelOf("MiniEventComplete", "EVENT COMPLETE!")
	elseif st == "Countdown" then
		if et == "GoldenWave" then
			title.Text = labelOf("MiniEventGoldenWaveIn", "GOLDEN WAVE IN %d"):format(math.ceil(remaining))
		elseif et == "ColorRush" then
			title.Text = labelOf("MiniEventColorRushIn", "COLOR RUSH IN %d"):format(math.ceil(remaining))
		else
			title.Text = labelOf("MiniEventGiantBubbleIn", "GIANT BUBBLE IN %d"):format(math.ceil(remaining))
		end
	else
		title.Text = eventDisplayName(et)
	end

	local timer = Instance.new("TextLabel")
	timer.Name = "EventTimer"
	timer.BackgroundTransparency = 1
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, 0, 0, 0)
	timer.Size = UDim2.fromOffset(44, 20)
	timer.Font = Enum.Font.GothamBold
	timer.TextSize = if compact then 14 else 15
	timer.TextColor3 = ACCENT
	timer.TextXAlignment = Enum.TextXAlignment.Right
	timer.Text = if st == "Ended" then "" else tostring(math.ceil(remaining)) .. "s"
	timer.ZIndex = 24
	timer.Parent = topRow
	L10nUtil.markNoLocalize(timer)

	local desc = Instance.new("TextLabel")
	desc.Name = "EventDesc"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, 0, 0, 0)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.Font = Enum.Font.Gotham
	desc.TextSize = if compact then 11 else 12
	desc.TextColor3 = MUTED
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextWrapped = true
	desc.LayoutOrder = 2
	desc.ZIndex = 23
	desc.Parent = card
	L10nUtil.markNoLocalize(desc)

	if st == "Ended" then
		if payload.rewardHint and type(payload.rewardHint.sellBonus) == "number" then
			desc.Text = labelOf("MiniEventSellBonusFmt", "Sell bonus earned: +%d"):format(payload.rewardHint.sellBonus)
		else
			desc.Text = ""
		end
	else
		desc.Text = eventDescLine(et, st, payload.objective)
	end

	if st == "Active" and et == "GiantBubble" and type(payload.progress) == "table" then
		local pr = payload.progress
		local cur = tonumber(pr.current) or 0
		local req = math.max(1, tonumber(pr.required) or 1)
		local personal = tonumber(pr.personal) or 0
		local progText = Instance.new("TextLabel")
		progText.BackgroundTransparency = 1
		progText.Size = UDim2.new(1, 0, 0, 16)
		progText.Font = Enum.Font.GothamMedium
		progText.TextSize = if compact then 11 else 12
		progText.TextColor3 = TEXT
		progText.TextXAlignment = Enum.TextXAlignment.Left
		progText.LayoutOrder = 3
		progText.ZIndex = 23
		progText.Text = labelOf("MiniEventGiantProgress", "%d / %d  ·  Your contribution: %d"):format(cur, req, personal)
		progText.Parent = card
		L10nUtil.markNoLocalize(progText)

		local barHost = Instance.new("Frame")
		barHost.BackgroundTransparency = 1
		barHost.Size = UDim2.new(1, 0, 0, 10)
		barHost.LayoutOrder = 4
		barHost.ZIndex = 23
		barHost.Parent = card
		makeProgressBar(barHost, cur / req, 23)
	end
	refreshMobileOpenBadges()
end

--------------------------------------------------------------------
-- Body rebuild
--------------------------------------------------------------------
local function showBodyStatus(message: string)
	if not scroll then
		return
	end
	clearChildren(scroll)
	local msg = Instance.new("TextLabel")
	msg.Name = "StatusMessage"
	msg.BackgroundTransparency = 1
	msg.Size = UDim2.new(1, -8, 0, 80)
	msg.Position = UDim2.fromOffset(4, 12)
	msg.Font = Enum.Font.GothamMedium
	msg.TextSize = 14
	msg.TextColor3 = MUTED
	msg.TextWrapped = true
	msg.TextXAlignment = Enum.TextXAlignment.Left
	msg.TextYAlignment = Enum.TextYAlignment.Top
	msg.Text = message
	msg.ZIndex = 22
	msg.LayoutOrder = 1
	msg.Parent = scroll
	L10nUtil.markNoLocalize(msg)
end

local function wireSelectable(btn: GuiButton)
	btn.Selectable = true
	btn.Active = true
end

local function rebuildBody()
	if not scroll then
		return
	end

	-- Panneau toujours visible même sans données (loading / empty / error).
	if dataPhase == "Loading" or (state == nil and dataPhase ~= "Error") then
		showBodyStatus(labelOf("ChallengesLoading", "Loading challenges..."))
		return
	end
	if dataPhase == "Error" then
		showBodyStatus(dataErrorMessage ~= "" and dataErrorMessage or labelOf("ChallengesError", "Could not load challenges. Try again later."))
		return
	end
	if dataPhase == "Empty" or state == nil then
		showBodyStatus(labelOf("ChallengesEmpty", "No challenges available right now."))
		return
	end

	clearChildren(scroll)

	local compact = isMobileDrawer()
	local cardPad = if compact then (HudChrome.CHALLENGES_MOBILE_CARD_PADDING or 11) else 10
	local listGap = if compact then (HudChrome.CHALLENGES_MOBILE_CARD_GAP or 8) else 8

	local pad = scroll:FindFirstChildOfClass("UIPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Parent = scroll
	end
	pad.PaddingTop = UDim.new(0, if compact then 2 else 4)
	pad.PaddingBottom = UDim.new(0, if compact then 28 else 14)
	pad.PaddingLeft = UDim.new(0, if compact then 8 else 10)
	pad.PaddingRight = UDim.new(0, if compact then 8 else 10)

	local list = scroll:FindFirstChildOfClass("UIListLayout")
	if not list then
		list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = scroll
	end
	list.Padding = UDim.new(0, listGap)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	if activeTab == "Challenges" then
		local featH = if compact then 58 else 72
		local feat = Instance.new("Frame")
		feat.LayoutOrder = nextOrder()
		feat.Size = UDim2.new(1, 0, 0, featH)
		feat.BackgroundColor3 = BG_CARD
		feat.BorderSizePixel = 0
		feat.ZIndex = 21
		feat.Parent = scroll
		corner(feat, if compact then 8 else 10)
		stroke(feat, GOLD, 1.1, 0.3)

		local fTitle = Instance.new("TextLabel")
		fTitle.BackgroundTransparency = 1
		fTitle.Position = UDim2.fromOffset(cardPad, if compact then 6 else 8)
		fTitle.Size = UDim2.new(1, -cardPad * 2, 0, 14)
		fTitle.Font = Enum.Font.GothamBold
		fTitle.TextSize = if compact then 10 else 11
		fTitle.TextColor3 = GOLD
		fTitle.TextXAlignment = Enum.TextXAlignment.Left
		fTitle.Text = labelOf("EventOfTheDay", "EVENT OF THE DAY")
		fTitle.ZIndex = 22
		fTitle.Parent = feat
		L10nUtil.markNoLocalize(fTitle)

		local fName = Instance.new("TextLabel")
		fName.BackgroundTransparency = 1
		fName.Position = UDim2.fromOffset(cardPad, if compact then 22 else 26)
		fName.Size = UDim2.new(1, -cardPad * 2, 0, if compact then 18 else 20)
		fName.Font = Enum.Font.GothamBold
		fName.TextSize = if compact then 14 else 16
		fName.TextColor3 = TEXT
		fName.TextXAlignment = Enum.TextXAlignment.Left
		fName.Text = eventDisplayName(tostring(state.FeaturedEventType or ""))
		fName.ZIndex = 22
		fName.Parent = feat
		L10nUtil.markNoLocalize(fName)

		local fDesc = Instance.new("TextLabel")
		fDesc.BackgroundTransparency = 1
		fDesc.Position = UDim2.fromOffset(cardPad, if compact then 40 else 48)
		fDesc.Size = UDim2.new(1, -cardPad * 2, 0, 14)
		fDesc.Font = Enum.Font.Gotham
		fDesc.TextSize = if compact then 11 else 12
		fDesc.TextColor3 = MUTED
		fDesc.TextXAlignment = Enum.TextXAlignment.Left
		fDesc.Text = labelOf("FeaturedToday", "Featured today")
		fDesc.ZIndex = 22
		fDesc.Parent = feat
		L10nUtil.markNoLocalize(fDesc)

		local function section(text: string)
			local s = Instance.new("TextLabel")
			s.BackgroundTransparency = 1
			s.LayoutOrder = nextOrder()
			s.Size = UDim2.new(1, 0, 0, if compact then 14 else 16)
			s.Font = Enum.Font.GothamBold
			s.TextSize = if compact then 10 else 11
			s.TextColor3 = ACCENT
			s.TextXAlignment = Enum.TextXAlignment.Left
			s.Text = text
			s.ZIndex = 21
			s.Parent = scroll
			L10nUtil.markNoLocalize(s)
		end

		section(labelOf("DailyChallenges", "DAILY CHALLENGES"))

		local function addChallengeCard(ch: any)
			if ChallengeLogic.IsChallengeVisibleInList(ch) == false then
				return
			end
			local target = math.max(1, math.floor(tonumber(ch.Target) or 1))
			local progress = math.min(target, math.max(0, math.floor(tonumber(ch.Progress) or 0)))
			local status = ChallengeLogic.ChallengeStatus({
				Id = tostring(ch.Id or ""),
				Metric = tostring(ch.Metric or ""),
				Target = target,
				Progress = progress,
				Completed = ch.Completed == true or progress >= target,
				Claimed = ch.Claimed == true,
				Slot = tostring(ch.Slot or "Easy"),
				TitleKey = tostring(ch.TitleKey or ""),
				DescKey = tostring(ch.DescKey or ""),
				RewardType = tostring(ch.RewardType or "SellBonus"),
				RewardAmount = math.floor(tonumber(ch.RewardAmount) or 0),
			})
			local isClaimed = status == "Claimed"
			local isReady = status == "ReadyToClaim"
			local isDone = isClaimed or isReady
			local ratio = progress / target

			local claimH = if compact then (HudChrome.CHALLENGES_MOBILE_CLAIM_HEIGHT or 44) else 26
			local rowH: number
			if compact then
				rowH = if isReady then 118 else 96
			else
				rowH = if isReady then 122 else 110
			end
			local row = Instance.new("Frame")
			row.Name = "Ch_" .. tostring(ch.Id)
			row.LayoutOrder = nextOrder()
			row.Size = UDim2.new(1, 0, 0, rowH)
			row.BackgroundColor3 = if isClaimed
				then Color3.fromRGB(18, 24, 36)
				elseif isReady then Color3.fromRGB(20, 38, 34)
				else BG_CARD
			row.BackgroundTransparency = if isClaimed then 0.08 else 0
			row.BorderSizePixel = 0
			row.Visible = true
			row.ZIndex = 21
			row.Parent = scroll
			corner(row, if compact then 8 else 10)
			local strokeColor = if isReady
				then OK_GREEN
				elseif isClaimed then Color3.fromRGB(70, 90, 110)
				else Color3.fromRGB(50, 80, 110)
			stroke(row, strokeColor, if isReady then 1.5 else 1, if isClaimed then 0.35 else 0.2)

			local titleSz = if compact then 16 else 13
			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(cardPad, if compact then 8 else 8)
			title.Size = UDim2.new(1, -cardPad * 2, 0, if compact then 18 else 16)
			title.Font = Enum.Font.GothamBold
			title.TextSize = titleSz
			title.TextColor3 = if isClaimed then Color3.fromRGB(200, 210, 220) else TEXT
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.Text = challengeTitle(ch)
			title.ZIndex = 22
			title.Parent = row
			L10nUtil.markNoLocalize(title)

			local progY = if compact then 28 else 26
			local prog = Instance.new("TextLabel")
			prog.BackgroundTransparency = 1
			prog.Position = UDim2.fromOffset(cardPad, progY)
			prog.Size = UDim2.new(0.45, 0, 0, 14)
			prog.Font = Enum.Font.GothamMedium
			prog.TextSize = if compact then 13 else 12
			prog.TextColor3 = if isDone then OK_GREEN else MUTED
			prog.TextXAlignment = Enum.TextXAlignment.Left
			prog.Text = string.format("%s / %s", HudChrome.Comma(progress), HudChrome.Comma(target))
			prog.ZIndex = 22
			prog.Parent = row
			L10nUtil.markNoLocalize(prog)

			local statusLbl = Instance.new("TextLabel")
			statusLbl.BackgroundTransparency = 1
			statusLbl.AnchorPoint = Vector2.new(1, 0)
			statusLbl.Position = UDim2.new(1, -cardPad, 0, progY)
			statusLbl.Size = UDim2.fromOffset(130, 14)
			statusLbl.Font = Enum.Font.GothamBold
			statusLbl.TextSize = if compact then 12 else 11
			statusLbl.TextXAlignment = Enum.TextXAlignment.Right
			statusLbl.ZIndex = 22
			statusLbl.Parent = row
			L10nUtil.markNoLocalize(statusLbl)
			if isClaimed then
				statusLbl.Text = labelOf("Claimed", "CLAIMED")
				statusLbl.TextColor3 = Color3.fromRGB(140, 165, 185)
			elseif isReady then
				statusLbl.Text = labelOf("ReadyToClaim", "READY TO CLAIM")
				statusLbl.TextColor3 = OK_GREEN
			else
				statusLbl.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5))
				statusLbl.TextColor3 = MUTED
			end

			local descY = if compact then 44 else 42
			local desc = Instance.new("TextLabel")
			desc.BackgroundTransparency = 1
			desc.Position = UDim2.fromOffset(cardPad, descY)
			desc.Size = UDim2.new(1, -cardPad * 2, 0, if compact then 16 else 16)
			desc.Font = Enum.Font.Gotham
			desc.TextSize = if compact then 12 else 11
			desc.TextColor3 = MUTED
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextTruncate = Enum.TextTruncate.AtEnd
			desc.TextWrapped = compact
			desc.MaxVisibleGraphemes = if compact then -1 else -1
			desc.Text = challengeDesc({
				DescKey = ch.DescKey,
				Progress = progress,
				Target = target,
			})
			desc.ZIndex = 22
			desc.Parent = row
			L10nUtil.markNoLocalize(desc)

			local barY = if compact then 64 else 62
			local barHost = Instance.new("Frame")
			barHost.BackgroundTransparency = 1
			barHost.Position = UDim2.fromOffset(cardPad, barY)
			barHost.Size = UDim2.new(1, -cardPad * 2, 0, 8)
			barHost.ZIndex = 22
			barHost.Parent = row
			local track = makeProgressBar(barHost, ratio, 22)
			local fill = track:FindFirstChild("Fill")
			if fill and fill:IsA("Frame") then
				if isClaimed then
					fill.BackgroundColor3 = Color3.fromRGB(90, 130, 150)
				elseif isReady then
					fill.BackgroundColor3 = OK_GREEN
				else
					fill.BackgroundColor3 = ACCENT
				end
			end

			local rewardY = if compact then 74 else 76
			local reward = Instance.new("TextLabel")
			reward.BackgroundTransparency = 1
			reward.Position = UDim2.fromOffset(cardPad, rewardY)
			reward.Size = UDim2.new(if isReady and compact then 0.5 else 0.55, 0, 0, if compact then 18 else 26)
			reward.Font = Enum.Font.GothamMedium
			reward.TextSize = if compact then 13 else 11
			reward.TextColor3 = GOLD
			reward.TextXAlignment = Enum.TextXAlignment.Left
			reward.TextYAlignment = Enum.TextYAlignment.Center
			reward.Text = string.format(
				"%s: +%s %s",
				labelOf("Reward", "Reward"),
				HudChrome.Comma(ch.RewardAmount or 0),
				labelOf("SellBonusShort", "sell bonus")
			)
			reward.ZIndex = 22
			reward.Parent = row
			L10nUtil.markNoLocalize(reward)

			if isReady then
				local claim = Instance.new("TextButton")
				if compact then
					claim.Size = UDim2.fromOffset(88, claimH)
					claim.Position = UDim2.new(1, -(88 + cardPad), 1, -(claimH + 6))
				else
					claim.Size = UDim2.fromOffset(72, 26)
					claim.Position = UDim2.new(1, -82, 1, -34)
				end
				claim.BackgroundColor3 = Color3.fromRGB(36, 110, 82)
				claim.TextColor3 = Color3.new(1, 1, 1)
				claim.Font = Enum.Font.GothamBold
				claim.TextSize = if compact then 13 else 12
				claim.BorderSizePixel = 0
				claim.AutoButtonColor = true
				claim.Visible = true
				claim.ZIndex = 23
				claim.Text = labelOf("Claim", "CLAIM")
				claim.Parent = row
				corner(claim, 8)
				stroke(claim, OK_GREEN, 1.1, 0.2)
				L10nUtil.markNoLocalize(claim)
				wireSelectable(claim)
				claim.Activated:Connect(function()
					Remotes.Event("ChallengeClaim"):FireServer(ch.Id)
				end)
			elseif isClaimed then
				local done = Instance.new("TextLabel")
				done.BackgroundTransparency = 1
				done.Size = UDim2.fromOffset(72, 26)
				done.Position = UDim2.new(1, -82, 1, -34)
				done.Font = Enum.Font.GothamBold
				done.TextSize = 11
				done.TextColor3 = Color3.fromRGB(140, 165, 185)
				done.TextXAlignment = Enum.TextXAlignment.Right
				done.TextYAlignment = Enum.TextYAlignment.Center
				done.Text = labelOf("Claimed", "CLAIMED")
				done.ZIndex = 22
				done.Parent = row
				L10nUtil.markNoLocalize(done)
			end
		end

		if type(state.Daily) == "table" then
			local dailyList: { any } = {}
			for _, ch in ipairs(state.Daily) do
				table.insert(dailyList, ch)
			end
			local typed: { ChallengeLogic.ChallengeInstance } = {}
			for _, ch in ipairs(dailyList) do
				table.insert(typed, {
					Id = tostring(ch.Id or ""),
					Metric = tostring(ch.Metric or "PopBubbles"),
					Target = math.max(1, math.floor(tonumber(ch.Target) or 1)),
					Progress = math.max(0, math.floor(tonumber(ch.Progress) or 0)),
					Completed = ch.Completed == true,
					Claimed = ch.Claimed == true,
					Slot = tostring(ch.Slot or "Easy"),
					TitleKey = tostring(ch.TitleKey or ""),
					DescKey = tostring(ch.DescKey or ""),
					RewardType = tostring(ch.RewardType or "SellBonus"),
					RewardAmount = math.floor(tonumber(ch.RewardAmount) or 0),
				})
			end
			local sorted = ChallengeLogic.SortChallengesForDisplay(typed)
			local byId: { [string]: any } = {}
			for _, ch in ipairs(dailyList) do
				byId[tostring(ch.Id)] = ch
			end
			for _, sortedCh in ipairs(sorted) do
				local original = byId[sortedCh.Id]
				if original then
					original.Completed = sortedCh.Completed or original.Completed
					original.Claimed = sortedCh.Claimed or original.Claimed
					original.Progress = math.max(tonumber(original.Progress) or 0, sortedCh.Progress)
					addChallengeCard(original)
				end
			end
			for _, ch in ipairs(dailyList) do
				local seen = false
				for _, s in ipairs(sorted) do
					if s.Id == tostring(ch.Id) then
						seen = true
						break
					end
				end
				if not seen then
					addChallengeCard(ch)
				end
			end
		end

		section(labelOf("WeeklyChallenge", "WEEKLY CHALLENGE"))
		if type(state.Weekly) == "table" then
			addChallengeCard(state.Weekly)
		end
	else
		local header = Instance.new("TextLabel")
		header.BackgroundTransparency = 1
		header.LayoutOrder = nextOrder()
		header.Size = UDim2.new(1, 0, 0, if compact then 18 else 20)
		header.Font = Enum.Font.GothamBold
		header.TextSize = if compact then 12 else 13
		header.TextColor3 = GOLD
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = labelOf("DailyBubbleChampions", "DAILY BUBBLE CHAMPIONS")
		header.ZIndex = 21
		header.Parent = scroll
		L10nUtil.markNoLocalize(header)

		local lb = state.Leaderboard
		local entries = if type(lb) == "table" and type(lb.Entries) == "table" then lb.Entries else {}
		if #entries == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.LayoutOrder = nextOrder()
			empty.Size = UDim2.new(1, 0, 0, 36)
			empty.Font = Enum.Font.Gotham
			empty.TextSize = 12
			empty.TextColor3 = MUTED
			empty.Text = labelOf("NoRankingsYet", "No rankings yet")
			empty.ZIndex = 21
			empty.Parent = scroll
			L10nUtil.markNoLocalize(empty)
		else
			for _, e in ipairs(entries) do
				local isMe = e.UserId == player.UserId
				local row = Instance.new("Frame")
				row.LayoutOrder = nextOrder()
				row.Size = UDim2.new(1, 0, 0, if compact then 28 else 32)
				row.BackgroundColor3 = if isMe then Color3.fromRGB(30, 48, 70) else BG_CARD
				row.BorderSizePixel = 0
				row.ZIndex = 21
				row.Parent = scroll
				corner(row, 8)
				if isMe then
					stroke(row, ACCENT, 1.1, 0.15)
				end

				local r = Instance.new("TextLabel")
				r.BackgroundTransparency = 1
				r.Position = UDim2.fromOffset(8, 0)
				r.Size = UDim2.new(0, 26, 1, 0)
				r.Font = Enum.Font.GothamBold
				r.TextSize = if compact then 11 else 12
				r.TextColor3 = if e.Rank <= 3 then GOLD else MUTED
				r.Text = tostring(e.Rank)
				r.ZIndex = 22
				r.Parent = row
				L10nUtil.markNoLocalize(r)

				local n = Instance.new("TextLabel")
				n.BackgroundTransparency = 1
				n.Position = UDim2.fromOffset(36, 0)
				n.Size = UDim2.new(1, -110, 1, 0)
				n.Font = Enum.Font.GothamMedium
				n.TextSize = if compact then 11 else 12
				n.TextColor3 = TEXT
				n.TextXAlignment = Enum.TextXAlignment.Left
				n.TextTruncate = Enum.TextTruncate.AtEnd
				n.Text = tostring(e.Name or "?")
				n.ZIndex = 22
				n.Parent = row
				L10nUtil.markNoLocalize(n)

				local p = Instance.new("TextLabel")
				p.BackgroundTransparency = 1
				p.AnchorPoint = Vector2.new(1, 0)
				p.Position = UDim2.new(1, -8, 0, 0)
				p.Size = UDim2.new(0, 64, 1, 0)
				p.Font = Enum.Font.GothamBold
				p.TextSize = if compact then 11 else 12
				p.TextColor3 = ACCENT
				p.TextXAlignment = Enum.TextXAlignment.Right
				p.Text = HudChrome.Comma(e.Pops or 0)
				p.ZIndex = 22
				p.Parent = row
				L10nUtil.markNoLocalize(p)
			end
		end

		local yours = Instance.new("TextLabel")
		yours.BackgroundTransparency = 1
		yours.LayoutOrder = nextOrder()
		yours.Size = UDim2.new(1, 0, 0, 40)
		yours.Font = Enum.Font.GothamMedium
		yours.TextSize = if compact then 11 else 12
		yours.TextColor3 = TEXT
		yours.TextXAlignment = Enum.TextXAlignment.Left
		yours.TextYAlignment = Enum.TextYAlignment.Top
		local pops = if type(lb) == "table" then tonumber(lb.YourPops) or state.DailyBubblePops or 0 else state.DailyBubblePops or 0
		local rank = if type(lb) == "table" then lb.YourRank else nil
		if type(rank) == "number" then
			yours.Text = string.format(
				"%s: %s\n%s: #%d",
				labelOf("YourPopsToday", "Your pops today"),
				HudChrome.Comma(pops),
				labelOf("YourRank", "Your rank"),
				rank
			)
		else
			yours.Text = string.format(
				"%s: %s",
				labelOf("YourPopsToday", "Your pops today"),
				HudChrome.Comma(pops)
			)
		end
		yours.ZIndex = 21
		yours.Parent = scroll
		L10nUtil.markNoLocalize(yours)
	end

	if tabChallenges and tabLeaderboard then
		setButtonActive(tabChallenges, activeTab == "Challenges")
		setButtonActive(tabLeaderboard, activeTab == "Leaderboard")
	end
	refreshMobileOpenBadges()
end

local function refreshCountdown()
	if not countdownLabel or not state then
		return
	end
	local serverNow = tonumber(state.ServerNow) or os.time()
	local elapsed = math.max(0, os.time() - serverNow)
	local rem = math.max(0, (tonumber(state.SecondsToDailyReset) or 0) - elapsed)
	countdownLabel.Text = string.format(
		"%s %s",
		labelOf("ResetsIn", "Resets in"),
		ChallengeLogic.FormatCountdown(rem)
	)
end

local function applyState(payload: any)
	if type(payload) ~= "table" then
		dataPhase = "Error"
		dataErrorMessage = labelOf("ChallengesError", "Could not load challenges. Try again later.")
		debugLog("ChallengeDataReceived", "invalid payload")
		rebuildBody()
		return
	end
	if type(payload.Daily) == "table" then
		for _, ch in ipairs(payload.Daily) do
			if type(ch) == "table" then
				local target = math.max(1, math.floor(tonumber(ch.Target) or 1))
				local progress = math.max(0, math.floor(tonumber(ch.Progress) or 0))
				if progress >= target or ch.Claimed == true then
					ch.Completed = true
					ch.Progress = target
				end
			end
		end
	end
	if type(payload.Weekly) == "table" then
		local ch = payload.Weekly
		local target = math.max(1, math.floor(tonumber(ch.Target) or 1))
		local progress = math.max(0, math.floor(tonumber(ch.Progress) or 0))
		if progress >= target or ch.Claimed == true then
			ch.Completed = true
			ch.Progress = target
		end
	end
	state = payload
	local dailyCount = if type(payload.Daily) == "table" then #payload.Daily else 0
	local hasWeekly = type(payload.Weekly) == "table"
	if dailyCount == 0 and not hasWeekly then
		dataPhase = "Empty"
	else
		dataPhase = "Ready"
	end
	logChallengeStep("ChallengeInitialStateReceived", dataPhase)
	debugLog("ChallengeDataReceived", dataPhase)
	refreshCountdown()
	rebuildBody()
	if isPermanentDock() and panel then
		logChallengeStep("ChallengePanelVisible", tostring(panel.Visible) .. " phase=" .. dataPhase)
	end
	if isPermanentDock() and gui and panel and dock then
		gui.Enabled = true
		panel.Visible = not dockedMinimized
		dock.Visible = true
	end
end

--------------------------------------------------------------------
-- Action column dock / undock
--------------------------------------------------------------------
local function applyCompactButtonChrome(btnSize: number)
	if not boundActionColumn then
		return
	end
	local glyphMax = HudChrome.CHALLENGES_ICON_GLYPH_SIZE or math.floor(btnSize * 0.5)
	local gap = HudChrome.CHALLENGES_ICON_GAP or 6
	local railH = HudChrome.ChallengesRailHeight(btnSize, gap)

	boundActionColumn.AnchorPoint = Vector2.new(0.5, 0)
	boundActionColumn.Position = UDim2.new(0.5, 0, 0, 0)
	boundActionColumn.Size = UDim2.fromOffset(btnSize, railH)

	local list = boundActionColumn:FindFirstChildOfClass("UIListLayout")
	if list then
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		list.Padding = UDim.new(0, gap)
	end

	for _, child in ipairs(boundActionColumn:GetChildren()) do
		if child:IsA("GuiObject") and (child:IsA("TextButton") or child.Name == "InventorySlot") then
			child.Size = UDim2.fromOffset(btnSize, btnSize)
			if child:IsA("GuiButton") then
				local cornerInst = child:FindFirstChildOfClass("UICorner")
				if cornerInst then
					cornerInst.CornerRadius = UDim.new(0, 10)
				end
				local border = child:FindFirstChildOfClass("UIStroke")
				if border then
					border.Thickness = 1.1
					border.Transparency = 0.22
				end
			end
			local inv = if child.Name == "InventorySlot" then child:FindFirstChild(HudChrome.INVENTORY_BUTTON_NAME) else nil
			local targetBtn: GuiObject? = if inv and inv:IsA("GuiObject") then inv else child
			if targetBtn then
				if inv and inv:IsA("GuiObject") then
					inv.Size = UDim2.fromScale(1, 1)
					local c = inv:FindFirstChildOfClass("UICorner")
					if c then
						c.CornerRadius = UDim.new(0, 10)
					end
					local s = inv:FindFirstChildOfClass("UIStroke")
					if s then
						s.Thickness = 1.1
						s.Transparency = 0.22
					end
				end
				local glyph = targetBtn:FindFirstChild("IconGlyph", true)
				if glyph and glyph:IsA("TextLabel") then
					glyph.TextScaled = false
					glyph.TextSize = glyphMax
					local constraint = glyph:FindFirstChildOfClass("UITextSizeConstraint")
					if constraint then
						constraint.MaxTextSize = glyphMax
						constraint.MinTextSize = 12
					end
				end
			end
		end
	end
end

local function restoreHudActionColumnSizes()
	if not boundActionColumn then
		return
	end
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
	local inset = GuiService:GetGuiInset()
	local usableW = math.max(200, vp.X - inset.X)
	local btn = if usableW < 700 then 52 else HudChrome.ACTION_BUTTON_SIZE
	local gap = if usableW < 700 then 10 else HudChrome.ACTION_BUTTON_GAP
	local visibleCount = 0
	for _, child in ipairs(boundActionColumn:GetChildren()) do
		if child:IsA("GuiObject") and (child:IsA("TextButton") or child.Name == "InventorySlot") and child.Visible then
			visibleCount += 1
		end
	end
	if visibleCount < 1 then
		visibleCount = 2
	end
	boundActionColumn.Size = UDim2.fromOffset(btn, btn * visibleCount + gap * math.max(0, visibleCount - 1))
	local list = boundActionColumn:FindFirstChildOfClass("UIListLayout")
	if list then
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		list.Padding = UDim.new(0, gap)
	end
	for _, child in ipairs(boundActionColumn:GetChildren()) do
		if child:IsA("GuiObject") and (child:IsA("TextButton") or child.Name == "InventorySlot") then
			child.Size = UDim2.fromOffset(btn, btn)
			if child.Name == "InventorySlot" then
				local inv = child:FindFirstChild(HudChrome.INVENTORY_BUTTON_NAME)
				if inv and inv:IsA("GuiObject") then
					inv.Size = UDim2.fromScale(1, 1)
				end
			end
		end
	end
end

-- Barre mobile unique : Inventory / Challenges / Music empilés (pas de MobileOpenButton superposé).
local function applyMobileActionBar()
	if not boundActionColumn then
		return
	end
	if not gui then
		return
	end
	local btnSize = HudChrome.CHALLENGES_MOBILE_OPEN_BTN_SIZE or 48
	local gap = 8
	local edge = HudChrome.CHALLENGES_MOBILE_OPEN_BTN_EDGE or 8
	local top = HudChrome.CHALLENGES_MOBILE_OPEN_BTN_TOP or 8

	-- Parent du ScreenGui Challenges (DisplayOrder 22) pour rester AU-DESSUS du tiroir (ZIndex 50).
	boundActionColumn.Parent = gui
	boundActionColumn:SetAttribute(HudChrome.DOCKED_ACTIONS_ATTR or "BPW_DockedActions", false)
	boundActionColumn.Visible = true
	boundActionColumn.Active = false
	boundActionColumn.BackgroundTransparency = 1
	boundActionColumn.AnchorPoint = Vector2.new(1, 0)
	boundActionColumn.Position = UDim2.new(1, -edge, 0, top)
	boundActionColumn.Size = UDim2.fromOffset(btnSize, btnSize * 3 + gap * 2)
	boundActionColumn.ZIndex = 60

	local list = boundActionColumn:FindFirstChildOfClass("UIListLayout")
	if not list then
		list = Instance.new("UIListLayout")
		list.Parent = boundActionColumn
	end
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, gap)

	for _, child in ipairs(boundActionColumn:GetChildren()) do
		if child:IsA("GuiObject") and (child:IsA("TextButton") or child.Name == "InventorySlot") then
			child.Visible = true
			child.Size = UDim2.fromOffset(btnSize, btnSize)
			child.ZIndex = 61
			if child.Name == "InventorySlot" then
				local inv = child:FindFirstChild(HudChrome.INVENTORY_BUTTON_NAME)
				if inv and inv:IsA("GuiObject") then
					inv.Size = UDim2.fromScale(1, 1)
					inv.Visible = true
					inv.ZIndex = 62
				end
			end
		end
	end

	if challengesBtn then
		challengesBtn.Visible = true
		challengesBtn.Size = UDim2.fromOffset(btnSize, btnSize)
		challengesBtn.ZIndex = 62
		setButtonActive(challengesBtn, open)
	end

	-- Ne jamais superposer un 4e bouton mobile.
	if mobileOpenBtn then
		mobileOpenBtn.Visible = false
		mobileOpenBtn.Active = false
	end
end

local function undockActionColumn()
	if not boundActionColumn then
		local pg = player:FindFirstChild("PlayerGui")
		local hud = pg and pg:FindFirstChild(HudChrome.SCREEN_NAME)
		local col = hud and hud:FindFirstChild(HudChrome.ACTION_COLUMN_NAME)
		if col and col:IsA("Frame") then
			boundActionColumn = col
		end
	end
	-- Aussi chercher dans gui Challenges si déjà déplacé.
	if not boundActionColumn and gui then
		local col = gui:FindFirstChild(HudChrome.ACTION_COLUMN_NAME)
		if col and col:IsA("Frame") then
			boundActionColumn = col
		end
	end
	if not boundActionColumn then
		return
	end
	applyMobileActionBar()
end

local function adoptActionColumn()
	if not actionRail then
		return
	end
	local pg = player:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild(HudChrome.SCREEN_NAME)
	local col = if boundActionColumn and boundActionColumn.Parent
		then boundActionColumn
		else (hud and hud:FindFirstChild(HudChrome.ACTION_COLUMN_NAME))
	-- Aussi chercher dans le ScreenGui Challenges (mode mobile précédent).
	if (not col or not col:IsA("Frame")) and gui then
		local fromGui = gui:FindFirstChild(HudChrome.ACTION_COLUMN_NAME)
		if fromGui and fromGui:IsA("Frame") then
			col = fromGui
		end
	end
	-- Aussi chercher si encore dans le rail
	if (not col or not col:IsA("Frame")) and actionRail then
		local existing = actionRail:FindFirstChild(HudChrome.ACTION_COLUMN_NAME)
		if existing and existing:IsA("Frame") then
			col = existing
		end
	end
	if col and col:IsA("Frame") then
		boundActionColumn = col
		col:SetAttribute(HudChrome.DOCKED_ACTIONS_ATTR or "BPW_DockedActions", true)
		col.Parent = actionRail
		col.AnchorPoint = Vector2.new(0.5, 0)
		col.Position = UDim2.new(0.5, 0, 0, 0)
		col.BackgroundTransparency = 1
		col.Visible = true
		col.ZIndex = 21

		local list = col:FindFirstChildOfClass("UIListLayout")
		if not list then
			list = Instance.new("UIListLayout")
			list.Parent = col
		end
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Top
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, HudChrome.CHALLENGES_ICON_GAP or 6)

		local btn = HudChrome.CHALLENGES_ICON_SIZE or 44
		local gap = HudChrome.CHALLENGES_ICON_GAP or 6
		col.Size = UDim2.fromOffset(btn, HudChrome.ChallengesRailHeight(btn, gap))

		if challengesBtn then
			challengesBtn.Visible = true
			bindChallengeButton(challengesBtn)
		else
			local b = col:FindFirstChild(HudChrome.CHALLENGES_BUTTON_NAME, true)
			if b and b:IsA("GuiButton") then
				challengesBtn = b :: TextButton
				b.Visible = true
				bindChallengeButton(b)
			end
		end
	end
end

local function applyChromeForMode()
	if not headerFrame or not tabsFrame or not closeBtn then
		return
	end
	local compact = isMobileDrawer()
	if compact then
		headerFrame.Size = UDim2.new(1, 0, 0, HudChrome.CHALLENGES_MOBILE_HEADER_HEIGHT or 40)
		tabsFrame.Size = UDim2.new(1, 0, 0, HudChrome.CHALLENGES_MOBILE_TABS_HEIGHT or 40)
		if hTitleLabel then
			hTitleLabel.TextSize = 21
			hTitleLabel.Position = UDim2.fromOffset(10, 2)
			hTitleLabel.Size = UDim2.new(1, -52, 0, 20)
		end
		if countdownLabel then
			countdownLabel.TextSize = 12
			countdownLabel.Position = UDim2.fromOffset(10, 22)
		end
		closeBtn.Size = UDim2.fromOffset(44, 44)
		closeBtn.Position = UDim2.new(1, -48, 0, 0)
		closeBtn.Visible = true
		if scroll then
			scroll.ScrollBarThickness = 3
		end
	else
		headerFrame.Size = UDim2.new(1, 0, 0, 42)
		tabsFrame.Size = UDim2.new(1, 0, 0, 38)
		if hTitleLabel then
			hTitleLabel.TextSize = 17
			hTitleLabel.Position = UDim2.fromOffset(12, 4)
			hTitleLabel.Size = UDim2.new(1, -48, 0, 18)
		end
		if countdownLabel then
			countdownLabel.TextSize = 11
			countdownLabel.Position = UDim2.fromOffset(12, 24)
		end
		local closeSize = if isConsoleDocked() then 40 else 32
		closeBtn.Size = UDim2.fromOffset(closeSize, closeSize)
		closeBtn.Position = UDim2.new(1, -(closeSize + 6), 0, 4)
		closeBtn.TextSize = if isConsoleDocked() then 20 else 16
		closeBtn.Visible = true
		if scroll then
			scroll.ScrollBarThickness = if isConsoleDocked() then 10 else 6
		end
		if isConsoleDocked() and panel then
			for _, item in ipairs(panel:GetDescendants()) do
				if item:IsA("TextLabel") or item:IsA("TextButton") then
					item.TextSize = math.max(item.TextSize, 15)
				end
			end
		end
	end
end

local function fixScrollHeight()
	if not panel or not scroll then
		return
	end
	local used = 0
	for _, ch in ipairs(panel:GetChildren()) do
		if ch:IsA("GuiObject") and ch ~= scroll and ch.Visible then
			used += ch.AbsoluteSize.Y
		end
	end
	local h = math.max(80, panel.AbsoluteSize.Y - used - 4)
	scroll.Size = UDim2.new(1, 0, 0, h)
end

--------------------------------------------------------------------
-- Layout responsive unique (DesktopDocked | ConsoleDocked | MobileDrawer)
--------------------------------------------------------------------
local studioDiagLogged = false

local function waitForValidCamera(): Camera
	local cam = Workspace.CurrentCamera
	if not cam then
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
		cam = Workspace.CurrentCamera
	end
	while cam and (cam.ViewportSize.X <= 0 or cam.ViewportSize.Y <= 0) do
		task.wait()
		cam = Workspace.CurrentCamera or cam
	end
	assert(cam, "CurrentCamera manquante")
	return cam
end

local function logChallengeUIRuntime(force: boolean?)
	if ChallengeUIConfig.DebugRuntime ~= true and not force then
		if not RunService:IsStudio() or HudChrome.CHALLENGES_STUDIO_DEBUG ~= true then
			return
		end
	end
	if studioDiagLogged and not force then
		return
	end
	if not panel or not dock then
		return
	end
	studioDiagLogged = true
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(0, 0)
	print("[ChallengeUI] BUILD:", ChallengeUIConfig.BuildId)
	print("[ChallengeUI] PreferredInput:", tostring(readPreferredInputName()))
	print("[ChallengeUI] TouchEnabled:", UserInputService.TouchEnabled)
	print("[ChallengeUI] KeyboardEnabled:", UserInputService.KeyboardEnabled)
	print("[ChallengeUI] MouseEnabled:", UserInputService.MouseEnabled)
	print("[ChallengeUI] GamepadEnabled:", UserInputService.GamepadEnabled)
	print("[ChallengeUI] Viewport:", vp.X, vp.Y)
	print("[ChallengeUI] LayoutMode:", layoutMode)
	print("[ChallengeUI] DrawerOpen:", open)
	print("[ChallengeUI] Panel:", panel:GetFullName())
	print("[ChallengeUI] Panel Visible:", panel.Visible)
	print("[ChallengeUI] Panel Position:", tostring(panel.Position))
	print("[ChallengeUI] Panel Size:", tostring(panel.Size))
	print("[ChallengeUI] PanelAbsX:", panel.AbsolutePosition.X, "AbsW:", panel.AbsoluteSize.X)
	print("[ChallengeUI] DockPosition:", tostring(dock.Position))
	print("[ChallengeUI] DockSize:", tostring(dock.Size))
	if mobileOpenBtn then
		print("[ChallengeUI] MobileOpenButton.Visible:", mobileOpenBtn.Visible)
	end
	if actionRail then
		print("[ChallengeUI] Rail Visible:", actionRail.Visible)
	end
	if boundActionColumn then
		print("[ChallengeUI] ActionButtons Visible:", boundActionColumn.Visible)
	end
	if mobileBackdrop then
		print("[ChallengeUI] Backdrop Visible:", mobileBackdrop.Visible)
	end
	if layoutMode == HudChrome.LAYOUT_MOBILE_DRAWER and not open then
		local okOff = HudChrome.IsPanelOffScreenRight(panel.AbsolutePosition.X, vp.X)
		print("[ChallengeUI] ClosedOffScreenAssert:", okOff, "absX>=vp?", panel.AbsolutePosition.X, ">=", vp.X)
	end
end

local function ensureGamepadSelectables()
	local invBtn: GuiButton? = nil
	local musicBtn: GuiButton? = nil
	local dailyRewardsBtn: GuiButton? = nil
	if boundActionColumn then
		local inv = boundActionColumn:FindFirstChild(HudChrome.INVENTORY_BUTTON_NAME, true)
		if inv and inv:IsA("GuiButton") then
			invBtn = inv
			wireSelectable(inv)
		end
		local mus = boundActionColumn:FindFirstChild(HudChrome.MUSIC_BUTTON_NAME, true)
		if mus and mus:IsA("GuiButton") then
			musicBtn = mus
			wireSelectable(mus)
		end
		local daily = boundActionColumn:FindFirstChild("DailyRewardsButton", true)
		if daily and daily:IsA("GuiButton") then
			dailyRewardsBtn = daily
			wireSelectable(daily)
		end
	end
	if challengesBtn then
		wireSelectable(challengesBtn)
	end
	if tabChallenges then
		wireSelectable(tabChallenges)
	end
	if tabLeaderboard then
		wireSelectable(tabLeaderboard)
	end
	if closeBtn then
		wireSelectable(closeBtn)
	end

	-- Navigation rail vertical.
	if invBtn and challengesBtn then
		invBtn.NextSelectionDown = challengesBtn
		challengesBtn.NextSelectionUp = invBtn
	end
	if challengesBtn and musicBtn then
		challengesBtn.NextSelectionDown = musicBtn
		musicBtn.NextSelectionUp = challengesBtn
	end
	if musicBtn and dailyRewardsBtn then
		musicBtn.NextSelectionDown = dailyRewardsBtn
		dailyRewardsBtn.NextSelectionUp = musicBtn
	end
	if dailyRewardsBtn and invBtn then
		dailyRewardsBtn.NextSelectionDown = invBtn
		invBtn.NextSelectionUp = dailyRewardsBtn
	elseif musicBtn and invBtn then
		musicBtn.NextSelectionDown = invBtn
		invBtn.NextSelectionUp = musicBtn
	end
	-- Rail → panneau (onglets).
	if challengesBtn and tabChallenges then
		challengesBtn.NextSelectionRight = tabChallenges
		tabChallenges.NextSelectionLeft = challengesBtn
	end
	if invBtn and tabChallenges then
		invBtn.NextSelectionRight = tabChallenges
	end
	if musicBtn and tabChallenges then
		musicBtn.NextSelectionRight = tabChallenges
	end
	if tabChallenges and tabLeaderboard then
		tabChallenges.NextSelectionRight = tabLeaderboard
		tabLeaderboard.NextSelectionLeft = tabChallenges
		tabChallenges.NextSelectionDown = tabLeaderboard
		tabLeaderboard.NextSelectionUp = tabChallenges
	end
	if tabChallenges and challengesBtn then
		tabChallenges.NextSelectionLeft = challengesBtn
	end
	if tabLeaderboard and challengesBtn then
		tabLeaderboard.NextSelectionLeft = challengesBtn
	end
end

local function applyDesktopDockedLayout(vp: Vector2)
	if not gui or not dock or not panel or not actionRail then
		return
	end
	cancelPanelTween()
	gui.Enabled = true
	stripUiScale(gui)
	stripUiScale(dock)
	stripUiScale(panel)
	stripUiScale(actionRail)
	-- Isolation totale : aucune prop console/mobile ne survit.
	if mobileOpenBtn then
		mobileOpenBtn.Visible = false
		mobileOpenBtn.Active = false
	end
	if mobileBackdrop then
		mobileBackdrop.Visible = false
		mobileBackdrop.Active = false
	end
	-- dockList = UIListLayout du ChallengesDock (pas de propriété Enabled).
	if dockList then
		dockList.Padding = UDim.new(0, HudChrome.CHALLENGES_RAIL_PANEL_GAP or 4)
		dockList.FillDirection = Enum.FillDirection.Horizontal
		dockList.HorizontalAlignment = Enum.HorizontalAlignment.Right
		dockList.VerticalAlignment = Enum.VerticalAlignment.Top
		dockList.SortOrder = Enum.SortOrder.LayoutOrder
	end
	if panel.Parent ~= dock then
		panel.Parent = dock
	end
	if actionRail.Parent ~= dock then
		actionRail.Parent = dock
	end

	local btn = HudChrome.CHALLENGES_ICON_SIZE or 44
	local gap = HudChrome.CHALLENGES_ICON_GAP or 6
	local railW = HudChrome.CHALLENGES_RAIL_WIDTH or 48
	local railH = HudChrome.ChallengesRailHeight(btn, gap)
	local panelW = math.clamp(PANEL_W, HudChrome.CHALLENGES_BAR_WIDTH_MIN or 330, HudChrome.CHALLENGES_BAR_WIDTH_MAX or 365)
	currentPanelW = panelW
	local dockW = HudChrome.ChallengesDockWidth(panelW, railW, HudChrome.CHALLENGES_RAIL_PANEL_GAP or 4)
	local bottomSafe = HudChrome.CHALLENGES_BOTTOM_MARGIN or 2

	dock.Visible = true
	dock.Active = false
	dock.ClipsDescendants = false
	dock.AutomaticSize = Enum.AutomaticSize.None
	dock.ZIndex = ChallengeUIConfig.PanelZIndex or 21
	dock.AnchorPoint = Vector2.new(1, 0)
	dock.Position = UDim2.new(1, 0, 0, 0)
	dock.Size = UDim2.new(0, dockW, 1, -bottomSafe)

	actionRail.Visible = true
	actionRail.Active = false
	actionRail.Size = UDim2.fromOffset(railW, railH)
	actionRail.LayoutOrder = 1
	actionRail.ZIndex = ChallengeUIConfig.RailZIndex or 25
	actionRail.AnchorPoint = Vector2.new(0, 0)
	actionRail.Position = UDim2.new(0, 0, 0, 0)
	actionRail.AutomaticSize = Enum.AutomaticSize.None

	pcall(function()
		adoptActionColumn()
		applyCompactButtonChrome(btn)
	end)

	panel.Visible = true
	panel.Active = true
	panel.LayoutOrder = 2
	panel.ZIndex = ChallengeUIConfig.PanelZIndex or 21
	panel.ClipsDescendants = true
	panel.AutomaticSize = Enum.AutomaticSize.None
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.new(0, 0, 0, 0)
	panel.Size = UDim2.new(0, panelW, 1, 0)

	if closeBtn then
		closeBtn.Visible = true
	end
	if challengesBtn then
		challengesBtn.Visible = true
		setButtonActive(challengesBtn, activeTab == "Challenges")
	end
	pcall(ensureGamepadSelectables)
	logChallengeStep("ChallengeLayoutApplied", "DesktopDocked")
	logChallengeStep("ChallengePanelVisible", tostring(panel.Visible))
end

local function applyConsoleDockedLayout(vp: Vector2)
	if not gui or not dock or not panel or not actionRail then
		return
	end
	cancelPanelTween()

	-- ScreenGui toujours actif (jamais lié à SelectedObject / gamepad focus).
	gui.Enabled = true
	stripUiScale(gui)
	stripUiScale(dock)
	stripUiScale(panel)
	stripUiScale(actionRail)

	if mobileOpenBtn then
		mobileOpenBtn.Visible = false
		mobileOpenBtn.Active = false
	end
	if mobileBackdrop then
		mobileBackdrop.Visible = false
		mobileBackdrop.Active = false
	end
	-- dockList = UIListLayout (pas Enabled).
	if dockList then
		dockList.Padding = UDim.new(0, HudChrome.CHALLENGES_RAIL_PANEL_GAP or 4)
		dockList.FillDirection = Enum.FillDirection.Horizontal
		dockList.HorizontalAlignment = Enum.HorizontalAlignment.Right
		dockList.VerticalAlignment = Enum.VerticalAlignment.Top
		dockList.SortOrder = Enum.SortOrder.LayoutOrder
	end
	if panel.Parent ~= dock then
		panel.Parent = dock
	end
	if actionRail.Parent ~= dock then
		actionRail.Parent = dock
	end

	local mx, my = HudChrome.ConsoleSafeMargins(
		ChallengeUIConfig.ConsoleSafeMarginX,
		ChallengeUIConfig.ConsoleSafeMarginY
	)
	local btn = HudChrome.CHALLENGES_ICON_SIZE or 44
	local gap = HudChrome.CHALLENGES_ICON_GAP or 6
	local railW = HudChrome.CHALLENGES_RAIL_WIDTH or 48
	local railH = HudChrome.ChallengesRailHeight(btn, gap)
	local panelW = HudChrome.ConsolePanelWidth(
		vp.X,
		ChallengeUIConfig.ConsolePanelWidthRatio,
		ChallengeUIConfig.ConsolePanelWidthMin,
		ChallengeUIConfig.ConsolePanelWidthMax
	)
	currentPanelW = panelW
	local dockW = HudChrome.ChallengesDockWidth(panelW, railW, HudChrome.CHALLENGES_RAIL_PANEL_GAP or 4)

	-- Dock = ancre droite Console (équivalent panel AnchorPoint 1,0 pour le groupement).
	dock.Visible = true
	dock.Active = false
	dock.ClipsDescendants = false
	dock.AutomaticSize = Enum.AutomaticSize.None
	dock.ZIndex = ChallengeUIConfig.PanelZIndex or 21
	dock.AnchorPoint = Vector2.new(1, 0)
	dock.Position = HudChrome.ConsoleDockPosition(mx, my)
	dock.Size = HudChrome.ConsoleDockSize(dockW, my)

	actionRail.Visible = true
	actionRail.Active = true
	actionRail.Size = UDim2.fromOffset(railW, railH)
	actionRail.LayoutOrder = 1
	actionRail.ZIndex = ChallengeUIConfig.RailZIndex or 25
	actionRail.AnchorPoint = Vector2.new(0, 0)
	actionRail.Position = UDim2.new(0, 0, 0, 0)
	actionRail.AutomaticSize = Enum.AutomaticSize.None

	-- Rail/Inventory non bloquant : panneau Challenges s'affiche même si adopt échoue.
	local adoptOk, adoptErr = pcall(function()
		adoptActionColumn()
		applyCompactButtonChrome(btn)
	end)
	if not adoptOk then
		logRuntimeError("consoleAdoptActionColumn", adoptErr, actionRail:GetFullName())
	end

	panel.Visible = true
	panel.Active = true
	panel.LayoutOrder = 2
	panel.ZIndex = ChallengeUIConfig.PanelZIndex or 21
	panel.ClipsDescendants = true
	panel.AutomaticSize = Enum.AutomaticSize.None
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.new(0, 0, 0, 0)
	panel.Size = UDim2.new(0, panelW, 1, 0)

	if scroll then
		scroll.CanvasPosition = Vector2.zero
	end

	if closeBtn then
		closeBtn.Visible = true
	end
	if challengesBtn then
		challengesBtn.Visible = true
		setButtonActive(challengesBtn, activeTab == "Challenges")
	end
	pcall(ensureGamepadSelectables)
	logChallengeStep("ChallengeLayoutApplied", "ConsoleDocked")
	logChallengeStep("ChallengePanelVisible", tostring(panel.Visible))
end

local function applyMobileDrawerLayout(vp: Vector2, preserveOpenState: boolean)
	if not gui or not dock or not panel or not actionRail then
		return
	end
	cancelPanelTween()

	-- Isolation : rail dock / dock console hors scène.
	-- UIListLayout (dockList) n'a pas de propriété Enabled — le dock est masqué ci-dessous.
	actionRail.Visible = false
	actionRail.Active = false
	actionRail.Size = UDim2.fromOffset(0, 0)
	dock.Visible = false
	dock.Active = false
	dock.Size = UDim2.fromOffset(0, 0)
	dock.AutomaticSize = Enum.AutomaticSize.None

	if not preserveOpenState then
		-- Entrée mobile / refresh de mode : toujours démarrer FERMÉ.
		mobileDrawerState = "Closed"
		open = false
	else
		open = isMobileDrawerOpen()
	end

	undockActionColumn()
	-- Boutons mobiles (Inventory/Challenges/Music) visibles à droite.
	if boundActionColumn then
		boundActionColumn.Visible = true
		boundActionColumn.Active = false
	end
	if mobileOpenBtn then
		mobileOpenBtn.Visible = false
		mobileOpenBtn.Active = false
	end
	if mobileBackdrop then
		mobileBackdrop.Visible = false
		mobileBackdrop.Active = false
	end

	local bottomSafe = HudChrome.CHALLENGES_BOTTOM_MARGIN or 2
	local topInset = 0
	local panelW = HudChrome.MobileDrawerPanelWidth(vp.X, vp.Y)
	currentPanelW = panelW
	local drawerOpen = isMobileDrawerOpen()

	if panel.Parent ~= gui then
		panel.Parent = gui
	end
	panel.Visible = true
	panel.Active = true
	panel.ZIndex = 50
	panel.ClipsDescendants = true
	panel.AutomaticSize = Enum.AutomaticSize.None
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Size = UDim2.new(0, panelW, 1, -bottomSafe)
	if drawerOpen then
		panel.Position = HudChrome.MobileDrawerOpenPosition(topInset)
	else
		panel.Position = HudChrome.MobileDrawerClosedPosition(panelW, topInset)
	end

	if closeBtn then
		closeBtn.Visible = true
		closeBtn.ZIndex = 55
	end
	if challengesBtn then
		challengesBtn.Visible = true
		setButtonActive(challengesBtn, drawerOpen)
	end
	ensureGamepadSelectables()
end

local function applyMobilePanelGeometry(animate: boolean)
	if not panel or not gui then
		return
	end
	if not isMobileDrawer() then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local bottomSafe = HudChrome.CHALLENGES_BOTTOM_MARGIN or 2
	local topInset = 0
	local panelW = HudChrome.MobileDrawerPanelWidth(vp.X, vp.Y)
	currentPanelW = panelW
	local drawerOpen = isMobileDrawerOpen()

	if panel.Parent ~= gui then
		panel.Parent = gui
	end
	panel.Visible = true
	panel.Active = true
	panel.ZIndex = 50
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Size = UDim2.new(0, panelW, 1, -bottomSafe)

	local openPos = HudChrome.MobileDrawerOpenPosition(topInset)
	local closedPos = HudChrome.MobileDrawerClosedPosition(panelW, topInset)
	local targetPos = if drawerOpen then openPos else closedPos

	if mobileBackdrop then
		mobileBackdrop.ZIndex = 40
		mobileBackdrop.Size = UDim2.new(1, -panelW, 1, 0)
		mobileBackdrop.Position = UDim2.new(0, 0, 0, 0)
		if drawerOpen and mobileDrawerState == "Open" then
			mobileBackdrop.Visible = true
			mobileBackdrop.Active = true
		elseif drawerOpen and mobileDrawerState == "Opening" then
			mobileBackdrop.Visible = true
			mobileBackdrop.Active = false
		else
			mobileBackdrop.Visible = false
			mobileBackdrop.Active = false
		end
	end

	cancelPanelTween()
	if animate and (mobileDrawerState == "Opening" or mobileDrawerState == "Closing") then
		panelTween = TweenService:Create(
			panel,
			TweenInfo.new(HudChrome.CHALLENGES_MOBILE_DRAWER_TWEEN or 0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPos }
		)
		local tw = panelTween
		panelTween.Completed:Connect(function()
			if panelTween ~= tw then
				return
			end
			if mobileDrawerState == "Opening" then
				mobileDrawerState = "Open"
				open = true
				if mobileBackdrop then
					mobileBackdrop.Visible = true
					mobileBackdrop.Active = true
				end
			elseif mobileDrawerState == "Closing" then
				mobileDrawerState = "Closed"
				open = false
				if mobileBackdrop then
					mobileBackdrop.Visible = false
					mobileBackdrop.Active = false
				end
				if panel then
					local vw = if Workspace.CurrentCamera then Workspace.CurrentCamera.ViewportSize.X else 0
					if not HudChrome.IsPanelOffScreenRight(panel.AbsolutePosition.X, vw) then
						panel.Position = HudChrome.MobileDrawerClosedPosition(currentPanelW, topInset)
					end
				end
			end
			if challengesBtn then
				setButtonActive(challengesBtn, isMobileDrawerOpen())
			end
		end)
		panelTween:Play()
	else
		panel.Position = targetPos
	end
end

local function applyLayoutMode(mode: string, vp: Vector2, prevMode: string)
	layoutMode = mode
	applyChromeForMode()

	if mode == HudChrome.LAYOUT_MOBILE_DRAWER then
		-- Transition vers mobile : forcer drawer fermé (ne pas hériter d'un open console).
		local preserve = prevMode == HudChrome.LAYOUT_MOBILE_DRAWER
		applyMobileDrawerLayout(vp, preserve)
	elseif mode == HudChrome.LAYOUT_CONSOLE_DOCKED then
		-- Drawer mobile inexistant conceptuellement en console.
		mobileDrawerState = "Closed"
		open = false
		applyConsoleDockedLayout(vp)
	else
		mobileDrawerState = "Closed"
		open = false
		applyDesktopDockedLayout(vp)
	end
end

local function recomputeAndApplyLayout()
	layoutRevision += 1
	local revision = layoutRevision
	task.defer(function()
		if revision ~= layoutRevision then
			return
		end
		if not gui or not dock or not panel or not actionRail then
			return
		end
		local cam = Workspace.CurrentCamera
		if not cam or cam.ViewportSize.X < 2 or cam.ViewportSize.Y < 2 then
			return
		end
		local vp = cam.ViewportSize
		local prevMode = layoutMode
		local nextMode = resolveLayoutModeForViewport(vp)

		if nextMode ~= prevMode or nextMode ~= lastLoggedLayoutMode then
			if ChallengeUIConfig.DebugRuntime == true then
				print("[ChallengeUI] Build:", ChallengeUIConfig.BuildId)
				print("[ChallengeUI] PreviousLayout:", prevMode)
				print("[ChallengeUI] NewLayout:", nextMode)
				print("[ChallengeUI] Viewport:", vp.X, vp.Y)
				print("[ChallengeUI] TouchEnabled:", UserInputService.TouchEnabled)
				print("[ChallengeUI] GamepadEnabled:", UserInputService.GamepadEnabled)
				print("[ChallengeUI] PreferredInput:", tostring(readPreferredInputName()))
			end
			lastLoggedLayoutMode = nextMode
		end

		applyLayoutMode(nextMode, vp, prevMode)
		refreshMobileOpenBadges()
		task.defer(function()
			if revision ~= layoutRevision then
				return
			end
			fixScrollHeight()
			logChallengeUIRuntime(false)
			-- Assert hors écran mobile fermé (runtime debug).
			if nextMode == HudChrome.LAYOUT_MOBILE_DRAWER and not isMobileDrawerOpen() and panel then
				local absX = panel.AbsolutePosition.X
				if ChallengeUIConfig.DebugRuntime == true and absX < vp.X - 0.5 then
					warn(
						"[ChallengeUI] Mobile panel not fully off-screen. absX=",
						absX,
						"vw=",
						vp.X
					)
					panel.Position = HudChrome.MobileDrawerClosedPosition(currentPanelW, 0)
				end
			end
		end)
	end)
end

-- Compat : anciens appels layoutResponsive redirigent vers recompute.
local function layoutResponsive(_opts: { animate: boolean? }?)
	recomputeAndApplyLayout()
end

-- Seule API autorisée pour ouvrir/fermer le tiroir mobile.
local function setMobileDrawerOpen(shouldOpen: boolean)
	-- Drawer mobile uniquement — refuse sur Desktop/Console (dispatcher via handleChallengeButtonActivated).
	if not isMobileDrawer() then
		return
	end

	if mobileDrawerState == "Opening" or mobileDrawerState == "Closing" then
		if shouldOpen == open then
			return
		end
	end

	if shouldOpen == open and (mobileDrawerState == "Open" or mobileDrawerState == "Closed") then
		return
	end

	open = shouldOpen
	if challengesBtn then
		challengesBtn.Visible = true
		setButtonActive(challengesBtn, shouldOpen)
	end
	if mobileOpenBtn then
		mobileOpenBtn.Visible = false
	end

	if shouldOpen then
		mobileDrawerState = "Opening"
		drawerOpenedAt = os.clock()
		flashPanel()
		Remotes.Event("ChallengePanelOpened"):FireServer()
		Remotes.Event("ChallengeRequestState"):FireServer()
		rebuildEventSlot()
		rebuildBody()

		if panel then
			local cam = Workspace.CurrentCamera
			local vp = if cam then cam.ViewportSize else Vector2.new(390, 844)
			local panelW = HudChrome.MobileDrawerPanelWidth(vp.X, vp.Y)
			currentPanelW = panelW
			if panel.Parent ~= gui and gui then
				panel.Parent = gui
			end
			panel.Visible = true
			panel.ZIndex = 50
			panel.AnchorPoint = Vector2.new(1, 0)
			panel.Size = UDim2.new(0, panelW, 1, -(HudChrome.CHALLENGES_BOTTOM_MARGIN or 2))
			if panel.AbsolutePosition.X < vp.X - 2 then
				panel.Position = HudChrome.MobileDrawerClosedPosition(panelW, 0)
			end
		end

		if mobileBackdrop then
			mobileBackdrop.Visible = true
			mobileBackdrop.Active = false
			mobileBackdrop.ZIndex = 40
			local panelW = currentPanelW
			mobileBackdrop.Size = UDim2.new(1, -panelW, 1, 0)
		end

		cancelPanelTween()
		if panel then
			local openPos = HudChrome.MobileDrawerOpenPosition(0)
			panelTween = TweenService:Create(
				panel,
				TweenInfo.new(HudChrome.CHALLENGES_MOBILE_DRAWER_TWEEN or 0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = openPos }
			)
			local tw = panelTween
			panelTween.Completed:Connect(function()
				if panelTween ~= tw then
					return
				end
				if open then
					mobileDrawerState = "Open"
					if mobileBackdrop and os.clock() - drawerOpenedAt >= 0.05 then
						mobileBackdrop.Active = true
					end
				end
				if challengesBtn then
					setButtonActive(challengesBtn, open)
					challengesBtn.Visible = true
				end
			end)
			panelTween:Play()
		end

		task.defer(function()
			task.wait(0.12)
			if open and mobileDrawerState ~= "Closing" and mobileDrawerState ~= "Closed" and mobileBackdrop then
				mobileBackdrop.Active = true
				if mobileDrawerState == "Opening" then
					mobileDrawerState = "Open"
				end
			end
		end)
	else
		mobileDrawerState = "Closing"
		if mobileBackdrop then
			mobileBackdrop.Active = false
		end
		rebuildEventSlot()
		cancelPanelTween()
		if panel then
			local closedPos = HudChrome.MobileDrawerClosedPosition(currentPanelW, 0)
			panelTween = TweenService:Create(
				panel,
				TweenInfo.new(HudChrome.CHALLENGES_MOBILE_DRAWER_TWEEN or 0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = closedPos }
			)
			local tw = panelTween
			panelTween.Completed:Connect(function()
				if panelTween ~= tw then
					return
				end
				mobileDrawerState = "Closed"
				if mobileBackdrop then
					mobileBackdrop.Visible = false
					mobileBackdrop.Active = false
				end
				if challengesBtn then
					challengesBtn.Visible = true
					setButtonActive(challengesBtn, false)
				end
				if panel then
					local vw = if Workspace.CurrentCamera then Workspace.CurrentCamera.ViewportSize.X else 0
					if not HudChrome.IsPanelOffScreenRight(panel.AbsolutePosition.X, vw) then
						panel.Position = HudChrome.MobileDrawerClosedPosition(currentPanelW, 0)
					end
				end
			end)
			panelTween:Play()
		else
			mobileDrawerState = "Closed"
		end
	end

	refreshMobileOpenBadges()
	task.defer(fillScrollHeight)
end

local function setOpen(value: boolean, _animate: boolean?)
	setMobileDrawerOpen(value)
end

showDockedChallengesPanel = function()
	if not gui or not panel or not dock then
		warn("[ChallengeButton] showDockedChallengesPanel: gui/panel/dock manquant")
		return
	end

	gui.Enabled = true
	local cam = Workspace.CurrentCamera
	local vp = if cam and cam.ViewportSize.X > 1 then cam.ViewportSize else Vector2.new(1920, 1080)

	mobileDrawerState = "Closed"
	open = false
	dockedMinimized = false
	cancelPanelTween()

	if layoutMode == HudChrome.LAYOUT_CONSOLE_DOCKED then
		applyConsoleDockedLayout(vp)
	else
		if not HudChrome.IsPermanentDockedMode(layoutMode) then
			layoutMode = HudChrome.LAYOUT_DESKTOP_DOCKED
		end
		applyDesktopDockedLayout(vp)
	end

	panel.Visible = true
	panel.Active = true
	dock.Visible = true
	if actionRail then
		actionRail.Visible = true
	end

	activeTab = "Challenges"
	if challengesBtn then
		challengesBtn.Visible = true
		challengesBtn.Active = true
		setButtonActive(challengesBtn, true)
	end
	if closeBtn then
		closeBtn.Visible = true
	end
	if mobileBackdrop then
		mobileBackdrop.Visible = false
		mobileBackdrop.Active = false
	end

	rebuildEventSlot()
	rebuildBody()
	task.defer(fillScrollHeight)
	flashPanel()

	pcall(function()
		Remotes.Event("ChallengePanelOpened"):FireServer()
		Remotes.Event("ChallengeRequestState"):FireServer()
	end)

	logDockedPanelStateStudio()
end

handleChallengeButtonActivated = function()
	logChallengeButtonStudio("Activated", if challengesBtn then challengesBtn:GetFullName() else "nil")
	logChallengeButtonStudio("Layout:", tostring(layoutMode))

	if isMobileDrawer() then
		if mobileDrawerState == "Opening" or mobileDrawerState == "Closing" then
			return
		end
		setMobileDrawerOpen(not isMobileDrawerOpen())
		return
	end

	if layoutMode == HudChrome.LAYOUT_DESKTOP_DOCKED
		or layoutMode == HudChrome.LAYOUT_CONSOLE_DOCKED
		or isPermanentDock()
	then
		showDockedChallengesPanel()
		return
	end

	warn("[ChallengeButton] Unsupported layout:", tostring(layoutMode))
end

bindChallengeButton = function(btn: GuiButton)
	if challengesBtnConn then
		challengesBtnConn:Disconnect()
		challengesBtnConn = nil
	end
	if btn:IsA("TextButton") then
		challengesBtn = btn
	end
	btn.Active = true
	btn.Selectable = true
	btn.Visible = true
	wireSelectable(btn)

	challengesBtnConn = btn.Activated:Connect(function()
		local ok, err = xpcall(handleChallengeButtonActivated, debug.traceback)
		if not ok then
			warn("[ChallengeButton] Activation failed:\n" .. tostring(err))
		end
	end)

	if RunService:IsStudio() then
		print("[ChallengeButton] Connected:", btn:GetFullName())
		print(
			"[ChallengeButton] Props Visible/Active/Selectable:",
			btn.Visible,
			btn.Active,
			btn.Selectable,
			"Abs:",
			btn.AbsolutePosition,
			btn.AbsoluteSize
		)
	end
end

function ChallengeController.Open()
	if isMobileDrawer() then
		setOpen(true, true)
	else
		showDockedChallengesPanel()
	end
end

function ChallengeController.Close()
	if isMobileDrawer() then
		setOpen(false, true)
		return
	end
	if panel and dock and actionRail then
		dockedMinimized = true
		panel.Visible = false
		panel.Active = false
		actionRail.Visible = true
		local railW = HudChrome.CHALLENGES_RAIL_WIDTH or 48
		dock.Size = UDim2.new(0, railW, 1, 0)
		if challengesBtn then
			setButtonActive(challengesBtn, false)
			GuiService.SelectedObject = challengesBtn
		end
	end
end

function ChallengeController.Toggle()
	local ok, err = xpcall(handleChallengeButtonActivated, debug.traceback)
	if not ok then
		warn("[ChallengeButton] Toggle failed:\n" .. tostring(err))
	end
end

function ChallengeController.UsesEmbeddedMiniEvent(): boolean
	-- Bandeau haut/centre dédié (MiniEventController) — pas d'embarqué Challenges.
	return false
end

function ChallengeController.IsPermanentBarActive(): boolean
	return started == true and isPermanentDock()
end

function ChallengeController.GetLayoutMode(): string
	return layoutMode
end

function ChallengeController.IsDrawerOpen(): boolean
	if not isMobileDrawer() then
		return true -- dock permanent toujours "visible"
	end
	return isMobileDrawerOpen()
end

function ChallengeController.SetMiniEventState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog("MiniEventStateReceived", tostring(payload.state))
	local prevState = if type(miniPayload) == "table" then miniPayload.state else nil
	if payload.state == "Ended" then
		miniPayload = payload
		miniHideAt = os.clock() + (MiniEventConfig.EndedBannerSeconds or 5)
	elseif payload.state == "Countdown" or payload.state == "Active" then
		miniPayload = payload
		miniHideAt = 0
		-- Notif compacte 2–3 s au lancement si tiroir fermé.
		local key = tostring(payload.eventType or "") .. ":" .. tostring(payload.state)
		if isMobileDrawer() and not isMobileDrawerOpen() and key ~= lastMobileNotifyKey and (payload.state == "Countdown" or (payload.state == "Active" and prevState ~= "Countdown" and prevState ~= "Active")) then
			lastMobileNotifyKey = key
			local name = eventDisplayName(tostring(payload.eventType or ""))
			pcall(function()
				local HUD = require(script.Parent.HUD)
				if HUD.Toast then
					HUD.Toast(name)
				end
			end)
		end
	else
		miniPayload = nil
		miniHideAt = 0
		lastMobileNotifyKey = ""
	end
	-- Panneau permanent reste visible même sans mini-événement.
	rebuildEventSlot()
	refreshMobileOpenBadges()
end

function ChallengeController.Start()
	if started then
		return
	end
	started = true
	logChallengeStep("ChallengeControllerStarted", "Challenges")
	debugLog("ControllerStarted", "Challenges")

	local screen = Instance.new("ScreenGui")
	screen.Name = "BPW_Challenges"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = ChallengeUIConfig.ScreenDisplayOrder or 40
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = true
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	logChallengeStep("ChallengeScreenGuiCreated", screen:GetFullName())
	debugLog("ScreenGuiCreated", screen:GetFullName())

	-- Backdrop mobile (gauche du tiroir).
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "MobileBackdrop"
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = HudChrome.CHALLENGES_MOBILE_BACKDROP_TRANSPARENCY or 0.62
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Position = UDim2.new(0, 0, 0, 0)
	backdrop.Visible = false
	backdrop.Active = false
	backdrop.ZIndex = 40
	backdrop.Parent = screen
	mobileBackdrop = backdrop
	backdrop.Activated:Connect(function()
		if os.clock() - drawerOpenedAt < 0.18 then
			return
		end
		if mobileDrawerState ~= "Open" then
			return
		end
		ChallengeController.Close()
	end)

	-- Bouton d'ouverture Challenges (bord droit, mobile uniquement).
	local openBtn = Instance.new("TextButton")
	openBtn.Name = "MobileOpenButton"
	openBtn.AutoButtonColor = true
	openBtn.Text = ""
	openBtn.BackgroundColor3 = BG_BUTTON
	openBtn.BackgroundTransparency = 0.08
	openBtn.BorderSizePixel = 0
	openBtn.Size = UDim2.fromOffset(HudChrome.CHALLENGES_MOBILE_OPEN_BTN_SIZE or 48, HudChrome.CHALLENGES_MOBILE_OPEN_BTN_SIZE or 48)
	openBtn.AnchorPoint = Vector2.new(1, 0)
	openBtn.Position = UDim2.new(1, -(HudChrome.CHALLENGES_MOBILE_OPEN_BTN_EDGE or 6), 0, HudChrome.CHALLENGES_MOBILE_OPEN_BTN_TOP or 8)
	openBtn.Visible = false
	openBtn.ZIndex = 25
	openBtn.Parent = screen
	corner(openBtn, 12)
	stroke(openBtn, ACCENT, 1.4, 0.25)
	mobileOpenBtn = openBtn

	local openGlyph = Instance.new("TextLabel")
	openGlyph.Name = "IconGlyph"
	openGlyph.BackgroundTransparency = 1
	openGlyph.Size = UDim2.fromScale(1, 1)
	openGlyph.Font = Enum.Font.GothamBold
	openGlyph.TextSize = HudChrome.CHALLENGES_MOBILE_OPEN_BTN_GLYPH or 24
	openGlyph.TextColor3 = TEXT
	openGlyph.Text = HudChrome.ICON_CHALLENGES
	openGlyph.ZIndex = 26
	openGlyph.Parent = openBtn
	L10nUtil.markNoLocalize(openGlyph)

	local claimDot = Instance.new("Frame")
	claimDot.Name = "ClaimBadge"
	claimDot.Size = UDim2.fromOffset(10, 10)
	claimDot.Position = UDim2.new(1, -4, 0, -2)
	claimDot.BackgroundColor3 = OK_GREEN
	claimDot.BorderSizePixel = 0
	claimDot.Visible = false
	claimDot.ZIndex = 27
	claimDot.Parent = openBtn
	corner(claimDot, 5)
	mobileClaimDot = claimDot

	local eventDot = Instance.new("Frame")
	eventDot.Name = "EventBadge"
	eventDot.Size = UDim2.fromOffset(10, 10)
	eventDot.Position = UDim2.new(1, -4, 0, -2)
	eventDot.BackgroundColor3 = GOLD
	eventDot.BorderSizePixel = 0
	eventDot.Visible = false
	eventDot.ZIndex = 27
	eventDot.Parent = openBtn
	corner(eventDot, 5)
	mobileEventDot = eventDot

	local eventTimer = Instance.new("TextLabel")
	eventTimer.Name = "EventTimerBadge"
	eventTimer.BackgroundTransparency = 1
	eventTimer.AnchorPoint = Vector2.new(0.5, 1)
	eventTimer.Position = UDim2.new(0.5, 0, 1, 2)
	eventTimer.Size = UDim2.new(1, 8, 0, 12)
	eventTimer.Font = Enum.Font.GothamBold
	eventTimer.TextSize = 10
	eventTimer.TextColor3 = GOLD
	eventTimer.Text = ""
	eventTimer.Visible = false
	eventTimer.ZIndex = 27
	eventTimer.Parent = openBtn
	L10nUtil.markNoLocalize(eventTimer)
	mobileEventTimer = eventTimer

	-- Deprecated : la barre ActionButtons porte Inventory/Challenges/Music (évite le chevauchement).
	openBtn.Visible = false
	openBtn.Active = false
	openBtn.Activated:Connect(function()
		-- no-op (sécurité si remis visible par erreur)
	end)

	local d = Instance.new("Frame")
	d.Name = HudChrome.CHALLENGES_DOCK_NAME or "ChallengesDock"
	d.AnchorPoint = Vector2.new(1, 0)
	d.Position = UDim2.new(1, 0, 0, 0)
	d.Size = UDim2.new(0, HudChrome.ChallengesDockWidth(PANEL_W), 1, -(HudChrome.CHALLENGES_BOTTOM_MARGIN or 2))
	d.BackgroundTransparency = 1
	d.BorderSizePixel = 0
	d.ZIndex = 20
	d.Visible = false -- évite flash desktop avant applyResponsiveLayout
	d.Parent = screen
	dock = d

	local dList = Instance.new("UIListLayout")
	dList.FillDirection = Enum.FillDirection.Horizontal
	dList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dList.VerticalAlignment = Enum.VerticalAlignment.Top
	dList.SortOrder = Enum.SortOrder.LayoutOrder
	dList.Padding = UDim.new(0, HudChrome.CHALLENGES_RAIL_PANEL_GAP or 4)
	dList.Parent = d
	dockList = dList

	local rail = Instance.new("Frame")
	rail.Name = "ActionRail"
	rail.LayoutOrder = 1
	rail.Size = UDim2.fromOffset(HudChrome.CHALLENGES_RAIL_WIDTH or 48, HudChrome.ChallengesRailHeight())
	rail.BackgroundTransparency = 1
	rail.BorderSizePixel = 0
	rail.ZIndex = 21
	rail.Parent = d
	actionRail = rail

	local p = Instance.new("Frame")
	p.Name = HudChrome.CHALLENGES_PANEL_NAME or "ChallengesPanel"
	p.LayoutOrder = 2
	p.Size = UDim2.new(0, PANEL_W, 1, 0)
	p.BackgroundColor3 = BG
	p.BackgroundTransparency = 0.06
	p.BorderSizePixel = 0
	p.ZIndex = 21
	p.ClipsDescendants = true
	p.Visible = false -- révélé après layout (mobile hors écran ; desktop full)
	p.Parent = d
	corner(p, 12)
	stroke(p, ACCENT, 1.5, 0.12)
	panel = p

	local badge = Instance.new("Frame")
	badge.Name = "EventBadge"
	badge.Size = UDim2.fromOffset(9, 9)
	badge.Position = UDim2.new(1, -4, 0, 0)
	badge.BackgroundColor3 = GOLD
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.ZIndex = 30
	badge.Parent = rail
	corner(badge, 5)
	eventBadge = badge

	local panelList = Instance.new("UIListLayout")
	panelList.FillDirection = Enum.FillDirection.Vertical
	panelList.SortOrder = Enum.SortOrder.LayoutOrder
	panelList.Padding = UDim.new(0, 0)
	panelList.Parent = p

	local eSlot = Instance.new("Frame")
	eSlot.Name = "ActiveEventSlot"
	eSlot.LayoutOrder = 1
	eSlot.Size = UDim2.new(1, 0, 0, 0)
	eSlot.AutomaticSize = Enum.AutomaticSize.Y
	eSlot.BackgroundTransparency = 1
	eSlot.BorderSizePixel = 0
	eSlot.Visible = false
	eSlot.ZIndex = 22
	eSlot.Parent = p
	eventSlot = eSlot

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 2
	header.Size = UDim2.new(1, 0, 0, 42)
	header.BackgroundTransparency = 1
	header.ZIndex = 22
	header.Parent = p
	headerFrame = header

	local hTitle = Instance.new("TextLabel")
	hTitle.BackgroundTransparency = 1
	hTitle.Position = UDim2.fromOffset(12, 4)
	hTitle.Size = UDim2.new(1, -48, 0, 18)
	hTitle.Font = Enum.Font.GothamBold
	hTitle.TextSize = 17
	hTitle.TextColor3 = TEXT
	hTitle.TextXAlignment = Enum.TextXAlignment.Left
	hTitle.Text = labelOf("Challenges", "CHALLENGES")
	hTitle.ZIndex = 23
	hTitle.Parent = header
	L10nUtil.markNoLocalize(hTitle)
	hTitleLabel = hTitle

	local hCd = Instance.new("TextLabel")
	hCd.BackgroundTransparency = 1
	hCd.Position = UDim2.fromOffset(12, 24)
	hCd.Size = UDim2.new(1, -48, 0, 14)
	hCd.Font = Enum.Font.Gotham
	hCd.TextSize = 11
	hCd.TextColor3 = MUTED
	hCd.TextXAlignment = Enum.TextXAlignment.Left
	hCd.Text = ""
	hCd.ZIndex = 23
	hCd.Parent = header
	L10nUtil.markNoLocalize(hCd)
	countdownLabel = hCd

	local xBtn = Instance.new("TextButton")
	xBtn.Size = UDim2.fromOffset(26, 26)
	xBtn.Position = UDim2.new(1, -32, 0, 6)
	xBtn.BackgroundColor3 = BG_BUTTON
	xBtn.Text = labelOf("Close", "X")
	xBtn.TextColor3 = TEXT
	xBtn.Font = Enum.Font.GothamBold
	xBtn.TextSize = 13
	xBtn.BorderSizePixel = 0
	xBtn.Visible = false
	xBtn.ZIndex = 24
	xBtn.Parent = header
	corner(xBtn, 7)
	closeBtn = xBtn
	xBtn.Activated:Connect(function()
		ChallengeController.Close()
	end)

	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.LayoutOrder = 3
	tabs.Size = UDim2.new(1, 0, 0, 38)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = 22
	tabs.Parent = p
	tabsFrame = tabs
	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingLeft = UDim.new(0, 10)
	tabPad.PaddingRight = UDim.new(0, 10)
	tabPad.PaddingTop = UDim.new(0, 2)
	tabPad.PaddingBottom = UDim.new(0, 2)
	tabPad.Parent = tabs
	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection = Enum.FillDirection.Horizontal
	tabList.Padding = UDim.new(0, 6)
	tabList.Parent = tabs

	local function makeTab(name: string, text: string): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.new(0.5, -3, 1, -4)
		b.BackgroundColor3 = BG_BUTTON
		b.Text = text
		b.TextColor3 = TEXT
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.ZIndex = 23
		b.Parent = tabs
		corner(b, 8)
		stroke(b, ACCENT, 1, 0.4)
		L10nUtil.markNoLocalize(b)
		b.Activated:Connect(function()
			activeTab = name
			rebuildBody()
		end)
		wireSelectable(b)
		return b
	end
	tabChallenges = makeTab("Challenges", labelOf("Challenges", "CHALLENGES"))
	tabLeaderboard = makeTab("Leaderboard", labelOf("LeaderboardTab", "LEADERBOARD"))

	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Body"
	sc.LayoutOrder = 4
	sc.Size = UDim2.new(1, 0, 1, -90)
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.ScrollBarThickness = 5
	sc.ScrollBarImageColor3 = ACCENT
	sc.CanvasSize = UDim2.new(0, 0, 0, 0)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.ScrollingDirection = Enum.ScrollingDirection.Y
	sc.ZIndex = 22
	sc.Parent = p
	scroll = sc
	local scPad = Instance.new("UIPadding")
	scPad.PaddingLeft = UDim.new(0, 10)
	scPad.PaddingRight = UDim.new(0, 10)
	scPad.PaddingTop = UDim.new(0, 6)
	scPad.PaddingBottom = UDim.new(0, 10)
	scPad.Parent = sc
	local scList = Instance.new("UIListLayout")
	scList.SortOrder = Enum.SortOrder.LayoutOrder
	scList.Padding = UDim.new(0, 8)
	scList.Parent = sc

	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fixScrollHeight)

	-- Etat Loading immediat (panneau visible sans attendre le serveur / remotes / inventaire).
	dataPhase = "Loading"
	rebuildBody()

	-- Layout IMMEDIAT (Console/Desktop) : ne pas attendre adoptActionColumn ni le réseau.
	do
		local camNow = Workspace.CurrentCamera
		local vpNow = if camNow and camNow.ViewportSize.X > 1 then camNow.ViewportSize else Vector2.new(1920, 1080)
		layoutMode = resolveLayoutModeForViewport(vpNow)
		mobileDrawerState = "Closed"
		open = false
		-- Permanent docks : appliquer de suite pour afficher "Loading challenges..."
		if HudChrome.IsPermanentDockedMode(layoutMode) then
			applyLayoutMode(layoutMode, vpNow, layoutMode)
			if gui then
				gui.Enabled = true
			end
			if panel then
				panel.Visible = true
			end
			if dock then
				dock.Visible = true
			end
		elseif layoutMode == HudChrome.LAYOUT_MOBILE_DRAWER then
			applyLayoutMode(layoutMode, vpNow, layoutMode)
		else
			if panel then
				panel.Visible = false
			end
			if dock then
				dock.Visible = false
			end
		end
	end

	-- Affinage layout + rail (non bloquant pour la visibilité du panneau permanent).
	task.spawn(function()
		local okSpawn, errSpawn = pcall(function()
			local cam = waitForValidCamera()
			local vp = cam.ViewportSize
			layoutMode = resolveLayoutModeForViewport(vp)
			mobileDrawerState = "Closed"
			open = false
			debugLog("LayoutResolved", layoutMode)

			-- Ne jamais bloquer Console sur le rail/Inventory : tentative courte seulement.
			local maxWait = if isPermanentDock() then 15 else 40
			for _ = 1, maxWait do
				if isPermanentDock() then
					pcall(adoptActionColumn)
					if boundActionColumn then
						local b = boundActionColumn:FindFirstChild(HudChrome.CHALLENGES_BUTTON_NAME, true)
						if b and b:IsA("GuiButton") then
							bindChallengeButton(b)
							break
						end
					end
					if _ >= 3 then
						break
					end
				else
					local pg = player:FindFirstChild("PlayerGui")
					local hud = pg and pg:FindFirstChild(HudChrome.SCREEN_NAME)
					local col = hud and hud:FindFirstChild(HudChrome.ACTION_COLUMN_NAME)
					if col and col:IsA("Frame") then
						boundActionColumn = col
						local b = col:FindFirstChild(HudChrome.CHALLENGES_BUTTON_NAME, true)
						if b and b:IsA("GuiButton") then
							bindChallengeButton(b)
							b.Visible = true
						end
						break
					end
				end
				task.wait(0.1)
			end

			cam = Workspace.CurrentCamera or cam
			vp = cam.ViewportSize
			mobileDrawerState = "Closed"
			open = false
			recomputeAndApplyLayout()
			if challengesBtn then
				challengesBtn.Visible = true
				bindChallengeButton(challengesBtn)
				if isPermanentDock() then
					setButtonActive(challengesBtn, true)
				end
			end
			pcall(ensureGamepadSelectables)
			debugLog("PanelShown", layoutMode)
			logChallengeStep("ChallengeLayoutApplied", layoutMode)
			if panel then
				logChallengeStep("ChallengePanelVisible", tostring(panel.Visible))
			end
			-- Desktop/Console : panneau permanent forcé visible une première fois.
			if isPermanentDock() then
				pcall(showDockedChallengesPanel)
			end
		end)
		if not okSpawn then
			logRuntimeError("initLayoutSpawn", errSpawn, if panel then panel:GetFullName() else "panel?")
			if panel and dock and gui then
				gui.Enabled = true
				panel.Visible = true
				dock.Visible = true
				if isPermanentDock() or layoutMode == HudChrome.LAYOUT_CONSOLE_DOCKED then
					pcall(function()
						applyConsoleDockedLayout(Vector2.new(1920, 1080))
					end)
				end
				showBodyStatus(labelOf("ChallengesError", "Could not load challenges. Try again later."))
			end
		end
	end)

	local remotesOk, remotesErr = pcall(function()
		Remotes.Event("ChallengeState").OnClientEvent:Connect(function(payload)
			local okA, errA = pcall(applyState, payload)
			if not okA then
				logRuntimeError("applyState", errA, if panel then panel:GetFullName() else nil)
				dataPhase = "Error"
				dataErrorMessage = labelOf("ChallengesError", "Could not load challenges. Try again later.")
				rebuildBody()
			end
		end)
		Remotes.Event("ChallengeNotify").OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end
			local kind = payload.kind
			local msg = nil
			if kind == "completed" then
				msg = labelOf("ChallengeCompletedToast", "Challenge complete! Claim your reward.")
			elseif kind == "claimed" then
				msg = string.format(
					labelOf("ChallengeClaimedToast", "Reward claimed: +%s sell bonus"),
					tostring(payload.rewardAmount or 0)
				)
			elseif kind == "top10" then
				msg = labelOf("ChallengeTop10Toast", "You entered the Daily Top 10!")
			elseif kind == "milestone" then
				msg = labelOf("ChallengeMilestoneToast", "Challenge progress!")
			end
			if msg then
				local toastOk, toastErr = pcall(function()
					local HUD = require(script.Parent.HUD)
					if HUD.Toast then
						HUD.Toast(msg)
					end
				end)
				if not toastOk then
					logRuntimeError("ChallengeNotifyToast", toastErr)
				end
			end
			refreshMobileOpenBadges()
		end)
		logChallengeStep("ChallengeRemotesResolved", "ChallengeState+Notify")
		debugLog("RemotesResolved", "ChallengeState+Notify")
		Remotes.Event("ChallengeRequestState"):FireServer()
		logChallengeStep("ChallengeInitialStateRequested", "ChallengeRequestState")
		debugLog("InitialStateRequested", "ChallengeRequestState")
	end)
	if not remotesOk then
		logRuntimeError("ChallengeRemotesResolved", remotesErr, "ReplicatedStorage.Remotes")
		dataPhase = "Error"
		dataErrorMessage = labelOf("ChallengesError", "Could not load challenges. Try again later.")
		rebuildBody()
	end

	task.spawn(function()
		while screen.Parent do
			refreshCountdown()
			refreshMobileOpenBadges()
			if miniHideAt > 0 and os.clock() >= miniHideAt then
				miniPayload = nil
				miniHideAt = 0
				rebuildEventSlot()
				fixScrollHeight()
			end
			task.wait(1)
		end
	end)

	local lastGiantProgressKey = ""
	RunService.RenderStepped:Connect(function()
		if type(miniPayload) ~= "table" then
			return
		end
		if miniPayload.state ~= "Countdown" and miniPayload.state ~= "Active" then
			return
		end
		refreshMobileOpenBadges()
		if not eventSlot or not eventSlot.Visible then
			return
		end
		local card = eventSlot:FindFirstChild("ActiveEventCard")
		if not card then
			return
		end
		local clock = Workspace:GetServerTimeNow()
		local remaining = 0
		if miniPayload.state == "Countdown" then
			remaining = math.max(0, (tonumber(miniPayload.startTime) or 0) - clock)
		else
			remaining = math.max(0, (tonumber(miniPayload.endTime) or 0) - clock)
		end
		local timer = card:FindFirstChild("EventTimer", true)
		if timer and timer:IsA("TextLabel") then
			timer.Text = tostring(math.ceil(remaining)) .. "s"
		end
		local title = card:FindFirstChild("EventTitle", true)
		if title and title:IsA("TextLabel") and miniPayload.state == "Countdown" then
			local et = tostring(miniPayload.eventType or "")
			if et == "GoldenWave" then
				title.Text = labelOf("MiniEventGoldenWaveIn", "GOLDEN WAVE IN %d"):format(math.ceil(remaining))
			elseif et == "ColorRush" then
				title.Text = labelOf("MiniEventColorRushIn", "COLOR RUSH IN %d"):format(math.ceil(remaining))
			else
				title.Text = labelOf("MiniEventGiantBubbleIn", "GIANT BUBBLE IN %d"):format(math.ceil(remaining))
			end
		end
		if miniPayload.state == "Active" and miniPayload.eventType == "GiantBubble" and type(miniPayload.progress) == "table" then
			local pr = miniPayload.progress
			local key = tostring(pr.current) .. ":" .. tostring(pr.personal)
			if key ~= lastGiantProgressKey then
				lastGiantProgressKey = key
				rebuildEventSlot()
			end
		end
	end)

	local function bindViewport()
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		local cam = Workspace.CurrentCamera
		if cam then
			viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				recomputeAndApplyLayout()
			end)
		end
	end
	bindViewport()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)

	-- Recalcul layout si l'entrée principale change (clavier ↔ manette), sans rebuild UI.
	pcall(function()
		if preferredInputConn then
			preferredInputConn:Disconnect()
			preferredInputConn = nil
		end
		preferredInputConn = UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			-- Toujours passer par resolveLayoutMode (jamais if Gamepad → Console direct).
			studioDiagLogged = false
			recomputeAndApplyLayout()
			task.defer(function()
				if not isPermanentDock() then
					return
				end
				local pref = readPreferredInputName()
				if pref == "Gamepad" and challengesBtn then
					local now = os.clock()
					if now - lastGamepadFocusAt > 1.5 then
						lastGamepadFocusAt = now
						-- Focus seulement : ne jamais piloter Visible/Enabled.
						if GuiService.SelectedObject == nil then
							GuiService.SelectedObject = challengesBtn
						end
					end
				end
			end)
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if input.KeyCode == Enum.KeyCode.ButtonB then
			-- Mobile : fermer le tiroir. Console/Desktop : retour focus rail (ne jamais cacher le panneau).
			if isMobileDrawer() and isMobileDrawerOpen() then
				if not gp then
					setOpen(false, true)
				end
				return
			end
			if isPermanentDock() and challengesBtn then
				local sel = GuiService.SelectedObject
				if sel and panel and sel:IsDescendantOf(panel) then
					GuiService.SelectedObject = challengesBtn
				end
			end
			return
		end
		if gp then
			return
		end
		if not isMobileDrawer() or not isMobileDrawerOpen() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false, true)
		end
	end)

	pcall(function()
		local HUD = require(script.Parent.HUD)
		HUD.OpenChallenges = ChallengeController.Toggle
	end)

	-- Ne pas re-masquer le panneau : le bloc immédiat ci-dessus a déjà appliqué le dock permanent.
	debugLog("ControllerStarted", "complete")
end

return ChallengeController
