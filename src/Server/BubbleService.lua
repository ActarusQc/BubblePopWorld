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
local BubbleAppearance = require(Shared.BubbleAppearance)
local BubbleValue = require(Shared.BubbleValue)
local HubLayout = require(Shared.HubLayout)
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
local function tintVariantsForZone(zoneId: string, zoneDef: any): { Color3 }
	local palette = BubbleAppearance.GetNormalPalette(zoneId)
	if #palette > 0 then
		return palette
	end
	if zoneDef and zoneDef.BubbleTintVariants and #zoneDef.BubbleTintVariants > 0 then
		return zoneDef.BubbleTintVariants
	end
	return B.Appearance.TintVariants
end

local function neighborTintIndices(board: BoardState, x: number, z: number): { number }
	local indices: { number } = {}
	for dx = -1, 1 do
		for dz = -1, 1 do
			if dx ~= 0 or dz ~= 0 then
				local col = board.grid[x + dx]
				local cell = col and col[z + dz]
				if cell and cell.def and cell.def.Id == "Normal" and type(cell.tintIndex) == "number" then
					table.insert(indices, cell.tintIndex)
				end
			end
		end
	end
	return indices
end

local function applyBubbleAppearance(bubble: BasePart, zoneId: string, def, tintIndex: number, alive: boolean)
	BubbleAppearance.ApplyToPart(bubble, zoneId, def.Id, tintIndex, alive)
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
	part:SetAttribute("Area", if board.zoneId == "SummerZone" then "SummerZone" else "GameRoom")
	part:SetAttribute("ThemeId", board.themeId)
	part.CanQuery = true
	part.CanTouch = true

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = B.MeshScale
	mesh.Parent = part

	part.Parent = board.folder

	-- 1) type réel d'abord (jamais une couleur)
	local def = BubbleTypes.Roll(rng)
	local tintIndex = 1
	if def.Id == "Normal" then
		-- 2) palette zone uniquement pour Normal
		tintIndex = BubbleAppearance.PickTintIndex(
			#board.tintVariants,
			neighborTintIndices(board, x, z),
			rng
		)
	end

	local cell = {
		part = part,
		mesh = mesh,
		def = def,
		alive = true,
		home = part.CFrame,
		tintIndex = tintIndex,
		zoneId = board.zoneId,
	}
	-- 3) apparence + effets après type confirmé
	applyBubbleAppearance(part, board.zoneId, cell.def, tintIndex, true)
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

	-- Cellules réservées : emprise du hub central + sa descente. La case reste nil
	-- (jamais de bulle fantôme dans la structure) ; tous les accès grid sont déjà
	-- protégés par `if cell then`.
	local reserved = 0
	for x = 1, sizeX do
		board.grid[x] = {}
		for z = 1, sizeZ do
			if HubLayout.IsCellReserved(zoneId, x, z) then
				reserved += 1
			else
				board.grid[x][z] = buildBubble(board, x, z)
			end
		end
		if x % 6 == 0 then
			task.wait()
		end
	end
	if reserved > 0 then
		print(("[BubbleService] %s : %d cellules réservées au hub central."):format(zoneId, reserved))
	end

	BubbleService.RunBubbleDiagnostics(zoneId)
	BubbleService.MaybeBuildSpecialPreviewRow(zoneId)

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
	-- 1) type réel d'abord
	cell.def = BubbleTypes.Roll(rng)
	cell.alive = true
	cell.part.CanCollide = true
	cell.part.CanQuery = true
	cell.part.CanTouch = true
	cell.part:SetAttribute("Alive", true)
	cell.part.CFrame = cell.home
	cell.mesh.Scale = B.MeshScale
	local board = boards[cell.zoneId]
	local paletteSize = if board then #board.tintVariants else #B.Appearance.TintVariants
	local x = cell.part:GetAttribute("CellX")
	local z = cell.part:GetAttribute("CellZ")
	if cell.def.Id == "Normal" then
		local neighbors = if board and type(x) == "number" and type(z) == "number"
			then neighborTintIndices(board, x, z)
			else {}
		cell.tintIndex = BubbleAppearance.PickTintIndex(paletteSize, neighbors, rng)
	else
		cell.tintIndex = 1
	end
	applyBubbleAppearance(cell.part, cell.zoneId, cell.def, cell.tintIndex, true)
	cell.eventVariant = nil
	cell.part:SetAttribute("EventVariant", nil)
	local ring = cell.part:FindFirstChild("EventMarkRing")
	if ring then
		ring:Destroy()
	end
	pcall(function()
		require(script.Parent.MiniEventService).OnBubbleReady(cell)
	end)
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
	part:SetAttribute("Alive", false)
	applyBubbleAppearance(part, cell.zoneId, cell.def, cell.tintIndex, false)

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

