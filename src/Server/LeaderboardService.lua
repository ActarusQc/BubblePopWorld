--!strict
-- Classements mondiaux via OrderedDataStore + panneau Top 10 dans le lobby.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local BOARDS = {
	{ Id = "Pops",  Label = "Bubbles popped", Store = DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName("Pops")),  Field = "Pops" },
	{ Id = "Level", Label = "Level",          Store = DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName("Level")), Field = "Level" },
	{ Id = "Coins", Label = "Wealth",         Store = DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName("Coins")), Field = "Coins" },
}

-- Classement principal affiché sur le panneau lobby.
local PRIMARY_BOARD = "Coins"

local LeaderboardService = {}
local cache: { [string]: any } = {}

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

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

local function findLobbyBoard(): Frame?
	local root = workspace:FindFirstChild("BubblePopWorld")
	if not root then
		return nil
	end
	local lobby = root:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	local decor = lobby:FindFirstChild("LobbyDecor")
	local board = (decor and decor:FindFirstChild("LeaderboardBoard"))
		or lobby:FindFirstChild("LeaderboardBoard", true)
	if not (board and board:IsA("BasePart")) then
		return nil
	end
	local gui = board:FindFirstChild("LeaderboardGui")
	if not (gui and gui:IsA("SurfaceGui")) then
		return nil
	end
	local list = gui:FindFirstChild("List")
	if list and list:IsA("Frame") then
		return list
	end
	return nil
end

local function updateWorldBoard()
	local list = findLobbyBoard()
	if not list then
		return
	end

	local boardData = cache[PRIMARY_BOARD]
	local entries = if boardData then boardData.Entries else nil
	for i = 1, 10 do
		local row = list:FindFirstChild("Row" .. tostring(i))
		if not (row and row:IsA("Frame")) then
			continue
		end
		local rankLabel = row:FindFirstChild("Rank")
		local nameLabel = row:FindFirstChild("Name")
		local valueLabel = row:FindFirstChild("Value")
		local entry = if entries then entries[i] else nil
		if entry then
			if rankLabel and rankLabel:IsA("TextLabel") then
				rankLabel.Text = "#" .. tostring(entry.Rank)
			end
			if nameLabel and nameLabel:IsA("TextLabel") then
				nameLabel.Text = tostring(entry.Name)
			end
			if valueLabel and valueLabel:IsA("TextLabel") then
				valueLabel.Text = comma(entry.Value) .. " coins"
			end
		else
			if rankLabel and rankLabel:IsA("TextLabel") then
				rankLabel.Text = "#" .. tostring(i)
			end
			if nameLabel and nameLabel:IsA("TextLabel") then
				nameLabel.Text = "—"
			end
			if valueLabel and valueLabel:IsA("TextLabel") then
				valueLabel.Text = "—"
			end
		end
	end
end

local function refresh()
	local result = {}
	for _, board in ipairs(BOARDS) do
		local ok, pages = pcall(function()
			return board.Store:GetSortedAsync(false, 10)
		end)
		if ok and pages then
			local entries = {}
			for rank, entry in ipairs(pages:GetCurrentPage()) do
				local name = "Joueur " .. tostring(entry.key)
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
	updateWorldBoard()
end

function LeaderboardService.GetCache()
	return cache
end

-- Retire un joueur de tous les classements (réinitialisation admin).
function LeaderboardService.RemoveEntry(userId: number)
	for _, board in ipairs(BOARDS) do
		local ok, err = pcall(function()
			board.Store:RemoveAsync(tostring(userId))
		end)
		if not ok then
			warn(("[LeaderboardService] retrait %s impossible pour %d : %s"):format(board.Id, userId, tostring(err)))
		end
	end
end

function LeaderboardService.RefreshWorldBoard()
	updateWorldBoard()
end

function LeaderboardService.Start()
	Players.PlayerRemoving:Connect(publish)
	Players.PlayerAdded:Connect(function(player)
		task.wait(3)
		Remotes.Event("LeaderboardUpdate"):FireClient(player, cache)
		updateWorldBoard()
	end)

	task.spawn(function()
		-- Laisse ZoneService créer le panneau lobby.
		task.wait(2)
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
