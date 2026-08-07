--!strict
-- Runtime : trouve les ancrages Studio et peind les SurfaceGui dual-face.
-- JAMAIS CFrame / Size / Parent / Orientation sur un ancrage existant.
-- DataStores n'empêchent jamais la création visuelle (Loading immédiat).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubDisplaysLayout = require(Shared.HubDisplaysLayout)
local HubDisplaysLogic = require(Shared.HubDisplaysLogic)
local HubBoardGui = require(Shared.HubBoardGui)
local L10n = require(Shared.LocalizationStrings)
local Config = require(Shared.GameConfig)

local HubDisplaysService = {}

local ADORN_NAME = "BPW_DebugLeaderboardAdornment"
local serviceInitialized = false
local startCount = 0

local function studioLog(...: any)
	if RunService:IsStudio() then
		print("[HubDisplays]", ...)
	end
end

local function logTrace(msg: string, err: any)
	warn("[HubDisplays]", msg, err)
	warn(debug.traceback())
end

local function getRearFolder(): Folder?
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	local modules = hub and hub:FindFirstChild("Modules")
	local rear = modules and modules:FindFirstChild(HubDisplaysLayout.REAR_FOLDER)
	if rear and rear:IsA("Folder") then
		return rear
	end
	return nil
end

local function findPlatform(): Model?
	local rear = getRearFolder()
	if rear then
		local m = rear:FindFirstChild(HubDisplaysLayout.PLATFORM_NAME)
		if m and m:IsA("Model") then
			return m
		end
	end
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	if hub then
		for _, d in ipairs(hub:GetDescendants()) do
			if d:IsA("Model") and d.Name == HubDisplaysLayout.PLATFORM_NAME then
				return d
			end
		end
	end
	return nil
end

local function findHubDisplaysFolder(): Folder?
	local rear = getRearFolder()
	if not rear then
		return nil
	end
	local f = rear:FindFirstChild(HubDisplaysLayout.FOLDER_NAME)
	if f and f:IsA("Folder") then
		return f
	end
	return nil
end

local function isDebugEnabled(): boolean
	local folder = findHubDisplaysFolder()
	if folder and folder:GetAttribute(HubDisplaysLayout.DEBUG_ATTR) == true then
		return true
	end
	return Config.Hub and Config.Hub.DebugLeaderboardAnchors == true
end

local function clearDebugAdornments(part: BasePart)
	for _, child in ipairs(part:GetChildren()) do
		if child.Name == ADORN_NAME then
			child:Destroy()
		end
	end
end

local function ensureDebugAdornment(part: BasePart, color: Color3)
	clearDebugAdornments(part)
	local adorn = Instance.new("BoxHandleAdornment")
	adorn.Name = ADORN_NAME
	adorn.Adornee = part
	adorn.AlwaysOnTop = true
	adorn.ZIndex = 10
	adorn.Size = part.Size
	adorn.Color3 = color
	adorn.Transparency = 0.35
	adorn.Parent = part
	studioLog("debug adornment created:", part.Name)
end

-- Physique seulement — JAMAIS CFrame/Size.
local function applyRuntimePhysicsOnly(part: BasePart, debugVisible: boolean, debugColor: Color3)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	-- Adornee SurfaceGui : Part toujours invisible (jamais DebugTransparency 0.35).
	part.Transparency = HubDisplaysLayout.RuntimeTransparency()
	if debugVisible then
		part.Color = debugColor
		ensureDebugAdornment(part, debugColor)
	else
		clearDebugAdornments(part)
	end
end

