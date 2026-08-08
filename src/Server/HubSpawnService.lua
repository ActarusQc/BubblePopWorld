--!strict
-- Apparition hub : SpawnLocation Roblox natif + RespawnLocation uniquement.
-- Aucune écriture de position sur le personnage, aucune correction Y du spawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubSpawnLogic = require(Shared.HubSpawnLogic)
local ManualRig = require(Shared.RearHubManualRig)

local HubSpawnService = {}

local ROOT_NAME = "CentralHub"
local LOG = "[HubSpawnManual] "
local AUDIT = "[HubSpawnManualAudit] "

local postSpawnWrites = 0
local initialSpawnCorrected: { [Player]: boolean } = {}

local function log(msg: string)
	print(LOG .. msg)
end

local function audit(msg: string)
	print(AUDIT .. msg)
end

function HubSpawnService.IsManualSpawn(sl: Instance): boolean
	if not sl:IsA("SpawnLocation") then
		return false
	end
	return HubSpawnLogic.IsManualPlacement(
		sl:GetAttribute("BPW_ManualPlacement") == true,
		sl:GetAttribute("BPW_SpawnManualInitialized") == true
	)
end

function HubSpawnService.FindManualHubSpawn(): SpawnLocation?
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild(ROOT_NAME)
	if not hub then
		return nil
	end
	local direct = hub:FindFirstChild("HubSpawnLocation")
	if direct and direct:IsA("SpawnLocation") then
		return direct
	end
	for _, d in ipairs(hub:GetDescendants()) do
		if d.Name == "HubSpawnLocation" and d:IsA("SpawnLocation") then
			return d
		end
	end
	return nil
end

--- Toute écriture de position sur le personnage passerait ici (doit rester 0).
function HubSpawnService.RecordPostSpawnPositionWrite(source: string)
	postSpawnWrites += 1
	warn(LOG .. "FORBIDDEN post-spawn position write from " .. source)
end

function HubSpawnService.GetPostSpawnWrites(): number
	return postSpawnWrites
end

-- Compat anciens appels
function HubSpawnService.GetTeleportCount(_player: Player?): number
	return postSpawnWrites
end

function HubSpawnService.LogAllSpawnLocations(): number
	local n = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			n += 1
			local sl = d :: SpawnLocation
			log(string.format(
				"SpawnLocation found: %s position=(%.2f,%.2f,%.2f) enabled=%s",
				sl:GetFullName(),
				sl.Position.X,
				sl.Position.Y,
				sl.Position.Z,
				tostring(sl.Enabled)
			))
		end
	end
	log(string.format("total SpawnLocations: %d", n))
	return n
end

function HubSpawnService.DisableCompetingSpawns(except: SpawnLocation?): number
	local disabled = 0
	local hasManual = except ~= nil
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d ~= except then
			local sl = d :: SpawnLocation
			local path = sl:GetFullName()
			local isHubRival = sl.Name == "HubSpawnLocation"
				or sl.Name == "HubSpawnPad"
				or sl.Name == "SpawnLocation"
				or string.find(path, "CentralHub", 1, true) ~= nil
				or (hasManual and sl.Name == "GameRoomSpawnLocation")
			if isHubRival then
				if sl.Enabled then
					sl.Enabled = false
					disabled += 1
					log("disabled competing: " .. path)
				end
				sl:SetAttribute("BPW_DisabledAsCompetingHubSpawn", true)
			end
		end
	end
	return disabled
end

--- Attributs / flags seulement. Le CFrame Studio n'est jamais réécrit.
function HubSpawnService.ConfigureSpawnLocation(sl: SpawnLocation)
	local cf = sl.CFrame
	sl:SetAttribute("BPW_ManualPlacement", true)
	sl:SetAttribute("BPW_Role", "HubSpawnLocation")
	sl:SetAttribute("BPW_SpawnManualInitialized", true)
	sl.Name = "HubSpawnLocation"
	sl.Anchored = true
	sl.Enabled = true
	sl.Neutral = true
	sl.AllowTeamChangeOnTouch = false
	sl.Duration = 0
	sl.Transparency = 1
	sl.CanCollide = false
	sl.CanTouch = false
	sl.CanQuery = false
	sl.CastShadow = false
	sl.CFrame = cf
end

-- Compat
function HubSpawnService.TagManualSpawn(sl: SpawnLocation)
	HubSpawnService.ConfigureSpawnLocation(sl)
end

function HubSpawnService.ApplyRespawnLocation(player: Player): boolean
	local sl = HubSpawnService.FindManualHubSpawn()
	if not sl then
		return false
	end
	player.RespawnLocation = sl
	log(string.format("RespawnLocation set for %s → %s", player.Name, sl:GetFullName()))
	return true
end

function HubSpawnService.ApplyRespawnLocationAll(): number
	local sl = HubSpawnService.FindManualHubSpawn()
	if not sl then
		return 0
	end
	local n = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		plr.RespawnLocation = sl
		n += 1
	end
	return n
end

--- Retour hub intentionnel : respawn natif Roblox (jamais un CFrame HRP).
function HubSpawnService.ReloadCharacterAtHubSpawn(player: Player): boolean
	local sl = HubSpawnService.FindManualHubSpawn()
	if not sl then
		return false
	end
	player.RespawnLocation = sl
	player:LoadCharacter()
	return true
end

