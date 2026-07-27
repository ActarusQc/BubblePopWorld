--!strict
-- Construction des dossiers GameZones, passerelle, barrière et décor généré Summer.
-- Ne touche jamais Workspace.StudioDecoration.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ZoneDefs = require(Shared.ZoneDefs)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local ZoneAccess = require(script.Parent.ZoneAccess)

local ZoneBuilder = {}

local SUMMER = {
	Sand = Color3.fromRGB(230, 210, 160),
	Wood = Color3.fromRGB(160, 110, 60),
	WoodDark = Color3.fromRGB(120, 80, 40),
	Turquoise = Color3.fromRGB(40, 200, 210),
	Sky = Color3.fromRGB(120, 210, 255),
	Sun = Color3.fromRGB(255, 220, 80),
	Coral = Color3.fromRGB(255, 130, 120),
	Lime = Color3.fromRGB(140, 230, 100),
	Water = Color3.fromRGB(60, 170, 220),
	Rope = Color3.fromRGB(180, 140, 90),
}

local function markGenerated(inst: Instance)
	inst:SetAttribute("GeneratedByCode", true)
end

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

local function clearGenerated(container: Instance)
	if not Config.World.RebuildGeneratedLayout then
		return
	end
	local doomed: { Instance } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:GetAttribute("GeneratedByCode") == true then
			table.insert(doomed, child)
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
	Parent: Instance?,
}): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or SUMMER.Wood
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.CanQuery = if props.CanQuery == nil then false else props.CanQuery
	p.CanTouch = if props.CanTouch == nil then false else props.CanTouch
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	markGenerated(p)
	if props.Parent then
		p.Parent = props.Parent
	end
	return p
end

local function decorPart(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Shape: Enum.PartType?,
	Parent: Instance,
}): Part
	return makePart({
		Name = props.Name,
		Size = props.Size,
		CFrame = props.CFrame,
		Color = props.Color,
		Material = props.Material,
		Transparency = props.Transparency,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Shape = props.Shape,
		Parent = props.Parent,
	})
end

function ZoneBuilder.EnsureStudioDecoration()
	local root = ensureFolder(workspace, "StudioDecoration")
	-- Jamais GeneratedByCode / jamais clear
	local zones = ensureFolder(root, "Zones")
	ensureFolder(zones, "Classic")
	ensureFolder(zones, "Summer")
	return root
end

function ZoneBuilder.EnsureGameZonesRoot(): Folder
	local root = ensureFolder(workspace, "GameZones")
	for _, def in ipairs(ZoneDefs.List) do
		local zone = ensureFolder(root, def.Id)
		ensureFolder(zone, "Bounds")
		ensureFolder(zone, "ZoneTrigger")
		if def.RequiredLevel > 1 then
			ensureFolder(zone, "Entrance")
			ensureFolder(zone, "LevelGate")
		end
	end
	return root
end

local function bubbleExtent(): (number, number)
	local G = Config.Grid
	local safetyGap = 2
	local ex = ((G.SizeX / 2) - 0.5) * G.Spacing + G.BubbleSize.X / 2 + safetyGap
	local ez = ((G.SizeZ / 2) - 0.5) * G.Spacing + G.BubbleSize.Z / 2 + safetyGap
	return ex, ez
end