local function applyTags(part: BasePart, spec: HubDisplaysLayout.AnchorSpec)
	part:SetAttribute(HubDisplaysLayout.ROLE_ATTR, spec.Role)
	part:SetAttribute("BPW_HubLeaderboard", true)
	part:SetAttribute("BPW_Rows", HubDisplaysLogic.TOP_N)
	part:SetAttribute("BPW_GuiFace", "Front+Back")
	part:SetAttribute(HubDisplaysLayout.MANUAL_ATTR, true)
	if not CollectionService:HasTag(part, HubDisplaysLayout.ANCHOR_TAG) then
		CollectionService:AddTag(part, HubDisplaysLayout.ANCHOR_TAG)
	end
	if not CollectionService:HasTag(part, spec.Tag) then
		CollectionService:AddTag(part, spec.Tag)
	end
	if spec.Role == "Coins" then
		part:SetAttribute("BPW_TopCoinsBoard", true)
	elseif spec.Role == "WeeklyBest" then
		part:SetAttribute("BPW_WeeklyBestScoreBoard", true)
		part:SetAttribute("BPW_WeeklyBestBoard", true)
	elseif spec.Role == "Levels" then
		part:SetAttribute("BPW_HighestLevelsBoard", true)
	end
end

local function buildShellGui(part: BasePart, spec: HubDisplaysLayout.AnchorSpec)
	local title = if spec.TitleKey == "TopCoinCollectors"
		then (L10n.TopCoinCollectors or "TOP COIN COLLECTORS")
		elseif spec.TitleKey == "HighestLevelsTitle"
		then (L10n.HighestLevelsTitle or "HIGHEST LEVELS")
		else (L10n.HubWeeklyBestTitle or "WEEKLY BEST")
	local theme = HubBoardGui.ThemeFromSpec(spec)
	local subtitle = if spec.Role == "WeeklyBest" then "" else "Global · Top 10"
	local kind: HubBoardGui.ValueKind = if spec.Role == "Coins"
		then "Coins"
		elseif spec.Role == "WeeklyBest"
		then "WeeklyBest"
		else "Levels"

	studioLog("creating board gui:", part.Name, "baseName=", spec.GuiName)

	local ok, err = pcall(function()
		local dual = HubBoardGui.EnsureDualBoard(part, spec.GuiName, title, theme, subtitle)
		studioLog("SurfaceGui parent=", dual.Front.Parent and dual.Front.Parent:GetFullName() or "nil")
		studioLog("SurfaceGui adornee=", dual.Front.Adornee and dual.Front.Adornee:GetFullName() or "nil")
		studioLog("SurfaceGui face= Front + Back")
		for _, faceGui in ipairs({ dual.Front, dual.Back }) do
			studioLog(
				"  ",
				faceGui.Name,
				"Enabled=",
				faceGui.Enabled,
				"Face=",
				faceGui.Face.Name,
				"Adornee=",
				faceGui.Adornee and faceGui.Adornee.Name or "nil",
				"LightInfluence=",
				faceGui.LightInfluence,
				"AlwaysOnTop=",
				faceGui.AlwaysOnTop
			)
		end
		local n = HubBoardGui.PaintAnchor(
			part,
			spec.GuiName,
			title,
			nil,
			"loading",
			kind,
			theme,
			subtitle,
			nil,
			nil
		)
		studioLog("board state=Loading")
		studioLog("rows rendered=", n, "(loading placeholder)")
		local count = HubBoardGui.CountBoardSurfaceGuis(part, spec.GuiName)
		studioLog("SurfaceGuis on anchor=", count, "(expect 2)")
	end)
	if not ok then
		logTrace("buildShellGui failed for " .. part.Name, err)
	end
end

local function logTripoDiagnostics(platform: Model?, anchors: { [string]: BasePart })
	if not RunService:IsStudio() then
		return
	end
	if platform then
		local shadowOn = 0
		for _, d in ipairs(platform:GetDescendants()) do
			if d:IsA("BasePart") and (d :: BasePart).CastShadow then
				shadowOn += 1
			end
		end
		studioLog("Tripo path=", platform:GetFullName())
		studioLog("Tripo meshparts CastShadow still true:", shadowOn, "(expect 0)")
	end
	local tripoPos = if platform then platform:GetPivot().Position else nil
	for _, name in ipairs({ "LeftLeaderboardAnchor", "CenterLeaderboardAnchor", "RightLeaderboardAnchor" }) do
		local p = anchors[name]
		if p then
			studioLog(name, "Position=", tostring(p.Position), "Size=", tostring(p.Size))
			if tripoPos then
				local d = HubDisplaysLayout.DistanceXZ(p.Position, tripoPos)
				studioLog("distance", name, "to Tripo=", string.format("%.2f", d))
			end
		else
			studioLog(name, "missing")
		end
	end
