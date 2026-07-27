--!strict
-- Accès par niveau aux zones gateées : PhysicsService + groupes de collision.
-- Niveau autoritaire : DataService.GetPlayerLevel (même source que le HUD via StatsUpdate).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneDefs = require(Shared.ZoneDefs)
local L10n = require(Shared.LocalizationStrings)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local ZoneAccess = {}

-- Logs Studio temporaires (diagnostic accès Summer). Remettre false après validation.
local DEBUG_SUMMER_ACCESS = RunService:IsStudio()

local GATE_NOTIFY_COOLDOWN = 2.5
local lastGateNotify: { [Player]: number } = {}
local groupsReady = false
local gatePartsByZone: { [string]: { BasePart } } = {}
local previousLevel: { [Player]: number } = {}
local characterBound: { [Model]: boolean } = {}
local playerBound: { [Player]: boolean } = {}
local descendantConns: { [Model]: RBXScriptConnection } = {}

local function ensureGroup(name: string)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end

local function debugAccess(player: Player, playerLevel: number, requiredLevel: number, canEnter: boolean)
	if not DEBUG_SUMMER_ACCESS then
		return
	end
	print(
		"[SummerZoneAccess]",
		player.Name,
		"Level:",
		playerLevel,
		"Required:",
		requiredLevel,
		"CanEnter:",
		canEnter
	)
end

function ZoneAccess.EnsureCollisionGroups()
	if groupsReady then
		return
	end

	local thresholds = ZoneDefs.GetAccessThresholds()
	for _, t in ipairs(thresholds) do
		ensureGroup(ZoneDefs.GetAccessGroupName(t))
	end

	for _, def in ipairs(ZoneDefs.GetGatedZones()) do
		ensureGroup(ZoneDefs.GateGroupName(def.Id))
	end

	-- Matrice : Access_L collisionne Gate_Z ssi L < RequiredLevel(Z)
	-- ⇒ canEnter iff playerLevel >= RequiredLevel (groupe Access au palier atteint).
	for _, t in ipairs(thresholds) do
		local accessName = ZoneDefs.GetAccessGroupName(t)
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(accessName, "Default", true)
		end)
		for _, other in ipairs(thresholds) do
			local otherName = ZoneDefs.GetAccessGroupName(other)
			pcall(function()
				PhysicsService:CollisionGroupSetCollidable(accessName, otherName, true)
			end)
		end
		for _, def in ipairs(ZoneDefs.GetGatedZones()) do
			local gateName = ZoneDefs.GateGroupName(def.Id)
			local collides = t < def.RequiredLevel
			pcall(function()
				PhysicsService:CollisionGroupSetCollidable(accessName, gateName, collides)
			end)
		end
	end

	for _, def in ipairs(ZoneDefs.GetGatedZones()) do
		local gateName = ZoneDefs.GateGroupName(def.Id)
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(gateName, "Default", true)
		end)
	end

	groupsReady = true
end

function ZoneAccess.RegisterGatePart(zoneId: string, part: BasePart)
	ZoneAccess.EnsureCollisionGroups()
	local group = ZoneDefs.GateGroupName(zoneId)
	part.CollisionGroup = group
	gatePartsByZone[zoneId] = gatePartsByZone[zoneId] or {}
	-- Évite les doublons si Rebuild recree la porte.
	local list = gatePartsByZone[zoneId]
	for i = #list, 1, -1 do
		if list[i] == part or list[i].Parent == nil then
			table.remove(list, i)
		end
	end
	table.insert(list, part)
end

local function setCharacterGroup(char: Model, groupName: string)
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = groupName
		end
	end
end

function ZoneAccess.GetPlayerLevel(player: Player): number
	return DataService.GetPlayerLevel(player)
end

function ZoneAccess.CanPlayerEnter(player: Player, zoneId: string): boolean
	return ZoneDefs.CanLevelEnter(ZoneAccess.GetPlayerLevel(player), zoneId)
end

local function updateAccessAttributes(player: Player, level: number)
	player:SetAttribute("PlayerLevel", level)
	for _, def in ipairs(ZoneDefs.GetGatedZones()) do
		local canEnter = ZoneDefs.CanLevelEnter(level, def.Id)
		player:SetAttribute("CanEnter_" .. def.Id, canEnter)
	end
end

