--!strict
-- Gestionnaire unique d'apparition des objets (rayon lumineux + ramassage).
-- Une boucle par zone active pilotée par le même planificateur partagé
-- (ItemSpawnPlanner) : chaque planche enregistrée obtient sa propre cadence,
-- son pool ZoneItemPools et son plafond d'objets simultanés.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ToolDefs = require(Shared.ToolDefs)
local ItemSpawnPlanner = require(Shared.ItemSpawnPlanner)
local Remotes = require(Shared.Remotes)

local BubbleService = require(script.Parent.BubbleService)
local ToolService = require(script.Parent.ToolService)

local DropService = {}
local rng = Random.new()

local activeByZone: { [string]: number } = {}
local zoneLoops: { [string]: boolean } = {}
-- Drops tutoriel : ne comptent pas dans le cap de zone aléatoire.
local tutorialActiveByZone: { [string]: number } = {}

local function zoneQuery(zoneId: string): ItemSpawnPlanner.CellQuery?
	local board = BubbleService.GetBoard(zoneId)
	if not board then
		return nil
	end
	return {
		SizeX = board.sizeX,
		SizeZ = board.sizeZ,
		IsAlive = function(x: number, z: number): boolean
			return BubbleService.IsAlive(x, z, zoneId)
		end,
	}
end

local function buildDropVisual(id: string, def: any, pos: Vector3): Part
	local model = Instance.new("Part")
	model.Name = "Drop_" .. id
	model.Anchored = true
	model.CanCollide = false
	model.CFrame = CFrame.new(pos)

	local accent = ToolDefs.RarityColor[def.Rarity] or def.Color
	if id == "Bombe" then
		model.Shape = Enum.PartType.Ball
		model.Size = Vector3.new(2.2, 2.2, 2.2)
		model.Color = Color3.fromRGB(35, 35, 42)
		model.Material = Enum.Material.SmoothPlastic
		local spark = Instance.new("Part")
		spark.Name = "Spark"
		spark.Anchored = true
		spark.CanCollide = false
		spark.Shape = Enum.PartType.Ball
		spark.Size = Vector3.new(0.45, 0.45, 0.45)
		spark.Color = Color3.fromRGB(255, 170, 50)
		spark.Material = Enum.Material.Neon
		spark.CFrame = CFrame.new(pos + Vector3.new(0.4, 1.3, 0))
		spark.Parent = model
	elseif id == "Epingle" then
		model.Size = Vector3.new(0.25, 2.4, 0.25)
		model.Color = Color3.fromRGB(175, 182, 195)
		model.Material = Enum.Material.Metal
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Anchored = true
		head.CanCollide = false
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(0.7, 0.7, 0.7)
		head.Color = Color3.fromRGB(255, 55, 75)
		head.Material = Enum.Material.SmoothPlastic
		head.CFrame = CFrame.new(pos + Vector3.new(0, 1.4, 0))
		head.Parent = model
	elseif id == "Marteau" then
		model.Size = Vector3.new(0.35, 2.2, 0.35)
		model.Color = Color3.fromRGB(120, 85, 50)
		model.Material = Enum.Material.Wood
		local head = Instance.new("Part")
		head.Anchored = true
		head.CanCollide = false
		head.Size = Vector3.new(1.4, 0.6, 0.55)
		head.Color = Color3.fromRGB(160, 165, 175)
		head.Material = Enum.Material.Metal
		head.CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0))
		head.Parent = model
	elseif id == "MegaRouleau" then
		model.Size = Vector3.new(2.4, 2.4, 2.4)
		model.Color = Color3.fromRGB(255, 140, 60)
		model.Material = Enum.Material.SmoothPlastic
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Cylinder
		mesh.Parent = model
		model.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	elseif id == "Laser" then
		model.Size = Vector3.new(0.4, 2.2, 0.4)
		model.Color = Color3.fromRGB(50, 50, 60)
		model.Material = Enum.Material.SmoothPlastic
		local tip = Instance.new("Part")
		tip.Anchored = true
		tip.CanCollide = false
		tip.Shape = Enum.PartType.Ball
		tip.Size = Vector3.new(0.7, 0.7, 0.7)
		tip.Color = Color3.fromRGB(255, 60, 90)
		tip.Material = Enum.Material.Neon
		tip.CFrame = CFrame.new(pos + Vector3.new(0, 1.4, 0))
		tip.Parent = model
	elseif id == "Singularite" then
		model.Shape = Enum.PartType.Ball
		model.Size = Vector3.new(2.0, 2.0, 2.0)
		model.Color = Color3.fromRGB(180, 60, 255)
		model.Material = Enum.Material.Neon
	elseif id == "Ailes" then
		model.Size = Vector3.new(0.4, 0.4, 0.4)
		model.Color = Color3.fromRGB(120, 210, 255)
		model.Material = Enum.Material.Neon
		model.Transparency = 0.3
		for _, side in ipairs({ -1, 1 }) do
			local wing = Instance.new("Part")
			wing.Anchored = true
			wing.CanCollide = false
			wing.Size = Vector3.new(0.2, 1.2, 2.0)
			wing.Color = Color3.fromRGB(140, 220, 255)
			wing.Material = Enum.Material.SmoothPlastic
			wing.Transparency = 0.2
			wing.CFrame = CFrame.new(pos + Vector3.new(side * 1.1, 0, 0))
			wing.Parent = model
		end
	else
		model.Size = Vector3.new(2, 2, 2)
		model.Color = accent
		model.Material = Enum.Material.Neon
	end

	-- Rayon lumineux visible de loin
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.Transparency = 0.55
	beam.Material = Enum.Material.Neon
	beam.Color = accent
	beam.Size = Vector3.new(3, 200, 3)
	beam.CFrame = CFrame.new(pos + Vector3.new(0, 100, 0))
	beam.Parent = model

	local light = Instance.new("PointLight")
	light.Color = accent
	light.Range = 24
	light.Brightness = 3
	light.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(8, 2)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = def.Name
	label.TextColor3 = accent
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	return model
end