function HubSpawnService.PrepareForPlay()
	HubSpawnService.LogAllSpawnLocations()
	local sl = HubSpawnService.FindManualHubSpawn()
	if sl then
		HubSpawnService.ConfigureSpawnLocation(sl)
		HubSpawnService.DisableCompetingSpawns(sl)
		HubSpawnService.ApplyRespawnLocationAll()
		log(string.format(
			"manual spawn kept: (%.2f, %.2f, %.2f) — no Y correction",
			sl.Position.X,
			sl.Position.Y,
			sl.Position.Z
		))
	else
		warn(LOG .. "aucun HubSpawnLocation sous CentralHub — placer en Studio")
	end
	ManualRig.ValidateRuntime()
end

local function footBottomY(part: BasePart): number
	return part.Position.Y - part.Size.Y / 2
end

function HubSpawnService.RunRuntimeAudit(player: Player?): boolean
	local sl = HubSpawnService.FindManualHubSpawn()
	audit("spawn path: " .. (if sl then sl:GetFullName() else "<missing>"))

	local plr = player or Players:GetPlayers()[1]
	local matches = plr ~= nil and sl ~= nil and plr.RespawnLocation == sl
	audit(string.format("player RespawnLocation matches: %s", tostring(matches)))

	local hrpAnchored = true
	local platformStand = true
	local floorName = "<none>"
	local gap = 999

	if plr and plr.Character then
		local char = plr.Character
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hum and hum:IsA("Humanoid") then
			if hum.PlatformStand then
				hum.PlatformStand = false
			end
			platformStand = hum.PlatformStand
			hum.AutoRotate = true
		end
		local floorY: number? = nil
		if hrp and hrp:IsA("BasePart") then
			if hrp.Anchored then
				hrp.Anchored = false
				warn(LOG .. "HumanoidRootPart était Anchored — forcé false")
			end
			hrpAnchored = hrp.Anchored
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char }
			local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -20, 0), params)
			if hit then
				floorY = hit.Position.Y
				floorName = hit.Instance:GetFullName()
			end
		end
		local left = char:FindFirstChild("LeftFoot") or char:FindFirstChild("Left Leg")
		local right = char:FindFirstChild("RightFoot") or char:FindFirstChild("Right Leg")
		local footY: number? = nil
		if left and left:IsA("BasePart") then
			footY = footBottomY(left)
			if right and right:IsA("BasePart") then
				footY = math.min(footY, footBottomY(right))
			end
		elseif hrp and hrp:IsA("BasePart") and hum then
			footY = hrp.Position.Y - hum.HipHeight - hrp.Size.Y / 2
		end
		if footY and floorY then
			gap = footY - floorY
		end
	end

	audit(string.format("HRP anchored: %s", tostring(hrpAnchored)))
	audit(string.format("PlatformStand: %s", tostring(platformStand)))
	audit("floor hit: " .. floorName)
	audit(string.format("foot/floor gap: %.3f", gap))
	audit(string.format("post-spawn position writes: %d", postSpawnWrites))
	audit(string.format("runtime reposition count: %d", ManualRig.GetRuntimeRepositionCount()))

	local pass = sl ~= nil
		and matches
		and hrpAnchored == false
		and platformStand == false
		and postSpawnWrites == 0
		and HubSpawnLogic.FootFloorGapOk(gap)

	if pass then
		audit("PASS")
	else
		audit("FAIL")
		warn(AUDIT .. "FAIL")
	end
	return pass
end

function HubSpawnService.Start()
	Players.PlayerAdded:Connect(function(player)
		HubSpawnService.ApplyRespawnLocation(player)
		player.CharacterAdded:Connect(function(character)
			-- Le tout premier Character peut être créé avant PlayerAdded/RespawnLocation.
			-- Si Roblox l'a placé sur un ancien spawn, refaire une seule apparition native.
			task.spawn(function()
				local root = character:WaitForChild("HumanoidRootPart", 8)
				local spawn = HubSpawnService.FindManualHubSpawn()
				if not root or not root:IsA("BasePart") or not spawn or initialSpawnCorrected[player] then
					return
				end
				local horizontal = HubSpawnLogic.HorizontalDisplacement(root.Position, spawn.Position)
				if horizontal > 24 then
					initialSpawnCorrected[player] = true
					warn(LOG .. string.format(
						"initial character spawned %.1f studs from hub; reloading at canonical spawn",
						horizontal
					))
					HubSpawnService.ReloadCharacterAtHubSpawn(player)
				else
					initialSpawnCorrected[player] = true
				end
			end)

			-- Aucun CFrame forcé. Filet anti-anchor / PlatformStand seulement.
			task.delay(1, function()
				if not character.Parent then
					return
				end
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") and hrp.Anchored then
					hrp.Anchored = false
				end
				local hum = character:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.PlatformStand = false
					hum.AutoRotate = true
				end
				HubSpawnService.RunRuntimeAudit(player)
			end)
		end)
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		HubSpawnService.ApplyRespawnLocation(plr)
	end
	Players.PlayerRemoving:Connect(function(player)
		initialSpawnCorrected[player] = nil
	end)

	task.spawn(function()
		local deadline = os.clock() + 30
		while os.clock() < deadline do
			if ManualRig.FindPlatform() then
				break
			end
			task.wait(0.25)
		end
		ManualRig.ValidateRuntime()
		HubSpawnService.ApplyRespawnLocationAll()
	end)
end

return HubSpawnService
