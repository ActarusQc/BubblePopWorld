--!strict
-- Tutoriel d'accueil progressif — autorité serveur uniquement.
-- Conditions / récompenses validées ici ; le client n'affiche que l'état reçu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local TutorialConfig = require(Shared.TutorialConfig)

local DataService = require(script.Parent.DataService)

local TutorialService = {}

local started = false
local bound: { [Player]: boolean } = {}
-- Marteau de guidage spawné pour un joueur (cleanup à step change / leave).
local guidedDrops: { [Player]: BasePart? } = {}
local advancing: { [Player]: boolean } = {}

local function safeFireState(player: Player, payload: any)
	local ok, err = pcall(function()
		Remotes.Event("TutorialState"):FireClient(player, payload)
	end)
	if not ok then
		warn(("[TutorialService] FireClient ignoré pour %s : %s"):format(
			tostring(player.Name),
			tostring(err)
		))
	end
end

local function ensureTutorialTable(profile: any): any
	if type(profile.Tutorial) ~= "table" then
		profile.Tutorial = {
			Version = TutorialConfig.Version,
			Step = 0,
			PopCount = 0,
			SellCount = 0,
			HammerPicked = false,
			HammerMultiDone = false,
			Rewarded = {},
		}
	end
	local t = profile.Tutorial
	if type(t.Rewarded) ~= "table" then
		t.Rewarded = {}
	end
	t.Version = TutorialConfig.Version
	t.Step = math.max(0, math.floor(tonumber(t.Step) or 0))
	t.PopCount = math.max(0, math.floor(tonumber(t.PopCount) or 0))
	t.SellCount = math.max(0, math.floor(tonumber(t.SellCount) or 0))
	t.HammerPicked = t.HammerPicked == true
	t.HammerMultiDone = t.HammerMultiDone == true
	if profile.TutorialCompleted == nil then
		profile.TutorialCompleted = false
	end
	return t
end

local function isActive(profile: any): boolean
	if not TutorialConfig.Enabled then
		return false
	end
	if profile.TutorialCompleted == true then
		return false
	end
	local t = ensureTutorialTable(profile)
	return t.Step > 0
end

local function playerHasTool(player: Player, toolId: string): boolean
	local function scan(container: Instance?): boolean
		if not container then
			return false
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("ToolId") == toolId then
				return true
			end
		end
		return false
	end
	return scan(player:FindFirstChildOfClass("Backpack")) or scan(player.Character)
end

local function grantReward(player: Player, step: TutorialConfig.StepDef, alreadyOwnedHint: boolean?): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local t = ensureTutorialTable(profile)
	if t.Rewarded[step.Id] == true then
		return true
	end

	local reward = step.Reward
	if reward.Kind == "Coins" then
		local amount = math.max(0, math.floor(tonumber(reward.Amount) or 0))
		if amount > 0 then
			local ok = DataService.AddCoins(player, amount, reward.Source or "Tutorial")
			if not ok then
				return false
			end
		end
	elseif reward.Kind == "Tool" then
		local toolId = reward.ToolId
		local skip = reward.SkipIfOwned == true
		local owned = alreadyOwnedHint == true or playerHasTool(player, toolId)
		if not (skip and owned) then
			local ToolService = require(script.Parent.ToolService)
			ToolService.Give(player, toolId)
		end
	end

	t.Rewarded[step.Id] = true
	profile.__dirty = true
	DataService.Push(player)
	return true
end

local function clearGuidedDrop(player: Player)
	local model = guidedDrops[player]
	guidedDrops[player] = nil
	if model and model.Parent then
		model:Destroy()
	end
end

local function ensureGuidedHammer(player: Player)
	if guidedDrops[player] and guidedDrops[player].Parent then
		return
	end
	local DropService = require(script.Parent.DropService)
	if type(DropService.SpawnTutorialDrop) ~= "function" then
		return
	end
	local drop = DropService.SpawnTutorialDrop(player, TutorialConfig.Ids.HammerToolId)
	if drop then
		guidedDrops[player] = drop
	end
end

local function buildPayload(
	kind: string,
	step: TutorialConfig.StepDef?,
	progress: number,
	rewardAmount: number?,
	guideActive: boolean?
): any
	local threshold = if step and type(step.Threshold) == "number" then step.Threshold else 0
	return {
		Kind = kind,
		StepId = if step then step.Id else 0,
		Key = if step then step.Key else "",
		Message = if step then step.Message else "",
		Progress = progress,
		ProgressMax = threshold,
		RewardCoins = rewardAmount or 0,
		Guide = guideActive == true,
		GuideToolId = if guideActive then TutorialConfig.Ids.HammerToolId else nil,
		Celebrate = kind == TutorialConfig.PayloadKind.StepComplete,
		Completed = kind == TutorialConfig.PayloadKind.Done,
	}