function ZoneAccess.ApplyToCharacter(player: Player, char: Model?)
	ZoneAccess.EnsureCollisionGroups()
	local character = char or player.Character
	if not character then
		return
	end

	local level = ZoneAccess.GetPlayerLevel(player)
	local groupName = ZoneDefs.GetAccessGroupName(level)
	previousLevel[player] = level
	updateAccessAttributes(player, level)

	-- DescendantAdded d'abord : accessoires / sac ajoutés pendant GetDescendants.
	if not characterBound[character] then
		characterBound[character] = true
		local conn = character.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				desc.CollisionGroup = ZoneDefs.GetAccessGroupName(ZoneAccess.GetPlayerLevel(player))
			end
		end)
		descendantConns[character] = conn
		character.Destroying:Connect(function()
			characterBound[character] = nil
			local c = descendantConns[character]
			if c then
				c:Disconnect()
				descendantConns[character] = nil
			end
		end)
	end

	setCharacterGroup(character, groupName)

	local summerReq = ZoneDefs.GetRequiredLevel("SummerZone")
	debugAccess(player, level, summerReq, level >= summerReq)
end

function ZoneAccess.RefreshPlayer(player: Player)
	ZoneAccess.EnsureCollisionGroups()
	local level = ZoneAccess.GetPlayerLevel(player)
	local prev = previousLevel[player]
	previousLevel[player] = level
	updateAccessAttributes(player, level)

	if player.Character then
		ZoneAccess.ApplyToCharacter(player, player.Character)
	end

	-- Déverrouillage immédiat (passage de niveau pendant la partie)
	if prev and level > prev then
		for _, def in ipairs(ZoneDefs.GetGatedZones()) do
			if prev < def.RequiredLevel and level >= def.RequiredLevel then
				Remotes.Event("Announce"):FireClient(
					player,
					string.format(L10n.ZoneUnlockedFmt, def.DisplayName),
					"world"
				)
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local spark = Instance.new("Part")
					spark.Name = "ZoneUnlockFx"
					spark.Anchored = true
					spark.CanCollide = false
					spark.CanQuery = false
					spark.CanTouch = false
					spark.Material = Enum.Material.Neon
					spark.Color = Color3.fromRGB(255, 220, 90)
					spark.Size = Vector3.new(1, 1, 1)
					spark.Transparency = 0.2
					spark.CFrame = hrp.CFrame
					spark.Parent = workspace
					local light = Instance.new("PointLight")
					light.Brightness = 2
					light.Range = 16
					light.Color = Color3.fromRGB(255, 230, 120)
					light.Parent = spark
					task.delay(0.9, function()
						spark:Destroy()
					end)
				end
			end
		end
	end
end

function ZoneAccess.NotifyBlocked(player: Player, zoneId: string)
	local now = os.clock()
	local last = lastGateNotify[player]
	if last and now - last < GATE_NOTIFY_COOLDOWN then
		return
	end
	lastGateNotify[player] = now

	local required = ZoneDefs.GetRequiredLevel(zoneId)
	local level = ZoneAccess.GetPlayerLevel(player)
	Remotes.Event("Announce"):FireClient(
		player,
		string.format(L10n.ZoneLockedFmt, required, level, required),
		"zone_locked"
	)
end

function ZoneAccess.BindGateTouch(zoneId: string, gatePart: BasePart)
	gatePart.CanTouch = true
	gatePart.Touched:Connect(function(hit)
		local char = hit.Parent
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then
			-- Accessoire : remonter au modèle personnage
			local model = hit:FindFirstAncestorOfClass("Model")
			if not model then
				return
			end
			char = model
			hum = char:FindFirstChildOfClass("Humanoid")
			if not hum then
				return
			end
		end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then
			return
		end
		if not ZoneAccess.CanPlayerEnter(player, zoneId) then
			ZoneAccess.NotifyBlocked(player, zoneId)
		end
	end)
end

local function waitForProfile(player: Player, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 10)
	while not DataService.Get(player) and os.clock() < deadline do
		task.wait()
	end
	return DataService.Get(player) ~= nil
end

local function bindPlayer(player: Player)
	if playerBound[player] then
		return
	end
	playerBound[player] = true

	player.CharacterAdded:Connect(function(char)
		task.spawn(function()
			waitForProfile(player, 10)
			ZoneAccess.ApplyToCharacter(player, char)
		end)
	end)

	if player.Character then
		task.spawn(function()
			waitForProfile(player, 10)
			ZoneAccess.ApplyToCharacter(player, player.Character)
		end)
	else
		task.defer(function()
			if waitForProfile(player, 10) then
				ZoneAccess.RefreshPlayer(player)
			end
		end)
	end
end

function ZoneAccess.Start()
	ZoneAccess.EnsureCollisionGroups()

	Players.PlayerAdded:Connect(bindPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastGateNotify[player] = nil
		previousLevel[player] = nil
		playerBound[player] = nil
	end)
end

return ZoneAccess
