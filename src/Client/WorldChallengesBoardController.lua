--!strict
-- Client : remplit le ChallengesBoard 3D avec les défis du joueur local (ChallengeState).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)
local ChallengeBoardUtil = require(Shared.ChallengeBoardUtil)

local WorldChallengesBoardController = {}

local TAG = "BPW_ChallengesBoard"
local player = Players.LocalPlayer
local lastState: any = nil
local boundBoard: BasePart? = nil

local function log(...: any)
	print("[WorldChallengesBoard]", ...)
end

local function labelOf(key: string, fallback: string): string
	local v = (L10n :: any)[key]
	if type(v) == "string" and v ~= "" then
		return v
	end
	return fallback
end

local function findBoard(): BasePart?
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") then
			return inst
		end
		if inst:IsA("Model") then
			local face = inst:FindFirstChild("ChallengesDisplay", true)
			if face and face:IsA("BasePart") then
				return face
			end
		end
	end
	local world = Workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	if hub then
		local face = hub:FindFirstChild("ChallengesDisplay", true)
		if face and face:IsA("BasePart") then
			return face
		end
		for _, d in ipairs(hub:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("BPW_ChallengesBoard") == true then
				return d
			end
		end
	end
	return nil
end

local function setText(label: Instance?, text: string, color: Color3?)
	if not (label and label:IsA("TextLabel")) then
		return
	end
	label.Text = text
	if color then
		label.TextColor3 = color
	end
end

local function paintRow(row: Frame?, line: ChallengeBoardUtil.BoardLine?, emptyHint: string?)
	if not row then
		return
	end
	local status = row:FindFirstChild("Status")
	local title = row:FindFirstChild("Title")
	if line then
		row.Visible = true
		local doneColor = Color3.fromRGB(80, 220, 120)
		local openColor = Color3.fromRGB(200, 210, 230)
		setText(status, line.Status, if line.Completed then doneColor else Color3.fromRGB(100, 200, 130))
		local body = string.format("%s  %s", line.Title, line.ProgressText)
		setText(title, body, if line.Completed then doneColor else openColor)
	elseif emptyHint then
		row.Visible = true
		setText(status, "", nil)
		setText(title, emptyHint, Color3.fromRGB(150, 165, 190))
	else
		row.Visible = false
	end
end

local function applyState(state: any)
	lastState = state
	local board = findBoard()
	if not board then
		if boundBoard then
			log("board lost after rebuild — will retry")
		end
		boundBoard = nil
		return
	end
	if boundBoard ~= board then
		boundBoard = board
		log("board found:", board:GetFullName())
	end

	local gui = board:FindFirstChild("ChallengesBoardGui") or board:FindFirstChildWhichIsA("SurfaceGui")
	if not (gui and gui:IsA("SurfaceGui")) then
		warn("[WorldChallengesBoard] SurfaceGui manquant")
		return
	end
	-- Client-local uniquement (ne doit pas dépendre du serveur pour le rendu perso)
	gui.ResetOnSpawn = false

	local root = gui:FindFirstChild("Root")
	if not (root and root:IsA("Frame")) then
		warn("[WorldChallengesBoard] Root manquant")
		return
	end

	if type(state) ~= "table" then
		log("état invalide")
		return
	end

	local dailyLines = ChallengeBoardUtil.BuildDailyLines(state.Daily, labelOf, 2)
	local weeklyLines = ChallengeBoardUtil.BuildWeeklyLines(state.Weekly, labelOf, 3)

	log(
		"paint daily=",
		#dailyLines,
		"weekly=",
		#weeklyLines,
		"player=",
		player.Name
	)

	for i = 1, 2 do
		local row = root:FindFirstChild("Daily" .. tostring(i))
		if row and row:IsA("Frame") then
			paintRow(row, dailyLines[i], if i == 1 and #dailyLines == 0 then (L10n.ChallengesEmpty or "No challenges") else nil)
		end
	end
	for i = 1, 3 do
		local row = root:FindFirstChild("Weekly" .. tostring(i))
		if row and row:IsA("Frame") then
			paintRow(row, weeklyLines[i], if i == 1 and #weeklyLines == 0 then (L10n.HubNoWeeklyChallenge or "No weekly challenge") else nil)
		end
	end
end

function WorldChallengesBoardController.Start()
	log("Start")
	Remotes.Event("ChallengeState").OnClientEvent:Connect(function(payload)
		applyState(payload)
	end)

	-- Demande d'état initiale
	task.defer(function()
		pcall(function()
			Remotes.Event("ChallengeRequestState"):FireServer()
		end)
	end)

	-- Rebind si le hub est reconstruit
	task.spawn(function()
		while true do
			task.wait(2)
			local board = findBoard()
			if board and board ~= boundBoard then
				log("rebind after hub change")
				if lastState then
					applyState(lastState)
				else
					boundBoard = board
					pcall(function()
						Remotes.Event("ChallengeRequestState"):FireServer()
					end)
				end
			elseif lastState and board then
				-- Réapplique si SurfaceGui regénéré (même part)
				local gui = board:FindFirstChildWhichIsA("SurfaceGui")
				local root = gui and gui:FindFirstChild("Root")
				local d1 = root and root:FindFirstChild("Daily1")
				local title = d1 and d1:FindFirstChild("Title")
				if title and title:IsA("TextLabel") then
					local t = title.Text
					if t == "Challenge 1" or t == "Challenge 2" or string.find(t, "Weekly goal", 1, true) then
						applyState(lastState)
					end
				end
			end
		end
	end)

	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart")
			and (inst.Name == "ChallengesDisplay" or inst:GetAttribute("BPW_ChallengesBoard") == true)
		then
			task.defer(function()
				if lastState then
					applyState(lastState)
				end
			end)
		end
	end)
end

return WorldChallengesBoardController
