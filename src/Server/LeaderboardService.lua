--!strict
-- Classements mondiaux via OrderedDataStore.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local BOARDS = {
	{ Id = "Pops",  Label = "Bulles éclatées", Store = DataStoreService:GetOrderedDataStore("BPW_LB_Pops_v1"),  Field = "Pops" },
	{ Id = "Level", Label = "Niveau",          Store = DataStoreService:GetOrderedDataStore("BPW_LB_Level_v1"), Field = "Level" },
	{ Id = "Coins", Label = "Richesse",        Store = DataStoreService:GetOrderedDataStore("BPW_LB_Coins_v1"), Field = "Coins" },
}

local LeaderboardService = {}
local cache = {}

local function publish(player: Player)
	local profile = DataService.Get(player)
	if not profile or not profile.__loaded then return end
	for _, board in ipairs(BOARDS) do
		local value = math.clamp(math.floor(profile[board.Field] or 0), 0, 2 ^ 31 - 1)
		pcall(function()
			board.Store:SetAsync(tostring(player.UserId), value)
		end)
	end
end

local function refresh()
	local result = {}
	for _, board in ipairs(BOARDS) do
		local ok, pages = pcall(function()
			return board.Store:GetSortedAsync(false, 25)
		end)
		if ok then
			local entries = {}
			for rank, entry in ipairs(pages:GetCurrentPage()) do
				local name = "Joueur " .. entry.key
				pcall(function()
					name = Players:GetNameFromUserIdAsync(tonumber(entry.key) or 0)
				end)
				table.insert(entries, { Rank = rank, Name = name, Value = entry.value })
			end
			result[board.Id] = { Label = board.Label, Entries = entries }
		end
	end
	cache = result
	Remotes.Event("LeaderboardUpdate"):FireAllClients(cache)
end

function LeaderboardService.Start()
	Players.PlayerRemoving:Connect(publish)
	Players.PlayerAdded:Connect(function(player)
		task.wait(3)
		Remotes.Event("LeaderboardUpdate"):FireClient(player, cache)
	end)

	task.spawn(function()
		while true do
			pcall(refresh)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(publish, player)
			end
			task.wait(120)
		end
	end)
end

return LeaderboardService
