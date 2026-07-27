--!strict
-- Prévisualisation Summer Zone pour édition Studio (décor manuel).
-- Play : ZoneService / ZoneBuilder appellent RemoveSummerZonePreview au démarrage.
-- Ne touche JAMAIS SummerZoneDecor.
-- Usage :
--   require(game.ReplicatedStorage.Shared.SummerZoneEditingPreview).CreateSummerZonePreview()

local RunService = game:GetService("RunService")

local SummerZoneEditingPreview = {}

local STUDIO_ROOT = "StudioDecoration"
local PREVIEW_NAME = "SummerZonePreview"
local DECOR_NAME = "SummerZoneDecor"
local MARKER_TRANSPARENCY = 0.45

local function getZoneDefs()
	return require(script.Parent.ZoneDefs)
end

local function ghostPart(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	Shape: Enum.PartType?,
}): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = if props.Transparency ~= nil then props.Transparency else MARKER_TRANSPARENCY
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	p:SetAttribute("SummerZonePreview", true)
	p:SetAttribute("StudioPreviewOnly", true)
	return p
end

function SummerZoneEditingPreview.EnsureStudioDecorationRoot(): Folder
	local existing = workspace:FindFirstChild(STUDIO_ROOT)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		warn("[SummerZoneEditingPreview] StudioDecoration existe déjà (" .. existing.ClassName .. ")")
		if existing:IsA("Model") then
			return existing :: any
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = STUDIO_ROOT
	folder.Parent = workspace
	return folder
end

