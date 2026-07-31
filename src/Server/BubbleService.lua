--!strict
-- Cœur du jeu : génération multi-planches, éclatement, régénération,
-- récompenses (sac uniquement, jamais de pièces), anti-exploit
-- et diffusion groupée des effets.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ZoneDefs = require(Shared.ZoneDefs)
local BubbleTypes = require(Shared.BubbleTypes)
local BubbleValue = require(Shared.BubbleValue)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local BackpackService = require(script.Parent.BackpackService)
local GlobalCounterService = require(script.Parent.GlobalCounterService)
local ComboService = require(script.Parent.ComboService)
local AmbianceService = require(script.Parent.AmbianceService)

local G = Config.Grid
local B = Config.Bubble

type BoardState = {
	zoneId: string,
	themeId: string,
	origin: Vector3,
	sizeX: number,
	sizeZ: number,
	folder: Folder,
	grid: { [number]: { [number]: any } },
	rewardMult: number,
	tintVariants: { Color3 },
}

local BubbleService = {}
local boards: { [string]: BoardState } = {}
local boardList: { BoardState } = {}
local rng = Random.new()
local currentWorld = Config.Worlds[1]
local defaultZoneId = "ClassicZone"

-- Anti-exploit : budget de pops par joueur
local budget: { [Player]: { tokens: number, last: number } } = {}

-- File d'effets envoyée en lot aux clients : { x, z, rarityId, zoneId }
local effectQueue: { any } = {}

--------------------------------------------------------------------
-- Coordonnées (zone-aware)
--------------------------------------------------------------------
local function boardSizes(zoneId: string): (number, number)
	local board = boards[zoneId]
	if board then
		return board.sizeX, board.sizeZ
	end
	return ZoneDefs.GetGridSize(zoneId)
end

function BubbleService.CellToWorld(x: number, z: number, zoneId: string?): Vector3
	local id = zoneId or defaultZoneId
	local board = boards[id]
	local def = ZoneDefs.Get(id)
	local origin = if board then board.origin elseif def then def.Origin else G.Origin
	local sizeX, sizeZ = boardSizes(id)
	return origin + Vector3.new((x - sizeX / 2) * G.Spacing, 0, (z - sizeZ / 2) * G.Spacing)
end

function BubbleService.WorldToCell(pos: Vector3): (number, number, string)
	local bestId = ZoneDefs.ResolveZoneIdAt(pos)
	if #boardList > 0 then
		local contained: string? = nil
		local bestDist = math.huge
		local nearest = bestId
		for _, board in ipairs(boardList) do
			local halfX = (board.sizeX * G.Spacing) / 2
			local halfZ = (board.sizeZ * G.Spacing) / 2
			local o = board.origin
			local inside = pos.X >= o.X - halfX
				and pos.X <= o.X + halfX
				and pos.Z >= o.Z - halfZ
				and pos.Z <= o.Z + halfZ
			if inside then
				contained = board.zoneId
				break
			end
			local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(o.X, 0, o.Z)).Magnitude
			if d < bestDist then
				bestDist = d
				nearest = board.zoneId
			end
		end
		bestId = contained or nearest
	end
	local board = boards[bestId]
	local def = ZoneDefs.Get(bestId)
	local origin = if board then board.origin elseif def then def.Origin else G.Origin
	local sizeX, sizeZ = boardSizes(bestId)
	local rel = pos - origin
	return math.round(rel.X / G.Spacing + sizeX / 2),
		math.round(rel.Z / G.Spacing + sizeZ / 2),
		bestId
end

function BubbleService.InBounds(x: number, z: number, zoneId: string?): boolean
	return ZoneDefs.InBounds(x, z, zoneId or defaultZoneId)
end

function BubbleService.GetBoard(zoneId: string): BoardState?
	return boards[zoneId]
end

function BubbleService.GetZoneIdAt(pos: Vector3): string
	local _, _, zoneId = BubbleService.WorldToCell(pos)
	return zoneId
end

