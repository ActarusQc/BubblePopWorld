--!strict
-- Lobby, salle de bulles, téléports serveur, barrières de sécurité et chute (FallReset).
-- Monde additif idempotent : les objets existants (décor Studio ou déjà créés) ne sont
-- jamais déplacés, redimensionnés ni détruits, sauf `Config.World.RebuildGeneratedLayout`
-- qui ne repositionne que les objets marqués `GeneratedByCode`.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)

local DataService = require(script.Parent.DataService)
local BackpackService = require(script.Parent.BackpackService)

local ZoneService = {}

--------------------------------------------------------------------
-- Aides idempotentes
--------------------------------------------------------------------
local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Crée `name` sous `container` via `build()` s'il est absent ; sinon réutilise l'objet
-- existant sans le déplacer/redimensionner (comportement par défaut). Si
-- `Config.World.RebuildGeneratedLayout` est actif ET que l'objet existant porte
-- `GeneratedByCode = true`, seule sa position/taille est réalignée (jamais un marker
-- placé manuellement dans Studio, qui n'a pas cet attribut).
local function ensurePart(container: Instance, name: string, build: () -> BasePart): BasePart
	local existing = container:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		if Config.World.RebuildGeneratedLayout and existing:GetAttribute("GeneratedByCode") == true then
			local fresh = build()
			existing.Size = fresh.Size
			existing.CFrame = fresh.CFrame
			fresh:Destroy()
		end
		return existing
	end
	local part = build()
	part.Name = name
	part:SetAttribute("GeneratedByCode", true)
	part.Parent = container
	return part
end

-- Répare additivement un ProximityPrompt : complète uniquement les propriétés manquantes
-- (jamais d'écrasement d'une personnalisation Studio existante).
local function ensurePrompt(
	part: BasePart,
	name: string,
	actionText: string,
	objectText: string,
	maxDistance: number
): ProximityPrompt
	local prompt = part:FindFirstChild(name)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		local created = Instance.new("ProximityPrompt")
		created.Name = name
		created.HoldDuration = 0.4
		created.RequiresLineOfSight = false
		created.Parent = part
		prompt = created
	end
	local p = prompt :: ProximityPrompt
	if p.ActionText == "" then
		p.ActionText = actionText
	end
	if p.ObjectText == "" then
		p.ObjectText = objectText
	end
	if p.MaxActivationDistance <= 0 then
		p.MaxActivationDistance = maxDistance
	end
	return p
end

-- Connecte `fn` une seule fois sur la durée de vie du prompt (protège contre un double
-- appel d'EnsureWorld, ex. Rebuild dev).
local function connectOnce(prompt: ProximityPrompt, key: string, fn: (Player) -> ())
	if prompt:GetAttribute(key) == true then
		return
	end
	prompt:SetAttribute(key, true)
	prompt.Triggered:Connect(fn)
end

local function validateOutsideGrid(pos: Vector3, margin: number, label: string)
	local b = Config.GetGridBounds()
	if pos.X > b.MinX - margin and pos.X < b.MaxX + margin
		and pos.Z > b.MinZ - margin and pos.Z < b.MaxZ + margin then
		warn("[ZoneService] position hors limites attendue mais chevauche la grille :", label, pos)
	end
end

--------------------------------------------------------------------
-- Références remplies par EnsureWorld
--------------------------------------------------------------------
local lobbySpawnPart: BasePart? = nil
local gameRoomSpawnPart: BasePart? = nil

--------------------------------------------------------------------
-- Barrières de sécurité (côtés grille, ouverture centrale côté spawn/sortie)
--------------------------------------------------------------------
local function ensureBorderWall(container: Instance, name: string, size: Vector3, cframe: CFrame): BasePart
	return ensurePart(container, name, function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.ForceField
		p.Color = Config.World.BorderColor
		p.Transparency = Config.World.BorderTransparency
		p.Size = size
		p.CFrame = cframe
		return p
	end)
end

local function buildSafetyBorders(gameRoom: Folder)
	local borders = ensureFolder(gameRoom, "SafetyBorders")
	local G = Config.Grid
	local W = Config.World
	local t = W.BorderThickness
	local h = W.BorderHeight
	local yCenter = G.Origin.Y + h / 2
	-- Les centres extrêmes sont à ((Size / 2) - 0.5) * Spacing. Les faces
	-- intérieures des murs restent 2 studs après le volume des bulles.
	local safetyGap = 2
	local bubbleExtentX = ((G.SizeX / 2) - 0.5) * G.Spacing + G.BubbleSize.X / 2 + safetyGap
	local bubbleExtentZ = ((G.SizeZ / 2) - 0.5) * G.Spacing + G.BubbleSize.Z / 2 + safetyGap

	ensureBorderWall(borders, "BorderNorth",
		Vector3.new((bubbleExtentX + t) * 2, h, t),
		CFrame.new(G.Origin.X, yCenter, G.Origin.Z + bubbleExtentZ + t / 2))

	ensureBorderWall(borders, "BorderEast",
		Vector3.new(t, h, (bubbleExtentZ + t) * 2),
		CFrame.new(G.Origin.X + bubbleExtentX + t / 2, yCenter, G.Origin.Z))

	ensureBorderWall(borders, "BorderWest",
		Vector3.new(t, h, (bubbleExtentZ + t) * 2),
		CFrame.new(G.Origin.X - bubbleExtentX - t / 2, yCenter, G.Origin.Z))

	-- Sud : ouverture centrale (pas de mur au-dessus des plateformes spawn/sortie).
	local gapWidth = math.max(Config.GameRoom.ExitSize.X, Config.GameRoom.PadSize.X) + 6
	local segLen = math.max(0, bubbleExtentX + t - gapWidth / 2)
	if segLen > 0 then
		ensureBorderWall(borders, "BorderSouthLeft",
			Vector3.new(segLen, h, t),
			CFrame.new(G.Origin.X - (gapWidth / 2 + segLen / 2), yCenter, G.Origin.Z - bubbleExtentZ - t / 2))
		ensureBorderWall(borders, "BorderSouthRight",
			Vector3.new(segLen, h, t),
			CFrame.new(G.Origin.X + (gapWidth / 2 + segLen / 2), yCenter, G.Origin.Z - bubbleExtentZ - t / 2))
	end
end

--------------------------------------------------------------------
-- Lobby
--------------------------------------------------------------------
local function buildLobby(lobby: Folder)
	local L = Config.Lobby
	local root = L.RootOffset

	validateOutsideGrid(root, L.ClearanceFromGrid, "Lobby.RootOffset")
	validateOutsideGrid(root + L.SellZoneOffset, L.ClearanceFromGrid, "Lobby.SellZoneOffset")
	validateOutsideGrid(root + L.EntranceOffset, L.ClearanceFromGrid, "Lobby.EntranceOffset")

	ensurePart(lobby, "Floor", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = L.FloorColor
		p.Size = L.FloorSize
		p.CFrame = CFrame.new(root - Vector3.new(0, L.FloorSize.Y / 2, 0))
		return p
	end)

	local spawn = ensurePart(lobby, "LobbySpawn", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Transparency = 1
		p.Size = Vector3.new(4, 1, 4)
		p.CFrame = CFrame.new(root + L.SpawnOffset)
		return p
	end)
	lobbySpawnPart = spawn

	local sellZone = ensurePart(lobby, "SellZone", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 210, 90)
		p.Transparency = 0.6
		p.Size = L.SellZoneSize
		p.CFrame = CFrame.new(root + L.SellZoneOffset)
		return p
	end)

	local entrance = ensurePart(lobby, "GameEntrance", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(120, 220, 140)
		p.Transparency = 0.6
		p.Size = L.EntranceSize
		p.CFrame = CFrame.new(root + L.EntranceOffset)
		return p
	end)

	local sellPrompt = ensurePrompt(sellZone, "SellPrompt", "Vendre mes bulles", "Vente", Config.World.SellMaxDistance)
	connectOnce(sellPrompt, "_wiredSell", function(player: Player)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then
			return
		end
		if (hrp.Position - sellZone.Position).Magnitude > Config.World.SellMaxDistance then
			return
		end
		BackpackService.Sell(player)
	end)

	local entrancePrompt = ensurePrompt(entrance, "EntrancePrompt", "Entrer dans la salle de bulles", "Bulles", 10)
	connectOnce(entrancePrompt, "_wiredEntrance", function(player: Player)
		ZoneService.TeleportToGameRoom(player)
	end)
end

--------------------------------------------------------------------
-- Salle de bulles (spawn, sortie, plateformes, barrières)
--------------------------------------------------------------------
local function buildGameRoom(gameRoom: Folder)
	local G = Config.Grid
	local R = Config.GameRoom

	local spawnPos = G.Origin + R.SpawnOffset
	local exitPos = G.Origin + R.ExitOffset
	validateOutsideGrid(spawnPos, Config.Lobby.ClearanceFromGrid, "GameRoom.SpawnOffset")
	validateOutsideGrid(exitPos, Config.Lobby.ClearanceFromGrid, "GameRoom.ExitOffset")

	-- Plateformes (pads) uniquement sous spawn/sortie : aucun plancher continu sous la grille.
	ensurePart(gameRoom, "SpawnPad", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = R.PadColor
		p.Size = R.PadSize
		p.CFrame = CFrame.new(spawnPos.X, G.Origin.Y - R.PadSize.Y / 2, spawnPos.Z)
		return p
	end)

	ensurePart(gameRoom, "ExitPad", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = R.PadColor
		p.Size = R.PadSize
		p.CFrame = CFrame.new(exitPos.X, G.Origin.Y - R.PadSize.Y / 2, exitPos.Z)
		return p
	end)

	local spawn = ensurePart(gameRoom, "GameRoomSpawn", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Transparency = 1
		p.Size = Vector3.new(4, 1, 4)
		p.CFrame = CFrame.new(spawnPos)
		return p
	end)
	gameRoomSpawnPart = spawn

	local exitZone = ensurePart(gameRoom, "ExitZone", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(220, 120, 120)
		p.Transparency = 0.6
		p.Size = R.ExitSize
		p.CFrame = CFrame.new(exitPos)
		return p
	end)

	local exitPrompt = ensurePrompt(exitZone, "ExitPrompt", "Retourner au lobby", "Sortie", 10)
	connectOnce(exitPrompt, "_wiredExit", function(player: Player)
		ZoneService.TeleportToLobby(player)
	end)

	buildSafetyBorders(gameRoom)
end

--------------------------------------------------------------------
-- Monde additif
--------------------------------------------------------------------
-- Idempotent : ne recrée/déplace jamais un objet existant (sauf Rebuild + GeneratedByCode).
-- Ne détruit jamais la map existante.
function ZoneService.EnsureWorld(): Folder
	local root = ensureFolder(workspace, "BubblePopWorld")
	local lobby = ensureFolder(root, "Lobby")
	local gameRoom = ensureFolder(root, "GameRoom")

	buildLobby(lobby)
	buildGameRoom(gameRoom)

	return root
end

--------------------------------------------------------------------
-- Téléports serveur uniquement
--------------------------------------------------------------------
local teleportLast: { [Player]: number } = {}

local function waitForHRP(player: Player, timeout: number?): (Model?, BasePart?)
	local char = player.Character
	if not char then
		local ok, result = pcall(function()
			return player.CharacterAdded:Wait()
		end)
		if not ok then
			return nil, nil
		end
		char = result
	end
	if not char then
		return nil, nil
	end

	local deadline = os.clock() + (timeout or 5)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	while not (hrp and hrp:IsA("BasePart")) do
		if os.clock() >= deadline or not char.Parent then
			return nil, nil
		end
		task.wait()
		hrp = char:FindFirstChild("HumanoidRootPart")
	end
	return char, hrp :: BasePart
end

local function doTeleport(player: Player, targetPos: Vector3, area: string, bypassCooldown: boolean?): boolean
	if not bypassCooldown then
		local last = teleportLast[player]
		if last and os.clock() - last < Config.World.TeleportCooldown then
			return false
		end
	end

	local char, hrp = waitForHRP(player)
	if not char or not hrp then
		return false
	end

	char:PivotTo(CFrame.new(targetPos))
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	teleportLast[player] = os.clock()
	-- L'attribut PlayerArea n'est posé qu'après un téléport réussi.
	player:SetAttribute("PlayerArea", area)
	return true
end

-- Serveur uniquement (module sous ServerScriptService). `bypassCooldown` réservé au
-- spawn initial et au FallReset (sécurité, ne doit pas être bloqué par l'anti-spam).
function ZoneService.TeleportToLobby(player: Player, bypassCooldown: boolean?): boolean
	if not lobbySpawnPart then
		return false
	end
	return doTeleport(player, lobbySpawnPart.Position + Vector3.new(0, 3, 0), "Lobby", bypassCooldown)
end

function ZoneService.TeleportToGameRoom(player: Player, bypassCooldown: boolean?): boolean
	if not gameRoomSpawnPart then
		return false
	end
	return doTeleport(player, gameRoomSpawnPart.Position + Vector3.new(0, 3, 0), "GameRoom", bypassCooldown)
end

--------------------------------------------------------------------
-- Spawn initial (debounce) + FallReset
--------------------------------------------------------------------
local spawningInProgress: { [Player]: boolean } = {}

local function onCharacterAdded(player: Player)
	if spawningInProgress[player] then
		return
	end
	spawningInProgress[player] = true
	task.spawn(function()
		local deadline = os.clock() + 10
		while not DataService.Get(player) and os.clock() < deadline do
			task.wait()
		end
		ZoneService.TeleportToLobby(player, true)
		spawningInProgress[player] = nil
	end)
end

local fallResetGuard: { [Player]: boolean } = {}

local function watchFallReset()
	RunService.Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			if fallResetGuard[player] then
				continue
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and hrp.Position.Y < Config.World.FallResetY then
				fallResetGuard[player] = true
				task.spawn(function()
					if Config.World.FallResetDestination == "Lobby" then
						ZoneService.TeleportToLobby(player, true)
					else
						ZoneService.TeleportToGameRoom(player, true)
					end
					fallResetGuard[player] = nil
				end)
			end
		end
	end)
end

function ZoneService.Start()
	ZoneService.EnsureWorld()

	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		if player.Character then
			onCharacterAdded(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		teleportLast[player] = nil
		spawningInProgress[player] = nil
		fallResetGuard[player] = nil
	end)

	watchFallReset()
end

return ZoneService