end

local function syncAttribute(player: Player, stepId: number)
	player:SetAttribute(TutorialConfig.AttributeName, stepId)
end

local function pushShow(player: Player, step: TutorialConfig.StepDef, progress: number)
	local guide = step.Guide == true
	if guide then
		task.defer(ensureGuidedHammer, player)
	else
		clearGuidedDrop(player)
	end
	syncAttribute(player, step.Id)
	safeFireState(player, buildPayload(TutorialConfig.PayloadKind.Show, step, progress, nil, guide))
end

local function pushProgress(player: Player, step: TutorialConfig.StepDef, progress: number)
	safeFireState(
		player,
		buildPayload(TutorialConfig.PayloadKind.Progress, step, progress, nil, step.Guide == true)
	)
end

function TutorialService.GetStepId(player: Player): number
	local profile = DataService.Get(player)
	if not profile or not isActive(profile) then
		return 0
	end
	return ensureTutorialTable(profile).Step
end

local function tryAdvance(player: Player)
	if advancing[player] then
		return
	end
	local profile = DataService.Get(player)
	if not profile or not isActive(profile) then
		return
	end

	local t = ensureTutorialTable(profile)
	local step = TutorialConfig.GetStep(t.Step)
	if not step then
		return
	end

	local done = false
	local progress = 0
	if step.Condition == "PopCount" then
		progress = t.PopCount
		done = progress >= (step.Threshold or 0)
	elseif step.Condition == "BackpackSold" then
		progress = t.SellCount
		done = progress >= (step.Threshold or 1)
	elseif step.Condition == "AcquireTool" then
		progress = if t.HammerPicked then 1 else 0
		done = t.HammerPicked == true
	elseif step.Condition == "ToolMultiPop" then
		progress = if t.HammerMultiDone then 1 else 0
		done = t.HammerMultiDone == true
	end

	if not done then
		pushProgress(player, step, progress)
		return
	end

	advancing[player] = true
	local okReward = grantReward(player, step, t.HammerPicked)
	if not okReward then
		advancing[player] = nil
		warn("[TutorialService] récompense étape " .. step.Id .. " échouée pour " .. player.Name)
		return
	end

	local rewardCoins = 0
	if step.Reward.Kind == "Coins" then
		rewardCoins = math.max(0, math.floor(tonumber(step.Reward.Amount) or 0))
	end

	safeFireState(
		player,
		buildPayload(
			TutorialConfig.PayloadKind.StepComplete,
			step,
			progress,
			rewardCoins,
			false
		)
	)

	local nextId = TutorialConfig.NextStepId(step.Id)
	if nextId == nil then
		profile.TutorialCompleted = true
		t.Step = 0
		profile.__dirty = true
		clearGuidedDrop(player)
		syncAttribute(player, 0)
		DataService.Push(player)
		safeFireState(player, buildPayload(TutorialConfig.PayloadKind.Done, nil, 0, rewardCoins, false))
		task.spawn(DataService.Save, player)
		advancing[player] = nil
		return
	end

	t.Step = nextId
	profile.__dirty = true
	DataService.Push(player)

	local nextStep = TutorialConfig.GetStep(nextId)
	if nextStep then
		-- Léger délai pour laisse l'UI célébrer / transitionner.
		task.delay(TutorialConfig.UI.CelebrateDuration, function()
			if not player.Parent then
				advancing[player] = nil
				return
			end
			local p2 = DataService.Get(player)
			if not p2 or p2.TutorialCompleted == true then
				advancing[player] = nil
				return
			end
			local t2 = ensureTutorialTable(p2)
			if t2.Step ~= nextId then
				advancing[player] = nil
				return
			end
			local prog = 0
			if nextStep.Condition == "PopCount" then
				prog = t2.PopCount
			elseif nextStep.Condition == "BackpackSold" then
				prog = t2.SellCount
			end
			pushShow(player, nextStep, prog)
			advancing[player] = nil
		end)
	else
		advancing[player] = nil
	end
end