local function buildZoneBorders(boundsFolder: Folder, zoneDef: any, openWest: boolean, openEastForBridge: boolean)
	clearGenerated(boundsFolder)
	local G = Config.Grid
	local W = Config.World
	local t = W.BorderThickness
	local ex, ez = bubbleExtent()
	local o = zoneDef.Origin
	local borderH = 5 -- 4–6 studs visibles
	local color = zoneDef.BorderColor or W.BorderColor

	local function wall(name: string, size: Vector3, cf: CFrame, collide: boolean?)
		local p = makePart({
			Name = name,
			Size = Vector3.new(size.X, borderH, size.Z),
			CFrame = CFrame.new(cf.Position.X, o.Y + borderH / 2, cf.Position.Z),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			CanCollide = if collide == nil then true else collide,
			Parent = boundsFolder,
		})
		return p
	end

	wall("BorderNorth", Vector3.new((ex + t) * 2, 0, t), CFrame.new(o.X, 0, o.Z + ez + t / 2))
	wall("BorderSouth", Vector3.new((ex + t) * 2, 0, t), CFrame.new(o.X, 0, o.Z - ez - t / 2))

	local bridgeGap = Config.GameRoom.PathSize.X + 6

	if openEastForBridge then
		local segLen = math.max(0, ez + t - bridgeGap / 2)
		if segLen > 0 then
			wall("BorderEastNorth", Vector3.new(t, 0, segLen),
				CFrame.new(o.X + ex + t / 2, 0, o.Z + (bridgeGap / 2 + segLen / 2)))
			wall("BorderEastSouth", Vector3.new(t, 0, segLen),
				CFrame.new(o.X + ex + t / 2, 0, o.Z - (bridgeGap / 2 + segLen / 2)))
		end
	else
		wall("BorderEast", Vector3.new(t, 0, (ez + t) * 2), CFrame.new(o.X + ex + t / 2, 0, o.Z))
	end

	if openWest then
		local segLen = math.max(0, ez + t - bridgeGap / 2)
		if segLen > 0 then
			wall("BorderWestNorth", Vector3.new(t, 0, segLen),
				CFrame.new(o.X - ex - t / 2, 0, o.Z + (bridgeGap / 2 + segLen / 2)))
			wall("BorderWestSouth", Vector3.new(t, 0, segLen),
				CFrame.new(o.X - ex - t / 2, 0, o.Z - (bridgeGap / 2 + segLen / 2)))
		end
	else
		wall("BorderWest", Vector3.new(t, 0, (ez + t) * 2), CFrame.new(o.X - ex - t / 2, 0, o.Z))
	end
end

local function buildZoneTrigger(triggerFolder: Folder, zoneDef: any)
	clearGenerated(triggerFolder)
	local halfX, halfZ = ZoneDefs.GetGridHalfExtent()
	local o = zoneDef.Origin
	local trigger = makePart({
		Name = "AreaVolume",
		Size = Vector3.new(halfX * 2 + 8, 40, halfZ * 2 + 8),
		CFrame = CFrame.new(o.X, o.Y + 10, o.Z),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = triggerFolder,
	})
	trigger:SetAttribute("ZoneId", zoneDef.Id)
	return trigger
end

