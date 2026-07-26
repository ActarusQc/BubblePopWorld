# Task 4 review
BASE: cba2fb0 HEAD: d96b13928768a2b76fe900ee30af92f31ae8d894
## Commits
d96b139 feat: add ZoneService lobby teleports and safety borders

## Stat
 src/Server/AmbianceService.lua |  28 +--
 src/Server/ZoneService.lua     | 462 +++++++++++++++++++++++++++++++++++++++++
 src/Server/init.server.lua     |   1 +
 3 files changed, 467 insertions(+), 24 deletions(-)

## Diff
```diff
diff --git a/src/Server/AmbianceService.lua b/src/Server/AmbianceService.lua
index 21d0414..cab693a 100644
--- a/src/Server/AmbianceService.lua
+++ b/src/Server/AmbianceService.lua
@@ -51,39 +51,19 @@ function AmbianceService.Apply(worldDef)
 	clear("ColorCorrectionEffect")
 	local cc = Instance.new("ColorCorrectionEffect")
 	cc.Saturation = 0.12
 	cc.Contrast = 0.08
 	cc.Brightness = 0
 	cc.Parent = Lighting
 end
 
--- Murs invisibles : on ne tombe plus hors de la nappe de bulles.
-function AmbianceService.BuildWalls(parent: Instance)
-	local G = Config.Grid
-	local w = G.SizeX * G.Spacing
-	local d = G.SizeZ * G.Spacing
-	local height = 220
-
-	local sides = {
-		{ Vector3.new(w + 20, height, 4), Vector3.new(0, height / 2, -d / 2 - 8) },
-		{ Vector3.new(w + 20, height, 4), Vector3.new(0, height / 2, d / 2 + 8) },
-		{ Vector3.new(4, height, d + 20), Vector3.new(-w / 2 - 8, height / 2, 0) },
-		{ Vector3.new(4, height, d + 20), Vector3.new(w / 2 + 8, height / 2, 0) },
-	}
-
-	for i, side in ipairs(sides) do
-		local wall = Instance.new("Part")
-		wall.Name = "Wall" .. i
-		wall.Anchored = true
-		wall.CanCollide = true
-		wall.Transparency = 1
-		wall.Size = side[1]
-		wall.CFrame = CFrame.new(G.Origin + side[2])
-		wall.Parent = parent
-	end
+-- No-op : les barri├¿res de s├⌐curit├⌐ sont d├⌐sormais g├⌐r├⌐es de fa├ºon idempotente par
+-- `ZoneService` (dossier `SafetyBorders` sous `Workspace.BubblePopWorld.GameRoom`),
+-- avec ouverture c├┤t├⌐ spawn/sortie. Conserv├⌐ pour compatibilit├⌐ des appelants existants.
+function AmbianceService.BuildWalls(_parent: Instance)
 end
 
 function AmbianceService.Start()
 	AmbianceService.Apply(Config.Worlds[1])
 end
 
 return AmbianceService
diff --git a/src/Server/ZoneService.lua b/src/Server/ZoneService.lua
new file mode 100644
index 0000000..03ea43f
--- /dev/null
+++ b/src/Server/ZoneService.lua
@@ -0,0 +1,462 @@
+--!strict
+-- Lobby, salle de bulles, t├⌐l├⌐ports serveur, barri├¿res de s├⌐curit├⌐ et chute (FallReset).
+-- Monde additif idempotent : les objets existants (d├⌐cor Studio ou d├⌐j├á cr├⌐├⌐s) ne sont
+-- jamais d├⌐plac├⌐s, redimensionn├⌐s ni d├⌐truits, sauf `Config.World.RebuildGeneratedLayout`
+-- qui ne repositionne que les objets marqu├⌐s `GeneratedByCode`.
+
+local Players = game:GetService("Players")
+local RunService = game:GetService("RunService")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Config = require(Shared.GameConfig)
+
+local DataService = require(script.Parent.DataService)
+local BackpackService = require(script.Parent.BackpackService)
+
+local ZoneService = {}
+
+--------------------------------------------------------------------
+-- Aides idempotentes
+--------------------------------------------------------------------
+local function ensureFolder(parent: Instance, name: string): Folder
+	local existing = parent:FindFirstChild(name)
+	if existing and existing:IsA("Folder") then
+		return existing
+	end
+	local folder = Instance.new("Folder")
+	folder.Name = name
+	folder.Parent = parent
+	return folder
+end
+
+-- Cr├⌐e `name` sous `container` via `build()` s'il est absent ; sinon r├⌐utilise l'objet
+-- existant sans le d├⌐placer/redimensionner (comportement par d├⌐faut). Si
+-- `Config.World.RebuildGeneratedLayout` est actif ET que l'objet existant porte
+-- `GeneratedByCode = true`, seule sa position/taille est r├⌐align├⌐e (jamais un marker
+-- plac├⌐ manuellement dans Studio, qui n'a pas cet attribut).
+local function ensurePart(container: Instance, name: string, build: () -> BasePart): BasePart
+	local existing = container:FindFirstChild(name)
+	if existing and existing:IsA("BasePart") then
+		if Config.World.RebuildGeneratedLayout and existing:GetAttribute("GeneratedByCode") == true then
+			local fresh = build()
+			existing.Size = fresh.Size
+			existing.CFrame = fresh.CFrame
+			fresh:Destroy()
+		end
+		return existing
+	end
+	local part = build()
+	part.Name = name
+	part:SetAttribute("GeneratedByCode", true)
+	part.Parent = container
+	return part
+end
+
+-- R├⌐pare additivement un ProximityPrompt : compl├¿te uniquement les propri├⌐t├⌐s manquantes
+-- (jamais d'├⌐crasement d'une personnalisation Studio existante).
+local function ensurePrompt(
+	part: BasePart,
+	name: string,
+	actionText: string,
+	objectText: string,
+	maxDistance: number
+): ProximityPrompt
+	local prompt = part:FindFirstChild(name)
+	if not (prompt and prompt:IsA("ProximityPrompt")) then
+		local created = Instance.new("ProximityPrompt")
+		created.Name = name
+		created.HoldDuration = 0.4
+		created.RequiresLineOfSight = false
+		created.Parent = part
+		prompt = created
+	end
+	local p = prompt :: ProximityPrompt
+	if p.ActionText == "" then
+		p.ActionText = actionText
+	end
+	if p.ObjectText == "" then
+		p.ObjectText = objectText
+	end
+	if p.MaxActivationDistance <= 0 then
+		p.MaxActivationDistance = maxDistance
+	end
+	return p
+end
+
+-- Connecte `fn` une seule fois sur la dur├⌐e de vie du prompt (prot├¿ge contre un double
+-- appel d'EnsureWorld, ex. Rebuild dev).
+local function connectOnce(prompt: ProximityPrompt, key: string, fn: (Player) -> ())
+	if prompt:GetAttribute(key) == true then
+		return
+	end
+	prompt:SetAttribute(key, true)
+	prompt.Triggered:Connect(fn)
+end
+
+local function validateOutsideGrid(pos: Vector3, margin: number, label: string)
+	local b = Config.GetGridBounds()
+	if pos.X > b.MinX - margin and pos.X < b.MaxX + margin
+		and pos.Z > b.MinZ - margin and pos.Z < b.MaxZ + margin then
+		warn("[ZoneService] position hors limites attendue mais chevauche la grille :", label, pos)
+	end
+end
+
+--------------------------------------------------------------------
+-- R├⌐f├⌐rences remplies par EnsureWorld
+--------------------------------------------------------------------
+local lobbySpawnPart: BasePart? = nil
+local gameRoomSpawnPart: BasePart? = nil
+
+--------------------------------------------------------------------
+-- Barri├¿res de s├⌐curit├⌐ (c├┤t├⌐s grille, ouverture centrale c├┤t├⌐ spawn/sortie)
+--------------------------------------------------------------------
+local function ensureBorderWall(container: Instance, name: string, size: Vector3, cframe: CFrame): BasePart
+	return ensurePart(container, name, function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = true
+		p.CanQuery = false
+		p.CanTouch = false
+		p.Material = Enum.Material.ForceField
+		p.Color = Config.World.BorderColor
+		p.Transparency = Config.World.BorderTransparency
+		p.Size = size
+		p.CFrame = cframe
+		return p
+	end)
+end
+
+local function buildSafetyBorders(gameRoom: Folder)
+	local borders = ensureFolder(gameRoom, "SafetyBorders")
+	local G = Config.Grid
+	local W = Config.World
+	local halfX = (G.SizeX * G.Spacing) / 2
+	local halfZ = (G.SizeZ * G.Spacing) / 2
+	local t = W.BorderThickness
+	local h = W.BorderHeight
+	local yCenter = G.Origin.Y + h / 2
+
+	ensureBorderWall(borders, "BorderNorth",
+		Vector3.new(halfX * 2 + t * 2, h, t),
+		CFrame.new(G.Origin.X, yCenter, G.Origin.Z + halfZ + t / 2))
+
+	ensureBorderWall(borders, "BorderEast",
+		Vector3.new(t, h, halfZ * 2 + t * 2),
+		CFrame.new(G.Origin.X + halfX + t / 2, yCenter, G.Origin.Z))
+
+	ensureBorderWall(borders, "BorderWest",
+		Vector3.new(t, h, halfZ * 2 + t * 2),
+		CFrame.new(G.Origin.X - halfX - t / 2, yCenter, G.Origin.Z))
+
+	-- Sud : ouverture centrale (pas de mur au-dessus des plateformes spawn/sortie).
+	local gapWidth = math.max(Config.GameRoom.ExitSize.X, Config.GameRoom.PadSize.X) + 6
+	local segLen = math.max(0, halfX + t - gapWidth / 2)
+	if segLen > 0 then
+		ensureBorderWall(borders, "BorderSouthLeft",
+			Vector3.new(segLen, h, t),
+			CFrame.new(G.Origin.X - (gapWidth / 2 + segLen / 2), yCenter, G.Origin.Z - halfZ - t / 2))
+		ensureBorderWall(borders, "BorderSouthRight",
+			Vector3.new(segLen, h, t),
+			CFrame.new(G.Origin.X + (gapWidth / 2 + segLen / 2), yCenter, G.Origin.Z - halfZ - t / 2))
+	end
+end
+
+--------------------------------------------------------------------
+-- Lobby
+--------------------------------------------------------------------
+local function buildLobby(lobby: Folder)
+	local L = Config.Lobby
+	local root = L.RootOffset
+
+	validateOutsideGrid(root, L.ClearanceFromGrid, "Lobby.RootOffset")
+	validateOutsideGrid(root + L.SellZoneOffset, L.ClearanceFromGrid, "Lobby.SellZoneOffset")
+	validateOutsideGrid(root + L.EntranceOffset, L.ClearanceFromGrid, "Lobby.EntranceOffset")
+
+	ensurePart(lobby, "Floor", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = true
+		p.Material = Enum.Material.SmoothPlastic
+		p.Color = L.FloorColor
+		p.Size = L.FloorSize
+		p.CFrame = CFrame.new(root - Vector3.new(0, L.FloorSize.Y / 2, 0))
+		return p
+	end)
+
+	local spawn = ensurePart(lobby, "LobbySpawn", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.CanQuery = false
+		p.Transparency = 1
+		p.Size = Vector3.new(4, 1, 4)
+		p.CFrame = CFrame.new(root + L.SpawnOffset)
+		return p
+	end)
+	lobbySpawnPart = spawn
+
+	local sellZone = ensurePart(lobby, "SellZone", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.Material = Enum.Material.Neon
+		p.Color = Color3.fromRGB(255, 210, 90)
+		p.Transparency = 0.6
+		p.Size = L.SellZoneSize
+		p.CFrame = CFrame.new(root + L.SellZoneOffset)
+		return p
+	end)
+
+	local entrance = ensurePart(lobby, "GameEntrance", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.Material = Enum.Material.Neon
+		p.Color = Color3.fromRGB(120, 220, 140)
+		p.Transparency = 0.6
+		p.Size = L.EntranceSize
+		p.CFrame = CFrame.new(root + L.EntranceOffset)
+		return p
+	end)
+
+	local sellPrompt = ensurePrompt(sellZone, "SellPrompt", "Vendre mes bulles", "Vente", Config.World.SellMaxDistance)
+	connectOnce(sellPrompt, "_wiredSell", function(player: Player)
+		local char = player.Character
+		local hrp = char and char:FindFirstChild("HumanoidRootPart")
+		if not (hrp and hrp:IsA("BasePart")) then
+			return
+		end
+		if (hrp.Position - sellZone.Position).Magnitude > Config.World.SellMaxDistance then
+			return
+		end
+		BackpackService.Sell(player)
+	end)
+
+	local entrancePrompt = ensurePrompt(entrance, "EntrancePrompt", "Entrer dans la salle de bulles", "Bulles", 10)
+	connectOnce(entrancePrompt, "_wiredEntrance", function(player: Player)
+		ZoneService.TeleportToGameRoom(player)
+	end)
+end
+
+--------------------------------------------------------------------
+-- Salle de bulles (spawn, sortie, plateformes, barri├¿res)
+--------------------------------------------------------------------
+local function buildGameRoom(gameRoom: Folder)
+	local G = Config.Grid
+	local R = Config.GameRoom
+
+	local spawnPos = G.Origin + R.SpawnOffset
+	local exitPos = G.Origin + R.ExitOffset
+	validateOutsideGrid(spawnPos, 0, "GameRoom.SpawnOffset")
+	validateOutsideGrid(exitPos, 0, "GameRoom.ExitOffset")
+
+	-- Plateformes (pads) uniquement sous spawn/sortie : aucun plancher continu sous la grille.
+	ensurePart(gameRoom, "SpawnPad", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = true
+		p.Material = Enum.Material.SmoothPlastic
+		p.Color = R.PadColor
+		p.Size = R.PadSize
+		p.CFrame = CFrame.new(spawnPos.X, G.Origin.Y - R.PadSize.Y / 2, spawnPos.Z)
+		return p
+	end)
+
+	ensurePart(gameRoom, "ExitPad", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = true
+		p.Material = Enum.Material.SmoothPlastic
+		p.Color = R.PadColor
+		p.Size = R.PadSize
+		p.CFrame = CFrame.new(exitPos.X, G.Origin.Y - R.PadSize.Y / 2, exitPos.Z)
+		return p
+	end)
+
+	local spawn = ensurePart(gameRoom, "GameRoomSpawn", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.CanQuery = false
+		p.Transparency = 1
+		p.Size = Vector3.new(4, 1, 4)
+		p.CFrame = CFrame.new(spawnPos)
+		return p
+	end)
+	gameRoomSpawnPart = spawn
+
+	local exitZone = ensurePart(gameRoom, "ExitZone", function()
+		local p = Instance.new("Part")
+		p.Anchored = true
+		p.CanCollide = false
+		p.Material = Enum.Material.Neon
+		p.Color = Color3.fromRGB(220, 120, 120)
+		p.Transparency = 0.6
+		p.Size = R.ExitSize
+		p.CFrame = CFrame.new(exitPos)
+		return p
+	end)
+
+	local exitPrompt = ensurePrompt(exitZone, "ExitPrompt", "Retourner au lobby", "Sortie", 10)
+	connectOnce(exitPrompt, "_wiredExit", function(player: Player)
+		ZoneService.TeleportToLobby(player)
+	end)
+
+	buildSafetyBorders(gameRoom)
+end
+
+--------------------------------------------------------------------
+-- Monde additif
+--------------------------------------------------------------------
+-- Idempotent : ne recr├⌐e/d├⌐place jamais un objet existant (sauf Rebuild + GeneratedByCode).
+-- Ne d├⌐truit jamais la map existante.
+function ZoneService.EnsureWorld(): Folder
+	local root = ensureFolder(workspace, "BubblePopWorld")
+	local lobby = ensureFolder(root, "Lobby")
+	local gameRoom = ensureFolder(root, "GameRoom")
+
+	buildLobby(lobby)
+	buildGameRoom(gameRoom)
+
+	return root
+end
+
+--------------------------------------------------------------------
+-- T├⌐l├⌐ports serveur uniquement
+--------------------------------------------------------------------
+local teleportLast: { [Player]: number } = {}
+
+local function waitForHRP(player: Player, timeout: number?): (Model?, BasePart?)
+	local char = player.Character
+	if not char then
+		local ok, result = pcall(function()
+			return player.CharacterAdded:Wait()
+		end)
+		if not ok then
+			return nil, nil
+		end
+		char = result
+	end
+	if not char then
+		return nil, nil
+	end
+
+	local deadline = os.clock() + (timeout or 5)
+	local hrp = char:FindFirstChild("HumanoidRootPart")
+	while not (hrp and hrp:IsA("BasePart")) do
+		if os.clock() >= deadline or not char.Parent then
+			return nil, nil
+		end
+		task.wait()
+		hrp = char:FindFirstChild("HumanoidRootPart")
+	end
+	return char, hrp :: BasePart
+end
+
+local function doTeleport(player: Player, targetPos: Vector3, area: string, bypassCooldown: boolean?): boolean
+	if not bypassCooldown then
+		local last = teleportLast[player]
+		if last and os.clock() - last < Config.World.TeleportCooldown then
+			return false
+		end
+	end
+
+	local char, hrp = waitForHRP(player)
+	if not char or not hrp then
+		return false
+	end
+
+	char:PivotTo(CFrame.new(targetPos))
+	hrp.AssemblyLinearVelocity = Vector3.zero
+	hrp.AssemblyAngularVelocity = Vector3.zero
+
+	teleportLast[player] = os.clock()
+	-- L'attribut PlayerArea n'est pos├⌐ qu'apr├¿s un t├⌐l├⌐port r├⌐ussi.
+	player:SetAttribute("PlayerArea", area)
+	return true
+end
+
+-- Serveur uniquement (module sous ServerScriptService). `bypassCooldown` r├⌐serv├⌐ au
+-- spawn initial et au FallReset (s├⌐curit├⌐, ne doit pas ├¬tre bloqu├⌐ par l'anti-spam).
+function ZoneService.TeleportToLobby(player: Player, bypassCooldown: boolean?): boolean
+	if not lobbySpawnPart then
+		return false
+	end
+	return doTeleport(player, lobbySpawnPart.Position + Vector3.new(0, 3, 0), "Lobby", bypassCooldown)
+end
+
+function ZoneService.TeleportToGameRoom(player: Player, bypassCooldown: boolean?): boolean
+	if not gameRoomSpawnPart then
+		return false
+	end
+	return doTeleport(player, gameRoomSpawnPart.Position + Vector3.new(0, 3, 0), "GameRoom", bypassCooldown)
+end
+
+--------------------------------------------------------------------
+-- Spawn initial (debounce) + FallReset
+--------------------------------------------------------------------
+local spawningInProgress: { [Player]: boolean } = {}
+
+local function onCharacterAdded(player: Player)
+	if spawningInProgress[player] then
+		return
+	end
+	spawningInProgress[player] = true
+	task.spawn(function()
+		local deadline = os.clock() + 10
+		while not DataService.Get(player) and os.clock() < deadline do
+			task.wait()
+		end
+		ZoneService.TeleportToLobby(player, true)
+		spawningInProgress[player] = nil
+	end)
+end
+
+local fallResetGuard: { [Player]: boolean } = {}
+
+local function watchFallReset()
+	RunService.Heartbeat:Connect(function()
+		for _, player in ipairs(Players:GetPlayers()) do
+			if fallResetGuard[player] then
+				continue
+			end
+			local char = player.Character
+			local hrp = char and char:FindFirstChild("HumanoidRootPart")
+			if hrp and hrp:IsA("BasePart") and hrp.Position.Y < Config.World.FallResetY then
+				fallResetGuard[player] = true
+				task.spawn(function()
+					if Config.World.FallResetDestination == "Lobby" then
+						ZoneService.TeleportToLobby(player, true)
+					else
+						ZoneService.TeleportToGameRoom(player, true)
+					end
+					fallResetGuard[player] = nil
+				end)
+			end
+		end
+	end)
+end
+
+function ZoneService.Start()
+	ZoneService.EnsureWorld()
+
+	Players.PlayerAdded:Connect(function(player: Player)
+		player.CharacterAdded:Connect(function()
+			onCharacterAdded(player)
+		end)
+		if player.Character then
+			onCharacterAdded(player)
+		end
+	end)
+
+	Players.PlayerRemoving:Connect(function(player: Player)
+		teleportLast[player] = nil
+		spawningInProgress[player] = nil
+		fallResetGuard[player] = nil
+	end)
+
+	watchFallReset()
+end
+
+return ZoneService
diff --git a/src/Server/init.server.lua b/src/Server/init.server.lua
index 8022262..e46c5c2 100644
--- a/src/Server/init.server.lua
+++ b/src/Server/init.server.lua
@@ -2,16 +2,17 @@
 -- Point d'entr├⌐e serveur : ordre de d├⌐marrage explicite.
 
 local ReplicatedStorage = game:GetService("ReplicatedStorage")
 require(ReplicatedStorage:WaitForChild("Shared").Remotes) -- cr├⌐e les remotes en premier
 
 local services = {
 	require(script.DataService),
 	require(script.BackpackService),
+	require(script.ZoneService),
 	require(script.GlobalCounterService),
 	require(script.ComboService),
 	require(script.AmbianceService),
 	require(script.BubbleService),
 	require(script.ToolService),
 	require(script.DropService),
 	require(script.ChestService),
 	require(script.ShopService),

```
