--!strict
-- Daily Rewards 7 jours : streak par jours UTC, serveur autoritaire, claim idempotent.
-- Le chandail J7 est enregistré comme entitlement durable dans le profil. La distribution
-- Marketplace réelle sera branchée séparément quand l'asset Roblox sera publié/configuré.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyRewardsConfig = require(Shared.DailyRewardsConfig)
local DailyRewardsLogic = require(Shared.DailyRewardsLogic)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local stateRemote = Remotes.Event("DailyRewardsState")
local requestRemote = Remotes.Event("DailyRewardsRequestState")
local claimRemote = Remotes.Event("DailyRewardsClaim")
local panelOpenedRemote = Remotes.Event("DailyRewardsPanelOpened")
local announceRemote = Remotes.Event("Announce")

local claimBusy: { [Player]: boolean } = {}
local lastClaimAt: { [Player]: number } = {}
local lastRequestAt: { [Player]: number } = {}
local started = false

local function todayKey(): number
	return DailyRewardsLogic.DayKeyFromUnix(os.time())
end

local function validLoadedProfile(player: Player): any?
	local profile = DataService.Get(player)
	if type(profile) ~= "table" or profile.__loaded ~= true then
		return nil
	end
	return profile
end

local function emitCustom(player: Player, name: string, value: number?)
	-- Réutilise le sink central du projet. DebugEmitCustom est le point générique actuel
	-- vers LogCustomEvent; pcall garantit qu'Analytics ne bloque jamais le gameplay.
	pcall(function()
		local GAS = require(script.Parent.GameAnalyticsService)
		if GAS.DebugEmitCustom then
			GAS.DebugEmitCustom(player, name, value)
		end
	end)
end

local function emitCoinEconomy(player: Player, amount: number, endingBalance: number)
	pcall(function()
		local GAS = require(script.Parent.GameAnalyticsService)
		if GAS.LogCoinSource then
			GAS.LogCoinSource(player, {
				amount = amount,
				endingBalance = endingBalance,
				transactionType = "Gameplay",
				itemSku = "DailyReward",
			})
		end
	end)
end

local function persistState(profile: any, state: any)
	profile.DailyRewards = {
		Version = state.Version,
		Streak = state.Streak,
		LastVisitDayKey = state.LastVisitDayKey,
		LastClaimDayKey = state.LastClaimDayKey,
		LifetimeClaims = state.LifetimeClaims,
		CompletedCycles = state.CompletedCycles,
		ShirtUnlocked = state.ShirtUnlocked == true,
	}
	profile.__dirty = true
end

local function pushState(player: Player, extra: any?)
	local profile = validLoadedProfile(player)
	if not profile then
		return
	end
	local payload = DailyRewardsLogic.SerializePublicState(profile.DailyRewards, todayKey())
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	pcall(function()
		stateRemote:FireClient(player, payload)
	end)
end

local function ensureTodayVisit(player: Player): (any?, any?)
	local profile = validLoadedProfile(player)
	if not profile then
		return nil, nil
	end

	local key = todayKey()
	local state, visit = DailyRewardsLogic.RecordVisit(profile.DailyRewards, key)
	if visit.Changed then
		persistState(profile, state)
		player:SetAttribute("DailyRewardStreak", state.Streak)
		player:SetAttribute("DailyRewardDay", visit.CycleDay)
		player:SetAttribute("DailyRewardShirtUnlocked", state.ShirtUnlocked)

		if visit.Advanced then
			emitCustom(player, "DailyStreakAdvanced", state.Streak)
		end
		if visit.Broken then
			emitCustom(player, "DailyStreakBroken", state.Streak)
		end
		if visit.ReachedDay7 then
			emitCustom(player, "DailyRewardDay7Reached", state.CompletedCycles)
			pcall(function()
				announceRemote:FireClient(player, "7-day streak! Exclusive Bubble Pop shirt unlocked!", "reward")
			end)
		end
	else
		player:SetAttribute("DailyRewardStreak", state.Streak)
		player:SetAttribute("DailyRewardDay", DailyRewardsLogic.CurrentCycleDay(state))
		player:SetAttribute("DailyRewardShirtUnlocked", state.ShirtUnlocked)
	end

	return profile, state
end