end

--- Résout les 3 ancrages déjà présents en Studio. Ne crée rien.
function HubDisplaysService.FindExistingAnchors(verbose: boolean?): {
	Folder: Folder?,
	Left: BasePart?,
	Center: BasePart?,
	Right: BasePart?,
	Missing: { string },
}
	local talk = verbose == true
	local missing: { string } = {}
	local folder = findHubDisplaysFolder()
	local out = {
		Folder = folder,
		Left = nil :: BasePart?,
		Center = nil :: BasePart?,
		Right = nil :: BasePart?,
		Missing = missing,
	}
	for _, spec in ipairs(HubDisplaysLayout.ANCHORS) do
		local found: BasePart? = nil
		if folder then
			local child = folder:FindFirstChild(spec.Name)
			if child and child:IsA("BasePart") then
				found = child
			end
		end
		if not found then
			local world = workspace:FindFirstChild("BubblePopWorld")
			local hub = world and world:FindFirstChild("CentralHub")
			if hub then
				local named = hub:FindFirstChild(spec.Name, true)
				if named and named:IsA("BasePart") then
					found = named
				end
			end
		end
		if found then
			if talk then
				studioLog("anchor found:", found.Name, found:GetFullName())
			end
			if spec.Name == "LeftLeaderboardAnchor" then
				out.Left = found
			elseif spec.Name == "CenterLeaderboardAnchor" then
				out.Center = found
			else
				out.Right = found
			end
		else
			table.insert(missing, spec.Name)
			if talk then
				studioLog("anchor NOT found:", spec.Name)
			end
		end
	end
	return out
end

function HubDisplaysService.FindAnchor(role: HubDisplaysLayout.BoardRole): BasePart?
	local found = HubDisplaysService.FindExistingAnchors()
	if role == "Coins" then
		return found.Left
	elseif role == "WeeklyBest" then
		return found.Center
	end
	return found.Right
end

function HubDisplaysService.GetDisplaysFolder(): Folder?
	return findHubDisplaysFolder()
end

function HubDisplaysService.CountDebugAdornments(): number
	local folder = findHubDisplaysFolder()
	if not folder then
		return 0
	end
	local n = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d.Name == ADORN_NAME and d:IsA("BoxHandleAdornment") then
			n += 1
		end
	end
	return n
end

local function forceRefreshDataServices()
	local ok1, err1 = pcall(function()
		require(script.Parent.LeaderboardService).ForceRefresh()
	end)
	if not ok1 then
		logTrace("LeaderboardService.ForceRefresh", err1)
	end
	local ok2, err2 = pcall(function()
		require(script.Parent.WeeklyBestService).ForceRefresh()
	end)
	if not ok2 then
		logTrace("WeeklyBestService.ForceRefresh", err2)
	end
	local ok3, err3 = pcall(function()
		require(script.Parent.LevelLeaderboardService).ForceRefresh()
	end)
	if not ok3 then
		logTrace("LevelLeaderboardService.ForceRefresh", err3)
	end
end