-- API commune : toute zone enregistre sa planche auprès du même BubbleService.
function BubbleService.RegisterBoard(zoneDef: any)
	return BubbleService.BuildBoard(zoneDef)
end

function BubbleService.RegisterZoneBoard(zoneId: string)
	local def = ZoneDefs.Get(zoneId)
	if not def then
		warn("[BubbleService] RegisterZoneBoard: zone inconnue " .. tostring(zoneId))
		return nil
	end
	return BubbleService.BuildBoard(def)
end

--------------------------------------------------------------------
-- Apparence visuelle (ne touche pas à la physique)
--------------------------------------------------------------------
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

local function normalizeCommonTints(common: any): { Color3 }?
	if common == nil then
		return nil
	end
	if typeof(common) == "Color3" then
		return { common :: Color3 }
	end
	if type(common) == "table" then
		local asTable = common :: { any }
		-- Liste de variantes (TintVariants) vs Color3 unique (champs R/G/B).
		if asTable[1] ~= nil then
			return asTable :: { Color3 }
		end
		if type(asTable.R) == "number" then
			return { common :: Color3 }
		end
	end
	return nil
end

-- Palette Normal par zone ; raretés restent sur BubbleTypes.
local function tintVariantsForZone(zoneId: string, zoneDef: any): { Color3 }
	local palettes = Config.ZoneBubblePalettes
	local paletteKey = if zoneId == "ClassicZone" then "GameRoom" else zoneId
	local palette = palettes and palettes[paletteKey]
	local fromPalette = palette and normalizeCommonTints(palette.Common)
	if fromPalette then
		return fromPalette
	end
	if zoneDef and zoneDef.BubbleTintVariants and #zoneDef.BubbleTintVariants > 0 then
		return zoneDef.BubbleTintVariants
	end
	return B.Appearance.TintVariants
end

