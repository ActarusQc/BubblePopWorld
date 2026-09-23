--!strict
-- Jeu de foire Roll-A-Ball. Le serveur possède la partie, le score et la récompense.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local RollABallConfig = require(Shared.RollABallConfig)
local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)

local Service = {}
local rng = Random.new()

local BALLS = RollABallConfig.BallsPerGame
local REPLAY_COOLDOWN = RollABallConfig.ReplayCooldown
local ROLL_COOLDOWN = RollABallConfig.RollCooldown
local sessions: { [Player]: any } = {}
local lastFinished: { [Player]: number } = {}
local boundPrompts: { [ProximityPrompt]: boolean } = {}

local function resultFor(score: number): (string, number, Color3)
	return RollABallConfig.ResultFor(score)
end

local function finish(player: Player, abandoned: boolean?)
	local session = sessions[player]
	if not session then return end
	sessions[player] = nil
	lastFinished[player] = os.clock()

	local score = session.score :: number
	local tier, reward, color = resultFor(score)
	local petAwarded = false
	if abandoned then
		reward = math.min(reward, RollABallConfig.AbandonMaxCoins)
		tier = "PARTICIPATION"
	elseif RollABallConfig.WinsPrizePet(score) then
		local profile = DataService.Get(player)
		local ownedItems = profile and profile.OwnedItems
		local alreadyOwned = type(ownedItems) == "table" and ownedItems[RollABallConfig.PrizePetId] == true
		if not alreadyOwned then
			PetService.GrantAndEquip(player)
			local refreshed = DataService.Get(player)
			petAwarded = refreshed ~= nil
				and type(refreshed.OwnedItems) == "table"
				and refreshed.OwnedItems[RollABallConfig.PrizePetId] == true
			if petAwarded then
				reward = 0
			end
		end
	end

	local credited = false
	if reward > 0 then
		credited = select(1, DataService.AddCoins(player, reward, "RollABall"))
	end
	if credited then DataService.Push(player) end
	Remotes.Event("RollABallEnd"):FireClient(player, {
		score = score,
		tier = tier,
		reward = reward,
		color = color,
		petAwarded = petAwarded,
		prizeName = if petAwarded then RollABallConfig.PrizePetName else nil,
		abandoned = abandoned == true,
	})
end

local function startGame(player: Player)
	if sessions[player] then return end
	if lastFinished[player] and os.clock() - lastFinished[player] < REPLAY_COOLDOWN then
		Remotes.Event("Announce"):FireClient(player, "Roll-A-Ball is reloading!", "info")
		return
	end
	local session = {
		score = 0,
		ballsLeft = BALLS,
		lastRollAt = 0,
		rolling = false,
		powerEpoch = Workspace:GetServerTimeNow(),
		powerPhase = rng:NextNumber(0, math.pi * 2),
	}
	sessions[player] = session
	Remotes.Event("RollABallStart"):FireClient(player, {
		balls = BALLS,
		score = 0,
		powerEpoch = session.powerEpoch,
		powerPhase = session.powerPhase,
	})
end

local function bindPrompt(prompt: ProximityPrompt)
	if boundPrompts[prompt] then return end
	if prompt.Name ~= "PlayRollABall" and prompt.Parent:GetAttribute("RollABallPrompt") ~= true then return end
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
	Remotes.Event("RollABallRoll").OnServerEvent:Connect(function(player: Player)
		local session = sessions[player]
		if not session then return end
		if session.ballsLeft <= 0 or session.rolling then return end
		local now = os.clock()
		if now - session.lastRollAt < ROLL_COOLDOWN then return end
		session.lastRollAt = now
		session.rolling = true
		session.ballsLeft -= 1

		local elapsed = Workspace:GetServerTimeNow() - session.powerEpoch
		local clamped = RollABallConfig.PowerAt(elapsed, session.powerPhase)
		local jitter = rng:NextNumber(-RollABallConfig.JitterAmplitude, RollABallConfig.JitterAmplitude)
		local points = RollABallConfig.ScoreForPower(clamped, jitter)
		session.score += points

		Remotes.Event("RollABallState"):FireClient(player, {
			score = session.score,
			points = points,
			ballsLeft = session.ballsLeft,
			power = clamped,
		})

		task.delay(1.05, function()
			if sessions[player] ~= session then return end
			session.rolling = false
			if session.ballsLeft <= 0 then
				finish(player, false)
			end
		end)
	end)

	Remotes.Event("RollABallExit").OnServerEvent:Connect(function(player: Player)
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
