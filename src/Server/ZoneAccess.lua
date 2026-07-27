--!strict
-- Accès par niveau aux zones gateées : PhysicsService + groupes de collision.
-- Le niveau vient exclusivement de DataService (serveur autoritaire).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneDefs = require(Shared.ZoneDefs)
local L10n = require(Shared.LocalizationStrings)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local ZoneAccess = {}

local GATE_NOTIFY_COOLDOWN = 2.5
local lastGateNotify: { [Player]: number } = {}
local groupsReady = false
local gatePartsByZone: { [string]: { BasePart } } = {}

local function ensureGroup(name: string)
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
	if not ok then
		-- Groupe déjà enregistré
	end
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

	-- Matrice : un joueur au palier Access_L collisionne avec Gate_Z ssi L < RequiredLevel(Z)
	for _, t in ipairs(thresholds) do
		local accessName = ZoneDefs.GetAccessGroupName(t)
		-- Collisions monde / autres joueurs
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

	-- Les portes collisionnent avec Default (sol / décor utile)
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
	table.insert(gatePartsByZone[zoneId], part)
end

local function setCharacterGroup(char: Model, groupName: string)
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = groupName
		end
	end
end

function ZoneAccess.GetPlayerLevel(player: Player): number
	local profile = DataService.Get(player)
	if profile and type(profile.Level) == "number" then
		return profile.Level
	end
	return 1
end

function ZoneAccess.CanPlayerEnter(player: Player, zoneId: string): boolean
	local required = ZoneDefs.GetRequiredLevel(zoneId)
	return ZoneAccess.GetPlayerLevel(player) >= required
end

local characterBound: { [Model]: boolean } = {}

function ZoneAccess.ApplyToCharacter(player: Player, char: Model?)
	ZoneAccess.EnsureCollisionGroups()
	local character = char or player.Character
	if not character then
		return
	end
	local level = ZoneAccess.GetPlayerLevel(player)
	local groupName = ZoneDefs.GetAccessGroupName(level)
	previousLevel[player] = level
	setCharacterGroup(character, groupName)

	if not characterBound[character] then
		characterBound[character] = true
		character.DescendantAdded:Connect(function(desc)
			if desc:IsA("BasePart") then
				desc.CollisionGroup = ZoneDefs.GetAccessGroupName(ZoneAccess.GetPlayerLevel(player))
			end
		end)
		character.Destroying:Connect(function()
			characterBound[character] = nil
		end)
	end
end

local previousLevel: { [Player]: number } = {}

function ZoneAccess.RefreshPlayer(player: Player)
	ZoneAccess.EnsureCollisionGroups()
	local level = ZoneAccess.GetPlayerLevel(player)
	local prev = previousLevel[player]
	previousLevel[player] = level

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
			return
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

function ZoneAccess.Start()
	ZoneAccess.EnsureCollisionGroups()

	local function bind(player: Player)
		player.CharacterAdded:Connect(function(char)
			-- Attendre le profil pour le bon groupe
			task.spawn(function()
				local deadline = os.clock() + 10
				while not DataService.Get(player) and os.clock() < deadline do
					task.wait()
				end
				ZoneAccess.ApplyToCharacter(player, char)
			end)
		end)
		if player.Character then
			task.defer(function()
				ZoneAccess.ApplyToCharacter(player, player.Character)
			end)
		end
	end

	Players.PlayerAdded:Connect(bind)
	for _, player in ipairs(Players:GetPlayers()) do
		bind(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastGateNotify[player] = nil
		previousLevel[player] = nil
	end)
end

return ZoneAccess
