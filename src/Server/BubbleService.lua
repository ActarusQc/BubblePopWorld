--!strict
-- Cœur du jeu : génération de la grille, éclatement, régénération,
-- récompenses, anti-exploit et diffusion groupée des effets.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local BubbleTypes = require(Shared.BubbleTypes)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local GlobalCounterService = require(script.Parent.GlobalCounterService)
local ComboService = require(script.Parent.ComboService)
local AmbianceService = require(script.Parent.AmbianceService)

local G = Config.Grid
local B = Config.Bubble

local BubbleService = {}
local grid: { [number]: { [number]: any } } = {}
local rng = Random.new()
local worldFolder: Folder
local currentWorld = Config.Worlds[1]

-- Anti-exploit : budget de pops par joueur
local budget: { [Player]: { tokens: number, last: number } } = {}

-- File d'effets envoyée en lot aux clients
local effectQueue: { any } = {}

--------------------------------------------------------------------
-- Coordonnées
--------------------------------------------------------------------
function BubbleService.CellToWorld(x: number, z: number): Vector3
	return G.Origin + Vector3.new((x - G.SizeX / 2) * G.Spacing, 0, (z - G.SizeZ / 2) * G.Spacing)
end

function BubbleService.WorldToCell(pos: Vector3): (number, number)
	local rel = pos - G.Origin
	return math.round(rel.X / G.Spacing + G.SizeX / 2),
	       math.round(rel.Z / G.Spacing + G.SizeZ / 2)
end

function BubbleService.InBounds(x: number, z: number): boolean
	return x >= 1 and x <= G.SizeX and z >= 1 and z <= G.SizeZ
end

--------------------------------------------------------------------
-- Apparence visuelle (ne touche pas à la physique)
--------------------------------------------------------------------
-- Effets obsolètes (écrans blancs / overlays) — toujours purgés.
-- BubbleHighlight / BubbleReflection sont gérés par ensure* (réutilisation).
local STALE_VISUAL_NAMES = {
	BubbleSurface = true,
	BubbleTexture = true,
	BubbleGlow = true,
	BubbleGui = true,
	BubbleSheet = true,
}

local function clearStaleVisuals(bubble: BasePart)
	for _, child in ipairs(bubble:GetChildren()) do
		if STALE_VISUAL_NAMES[child.Name] then
			child:Destroy()
		elseif child:IsA("SurfaceGui") or child:IsA("BillboardGui") then
			if child.Name:find("Bubble") then
				child:Destroy()
			end
		elseif (child:IsA("Decal") or child:IsA("Texture")) and child.Name:find("Bubble") then
			child:Destroy()
		end
	end
end