local function isSpecialRarity(rarityId: string): boolean
	return rarityId ~= "Normal"
end

-- Analytics : ClassicZone → GameRoom ; SummerZone inchangé.
local function analyticsZoneId(zoneId: string): string
	if zoneId == "SummerZone" then
		return "SummerZone"
	end
	return "GameRoom"
end

local function notifyBubblePoppedAnalytics(player: Player, zoneId: string, rarityId: string)
	pcall(function()
		local GAS = require(script.Parent.GameAnalyticsService)
		GAS.OnBubblePopped(player, {
			zoneId = analyticsZoneId(zoneId),
			rarityId = rarityId,
			isSpecial = isSpecialRarity(rarityId),
		})
	end)
	pcall(function()
		require(script.Parent.OnboardingService).Refresh(player)
	end)
end

local function notifyBubblesAddedToBagAnalytics(
	player: Player,
	storageAdded: number,
	sellValueAdded: number,
	zoneId: string,
	becameFull: boolean,
	wasBelowCapacity: boolean
)
	pcall(function()
		local GAS = require(script.Parent.GameAnalyticsService)
		GAS.OnBubblesAddedToBag(player, {
			storageAdded = storageAdded,
			sellValueAdded = sellValueAdded,
			zoneId = analyticsZoneId(zoneId),
			becameFull = becameFull,
			wasBelowCapacity = wasBelowCapacity,
		})
	end)
end

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

	local eventMult = 1
	pcall(function()
		local MiniEventService = require(script.Parent.MiniEventService)
		eventMult = MiniEventService.GetPopSellMultiplier(cell)
	end)
	if type(eventMult) ~= "number" or eventMult ~= eventMult or eventMult <= 0 then
		eventMult = 1
	end

	local otherMult = ctx.coinMult * ctx.worldMult * ctx.extra * ctx.combo()
	local raw = bagValue * otherMult * eventMult
	local sellValue = BackpackService.RoundSellValue(raw, baseSell)
	if not sellValue or sellValue <= 0 then return "skip" end

	local eventBonusCoins = 0
	if eventMult > 1 then
		local sellWithout = BackpackService.RoundSellValue(bagValue * otherMult, baseSell)
		if sellWithout then
			eventBonusCoins = math.max(0, sellValue - sellWithout)
		end
	end

	local wasBelowCapacity = not BackpackService.IsFull(player)
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

	local challengeTags = { isGoldenWave = false, isColorRushMatch = false }
	pcall(function()
		local MiniEventService = require(script.Parent.MiniEventService)
		if MiniEventService.GetPopChallengeTags then
			challengeTags = MiniEventService.GetPopChallengeTags(cell)
		end
	end)

	pcall(function()
		require(script.Parent.ChallengeService).OnBubblePopped(player, {
			zoneId = zoneId,
			rarityId = def.Id,
			isSpecial = isSpecialRarity(def.Id),
			isGoldenWave = challengeTags.isGoldenWave == true,
			isColorRushMatch = challengeTags.isColorRushMatch == true,
			isTutorial = false,
		})
	end)

	pcall(function()
		require(script.Parent.MiniEventService).OnBubblePopped(player, cell, eventBonusCoins)
	end)

	local becameFull = wasBelowCapacity and BackpackService.IsFull(player)
	notifyBubblePoppedAnalytics(player, zoneId, def.Id)
	-- Valeurs réellement acceptées par la transaction (pas la théorie pré-Add).
	local storageAdded = if tx then tx.StorageAdded else storage
	local sellValueAdded = if tx then tx.SellValueAdded else sellValue
	notifyBubblesAddedToBagAnalytics(player, storageAdded, sellValueAdded, zoneId, becameFull, wasBelowCapacity)
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

	pcall(function()
		require(script.Parent.TutorialService).OnBubblesPopped(player, count)
	end)

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
	if not zoneId then
		-- Tentative Giant Bubble même hors cellule de grille.
		pcall(function()
			require(script.Parent.MiniEventService).TryGiantHit(player, root.Position, "Jump")
		end)
		return
	end

	local target = BubbleService.CellToWorld(x, z, zoneId)
	local maxRange = if player:GetAttribute("HasWings") == true then B.WingPopRange else B.MaxPopRange
	if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude > maxRange then
		return
	end

	-- Giant bubble prioritaire si à portée
	pcall(function()
		require(script.Parent.MiniEventService).TryGiantHit(player, root.Position, "Jump")
	end)

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

