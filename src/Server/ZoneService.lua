--!strict
-- Lobby, salle de bulles, téléports serveur, barrières de sécurité et chute (FallReset).
-- Monde additif idempotent : les objets existants (décor Studio ou déjà créés) ne sont
-- jamais déplacés, redimensionnés ni détruits, sauf `Config.World.RebuildGeneratedLayout`
-- qui ne reconstruit que les objets marqués `GeneratedByCode` (jamais BubbleWorld).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)

local DataService = require(script.Parent.DataService)
local BackpackService = require(script.Parent.BackpackService)

local ZoneService = {}

local PALETTE = {
	Floor = Color3.fromRGB(28, 38, 68),
	FloorAccent = Color3.fromRGB(40, 55, 95),
	Cyan = Color3.fromRGB(70, 200, 255),
	CyanDeep = Color3.fromRGB(40, 140, 200),
	Violet = Color3.fromRGB(150, 100, 255),
	Gold = Color3.fromRGB(255, 210, 90),
	Glass = Color3.fromRGB(80, 180, 230),
	Pillar = Color3.fromRGB(50, 70, 120),
	White = Color3.fromRGB(240, 248, 255),
}

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

local function markGenerated(inst: Instance)
	inst:SetAttribute("GeneratedByCode", true)
end

-- Supprime uniquement les enfants marqués GeneratedByCode (migration dev).
-- Ne touche jamais BubbleWorld ni les objets Studio sans attribut.
local function clearGeneratedChildren(container: Instance)
	if not Config.World.RebuildGeneratedLayout then
		return
	end
	local doomed: { Instance } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:GetAttribute("GeneratedByCode") == true then
			table.insert(doomed, child)
		elseif child:IsA("Folder") then
			for _, nested in ipairs(child:GetChildren()) do
				if nested:GetAttribute("GeneratedByCode") == true then
					table.insert(doomed, nested)
				end
			end
		end
	end
	for _, inst in ipairs(doomed) do
		inst:Destroy()
	end
end

local function makePart(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	Shape: Enum.PartType?,
}): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or PALETTE.Pillar
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	p.CanTouch = if props.CanTouch == nil then false else props.CanTouch
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	markGenerated(p)
	return p
end