-- Crée SummerZoneDecor s'il manque — ne le vide jamais.
function SummerZoneEditingPreview.EnsureSummerZoneDecor(): Folder
	local root = SummerZoneEditingPreview.EnsureStudioDecorationRoot()
	local existing = root:FindFirstChild(DECOR_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		warn("[SummerZoneEditingPreview] SummerZoneDecor n'est pas un Folder — conservation telle quelle.")
		return existing :: any
	end
	local folder = Instance.new("Folder")
	folder.Name = DECOR_NAME
	folder:SetAttribute("ManualDecor", true)
	folder.Parent = root
	return folder
end

function SummerZoneEditingPreview.RemoveSummerZonePreview()
	local root = workspace:FindFirstChild(STUDIO_ROOT)
	if root then
		local preview = root:FindFirstChild(PREVIEW_NAME)
		if preview then
			preview:Destroy()
		end
	end
	local stray = workspace:FindFirstChild(PREVIEW_NAME)
	if stray then
		stray:Destroy()
	end
end

function SummerZoneEditingPreview.CreateSummerZonePreview(): Folder?
	if RunService:IsRunning() then
		warn("[SummerZoneEditingPreview] Create/Refresh uniquement en mode Edit (pas en Play).")
		return nil
	end

	local ZoneDefs = getZoneDefs()
	local layout = ZoneDefs.GetSummerBridgeLayout()
	local o = layout.Origin
	local ex, ez = layout.Ex, layout.Ez
	local t = layout.BorderThickness
	local borderH = layout.BorderHeight
	local y = layout.Y

	SummerZoneEditingPreview.EnsureSummerZoneDecor()
	SummerZoneEditingPreview.RemoveSummerZonePreview()

	local root = SummerZoneEditingPreview.EnsureStudioDecorationRoot()
	local preview = Instance.new("Folder")
	preview.Name = PREVIEW_NAME
	preview:SetAttribute("SummerZonePreview", true)
	preview:SetAttribute("StudioPreviewOnly", true)
	preview.Parent = root

	-- Étiquette claire
	local labelHost = ghostPart({
		Name = "PREVIEW_LABEL",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(o.X, y + 18, o.Z),
		Color = Color3.fromRGB(255, 220, 80),
		Material = Enum.Material.Neon,
		Transparency = 1,
	})
	labelHost.Parent = preview
	local bb = Instance.new("BillboardGui")
	bb.Name = "PreviewBanner"
	bb.Size = UDim2.fromScale(18, 3)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = true
	bb.Parent = labelHost
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Text = "SUMMER ZONE PREVIEW (Studio only)"
	title.TextColor3 = Color3.fromRGB(255, 230, 120)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Parent = bb

	-- Plancher (emprise grille)
	ghostPart({
		Name = "Floor",
		Size = Vector3.new(ex * 2, 1.2, ez * 2),
		CFrame = CFrame.new(o.X, y - 0.6, o.Z),
		Color = layout.FloorColor,
		Transparency = 0.35,
	}).Parent = preview

	-- Emplacement BubbleBoard (volume grille)
	local halfX, halfZ = ZoneDefs.GetGridHalfExtent()
	ghostPart({
		Name = "BubbleBoardMarker",
		Size = Vector3.new(halfX * 2, 0.4, halfZ * 2),
		CFrame = CFrame.new(o.X, y + 0.2, o.Z),
		Color = Color3.fromRGB(80, 220, 230),
		Material = Enum.Material.Neon,
		Transparency = 0.65,
	}).Parent = preview

	-- Limite générale (cadre filaire bas)
	local boundsFolder = Instance.new("Folder")
	boundsFolder.Name = "Bounds"
	boundsFolder.Parent = preview

	local function wall(name: string, size: Vector3, cf: CFrame)
		ghostPart({
			Name = name,
			Size = Vector3.new(size.X, borderH, size.Z),
			CFrame = CFrame.new(cf.Position.X, y + borderH / 2, cf.Position.Z),
			Color = layout.BorderColor,
			Material = Enum.Material.Glass,
			Transparency = 0.55,
		}).Parent = boundsFolder
	end

	wall("BorderNorth", Vector3.new((ex + t) * 2, 0, t), CFrame.new(o.X, 0, o.Z + ez + t / 2))
	wall("BorderSouth", Vector3.new((ex + t) * 2, 0, t), CFrame.new(o.X, 0, o.Z - ez - t / 2))
	wall("BorderEast", Vector3.new(t, 0, (ez + t) * 2), CFrame.new(o.X + ex + t / 2, 0, o.Z))

	local bridgeGap = layout.BridgeGap
	local segLen = math.max(0, ez + t - bridgeGap / 2)
	if segLen > 0 then
		wall("BorderWestNorth", Vector3.new(t, 0, segLen),
			CFrame.new(o.X - ex - t / 2, 0, o.Z + (bridgeGap / 2 + segLen / 2)))
		wall("BorderWestSouth", Vector3.new(t, 0, segLen),
			CFrame.new(o.X - ex - t / 2, 0, o.Z - (bridgeGap / 2 + segLen / 2)))
	end

	-- Entrée / passerelle (référence visuelle, sans LevelGate actif)
	local entrance = Instance.new("Folder")
	entrance.Name = "Entrance"
	entrance.Parent = preview

	local pathW = layout.PathW
	ghostPart({
		Name = "BridgeDeck",
		Size = Vector3.new(layout.Span + 2, 1.5, pathW),
		CFrame = CFrame.new(layout.MidX, y - 0.75, o.Z),
		Color = Color3.fromRGB(160, 110, 60),
		Material = Enum.Material.WoodPlanks,
		Transparency = 0.35,
	}).Parent = entrance

	for _, side in ipairs({ -1, 1 }) do
		ghostPart({
			Name = if side < 0 then "BridgeRailLeft" else "BridgeRailRight",
			Size = Vector3.new(layout.Span, 1.2, 0.6),
			CFrame = CFrame.new(layout.MidX, y + 2.2, o.Z + side * (pathW / 2 - 0.3)),
			Color = Color3.fromRGB(180, 140, 90),
			Transparency = MARKER_TRANSPARENCY,
		}).Parent = entrance
	end

	local archX = layout.ArchX
	local archZ = layout.ArchZ
	local gap = layout.ArchGap
	for _, side in ipairs({ -1, 1 }) do
		ghostPart({
			Name = if side < 0 then "ArchPillarL" else "ArchPillarR",
			Size = Vector3.new(2, 12, 2),
			CFrame = CFrame.new(archX, y + 6, archZ + side * (gap / 2)),
			Color = Color3.fromRGB(160, 110, 60),
			Material = Enum.Material.Wood,
			Transparency = 0.35,
		}).Parent = entrance
	end
	ghostPart({
		Name = "ArchLintel",
		Size = Vector3.new(2.5, 2, gap + 4),
		CFrame = CFrame.new(archX, y + 12, archZ),
		Color = Color3.fromRGB(40, 200, 210),
		Transparency = 0.35,
	}).Parent = entrance

	-- Emplacement porte (fantôme, pas de Touched / pas de collision)
	ghostPart({
		Name = "GateMarker",
		Size = Vector3.new(2.5, 14, pathW + 4),
		CFrame = CFrame.new(layout.GateX, y + 7, o.Z),
		Color = Color3.fromRGB(255, 220, 80),
		Material = Enum.Material.ForceField,
		Transparency = 0.55,
	}).Parent = entrance

	print("[SummerZoneEditingPreview] Créé: Workspace.StudioDecoration.SummerZonePreview")
	print("[SummerZoneEditingPreview] Décor manuel: Workspace.StudioDecoration.SummerZoneDecor (jamais écrasé)")
	return preview
end

return SummerZoneEditingPreview
