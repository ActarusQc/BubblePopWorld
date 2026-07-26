--!strict
-- Cœur du jeu : génération de la grille, éclatement, régénération,
-- récompenses (sac uniquement, jamais de pièces), anti-exploit
-- et diffusion groupée des effets.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local BubbleTypes = require(Shared.BubbleTypes)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local BackpackService = require(script.Parent.BackpackService)
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

	-- Plateau de support discret : les bulles restent la surface principale quand
	-- elles sont intactes ; une fois éclatées, le joueur reste sur ce sol (plus de chute).
	do
		local halfX = (G.SizeX * G.Spacing) / 2 + 2
		local halfZ = (G.SizeZ * G.Spacing) / 2 + 2
		local thickness = 1.2
		-- Dessous du volume des bulles : petit écart pour ne pas masquer le look.
		local floorTopY = G.Origin.Y - G.BubbleSize.Y * 0.35
		local floor = Instance.new("Part")
		floor.Name = "PlayFloor"
		floor.Anchored = true
		floor.CanCollide = true
		floor.CanQuery = false
		floor.CanTouch = false
		floor.CastShadow = false
		floor.Material = Enum.Material.SmoothPlastic
		floor.Color = Color3.fromRGB(18, 32, 58)
		floor.Transparency = 0.4
		floor.Size = Vector3.new(halfX * 2, thickness, halfZ * 2)
		floor.CFrame = CFrame.new(G.Origin.X, floorTopY - thickness / 2, G.Origin.Z)
		floor:SetAttribute("GeneratedByCode", true)
		floor.Parent = worldFolder
	end

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
	-- Un claim ne doit jamais survivre au cycle de régénération.
	cell.popClaim = nil
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

--------------------------------------------------------------------
-- Verrou de cellule : jeton unique, un seul joueur gagne la course
--------------------------------------------------------------------
local function tryClaim(cell: any): any?
	if not cell.alive or cell.popClaim ~= nil then return nil end
	local token = {}
	cell.popClaim = token
	return token
end

local function releaseClaim(cell: any, token: any)
	if cell.popClaim == token then
		cell.popClaim = nil
	end
end

-- Mutation réelle de la bulle. Retourne false si la case n'est plus éclatable.
local function applyPop(cell: any, x: number, z: number): boolean
	if not cell.alive then return false end
	local part = cell.part :: BasePart?
	if not part or not part.Parent then return false end

	cell.alive = false
	part.CanCollide = false
	-- CanQuery = false : le raycast client traverse la case vide (plus de faux rebonds)
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part:SetAttribute("Alive", false)

	table.insert(effectQueue, { x, z, cell.def.Id })
	task.delay(B.RegenTime, function()
		if cell.part.Parent then regen(cell) end
	end)

	return true
end

local function positiveNumber(value: any, fallback: number): number
	local n = tonumber(value)
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge or n <= 0 then
		return fallback
	end
	return n
end

type PopContext = {
	coinMult: number,
	xpMult: number,
	worldMult: number,
	extra: number,
	combo: () -> number,
}

-- Traite une cellule déjà réservée (claim posé par l'appelant).
-- Retourne "ok" (+ def), "full" (sac plein) ou "skip".
local function popClaimedCell(player: Player, cell: any, x: number, z: number, ctx: PopContext): (string, any?)
	if not cell.alive then return "skip" end

	local def = cell.def
	if type(def) ~= "table" or type(def.Id) ~= "string" then return "skip" end

	local storage = math.max(1, math.floor(positiveNumber(def.StorageValue, 1)))
	if not BackpackService.CanAdd(player, storage) then
		return "full"
	end

	local baseSell = positiveNumber(def.SellValue, positiveNumber(def.Coins, 1))
	local raw = baseSell * ctx.coinMult * ctx.worldMult * ctx.extra * ctx.combo()
	local sellValue = BackpackService.RoundSellValue(raw, baseSell)
	if not sellValue or sellValue <= 0 then return "skip" end

	local added, err, tx = BackpackService.AddBubbles(player, storage, sellValue)
	if not added then
		return if err == BackpackService.ErrorCodes.BackpackFull then "full" else "skip"
	end

	-- Le pop réel est le seul point où une erreur Lua laisserait une transaction
	-- orpheline : on le protège explicitement pour garantir le rollback.
	local popOk, popped = pcall(applyPop, cell, x, z)
	if not popOk then
		warn(("[BubbleService] pop échoué en %d,%d : %s"):format(x, z, tostring(popped)))
	end
	if not popOk or popped ~= true then
		if not BackpackService.RollbackAdd(player, tx) then
			warn(("[BubbleService] rollback du sac échoué en %d,%d"):format(x, z))
		end
		return "skip"
	end

	return "ok", def
end

-- API publique : éclate une liste de cellules pour un joueur.
-- Les bulles ne créditent JAMAIS de pièces ici : elles remplissent le sac
-- (vente via BackpackService.Sell). L'XP reste immédiate après un pop réussi.
function BubbleService.PopCells(player: Player, cells: { { number } }, multiplier: number?): number
	if not DataService.Get(player) then return 0 end

	local coinMult, xpMult = DataService.Multipliers(player)

	-- Le combo n'est enregistré qu'une fois par lot, et seulement si au moins une
	-- cellule est réellement sur le point d'être ajoutée au sac.
	local comboMult: number? = nil
	local ctx: PopContext = {
		coinMult = coinMult,
		xpMult = xpMult,
		worldMult = currentWorld.Mult,
		extra = multiplier or 1,
		combo = function(): number
			if not comboMult then
				comboMult = ComboService.Register(player)
			end
			return comboMult :: number
		end,
	}

	local rawXP, count = 0, 0
	local announce = nil
	local notifiedFull = false

	for _, c in ipairs(cells) do
		local x, z = c[1], c[2]
		if BubbleService.InBounds(x, z) then
			local cell = grid[x] and grid[x][z]
			if cell then
				local token = tryClaim(cell)
				if token then
					local status: string? = nil
					local def: any = nil
					local ok = xpcall(function()
						status, def = popClaimedCell(player, cell, x, z, ctx)
					end, function(err)
						warn(("[BubbleService] erreur de pop en %d,%d : %s"):format(x, z, tostring(err)))
					end)
					releaseClaim(cell, token) -- garanti sur tous les chemins

					if ok and status == "ok" and def then
						rawXP += positiveNumber(def.XP, 0)
						count += 1
						if def.Announce then announce = def end
					elseif ok and status == "full" and not notifiedFull then
						notifiedFull = true
						BackpackService.NotifyFull(player)
					end
				end
			end
		end
	end

	if count == 0 then return 0 end

	local profile = DataService.Get(player)
	if not profile then return count end

	local xp = math.floor(rawXP * xpMult * ctx.extra * (comboMult or 1))
	if xp > 0 then
		DataService.AddXP(player, xp)
	end
	profile.Pops += count
	profile.__dirty = true
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