local function spawnInZone(zoneId: string): boolean
	local query = zoneQuery(zoneId)
	if not query then
		ItemSpawnPlanner.LogFailure(zoneId, "board not registered")
		return false
	end

	local plan, reason = ItemSpawnPlanner.Plan(zoneId, query, rng)
	if not plan then
		ItemSpawnPlanner.LogFailure(zoneId, reason or "unknown reason")
		return false
	end

	if not BubbleService.BoardFolder(zoneId) then
		ItemSpawnPlanner.LogFailure(zoneId, "board folder missing")
		return false
	end

	if not ToolDefs.Get(plan.ItemId) then
		ItemSpawnPlanner.LogFailure(zoneId, "unknown item " .. plan.ItemId)
		return false
	end

	return DropService.SpawnDropAt(zoneId, plan.ItemId, plan.X, plan.Z, {
		countTowardCap = true,
		announceRare = true,
	}) ~= nil
end

export type SpawnDropOptions = {
	countTowardCap: boolean?,
	announceRare: boolean?,
	lifetime: number?,
	ownerUserId: number?,
	tutorial: boolean?,
}

-- Spawn générique d'un drop au sol (aléatoire ou tutoriel guidé).
function DropService.SpawnDropAt(
	zoneId: string,
	itemId: string,
	cellX: number,
	cellZ: number,
	opts: SpawnDropOptions?
): BasePart?
	local options = opts or {}
	local def = ToolDefs.Get(itemId)
	if not def then
		return nil
	end
	local folder = BubbleService.BoardFolder(zoneId)
	if not folder then
		return nil
	end
	if not BubbleService.InBounds(cellX, cellZ, zoneId) then
		return nil
	end

	local pos = BubbleService.CellToWorld(cellX, cellZ, zoneId)
		+ Vector3.new(0, ItemSpawnPlanner.SpawnHeightOffset, 0)

	local model = buildDropVisual(itemId, def, pos)
	model:SetAttribute("ZoneId", zoneId)
	model:SetAttribute("ToolId", itemId)
	model:SetAttribute("CellX", cellX)
	model:SetAttribute("CellZ", cellZ)
	if options.tutorial == true then
		model:SetAttribute("TutorialDrop", true)
	end
	if type(options.ownerUserId) == "number" then
		model:SetAttribute("TutorialOwnerUserId", options.ownerUserId)
	end
	model.Parent = folder

	local countCap = options.countTowardCap ~= false
	local released = false
	if countCap then
		activeByZone[zoneId] = (activeByZone[zoneId] or 0) + 1
	else
		tutorialActiveByZone[zoneId] = (tutorialActiveByZone[zoneId] or 0) + 1
	end
	model.Destroying:Connect(function()
		if released then
			return
		end
		released = true
		if countCap then
			activeByZone[zoneId] = math.max(0, (activeByZone[zoneId] or 1) - 1)
		else
			tutorialActiveByZone[zoneId] = math.max(0, (tutorialActiveByZone[zoneId] or 1) - 1)
		end
	end)

	ItemSpawnPlanner.Log(
		"Spawned %s in %s at cell (%d, %d) world (%.1f, %.1f, %.1f)%s",
		def.Name,
		zoneId,
		cellX,
		cellZ,
		pos.X,
		pos.Y,
		pos.Z,
		if options.tutorial then " [tutorial]" else ""
	)

	local taken = false
	local ownerUserId = options.ownerUserId
	task.spawn(function()
		local radius = Config.Drops.PickupRadius
		while model.Parent and not taken do
			for _, plr in ipairs(Players:GetPlayers()) do
				if type(ownerUserId) == "number" and plr.UserId ~= ownerUserId then
					continue
				end
				local char = plr.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if root and hum and hum.Health > 0 then
					if (root.Position - pos).Magnitude <= radius then
						taken = true
						ToolService.Give(plr, itemId)
						ItemSpawnPlanner.Log("Picked up %s in %s by %s", def.Name, zoneId, plr.Name)
						model:Destroy()
						break
					end
				end
			end
			task.wait(Config.Drops.PickupRate)
		end
	end)

	task.spawn(function()
		while model.Parent do
			model.CFrame = model.CFrame * CFrame.Angles(0, math.rad(2), 0)
			task.wait(0.03)
		end
	end)

	if options.announceRare ~= false and (def.Rarity == "Epic" or def.Rarity == "Mythic") then
		Remotes.Event("Announce"):FireAllClients(
			("A %s item just appeared: %s"):format(def.Rarity, def.Name), "item")
	end

	Debris:AddItem(model, options.lifetime or Config.Drops.Lifetime)
	return model