--- Bind SurfaceGui + tags. Zéro mouvement géométrie. Loading immédiat.
function HubDisplaysService.BindExistingAnchors(): boolean
	studioLog("BindExistingAnchors started")
	local found = HubDisplaysService.FindExistingAnchors(true)
	if found.Folder then
		studioLog("HubDisplays folder:", found.Folder:GetFullName())
	else
		studioLog("HubDisplays folder missing — use plugin Create Missing Display Anchors")
	end

	if #found.Missing > 0 then
		warn(
			"[HubDisplays] ANCRAGES MANQUANTS (Studio-owned). Plugin: Create Missing Display Anchors. Missing=",
			table.concat(found.Missing, ", ")
		)
	end

	local debugVisible = isDebugEnabled()
	studioLog("debug enabled:", debugVisible)

	local map: { [string]: BasePart } = {}
	local pairs_ = {
		{ Found = found.Left, Spec = HubDisplaysLayout.SpecByRole("Coins") },
		{ Found = found.Center, Spec = HubDisplaysLayout.SpecByRole("WeeklyBest") },
		{ Found = found.Right, Spec = HubDisplaysLayout.SpecByRole("Levels") },
	}
	local platform = findPlatform()
	local tripoPos = if platform then platform:GetPivot().Position else nil

	for _, entry in ipairs(pairs_) do
		local part = entry.Found
		local spec = entry.Spec
		if part and spec then
			if tripoPos and HubDisplaysLayout.IsAnchorTooFarFromTripo(part.Position, tripoPos)
				and part:GetAttribute(HubDisplaysLayout.MANUAL_ATTR) ~= true
			then
				warn("[HubDisplays] destroying far non-manual anchor:", part:GetFullName())
				part:Destroy()
				continue
			end
			-- INTENTIONNELLEMENT aucune écriture CFrame / Size / Parent.
			local okPhys, errPhys = pcall(function()
				applyRuntimePhysicsOnly(part, debugVisible, spec.DebugColor)
				applyTags(part, spec)
			end)
			if not okPhys then
				logTrace("physics/tags " .. part.Name, errPhys)
			end
			buildShellGui(part, spec)
			map[spec.Name] = part
			studioLog(string.format(
				"anchor ready (studio pose kept): %s Position=(%.2f, %.2f, %.2f) Size=(%.2f, %.2f, %.2f)",
				part.Name,
				part.Position.X,
				part.Position.Y,
				part.Position.Z,
				part.Size.X,
				part.Size.Y,
				part.Size.Z
			))
		end
	end

	logTripoDiagnostics(platform, map)
	local remaining = HubDisplaysService.FindExistingAnchors()
	local allOk = #remaining.Missing == 0
	if allOk then
		task.defer(forceRefreshDataServices)
	end
	studioLog("BindExistingAnchors completed allBound=", allOk)
	return allOk
end

function HubDisplaysService.EnsureAnchors(): boolean
	return HubDisplaysService.BindExistingAnchors()
end

function HubDisplaysService.SetDebugVisible(visible: boolean)
	local folder = findHubDisplaysFolder()
	if folder then
		folder:SetAttribute(HubDisplaysLayout.DEBUG_ATTR, visible)
	end
	HubDisplaysService.BindExistingAnchors()
	studioLog("debug enabled:", visible)
end

function HubDisplaysService.ValidateStructure(): boolean
	local found = HubDisplaysService.FindExistingAnchors()
	if #found.Missing > 0 then
		return false
	end
	for _, pair in ipairs({
		{ part = found.Left, name = "CoinsLeaderboardGui" },
		{ part = found.Center, name = "WeeklyBestGui" },
		{ part = found.Right, name = "LevelsLeaderboardGui" },
	}) do
		if pair.part and HubBoardGui.CountBoardSurfaceGuis(pair.part, pair.name) < 2 then
			return false
		end
	end
	return true
end

function HubDisplaysService.GetStartCount(): number
	return startCount
end

function HubDisplaysService.Start()
	startCount += 1
	if serviceInitialized then
		studioLog("Start ignored (already initialized once)")
		return
	end
	serviceInitialized = true
	studioLog("Init started")
	studioLog("mode=Studio-owned anchors only (no runtime placement)")

	task.spawn(function()
		local ok, err = pcall(function()
			for i = 1, 40 do
				if HubDisplaysService.BindExistingAnchors() then
					studioLog("BindExistingAnchors success after attempt", i)
					studioLog("Init completed")
					return
				end
				task.wait(0.5)
			end
			warn("[HubDisplays] anchors still missing after retries — place with Studio plugin")
			studioLog("Init completed (partial — missing anchors)")
		end)
		if not ok then
			logTrace("Init failed", err)
		end
	end)
end

return HubDisplaysService
