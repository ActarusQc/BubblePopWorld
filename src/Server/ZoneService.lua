--!strict
-- Lobby, salle de bulles, passage physique, barrières et chute (FallReset).
-- Lobby ↔ salle : déplacement à pied uniquement (aucun téléport de zone).
-- Téléports réservés au spawn initial et au FallReset (sécurité).
-- Monde additif idempotent : `RebuildGeneratedLayout` ne reconstruit que `GeneratedByCode`.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ZoneDefs = require(Shared.ZoneDefs)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local DataService = require(script.Parent.DataService)
local BackpackService = require(script.Parent.BackpackService)
local ZoneAccess = require(script.Parent.ZoneAccess)
local ZoneBuilder = require(script.Parent.ZoneBuilder)
local LobbyEditingPreview = require(Shared.LobbyEditingPreview)
local EnvironmentBackdropBuilder = require(Shared.EnvironmentBackdropBuilder)

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

-- Lobby canonique : évite un 2e "Lobby" si l'import Studio est un Model nommé Lobby
-- (ensureFolder ne matche que Folder → créait un doublon Folder + Model).
local function ensureLobby(worldRoot: Instance): Folder
	local folders: { Folder } = {}
	local models: { Model } = {}
	for _, child in ipairs(worldRoot:GetChildren()) do
		if child.Name == "Lobby" then
			if child:IsA("Folder") then
				table.insert(folders, child)
			elseif child:IsA("Model") then
				table.insert(models, child)
			end
		end
	end

	local function hasStudioKiosk(inst: Instance): boolean
		local k = inst:FindFirstChild("SellKiosk")
		return k ~= nil and k:IsA("Model")
	end

	-- 1) Folder qui contient déjà le SellKiosk Studio
	for _, f in ipairs(folders) do
		if hasStudioKiosk(f) then
			return f
		end
	end

	-- 2) Convertir un Model Lobby (imports) en Folder
	for _, m in ipairs(models) do
		if hasStudioKiosk(m) or #folders == 0 then
			local f = Instance.new("Folder")
			f.Name = "Lobby"
			f.Parent = worldRoot
			for _, nested in ipairs(m:GetChildren()) do
				nested.Parent = f
			end
			print(("[ZoneService] Lobby Model converti en Folder (%d enfants)"):format(#f:GetChildren()))
			m:Destroy()
			return f
		end
	end

	-- 3) Premier Folder Lobby existant
	if #folders > 0 then
		return folders[1]
	end

	-- 4) Création
	return ensureFolder(worldRoot, "Lobby")
end

local function markGenerated(inst: Instance)
	inst:SetAttribute("GeneratedByCode", true)
end

-- Supprime uniquement les enfants marqués GeneratedByCode (migration dev).
-- Ne touche jamais BubbleWorld, GameZones.BubbleBoard, ni Workspace.StudioDecoration.
local function clearGeneratedChildren(container: Instance)
	local studioDecor = workspace:FindFirstChild("StudioDecoration")
	if container.Name == "StudioDecoration"
		or (studioDecor ~= nil and container:IsDescendantOf(studioDecor)) then
		return
	end
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

