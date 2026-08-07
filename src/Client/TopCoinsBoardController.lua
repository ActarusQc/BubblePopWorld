--!strict
-- Client : peint les 3 tableaux hub (Coins / Weekly / Levels) via LeaderboardUpdate.
-- Une seule connexion RemoteEvent ; le serveur reste autoritaire.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local HubDisplaysLogic = require(Shared.HubDisplaysLogic)
local HubDisplaysLayout = require(Shared.HubDisplaysLayout)
local HubBoardGui = require(Shared.HubBoardGui)

local TopCoinsBoardController = {}

local connected = false
local lastByRole: {
	Coins: { entries: any?, mode: string, subtitle: string? },
	WeeklyBest: { entries: any?, mode: string, subtitle: string? },
	Levels: { entries: any?, mode: string, subtitle: string? },
} = {
	Coins = { entries = nil, mode = "loading", subtitle = "Global · Top 10" },
	WeeklyBest = { entries = nil, mode = "loading", subtitle = nil },
	Levels = { entries = nil, mode = "loading", subtitle = "Global · Top 10" },
}

local function log(...: any)
	print("[HubBoards]", ...)
end

local function findAnchor(role: string): BasePart?
	local spec = HubDisplaysLayout.SpecByRole(role :: any)
	if not spec then
		return nil
	end
	local world = Workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	if hub then
		local named = hub:FindFirstChild(spec.Name, true)
		local part = HubDisplaysLogic.AsBasePart(named)
		if part then
			return part
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(spec.Tag)) do
		local part = HubDisplaysLogic.AsBasePart(inst)
		if part and (part.Name == spec.Name or part:GetAttribute("BPW_LeaderboardRole") == role) then
			return part
		end
	end
	return nil
end

local function titleFor(role: string): string
	if role == "Coins" then
		return L10n.TopCoinCollectors or "TOP COIN COLLECTORS"
	elseif role == "WeeklyBest" then
		return L10n.HubWeeklyBestTitle or "WEEKLY BEST"
	end
	return L10n.HighestLevelsTitle or "HIGHEST LEVELS"
end

local function kindFor(role: string): HubBoardGui.ValueKind
	if role == "Coins" then
		return "Coins"
	elseif role == "WeeklyBest" then
		return "WeeklyBest"
	end
	return "Levels"
end

local function emptyText(role: string): string
	if role == "WeeklyBest" then
		return L10n.NoWeeklyScoresYet or "No weekly scores yet"
	elseif role == "Levels" then
		return L10n.NoLevelRankingsYet or "No level rankings yet"
	end
	return L10n.NoRankingsYet or "No rankings yet"
end

local function unavailText(role: string): string
	if role == "WeeklyBest" then
		return L10n.WeeklyLeaderboardUnavailable or L10n.LeaderboardUnavailable or "Unavailable"
	elseif role == "Levels" then
		return L10n.LevelLeaderboardUnavailable or L10n.LeaderboardUnavailable or "Unavailable"
	end
	return L10n.LeaderboardUnavailable or "Unavailable"
end

local function paintRole(role: string)
	local bag = lastByRole[role]
	if not bag then
		return
	end
	local surface = findAnchor(role)
	if not surface then
		return
	end
	local spec = HubDisplaysLayout.SpecByRole(role :: any)
	if not spec then
		return
	end
	local theme = HubBoardGui.ThemeFromSpec(spec)
	local mode = bag.mode
	if mode ~= "loading" and mode ~= "empty" and mode ~= "ready" and mode ~= "unavailable" then
		mode = "ready"
	end
	local n = HubBoardGui.PaintAnchor(
		surface,
		spec.GuiName,
		titleFor(role),
		bag.entries,
		mode :: any,
		kindFor(role),
		theme,
		bag.subtitle,
		emptyText(role),
		unavailText(role)
	)
	log("paint", role, "mode=", mode, "rows=", n, "dualFaces=2")
end

local function applyPayload(payload: any)
	if type(payload) ~= "table" then
		return
	end

	if type(payload.Coins) == "table" then
		local entries = payload.Coins.Entries
		if type(entries) == "table" then
			lastByRole.Coins.entries = entries
			lastByRole.Coins.mode = if #entries == 0 then "empty" else "ready"
			paintRole("Coins")
		end
	end

	if type(payload.WeeklyBest) == "table" then
		local entries = payload.WeeklyBest.Entries
		local weekKey = payload.WeeklyBest.WeekKey
		if type(weekKey) == "string" and weekKey ~= "" then
			lastByRole.WeeklyBest.subtitle = (L10n.WeekLabel or "Week") .. " " .. weekKey .. " · Top 10"
		end
		if type(entries) == "table" then
			lastByRole.WeeklyBest.entries = entries
			lastByRole.WeeklyBest.mode = if #entries == 0 then "empty" else "ready"
			paintRole("WeeklyBest")
		end
	end

	if type(payload.Levels) == "table" then
		local entries = payload.Levels.Entries
		if type(entries) == "table" then
			lastByRole.Levels.entries = entries
			lastByRole.Levels.mode = if #entries == 0 then "empty" else "ready"
			paintRole("Levels")
		end
	end
end

function TopCoinsBoardController.Start()
	if connected then
		return
	end
	connected = true
	log("Start")

	for _, role in ipairs({ "Coins", "WeeklyBest", "Levels" }) do
		paintRole(role)
	end

	Remotes.Event("LeaderboardUpdate").OnClientEvent:Connect(function(payload)
		local ok, err = pcall(applyPayload, payload)
		if not ok then
			warn("[HubBoards] payload error:", err)
		end
	end)

	task.spawn(function()
		for i = 1, 25 do
			task.wait(1)
			for _, role in ipairs({ "Coins", "WeeklyBest", "Levels" }) do
				local bag = lastByRole[role]
				if bag and bag.mode == "loading" and i >= 10 then
					bag.mode = "unavailable"
				end
				paintRole(role)
			end
		end
	end)

	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") and (
			inst.Name == "LeftLeaderboardAnchor"
			or inst.Name == "CenterLeaderboardAnchor"
			or inst.Name == "RightLeaderboardAnchor"
		) then
			task.defer(function()
				for _, role in ipairs({ "Coins", "WeeklyBest", "Levels" }) do
					paintRole(role)
				end
			end)
		end
	end)
end

return TopCoinsBoardController