function TutorialService.BeginIfNeeded(player: Player)
	if not TutorialConfig.Enabled then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local t = ensureTutorialTable(profile)

	if profile.TutorialCompleted == true then
		t.Step = 0
		syncAttribute(player, 0)
		safeFireState(player, buildPayload(TutorialConfig.PayloadKind.Done, nil, 0, 0, false))
		return
	end

	-- Reprise : étape déjà en cours (session précédente).
	if t.Step > 0 then
		local step = TutorialConfig.GetStep(t.Step)
		if not step then
			return
		end
		local progress = 0
		if step.Condition == "PopCount" then
			progress = t.PopCount
		elseif step.Condition == "BackpackSold" then
			progress = t.SellCount
		elseif step.Condition == "AcquireTool" then
			progress = if t.HammerPicked then 1 else 0
		elseif step.Condition == "ToolMultiPop" then
			progress = if t.HammerMultiDone then 1 else 0
		end
		pushShow(player, step, progress)
		task.defer(tryAdvance, player)
		return
	end

	-- Première session uniquement : un joueur déjà progressé (hors feature) ne revoit pas le tuto.
	local pops = math.floor(tonumber(profile.Pops) or 0)
	local sold = math.floor(tonumber(profile.TotalBubblesSold) or 0)
	local isNew = profile.__isNewProfile == true
	if not isNew and (pops > 0 or sold > 0) then
		profile.TutorialCompleted = true
		t.Step = 0
		profile.__dirty = true
		syncAttribute(player, 0)
		task.spawn(DataService.Save, player)
		return
	end

	t.Step = TutorialConfig.FirstStepId()
	t.PopCount = 0
	t.SellCount = 0
	t.HammerPicked = false
	t.HammerMultiDone = false
	if type(t.Rewarded) ~= "table" then
		t.Rewarded = {}
	end
	profile.__dirty = true

	local step = TutorialConfig.GetStep(t.Step)
	if not step then
		return
	end
	pushShow(player, step, 0)
	task.defer(tryAdvance, player)
end

function TutorialService.OnBubblesPopped(player: Player, count: number)
	if type(count) ~= "number" or count ~= count or count <= 0 then
		return
	end
	local profile = DataService.Get(player)
	if not profile or not isActive(profile) then
		return
	end
	local t = ensureTutorialTable(profile)
	local step = TutorialConfig.GetStep(t.Step)
	if not step or step.Condition ~= "PopCount" then
		return
	end
	t.PopCount = t.PopCount + math.floor(count)
	profile.__dirty = true
	tryAdvance(player)
end

function TutorialService.OnBackpackSold(player: Player, _sold: number?, _earned: number?)
	local profile = DataService.Get(player)
	if not profile or not isActive(profile) then
		return
	end
	local t = ensureTutorialTable(profile)
	local step = TutorialConfig.GetStep(t.Step)
	if not step or step.Condition ~= "BackpackSold" then
		return
	end
	t.SellCount = t.SellCount + 1
	profile.__dirty = true
	tryAdvance(player)
end

function TutorialService.OnToolAcquired(player: Player, toolId: string)
	if type(toolId) ~= "string" then
		return
	end
	local profile = DataService.Get(player)
	if not profile or not isActive(profile) then
		return
	end
	local t = ensureTutorialTable(profile)
	local step = TutorialConfig.GetStep(t.Step)
	if not step or step.Condition ~= "AcquireTool" then
		return
	end
	if toolId ~= (step.ToolId or TutorialConfig.Ids.HammerToolId) then
		return
	end
	t.HammerPicked = true
	profile.__dirty = true
	clearGuidedDrop(player)
	tryAdvance(player)
end

function TutorialService.OnToolMultiPop(player: Player, toolId: string, popCount: number)
	if type(toolId) ~= "string" then
		return
	end
	if type(popCount) ~= "number" or popCount ~= popCount or popCount <= 0 then
		return
	end
	local profile = DataService.Get(player)
	if not profile or not isActive(profile) then
		return
	end
	local t = ensureTutorialTable(profile)
	local step = TutorialConfig.GetStep(t.Step)
	if not step or step.Condition ~= "ToolMultiPop" then
		return
	end
	if toolId ~= (step.ToolId or TutorialConfig.Ids.HammerToolId) then
		return
	end
	local need = step.Threshold or 2
	if popCount < need then
		return
	end
	t.HammerMultiDone = true
	profile.__dirty = true
	tryAdvance(player)
end

function TutorialService.Start()
	if started then
		return
	end
	started = true

	local function bind(player: Player)
		if bound[player] then
			return
		end
		bound[player] = true
		task.spawn(function()
			local deadline = os.clock() + 30
			while player.Parent and not DataService.Get(player) and os.clock() < deadline do
				task.wait(0.1)
			end
			if not player.Parent then
				return
			end
			-- Attendre fin du chargement DataStore si marqué.
			local profile = DataService.Get(player)
			if profile and profile.__loaded == false then
				-- Profil bloqué : ne pas démarrer un tutoriel qui ne pourra pas se sauvegarder.
				return
			end
			TutorialService.BeginIfNeeded(player)
		end)
	end

	Players.PlayerAdded:Connect(bind)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(bind, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		bound[player] = nil
		advancing[player] = nil
		clearGuidedDrop(player)
	end)
end

return TutorialService