-- Compte les bulles d'une planche (Studio / DiagnosticsEnabled).
function BubbleService.CountBoardRarities(zoneId: string): {
	byType: { [string]: number },
	total: number,
	totalSpecial: number,
	minValue: number,
	maxValue: number,
}
	local board = boards[zoneId]
	local byType: { [string]: number } = {}
	local total = 0
	local totalSpecial = 0
	local minValue = math.huge
	local maxValue = 0
	if board then
		for x = 1, board.sizeX do
			local col = board.grid[x]
			if col then
				for z = 1, board.sizeZ do
					local cell = col[z]
					if cell and cell.def then
						local id = cell.def.Id
						byType[id] = (byType[id] or 0) + 1
						total += 1
						local v = BubbleValue.GetBaseBubbleValue(id)
						if v < minValue then
							minValue = v
						end
						if v > maxValue then
							maxValue = v
						end
						if id ~= "Normal" then
							totalSpecial += 1
						end
					end
				end
			end
		end
	end
	if minValue == math.huge then
		minValue = 0
	end
	return {
		byType = byType,
		total = total,
		totalSpecial = totalSpecial,
		minValue = minValue,
		maxValue = maxValue,
	}
end

function BubbleService.RunBubbleDiagnostics(zoneId: string)
	local inStudio = RunService:IsStudio()
	local verbose = B.DiagnosticsEnabled == true
	if not inStudio and not verbose then
		return
	end

	local counts = BubbleService.CountBoardRarities(zoneId)
	local area = if zoneId == "SummerZone" then "SummerZone" else "GameRoom"

	-- Poids spéciaux configurés > 0 ?
	local specialWeight = 0
	for _, def in ipairs(BubbleTypes.List) do
		if def.Id ~= "Normal" and type(def.Weight) == "number" and def.Weight > 0 then
			specialWeight += def.Weight
		end
	end

	if inStudio and counts.total > 0 and counts.totalSpecial == 0 and specialWeight > 0 then
		warn(("[BubbleDiagnostics] %s : 0 bulles spéciales après génération (poids spéciaux=%d, total=%d)"):format(
			area,
			specialWeight,
			counts.total
		))
	end

	if inStudio and boards[zoneId] then
		local board = boards[zoneId]
		for x = 1, board.sizeX do
			local col = board.grid[x]
			if col then
				for z = 1, board.sizeZ do
					local cell = col[z]
					if cell and cell.part and cell.def then
						local part = cell.part
						local id = cell.def.Id
						local base = BubbleValue.GetBaseBubbleValue(id)
						local normalBase = BubbleValue.GetBaseBubbleValue("Normal")
						if id ~= "Normal" and base <= normalBase then
							warn(("[BubbleDiagnostics] spéciale %s valeur <= Normal (base=%s)"):format(id, tostring(base)))
						end
						if id ~= "Normal" then
							if BubbleAppearance.IsNormalPaletteColor(zoneId, part.Color) then
								warn(("[BubbleDiagnostics] spéciale %s a une couleur de palette normale"):format(id))
							end
							if part:GetAttribute("Alive") == true then
								local mainZone = zoneId == "ClassicZone" or zoneId == "GameRoom"
								if mainZone then
									if BubbleAppearance.HasRarityMarker(part)
										or BubbleAppearance.HasSpecialBorder(part)
										or BubbleAppearance.HasSpecialSymbol(part)
									then
										warn(("[BubbleDiagnostics] spéciale main %s a encore un marqueur de rareté"):format(id))
									end
								end
								if BubbleAppearance.HasRealLights(part) then
									warn(("[BubbleDiagnostics] spéciale %s a encore une vraie lumière"):format(id))
								end
								if BubbleAppearance.HasBeam(part) then
									warn(("[BubbleDiagnostics] spéciale %s a encore un Beam/colonne"):format(id))
								end
							end
						else
							if zoneId == "ClassicZone" or zoneId == "GameRoom" then
								if BubbleAppearance.HasRarityMarker(part)
									or BubbleAppearance.HasSpecialBorder(part)
									or BubbleAppearance.HasSpecialSymbol(part)
								then
									warn("[BubbleDiagnostics] bulle Normal avec marqueur de rareté")
								end
							end
						end
					end
				end
			end
		end
	end

	if not verbose then
		return
	end

	print(("[BubbleDiagnostics] Zone=%s"):format(area))
	print(("  Normal=%d"):format(counts.byType.Normal or 0))
	for _, def in ipairs(BubbleTypes.List) do
		if def.Id ~= "Normal" then
			print(("  %s=%d"):format(def.Id, counts.byType[def.Id] or 0))
		end
	end
	print(("  TotalSpecial=%d Total=%d"):format(counts.totalSpecial, counts.total))
	print(("  MinValue=%s MaxValue=%s"):format(tostring(counts.minValue), tostring(counts.maxValue)))