local function claimToday(player: Player)
	if claimBusy[player] then
		return
	end
	local nowClock = os.clock()
	if lastClaimAt[player] and (nowClock - lastClaimAt[player]) < DailyRewardsConfig.ClaimCooldownSeconds then
		return
	end
	lastClaimAt[player] = nowClock
	claimBusy[player] = true

	local ok, err = xpcall(function()
		local profile, state = ensureTodayVisit(player)
		if not profile or not state then
			return
		end

		local key = todayKey()
		if not DailyRewardsLogic.CanClaim(state, key) then
			pushState(player, { ClaimResult = "already_claimed" })
			return
		end

		local cycleDay = DailyRewardsLogic.CurrentCycleDay(state)
		local reward = DailyRewardsConfig.GetReward(cycleDay)
		if not reward then
			pushState(player, { ClaimResult = "invalid_reward" })
			return
		end

		local amount = math.max(0, math.floor(tonumber(reward.Amount) or 0))
		local endingBalance = math.max(0, math.floor(tonumber(profile.Coins) or 0))
		if amount > 0 then
			local added, balance = DataService.AddCoins(player, amount, "DailyReward")
			if not added or type(balance) ~= "number" then
				pushState(player, { ClaimResult = "coin_grant_failed" })
				return
			end
			endingBalance = balance
		end

		local claimedState, marked, code = DailyRewardsLogic.MarkClaimed(state, key)
		if not marked then
			-- En pratique impossible sous claimBusy; ne jamais écraser l'état si le marker refuse.
			pushState(player, { ClaimResult = code })
			return
		end
		if reward.RewardType == "ExclusiveShirt" then
			claimedState.ShirtUnlocked = true
		end
		persistState(profile, claimedState)
		DataService.Push(player)

		if amount > 0 then
			emitCoinEconomy(player, amount, endingBalance)
		end
		emitCustom(player, "DailyRewardClaimed", cycleDay)

		pcall(function()
			announceRemote:FireClient(player, reward.Title .. " claimed!", "reward")
		end)
		pushState(player, {
			ClaimResult = "ok",
			ClaimedDay = cycleDay,
			ClaimedAmount = amount,
		})
	end, debug.traceback)

	claimBusy[player] = nil
	if not ok then
		warn("[DailyRewardsService] claim failed for " .. player.Name .. ":\n" .. tostring(err))
	end
end

local function onPlayerReady(player: Player)
	task.spawn(function()
		-- DataService est démarré par le bootstrap principal; ce Script peut démarrer en parallèle.
		for _ = 1, 100 do
			local profile = DataService.Get(player)
			if type(profile) == "table" then
				if profile.__loaded == true then
					break
				elseif profile.__loaded == false then
					-- Échec DataStore : aucune récompense non persistable.
					return
				end
			end
			if not player.Parent then
				return
			end
			task.wait(0.1)
		end

		if not player.Parent or not validLoadedProfile(player) then
			return
		end
		ensureTodayVisit(player)
		pushState(player)
	end)
end

local function start()
	if started or not DailyRewardsConfig.Enabled then
		return
	end
	started = true

	requestRemote.OnServerEvent:Connect(function(player: Player)
		local nowClock = os.clock()
		if lastRequestAt[player]
			and (nowClock - lastRequestAt[player]) < DailyRewardsConfig.StateRequestThrottleSeconds then
			return
		end
		lastRequestAt[player] = nowClock
		if ensureTodayVisit(player) then
			pushState(player)
		end
	end)

	claimRemote.OnServerEvent:Connect(function(player: Player)
		claimToday(player)
	end)

	panelOpenedRemote.OnServerEvent:Connect(function(player: Player)
		if validLoadedProfile(player) then
			emitCustom(player, "DailyRewardsPanelOpened", 1)
		end
	end)

	Players.PlayerAdded:Connect(onPlayerReady)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerReady(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		claimBusy[player] = nil
		lastClaimAt[player] = nil
		lastRequestAt[player] = nil
	end)

	-- Si un joueur reste connecté pendant le changement de journée UTC, avancer le streak
	-- sans exiger de reconnexion et rendre le nouveau reward disponible.
	task.spawn(function()
		local observedDay = todayKey()
		while started do
			task.wait(15)
			local currentDay = todayKey()
			if currentDay ~= observedDay then
				observedDay = currentDay
				for _, player in ipairs(Players:GetPlayers()) do
					if validLoadedProfile(player) then
						ensureTodayVisit(player)
						pushState(player)
					end
				end
			end
		end
	end)

	if RunService:IsStudio() then
		_G.DailyRewardsShowState = function(player: Player?)
			local p = player or Players:GetPlayers()[1]
			if not p then
				print("[DailyRewards] no player")
				return
			end
			local profile = validLoadedProfile(p)
			if not profile then
				print("[DailyRewards] profile unavailable")
				return
			end
			local public = DailyRewardsLogic.SerializePublicState(profile.DailyRewards, todayKey())
			print(
				"[DailyRewards]",
				p.Name,
				"streak=", public.Streak,
				"day=", public.CycleDay,
				"canClaim=", public.CanClaim,
				"shirt=", public.ShirtUnlocked
			)
		end

		-- Outil Studio volontairement explicite pour tester J7 sans attendre une semaine.
		_G.DailyRewardsStudioSetNextStreak = function(targetStreak: number, player: Player?)
			local p = player or Players:GetPlayers()[1]
			if not p then
				return false
			end
			local profile = validLoadedProfile(p)
			if not profile then
				return false
			end
			targetStreak = math.clamp(math.floor(tonumber(targetStreak) or 1), 1, 1000)
			local key = todayKey()
			local state = DailyRewardsLogic.NormalizeState(profile.DailyRewards)
			state.Streak = math.max(0, targetStreak - 1)
			state.LastVisitDayKey = key - 1
			state.LastClaimDayKey = math.min(state.LastClaimDayKey, key - 1)
			persistState(profile, state)
			ensureTodayVisit(p)
			pushState(p)
			return true
		end
	end
end

start()