-- Crée `name` sous `container` via `build()` s'il est absent ; sinon réutilise l'objet
-- existant sans le déplacer/redimensionner (comportement par défaut). Si
-- `Config.World.RebuildGeneratedLayout` est actif ET que l'objet existant porte
-- `GeneratedByCode = true`, repositionne taille/CFrame (après clearGenerated, en pratique
-- l'objet est recréé).
local function ensurePart(container: Instance, name: string, build: () -> BasePart): BasePart
	local existing = container:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		if Config.World.RebuildGeneratedLayout and existing:GetAttribute("GeneratedByCode") == true then
			local fresh = build()
			existing.Size = fresh.Size
			existing.CFrame = fresh.CFrame
			existing.Transparency = fresh.Transparency
			existing.CanCollide = fresh.CanCollide
			existing.CanQuery = fresh.CanQuery
			existing.CanTouch = fresh.CanTouch
			existing.Color = fresh.Color
			existing.Material = fresh.Material
			fresh:Destroy()
		end
		return existing
	end
	local part = build()
	part.Name = name
	markGenerated(part)
	part.Parent = container
	return part
end

local function ensureDecorFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		if Config.World.RebuildGeneratedLayout and existing:GetAttribute("GeneratedByCode") == true then
			existing:Destroy()
		else
			return existing
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	markGenerated(folder)
	folder.Parent = parent
	return folder
end

local function addBillboard(part: BasePart, name: string, text: string, size: Vector2, studsOffset: Vector3, textSize: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	gui.StudsOffset = studsOffset
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = PALETTE.White
	label.Font = Enum.Font.GothamBold
	label.TextScaled = textSize == nil
	if textSize then
		label.TextSize = textSize
	end
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(10, 20, 40)
	label.Parent = gui
	return gui
end

local function addSurfaceSign(part: BasePart, face: Enum.NormalId, text: string, textSize: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = PALETTE.White
	label.Font = Enum.Font.GothamBold
	label.TextScaled = textSize == nil
	if textSize then
		label.TextSize = textSize
	end
	label.TextWrapped = true
	label.Parent = gui
end

-- Répare additivement un ProximityPrompt : complète uniquement les propriétés manquantes
-- (jamais d'écrasement d'une personnalisation Studio existante), sauf Rebuild.
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
	if Config.World.RebuildGeneratedLayout or p.ActionText == "" then
		p.ActionText = actionText
	end
	if Config.World.RebuildGeneratedLayout or p.ObjectText == "" then
		p.ObjectText = objectText
	end
	if Config.World.RebuildGeneratedLayout or p.MaxActivationDistance <= 0 then
		p.MaxActivationDistance = maxDistance
	end
	return p
end

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

local function disableStudioBaseplate()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.CanCollide = false
		baseplate.Transparency = 1
	end
end

--------------------------------------------------------------------
-- Barrières : garde-corps visibles bas + collision invisible plus haute
--------------------------------------------------------------------
local function ensureBorderPair(
	container: Instance,
	name: string,
	sizeXZ: Vector3,
	cframe: CFrame
)
	local W = Config.World
	local visH = W.VisibleBorderHeight
	local colH = W.InvisibleCollisionHeight

	ensurePart(container, name .. "Visible", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Glass
		p.Color = W.BorderColor
		p.Transparency = math.clamp(W.BorderTransparency, 0.65, 0.85)
		p.Size = Vector3.new(sizeXZ.X, visH, sizeXZ.Z)
		local y = Config.Grid.Origin.Y + visH / 2
		p.CFrame = CFrame.new(cframe.Position.X, y, cframe.Position.Z) * (cframe - cframe.Position)
		return p
	end)

	ensurePart(container, name .. "Collision", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(sizeXZ.X, colH, sizeXZ.Z)
		local y = Config.Grid.Origin.Y + colH / 2
		p.CFrame = CFrame.new(cframe.Position.X, y, cframe.Position.Z) * (cframe - cframe.Position)
		return p
	end)

	-- Poteaux décoratifs aux extrémités (murs longs uniquement)
	if math.max(sizeXZ.X, sizeXZ.Z) > 20 then
		local alongX = sizeXZ.X >= sizeXZ.Z
		local half = (if alongX then sizeXZ.X else sizeXZ.Z) / 2 - 1
		local postY = Config.Grid.Origin.Y + visH / 2
		for i, sign in ipairs({ -1, 1 }) do
			ensurePart(container, name .. "Post" .. tostring(i), function()
				local offset = if alongX
					then Vector3.new(half * sign, 0, 0)
					else Vector3.new(0, 0, half * sign)
				return makePart({
					Name = "Post",
					Size = Vector3.new(1.2, visH + 1, 1.2),
					CFrame = CFrame.new(cframe.Position.X + offset.X, postY, cframe.Position.Z + offset.Z),
					Color = PALETTE.CyanDeep,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					CanQuery = false,
				})
			end)
		end
	end
end

local function buildSafetyBorders(gameRoom: Folder)
	local borders = ensureFolder(gameRoom, "SafetyBorders")
	clearGeneratedChildren(borders)

	local G = Config.Grid
	local W = Config.World
	local t = W.BorderThickness
	local safetyGap = 2
	local bubbleExtentX = ((G.SizeX / 2) - 0.5) * G.Spacing + G.BubbleSize.X / 2 + safetyGap
	local bubbleExtentZ = ((G.SizeZ / 2) - 0.5) * G.Spacing + G.BubbleSize.Z / 2 + safetyGap

	ensureBorderPair(borders, "BorderNorth",
		Vector3.new((bubbleExtentX + t) * 2, 0, t),
		CFrame.new(G.Origin.X, 0, G.Origin.Z + bubbleExtentZ + t / 2))

	ensureBorderPair(borders, "BorderEast",
		Vector3.new(t, 0, (bubbleExtentZ + t) * 2),
		CFrame.new(G.Origin.X + bubbleExtentX + t / 2, 0, G.Origin.Z))

	ensureBorderPair(borders, "BorderWest",
		Vector3.new(t, 0, (bubbleExtentZ + t) * 2),
		CFrame.new(G.Origin.X - bubbleExtentX - t / 2, 0, G.Origin.Z))

	-- Ouverture sud calibrée sur la passerelle (ArrivalPath) : juste assez large pour
	-- la traverser, pas assez pour ouvrir un trou de chaque côté.
	local gapWidth = Config.GameRoom.PathSize.X + 8
	local segLen = math.max(0, bubbleExtentX + t - gapWidth / 2)
	if segLen > 0 then
		ensureBorderPair(borders, "BorderSouthLeft",
			Vector3.new(segLen, 0, t),
			CFrame.new(G.Origin.X - (gapWidth / 2 + segLen / 2), 0, G.Origin.Z - bubbleExtentZ - t / 2))
		ensureBorderPair(borders, "BorderSouthRight",
			Vector3.new(segLen, 0, t),
			CFrame.new(G.Origin.X + (gapWidth / 2 + segLen / 2), 0, G.Origin.Z - bubbleExtentZ - t / 2))
	end
end

--------------------------------------------------------------------
-- Décor lobby
--------------------------------------------------------------------
local function buildLobbyRailings(decor: Folder, root: Vector3, floorSize: Vector3)
	local L = Config.Lobby
	local h = L.RailingHeight
	local t = 1.2
	local y = root.Y + h / 2
	local halfX = floorSize.X / 2
	local halfZ = floorSize.Z / 2

	local segments = {
		{ "RailNorth", Vector3.new(floorSize.X, h, t), Vector3.new(0, 0, halfZ - t / 2) },
		{ "RailSouth", Vector3.new(floorSize.X, h, t), Vector3.new(0, 0, -(halfZ - t / 2)) },
		{ "RailEast", Vector3.new(t, h, floorSize.Z), Vector3.new(halfX - t / 2, 0, 0) },
		{ "RailWest", Vector3.new(t, h, floorSize.Z), Vector3.new(-(halfX - t / 2), 0, 0) },
	}

	-- Ouverture nord pour l'entrée (trou central)
	local entranceGap = 20
	for _, seg in ipairs(segments) do
		local name, size, offset = seg[1] :: string, seg[2] :: Vector3, seg[3] :: Vector3
		if name == "RailNorth" then
			local sideLen = (floorSize.X - entranceGap) / 2
			if sideLen > 2 then
				local left = makePart({
					Name = "RailNorthLeft",
					Size = Vector3.new(sideLen, h, t),
					CFrame = CFrame.new(root + Vector3.new(-(entranceGap / 2 + sideLen / 2), y - root.Y, offset.Z)),
					Color = PALETTE.CyanDeep,
					Material = Enum.Material.SmoothPlastic,
					Transparency = 0.15,
				})
				left.Parent = decor
				local right = makePart({
					Name = "RailNorthRight",
					Size = Vector3.new(sideLen, h, t),
					CFrame = CFrame.new(root + Vector3.new(entranceGap / 2 + sideLen / 2, y - root.Y, offset.Z)),
					Color = PALETTE.CyanDeep,
					Material = Enum.Material.SmoothPlastic,
					Transparency = 0.15,
				})
				right.Parent = decor
			end
		else
			local rail = makePart({
				Name = name,
				Size = size,
				CFrame = CFrame.new(root + Vector3.new(offset.X, y - root.Y, offset.Z)),
				Color = PALETTE.CyanDeep,
				Material = Enum.Material.Glass,
				Transparency = 0.35,
			})
			rail.Parent = decor
		end
	end
end

local function buildEntranceArch(decor: Folder, root: Vector3)
	local L = Config.Lobby
	local pos = root + L.EntranceOffset
	local pillarH = 12
	local pillarW = 2.5
	local gap = 14
	local lintelH = 2.5

	local left = makePart({
		Name = "EntrancePillarLeft",
		Size = Vector3.new(pillarW, pillarH, pillarW),
		CFrame = CFrame.new(pos + Vector3.new(-gap / 2, pillarH / 2 - 1, 0)),
		Color = PALETTE.Violet,
		Material = Enum.Material.SmoothPlastic,
	})
	left.Parent = decor

	local right = makePart({
		Name = "EntrancePillarRight",
		Size = Vector3.new(pillarW, pillarH, pillarW),
		CFrame = CFrame.new(pos + Vector3.new(gap / 2, pillarH / 2 - 1, 0)),
		Color = PALETTE.Violet,
		Material = Enum.Material.SmoothPlastic,
	})
	right.Parent = decor

	local lintel = makePart({
		Name = "EntranceLintel",
		Size = Vector3.new(gap + pillarW * 2, lintelH, 3),
		CFrame = CFrame.new(pos + Vector3.new(0, pillarH - 1, 0)),
		Color = PALETTE.Cyan,
		Material = Enum.Material.Neon,
	})
	lintel.Parent = decor
	addSurfaceSign(lintel, Enum.NormalId.Front, "SALLE DE BULLES")
	addSurfaceSign(lintel, Enum.NormalId.Back, "SALLE DE BULLES")

	local glow = makePart({
		Name = "EntranceGlow",
		Size = Vector3.new(gap - 1, 0.4, 8),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 2)),
		Color = PALETTE.Cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	glow.Parent = decor
end

local function buildSellBooth(decor: Folder, root: Vector3)
	local L = Config.Lobby
	local pos = root + L.SellZoneOffset

	local counter = makePart({
		Name = "SellCounter",
		Size = Vector3.new(12, 3, 5),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)),
		Color = Color3.fromRGB(45, 55, 95),
		Material = Enum.Material.SmoothPlastic,
	})
	counter.Parent = decor

	local top = makePart({
		Name = "SellCounterTop",
		Size = Vector3.new(12.5, 0.5, 5.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 3.25, 0)),
		Color = PALETTE.CyanDeep,
		Material = Enum.Material.SmoothPlastic,
	})
	top.Parent = decor

	local tank = makePart({
		Name = "SellTank",
		Size = Vector3.new(4, 4, 4),
		CFrame = CFrame.new(pos + Vector3.new(-3.5, 5.2, -1)),
		Color = PALETTE.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	-- Cylinder axis is X by default; rotate to stand upright
	tank.CFrame = CFrame.new(pos + Vector3.new(-3.5, 5.2, -1)) * CFrame.Angles(0, 0, math.rad(90))
	tank.Parent = decor

	local machine = makePart({
		Name = "SellMachine",
		Size = Vector3.new(3.5, 5, 3.5),
		CFrame = CFrame.new(pos + Vector3.new(3.2, 5.5, -1)),
		Color = PALETTE.Violet,
		Material = Enum.Material.SmoothPlastic,
	})
	machine.Parent = decor

	local coinIcon = makePart({
		Name = "SellCoinIcon",
		Size = Vector3.new(2.2, 2.2, 0.4),
		CFrame = CFrame.new(pos + Vector3.new(3.2, 8.4, -1)),
		Color = PALETTE.Gold,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
	})
	coinIcon.CFrame = CFrame.new(pos + Vector3.new(3.2, 8.4, -1)) * CFrame.Angles(0, 0, math.rad(90))
	coinIcon.Parent = decor

	local crate = makePart({
		Name = "SellCrate",
		Size = Vector3.new(3, 2.2, 3),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.3, -2.5)),
		Color = Color3.fromRGB(70, 90, 140),
		Material = Enum.Material.SmoothPlastic,
	})
	crate.Parent = decor

	local sign = makePart({
		Name = "SellSign",
		Size = Vector3.new(10, 3, 0.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 9.5, 0)),
		Color = Color3.fromRGB(35, 50, 90),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	sign.Parent = decor
	addSurfaceSign(sign, Enum.NormalId.Front, "VENDRE LES BULLES")
	addSurfaceSign(sign, Enum.NormalId.Back, "VENDRE LES BULLES")

	local valueBoard = makePart({
		Name = "SellValueBoard",
		Size = Vector3.new(8, 2, 0.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 7.2, 2.2)),
		Color = Color3.fromRGB(25, 35, 60),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	valueBoard.Parent = decor
	local gui = addBillboard(valueBoard, "SellValueGui", "Valeur du sac : 0 pièces", Vector2.new(280, 48), Vector3.new(0, 0, 0))
	gui.MaxDistance = 60
end

local function buildSpawnRing(decor: Folder, root: Vector3)
	local L = Config.Lobby
	local pos = root + L.SpawnOffset
	local ring = makePart({
		Name = "SpawnRing",
		Size = Vector3.new(10, 0.35, 10),
		CFrame = CFrame.new(pos.X, root.Y + 0.2, pos.Z),
		Color = PALETTE.Cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
	})
	ring.CFrame = CFrame.new(pos.X, root.Y + 0.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = decor

	local pad = makePart({
		Name = "SpawnAccent",
		Size = Vector3.new(14, 0.25, 14),
		CFrame = CFrame.new(pos.X, root.Y + 0.15, pos.Z),
		Color = PALETTE.FloorAccent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})
	pad.Parent = decor
end

local function buildGuideSign(decor: Folder, root: Vector3)
	local L = Config.Lobby
	local board = makePart({
		Name = "GuideSign",
		Size = Vector3.new(12, 7, 0.6),
		CFrame = CFrame.new(root + Vector3.new(30, 5, -10)),
		Color = Color3.fromRGB(30, 42, 75),
		Material = Enum.Material.SmoothPlastic,
	})
	board.Parent = decor
	addSurfaceSign(board, Enum.NormalId.Front, L.SignText)
	addSurfaceSign(board, Enum.NormalId.Back, L.SignText)
end

--------------------------------------------------------------------
-- Lobby
--------------------------------------------------------------------
local function buildLobby(lobby: Folder)
	local L = Config.Lobby
	local root = L.RootOffset

	validateOutsideGrid(root, L.ClearanceFromGrid, "Lobby.RootOffset")
	validateOutsideGrid(L.SellPosition, L.ClearanceFromGrid, "Lobby.SellPosition")
	validateOutsideGrid(L.EntrancePosition, L.ClearanceFromGrid, "Lobby.EntrancePosition")

	ensurePart(lobby, "Floor", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = L.FloorColor
		p.Size = L.FloorSize
		p.CFrame = CFrame.new(root - Vector3.new(0, L.FloorSize.Y / 2, 0))
		p.TopSurface = Enum.SurfaceType.Smooth
		return p
	end)

	-- Bande centrale (chemin vers l'entrée)
	local decor = ensureDecorFolder(lobby, "LobbyDecor")
	if #decor:GetChildren() == 0 then
		local path = makePart({
			Name = "LobbyPath",
			Size = Vector3.new(14, 0.3, 50),
			CFrame = CFrame.new(root + Vector3.new(0, 0.2, 12)),
			Color = PALETTE.FloorAccent,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
		})
		path.Parent = decor

		buildLobbyRailings(decor, root, L.FloorSize)
		buildEntranceArch(decor, root)
		buildSellBooth(decor, root)
		buildSpawnRing(decor, root)
		buildGuideSign(decor, root)
	end

	local spawn = ensurePart(lobby, "LobbySpawn", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(4, 1, 4)
		p.CFrame = CFrame.new(root + L.SpawnOffset)
		return p
	end)
	lobbySpawnPart = spawn

	-- Trigger technique invisible (intégré au comptoir)
	local sellZone = ensurePart(lobby, "SellZone", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = true
		p.CanTouch = false
		p.Transparency = 1
		p.Size = L.SellZoneSize
		p.CFrame = CFrame.new(L.SellPosition)
		return p
	end)

	local entrance = ensurePart(lobby, "GameEntrance", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = true
		p.CanTouch = false
		p.Transparency = 1
		p.Size = L.EntranceSize
		p.CFrame = CFrame.new(L.EntrancePosition)
		return p
	end)

	local sellPrompt = ensurePrompt(sellZone, "SellPrompt", "Vendre mes bulles", "VENDRE LES BULLES", Config.World.SellMaxDistance)
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

	local entrancePrompt = ensurePrompt(entrance, "EntrancePrompt", "Entrer dans la salle de bulles", "SALLE DE BULLES", 12)
	connectOnce(entrancePrompt, "_wiredEntrance", function(player: Player)
		ZoneService.TeleportToGameRoom(player)
	end)
end

--------------------------------------------------------------------
-- Décor salle (sortie + chemin)
--------------------------------------------------------------------
local function buildExitArch(decor: Folder, exitPos: Vector3, groundY: number)
	local pillarH = 10
	local gap = 12

	local left = makePart({
		Name = "ExitPillarLeft",
		Size = Vector3.new(2.2, pillarH, 2.2),
		CFrame = CFrame.new(exitPos.X - gap / 2, groundY + pillarH / 2, exitPos.Z),
		Color = PALETTE.Violet,
		Material = Enum.Material.SmoothPlastic,
	})
	left.Parent = decor

	local right = makePart({
		Name = "ExitPillarRight",
		Size = Vector3.new(2.2, pillarH, 2.2),
		CFrame = CFrame.new(exitPos.X + gap / 2, groundY + pillarH / 2, exitPos.Z),
		Color = PALETTE.Violet,
		Material = Enum.Material.SmoothPlastic,
	})
	right.Parent = decor

	local lintel = makePart({
		Name = "ExitLintel",
		Size = Vector3.new(gap + 4, 2.2, 2.5),
		CFrame = CFrame.new(exitPos.X, groundY + pillarH, exitPos.Z),
		Color = PALETTE.Cyan,
		Material = Enum.Material.Neon,
	})
	lintel.Parent = decor
	addSurfaceSign(lintel, Enum.NormalId.Front, "Retour au lobby")
	addSurfaceSign(lintel, Enum.NormalId.Back, "Retour au lobby")
end

local function buildGameRoom(gameRoom: Folder)
	local G = Config.Grid
	local R = Config.GameRoom

	local spawnPos = R.SpawnPadPosition
	local exitPos = R.ExitPosition
	validateOutsideGrid(spawnPos, Config.Lobby.ClearanceFromGrid, "GameRoom.SpawnPadPosition")
	validateOutsideGrid(exitPos, Config.Lobby.ClearanceFromGrid, "GameRoom.ExitPosition")

	local padTopY = G.Origin.Y - R.PadSize.Y / 2

	ensurePart(gameRoom, "SpawnPad", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = R.PadColor
		p.Size = R.PadSize
		p.CFrame = CFrame.new(spawnPos.X, padTopY, spawnPos.Z)
		return p
	end)

	ensurePart(gameRoom, "ExitPad", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(50, 60, 110)
		p.Size = R.ExitPadSize
		p.CFrame = CFrame.new(exitPos.X, G.Origin.Y - R.ExitPadSize.Y / 2, exitPos.Z)
		return p
	end)

	-- Passerelle continue entre le bord nord du SpawnPad et la face sud de la première
	-- rangée de bulles : sans elle, le joueur tombe dans le vide (boucle FallReset).
	-- Elle traverse l'ouverture centrale des SafetyBorders (voir buildSafetyBorders).
	local bubbleEdgeZ = G.Origin.Z - (((G.SizeZ / 2) - 0.5) * G.Spacing + G.BubbleSize.Z / 2)
	local padEdgeZ = spawnPos.Z + R.PadSize.Z / 2
	local seamOverlap = 1
	local pathLength = math.max(0, bubbleEdgeZ - padEdgeZ) + seamOverlap * 2
	local pathZ = (padEdgeZ + bubbleEdgeZ) / 2
	ensurePart(gameRoom, "ArrivalPath", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.Material = Enum.Material.SmoothPlastic
		p.Color = R.PathColor
		p.Size = Vector3.new(R.PathSize.X, R.PathSize.Y, pathLength)
		p.CFrame = CFrame.new(spawnPos.X, G.Origin.Y - R.PathSize.Y / 2, pathZ)
		return p
	end)

	local decor = ensureDecorFolder(gameRoom, "GameRoomDecor")
	if #decor:GetChildren() == 0 then
		buildExitArch(decor, exitPos, G.Origin.Y)

		-- Garde-corps latéraux sur la plateforme d'arrivée
		for _, side in ipairs({ -1, 1 }) do
			local rail = makePart({
				Name = if side < 0 then "SpawnRailLeft" else "SpawnRailRight",
				Size = Vector3.new(1.2, 5, R.PadSize.Z),
				CFrame = CFrame.new(spawnPos.X + side * (R.PadSize.X / 2 - 0.6), G.Origin.Y + 2.5, spawnPos.Z),
				Color = PALETTE.CyanDeep,
				Material = Enum.Material.Glass,
				Transparency = 0.4,
			})
			rail.Parent = decor
		end

		-- Garde-corps de la passerelle : on ne tombe pas sur le trajet pad → bulles.
		-- Ils s'arrêtent avant la première rangée de bulles (pas de clipping).
		local railLength = math.max(1, pathLength - seamOverlap * 2)
		for _, side in ipairs({ -1, 1 }) do
			local rail = makePart({
				Name = if side < 0 then "PathRailLeft" else "PathRailRight",
				Size = Vector3.new(1, 4, railLength),
				CFrame = CFrame.new(spawnPos.X + side * (R.PathSize.X / 2 - 0.5), G.Origin.Y + 2, pathZ),
				Color = PALETTE.CyanDeep,
				Material = Enum.Material.Glass,
				Transparency = 0.4,
			})
			rail.Parent = decor
		end
	end

	local spawn = ensurePart(gameRoom, "GameRoomSpawn", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
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
		p.CanQuery = true
		p.CanTouch = false
		p.Transparency = 1
		p.Size = R.ExitSize
		p.CFrame = CFrame.new(exitPos)
		return p
	end)

	local exitPrompt = ensurePrompt(exitZone, "ExitPrompt", "Retourner au lobby", "Retour au lobby", 12)
	connectOnce(exitPrompt, "_wiredExit", function(player: Player)
		ZoneService.TeleportToLobby(player)
	end)

	buildSafetyBorders(gameRoom)
end

--------------------------------------------------------------------
-- Monde additif
--------------------------------------------------------------------
function ZoneService.EnsureWorld(): Folder
	disableStudioBaseplate()

	local root = ensureFolder(workspace, "BubblePopWorld")
	local lobby = ensureFolder(root, "Lobby")
	local gameRoom = ensureFolder(root, "GameRoom")

	-- Migration dev : supprimer uniquement GeneratedByCode (jamais BubbleWorld / grille).
	clearGeneratedChildren(lobby)
	clearGeneratedChildren(gameRoom)

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
	player:SetAttribute("PlayerArea", area)
	return true
end

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

-- Un joueur tombé du lobby revient au lobby ; dans la salle, on suit
-- FallResetDestination (par défaut le pad de la salle).
local function fallResetToLobby(player: Player): boolean
	if player:GetAttribute("PlayerArea") == "Lobby" then
		return true
	end
	return Config.World.FallResetDestination == "Lobby"
end

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
					if fallResetToLobby(player) then
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

	local function bindPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		if player.Character then
			onCharacterAdded(player)
		end
	end

	Players.PlayerAdded:Connect(bindPlayer)

	-- Joueurs déjà connectés quand le service démarre (Rojo sync / hot reload Studio).
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		teleportLast[player] = nil
		spawningInProgress[player] = nil
		fallResetGuard[player] = nil
	end)

	watchFallReset()
end

return ZoneService