end

-- Studio only : rangée d'exemples de chaque type (ne change pas les proba de jeu).
function BubbleService.MaybeBuildSpecialPreviewRow(zoneId: string)
	if not RunService:IsStudio() then
		return
	end
	if B.StudioSpecialPreviewRow ~= true then
		return
	end
	if zoneId ~= defaultZoneId and zoneId ~= "ClassicZone" then
		return
	end

	local board = boards[zoneId]
	if not board or not board.folder then
		return
	end

	local existing = board.folder:FindFirstChild("SpecialPreviewRow")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "SpecialPreviewRow"
	folder.Parent = board.folder

	local origin = board.origin + Vector3.new(0, 8, -(board.sizeZ * G.Spacing) * 0.5 - 14)
	local types = { "Normal", "Rare", "Golden", "Diamond", "Legendary" }
	for i, id in ipairs(types) do
		local part = Instance.new("Part")
		part.Name = "Preview_" .. id
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Size = G.BubbleSize
		part.CFrame = CFrame.new(origin + Vector3.new((i - 3) * 7, 0, 0))
		part.Parent = folder
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = B.MeshScale
		mesh.Parent = part
		BubbleAppearance.ApplyToPart(part, zoneId, id, i, true)
		print(("[SpecialBubbleVisual] Preview Type=%s Path=%s Marker=%s Lights=%s Beam=%s"):format(
			id,
			part:GetFullName(),
			tostring(BubbleAppearance.HasRarityMarker(part)),
			tostring(BubbleAppearance.HasRealLights(part)),
			tostring(BubbleAppearance.HasBeam(part))
		))
	end
	print("[SpecialBubbleVisual] Preview row (StudioSpecialPreviewRow=true).")
end

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
	-- Réapplique le rendu stable Neon sur les bulles actives (évite templates/anciens mats).
	BubbleService.ReapplyMainZoneVisuals()
	Remotes.Event("PopRequest").OnServerEvent:Connect(onPopRequest)
	Players.PlayerRemoving:Connect(function(p) budget[p] = nil end)
	startEffectLoop()
end

-- Force le pipeline d’apparence actuel sur toutes les bulles de zone principale.
function BubbleService.ReapplyMainZoneVisuals()
	for _, board in ipairs(boardList) do
		local zid = board.zoneId
		if zid ~= "SummerZone" then
			for x = 1, board.sizeX do
				for z = 1, board.sizeZ do
					local cell = board.grid[x] and board.grid[x][z]
					if cell and cell.part and cell.def then
						applyBubbleAppearance(
							cell.part,
							cell.zoneId,
							cell.def,
							cell.tintIndex or 1,
							cell.alive == true
						)
					end
				end
			end
		end
	end
end

return BubbleService