local function resolveBubbleColor(def, tintIndex: number): Color3
	local A = B.Appearance
	if def.Id == "Normal" then
		local variants = A.TintVariants
		return variants[((tintIndex - 1) % #variants) + 1]
	end
	-- Raretés : teinte du type, légèrement tirée vers le cyan de base (irisé)
	local base = A.BaseColor
	local c = def.Color
	return Color3.new(
		c.R * 0.75 + base.R * 0.25,
		c.G * 0.75 + base.G * 0.25,
		c.B * 0.75 + base.B * 0.25
	)
end

local function ensureHighlight(bubble: BasePart)
	local A = B.Appearance
	local highlight = bubble:FindFirstChild("BubbleHighlight") :: Highlight?
	if not A.EnableHighlight then
		if highlight then highlight:Destroy() end
		return
	end
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "BubbleHighlight"
		highlight.Adornee = bubble
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = bubble
	end
	highlight.FillTransparency = 1
	highlight.FillColor = Color3.fromRGB(0, 0, 0)
	highlight.OutlineTransparency = A.OutlineTransparency
	highlight.OutlineColor = A.OutlineColor
end

local function ensureReflection(bubble: BasePart)
	local A = B.Appearance
	local spark = bubble:FindFirstChild("BubbleReflection") :: BasePart?
	if not A.EnableReflection then
		if spark then spark:Destroy() end
		return
	end
	if not spark then
		spark = Instance.new("Part")
		spark.Name = "BubbleReflection"
		spark.Shape = Enum.PartType.Ball
		spark.Size = A.ReflectionSize
		spark.Transparency = A.ReflectionTransparency
		spark.Color = Color3.fromRGB(210, 240, 255)
		spark.CanCollide = false
		spark.CanQuery = false
		spark.CanTouch = false
		spark.CastShadow = false
		spark.Massless = true
		spark.Anchored = false
		spark.Material = Enum.Material.SmoothPlastic
		spark.Reflectance = 0
		spark.CFrame = bubble.CFrame * CFrame.new(0.85, bubble.Size.Y * 0.28, -0.65)
		spark.Parent = bubble

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bubble
		weld.Part1 = spark
		weld.Parent = spark
	else
		spark.Size = A.ReflectionSize
		spark.Transparency = A.ReflectionTransparency
		spark.Color = Color3.fromRGB(210, 240, 255)
	end
end

local function applyBubbleAppearance(bubble: BasePart, def, tintIndex: number, alive: boolean)
	local A = B.Appearance
	clearStaleVisuals(bubble)

	bubble.Material = A.Material
	bubble.Color = resolveBubbleColor(def, tintIndex)
	bubble.Reflectance = A.Reflectance
	bubble.CastShadow = A.CastShadow
	if alive then
		bubble.Transparency = A.Transparency
	end
	bubble:SetAttribute("Rarity", def.Id)

	ensureHighlight(bubble)
	ensureReflection(bubble)
end

--------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------
local function buildBubble(x: number, z: number)
	local part = Instance.new("Part")
	part.Name = x .. "_" .. z
	part.Anchored = true
	part.Size = G.BubbleSize
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = B.Appearance.CastShadow
	-- Position inchangée (gameplay)
	part.CFrame = CFrame.new(BubbleService.CellToWorld(x, z) + Vector3.new(0, 0.35, 0))
	part:SetAttribute("CellX", x)
	part:SetAttribute("CellZ", z)
	part:SetAttribute("Alive", true)
	part.CanQuery = true
	part.CanTouch = true

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = B.MeshScale
	mesh.Parent = part

	part.Parent = worldFolder

	local tintIndex = rng:NextInteger(1, #B.Appearance.TintVariants)
	local cell = {
		part = part,
		mesh = mesh,
		def = BubbleTypes.Roll(rng),
		alive = true,
		home = part.CFrame,
		tintIndex = tintIndex,
	}
	applyBubbleAppearance(part, cell.def, tintIndex, true)
	return cell
end

function BubbleService.BuildWorld(worldDef)
	currentWorld = worldDef or currentWorld

	if worldFolder then worldFolder:Destroy() end
	grid = {}

	worldFolder = Instance.new("Folder")
	worldFolder.Name = "BubbleWorld"
	worldFolder.Parent = workspace

	-- Plancher sous la nappe de bulles (pas de film blanc)
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(G.SizeX * G.Spacing + 40, 4, G.SizeZ * G.Spacing + 40)
	floor.CFrame = CFrame.new(G.Origin - Vector3.new(0, 3, 0))
	floor.Color = currentWorld.Ground
	floor.Material = Enum.Material.Sand
	floor.Parent = worldFolder

	for x = 1, G.SizeX do
		grid[x] = {}
		for z = 1, G.SizeZ do
			grid[x][z] = buildBubble(x, z)
		end
		if x % 6 == 0 then task.wait() end -- évite le gel du serveur au démarrage
	end

	AmbianceService.Apply(currentWorld)
	AmbianceService.BuildWalls(worldFolder)
end

--------------------------------------------------------------------
-- Éclatement
--------------------------------------------------------------------
local function regen(cell)
	cell.def = BubbleTypes.Roll(rng)
	cell.alive = true
	cell.part.CanCollide = true
	cell.part.CanQuery = true
	cell.part.CanTouch = true
	cell.part:SetAttribute("Alive", true)
	cell.part.CFrame = cell.home
	cell.mesh.Scale = B.MeshScale
	applyBubbleAppearance(cell.part, cell.def, cell.tintIndex, true)
end

-- Retourne pièces, xp, def (ou nil si la bulle n'était pas disponible)
local function popCell(x: number, z: number)
	if not BubbleService.InBounds(x, z) then return nil end
	local cell = grid[x] and grid[x][z]
	if not cell or not cell.alive then return nil end

	local def = cell.def
	cell.alive = false
	cell.part.CanCollide = false
	-- CanQuery = false : le raycast client traverse la case vide (plus de faux rebonds)
	cell.part.CanQuery = false
	cell.part.CanTouch = false
	cell.part.Transparency = 1
	cell.part:SetAttribute("Alive", false)

	table.insert(effectQueue, { x, z, def.Id })
	task.delay(B.RegenTime, function()
		if cell.part.Parent then regen(cell) end
	end)

	return def
end

-- API publique : éclate une liste de cellules pour un joueur.
function BubbleService.PopCells(player: Player, cells: { { number } }, multiplier: number?)
	local profile = DataService.Get(player)
	if not profile then return 0 end

	local coinMult, xpMult = DataService.Multipliers(player)
	local worldMult = currentWorld.Mult
	local extra = multiplier or 1

	local coins, xp, count = 0, 0, 0
	local announce = nil

	for _, c in ipairs(cells) do
		local def = popCell(c[1], c[2])
		if def then
			coins += def.Coins
			xp += def.XP
			count += 1
			if def.Announce then announce = def end
		end
	end

	if count == 0 then return 0 end

	local comboMult = ComboService.Register(player)

	coins = math.floor(coins * coinMult * worldMult * extra * comboMult)
	xp = math.floor(xp * xpMult * extra * comboMult)

	DataService.AddCoins(player, coins)
	DataService.AddXP(player, xp)
	profile.Pops += count
	DataService.Push(player)
	GlobalCounterService.Add(count)

	if announce then
		Remotes.Event("Announce"):FireAllClients(
			("%s a éclaté une %s !"):format(player.DisplayName, announce.Label), "legendary")
	end

	return count
end

--------------------------------------------------------------------
-- Requêtes client (marcher / sauter sur les bulles)
--------------------------------------------------------------------
local function checkBudget(player: Player): boolean
	local b = budget[player]
	local now = os.clock()
	if not b then
		b = { tokens = B.MaxPopsPerSecond, last = now }
		budget[player] = b
	end
	b.tokens = math.min(B.MaxPopsPerSecond, b.tokens + (now - b.last) * B.MaxPopsPerSecond)
	b.last = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

local function onPopRequest(player: Player, x: any, z: any)
	if type(x) ~= "number" or type(z) ~= "number" then return end
	x, z = math.floor(x), math.floor(z)
	if not BubbleService.InBounds(x, z) then return end
	if not checkBudget(player) then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	-- Validation de distance : impossible de "popper" à l'autre bout de la carte.
	local target = BubbleService.CellToWorld(x, z)
	local maxRange = if player:GetAttribute("HasWings") == true then B.WingPopRange else B.MaxPopRange
	if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude > maxRange then
		return
	end

	local profile = DataService.Get(player)
	local power = profile and profile.Upgrades.Power or 0

	local cells = { { x, z } }
	if power > 0 then
		local r = math.floor(power / 2)
		if r > 0 then
			cells = {}
			for dx = -r, r do
				for dz = -r, r do
					if dx * dx + dz * dz <= r * r then
						table.insert(cells, { x + dx, z + dz })
					end
				end
			end
		end
	end

	BubbleService.PopCells(player, cells)
end

--------------------------------------------------------------------
-- Diffusion groupée des effets
--------------------------------------------------------------------
local function startEffectLoop()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < B.EffectFlushRate then return end
		acc = 0
		if #effectQueue == 0 then return end
		local batch = effectQueue
		effectQueue = {}
		Remotes.Event("PopEffects"):FireAllClients(batch)
	end)
end

function BubbleService.CurrentWorld() return currentWorld end
function BubbleService.WorldFolder() return worldFolder end

function BubbleService.IsAlive(x: number, z: number): boolean
	if not BubbleService.InBounds(x, z) then return false end
	local cell = grid[x] and grid[x][z]
	return cell ~= nil and cell.alive == true
end

function BubbleService.Start()
	BubbleService.BuildWorld(Config.Worlds[1])
	Remotes.Event("PopRequest").OnServerEvent:Connect(onPopRequest)
	Players.PlayerRemoving:Connect(function(p) budget[p] = nil end)
	startEffectLoop()
end

return BubbleService
