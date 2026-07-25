--!strict
-- Compteur communautaire mondial : accumulation locale, écriture DataStore
-- groupée, diffusion inter-serveurs via MessagingService.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local store = DataStoreService:GetDataStore("BPW_Global_v1")
local KEY = "TotalPops"

local GlobalCounterService = {}
local pending = 0
local cached = 0

function GlobalCounterService.Add(amount: number)
	pending += amount
end

function GlobalCounterService.Get(): number
	return cached + pending
end

local function flush()
	if pending <= 0 then return end
	local delta = pending
	pending = 0
	local ok, result = pcall(function()
		return store:IncrementAsync(KEY, delta)
	end)
	if ok and type(result) == "number" then
		cached = result
		pcall(function()
			MessagingService:PublishAsync(Config.Global.Topic, { total = cached })
		end)
		Remotes.Event("GlobalCounter"):FireAllClients(cached, Config.Global.Target)
	else
		pending += delta -- on ne perd rien, on réessaiera
	end
end

function GlobalCounterService.Start()
	local ok, value = pcall(function() return store:GetAsync(KEY) end)
	cached = if ok and type(value) == "number" then value else 0

	pcall(function()
		MessagingService:SubscribeAsync(Config.Global.Topic, function(message)
			local data = message.Data
			if type(data) == "table" and type(data.total) == "number" and data.total > cached then
				cached = data.total
				Remotes.Event("GlobalCounter"):FireAllClients(cached, Config.Global.Target)
			end
		end)
	end)
	Players.PlayerAdded:Connect(function(player)
		Remotes.Event("GlobalCounter"):FireClient(player, cached, Config.Global.Target)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Global.FlushInterval)
			flush()
		end
	end)

	game:BindToClose(flush)
end

return GlobalCounterService