end

-- Drop guidé pour le tutoriel : proche du joueur, réservé à ce UserId, hors cap aléatoire.
function DropService.SpawnTutorialDrop(player: Player, itemId: string): BasePart?
	if not player or not itemId then
		return nil
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

	local zoneId = "ClassicZone"
	local cellX, cellZ = 20, 6
	if root then
		local cx, cz, zid = BubbleService.WorldToCell(root.Position)
		if type(zid) == "string" and zid ~= "" then
			zoneId = zid
		end
		if type(cx) == "number" and type(cz) == "number" then
			-- Décaler de 2–3 cellules pour que le joueur voie le drop, pas sous ses pieds.
			cellX = cx + 2
			cellZ = math.max(1, cz - 1)
		end
	end

	if not BubbleService.InBounds(cellX, cellZ, zoneId) then
		local sizeX, sizeZ = 40, 40
		local board = BubbleService.GetBoard(zoneId)
		if board then
			sizeX = board.sizeX
			sizeZ = board.sizeZ
		end
		cellX = math.clamp(cellX, 1, sizeX)
		cellZ = math.clamp(cellZ, 1, sizeZ)
	end

	return DropService.SpawnDropAt(zoneId, itemId, cellX, cellZ, {
		countTowardCap = false,
		announceRare = false,
		tutorial = true,
		ownerUserId = player.UserId,
		lifetime = math.max(Config.Drops.Lifetime, 180),
	})
end

local function zoneLoop(zoneId: string)
	while true do
		local zoneCount = #BubbleService.ListBoardZoneIds()
		task.wait(ItemSpawnPlanner.NextDelay(zoneCount, rng))

		local active = activeByZone[zoneId] or 0
		local cap = ItemSpawnPlanner.MaxActivePerZone()
		if active >= cap then
			ItemSpawnPlanner.Log("%s skipped: %d active item(s), cap %d", zoneId, active, cap)
			continue
		end

		local ok, err = pcall(spawnInZone, zoneId)
		if not ok then
			warn(("[ItemSpawnDebug] %s spawn error: %s"):format(zoneId, tostring(err)))
		end
	end
end

-- Démarre une boucle par planche enregistrée (et pour toute planche ajoutée ensuite).
local function ensureZoneLoops(): number
	local zoneIds = BubbleService.ListBoardZoneIds()
	for _, zoneId in ipairs(zoneIds) do
		if not zoneLoops[zoneId] then
			zoneLoops[zoneId] = true
			ItemSpawnPlanner.Log("Spawn loop started for zone: %s", zoneId)
			task.spawn(zoneLoop, zoneId)
		end
	end
	return #zoneIds
end

function DropService.Start()
	task.spawn(function()
		-- Les planches sont construites par BubbleService.Start (qui yield) : on
		-- attend leur enregistrement avant de lancer la moindre boucle.
		local waited = 0
		while #BubbleService.ListBoardZoneIds() == 0 and waited < 120 do
			task.wait(0.5)
			waited += 1
		end

		if ensureZoneLoops() == 0 then
			warn("[DropService] aucune planche enregistrée : apparition d'objets inactive")
			return
		end

		while true do
			task.wait(30)
			ensureZoneLoops()
		end
	end)
end

return DropService