local function addSurfaceSign(part: BasePart, face: Enum.NormalId, text: string, textSize: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = PALETTE.White
	label.Font = Enum.Font.GothamBold
	label.TextScaled = textSize == nil
	if textSize then
		label.TextSize = textSize
	end
	label.TextWrapped = true
	label.Parent = gui
	L10nUtil.localize(label, text)
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
-- Zone de vente des bulles uniquement (la boutique d'items n'en a pas).
local sellZonePart: BasePart? = nil

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

	-- Ouverture est vers la Summer Zone (passerelle) — même largeur que le pont.
	local eastGap = Config.GameRoom.PathSize.X + 6
	local eastSeg = math.max(0, bubbleExtentZ + t - eastGap / 2)
	if eastSeg > 0 then
		ensureBorderPair(borders, "BorderEastNorth",
			Vector3.new(t, 0, eastSeg),
			CFrame.new(G.Origin.X + bubbleExtentX + t / 2, 0, G.Origin.Z + (eastGap / 2 + eastSeg / 2)))
		ensureBorderPair(borders, "BorderEastSouth",
			Vector3.new(t, 0, eastSeg),
			CFrame.new(G.Origin.X + bubbleExtentX + t / 2, 0, G.Origin.Z - (eastGap / 2 + eastSeg / 2)))
	end

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

	-- Ouverture nord pour l'entrée (passage praticable, bas seuil au sol)
	local entranceGap = 18
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
			-- Seuil bas dans l'ouverture (pas de trou vers le vide).
			local threshold = makePart({
				Name = "RailNorthThreshold",
				Size = Vector3.new(entranceGap, 1.2, t + 1),
				CFrame = CFrame.new(root + Vector3.new(0, 0.6, offset.Z)),
				Color = PALETTE.Cyan,
				Material = Enum.Material.Neon,
				Transparency = 0.5,
				CanCollide = true,
			})
			threshold.Parent = decor
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

	-- Seuil / rampe continue (plus de trou devant l'arche).
	local sill = makePart({
		Name = "EntranceSill",
		Size = Vector3.new(gap + 4, 1.2, 14),
		CFrame = CFrame.new(pos.X, root.Y + 0.1, pos.Z + 1),
		Color = PALETTE.FloorAccent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})
	sill.Parent = decor

	local ramp = makePart({
		Name = "EntranceRamp",
		Size = Vector3.new(gap + 2, 1, 10),
		CFrame = CFrame.new(pos.X, root.Y + 0.05, pos.Z - 4),
		Color = Color3.fromRGB(48, 70, 120),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})
	ramp.Parent = decor

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
	addSurfaceSign(lintel, Enum.NormalId.Front, L10n.BubbleRoom)
	addSurfaceSign(lintel, Enum.NormalId.Back, L10n.BubbleRoom)

	local glow = makePart({
		Name = "EntranceGlow",
		Size = Vector3.new(gap - 1, 0.35, gap),
		CFrame = CFrame.new(pos.X, root.Y + 0.35, pos.Z),
		Color = PALETTE.Cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
	})
	glow.Parent = decor
end

--------------------------------------------------------------------
-- Kiosque de vente (assemblage code, restauré depuis l'ancienne version)
--------------------------------------------------------------------
-- CFrame local du kiosque : origine au centre, façade initiale vers +Z, puis yaw config.
local function sellBoothBaseCF(root: Vector3): CFrame
	local L = Config.Lobby
	local booth = L.SellBooth
	local origin = root + booth.OriginOffset
	return CFrame.new(origin) * CFrame.Angles(0, math.rad(booth.YawDegrees), 0)
end

local function sellLocalCF(base: CFrame, localPos: Vector3, localRot: CFrame?): CFrame
	local cf = base * CFrame.new(localPos)
	if localRot then
		return cf * localRot
	end
	return cf
end

local SELL_NAVY = Color3.fromRGB(18, 32, 85)
local SELL_NAVY_DEEP = Color3.fromRGB(8, 22, 65)
local SELL_BLUE = Color3.fromRGB(28, 105, 255)
local SELL_CYAN = Color3.fromRGB(80, 230, 255)
local SELL_CYAN_SOFT = Color3.fromRGB(160, 240, 255)
local SELL_GOLD = Color3.fromRGB(255, 185, 60) -- coins / money accents only
local SELL_TOP = Color3.fromRGB(210, 220, 235)
local SELL_PANEL = Color3.fromRGB(10, 26, 72)

local function attachPart(parent: Folder, props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	Shape: Enum.PartType?,
	Reflectance: number?,
}): Part
	local p = makePart({
		Name = props.Name,
		Size = props.Size,
		CFrame = props.CFrame,
		Color = props.Color,
		Material = props.Material,
		Transparency = props.Transparency,
		CanCollide = props.CanCollide,
		CanQuery = props.CanQuery,
		Shape = props.Shape,
	})
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
	p.Parent = parent
	return p
end

local function addSellValueScreen(board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SellValueGui"
	gui.Face = Enum.NormalId.Front
	gui.Enabled = true
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	-- Never AlwaysOnTop: otherwise this counter screen draws over the player when they stand on the pad.
	gui.AlwaysOnTop = false
	gui.Parent = board

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(8, 16, 38)
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = SELL_CYAN
	stroke.Thickness = 3
	stroke.Transparency = 0.15
	stroke.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.Parent = frame

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.new(1, 0, 0.28, 0)
	caption.BackgroundTransparency = 1
	caption.TextColor3 = PALETTE.White
	caption.Font = Enum.Font.GothamBold
	caption.TextScaled = true
	caption.Parent = frame
	L10nUtil.localize(caption, L10n.BagValue)

	local row = Instance.new("Frame")
	row.Name = "ValueRow"
	row.Size = UDim2.new(1, 0, 0.62, 0)
	row.Position = UDim2.new(0, 0, 0.34, 0)
	row.BackgroundTransparency = 1
	row.Parent = frame

	local amount = Instance.new("TextLabel")
	amount.Name = "Label"
	amount.Size = UDim2.new(0.62, 0, 1, 0)
	amount.BackgroundTransparency = 1
	amount.TextColor3 = SELL_CYAN
	amount.Font = Enum.Font.GothamBold
	amount.TextScaled = true
	amount.TextXAlignment = Enum.TextXAlignment.Right
	amount.Parent = row
	L10nUtil.dynamic(amount, "0")

	local unit = Instance.new("TextLabel")
	unit.Name = "Unit"
	unit.Size = UDim2.new(0.34, 0, 0.55, 0)
	unit.Position = UDim2.new(0.64, 0, 0.28, 0)
	unit.BackgroundTransparency = 1
	unit.TextColor3 = PALETTE.White
	unit.Font = Enum.Font.Gotham
	unit.TextScaled = true
	unit.TextXAlignment = Enum.TextXAlignment.Left
	unit.Parent = row
	L10nUtil.localize(unit, L10n.CoinsUnit)
end

-- Cadre ouvert (4 bords) dans le plan local d'un écran — jamais de plaque pleine devant le GUI.
local function attachOpenBorder(
	parent: Folder,
	name: string,
	planeCF: CFrame,
	width: number,
	height: number,
	border: number,
	depth: number,
	color: Color3,
	transparency: number?
)
	local t = transparency or 0.15
	local halfW = width / 2
	local halfH = height / 2
	local inset = border / 2

	attachPart(parent, {
		Name = name .. "_Top",
		Size = Vector3.new(width, border, depth),
		CFrame = planeCF * CFrame.new(0, halfH - inset, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = t,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(parent, {
		Name = name .. "_Bottom",
		Size = Vector3.new(width, border, depth),
		CFrame = planeCF * CFrame.new(0, -halfH + inset, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = t,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(parent, {
		Name = name .. "_Left",
		Size = Vector3.new(border, height - border * 2, depth),
		CFrame = planeCF * CFrame.new(-halfW + inset, 0, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = t,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(parent, {
		Name = name .. "_Right",
		Size = Vector3.new(border, height - border * 2, depth),
		CFrame = planeCF * CFrame.new(halfW - inset, 0, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = t,
		CanCollide = false,
		CanQuery = false,
	})
end

local function addSellTitleGui(sign: BasePart)
	local booth = Config.Lobby.SellBooth
	local titleText = booth.SignText or L10n.SellYourBubbles
	local taglineText = booth.TaglineText or L10n.PopFillCashIn

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 45
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.AlwaysOnTop = false
	gui.Parent = sign

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = SELL_PANEL
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = SELL_CYAN
	stroke.Thickness = 3
	stroke.Transparency = 0.2
	stroke.Parent = frame

	local line1 = Instance.new("TextLabel")
	line1.Name = "Title"
	line1.Size = UDim2.new(1, -28, 0.52, 0)
	line1.Position = UDim2.new(0, 14, 0.08, 0)
	line1.BackgroundTransparency = 1
	line1.TextColor3 = Color3.fromRGB(245, 250, 255)
	line1.Font = Enum.Font.GothamBlack
	line1.TextScaled = true
	line1.TextStrokeColor3 = SELL_BLUE
	line1.TextStrokeTransparency = 0.35
	line1.Parent = frame
	L10nUtil.localize(line1, titleText)

	local line2 = Instance.new("TextLabel")
	line2.Name = "Subtitle"
	line2.Size = UDim2.new(1, -32, 0.26, 0)
	line2.Position = UDim2.new(0, 16, 0.64, 0)
	line2.BackgroundTransparency = 1
	line2.TextColor3 = SELL_CYAN_SOFT
	line2.Font = Enum.Font.GothamBold
	line2.TextScaled = true
	line2.Parent = frame
	L10nUtil.localize(line2, taglineText)
end

local function startSellTankBubbleAnims(parent: Folder, tankWorldCF: CFrame, radius: number, height: number, count: number)
	local colors = {
		SELL_CYAN_SOFT,
		SELL_CYAN,
		Color3.fromRGB(100, 235, 255),
		SELL_BLUE,
		Color3.fromRGB(80, 210, 255),
	}
	for i = 1, count do
		local diameter = 0.55 + (i % 5) * 0.22
		local bubble = attachPart(parent, {
			Name = "SellTankBubble" .. tostring(i),
			Size = Vector3.new(diameter, diameter, diameter),
			CFrame = tankWorldCF,
			Color = colors[((i - 1) % #colors) + 1],
			Material = Enum.Material.Glass,
			Transparency = 0.22,
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			CanQuery = false,
			Reflectance = 0.22,
		})

		task.spawn(function()
			local phase = (i - 1) / count
			while bubble.Parent do
				local x = math.noise(i * 1.7, phase * 3, 0.2) * radius * 0.9
				local z = math.noise(0.3, i * 2.1, phase * 3) * radius * 0.9
				local startY = -height * 0.4
				local endY = height * 0.4
				local driftX = (math.random() - 0.5) * radius * 0.4
				local driftZ = (math.random() - 0.5) * radius * 0.4
				local duration = 2.4 + math.random() * 2.6

				bubble.CFrame = tankWorldCF * CFrame.new(x, startY, z)
				bubble.Transparency = 0.15 + math.random() * 0.15

				local tween = TweenService:Create(
					bubble,
					TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ CFrame = tankWorldCF * CFrame.new(x + driftX, endY, z + driftZ), Transparency = 0.5 }
				)
				tween:Play()
				tween.Completed:Wait()
				phase += 0.19
				task.wait(0.04 + math.random() * 0.18)
			end
		end)
	end
end

local function buildSellBooth(decor: Folder, root: Vector3)
	local booth = Config.Lobby.SellBooth
	local base = sellBoothBaseCF(root)
	local faceFront = CFrame.Angles(0, math.rad(180), 0)
	local tiltFront = CFrame.Angles(math.rad(-14), math.rad(180), 0)

	--------------------------------------------------------------------
	-- Estrade + pad de vente (bas de plaza légèrement enfoncé dans le sol lobby)
	--------------------------------------------------------------------
	attachPart(decor, {
		Name = "SellPlaza",
		Size = Vector3.new(24, 1.2, 22),
		CFrame = sellLocalCF(base, Vector3.new(0, -1.6, 0.6)),
		Color = SELL_NAVY,
		Material = Enum.Material.SmoothPlastic,
	})
	attachPart(decor, {
		Name = "SellPlazaTrim",
		Size = Vector3.new(24.6, 0.18, 22.6),
		CFrame = sellLocalCF(base, Vector3.new(0, -0.95, 0.6)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
	})

	local padY = booth.PadLocalOffset.Y
	local padZ = booth.PadLocalOffset.Z
	attachPart(decor, {
		Name = "SellPad",
		Size = booth.PadSize,
		CFrame = sellLocalCF(base, booth.PadLocalOffset),
		Color = Color3.fromRGB(30, 90, 140),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		CanCollide = false,
		CanQuery = false,
	})
	-- Bordure néon du pad (4 côtés)
	local padW, padD = booth.PadSize.X, booth.PadSize.Z
	attachPart(decor, {
		Name = "SellPadBorderF",
		Size = Vector3.new(padW + 0.4, 0.22, 0.35),
		CFrame = sellLocalCF(base, Vector3.new(0, padY + 0.12, padZ + padD / 2)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellPadBorderB",
		Size = Vector3.new(padW + 0.4, 0.22, 0.35),
		CFrame = sellLocalCF(base, Vector3.new(0, padY + 0.12, padZ - padD / 2)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellPadBorderL",
		Size = Vector3.new(0.35, 0.22, padD),
		CFrame = sellLocalCF(base, Vector3.new(-padW / 2, padY + 0.12, padZ)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellPadBorderR",
		Size = Vector3.new(0.35, 0.22, padD),
		CFrame = sellLocalCF(base, Vector3.new(padW / 2, padY + 0.12, padZ)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellPadGlow",
		Size = Vector3.new(padW - 0.8, 0.12, padD - 0.8),
		CFrame = sellLocalCF(base, Vector3.new(0, padY + 0.08, padZ)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellPadRing",
		Size = Vector3.new(0.18, 3.8, 3.8),
		CFrame = sellLocalCF(base, Vector3.new(0, padY + 0.16, padZ), CFrame.Angles(0, 0, math.rad(90))),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
	})
	attachPart(decor, {
		Name = "SellPadBubble",
		Size = Vector3.new(1.7, 1.7, 1.7),
		CFrame = sellLocalCF(base, Vector3.new(0, padY + 0.45, padZ)),
		Color = SELL_CYAN_SOFT,
		Material = Enum.Material.Glass,
		Transparency = 0.28,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Ball,
		Reflectance = 0.2,
	})
	for i, offset in ipairs({
		Vector3.new(1.4, 0.35, 0.9),
		Vector3.new(-1.3, 0.32, -0.8),
		Vector3.new(0.9, 0.3, -1.2),
		Vector3.new(-1.0, 0.34, 1.1),
	}) do
		attachPart(decor, {
			Name = "SellPadSpark" .. tostring(i),
			Size = Vector3.new(0.45, 0.45, 0.45),
			CFrame = sellLocalCF(base, Vector3.new(offset.X, padY + offset.Y, padZ + offset.Z)),
			Color = PALETTE.White,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			Shape = Enum.PartType.Ball,
		})
	end

	--------------------------------------------------------------------
	-- Colonnes massives + néons encastrés
	--------------------------------------------------------------------
	local pillarH = 10.5
	local pillarY = pillarH / 2 - 1.35
	for _, side in ipairs({ -1, 1 }) do
		local px = side * 7.4
		attachPart(decor, {
			Name = if side < 0 then "SellPillarL" else "SellPillarR",
			Size = Vector3.new(2.5, pillarH, 2.8),
			CFrame = sellLocalCF(base, Vector3.new(px, pillarY, -1.4)),
			Color = SELL_NAVY_DEEP,
			Material = Enum.Material.SmoothPlastic,
		})
		attachPart(decor, {
			Name = if side < 0 then "SellPillarCapL" else "SellPillarCapR",
			Size = Vector3.new(2.8, 0.45, 3.1),
			CFrame = sellLocalCF(base, Vector3.new(px, pillarY + pillarH / 2 - 0.1, -1.4)),
			Color = SELL_NAVY,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
		})
		attachPart(decor, {
			Name = if side < 0 then "SellPillarNeonL" else "SellPillarNeonR",
			Size = Vector3.new(0.35, pillarH - 1.4, 0.35),
			CFrame = sellLocalCF(base, Vector3.new(px, pillarY, 0.15)),
			Color = SELL_CYAN,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
		attachPart(decor, {
			Name = if side < 0 then "SellPillarNeonSideL" else "SellPillarNeonSideR",
			Size = Vector3.new(0.22, pillarH - 2.2, 0.22),
			CFrame = sellLocalCF(base, Vector3.new(px + side * 1.15, pillarY, -1.4)),
			Color = SELL_CYAN,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
		})
	end

	-- Pièce dorée sur la colonne gauche (accent money uniquement)
	local coin = attachPart(decor, {
		Name = "SellPillarCoin",
		Size = Vector3.new(0.28, 1.5, 1.5),
		CFrame = sellLocalCF(base, Vector3.new(-7.4, 3.4, 0.2), CFrame.Angles(0, math.rad(90), 0)),
		Color = SELL_GOLD,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
	})
	local coinGui = Instance.new("SurfaceGui")
	coinGui.Name = "CoinGui"
	coinGui.Face = Enum.NormalId.Right
	coinGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	coinGui.PixelsPerStud = 40
	coinGui.LightInfluence = 0
	coinGui.Parent = coin
	local coinLabel = Instance.new("TextLabel")
	coinLabel.Size = UDim2.fromScale(1, 1)
	coinLabel.BackgroundTransparency = 1
	coinLabel.TextColor3 = Color3.fromRGB(80, 50, 0)
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.TextScaled = true
	coinLabel.Parent = coinGui
	L10nUtil.dynamic(coinLabel, "$")

	--------------------------------------------------------------------
	-- Comptoir profond + plateau clair + façade écran
	--------------------------------------------------------------------
	local counterSize = booth.CounterSize
	attachPart(decor, {
		Name = "SellCounter",
		Size = counterSize,
		CFrame = sellLocalCF(base, Vector3.new(0, 0.55, -0.8)),
		Color = SELL_NAVY,
		Material = Enum.Material.SmoothPlastic,
	})
	attachPart(decor, {
		Name = "SellCounterSkirt",
		Size = Vector3.new(counterSize.X + 0.6, 0.7, 1.2),
		CFrame = sellLocalCF(base, Vector3.new(0, -1.05, 2.0)),
		Color = SELL_NAVY_DEEP,
		Material = Enum.Material.SmoothPlastic,
	})
	attachPart(decor, {
		Name = "SellCounterTop",
		Size = Vector3.new(counterSize.X + 0.7, 0.5, counterSize.Z + 0.9),
		CFrame = sellLocalCF(base, Vector3.new(0, 2.85, -0.55)),
		Color = SELL_TOP,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.08,
	})
	attachPart(decor, {
		Name = "SellCounterTopEdge",
		Size = Vector3.new(counterSize.X + 0.85, 0.18, 0.28),
		CFrame = sellLocalCF(base, Vector3.new(0, 2.7, 2.55)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellCounterSideNeonL",
		Size = Vector3.new(0.2, counterSize.Y + 0.3, counterSize.Z + 0.2),
		CFrame = sellLocalCF(base, Vector3.new(-counterSize.X / 2 - 0.05, 0.55, -0.8)),
		Color = SELL_BLUE,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellCounterSideNeonR",
		Size = Vector3.new(0.2, counterSize.Y + 0.3, counterSize.Z + 0.2),
		CFrame = sellLocalCF(base, Vector3.new(counterSize.X / 2 + 0.05, 0.55, -0.8)),
		Color = SELL_BLUE,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
	})

	-- Façade avant + écran digital incliné
	attachPart(decor, {
		Name = "SellFrontPanel",
		Size = Vector3.new(counterSize.X - 1.2, 3.2, 0.55),
		CFrame = sellLocalCF(base, Vector3.new(0, 0.7, 2.35), CFrame.Angles(math.rad(-12), 0, 0)),
		Color = SELL_NAVY_DEEP,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	local valueBoard = attachPart(decor, {
		Name = "SellValueBoard",
		Size = Vector3.new(9.2, 2.55, 0.22),
		CFrame = sellLocalCF(base, Vector3.new(0.3, 0.85, 2.65), tiltFront),
		Color = Color3.fromRGB(6, 14, 34),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	-- Cadre ouvert devant l'écran (pas de plaque pleine qui masque le SurfaceGui de près).
	local valueBorderCF = sellLocalCF(base, Vector3.new(0.3, 0.85, 2.82), tiltFront)
	attachOpenBorder(decor, "SellValueBorder", valueBorderCF, 9.7, 2.95, 0.28, 0.12, SELL_CYAN, 0.12)
	addSellValueScreen(valueBoard)
	attachPart(decor, {
		Name = "SellValueCoin",
		Size = Vector3.new(0.22, 1.05, 1.05),
		CFrame = sellLocalCF(base, Vector3.new(-3.9, 0.7, 2.95), CFrame.Angles(math.rad(-14), math.rad(90), 0)),
		Color = SELL_GOLD,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
	})

	--------------------------------------------------------------------
	-- Auvent multi-couches
	--------------------------------------------------------------------
	local canopy = booth.CanopySize
	attachPart(decor, {
		Name = "SellCanopy",
		Size = canopy,
		CFrame = sellLocalCF(base, Vector3.new(0, 7.55, 0.8)),
		Color = SELL_NAVY_DEEP,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	attachPart(decor, {
		Name = "SellCanopyMid",
		Size = Vector3.new(canopy.X - 1.2, 0.55, canopy.Z - 1.4),
		CFrame = sellLocalCF(base, Vector3.new(0, 8.25, 0.5)),
		Color = SELL_NAVY,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	attachPart(decor, {
		Name = "SellCanopyLip",
		Size = Vector3.new(canopy.X + 0.4, 0.7, 1.4),
		CFrame = sellLocalCF(base, Vector3.new(0, 7.2, canopy.Z / 2 + 0.3)),
		Color = SELL_NAVY,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	attachPart(decor, {
		Name = "SellCanopyFrontNeon",
		Size = Vector3.new(canopy.X + 0.3, 0.32, 0.32),
		CFrame = sellLocalCF(base, Vector3.new(0, 7.05, canopy.Z / 2 + 0.95)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellCanopyUnderNeon",
		Size = Vector3.new(canopy.X - 2, 0.18, 0.18),
		CFrame = sellLocalCF(base, Vector3.new(0, 6.95, 2.2)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellCanopyCornerL",
		Size = Vector3.new(0.4, 0.4, 2.2),
		CFrame = sellLocalCF(base, Vector3.new(-canopy.X / 2 + 0.2, 7.35, canopy.Z / 2 - 0.4)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellCanopyCornerR",
		Size = Vector3.new(0.4, 0.4, 2.2),
		CFrame = sellLocalCF(base, Vector3.new(canopy.X / 2 - 0.2, 7.35, canopy.Z / 2 - 0.4)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})

	--------------------------------------------------------------------
	-- Enseigne « SELL YOUR BUBBLES »
	--------------------------------------------------------------------
	local signSize = booth.SignSize
	local sign = attachPart(decor, {
		Name = "SellSign",
		Size = signSize,
		CFrame = sellLocalCF(base, Vector3.new(0, 10.0, 0.9), faceFront),
		Color = SELL_PANEL,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	attachPart(decor, {
		Name = "SellSignBack",
		Size = Vector3.new(signSize.X + 0.8, signSize.Y + 0.7, 0.55),
		CFrame = sellLocalCF(base, Vector3.new(0, 10.0, 0.45)),
		Color = SELL_NAVY_DEEP,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	local signBorderCF = sellLocalCF(base, Vector3.new(0, 10.0, 1.58), faceFront)
	attachOpenBorder(decor, "SellSignBorder", signBorderCF, signSize.X + 0.55, signSize.Y + 0.55, 0.28, 0.14, SELL_CYAN, 0.12)
	attachPart(decor, {
		Name = "SellSignTopNeon",
		Size = Vector3.new(signSize.X + 0.2, 0.22, 0.22),
		CFrame = sellLocalCF(base, Vector3.new(0, 10.0 + signSize.Y / 2 + 0.15, 1.35)),
		Color = SELL_BLUE,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	addSellTitleGui(sign)

	local bubbleDecors: { { pos: Vector3, size: number } } = {
		{ pos = Vector3.new(-6.4, 10.55, 1.7), size = 1.15 },
		{ pos = Vector3.new(-5.5, 9.45, 1.65), size = 0.75 },
		{ pos = Vector3.new(-6.9, 9.7, 1.55), size = 0.55 },
		{ pos = Vector3.new(6.3, 10.5, 1.7), size = 1.2 },
		{ pos = Vector3.new(5.4, 9.5, 1.65), size = 0.7 },
		{ pos = Vector3.new(6.8, 9.75, 1.55), size = 0.5 },
		{ pos = Vector3.new(-4.2, 10.9, 1.5), size = 0.45 },
		{ pos = Vector3.new(4.3, 10.85, 1.5), size = 0.4 },
	}
	for i, info in ipairs(bubbleDecors) do
		local d = info.size
		attachPart(decor, {
			Name = "SellSignBubble" .. tostring(i),
			Size = Vector3.new(d, d, d),
			CFrame = sellLocalCF(base, info.pos),
			Color = if i % 2 == 0 then SELL_CYAN else SELL_CYAN_SOFT,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			Shape = Enum.PartType.Ball,
			Reflectance = 0.25,
		})
	end

	--------------------------------------------------------------------
	-- Bocal central (élément principal)
	--------------------------------------------------------------------
	local tankLocal = Vector3.new(0, 5.15, -0.55)
	local tankH, tankD = 5.4, 4.0
	attachPart(decor, {
		Name = "SellTank",
		Size = Vector3.new(tankH, tankD, tankD),
		CFrame = sellLocalCF(base, tankLocal, CFrame.Angles(0, 0, math.rad(90))),
		Color = Color3.fromRGB(120, 210, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.42,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Reflectance = 0.28,
	})
	-- Anneaux base / sommet
	attachPart(decor, {
		Name = "SellTankBase",
		Size = Vector3.new(0.55, tankD + 0.5, tankD + 0.5),
		CFrame = sellLocalCF(base, tankLocal + Vector3.new(0, -tankH / 2 - 0.05, 0), CFrame.Angles(0, 0, math.rad(90))),
		Color = SELL_BLUE,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
	})
	attachPart(decor, {
		Name = "SellTankBasePlate",
		Size = Vector3.new(0.35, tankD + 0.1, tankD + 0.1),
		CFrame = sellLocalCF(base, tankLocal + Vector3.new(0, -tankH / 2 + 0.35, 0), CFrame.Angles(0, 0, math.rad(90))),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
	})
	attachPart(decor, {
		Name = "SellTankTop",
		Size = Vector3.new(0.45, tankD + 0.35, tankD + 0.35),
		CFrame = sellLocalCF(base, tankLocal + Vector3.new(0, tankH / 2 + 0.05, 0), CFrame.Angles(0, 0, math.rad(90))),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
	})
	attachPart(decor, {
		Name = "SellTankCoreGlow",
		Size = Vector3.new(tankH - 0.8, tankD * 0.55, tankD * 0.55),
		CFrame = sellLocalCF(base, tankLocal, CFrame.Angles(0, 0, math.rad(90))),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		Transparency = 0.78,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
	})
	local tankBaseLightPart = attachPart(decor, {
		Name = "SellTankLightHost",
		Size = Vector3.new(1, 1, 1),
		CFrame = sellLocalCF(base, tankLocal + Vector3.new(0, -1.2, 0)),
		Color = SELL_CYAN,
		Material = Enum.Material.Neon,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	local tankLight = Instance.new("PointLight")
	tankLight.Name = "SellTankLight"
	tankLight.Brightness = 1.1
	tankLight.Range = 12
	tankLight.Color = SELL_CYAN
	tankLight.Parent = tankBaseLightPart

	startSellTankBubbleAnims(decor, sellLocalCF(base, tankLocal), 1.25, tankH - 1.2, booth.TankBubbleCount)

	--------------------------------------------------------------------
	-- Terminal secondaire (droite, plus grand)
	--------------------------------------------------------------------
	attachPart(decor, {
		Name = "SellTerminal",
		Size = Vector3.new(2.6, 3.8, 1.6),
		CFrame = sellLocalCF(base, Vector3.new(5.1, 4.85, -1.1)),
		Color = SELL_NAVY_DEEP,
		Material = Enum.Material.SmoothPlastic,
	})
	attachOpenBorder(
		decor,
		"SellTerminalBorder",
		sellLocalCF(base, Vector3.new(5.1, 4.9, -0.05), faceFront),
		2.85,
		4.05,
		0.22,
		0.12,
		SELL_CYAN,
		0.15
	)
	local terminalScreen = attachPart(decor, {
		Name = "SellTerminalScreen",
		Size = Vector3.new(2.35, 3.5, 0.16),
		CFrame = sellLocalCF(base, Vector3.new(5.1, 4.9, -0.1), faceFront),
		Color = Color3.fromRGB(8, 14, 32),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})

	local termGui = Instance.new("SurfaceGui")
	termGui.Name = "TerminalGui"
	termGui.Face = Enum.NormalId.Front
	termGui.Enabled = true
	termGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	termGui.PixelsPerStud = 40
	termGui.LightInfluence = 0
	termGui.Brightness = 1.15
	termGui.AlwaysOnTop = false
	termGui.Parent = terminalScreen

	local termFrame = Instance.new("Frame")
	termFrame.Size = UDim2.fromScale(1, 1)
	termFrame.BackgroundColor3 = Color3.fromRGB(6, 12, 30)
	termFrame.BorderSizePixel = 0
	termFrame.Parent = termGui

	local termStroke = Instance.new("UIStroke")
	termStroke.Color = SELL_CYAN
	termStroke.Thickness = 3
	termStroke.Parent = termFrame

	local termLabel = Instance.new("TextLabel")
	termLabel.Size = UDim2.new(1, -16, 0.42, 0)
	termLabel.Position = UDim2.new(0, 8, 0.06, 0)
	termLabel.BackgroundTransparency = 1
	termLabel.TextColor3 = PALETTE.White
	termLabel.Font = Enum.Font.GothamBold
	termLabel.TextScaled = true
	termLabel.TextWrapped = true
	termLabel.Parent = termFrame
	L10nUtil.localize(termLabel, L10n.TurnBubblesIntoCoins)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, -16, 0.42, 0)
	iconLabel.Position = UDim2.new(0, 8, 0.5, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextColor3 = SELL_CYAN
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextScaled = true
	iconLabel.Parent = termFrame
	L10nUtil.dynamic(iconLabel, "▼  $")

	-- Pictogramme 3D sous le texte (sac + bulle)
	attachPart(decor, {
		Name = "SellTerminalBagIcon",
		Size = Vector3.new(1.15, 1.25, 0.7),
		CFrame = sellLocalCF(base, Vector3.new(5.1, 3.55, 0.15)),
		Color = SELL_GOLD,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})
	attachPart(decor, {
		Name = "SellTerminalDropBubble",
		Size = Vector3.new(0.85, 0.85, 0.85),
		CFrame = sellLocalCF(base, Vector3.new(5.1, 4.45, 0.2)),
		Color = SELL_CYAN,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Ball,
		Reflectance = 0.2,
	})
end

local SellKioskBuilder = require(script.Parent.SellKioskBuilder)

-- Face avant (-Z local) vers le spawn : yaw Y uniquement, jamais de pitch/roll.
local function boardCFrameFacingSpawn(boardPos: Vector3, spawnPos: Vector3): CFrame
	local lookTarget = Vector3.new(spawnPos.X, boardPos.Y, spawnPos.Z)
	local delta = lookTarget - boardPos
	if delta.Magnitude < 0.05 then
		return CFrame.new(boardPos)
	end
	local _, yaw = CFrame.lookAt(boardPos, lookTarget):ToOrientation()
	return CFrame.new(boardPos) * CFrame.Angles(0, yaw, 0)
end

local function _clearSurfaceGuis(part: BasePart)
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceGui") then
			child:Destroy()
		end
	end
end

local function upsertBoardPart(
	decor: Folder,
	names: { string },
	canonicalName: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	canCollide: boolean?
): BasePart
	local existing: Instance? = nil
	for _, name in ipairs(names) do
		existing = decor:FindFirstChild(name)
		if existing then
			break
		end
	end

	local frame: BasePart
	if existing and existing:IsA("BasePart") then
		frame = existing
		frame.Name = canonicalName
		frame.Size = size
		frame.CFrame = cf
		frame.Color = color
		frame.Material = Enum.Material.SmoothPlastic
		if canCollide ~= nil then
			frame.CanCollide = canCollide
		end
		markGenerated(frame)
	else
		frame = makePart({
			Name = canonicalName,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = canCollide,
		})
		frame.Parent = decor
	end
	return frame
end

local function buildLeaderboardBoard(decor: Folder, root: Vector3)
	-- Panneau est (mur +X), face vers le spawn. SurfaceGui Front via LeaderboardService.
	local L = Config.Lobby
	local spawnPos = root + L.SpawnOffset
	local size = Vector3.new(12, 14, 0.6)
	local wallInset = 3.2
	-- Est, légèrement au sud du centre : visible en tournant à gauche depuis le spawn (-Z).
	local boardPos = root + Vector3.new(L.FloorSize.X / 2 - wallInset, size.Y / 2, -8)
	local cf = boardCFrameFacingSpawn(boardPos, spawnPos)

	local frame = upsertBoardPart(
		decor,
		{ "GlobalLeaderboardBoard", "LeaderboardBoard" },
		"GlobalLeaderboardBoard",
		size,
		cf,
		Color3.fromRGB(22, 30, 55),
		true
	)
	frame:SetAttribute("BPW_DisplaySurface", true)
	frame:SetAttribute("GeneratedByCode", true)

	local headerSize = Vector3.new(12.2, 1.8, 0.5)
	local headerPos = boardPos + Vector3.new(0, size.Y / 2 + headerSize.Y / 2 + 0.12, 0)
	local headerCF = boardCFrameFacingSpawn(headerPos, spawnPos)
	upsertBoardPart(
		decor,
		{ "LeaderboardHeader" },
		"LeaderboardHeader",
		headerSize,
		headerCF,
		PALETTE.Violet,
		false
	)
	local headerInst = decor:FindFirstChild("LeaderboardHeader")
	if headerInst and headerInst:IsA("BasePart") then
		headerInst.Material = Enum.Material.Neon
	end
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

-- Panneau d'instructions (sud-est) : assemblage local + PivotTo (yaw seul).
local function buildInstructionBoard(decor: Folder, root: Vector3)
	local L = Config.Lobby
	local spawnPos = root + L.SpawnOffset

	-- Réutiliser le Model existant (pas de doublon).
	local group = decor:FindFirstChild("InstructionBoard")
	if group and not group:IsA("Model") then
		group:Destroy()
		group = nil
	end
	if not group then
		group = Instance.new("Model")
		group.Name = "InstructionBoard"
		markGenerated(group)
		group.Parent = decor
	else
		for _, child in ipairs(group:GetChildren()) do
			child:Destroy()
		end
	end

	-- Décor hérité (anciennes formes).
	for _, name in ipairs({ "GuideSign", "InstructionBoardGroup" }) do
		local stale = decor:FindFirstChild(name)
		if stale then
			stale:Destroy()
		end
	end

	local panelSize = Vector3.new(12, 7.2, 0.55)
	local wallInset = 6.8
	local boardPos = root + Vector3.new(18, panelSize.Y / 2 + 1.1, -(L.FloorSize.Z / 2 - wallInset))
	local baseCF = boardCFrameFacingSpawn(boardPos, spawnPos)

	local halfW, halfH = panelSize.X / 2, panelSize.Y / 2
	local groundY = root.Y
	local postH = boardPos.Y - halfH - groundY
	if postH < 1.2 then
		postH = 1.2
	end
	local postSize = Vector3.new(0.55, postH, 0.55)
	local postHalfW = 4.2

	local navy = Color3.fromRGB(18, 42, 88)
	local cyan = Color3.fromRGB(70, 220, 255)
	local lightBlue = Color3.fromRGB(140, 210, 255)
	local pink = Color3.fromRGB(255, 130, 200)

	-- Toutes les pièces : offsets locaux (origine = centre du panneau), rotation identité.
	local function attachLocal(props: {
		Name: string,
		Size: Vector3,
		LocalCF: CFrame,
		Color: Color3?,
		Material: Enum.Material?,
		Transparency: number?,
		CanCollide: boolean?,
		CanQuery: boolean?,
		Shape: Enum.PartType?,
		Reflectance: number?,
	}): Part
		local p = makePart({
			Name = props.Name,
			Size = props.Size,
			CFrame = props.LocalCF,
			Color = props.Color,
			Material = props.Material,
			Transparency = props.Transparency,
			CanCollide = props.CanCollide,
			CanQuery = props.CanQuery,
			Shape = props.Shape,
		})
		if props.Reflectance then
			p.Reflectance = props.Reflectance
		end
		p.Anchored = true
		p.Parent = group
		return p
	end

	local borderT = 0.28
	local frameDepth = 0.22
	local frameZ = -panelSize.Z / 2 - frameDepth / 2

	attachLocal({
		Name = "PanelBack",
		Size = panelSize + Vector3.new(0.35, 0.35, 0.35),
		LocalCF = CFrame.new(0, 0, 0.28),
		Color = Color3.fromRGB(10, 28, 62),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})

	local panel = attachLocal({
		Name = "Panel",
		Size = panelSize,
		LocalCF = CFrame.new(),
		Color = navy,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})

	local frameSpecs = {
		{ "FrameTop", Vector3.new(panelSize.X + borderT * 2, borderT, frameDepth), Vector3.new(0, halfH + borderT / 2, frameZ) },
		{ "FrameBottom", Vector3.new(panelSize.X + borderT * 2, borderT, frameDepth), Vector3.new(0, -halfH - borderT / 2, frameZ) },
		{ "FrameLeft", Vector3.new(borderT, panelSize.Y, frameDepth), Vector3.new(-halfW - borderT / 2, 0, frameZ) },
		{ "FrameRight", Vector3.new(borderT, panelSize.Y, frameDepth), Vector3.new(halfW + borderT / 2, 0, frameZ) },
	}
	for _, spec in ipairs(frameSpecs) do
		attachLocal({
			Name = spec[1] :: string,
			Size = spec[2] :: Vector3,
			LocalCF = CFrame.new(spec[3] :: Vector3),
			Color = cyan,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
	end
	for _, corner in ipairs({
		Vector3.new(-halfW - borderT / 2, halfH + borderT / 2, frameZ),
		Vector3.new(halfW + borderT / 2, halfH + borderT / 2, frameZ),
		Vector3.new(-halfW - borderT / 2, -halfH - borderT / 2, frameZ),
		Vector3.new(halfW + borderT / 2, -halfH - borderT / 2, frameZ),
	}) do
		attachLocal({
			Name = "FrameCorner",
			Size = Vector3.new(borderT * 1.35, borderT * 1.35, borderT * 1.35),
			LocalCF = CFrame.new(corner),
			Color = cyan,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			Shape = Enum.PartType.Ball,
		})
	end

	local headerSize = Vector3.new(9.2, 1.55, 0.45)
	local headerY = halfH + headerSize.Y / 2 + 0.22
	local headerZ = -0.05
	local headerLocal = CFrame.new(0, headerY, headerZ)

	local header = attachLocal({
		Name = "TitleHeader",
		Size = headerSize,
		LocalCF = headerLocal,
		Color = Color3.fromRGB(24, 58, 110),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})
	attachLocal({
		Name = "TitleHeaderBorder",
		Size = headerSize + Vector3.new(0.3, 0.3, 0.12),
		LocalCF = headerLocal * CFrame.new(0, 0, 0.12),
		Color = cyan,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})

	attachLocal({
		Name = "TitleBubble",
		Size = Vector3.new(0.85, 0.85, 0.85),
		LocalCF = headerLocal * CFrame.new(-3.6, 0.05, -0.35),
		Color = cyan,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Ball,
		Reflectance = 0.25,
	})
	attachLocal({
		Name = "TitleBubbleHighlight",
		Size = Vector3.new(0.28, 0.28, 0.28),
		LocalCF = headerLocal * CFrame.new(-3.75, 0.22, -0.55),
		Color = PALETTE.White,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		Shape = Enum.PartType.Ball,
	})

	local titleGui = Instance.new("SurfaceGui")
	titleGui.Name = "TitleGui"
	titleGui.Face = Enum.NormalId.Front
	titleGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	titleGui.PixelsPerStud = 45
	titleGui.AlwaysOnTop = false
	titleGui.LightInfluence = 0
	titleGui.ClipsDescendants = true
	titleGui.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -36, 1, -10)
	titleLabel.Position = UDim2.new(0, 28, 0, 5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextColor3 = PALETTE.White
	titleLabel.TextScaled = true
	titleLabel.TextWrapped = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.Parent = titleGui
	L10nUtil.localize(titleLabel, L10n.HowToPlayTitle)
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MinTextSize = 18
	titleConstraint.MaxTextSize = 42
	titleConstraint.Parent = titleLabel

	-- Supports : verticaux, symétriques, sommet au bas du panneau.
	for _, side in ipairs({ -postHalfW, postHalfW }) do
		attachLocal({
			Name = "Post",
			Size = postSize,
			LocalCF = CFrame.new(side, -halfH - postH / 2, 0),
			Color = Color3.fromRGB(35, 55, 100),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
			CanQuery = false,
		})
	end

	local deco = {
		{ Vector3.new(-5.8, 3.2, -0.55), 1.1, cyan, 0.35 },
		{ Vector3.new(5.6, 2.8, -0.5), 0.9, pink, 0.4 },
		{ Vector3.new(-5.4, -2.9, -0.45), 0.75, lightBlue, 0.45 },
		{ Vector3.new(5.5, -3.1, -0.5), 0.85, cyan, 0.38 },
		{ Vector3.new(0.2, 4.55, -0.4), 0.55, pink, 0.5 },
	}
	for i, d in ipairs(deco) do
		attachLocal({
			Name = "DecoBubble" .. tostring(i),
			Size = Vector3.new(d[2] :: number, d[2] :: number, d[2] :: number),
			LocalCF = CFrame.new(d[1] :: Vector3),
			Color = d[3] :: Color3,
			Material = Enum.Material.Glass,
			Transparency = d[4] :: number,
			CanCollide = false,
			CanQuery = false,
			Shape = Enum.PartType.Ball,
			Reflectance = 0.2,
		})
	end

	local bodyGui = Instance.new("SurfaceGui")
	bodyGui.Name = "InstructionsGui"
	bodyGui.Face = Enum.NormalId.Front
	bodyGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	bodyGui.PixelsPerStud = 40
	bodyGui.AlwaysOnTop = false
	bodyGui.LightInfluence = 0
	bodyGui.ClipsDescendants = true
	bodyGui.Parent = panel

	local rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.BackgroundTransparency = 1
	rootFrame.Parent = bodyGui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.06, 0)
	pad.PaddingBottom = UDim.new(0.06, 0)
	pad.PaddingLeft = UDim.new(0.07, 0)
	pad.PaddingRight = UDim.new(0.07, 0)
	pad.Parent = rootFrame

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0.028, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rootFrame

	local lines = {
		L10n.HowToPlayLine1,
		L10n.HowToPlayLine2,
		L10n.HowToPlayLine3,
		L10n.HowToPlayLine4,
		L10n.HowToPlayLine5,
	}
	for i, lineText in ipairs(lines) do
		local row = Instance.new("Frame")
		row.Name = "Line" .. tostring(i)
		row.Size = UDim2.new(1, 0, 0.16, 0)
		row.BackgroundTransparency = 1
		row.LayoutOrder = i
		row.Parent = rootFrame

		local num = Instance.new("TextLabel")
		num.Name = "Num"
		num.Size = UDim2.new(0.12, 0, 1, 0)
		num.BackgroundTransparency = 1
		num.Font = Enum.Font.FredokaOne
		num.TextColor3 = cyan
		num.TextScaled = true
		num.TextXAlignment = Enum.TextXAlignment.Left
		num.TextYAlignment = Enum.TextYAlignment.Center
		num.Parent = row
		L10nUtil.localize(num, tostring(i) .. ".")
		local numCap = Instance.new("UITextSizeConstraint")
		numCap.MinTextSize = 16
		numCap.MaxTextSize = 36
		numCap.Parent = num

		local body = Instance.new("TextLabel")
		body.Name = "Body"
		body.Size = UDim2.new(0.88, 0, 1, 0)
		body.Position = UDim2.new(0.12, 0, 0, 0)
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.GothamBold
		body.TextColor3 = PALETTE.White
		body.TextScaled = true
		body.TextWrapped = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Center
		body.Parent = row
		local bodyOnly = (lineText:gsub("^%d+%.%s*", ""))
		L10nUtil.localize(body, bodyOnly)
		local bodyCap = Instance.new("UITextSizeConstraint")
		bodyCap.MinTextSize = 14
		bodyCap.MaxTextSize = 32
		bodyCap.Parent = body
	end

	group.PrimaryPart = panel
	group:PivotTo(baseCF)
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

	local codeBooth = L.SellBooth.Mode ~= "StudioModel"
	if codeBooth and lobby:FindFirstChild("SellKiosk") then
		warn("[ZoneService] SellKiosk Studio présent alors que SellBooth.Mode = \"Code\" — "
			.. "supprime-le pour éviter deux kiosques superposés.")
	end

	-- Bande centrale (chemin praticable vers l'entrée)
	local decor = ensureDecorFolder(lobby, "LobbyDecor")
	if #decor:GetChildren() == 0 then
		local path = makePart({
			Name = "LobbyPath",
			Size = Vector3.new(16, 1.5, 56),
			CFrame = CFrame.new(root + Vector3.new(0, 0.15, 10)),
			Color = PALETTE.FloorAccent,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
		path.Parent = decor

		buildLobbyRailings(decor, root, L.FloorSize)
		buildEntranceArch(decor, root)
		if codeBooth then
			buildSellBooth(decor, root)
		end
		buildSpawnRing(decor, root)
	end

	-- Panneaux lobby : toujours (ré)alignés face au spawn (idempotent).
	buildInstructionBoard(decor, root)
	buildLeaderboardBoard(decor, root)

	-- Décor hérité : anciens noms / indices obsolètes.
	local staleGuide = decor:FindFirstChild("GuideSign")
	if staleGuide then
		staleGuide:Destroy()
	end
	local staleHint = decor:FindFirstChild("EntranceHint")
	if staleHint then
		staleHint:Destroy()
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

	-- Trigger technique invisible (pad de vente devant le kiosque)
	local sellZone: BasePart
	if codeBooth then
		sellZone = ensurePart(lobby, "SellZone", function()
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = true
			p.CanTouch = false
			p.Transparency = 1
			p.Size = L.SellZoneSize
			p.CFrame = sellBoothBaseCF(root) * CFrame.new(L.SellBooth.PadLocalOffset)
			return p
		end)
	else
		-- Mode "StudioModel" : priorité au Part dans SellKiosk ; sinon fallback config.
		SellKioskBuilder.Bind(lobby)
		local bound = SellKioskBuilder.GetSellZone(lobby)
		if bound then
			sellZone = bound
		else
			sellZone = ensurePart(lobby, "SellZone", function()
				local p = Instance.new("Part")
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = true
				p.CanTouch = false
				p.Transparency = 1
				p.Size = L.SellZoneSize
				p.CFrame = SellKioskBuilder.GetPadWorldCFrame(root, lobby)
				markGenerated(p)
				return p
			end)
			warn("[ZoneService] SellZone fallback lobby — place SellPad/SellZone dans SellKiosk Studio.")
		end
	end

	-- Marqueur logique uniquement (plus de téléport / prompt).
	local entrance = ensurePart(lobby, "GameEntrance", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = L.EntranceSize
		p.CFrame = CFrame.new(L.EntrancePosition)
		return p
	end)
	entrance.CanTouch = false
	entrance.CanQuery = false
	entrance.Transparency = 1
	for _, child in ipairs(entrance:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end

	-- Vente automatique : plus aucun prompt à déclencher sur la zone de vente.
	for _, child in ipairs(sellZone:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
	sellZonePart = sellZone
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
	addSurfaceSign(lintel, Enum.NormalId.Front, L10n.BackToLobby)
	addSurfaceSign(lintel, Enum.NormalId.Back, L10n.BackToLobby)
end

--------------------------------------------------------------------
-- Passage physique lobby ↔ salle (escalier + palier, aucun téléport)
--------------------------------------------------------------------
local function buildPhysicalConnection(parent: Folder)
	local connection = ensureFolder(parent, "Connection")
	clearGeneratedChildren(connection)

	local decor = ensureDecorFolder(connection, "ConnectionDecor")
	if #decor:GetChildren() > 0 then
		return
	end

	local L = Config.Lobby
	local R = Config.GameRoom
	local G = Config.Grid
	local root = L.RootOffset
	local lobbyTopY = root.Y
	local roomTopY = G.Origin.Y
	local rise = roomTopY - lobbyTopY
	local width = 16

	local exitSouthZ = R.ExitPosition.Z - R.ExitPadSize.Z / 2
	local spawnNorthZ = R.SpawnPadPosition.Z + R.PadSize.Z / 2

	-- Escalier : démarre sous l'arche, finit pile à la face sud du ExitPad (hauteur salle).
	local stepCount = math.max(6, math.ceil(rise / 1.0))
	local stepRise = rise / stepCount
	local stepDepth = 3.0
	local stepThickness = math.max(1.15, stepRise + 0.25)
	local stairsEndZ = exitSouthZ
	local stairsStartZ = stairsEndZ - stepCount * stepDepth

	-- 1) Pont d'approche lobby → pied de l'escalier (comble le trou).
	local approachStartZ = math.min(L.EntrancePosition.Z - 4, stairsStartZ - 2)
	local approachEndZ = stairsStartZ + 0.5
	local approachLen = math.max(4, approachEndZ - approachStartZ)
	local approach = makePart({
		Name = "ApproachDeck",
		Size = Vector3.new(width, 1.5, approachLen),
		CFrame = CFrame.new(0, lobbyTopY + 0.15, (approachStartZ + approachEndZ) / 2),
		Color = PALETTE.FloorAccent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})
	approach.Parent = decor

	-- 2) Marches montantes (+Z).
	for i = 1, stepCount do
		local topY = lobbyTopY + stepRise * i
		local centerZ = stairsStartZ + (i - 0.5) * stepDepth
		local step = makePart({
			Name = "StairStep" .. tostring(i),
			Size = Vector3.new(width, stepThickness, stepDepth + 0.2),
			CFrame = CFrame.new(0, topY - stepThickness / 2, centerZ),
			Color = if i % 2 == 0 then Color3.fromRGB(48, 75, 130) else Color3.fromRGB(40, 65, 115),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
		step.Parent = decor
	end

	-- 3) Palier haut continu ExitPad → SpawnPad (niveau salle).
	local landingStartZ = stairsEndZ - 1
	local landingEndZ = spawnNorthZ
	local landingLen = math.max(8, landingEndZ - landingStartZ)
	local landing = makePart({
		Name = "UpperLanding",
		Size = Vector3.new(width + 6, 2, landingLen),
		CFrame = CFrame.new(0, roomTopY - 1, (landingStartZ + landingEndZ) / 2),
		Color = R.PadColor,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	})
	landing.Parent = decor

	-- Garde-corps latéraux sur le parcours.
	local railHeight = rise + 5
	local totalPathStart = approachStartZ
	local totalPathEnd = landingEndZ
	local totalLen = totalPathEnd - totalPathStart
	local midZ = (totalPathStart + totalPathEnd) / 2
	for _, side in ipairs({ -1, 1 }) do
		local rail = makePart({
			Name = if side < 0 then "ConnRailLeft" else "ConnRailRight",
			Size = Vector3.new(0.9, railHeight, totalLen),
			CFrame = CFrame.new(side * (width / 2 + 0.2), lobbyTopY + railHeight / 2, midZ),
			Color = PALETTE.CyanDeep,
			Material = Enum.Material.Glass,
			Transparency = 0.35,
			CanCollide = true,
		})
		rail.Parent = decor
	end

	for _, side in ipairs({ -1, 1 }) do
		local post = makePart({
			Name = if side < 0 then "ConnPostLeft" else "ConnPostRight",
			Size = Vector3.new(1.4, 7, 1.4),
			CFrame = CFrame.new(side * (width / 2 - 0.5), roomTopY + 3.5, stairsEndZ),
			Color = PALETTE.Violet,
			Material = Enum.Material.SmoothPlastic,
		})
		post.Parent = decor
	end
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

	-- Ancien trigger de téléport : désactivé (marqueur décoratif invisible seulement).
	local exitZone = ensurePart(gameRoom, "ExitZone", function()
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = R.ExitSize
		p.CFrame = CFrame.new(exitPos)
		return p
	end)
	exitZone.CanTouch = false
	exitZone.CanQuery = false
	exitZone.Transparency = 1
	for _, child in ipairs(exitZone:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end

	buildSafetyBorders(gameRoom)
end

--------------------------------------------------------------------
-- Monde additif
--------------------------------------------------------------------
function ZoneService.EnsureWorld(): Folder
	disableStudioBaseplate()

	-- Jamais utiliser la prévisualisation d'édition Studio en Play.
	LobbyEditingPreview.RemoveLobbyEditingPreview()

	local root = ensureFolder(workspace, "BubblePopWorld")
	local lobby = ensureLobby(root)
	local gameRoom = ensureFolder(root, "GameRoom")

	-- Migration dev : supprimer uniquement GeneratedByCode (jamais le SellKiosk Studio).
	clearGeneratedChildren(lobby)
	clearGeneratedChildren(gameRoom)
	local connectionFolder = ensureFolder(root, "Connection")
	clearGeneratedChildren(connectionFolder)

	buildLobby(lobby)
	buildGameRoom(gameRoom)
	buildPhysicalConnection(root)

	-- Zones de jeu (planches / passerelle / barrière). Ne touche jamais StudioDecoration.
	ZoneBuilder.EnsureStudioDecoration()
	ZoneBuilder.BuildPlayZones()

	-- Décor d'horizon (montagnes) : Workspace.GeneratedWorld.EnvironmentBackdrop uniquement.
	EnvironmentBackdropBuilder.Build()

	-- Remplit le panneau Top 10 dès que le décor lobby est prêt.
	task.defer(function()
		local ok, leaderboard = pcall(function()
			return require(script.Parent.LeaderboardService)
		end)
		if ok and leaderboard and leaderboard.RefreshWorldBoard then
			leaderboard.RefreshWorldBoard()
		end
	end)

	return root
end

--------------------------------------------------------------------
-- Téléports : spawn initial + FallReset uniquement (jamais lobby ↔ salle)
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

-- Spawn initial / FallReset lobby uniquement.
function ZoneService.TeleportToLobby(player: Player, bypassCooldown: boolean?): boolean
	if not lobbySpawnPart then
		return false
	end
	return doTeleport(player, lobbySpawnPart.Position + Vector3.new(0, 3, 0), "Lobby", bypassCooldown)
end

-- FallReset salle uniquement (plus aucun passage lobby ↔ salle).
function ZoneService.TeleportToGameRoom(player: Player, bypassCooldown: boolean?): boolean
	if not gameRoomSpawnPart then
		return false
	end
	return doTeleport(player, gameRoomSpawnPart.Position + Vector3.new(0, 3, 0), "GameRoom", bypassCooldown)
end

local function resolveAreaFromPosition(pos: Vector3): string
	local split = Config.World.AreaSplitZ
	if pos.Z < split then
		return "Lobby"
	end

	local summerBounds = ZoneDefs.GetZoneBounds("SummerZone")
	if summerBounds then
		local margin = 12
		if pos.X >= summerBounds.MinX - margin
			and pos.X <= summerBounds.MaxX + margin
			and pos.Z >= summerBounds.MinZ - margin
			and pos.Z <= summerBounds.MaxZ + margin then
			return "SummerZone"
		end
	end

	-- Compat : "GameRoom" conserve le comportement existant (pads + planche classique).
	return "GameRoom"
end

--------------------------------------------------------------------
-- API zones (niveau / accès) — source de vérité : ZoneDefs + DataService
--------------------------------------------------------------------
function ZoneService.GetRequiredLevel(zoneId: string): number
	return ZoneDefs.GetRequiredLevel(zoneId)
end

function ZoneService.CanPlayerEnter(player: Player, zoneId: string): boolean
	return ZoneAccess.CanPlayerEnter(player, zoneId)
end

function ZoneService.GetPlayerLevel(player: Player): number
	return ZoneAccess.GetPlayerLevel(player)
end

function ZoneService.GetPlayerZone(player: Player): string
	local area = player:GetAttribute("PlayerArea")
	if type(area) == "string" and area ~= "" then
		return area
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return resolveAreaFromPosition(hrp.Position)
	end
	return "Lobby"
end

function ZoneService.RefreshPlayerAccess(player: Player)
	ZoneAccess.RefreshPlayer(player)
end

--------------------------------------------------------------------
-- Spawn initial (debounce) + PlayerArea + FallReset
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
		-- Seul téléport de gameplay : apparition initiale dans le lobby.
		ZoneService.TeleportToLobby(player, true)
		spawningInProgress[player] = nil
	end)
end

local fallResetGuard: { [Player]: boolean } = {}

local function fallResetToLobby(player: Player): boolean
	if player:GetAttribute("PlayerArea") == "Lobby" then
		return true
	end
	return Config.World.FallResetDestination == "Lobby"
end

-- Met à jour PlayerArea par position (sans téléporter).
local function watchPlayerArea()
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local area = resolveAreaFromPosition(hrp.Position)
				if player:GetAttribute("PlayerArea") ~= area then
					player:SetAttribute("PlayerArea", area)
				end
			end
		end
	end)
end

--------------------------------------------------------------------
-- Vente automatique (kiosque de vente des bulles uniquement)
--------------------------------------------------------------------
-- `sellSpent[player]` = une vente a déjà eu lieu pour ce séjour dans la zone ;
-- il faut ressortir (au-delà de ExitMargin) pour réarmer une nouvelle vente.
local sellSpent: { [Player]: boolean } = {}
local sellLastAt: { [Player]: number } = {}

local function insideZone(zone: BasePart, pos: Vector3, margin: number): boolean
	local offset = zone.CFrame:PointToObjectSpace(pos)
	local half = zone.Size / 2
	return math.abs(offset.X) <= half.X + margin
		and math.abs(offset.Y) <= half.Y + margin
		and math.abs(offset.Z) <= half.Z + margin
end

local function watchAutoSell()
	local A = Config.Lobby.AutoSell
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < A.PollInterval then
			return
		end
		accum = 0

		local zone = sellZonePart
		if not (zone and zone.Parent) then
			return
		end

		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not (hrp and hrp:IsA("BasePart")) then
				sellSpent[player] = nil
				continue
			end

			if not insideZone(zone, hrp.Position, 0) then
				-- Hystérésis : on ne réarme qu'une fois clairement sorti de la zone.
				if not insideZone(zone, hrp.Position, A.ExitMargin) then
					sellSpent[player] = nil
				end
				continue
			end

			if sellSpent[player] then
				continue
			end

			-- Sac vide : aucune vente, aucun message (pas de spam tant qu'on reste dedans).
			local profile = DataService.Get(player)
			if not profile or profile.CurrentBubbles <= 0 then
				continue
			end

			local last = sellLastAt[player]
			if last and os.clock() - last < A.Cooldown then
				continue
			end

			sellSpent[player] = true
			sellLastAt[player] = os.clock()
			task.spawn(function()
				local sold = BackpackService.Sell(player)
				if not sold then
					-- Verrou occupé ou crédit refusé : on réarme pour un nouvel essai,
					-- que le cooldown espacera de toute façon.
					sellSpent[player] = nil
				end
			end)
		end
	end)
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
	ZoneAccess.EnsureCollisionGroups()
	ZoneService.EnsureWorld()
	ZoneAccess.Start()

	local function bindPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		if player.Character then
			onCharacterAdded(player)
		end
	end

	Players.PlayerAdded:Connect(bindPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		teleportLast[player] = nil
		spawningInProgress[player] = nil
		fallResetGuard[player] = nil
		sellSpent[player] = nil
		sellLastAt[player] = nil
	end)

	watchPlayerArea()
	watchAutoSell()
	watchFallReset()
end

return ZoneService