local function buildBridgeAndEntrance(gameZones: Folder)
	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local ex = select(1, bubbleExtent())
	local classicEdgeX = classic.Origin.X + ex
	local summerEdgeX = summer.Origin.X - ex
	local midX = (classicEdgeX + summerEdgeX) / 2
	local span = math.max(4, summerEdgeX - classicEdgeX)
	local y = classic.Origin.Y
	local pathW = Config.GameRoom.PathSize.X

	local summerFolder = gameZones:FindFirstChild("SummerZone") :: Folder
	local entrance = ensureFolder(summerFolder, "Entrance")
	clearGenerated(entrance)

	-- Passerelle bois
	makePart({
		Name = "BridgeDeck",
		Size = Vector3.new(span + 2, 1.5, pathW),
		CFrame = CFrame.new(midX, y - 0.75, classic.Origin.Z),
		Color = SUMMER.Wood,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
		Parent = entrance,
	})

	-- Planches / cordes latérales
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = if side < 0 then "BridgeRailLeft" else "BridgeRailRight",
			Size = Vector3.new(span, 1.2, 0.6),
			CFrame = CFrame.new(midX, y + 2.2, classic.Origin.Z + side * (pathW / 2 - 0.3)),
			Color = SUMMER.Rope,
			Material = Enum.Material.Fabric,
			CanCollide = true,
			Parent = entrance,
		})
		for i = 0, 4 do
			local px = classicEdgeX + (span * i / 4)
			decorPart({
				Name = "BridgePost" .. side .. i,
				Size = Vector3.new(0.7, 4, 0.7),
				CFrame = CFrame.new(px, y + 2, classic.Origin.Z + side * (pathW / 2 - 0.3)),
				Color = SUMMER.WoodDark,
				Material = Enum.Material.Wood,
				Parent = entrance,
			})
		end
	end

	-- Arche estivale à l'entrée Summer (côté ouest de Summer)
	local archX = summerEdgeX - 2
	local archZ = summer.Origin.Z
	local gap = pathW + 2
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = if side < 0 then "ArchPillarL" else "ArchPillarR",
			Size = Vector3.new(2, 12, 2),
			CFrame = CFrame.new(archX, y + 6, archZ + side * (gap / 2)),
			Color = SUMMER.Wood,
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = entrance,
		})
	end
	makePart({
		Name = "ArchLintel",
		Size = Vector3.new(2.5, 2, gap + 4),
		CFrame = CFrame.new(archX, y + 12, archZ),
		Color = SUMMER.Turquoise,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		Parent = entrance,
	})
	decorPart({
		Name = "ArchSun",
		Size = Vector3.new(3, 3, 0.6),
		CFrame = CFrame.new(archX - 1.5, y + 12.5, archZ),
		Color = SUMMER.Sun,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		Parent = entrance,
	})

	-- Planches de surf encadrant l'entrée
	for i, side in ipairs({ -1, 1 }) do
		local surf = decorPart({
			Name = "Surfboard" .. i,
			Size = Vector3.new(1.2, 8, 2.4),
			CFrame = CFrame.new(archX - 3, y + 4, archZ + side * (gap / 2 + 4))
				* CFrame.Angles(0, 0, math.rad(12 * side)),
			Color = if side < 0 then SUMMER.Coral else SUMMER.Sky,
			Material = Enum.Material.SmoothPlastic,
			Parent = entrance,
		})
		surf.CanCollide = false
	end

	-- Panneau SUMMER ZONE
	local sign = makePart({
		Name = "SummerZoneSign",
		Size = Vector3.new(0.6, 8, 14),
		CFrame = CFrame.new(archX - 4, y + 8, archZ + gap / 2 + 8),
		Color = SUMMER.WoodDark,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = entrance,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.Parent = sign
	markGenerated(gui)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.45)
	title.Position = UDim2.fromScale(0, 0.08)
	title.BackgroundTransparency = 1
	title.TextColor3 = SUMMER.Sun
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Parent = gui
	L10nUtil.localize(title, L10n.SummerZoneTitle)

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Size = UDim2.fromScale(1, 0.35)
	sub.Position = UDim2.fromScale(0, 0.55)
	sub.BackgroundTransparency = 1
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Parent = gui
	L10nUtil.localize(sub, L10n.SummerZoneUnlocksAt)
end

local function buildLevelGate(gameZones: Folder)
	local summer = ZoneDefs.SummerZone
	local ex = select(1, bubbleExtent())
	local summerEdgeX = summer.Origin.X - ex
	local y = summer.Origin.Y
	local pathW = Config.GameRoom.PathSize.X + 4
	local gateX = summerEdgeX + 1.5

	local summerFolder = gameZones:FindFirstChild("SummerZone") :: Folder
	local gateFolder = ensureFolder(summerFolder, "LevelGate")
	clearGenerated(gateFolder)

	local gate = makePart({
		Name = "ForceFieldGate",
		Size = Vector3.new(2.5, 14, pathW),
		CFrame = CFrame.new(gateX, y + 7, summer.Origin.Z),
		Color = Color3.fromRGB(80, 220, 230),
		Material = Enum.Material.ForceField,
		Transparency = 0.35,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		Parent = gateFolder,
	})
	gate:SetAttribute("ZoneId", summer.Id)
	ZoneAccess.RegisterGatePart(summer.Id, gate)
	ZoneAccess.BindGateTouch(summer.Id, gate)

	-- Pulsation légère
	task.spawn(function()
		local tweenIn = TweenService:Create(gate, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Transparency = 0.55,
		})
		tweenIn:Play()
	end)

	local lock = decorPart({
		Name = "LockSymbol",
		Size = Vector3.new(1.2, 2.5, 2.5),
		CFrame = CFrame.new(gateX - 1.5, y + 8, summer.Origin.Z),
		Color = SUMMER.Sun,
		Material = Enum.Material.Neon,
		Parent = gateFolder,
	})
	local lockGui = Instance.new("BillboardGui")
	lockGui.Name = "LockBillboard"
	lockGui.Size = UDim2.fromScale(6, 3)
	lockGui.StudsOffset = Vector3.new(0, 3, 0)
	lockGui.AlwaysOnTop = true
	lockGui.Parent = lock
	markGenerated(lockGui)
	local lockLabel = Instance.new("TextLabel")
	lockLabel.Size = UDim2.fromScale(1, 1)
	lockLabel.BackgroundTransparency = 1
	lockLabel.TextColor3 = SUMMER.Sun
	lockLabel.Font = Enum.Font.GothamBlack
	lockLabel.TextScaled = true
	lockLabel.Parent = lockGui
	L10nUtil.localize(lockLabel, L10n.ZoneLockIcon)
