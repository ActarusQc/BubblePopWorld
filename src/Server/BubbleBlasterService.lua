--!strict
-- Jeu de foire Bubble Blaster. Le serveur possède la partie, le score et la récompense.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local BubbleBlasterConfig = require(Shared.BubbleBlasterConfig)
local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)

local Service = {}
local rng = Random.new()

local DURATION = BubbleBlasterConfig.Duration
local REPLAY_COOLDOWN = BubbleBlasterConfig.ReplayCooldown
local sessions: { [Player]: any } = {}
local lastFinished: { [Player]: number } = {}
local boundPrompts: { [ProximityPrompt]: boolean } = {}

local function resultFor(score: number): (string, number, Color3)
	return BubbleBlasterConfig.ResultFor(score)
end

local function finish(player: Player, abandoned: boolean?)
	local session = sessions[player]
	if not session then return end
	sessions[player] = nil
	lastFinished[player] = os.clock()

	local score = session.score :: number
	local tier, reward, color = resultFor(score)
	if abandoned then
		reward = math.min(reward, BubbleBlasterConfig.AbandonMaxCoins)
		tier = "PARTICIPATION"
	end

	local credited = DataService.AddCoins(player, reward, "BubbleBlaster")
	if credited then DataService.Push(player) end
	Remotes.Event("BubbleBlasterEnd"):FireClient(player, {
		score = score,
		tier = tier,
		reward = reward,
		color = color,
		abandoned = abandoned == true,
	})
end

local function runSession(player: Player, session: any)
	while sessions[player] == session and os.clock() < session.endsAt do
		session.serial += 1
		local progress = math.clamp((os.clock() - session.startedAt) / DURATION, 0, 1)
		local lifetime = 1.45 - progress * 0.62
		local isGolden = rng:NextNumber() < BubbleBlasterConfig.GoldenChance
		local target = {
			id = session.serial,
			x = rng:NextNumber(0.10, 0.90),
			y = rng:NextNumber(0.16, 0.78),
			size = rng:NextNumber(0.115, 0.155) - progress * 0.025,
			colorIndex = rng:NextInteger(1, 5),
			golden = isGolden,
			points = if isGolden then BubbleBlasterConfig.GoldenPoints else BubbleBlasterConfig.NormalPoints,
			expiresAt = os.clock() + lifetime,
		}
		session.target = target
		Remotes.Event("BubbleBlasterTarget"):FireClient(player, target)

		while sessions[player] == session and session.target == target and os.clock() < target.expiresAt do
			task.wait(0.04)
		end
		if sessions[player] ~= session then return end
		if session.target == target then
			session.target = nil
			Remotes.Event("BubbleBlasterState"):FireClient(player, {
				score = session.score,
				miss = true,
			})
		end
		task.wait(0.10)
	end
	if sessions[player] == session then finish(player, false) end
end

local function startGame(player: Player)
	if sessions[player] then return end
	if lastFinished[player] and os.clock() - lastFinished[player] < REPLAY_COOLDOWN then
		Remotes.Event("Announce"):FireClient(player, "Bubble Blaster is reloading!", "info")
		return
	end
	local now = os.clock()
	local session = {
		startedAt = now,
		endsAt = now + DURATION,
		score = 0,
		serial = 0,
		target = nil,
		lastShotAt = 0,
	}
	sessions[player] = session
	PetService.GrantAndEquip(player)
	Remotes.Event("BubbleBlasterStart"):FireClient(player, {
		duration = DURATION,
		endsAt = session.endsAt,
	})
	task.spawn(runSession, player, session)
end

local function bindPrompt(prompt: ProximityPrompt)
	if boundPrompts[prompt] then return end
	if prompt.Name ~= "PlayBubbleBlaster" and prompt.Parent:GetAttribute("BubbleBlasterPrompt") ~= true then return end
	boundPrompts[prompt] = true
	prompt.Triggered:Connect(startGame)
	prompt.Destroying:Connect(function() boundPrompts[prompt] = nil end)
end

local function scanPrompts()
	local park = workspace:FindFirstChild("ParcAttractions")
	if not park then return end
	for _, descendant in ipairs(park:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then bindPrompt(descendant) end
	end
end

function Service.Start()
	Remotes.Event("BubbleBlasterShoot").OnServerEvent:Connect(function(player: Player, targetId: any)
		local session = sessions[player]
		if not session or type(targetId) ~= "number" then return end
		local now = os.clock()
		if now - session.lastShotAt < 0.075 then return end
		session.lastShotAt = now
		local target = session.target
		if not target or target.id ~= targetId or now > target.expiresAt then return end
		session.target = nil
		session.score += target.points
		Remotes.Event("BubbleBlasterState"):FireClient(player, {
			score = session.score,
			hit = true,
			golden = target.golden,
			points = target.points,
		})
	end)

	Remotes.Event("BubbleBlasterExit").OnServerEvent:Connect(function(player: Player)
		finish(player, true)
	end)

	workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then task.defer(bindPrompt, descendant) end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		lastFinished[player] = nil
	end)
	task.defer(scanPrompts)
end

return Service