local function resolveBubbleColor(def, tintIndex: number, tintVariants: { Color3 }): Color3
	local A = B.Appearance
	if def.Id == "Normal" then
		return tintVariants[((tintIndex - 1) % #tintVariants) + 1]
	end
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

local function applyBubbleAppearance(bubble: BasePart, def, tintIndex: number, alive: boolean, tintVariants: { Color3 })
	local A = B.Appearance
	clearStaleVisuals(bubble)

	bubble.Material = A.Material
	bubble.Color = resolveBubbleColor(def, tintIndex, tintVariants)
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
-- Construction d'une planche
--------------------------------------------------------------------
local function buildBubble(board: BoardState, x: number, z: number)
	local part = Instance.new("Part")
	part.Name = x .. "_" .. z
	part.Anchored = true
	part.Size = G.BubbleSize
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = B.Appearance.CastShadow
	part.CFrame = CFrame.new(BubbleService.CellToWorld(x, z, board.zoneId) + Vector3.new(0, 0.35, 0))
	part:SetAttribute("CellX", x)
	part:SetAttribute("CellZ", z)
	part:SetAttribute("Alive", true)
	part:SetAttribute("ZoneId", board.zoneId)
	-- Area : GameRoom (ClassicZone) ou SummerZone — identification explicite hors position joueur.
	part:SetAttribute("Area", if board.zoneId == "SummerZone" then "SummerZone" else "GameRoom")
	part:SetAttribute("ThemeId", board.themeId)
	part.CanQuery = true
	part.CanTouch = true

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = B.MeshScale
	mesh.Parent = part

	part.Parent = board.folder

	local tintIndex = rng:NextInteger(1, #board.tintVariants)
	local cell = {
		part = part,
		mesh = mesh,
		def = BubbleTypes.Roll(rng),
		alive = true,
		home = part.CFrame,
		tintIndex = tintIndex,
		zoneId = board.zoneId,
	}
	applyBubbleAppearance(part, cell.def, tintIndex, true, board.tintVariants)
	return cell
end

local function destroyBoard(zoneId: string)
	local board = boards[zoneId]
	if not board then
		return
	end
	if board.folder and board.folder.Parent then
		board.folder:Destroy()
	end
	boards[zoneId] = nil
	for i = #boardList, 1, -1 do
		if boardList[i].zoneId == zoneId then
			table.remove(boardList, i)
		end
	end
end

local function resolveParentFolder(zoneId: string): Instance
	local gameZones = workspace:FindFirstChild("GameZones")
	if gameZones then
		local zoneFolder = gameZones:FindFirstChild(zoneId)
		if zoneFolder then
			local existing = zoneFolder:FindFirstChild("BubbleBoard")
			if existing then
				existing:Destroy()
			end
			local folder = Instance.new("Folder")
			folder.Name = "BubbleBoard"
			folder.Parent = zoneFolder
			return folder
		end
	end

	-- Fallback : compatibilité si GameZones n'est pas encore prêt
	local name = if zoneId == defaultZoneId then "BubbleWorld" else ("BubbleWorld_" .. zoneId)
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = workspace
	return folder
end

function BubbleService.BuildBoard(zoneDef: any)
	local zoneId = zoneDef.Id :: string
	destroyBoard(zoneId)

	local tintVariants = tintVariantsForZone(zoneId, zoneDef)
	local folder = resolveParentFolder(zoneId) :: Folder
	local sizeX = zoneDef.SizeX or G.SizeX
	local sizeZ = zoneDef.SizeZ or G.SizeZ

	local board: BoardState = {
		zoneId = zoneId,
		themeId = zoneDef.ThemeId,
		origin = zoneDef.Origin,
		sizeX = sizeX,
		sizeZ = sizeZ,
		folder = folder,
		grid = {},
		rewardMult = zoneDef.RewardMultiplier or 1,
		tintVariants = tintVariants,
	}
	boards[zoneId] = board
	table.insert(boardList, board)

	do
		local halfX = (sizeX * G.Spacing) / 2 + 2
		local halfZ = (sizeZ * G.Spacing) / 2 + 2
		local thickness = 1.2
		local floorTopY = board.origin.Y - G.BubbleSize.Y * 0.35
		local floor = Instance.new("Part")
		floor.Name = "PlayFloor"
		floor.Anchored = true
		floor.CanCollide = true
		floor.CanQuery = false
		floor.CanTouch = false
		floor.CastShadow = false
		floor.Material = Enum.Material.SmoothPlastic
		floor.Color = zoneDef.FloorColor or Color3.fromRGB(18, 32, 58)
		floor.Transparency = if zoneDef.ThemeId == "Summer" then 0.25 else 0.4
		floor.Size = Vector3.new(halfX * 2, thickness, halfZ * 2)
		floor.CFrame = CFrame.new(board.origin.X, floorTopY - thickness / 2, board.origin.Z)
		floor:SetAttribute("GeneratedByCode", true)
		floor:SetAttribute("ZoneId", zoneId)
		floor.Parent = folder
	end

	for x = 1, sizeX do
		board.grid[x] = {}
		for z = 1, sizeZ do
			board.grid[x][z] = buildBubble(board, x, z)
		end
		if x % 6 == 0 then
			task.wait()
		end
	end

	return board
end

-- Legacy : reconstruit uniquement la planche classique (Prairie ambiance).
function BubbleService.BuildWorld(worldDef)
	currentWorld = worldDef or currentWorld
	BubbleService.RegisterBoard(ZoneDefs.ClassicZone)
	AmbianceService.Apply(currentWorld)
	local classic = boards[defaultZoneId]
	if classic then
		AmbianceService.BuildWalls(classic.folder)
	end
end

function BubbleService.BuildAllBoards()
	for _, zoneDef in ipairs(ZoneDefs.List) do
		BubbleService.RegisterBoard(zoneDef)
	end
	AmbianceService.Apply(currentWorld)
	local classic = boards[defaultZoneId]
	if classic then
		AmbianceService.BuildWalls(classic.folder)
	end
end

--------------------------------------------------------------------
-- Éclatement
--------------------------------------------------------------------
local function regen(cell)
	cell.popClaim = nil
	cell.def = BubbleTypes.Roll(rng)
	cell.alive = true
	cell.part.CanCollide = true
	cell.part.CanQuery = true
	cell.part.CanTouch = true
	cell.part:SetAttribute("Alive", true)
	cell.part.CFrame = cell.home
	cell.mesh.Scale = B.MeshScale
	local board = boards[cell.zoneId]
	local tints = if board then board.tintVariants else B.Appearance.TintVariants
	applyBubbleAppearance(cell.part, cell.def, cell.tintIndex, true, tints)
end

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

local function applyPop(cell: any, _x: number, _z: number): boolean
	if not cell.alive then return false end
	local part = cell.part :: BasePart?
	if not part or not part.Parent then return false end

	cell.alive = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part:SetAttribute("Alive", false)

	table.insert(effectQueue, { _x, _z, cell.def.Id, cell.zoneId })
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
	worldMult: number,
	extra: number,
	combo: () -> number,
}

-- Zone de la bulle (attribut / métadonnée cellule) — jamais la position du joueur.
local function resolveBubbleZoneId(cell: any): string
	local part = cell and cell.part
	if part then
		local attr = part:GetAttribute("ZoneId")
		if type(attr) == "string" and ZoneDefs.Get(attr) then
			return attr
		end
		local area = part:GetAttribute("Area")
		if area == "SummerZone" then
			return "SummerZone"
		elseif area == "GameRoom" then
			return "ClassicZone"
		end
	end
	if type(cell.zoneId) == "string" and ZoneDefs.Get(cell.zoneId) then
		return cell.zoneId
	end
	return defaultZoneId
end

local function popClaimedCell(player: Player, cell: any, x: number, z: number, ctx: PopContext): (string, any?)
	if not cell.alive then return "skip" end

	local def = cell.def
	if type(def) ~= "table" or type(def.Id) ~= "string" then return "skip" end

	local storage = math.max(1, math.floor(positiveNumber(def.StorageValue, 1)))
	if not BackpackService.CanAdd(player, storage) then
		return "full"
	end

	-- Valeur sac centralisée (SummerZone ×2). RewardMultiplier / XP inchangés.
	local zoneId = resolveBubbleZoneId(cell)
	local baseSell = BubbleValue.GetBaseBubbleValue(def.Id)
	local zoneBagMult = BubbleValue.GetZoneMultiplier(zoneId)
	local bagValue = BubbleValue.GetBubbleBagValue(def.Id, zoneId)
	BubbleValue.DebugLog(zoneId, def.Id, baseSell, zoneBagMult, bagValue)

	local raw = bagValue * ctx.coinMult * ctx.worldMult * ctx.extra * ctx.combo()
	local sellValue = BackpackService.RoundSellValue(raw, baseSell)
	if not sellValue or sellValue <= 0 then return "skip" end

	local added, err, tx = BackpackService.AddBubbles(player, storage, sellValue)
	if not added then
		return if err == BackpackService.ErrorCodes.BackpackFull then "full" else "skip"
	end

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

-- cells : { { x, z } } ou { { x, z, zoneId } }
function BubbleService.PopCells(player: Player, cells: { { any } }, multiplier: number?, zoneIdHint: string?): number
	if not DataService.Get(player) then return 0 end

	local coinMult = DataService.Multipliers(player)
	local comboMult: number? = nil

	local ctx: PopContext = {
		coinMult = coinMult,
		worldMult = currentWorld.Mult,
		extra = multiplier or 1,
		combo = function(): number
			if not comboMult then
				comboMult = ComboService.Register(player)
			end
			return comboMult :: number
		end,
	}

	local count = 0
	local announce = nil
	local notifiedFull = false

	for _, c in ipairs(cells) do
		local x, z = c[1], c[2]
		local zid = (c[3] or zoneIdHint or defaultZoneId) :: string
		if type(x) == "number" and type(z) == "number" and BubbleService.InBounds(x, z, zid) then
			local profile = DataService.Get(player)
			if not profile or not ZoneDefs.CanLevelEnter(DataService.GetPlayerLevel(player), zid) then
				continue
			end
			local board = boards[zid]
			local cell = board and board.grid[x] and board.grid[x][z]
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
					releaseClaim(cell, token)

					if ok and status == "ok" and def then
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

	profile.Pops += count
	profile.__dirty = true
	DataService.Push(player)
	GlobalCounterService.Add(count)

	if announce then
		Remotes.Event("Announce"):FireAllClients(
			("%s popped a %s!"):format(player.DisplayName, announce.Label), "legendary")
	end

	return count
end

--------------------------------------------------------------------
-- Requêtes client
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

-- Résout la planche via ZoneId client ou cellule vivante — pas uniquement la position joueur.
local function resolvePopBoardZone(x: number, z: number, zoneIdArg: any): string?
	if type(zoneIdArg) == "string" and ZoneDefs.Get(zoneIdArg) and BubbleService.InBounds(x, z, zoneIdArg) then
		local board = boards[zoneIdArg]
		local cell = board and board.grid[x] and board.grid[x][z]
		if cell then
			return zoneIdArg
		end
	end
	for _, board in ipairs(boardList) do
		if BubbleService.InBounds(x, z, board.zoneId) then
			local cell = board.grid[x] and board.grid[x][z]
			if cell and cell.alive then
				local attr = cell.part and cell.part:GetAttribute("ZoneId")
				if type(attr) == "string" and ZoneDefs.Get(attr) then
					return attr
				end
				return board.zoneId
			end
		end
	end
	if type(zoneIdArg) == "string" and ZoneDefs.Get(zoneIdArg) and BubbleService.InBounds(x, z, zoneIdArg) then
		return zoneIdArg
	end
	return nil
end

local function onPopRequest(player: Player, x: any, z: any, zoneIdArg: any)
	if type(x) ~= "number" or type(z) ~= "number" then return end
	x, z = math.floor(x), math.floor(z)
	if not checkBudget(player) then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local zoneId = resolvePopBoardZone(x, z, zoneIdArg)
	if not zoneId then return end

	local target = BubbleService.CellToWorld(x, z, zoneId)
	local maxRange = if player:GetAttribute("HasWings") == true then B.WingPopRange else B.MaxPopRange
	if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude > maxRange then
		return
	end

	local profile = DataService.Get(player)
	if not profile or not ZoneDefs.CanLevelEnter(DataService.GetPlayerLevel(player), zoneId) then
		return
	end
	local power = Config.EffectiveUpgradeLevel("Power", profile.Upgrades.Power or 0)

	local cells: { { any } } = { { x, z, zoneId } }
	if power > 0 then
		local r = math.floor(power / 2)
		if r > 0 then
			cells = {}
			for dx = -r, r do
				for dz = -r, r do
					if dx * dx + dz * dz <= r * r then
						table.insert(cells, { x + dx, z + dz, zoneId })
					end
				end
			end
		end
	end

	BubbleService.PopCells(player, cells, nil, zoneId)
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

-- Compat : dossier de la planche classique (drops / coffres).
function BubbleService.WorldFolder()
	local board = boards[defaultZoneId]
	return if board then board.folder else nil
end

function BubbleService.BoardFolder(zoneId: string): Folder?
	local board = boards[zoneId]
	return if board then board.folder else nil
end

function BubbleService.ListBoardZoneIds(): { string }
	local ids = {}
	for _, board in ipairs(boardList) do
		table.insert(ids, board.zoneId)
	end
	return ids
end

function BubbleService.IsAlive(x: number, z: number, zoneId: string?): boolean
	local zid = zoneId or defaultZoneId
	if not BubbleService.InBounds(x, z, zid) then return false end
	local board = boards[zid]
	local cell = board and board.grid[x] and board.grid[x][z]
	return cell ~= nil and cell.alive == true
end

function BubbleService.Start()
	-- ZoneService.EnsureWorld crée GameZones avant ; BuildAllBoards y accroche les planches.
	BubbleService.BuildAllBoards()
	Remotes.Event("PopRequest").OnServerEvent:Connect(onPopRequest)
	Players.PlayerRemoving:Connect(function(p) budget[p] = nil end)
	startEffectLoop()
end

return BubbleService