end

local function buildSummerGeneratedDecor(gameZones: Folder)
	local summer = ZoneDefs.SummerZone
	local o = summer.Origin
	local halfX, halfZ = ZoneDefs.GetGridHalfExtent()
	local summerFolder = gameZones:FindFirstChild("SummerZone") :: Folder
	local decor = ensureFolder(summerFolder, "GeneratedDecor")
	clearGenerated(decor)

	-- Bordure sable basse (hors grille, sud)
	makePart({
		Name = "SandBorderSouth",
		Size = Vector3.new(halfX * 2 + 10, 1.2, 6),
		CFrame = CFrame.new(o.X, o.Y - 1, o.Z - halfZ - 5),
		Color = SUMMER.Sand,
		Material = Enum.Material.Sand,
		CanCollide = true,
		Parent = decor,
	})

	-- Eau décorative (pas de collision)
	decorPart({
		Name = "WaterAccent",
		Size = Vector3.new(halfX * 2 + 4, 0.4, 8),
		CFrame = CFrame.new(o.X, o.Y - 1.5, o.Z + halfZ + 6),
		Color = SUMMER.Water,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Parent = decor,
	})

	-- Palmiers simples (coins)
	local palmSpots = {
		Vector3.new(o.X - halfX - 6, o.Y, o.Z - halfZ + 10),
		Vector3.new(o.X + halfX + 6, o.Y, o.Z - halfZ + 10),
		Vector3.new(o.X - halfX - 6, o.Y, o.Z + halfZ - 10),
		Vector3.new(o.X + halfX + 6, o.Y, o.Z + halfZ - 10),
	}
	for i, pos in ipairs(palmSpots) do
		decorPart({
			Name = "PalmTrunk" .. i,
			Size = Vector3.new(1.4, 10, 1.4),
			CFrame = CFrame.new(pos.X, pos.Y + 5, pos.Z),
			Color = SUMMER.WoodDark,
			Material = Enum.Material.Wood,
			Parent = decor,
		})
		decorPart({
			Name = "PalmLeaves" .. i,
			Size = Vector3.new(8, 1.5, 8),
			CFrame = CFrame.new(pos.X, pos.Y + 10.5, pos.Z),
			Color = SUMMER.Lime,
			Material = Enum.Material.Grass,
			Parent = decor,
		})
	end

	-- Parasols / chaises
	for i, side in ipairs({ -1, 1 }) do
		local px = o.X + side * (halfX + 5)
		local pz = o.Z - 20
		decorPart({
			Name = "UmbrellaPole" .. i,
			Size = Vector3.new(0.5, 7, 0.5),
			CFrame = CFrame.new(px, o.Y + 3.5, pz),
			Color = SUMMER.Wood,
			Parent = decor,
		})
		decorPart({
			Name = "UmbrellaTop" .. i,
			Size = Vector3.new(7, 0.6, 7),
			CFrame = CFrame.new(px, o.Y + 7.2, pz),
			Color = if side < 0 then SUMMER.Coral else SUMMER.Sun,
			Parent = decor,
		})
		decorPart({
			Name = "BeachChair" .. i,
			Size = Vector3.new(3, 1.2, 4),
			CFrame = CFrame.new(px + side * 3, o.Y + 0.6, pz + 4),
			Color = SUMMER.Sky,
			Parent = decor,
		})
	end

	-- Bouées / ballon / glacière
	decorPart({
		Name = "BeachBall",
		Size = Vector3.new(2.5, 2.5, 2.5),
		CFrame = CFrame.new(o.X + halfX + 4, o.Y + 1.2, o.Z),
		Color = SUMMER.Coral,
		Shape = Enum.PartType.Ball,
		Parent = decor,
	})
	decorPart({
		Name = "Cooler",
		Size = Vector3.new(3, 2.2, 2),
		CFrame = CFrame.new(o.X - halfX - 4, o.Y + 1.1, o.Z + 15),
		Color = SUMMER.Turquoise,
		Parent = decor,
	})
	decorPart({
		Name = "FloatRing",
		Size = Vector3.new(4, 0.8, 4),
		CFrame = CFrame.new(o.X + 20, o.Y + 0.5, o.Z + halfZ + 4),
		Color = SUMMER.Sun,
		Parent = decor,
	})

	-- Kiosque limonade simple
	local kioskPos = Vector3.new(o.X + halfX + 8, o.Y, o.Z + 40)
	makePart({
		Name = "LemonadeCounter",
		Size = Vector3.new(8, 3, 4),
		CFrame = CFrame.new(kioskPos.X, o.Y + 1.5, kioskPos.Z),
		Color = SUMMER.Wood,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
		Parent = decor,
	})
	decorPart({
		Name = "LemonadeRoof",
		Size = Vector3.new(10, 0.6, 6),
		CFrame = CFrame.new(kioskPos.X, o.Y + 5, kioskPos.Z),
		Color = SUMMER.Sun,
		Parent = decor,
	})
