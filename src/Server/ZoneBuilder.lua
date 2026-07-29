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
	local zones = ensureFolder(root, "Zones")
	ensureFolder(zones, "Classic")
	ensureFolder(zones, "Summer")
	local decor = root:FindFirstChild("SummerZoneDecor")
	if not decor then
		decor = Instance.new("Folder")
		decor.Name = "SummerZoneDecor"
		decor:SetAttribute("ManualDecor", true)
		decor.Parent = root
	end
	-- Sous-dossiers manuels : créer s’ils manquent, ne jamais vider.
	if decor:IsA("Folder") then
		for _, name in ipairs({ "Nature", "BeachProps", "Structures", "Signs", "Effects" }) do
			ensureFolder(decor, name)
		end
	end
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

local function bubbleExtent(zoneDef: any): (number, number)
	-- Murs = emprise extérieure (pas le board réduit).
	if zoneDef.Id == "SummerZone" then
		return ZoneDefs.GetOuterPlayExtent(zoneDef.Id)
	end
	return ZoneDefs.GetBubblePlayExtent(zoneDef.Id)
end

local function zoneCenter(zoneDef: any): Vector3
	return zoneDef.ZoneOrigin or zoneDef.Origin
end

local function buildZoneBorders(boundsFolder: Folder, zoneDef: any, openWest: boolean, openEastForBridge: boolean)
	clearGenerated(boundsFolder)
	local W = Config.World
	local t = W.BorderThickness
	local ex, ez = bubbleExtent(zoneDef)
	local o = zoneCenter(zoneDef)
	local borderH = 5
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
	local halfX, halfZ = ZoneDefs.GetOuterHalfExtent(zoneDef.Id)
	local o = zoneCenter(zoneDef)
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
	local layout = ZoneDefs.GetSummerBridgeLayout()
	local classicEdgeX = layout.ClassicEdgeX
	local midX = layout.MidX
	local span = layout.Span
	local y = layout.Y
	local pathW = layout.PathW
	local oZ = layout.Origin.Z

	local summerFolder = gameZones:FindFirstChild("SummerZone") :: Folder
	local entrance = ensureFolder(summerFolder, "Entrance")
	clearGenerated(entrance)

	-- Passerelle bois
	makePart({
		Name = "BridgeDeck",
		Size = Vector3.new(span + 2, 1.5, pathW),
		CFrame = CFrame.new(midX, y - 0.75, oZ),
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
			CFrame = CFrame.new(midX, y + 2.2, oZ + side * (pathW / 2 - 0.3)),
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
				CFrame = CFrame.new(px, y + 2, oZ + side * (pathW / 2 - 0.3)),
				Color = SUMMER.WoodDark,
				Material = Enum.Material.Wood,
				Parent = entrance,
			})
		end
	end

	-- Arche estivale à l'entrée Summer (côté ouest de Summer)
	local archX = layout.ArchX
	local archZ = layout.ArchZ
	local gap = layout.ArchGap
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
	local layout = ZoneDefs.GetSummerBridgeLayout()
	local y = layout.Y
	local pathW = layout.PathW + 4
	local gateX = layout.GateX

	local summerFolder = gameZones:FindFirstChild("SummerZone") :: Folder
	local gateFolder = ensureFolder(summerFolder, "LevelGate")
	clearGenerated(gateFolder)
	-- Supprime toute barrière résiduelle (Studio / ancien build) hors GeneratedByCode.
	for _, child in ipairs(gateFolder:GetChildren()) do
		if child.Name == "ForceFieldGate" or child.Name == "LockSymbol" then
			child:Destroy()
		end
	end

	local gate = makePart({
		Name = "ForceFieldGate",
		Size = Vector3.new(2.5, 14, pathW),
		CFrame = CFrame.new(gateX, y + 7, layout.ZoneOrigin.Z),
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
		CFrame = CFrame.new(gateX - 1.5, y + 8, layout.ZoneOrigin.Z),
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

-- Plancher thématique extérieur + référence de contour (sans props décoratifs).
local function buildDecorPerimeter(summerFolder: Folder)
	local layout = ZoneDefs.GetSummerBridgeLayout()
	local perimeter = ensureFolder(summerFolder, "DecorPerimeter")
	clearGenerated(perimeter)

	local halfX, halfZ = ZoneDefs.GetOuterHalfExtent("SummerZone")
	local o = layout.ZoneOrigin
	local thickness = 1.4
	local floorTopY = o.Y - Config.Grid.BubbleSize.Y * 0.35

	makePart({
		Name = "ZoneFloor",
		Size = Vector3.new(halfX * 2 + 4, thickness, halfZ * 2 + 4),
		CFrame = CFrame.new(o.X, floorTopY - thickness / 2, o.Z),
		Color = layout.FloorColor,
		Material = Enum.Material.Sand,
		Transparency = 0,
		CanCollide = true,
		Parent = perimeter,
	})
end

function ZoneBuilder.BuildPlayZones()
	local okPreview, SummerPreview = pcall(function()
		return require(Shared.SummerZoneEditingPreview)
	end)
	if okPreview and SummerPreview and SummerPreview.RemoveSummerZonePreview then
		SummerPreview.RemoveSummerZonePreview()
	end

	ZoneBuilder.EnsureStudioDecoration()
	local gameZones = ZoneBuilder.EnsureGameZonesRoot()

	local summerFolder = gameZones:FindFirstChild("SummerZone") :: Folder

	buildZoneBorders(ensureFolder(summerFolder, "Bounds"), ZoneDefs.SummerZone, true, false)

	local classicFolder = gameZones:FindFirstChild("ClassicZone") :: Folder
	buildZoneTrigger(ensureFolder(classicFolder, "ZoneTrigger"), ZoneDefs.ClassicZone)
	buildZoneTrigger(ensureFolder(summerFolder, "ZoneTrigger"), ZoneDefs.SummerZone)

	buildBridgeAndEntrance(gameZones)
	buildLevelGate(gameZones)
	buildDecorPerimeter(summerFolder)

	local legacyDecor = summerFolder:FindFirstChild("GeneratedDecor")
	if legacyDecor then
		legacyDecor:Destroy()
	end

	return gameZones
end

function ZoneBuilder.GetBridgeMidX(): number
	return ZoneDefs.GetSummerBridgeLayout().MidX
end

return ZoneBuilder