end

function ZoneBuilder.BuildPlayZones()
	ZoneBuilder.EnsureStudioDecoration()
	local gameZones = ZoneBuilder.EnsureGameZonesRoot()

	local summerFolder = gameZones:FindFirstChild("SummerZone") :: Folder

	-- Classic : les SafetyBorders de ZoneService restent la référence (ouverture est ajoutée là).
	-- Summer : bordures thématiques propres.
	buildZoneBorders(ensureFolder(summerFolder, "Bounds"), ZoneDefs.SummerZone, true, false)

	local classicFolder = gameZones:FindFirstChild("ClassicZone") :: Folder
	buildZoneTrigger(ensureFolder(classicFolder, "ZoneTrigger"), ZoneDefs.ClassicZone)
	buildZoneTrigger(ensureFolder(summerFolder, "ZoneTrigger"), ZoneDefs.SummerZone)

	buildBridgeAndEntrance(gameZones)
	buildLevelGate(gameZones)
	buildSummerGeneratedDecor(gameZones)

	return gameZones
end

-- Point milieu passerelle (pour résolution d'aire).
function ZoneBuilder.GetBridgeMidX(): number
	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local ex = select(1, bubbleExtent())
	return (classic.Origin.X + ex + summer.Origin.X - ex) / 2
end

return ZoneBuilder
