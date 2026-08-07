--!strict
-- Coque visuelle Studio-first de l'ItemShop.
--
-- Le code ne décore JAMAIS la boutique : il crée une seule fois une coque
-- initiale éditable dans Workspace.StudioDecoration.ItemShopVisual, puis n'y
-- retouche plus jamais. Toute la décoration est ensuite manuelle dans Studio.
--
-- Aucune fonction de ce module ne modifie un descendant existant de
-- ItemShopVisual. CreateEditableShell() refuse d'écraser un modèle existant.
--
-- Usage barre de commande Studio (Edit, Rojo connecté) :
--   require(game.ReplicatedStorage.Shared.ItemShopVisualShell).CreateEditableShell()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)

local ItemShopVisualShell = {}

ItemShopVisualShell.MissingVisualMessage =
	"[ItemShopBuilder] ItemShopVisual missing. Using functional fallback shell."
ItemShopVisualShell.AlreadyExistsMessage =
	"ItemShopVisual already exists. No changes were made."

export type BuildMode = "Legacy" | "FunctionalOnly" | "FunctionalWithFallback"

export type ShellPartSpec = {
	Name: string,
	Path: string, -- chemin de dossiers sous ItemShopVisual, séparé par "/"
	Section: string,
	Size: Vector3,
	Offset: Vector3, -- local, relatif au pivot de la boutique
	CanCollide: boolean,
	Material: string,
	Color: Color3,
	Transparency: number?,
	Light: { Color: Color3, Brightness: number, Range: number }?,
	-- Repris tel quel par le FallbackShell quand ItemShopVisual est absent.
	Fallback: boolean?,
}

local SECTIONS = { "Structure", "Exterior", "Interior", "Displays", "Lighting" }

local PALETTE = {
	Floor = Color3.fromRGB(30, 35, 42),
	Wall = Color3.fromRGB(22, 32, 46),
	Ceiling = Color3.fromRGB(16, 23, 34),
	Facade = Color3.fromRGB(27, 42, 59),
	Sign = Color3.fromRGB(11, 21, 39),
	Podium = Color3.fromRGB(18, 24, 33),
	Light = Color3.fromRGB(255, 225, 180),
	Fallback = Color3.fromRGB(96, 100, 106),
}

--------------------------------------------------------------------
-- Configuration et pivot commun
--------------------------------------------------------------------

function ItemShopVisualShell.GetShopConfig(): typeof(Config.Lobby.ItemShop)
	return Config.Lobby.ItemShop
end

function ItemShopVisualShell.GetVisualModelName(): string
	return Config.Lobby.ItemShop.VisualModelName or "ItemShopVisual"
end

function ItemShopVisualShell.GetStudioDecorationRootName(): string
	return Config.Lobby.ItemShop.StudioDecorationRoot or "StudioDecoration"
end

function ItemShopVisualShell.GetShellVersion(): number
	return Config.Lobby.ItemShop.ShellVersion or 1
end

function ItemShopVisualShell.GetPivotPosition(): Vector3
	return Config.Lobby.ItemShopPosition
end

function ItemShopVisualShell.GetPivotYaw(): number
	return Config.Lobby.ItemShop.YawDegrees or 0
end

-- Source de vérité unique de l'alignement fonctionnel <-> visuel.
function ItemShopVisualShell.GetPivotCFrame(): CFrame
	return CFrame.new(ItemShopVisualShell.GetPivotPosition())
		* CFrame.Angles(0, math.rad(ItemShopVisualShell.GetPivotYaw()), 0)
end

--------------------------------------------------------------------
-- Logique pure des trois états (partagée avec ItemShopBuilder)
--------------------------------------------------------------------

function ItemShopVisualShell.ResolveBuildMode(useStudioVisual: boolean?, visualPresent: boolean?): BuildMode
	if useStudioVisual ~= true then
		return "Legacy"
	end
	if visualPresent == true then
		return "FunctionalOnly"
	end
	return "FunctionalWithFallback"
end

function ItemShopVisualShell.ShouldBuildLegacyDecor(mode: BuildMode): boolean
	return mode == "Legacy"
end

-- Depuis l'Étape 2, la décoration procédurale n'existe plus dans le code : le mode
-- Legacy dégrade vers le comportement Studio-first au lieu de laisser une salle vide.
function ItemShopVisualShell.ResolveEffectiveMode(useStudioVisual: boolean?, visualPresent: boolean?): BuildMode
	local mode = ItemShopVisualShell.ResolveBuildMode(useStudioVisual, visualPresent)
	if mode ~= "Legacy" then
		return mode
	end
	return if visualPresent == true then "FunctionalOnly" else "FunctionalWithFallback"
end

function ItemShopVisualShell.IsLegacyDecorRequested(useStudioVisual: boolean?): boolean
	return useStudioVisual ~= true
end

function ItemShopVisualShell.ShouldBuildFallbackShell(mode: BuildMode): boolean
	return mode == "FunctionalWithFallback"
end

--------------------------------------------------------------------
-- Spécification de la coque initiale (données pures, testables)
--------------------------------------------------------------------

function ItemShopVisualShell.GetSections(): { string }
	return table.clone(SECTIONS)
end

function ItemShopVisualShell.GetEntranceOpening(): { Width: number, Height: number, MinX: number, MaxX: number, MinY: number, MaxY: number, Z: number }
	local shop = Config.Lobby.ItemShop
	local doorWidth = shop.DoorWidth or 13
	local openingHeight = 10
	return {
		Width = doorWidth,
		Height = openingHeight,
		MinX = -doorWidth / 2,
		MaxX = doorWidth / 2,
		MinY = 1,
		MaxY = 1 + openingHeight,
		Z = (shop.Depth or 26) / 2,
	}
end

-- Centre des présentoirs, aligné sur les FocusAnchor du modèle fonctionnel.
function ItemShopVisualShell.GetDisplayCenters(): { [string]: Vector3 }
	local shop = Config.Lobby.ItemShop
	local halfW = (shop.Width or 32) / 2
	local halfD = (shop.Depth or 26) / 2
	local t = (shop.WallThickness or 1) / 2
	return {
		Skills = Vector3.new(-halfW + t + 4.1, 0, 0),
		Items = Vector3.new(0, 0, -halfD + t + 4.6),
		Cosmetics = Vector3.new(halfW - t - 4.1, 0, 0),
	}
end

function ItemShopVisualShell.GetShellSpec(): { ShellPartSpec }
	local shop = Config.Lobby.ItemShop
	local width = shop.Width or 32
	local depth = shop.Depth or 26
	local height = shop.Height or 15
	local doorWidth = shop.DoorWidth or 13
	local thickness = shop.WallThickness or 1
	local halfW, halfD = width / 2, depth / 2
	local wallHeight = height - 1 -- du dessus du plancher (y = 1) au plafond
	local wallY = 1 + wallHeight / 2
	local opening = ItemShopVisualShell.GetEntranceOpening()
	local pillarWidth = (width - doorWidth) / 2
	local lintelHeight = height - opening.Height - 1
	local centers = ItemShopVisualShell.GetDisplayCenters()

	local parts: { ShellPartSpec } = {
		{
			Name = "Floor",
			Path = "Structure",
			Section = "Structure",
			Size = Vector3.new(width, 1, depth),
			Offset = Vector3.new(0, 0.5, 0),
			CanCollide = true,
			Material = "Slate",
			Color = PALETTE.Floor,
		},
		{
			Name = "LeftWall",
			Path = "Structure",
			Section = "Structure",
			Size = Vector3.new(thickness, wallHeight, depth),
			Offset = Vector3.new(-halfW + thickness / 2, wallY, 0),
			CanCollide = true,
			Material = "SmoothPlastic",
			Color = PALETTE.Wall,
		},
		{
			Name = "BackWall",
			Path = "Structure",
			Section = "Structure",
			Size = Vector3.new(width - thickness * 2, wallHeight, thickness),
			Offset = Vector3.new(0, wallY, -halfD + thickness / 2),
			CanCollide = true,
			Material = "SmoothPlastic",
			Color = PALETTE.Wall,
		},
		{
			Name = "RightWall",
			Path = "Structure",
			Section = "Structure",
			Size = Vector3.new(thickness, wallHeight, depth),
			Offset = Vector3.new(halfW - thickness / 2, wallY, 0),
			CanCollide = true,
			Material = "SmoothPlastic",
			Color = PALETTE.Wall,
		},
		{
			Name = "Ceiling",
			Path = "Structure",
			Section = "Structure",
			Size = Vector3.new(width, 1, depth),
			Offset = Vector3.new(0, height + 0.5, 0),
			CanCollide = false,
			Material = "Metal",
			Color = PALETTE.Ceiling,
		},
		{
			Name = "FacadePillarLeft",
			Path = "Structure/FacadeBase",
			Section = "Structure",
			Size = Vector3.new(pillarWidth, wallHeight, thickness),
			Offset = Vector3.new(-(doorWidth + pillarWidth) / 2, wallY, halfD - thickness / 2),
			CanCollide = true,
			Material = "SmoothPlastic",
			Color = PALETTE.Facade,
		},
		{
			Name = "FacadePillarRight",
			Path = "Structure/FacadeBase",
			Section = "Structure",
			Size = Vector3.new(pillarWidth, wallHeight, thickness),
			Offset = Vector3.new((doorWidth + pillarWidth) / 2, wallY, halfD - thickness / 2),
			CanCollide = true,
			Material = "SmoothPlastic",
			Color = PALETTE.Facade,
		},
		{
			Name = "FacadeLintel",
			Path = "Structure/FacadeBase",
			Section = "Structure",
			Size = Vector3.new(doorWidth, lintelHeight, thickness),
			Offset = Vector3.new(0, opening.MaxY + lintelHeight / 2, halfD - thickness / 2),
			CanCollide = true,
			Material = "SmoothPlastic",
			Color = PALETTE.Facade,
		},
		{
			Name = "SignBoard",
			Path = "Exterior/ShopSign",
			Section = "Exterior",
			Size = Vector3.new(doorWidth + 1, 3, 0.6),
			Offset = Vector3.new(0, height + 2.5, halfD + 0.4),
			CanCollide = false,
			Material = "SmoothPlastic",
			Color = PALETTE.Sign,
		},
		{
			Name = "CeilingLightHost",
			Path = "Lighting",
			Section = "Lighting",
			Size = Vector3.new(3, 0.3, 3),
			Offset = Vector3.new(0, height - 0.7, -2),
			CanCollide = false,
			Material = "Neon",
			Color = PALETTE.Light,
			Transparency = 0.35,
			Light = { Color = PALETTE.Light, Brightness = 1, Range = 16 },
		},
	}

	-- Coque de secours : structure porteuse + panneau d'enseigne, rien d'autre.
	for _, part in ipairs(parts) do
		part.Fallback = part.Section == "Structure" or part.Name == "SignBoard"
	end

	-- Socles alignés exactement sur les FocusAnchor de Display_* (cadrage validé).
	for _, id in ipairs({ "Skills", "Items", "Cosmetics" }) do
		local center = centers[id]
		local diameter = if id == "Items" then 5.4 else 4.6
		table.insert(parts, {
			Name = id .. "Podium",
			Path = "Displays/" .. id .. "DisplayVisual",
			Section = "Displays",
			Size = Vector3.new(diameter, 0.7, diameter),
			Offset = Vector3.new(center.X, 1.35, center.Z),
			CanCollide = false,
			Material = "Metal",
			Color = PALETTE.Podium,
		})
	end

	return parts
end

-- Coque de secours minimale : plancher, murs, plafond, entrée ouverte, panneau SHOP.
function ItemShopVisualShell.GetFallbackSpec(): { ShellPartSpec }
	local fallback: { ShellPartSpec } = {}
	for _, part in ipairs(ItemShopVisualShell.GetShellSpec()) do
		if part.Fallback == true then
			table.insert(fallback, part)
		end
	end
	return fallback
end

function ItemShopVisualShell.GetSignText(): string
	return Config.Lobby.ItemShop.SignText or "SHOP"
end

function ItemShopVisualShell.GetAttributeSpec(): { [string]: any }
	return {
		ManualDecor = true,
		BPW_ItemShopVisual = true,
		BPW_PivotPosition = ItemShopVisualShell.GetPivotPosition(),
		BPW_PivotYaw = ItemShopVisualShell.GetPivotYaw(),
		BPW_ShellVersion = ItemShopVisualShell.GetShellVersion(),
	}
end

--------------------------------------------------------------------
-- Façade extérieure : brouillon éditable, créé une seule fois
--------------------------------------------------------------------

local EXTERIOR_FOLDER = "Exterior"
local EXTERIOR_DRAFT_NAME = "ExteriorDraft_v1"

ItemShopVisualShell.ExteriorAlreadyExistsMessage =
	"ExteriorDraft_v1 already exists. No changes were made."

export type DraftPartSpec = {
	Name: string,
	Path: string, -- chemin de modèles sous ExteriorDraft_v1, séparé par "/"
	Size: Vector3,
	Offset: Vector3, -- local, relatif au pivot de la boutique
	Rotation: Vector3?, -- degrés (X, Y, Z)
	CanCollide: boolean,
	Material: string,
	Color: Color3,
	Transparency: number?,
	Shape: string?, -- "Block" (défaut), "Cylinder", "Ball"
	Text: string?,
	TextFace: string?, -- "Back" (défaut, +Z), "Right", "Left", "Front"
	Light: { Color: Color3, Brightness: number, Range: number }?,
}

local DRAFT = {
	NavyDeep = Color3.fromRGB(5, 10, 23),
	Navy = Color3.fromRGB(11, 21, 39),
	Panel = Color3.fromRGB(27, 42, 59),
	PanelSoft = Color3.fromRGB(45, 61, 78),
	Cyan = Color3.fromRGB(42, 202, 232),
	Gold = Color3.fromRGB(245, 180, 42),
	White = Color3.fromRGB(245, 250, 255),
	Violet = Color3.fromRGB(184, 76, 232),
	Pink = Color3.fromRGB(255, 120, 200),
	GlassTint = Color3.fromRGB(105, 160, 184),
	Stone = Color3.fromRGB(34, 40, 47),
	Warm = Color3.fromRGB(255, 225, 180),
	-- Polish v1 : niveaux intermédiaires pour détacher les volumes du noir.
	Steel = Color3.fromRGB(58, 78, 100),
	WindowBack = Color3.fromRGB(36, 54, 76),
	StoneLight = Color3.fromRGB(46, 54, 66),
	SignGlow = Color3.fromRGB(206, 236, 255),
}

function ItemShopVisualShell.GetExteriorDraftName(): string
	return EXTERIOR_DRAFT_NAME
end

function ItemShopVisualShell.GetExteriorFolderName(): string
	return EXTERIOR_FOLDER
end

-- Volume à laisser entièrement libre devant l'entrée : 13 studs de large,
-- toute la hauteur utile, et 6 studs de parvis.
function ItemShopVisualShell.GetEntranceClearance(): { MinX: number, MaxX: number, MinY: number, MaxY: number, MinZ: number, MaxZ: number }
	local shop = Config.Lobby.ItemShop
	local halfDoor = (shop.DoorWidth or 13) / 2
	local front = (shop.Depth or 26) / 2
	return {
		MinX = -halfDoor,
		MaxX = halfDoor,
		-- Au-dessus des dalles plates du seuil, jusqu'au linteau.
		MinY = 1.15,
		MaxY = 10.9,
		MinZ = front,
		MaxZ = front + (shop.ForecourtDepth or 6),
	}
end

export type Bounds = {
	MinX: number,
	MaxX: number,
	MinY: number,
	MaxY: number,
	MinZ: number,
	MaxZ: number,
}

-- Demi-encombrement d'une boîte tournée : |R| appliqué aux demi-dimensions.
local function rotatedHalfExtents(size: Vector3, rotation: Vector3?): Vector3
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	if not rotation then
		return Vector3.new(hx, hy, hz)
	end
	local rx, ry, rz = math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	-- R = Rx * Ry * Rz, l'ordre utilisé par CFrame.Angles.
	local m = {
		{ cy * cz, -cy * sz, sy },
		{ sx * sy * cz + cx * sz, -sx * sy * sz + cx * cz, -sx * cy },
		{ -cx * sy * cz + sx * sz, cx * sy * sz + sx * cz, cx * cy },
	}
	return Vector3.new(
		math.abs(m[1][1]) * hx + math.abs(m[1][2]) * hy + math.abs(m[1][3]) * hz,
		math.abs(m[2][1]) * hx + math.abs(m[2][2]) * hy + math.abs(m[2][3]) * hz,
		math.abs(m[3][1]) * hx + math.abs(m[3][2]) * hy + math.abs(m[3][3]) * hz
	)
end

-- Boîte englobante locale d'une pièce du décor, rotation comprise.
function ItemShopVisualShell.GetPartBounds(part: DraftPartSpec): Bounds
	local half = rotatedHalfExtents(part.Size, part.Rotation)
	return {
		MinX = part.Offset.X - half.X,
		MaxX = part.Offset.X + half.X,
		MinY = part.Offset.Y - half.Y,
		MaxY = part.Offset.Y + half.Y,
		MinZ = part.Offset.Z - half.Z,
		MaxZ = part.Offset.Z + half.Z,
	}
end

local function overlapsZone(part: DraftPartSpec, zone: Bounds): boolean
	local b = ItemShopVisualShell.GetPartBounds(part)
	return b.MinX < zone.MaxX
		and b.MaxX > zone.MinX
		and b.MinY < zone.MaxY
		and b.MaxY > zone.MinY
		and b.MinZ < zone.MaxZ
		and b.MaxZ > zone.MinZ
end

ItemShopVisualShell.OverlapsZone = overlapsZone

-- Vrai si la pièce empiète sur le couloir d'entrée (collisionnable ou non).
function ItemShopVisualShell.IntrudesEntranceCorridor(part: DraftPartSpec): boolean
	return overlapsZone(part, ItemShopVisualShell.GetEntranceClearance() :: any)
end

-- Segment (caméra → présentoir) contre la boîte d'une pièce : méthode des dalles.
function ItemShopVisualShell.SegmentHitsPart(from: Vector3, to: Vector3, part: DraftPartSpec): boolean
	local b = ItemShopVisualShell.GetPartBounds(part)
	local origins = { from.X, from.Y, from.Z }
	local deltas = { to.X - from.X, to.Y - from.Y, to.Z - from.Z }
	local mins = { b.MinX, b.MinY, b.MinZ }
	local maxs = { b.MaxX, b.MaxY, b.MaxZ }
	local tmin, tmax = 0, 1
	for axis = 1, 3 do
		local origin, delta = origins[axis], deltas[axis]
		if math.abs(delta) < 1e-6 then
			if origin < mins[axis] or origin > maxs[axis] then
				return false
			end
		else
			local t1 = (mins[axis] - origin) / delta
			local t2 = (maxs[axis] - origin) / delta
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return false
			end
		end
	end
	return true
end

function ItemShopVisualShell.GetExteriorDraftSpec(): { DraftPartSpec }
	local shop = Config.Lobby.ItemShop
	local front = (shop.Depth or 26) / 2 -- plan extérieur de la façade existante
	local parts: { DraftPartSpec } = {}

	local function add(path: string, name: string, size: Vector3, offset: Vector3, options: {
		CanCollide: boolean?,
		Material: string?,
		Color: Color3?,
		Transparency: number?,
		Rotation: Vector3?,
		Text: string?,
		Light: { Color: Color3, Brightness: number, Range: number }?,
	}?)
		local opts = options or {}
		table.insert(parts, {
			Name = name,
			Path = path,
			Size = size,
			Offset = offset,
			Rotation = opts.Rotation,
			CanCollide = opts.CanCollide == true,
			Material = opts.Material or "SmoothPlastic",
			Color = opts.Color or DRAFT.Navy,
			Transparency = opts.Transparency,
			Text = opts.Text,
			Light = opts.Light,
		})
	end

	----------------------------------------------------------------
	-- Colonnes : deux pilastres par côté, base large et chapiteau
	----------------------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local group = "FacadeStructure/" .. (if side < 0 then "LeftColumn" else "RightColumn")
		local outer, inner = side * 14.6, side * 7.9
		add(group, "OuterPilasterBase", Vector3.new(2.8, 2.0, 2.8), Vector3.new(outer, 2.0, front + 0.9), {
			CanCollide = true, Material = "Slate", Color = DRAFT.NavyDeep,
		})
		add(group, "OuterPilasterShaft", Vector3.new(2.4, 10.4, 2.4), Vector3.new(outer, 8.2, front + 0.7), {
			CanCollide = true, Color = DRAFT.Navy,
		})
		add(group, "OuterPilasterCap", Vector3.new(3.0, 0.7, 3.0), Vector3.new(outer, 13.75, front + 0.9), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(group, "OuterPilasterTrim", Vector3.new(0.16, 8.4, 0.12), Vector3.new(outer, 8.2, front + 1.96), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.25,
		})
		add(group, "InnerPilasterBase", Vector3.new(2.7, 2.0, 2.8), Vector3.new(inner, 2.0, front + 0.9), {
			CanCollide = true, Material = "Slate", Color = DRAFT.NavyDeep,
		})
		add(group, "InnerPilasterShaft", Vector3.new(2.5, 10.4, 2.4), Vector3.new(inner, 8.2, front + 0.7), {
			CanCollide = true, Color = DRAFT.Navy,
		})
		add(group, "InnerPilasterCap", Vector3.new(3.1, 0.7, 3.0), Vector3.new(inner, 13.75, front + 0.9), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(group, "InnerPilasterTrim", Vector3.new(0.16, 8.4, 0.12), Vector3.new(inner, 8.2, front + 1.96), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.25,
		})
	end

	----------------------------------------------------------------
	-- Bandeau supérieur et corniche
	----------------------------------------------------------------
	do
		local band = "FacadeStructure/UpperBand"
		add(band, "BandLower", Vector3.new(32.0, 1.4, 2.2), Vector3.new(0, 13.9, front + 0.9), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(band, "BandMain", Vector3.new(31.0, 2.0, 2.8), Vector3.new(0, 15.6, front + 1.1), {
			Color = DRAFT.Panel,
		})
		add(band, "BandInset", Vector3.new(25.0, 1.0, 0.3), Vector3.new(0, 15.6, front + 2.3), {
			Material = "Metal", Color = DRAFT.NavyDeep,
		})
		add(band, "BandCyanTrim", Vector3.new(30.0, 0.16, 0.14), Vector3.new(0, 14.5, front + 2.06), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.3,
		})
		add(band, "Cornice", Vector3.new(33.0, 0.9, 3.4), Vector3.new(0, 17.05, front + 1.3), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(band, "CorniceGoldTrim", Vector3.new(32.4, 0.14, 0.14), Vector3.new(0, 16.55, front + 2.93), {
			Material = "Neon", Color = DRAFT.Gold, Transparency = 0.3,
		})
	end

	----------------------------------------------------------------
	-- Cadre d'entrée : montants, linteau, encadrement en retrait
	----------------------------------------------------------------
	do
		local frame = "FacadeStructure/EntranceFrame"
		for _, side in ipairs({ -1, 1 }) do
			local suffix = if side < 0 then "Left" else "Right"
			add(frame, "Jamb" .. suffix, Vector3.new(1.0, 10.0, 1.6), Vector3.new(side * 7.0, 6.0, front + 0.6), {
				CanCollide = true, Color = DRAFT.Navy,
			})
			add(frame, "RecessSide" .. suffix, Vector3.new(0.7, 10.6, 0.5), Vector3.new(side * 7.85, 6.3, front + 0.1), {
				Material = "Metal", Color = DRAFT.Panel,
			})
			add(frame, "CyanTrim" .. suffix, Vector3.new(0.14, 9.6, 0.12), Vector3.new(side * 7.42, 6.0, front + 1.42), {
				Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.25,
			})
		end
		add(frame, "Lintel", Vector3.new(15.0, 1.2, 1.8), Vector3.new(0, 11.6, front + 0.7), {
			CanCollide = true, Color = DRAFT.Navy,
		})
		add(frame, "RecessHead", Vector3.new(16.4, 0.7, 0.5), Vector3.new(0, 11.95, front + 0.1), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(frame, "CyanTrimTop", Vector3.new(14.6, 0.14, 0.12), Vector3.new(0, 11.15, front + 1.42), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.25,
		})
	end

	----------------------------------------------------------------
	-- Volumes inclinés (transitions colonnes / bandeau / enseigne)
	----------------------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local trims = "FacadeStructure/ArchitecturalTrims"
		local suffix = if side < 0 then "Left" else "Right"
		add(trims, "Shoulder" .. suffix, Vector3.new(2.6, 0.6, 2.2), Vector3.new(side * 15.2, 13.2, front + 0.9), {
			Material = "Metal", Color = DRAFT.Panel, Rotation = Vector3.new(0, 0, side * 30),
		})
		add(trims, "CorniceEnd" .. suffix, Vector3.new(2.2, 0.7, 3.2), Vector3.new(side * 15.3, 16.6, front + 1.3), {
			Material = "Metal", Color = DRAFT.Navy, Rotation = Vector3.new(0, 0, -side * 20),
		})
		add(trims, "SignWing" .. suffix, Vector3.new(2.0, 1.5, 0.5), Vector3.new(side * 9.6, 18.0, front + 2.0), {
			Material = "Metal", Color = DRAFT.Panel, Rotation = Vector3.new(0, 0, side * 32),
		})
	end

	----------------------------------------------------------------
	-- Enseigne SHOP multicouche
	----------------------------------------------------------------
	do
		local sign = "ShopSign"
		add(sign, "BackPlate", Vector3.new(18.0, 5.0, 0.8), Vector3.new(0, 19.4, front + 1.6), {
			Material = "Metal", Color = DRAFT.NavyDeep,
		})
		add(sign, "OuterFrame", Vector3.new(16.8, 4.2, 0.7), Vector3.new(0, 19.4, front + 2.2), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		local trim = "ShopSign/CyanTrim"
		add(trim, "TrimTop", Vector3.new(16.2, 0.18, 0.16), Vector3.new(0, 21.3, front + 2.62), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.2,
		})
		add(trim, "TrimBottom", Vector3.new(16.2, 0.18, 0.16), Vector3.new(0, 17.5, front + 2.62), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.2,
		})
		for _, side in ipairs({ -1, 1 }) do
			add(trim, if side < 0 then "TrimLeft" else "TrimRight",
				Vector3.new(0.18, 3.98, 0.16), Vector3.new(side * 8.01, 19.4, front + 2.62), {
					Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.2,
				})
		end
		add(sign, "InnerPanel", Vector3.new(15.6, 3.4, 0.5), Vector3.new(0, 19.4, front + 2.42), {
			Color = DRAFT.Navy,
		})
		add(sign, "TextSurface", Vector3.new(14.4, 2.6, 0.25), Vector3.new(0, 19.4, front + 2.72), {
			Material = "Metal", Color = DRAFT.NavyDeep, Text = ItemShopVisualShell.GetSignText(),
		})
		local bag = "ShopSign/BagIcon"
		add(bag, "BagBody", Vector3.new(2.6, 1.8, 0.6), Vector3.new(0, 22.3, front + 2.0), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(bag, "BagHandleTop", Vector3.new(1.6, 0.3, 0.5), Vector3.new(0, 23.55, front + 2.0), {
			Material = "Metal", Color = DRAFT.PanelSoft,
		})
		for _, side in ipairs({ -1, 1 }) do
			add(bag, if side < 0 then "BagHandleLeft" else "BagHandleRight",
				Vector3.new(0.3, 0.55, 0.5), Vector3.new(side * 0.65, 23.15, front + 2.0), {
					Material = "Metal", Color = DRAFT.PanelSoft,
				})
		end
		add(bag, "BagSymbol", Vector3.new(0.85, 0.85, 0.2), Vector3.new(0, 22.3, front + 2.35), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.2,
		})
	end

	----------------------------------------------------------------
	-- Vitrines décoratives (aucun prompt, aucune interaction)
	----------------------------------------------------------------
	local windows = {
		{
			Group = "SkillsWindow",
			Side = -1,
			Accent = DRAFT.Cyan,
			Label = "SKILLS",
			Symbol = "SkillSymbol",
		},
		{
			Group = "CosmeticsWindow",
			Side = 1,
			Accent = DRAFT.Violet,
			Label = "COSMETICS",
			Symbol = "CosmeticSymbol",
		},
	}
	for _, window in ipairs(windows) do
		local group = window.Group
		local cx = window.Side * 10.05
		add(group, "InteriorBox", Vector3.new(5.2, 6.0, 1.4), Vector3.new(cx, 7.4, front + 0.7), {
			Material = "Slate", Color = DRAFT.NavyDeep,
		})
		local frame = group .. "/Frame"
		add(frame, "FrameTop", Vector3.new(6.6, 0.7, 1.7), Vector3.new(cx, 10.75, front + 0.85), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(frame, "FrameBottom", Vector3.new(6.6, 0.7, 1.7), Vector3.new(cx, 4.05, front + 0.85), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(frame, "FrameLeft", Vector3.new(0.7, 6.0, 1.7), Vector3.new(cx - 2.95, 7.4, front + 0.85), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(frame, "FrameRight", Vector3.new(0.7, 6.0, 1.7), Vector3.new(cx + 2.95, 7.4, front + 0.85), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(group, "Glass", Vector3.new(5.2, 6.0, 0.15), Vector3.new(cx, 7.4, front + 1.45), {
			Material = "Glass", Color = DRAFT.GlassTint, Transparency = 0.6,
		})
		add(group, "Pedestal", Vector3.new(2.0, 0.7, 1.1), Vector3.new(cx, 4.75, front + 0.8), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(group .. "/AccentLighting", "LightStrip", Vector3.new(4.6, 0.18, 0.14), Vector3.new(cx, 10.2, front + 0.95), {
			Material = "Neon",
			Color = window.Accent,
			Transparency = 0.25,
			Light = { Color = window.Accent, Brightness = 0.55, Range = 9 },
		})
		local symbol = group .. "/" .. window.Symbol
		if window.Side < 0 then
			add(symbol, "BoltUpper", Vector3.new(0.5, 1.7, 0.25), Vector3.new(cx - 0.15, 7.0, front + 0.75), {
				Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.15, Rotation = Vector3.new(0, 0, 20),
			})
			add(symbol, "BoltLower", Vector3.new(0.5, 1.7, 0.25), Vector3.new(cx + 0.15, 6.0, front + 0.75), {
				Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.15, Rotation = Vector3.new(0, 0, -20),
			})
		else
			add(symbol, "CapCrown", Vector3.new(1.7, 0.9, 1.3), Vector3.new(cx, 5.6, front + 0.8), {
				Material = "Metal", Color = DRAFT.Violet,
			})
			add(symbol, "CapBrim", Vector3.new(1.9, 0.28, 1.9), Vector3.new(cx, 5.2, front + 1.1), {
				Material = "Metal", Color = DRAFT.Pink,
			})
		end
		add(group, "LabelPlate", Vector3.new(5.6, 0.9, 0.35), Vector3.new(cx, 11.65, front + 1.1), {
			Material = "Metal", Color = DRAFT.Navy, Text = window.Label,
		})
	end

	----------------------------------------------------------------
	-- Parvis, seuil et bornes latérales
	----------------------------------------------------------------
	do
		local decor = "EntranceDecor"
		add(decor, "Forecourt", Vector3.new(19.0, 0.4, 5.6), Vector3.new(0, 0.8, front + 2.9), {
			CanCollide = true, Material = "Slate", Color = DRAFT.Stone,
		})
		add(decor, "Threshold", Vector3.new(14.0, 0.3, 1.8), Vector3.new(0, 0.85, front + 0.9), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(decor, "ThresholdGlow", Vector3.new(13.0, 0.1, 0.16), Vector3.new(0, 1.03, front + 1.6), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.25,
		})
		for _, side in ipairs({ -1, 1 }) do
			local post = decor .. "/" .. (if side < 0 then "LeftPost" else "RightPost")
			add(post, "PostBase", Vector3.new(1.3, 0.4, 1.3), Vector3.new(side * 8.8, 1.2, front + 3.4), {
				Material = "Slate", Color = DRAFT.NavyDeep,
			})
			add(post, "PostBody", Vector3.new(0.85, 2.4, 0.85), Vector3.new(side * 8.8, 2.6, front + 3.4), {
				Material = "Metal", Color = DRAFT.Panel,
			})
			add(post, "PostLamp", Vector3.new(0.95, 0.4, 0.95), Vector3.new(side * 8.8, 4.0, front + 3.4), {
				Material = "Neon", Color = DRAFT.Gold, Transparency = 0.2,
			})
		end
	end

	----------------------------------------------------------------
	-- Éclairage extérieur : deux sources seulement (2 autres en vitrine)
	----------------------------------------------------------------
	do
		local lighting = "ExteriorLighting"
		add(lighting, "EntranceLightHost", Vector3.new(3.2, 0.22, 1.0), Vector3.new(0, 11.85, front + 1.9), {
			Material = "Neon",
			Color = DRAFT.Warm,
			Transparency = 0.3,
			Light = { Color = DRAFT.Warm, Brightness = 0.75, Range = 14 },
		})
		add(lighting, "SignLightHost", Vector3.new(6.0, 0.2, 0.6), Vector3.new(0, 17.75, front + 2.9), {
			Material = "Neon",
			Color = DRAFT.Gold,
			Transparency = 0.35,
			Light = { Color = DRAFT.Warm, Brightness = 0.3, Range = 9 },
		})
	end

	return parts
end

--------------------------------------------------------------------
-- Intérieur : aménagement artistique, créé une seule fois
--------------------------------------------------------------------

local INTERIOR_FOLDER = "Interior"
local INTERIOR_DRAFT_NAME = "InteriorDraft_v1"

ItemShopVisualShell.InteriorAlreadyExistsMessage =
	"InteriorDraft_v1 already exists. No changes were made."

local INSIDE = {
	Floor = Color3.fromRGB(26, 31, 40),
	FloorTileA = Color3.fromRGB(34, 42, 54),
	FloorTileB = Color3.fromRGB(29, 36, 46),
	Joint = Color3.fromRGB(62, 82, 102),
}

function ItemShopVisualShell.GetInteriorDraftName(): string
	return INTERIOR_DRAFT_NAME
end

function ItemShopVisualShell.GetInteriorFolderName(): string
	return INTERIOR_FOLDER
end

-- Couloir central : de l'entrée jusqu'au socle ITEMS, toute la hauteur utile.
function ItemShopVisualShell.GetInteriorCorridor(): Bounds
	local shop = Config.Lobby.ItemShop
	local halfDoor = (shop.DoorWidth or 13) / 2
	return {
		MinX = -halfDoor,
		MaxX = halfDoor,
		MinY = 1.28, -- au-dessus des dalles et des lignes lumineuses au sol
		MaxY = 10.9,
		MinZ = -4.5, -- devant le socle ITEMS
		MaxZ = (shop.Depth or 26) / 2,
	}
end

-- Rayons caméra → présentoir, tronqués avant la cible : mêmes valeurs que
-- ItemShopBuilder.createCameraPoint, jamais modifiées ici.
function ItemShopVisualShell.GetCameraRays(): { { Id: string, From: Vector3, To: Vector3, Target: Vector3 } }
	local centers = ItemShopVisualShell.GetDisplayCenters()
	local inward = {
		Skills = Vector3.new(1, 0, 0),
		Items = Vector3.new(0, 0, 1),
		Cosmetics = Vector3.new(-1, 0, 0),
	}
	local framing = {
		Skills = { Distance = 8.8, Height = 5.4 },
		Items = { Distance = 10, Height = 5.7 },
		Cosmetics = { Distance = 8.8, Height = 5.4 },
	}
	local rays = {}
	for _, id in ipairs({ "Skills", "Items", "Cosmetics" }) do
		local stand = centers[id]
		local from = stand + inward[id] * framing[id].Distance + Vector3.new(0, framing[id].Height, 0)
		local target = stand + Vector3.new(0, 3.3, 0)
		local delta = target - from
		local length = delta.Magnitude
		local trim = math.min(2.2, length * 0.5)
		local to = from + delta * ((length - trim) / length)
		table.insert(rays, { Id = id, From = from, To = to, Target = target })
	end
	return rays
end

function ItemShopVisualShell.GetInteriorDraftSpec(): { DraftPartSpec }
	local shop = Config.Lobby.ItemShop
	local width = shop.Width or 32
	local depth = shop.Depth or 26
	local thickness = shop.WallThickness or 1
	local wallX = width / 2 - thickness -- face intérieure des murs latéraux
	local backZ = -(depth / 2) + thickness -- face intérieure du mur du fond
	local centers = ItemShopVisualShell.GetDisplayCenters()
	local parts: { DraftPartSpec } = {}

	local function add(path: string, name: string, size: Vector3, offset: Vector3, options: {
		CanCollide: boolean?,
		Material: string?,
		Color: Color3?,
		Transparency: number?,
		Rotation: Vector3?,
		Shape: string?,
		Text: string?,
		TextFace: string?,
		Light: { Color: Color3, Brightness: number, Range: number }?,
	}?)
		local opts = options or {}
		table.insert(parts, {
			Name = name,
			Path = path,
			Size = size,
			Offset = offset,
			Rotation = opts.Rotation,
			CanCollide = opts.CanCollide == true,
			Material = opts.Material or "SmoothPlastic",
			Color = opts.Color or DRAFT.Panel,
			Transparency = opts.Transparency,
			Shape = opts.Shape,
			Text = opts.Text,
			TextFace = opts.TextFace,
			Light = opts.Light,
		})
	end

	----------------------------------------------------------------
	-- Sol : grandes dalles, joints fins, médaillon devant ITEMS
	----------------------------------------------------------------
	do
		local floor = "Floor"
		add(floor, "FloorBase", Vector3.new(30, 0.12, 24), Vector3.new(0, 1.06, 0), {
			CanCollide = true, Material = "Slate", Color = INSIDE.Floor,
		})
		add(floor, "TileNorthWest", Vector3.new(14.8, 0.1, 11.8), Vector3.new(-7.55, 1.13, -5.95), {
			Material = "Slate", Color = INSIDE.FloorTileA,
		})
		add(floor, "TileSouthEast", Vector3.new(14.8, 0.1, 11.8), Vector3.new(7.55, 1.13, 5.95), {
			Material = "Slate", Color = INSIDE.FloorTileA,
		})
		add(floor, "TileNorthEast", Vector3.new(14.8, 0.1, 11.8), Vector3.new(7.55, 1.13, -5.95), {
			Material = "Slate", Color = INSIDE.FloorTileB,
		})
		add(floor, "TileSouthWest", Vector3.new(14.8, 0.1, 11.8), Vector3.new(-7.55, 1.13, 5.95), {
			Material = "Slate", Color = INSIDE.FloorTileB,
		})
		add(floor, "JointLeft", Vector3.new(0.16, 0.08, 24), Vector3.new(-7.55, 1.17, 0), {
			Material = "Metal", Color = INSIDE.Joint,
		})
		add(floor, "JointRight", Vector3.new(0.16, 0.08, 24), Vector3.new(7.55, 1.17, 0), {
			Material = "Metal", Color = INSIDE.Joint,
		})
		add(floor, "JointBack", Vector3.new(30, 0.08, 0.16), Vector3.new(0, 1.17, -11.9), {
			Material = "Metal", Color = INSIDE.Joint,
		})
		add(floor, "JointMiddle", Vector3.new(30, 0.08, 0.16), Vector3.new(0, 1.17, 0), {
			Material = "Metal", Color = INSIDE.Joint,
		})
		add(floor, "JointFront", Vector3.new(30, 0.08, 0.16), Vector3.new(0, 1.17, 11.9), {
			Material = "Metal", Color = INSIDE.Joint,
		})
		add(floor, "MedallionRing", Vector3.new(0.1, 10.4, 10.4), Vector3.new(0, 1.19, -3.0), {
			Material = "Metal", Color = DRAFT.Panel, Shape = "Cylinder", Rotation = Vector3.new(0, 0, 90),
		})
		add(floor, "MedallionDisc", Vector3.new(0.1, 8.6, 8.6), Vector3.new(0, 1.22, -3.0), {
			Material = "Slate", Color = INSIDE.FloorTileA, Shape = "Cylinder", Rotation = Vector3.new(0, 0, 90),
		})
		add(floor, "MedallionCrossX", Vector3.new(9.6, 0.06, 0.18), Vector3.new(0, 1.25, -3.0), {
			Material = "Neon", Color = DRAFT.Gold, Transparency = 0.45,
		})
		add(floor, "MedallionCrossZ", Vector3.new(0.18, 0.06, 9.6), Vector3.new(0, 1.25, -3.0), {
			Material = "Neon", Color = DRAFT.Gold, Transparency = 0.45,
		})
		add(floor, "FloorAccentSkills", Vector3.new(0.2, 0.08, 15.0), Vector3.new(-13.6, 1.17, 0), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.4,
		})
		add(floor, "FloorAccentCosmetics", Vector3.new(0.2, 0.08, 15.0), Vector3.new(13.6, 1.17, 0), {
			Material = "Neon", Color = DRAFT.Violet, Transparency = 0.4,
		})
	end

	----------------------------------------------------------------
	-- Plafond : panneau, cadre, trois caissons, trois lignes douces
	----------------------------------------------------------------
	do
		local ceiling = "Ceiling"
		add(ceiling, "CeilingPanel", Vector3.new(28, 0.4, 22), Vector3.new(0, 14.7, 0), {
			Material = "Slate", Color = DRAFT.Navy,
		})
		add(ceiling, "FrameBack", Vector3.new(30, 0.7, 1.4), Vector3.new(0, 14.45, -11.3), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(ceiling, "FrameFront", Vector3.new(30, 0.7, 1.4), Vector3.new(0, 14.45, 11.3), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(ceiling, "FrameLeft", Vector3.new(1.4, 0.7, 22), Vector3.new(-14.3, 14.45, 0), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(ceiling, "FrameRight", Vector3.new(1.4, 0.7, 22), Vector3.new(14.3, 14.45, 0), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(ceiling, "InsetSkills", Vector3.new(6.0, 0.2, 14.0), Vector3.new(-10.5, 14.44, -1), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		add(ceiling, "InsetCosmetics", Vector3.new(6.0, 0.2, 14.0), Vector3.new(10.5, 14.44, -1), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		add(ceiling, "InsetItems", Vector3.new(14.0, 0.2, 5.0), Vector3.new(0, 14.44, -8.5), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		add(ceiling, "LineSkills", Vector3.new(0.3, 0.16, 13.0), Vector3.new(-10.5, 14.3, -1), {
			Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.35,
		})
		add(ceiling, "LineCosmetics", Vector3.new(0.3, 0.16, 13.0), Vector3.new(10.5, 14.3, -1), {
			Material = "Neon", Color = DRAFT.Violet, Transparency = 0.35,
		})
		add(ceiling, "LineItems", Vector3.new(13.0, 0.16, 0.3), Vector3.new(0, 14.3, -8.5), {
			Material = "Neon", Color = DRAFT.Gold, Transparency = 0.35,
		})
	end

	----------------------------------------------------------------
	-- Transition d'entrée : plafond clair, panneaux latéraux, lumière chaude
	----------------------------------------------------------------
	do
		local entry = "EntryTransition"
		add(entry, "EntrySoffit", Vector3.new(14.0, 0.5, 3.4), Vector3.new(0, 12.9, 10.5), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		for _, side in ipairs({ -1, 1 }) do
			local suffix = if side < 0 then "Left" else "Right"
			add(entry, "SidePanel" .. suffix, Vector3.new(2.6, 9.6, 0.5), Vector3.new(side * 7.8, 5.9, 11.7), {
				Material = "Metal", Color = DRAFT.Panel,
			})
			add(entry, "SideTrim" .. suffix, Vector3.new(0.2, 9.2, 0.2), Vector3.new(side * 6.75, 6.0, 11.35), {
				Material = "Neon", Color = DRAFT.Cyan, Transparency = 0.25,
			})
		end
		add(entry, "FloorBand", Vector3.new(12.6, 0.08, 0.5), Vector3.new(0, 1.24, 10.9), {
			Material = "Neon", Color = DRAFT.Warm, Transparency = 0.4,
		})
		add(entry, "EntryLightHost", Vector3.new(4.5, 0.3, 1.2), Vector3.new(0, 11.6, 10.4), {
			Material = "Neon",
			Color = DRAFT.Warm,
			Transparency = 0.3,
			Light = { Color = DRAFT.Warm, Brightness = 0.7, Range = 18 },
		})
	end

	----------------------------------------------------------------
	-- Murs latéraux : SKILLS à gauche, COSMETICS à droite
	----------------------------------------------------------------
	local sideSections = {
		{
			Group = "SkillsSection",
			Side = -1,
			Accent = DRAFT.Cyan,
			Title = "SKILLS",
			Face = "Right",
			Symbols = "SkillSymbols",
		},
		{
			Group = "CosmeticsSection",
			Side = 1,
			Accent = DRAFT.Violet,
			Title = "COSMETICS",
			Face = "Left",
			Symbols = "CosmeticSymbols",
		},
	}
	for _, section in ipairs(sideSections) do
		local group, side, accent = section.Group, section.Side, section.Accent
		local stand = centers[if side < 0 then "Skills" else "Cosmetics"]

		local walls = group .. "/WallPanels"
		add(walls, "PanelBase", Vector3.new(0.6, 11.0, 18.0), Vector3.new(side * (wallX - 0.3), 6.6, 0), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(walls, "PanelCap", Vector3.new(0.4, 0.8, 18.0), Vector3.new(side * (wallX - 0.4), 12.4, 0), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		for _, z in ipairs({ -4.7, 4.7 }) do
			add(walls, if z < 0 then "DividerBack" else "DividerFront",
				Vector3.new(0.5, 11.0, 0.5), Vector3.new(side * (wallX - 0.4), 6.6, z), {
					Material = "Metal", Color = DRAFT.Navy,
				})
		end

		local header = group .. "/Header"
		add(header, "HeaderPlate", Vector3.new(0.7, 2.8, 9.4), Vector3.new(side * (wallX - 0.75), 10.5, 0), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(header, "HeaderTrim", Vector3.new(0.28, 0.24, 9.6), Vector3.new(side * (wallX - 1.05), 8.95, 0), {
			Material = "Neon", Color = accent, Transparency = 0.2,
		})
		add(header, "HeaderText", Vector3.new(0.3, 2.2, 8.6), Vector3.new(side * (wallX - 1.15), 10.5, 0), {
			Material = "Metal", Color = DRAFT.NavyDeep, Text = section.Title, TextFace = section.Face,
		})

		local backdrop = group .. "/MainDisplayBackdrop"
		add(backdrop, "BackdropPanel", Vector3.new(0.5, 6.6, 7.6), Vector3.new(side * (wallX - 0.7), 4.6, 0), {
			Material = "Metal", Color = DRAFT.NavyDeep,
		})
		add(backdrop, "BackdropTop", Vector3.new(0.5, 0.4, 8.0), Vector3.new(side * (wallX - 0.8), 8.1, 0), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		for _, z in ipairs({ -3.8, 3.8 }) do
			add(backdrop, if z < 0 then "BackdropTrimBack" else "BackdropTrimFront",
				Vector3.new(0.26, 6.4, 0.22), Vector3.new(side * (wallX - 1.0), 4.6, z), {
					Material = "Neon", Color = accent, Transparency = 0.2,
				})
		end

		for _, niche in ipairs({ { Name = "LeftSecondaryDisplay", Z = 6.8 }, { Name = "RightSecondaryDisplay", Z = -6.8 } }) do
			local path = group .. "/" .. niche.Name
			add(path, "NicheBox", Vector3.new(0.5, 4.2, 3.8), Vector3.new(side * (wallX - 0.7), 4.3, niche.Z), {
				Material = "Metal", Color = DRAFT.NavyDeep,
			})
			add(path, "NicheShelf", Vector3.new(1.3, 0.35, 3.2), Vector3.new(side * (wallX - 1.2), 3.2, niche.Z), {
				Material = "Metal", Color = DRAFT.Steel,
			})
			add(path, "NicheTrim", Vector3.new(0.24, 0.2, 3.6), Vector3.new(side * (wallX - 1.1), 6.5, niche.Z), {
				Material = "Neon", Color = accent, Transparency = 0.2,
			})
		end

		local podium = group .. "/MainPodium"
		add(podium, "PodiumBase", Vector3.new(5.6, 0.8, 5.6), Vector3.new(stand.X, 1.4, stand.Z), {
			Material = "Slate", Color = DRAFT.Navy,
		})
		add(podium, "PodiumMid", Vector3.new(4.4, 0.55, 4.4), Vector3.new(stand.X, 2.075, stand.Z), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(podium, "PodiumTop", Vector3.new(3.4, 0.25, 3.4), Vector3.new(stand.X, 2.475, stand.Z), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		add(podium, "PodiumRing", Vector3.new(3.9, 0.16, 3.9), Vector3.new(stand.X, 2.4, stand.Z), {
			Material = "Neon", Color = accent, Transparency = 0.3,
		})

		local symbols = group .. "/" .. section.Symbols
		if side < 0 then
			add(symbols, "BoltLower", Vector3.new(0.38, 1.4, 0.75), Vector3.new(stand.X, 3.3, -0.25), {
				Material = "Neon", Color = accent, Transparency = 0.15, Rotation = Vector3.new(-26, 0, 0),
			})
			add(symbols, "BoltUpper", Vector3.new(0.38, 1.4, 0.75), Vector3.new(stand.X, 3.95, 0.25), {
				Material = "Neon", Color = accent, Transparency = 0.15, Rotation = Vector3.new(26, 0, 0),
			})
		else
			add(symbols, "CapCrown", Vector3.new(1.4, 1.1, 2.0), Vector3.new(stand.X, 3.6, 0), {
				Material = "Metal", Color = accent,
			})
			add(symbols, "CapBrim", Vector3.new(1.6, 0.3, 2.9), Vector3.new(stand.X, 3.0, 0.3), {
				Material = "Metal", Color = DRAFT.Pink,
			})
		end
		for _, z in ipairs({ -6.8, 6.8 }) do
			local suffix = if z < 0 then "Back" else "Front"
			if side < 0 then
				add(symbols, "Boot" .. suffix, Vector3.new(1.1, 1.3, 1.7), Vector3.new(side * (wallX - 1.25), 4.05, z), {
					Material = "Metal", Color = DRAFT.Steel,
				})
			else
				add(symbols, "Star" .. suffix, Vector3.new(1.2, 1.2, 1.6), Vector3.new(side * (wallX - 1.25), 4.05, z), {
					Material = "Metal", Color = DRAFT.Pink, Rotation = Vector3.new(45, 0, 0),
				})
			end
		end

		local lights = group .. "/AccentLights"
		add(lights, "WallGlowStrip", Vector3.new(0.2, 0.18, 16.0), Vector3.new(side * (wallX + 0.15), 2.3, 0), {
			Material = "Neon", Color = accent, Transparency = 0.4,
		})
		add(lights, "SectionLightHost", Vector3.new(2.6, 0.3, 2.6), Vector3.new(stand.X, 13.85, stand.Z), {
			Material = "Neon",
			Color = accent,
			Transparency = 0.3,
			Light = { Color = accent, Brightness = 0.5, Range = 16 },
		})
	end

	----------------------------------------------------------------
	-- Mur du fond : ITEMS, point focal de la pièce
	----------------------------------------------------------------
	do
		local group = "ItemsSection"
		local stand = centers.Items
		local accent = DRAFT.Gold

		local walls = group .. "/WallPanels"
		add(walls, "PanelBase", Vector3.new(22.0, 11.0, 0.6), Vector3.new(0, 6.6, backZ + 0.3), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(walls, "PanelCap", Vector3.new(22.0, 0.8, 0.4), Vector3.new(0, 12.4, backZ + 0.4), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		for _, x in ipairs({ -6.6, 6.6 }) do
			add(walls, if x < 0 then "DividerLeft" else "DividerRight",
				Vector3.new(0.5, 11.0, 0.5), Vector3.new(x, 6.6, backZ + 0.4), {
					Material = "Metal", Color = DRAFT.Navy,
				})
		end

		local header = group .. "/Header"
		add(header, "HeaderPlate", Vector3.new(11.4, 3.0, 0.7), Vector3.new(0, 10.6, backZ + 0.75), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(header, "HeaderTrim", Vector3.new(11.6, 0.26, 0.28), Vector3.new(0, 8.95, backZ + 1.05), {
			Material = "Neon", Color = accent, Transparency = 0.2,
		})
		add(header, "HeaderText", Vector3.new(10.4, 2.4, 0.3), Vector3.new(0, 10.6, backZ + 1.15), {
			Material = "Metal", Color = DRAFT.NavyDeep, Text = "ITEMS", TextFace = "Back",
		})

		local arch = group .. "/CentralArch"
		for _, x in ipairs({ -4.9, 4.9 }) do
			add(arch, if x < 0 then "ArchLegLeft" else "ArchLegRight",
				Vector3.new(1.3, 8.2, 1.7), Vector3.new(x, 5.1, backZ + 1.1), {
					Material = "Metal", Color = DRAFT.Navy,
				})
			add(arch, if x < 0 then "ArchCornerLeft" else "ArchCornerRight",
				Vector3.new(2.4, 0.7, 1.6), Vector3.new(x * 0.84, 8.9, backZ + 1.1), {
					Material = "Metal",
					Color = DRAFT.Steel,
					Rotation = Vector3.new(0, 0, if x < 0 then 40 else -40),
				})
		end
		add(arch, "ArchTop", Vector3.new(12.0, 1.3, 1.7), Vector3.new(0, 9.85, backZ + 1.1), {
			Material = "Metal", Color = DRAFT.Navy,
		})
		add(arch, "ArchTrim", Vector3.new(10.6, 0.26, 0.22), Vector3.new(0, 9.15, backZ + 2.0), {
			Material = "Neon", Color = accent, Transparency = 0.2,
		})

		local backdrop = group .. "/MainDisplayBackdrop"
		add(backdrop, "BackdropPanel", Vector3.new(8.6, 6.8, 0.5), Vector3.new(0, 4.6, backZ + 0.7), {
			Material = "Metal", Color = DRAFT.NavyDeep,
		})
		add(backdrop, "BackdropTop", Vector3.new(9.0, 0.4, 0.5), Vector3.new(0, 8.2, backZ + 0.8), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		for _, x in ipairs({ -4.1, 4.1 }) do
			add(backdrop, if x < 0 then "BackdropTrimLeft" else "BackdropTrimRight",
				Vector3.new(0.26, 6.6, 0.22), Vector3.new(x, 4.6, backZ + 1.0), {
					Material = "Neon", Color = accent, Transparency = 0.2,
				})
		end

		for _, niche in ipairs({ { Name = "LeftSecondaryDisplay", X = -8.9 }, { Name = "RightSecondaryDisplay", X = 8.9 } }) do
			local path = group .. "/" .. niche.Name
			add(path, "NicheBox", Vector3.new(4.2, 4.2, 0.5), Vector3.new(niche.X, 4.3, backZ + 0.65), {
				Material = "Metal", Color = DRAFT.NavyDeep,
			})
			add(path, "NicheShelf", Vector3.new(3.4, 0.35, 1.3), Vector3.new(niche.X, 3.2, backZ + 1.1), {
				Material = "Metal", Color = DRAFT.Steel,
			})
			add(path, "NicheTrim", Vector3.new(3.8, 0.2, 0.24), Vector3.new(niche.X, 6.5, backZ + 1.0), {
				Material = "Neon", Color = accent, Transparency = 0.2,
			})
		end

		local podium = group .. "/MainPodium"
		add(podium, "PodiumBase", Vector3.new(6.6, 0.9, 6.6), Vector3.new(stand.X, 1.45, stand.Z), {
			Material = "Slate", Color = DRAFT.Navy,
		})
		add(podium, "PodiumMid", Vector3.new(5.2, 0.6, 5.2), Vector3.new(stand.X, 2.2, stand.Z), {
			Material = "Metal", Color = DRAFT.Panel,
		})
		add(podium, "PodiumTop", Vector3.new(4.0, 0.3, 4.0), Vector3.new(stand.X, 2.65, stand.Z), {
			Material = "Metal", Color = DRAFT.Steel,
		})
		add(podium, "PodiumRing", Vector3.new(4.6, 0.18, 4.6), Vector3.new(stand.X, 2.55, stand.Z), {
			Material = "Neon", Color = accent, Transparency = 0.3,
		})

		local symbols = group .. "/ItemSymbols"
		add(symbols, "CrateBody", Vector3.new(2.4, 1.7, 2.0), Vector3.new(stand.X, 3.65, stand.Z), {
			Material = "Metal", Color = DRAFT.Steel, Rotation = Vector3.new(0, 18, 0),
		})
		add(symbols, "CrateLid", Vector3.new(2.7, 0.32, 2.3), Vector3.new(stand.X, 4.66, stand.Z), {
			Material = "Metal", Color = DRAFT.Panel, Rotation = Vector3.new(0, 18, 0),
		})
		add(symbols, "CrateBand", Vector3.new(2.55, 0.26, 2.15), Vector3.new(stand.X, 3.65, stand.Z), {
			Material = "Neon", Color = accent, Transparency = 0.25, Rotation = Vector3.new(0, 18, 0),
		})
		for _, x in ipairs({ -8.9, 8.9 }) do
			add(symbols, if x < 0 then "HammerLeft" else "HammerRight",
				Vector3.new(1.5, 0.75, 0.8), Vector3.new(x, 3.95, backZ + 1.1), {
					Material = "Metal", Color = DRAFT.Steel,
				})
		end

		local lights = group .. "/AccentLights"
		add(lights, "WallGlowStrip", Vector3.new(20.0, 0.18, 0.2), Vector3.new(0, 2.3, backZ + 0.15), {
			Material = "Neon", Color = accent, Transparency = 0.4,
		})
		add(lights, "SectionLightHost", Vector3.new(3.0, 0.3, 3.0), Vector3.new(stand.X, 13.85, stand.Z), {
			Material = "Neon",
			Color = accent,
			Transparency = 0.3,
			Light = { Color = accent, Brightness = 0.6, Range = 18 },
		})
	end

	----------------------------------------------------------------
	-- Décor central : deux banquettes, hors des axes de caméra
	----------------------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local bench = "CentralDecor/" .. (if side < 0 then "LeftBench" else "RightBench")
		add(bench, "BenchBase", Vector3.new(4.4, 0.85, 1.3), Vector3.new(side * 10.6, 1.6, 7.4), {
			CanCollide = true, Material = "Metal", Color = DRAFT.Navy,
		})
		add(bench, "BenchSeat", Vector3.new(5.0, 0.45, 1.9), Vector3.new(side * 10.6, 2.25, 7.4), {
			CanCollide = true, Material = "Metal", Color = DRAFT.Panel,
		})
	end

	----------------------------------------------------------------
	-- Éclairage général : deux plafonniers blanc chaud
	----------------------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		add("InteriorLighting", if side < 0 then "MainLightHostLeft" else "MainLightHostRight",
			Vector3.new(3.6, 0.28, 3.6), Vector3.new(side * 6.5, 14.3, 3.0), {
				Material = "Neon",
				Color = DRAFT.Warm,
				Transparency = 0.35,
				Light = { Color = DRAFT.Warm, Brightness = 0.75, Range = 24 },
			})
	end

	return parts
end

--------------------------------------------------------------------
-- Polish v1 de la façade : retouches ciblées + ajouts limités
--------------------------------------------------------------------

ItemShopVisualShell.ExteriorPolishVersion = 1
ItemShopVisualShell.ExteriorMissingMessage =
	"ExteriorDraft_v1 not found. No changes were made."
ItemShopVisualShell.ExteriorPolishAppliedMessage =
	"Exterior polish version 1 is already applied. No changes were made."

export type DraftPartUpdate = {
	Path: string,
	Name: string,
	Size: Vector3?,
	Offset: Vector3?,
	Color: Color3?,
	Material: string?,
	Transparency: number?,
	Light: { Color: Color3, Brightness: number, Range: number }?,
}

export type ExteriorPolishSpec = {
	Version: number,
	Updates: { DraftPartUpdate },
	Additions: { DraftPartSpec },
}

function ItemShopVisualShell.GetExteriorPolishSpec(): ExteriorPolishSpec
	local shop = Config.Lobby.ItemShop
	local front = (shop.Depth or 26) / 2
	local updates: { DraftPartUpdate } = {}
	local additions: { DraftPartSpec } = {}

	local function set(path: string, name: string, fields: {
		Size: Vector3?,
		Offset: Vector3?,
		Color: Color3?,
		Material: string?,
		Transparency: number?,
		Light: { Color: Color3, Brightness: number, Range: number }?,
	})
		table.insert(updates, {
			Path = path,
			Name = name,
			Size = fields.Size,
			Offset = fields.Offset,
			Color = fields.Color,
			Material = fields.Material,
			Transparency = fields.Transparency,
			Light = fields.Light,
		})
	end

	local function add(path: string, name: string, size: Vector3, offset: Vector3, options: {
		Material: string?,
		Color: Color3?,
		Transparency: number?,
	}?)
		local opts = options or {}
		table.insert(additions, {
			Name = name,
			Path = path,
			Size = size,
			Offset = offset,
			Rotation = nil,
			CanCollide = false,
			Material = opts.Material or "Metal",
			Color = opts.Color or DRAFT.Steel,
			Transparency = opts.Transparency,
			Text = nil,
			Light = nil,
		})
	end

	----------------------------------------------------------------
	-- Colonnes : trois niveaux de valeur distincts + bandeau doré
	----------------------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local group = "FacadeStructure/" .. (if side < 0 then "LeftColumn" else "RightColumn")
		local outer, inner = side * 14.6, side * 7.9
		set(group, "OuterPilasterShaft", { Color = DRAFT.Panel })
		set(group, "OuterPilasterCap", { Color = DRAFT.Steel })
		set(group, "OuterPilasterTrim", {
			Size = Vector3.new(0.24, 8.6, 0.16),
			Transparency = 0.1,
		})
		set(group, "InnerPilasterShaft", { Color = DRAFT.Panel })
		set(group, "InnerPilasterCap", { Color = DRAFT.Steel })
		set(group, "InnerPilasterTrim", {
			Size = Vector3.new(0.24, 8.6, 0.16),
			Transparency = 0.1,
		})
		add(group, "OuterGoldBand", Vector3.new(3.1, 0.24, 0.22), Vector3.new(outer, 3.16, front + 2.28), {
			Material = "Neon", Color = DRAFT.Gold, Transparency = 0.2,
		})
		add(group, "InnerGoldBand", Vector3.new(2.7, 0.24, 0.22), Vector3.new(inner, 3.16, front + 2.28), {
			Material = "Neon", Color = DRAFT.Gold, Transparency = 0.2,
		})
	end

	----------------------------------------------------------------
	-- Bandeau et corniche : chaque couche a sa propre valeur
	----------------------------------------------------------------
	do
		local band = "FacadeStructure/UpperBand"
		set(band, "BandLower", { Color = DRAFT.Panel })
		set(band, "BandMain", { Color = DRAFT.Steel })
		set(band, "BandInset", { Color = DRAFT.Navy })
		set(band, "BandCyanTrim", {
			Size = Vector3.new(30.4, 0.3, 0.22),
			Offset = Vector3.new(0, 14.45, front + 2.1),
			Transparency = 0.15,
		})
		set(band, "Cornice", { Color = DRAFT.PanelSoft })
		set(band, "CorniceGoldTrim", {
			Size = Vector3.new(32.4, 0.3, 0.26),
			Offset = Vector3.new(0, 16.5, front + 2.95),
			Transparency = 0.15,
		})
	end

	----------------------------------------------------------------
	-- Entrée : plus claire, mieux cadrée, jamais obstruée
	----------------------------------------------------------------
	do
		local frame = "FacadeStructure/EntranceFrame"
		set(frame, "Lintel", { Color = DRAFT.Panel })
		set(frame, "RecessHead", { Color = DRAFT.Steel })
		set(frame, "CyanTrimTop", {
			Size = Vector3.new(14.9, 0.26, 0.2),
			Offset = Vector3.new(0, 11.2, front + 1.45),
			Transparency = 0.1,
		})
		for _, side in ipairs({ -1, 1 }) do
			local suffix = if side < 0 then "Left" else "Right"
			set(frame, "Jamb" .. suffix, { Color = DRAFT.Panel })
			set(frame, "RecessSide" .. suffix, { Color = DRAFT.Steel })
			set(frame, "CyanTrim" .. suffix, {
				Size = Vector3.new(0.26, 9.8, 0.2),
				Offset = Vector3.new(side * 7.35, 6.0, front + 1.45),
				Transparency = 0.1,
			})
			-- Tableau intérieur clair : visible depuis le parvis, en retrait du plan
			-- de façade, aligné exactement sur le bord de l'ouverture.
			add(frame, "RevealPanel" .. suffix, Vector3.new(0.3, 9.6, 1.4), Vector3.new(side * 6.65, 5.9, 11.7), {
				Color = DRAFT.Steel,
			})
			add(frame, "GoldTrim" .. suffix, Vector3.new(0.22, 9.6, 0.2), Vector3.new(side * 7.62, 6.0, front + 1.4), {
				Material = "Neon", Color = DRAFT.Gold, Transparency = 0.2,
			})
		end
		-- Plafond d'entrée clair, calé sous le linteau, hors du gabarit de passage.
		add(frame, "EntranceSoffit", Vector3.new(13.0, 0.3, 1.7), Vector3.new(0, 11.05, front + 0.6), {
			Color = DRAFT.Steel,
		})
	end

	----------------------------------------------------------------
	-- Volumes inclinés : plus lisibles, recalés sur la nouvelle enseigne
	----------------------------------------------------------------
	for _, side in ipairs({ -1, 1 }) do
		local trims = "FacadeStructure/ArchitecturalTrims"
		local suffix = if side < 0 then "Left" else "Right"
		set(trims, "Shoulder" .. suffix, {
			Size = Vector3.new(3.0, 0.7, 2.4),
			Offset = Vector3.new(side * 15.0, 13.2, front + 0.9),
			Color = DRAFT.Steel,
		})
		set(trims, "CorniceEnd" .. suffix, { Color = DRAFT.PanelSoft })
		set(trims, "SignWing" .. suffix, {
			Size = Vector3.new(2.4, 1.8, 0.6),
			Offset = Vector3.new(side * 12.2, 18.4, front + 3.0),
			Color = DRAFT.Steel,
		})
	end

	----------------------------------------------------------------
	-- Enseigne : plus large, plus haute, descendue vers la corniche
	----------------------------------------------------------------
	do
		local sign = "ShopSign"
		set(sign, "BackPlate", {
			Size = Vector3.new(22.5, 6.0, 0.9),
			Offset = Vector3.new(0, 19.0, front + 3.3),
			Color = DRAFT.Navy,
		})
		set(sign, "OuterFrame", {
			Size = Vector3.new(21.0, 5.1, 0.8),
			Offset = Vector3.new(0, 19.0, front + 3.9),
			Color = DRAFT.Steel,
		})
		local trim = "ShopSign/CyanTrim"
		set(trim, "TrimTop", {
			Size = Vector3.new(20.2, 0.3, 0.2),
			Offset = Vector3.new(0, 21.05, front + 4.4),
			Transparency = 0.1,
		})
		set(trim, "TrimBottom", {
			Size = Vector3.new(20.2, 0.3, 0.2),
			Offset = Vector3.new(0, 16.95, front + 4.4),
			Transparency = 0.1,
		})
		for _, side in ipairs({ -1, 1 }) do
			set(trim, if side < 0 then "TrimLeft" else "TrimRight", {
				Size = Vector3.new(0.3, 4.4, 0.2),
				Offset = Vector3.new(side * 9.95, 19.0, front + 4.4),
				Transparency = 0.1,
			})
		end
		set(sign, "InnerPanel", {
			Size = Vector3.new(19.6, 4.2, 0.6),
			Offset = Vector3.new(0, 19.0, front + 4.12),
			Color = DRAFT.Panel,
		})
		set(sign, "TextSurface", {
			Size = Vector3.new(18.4, 3.4, 0.3),
			Offset = Vector3.new(0, 19.0, front + 4.45),
			Color = DRAFT.Navy,
		})
		local bag = "ShopSign/BagIcon"
		set(bag, "BagBody", {
			Size = Vector3.new(3.6, 2.2, 0.7),
			Offset = Vector3.new(0, 22.5, front + 3.6),
			Color = DRAFT.Steel,
		})
		set(bag, "BagHandleTop", {
			Size = Vector3.new(1.9, 0.3, 0.6),
			Offset = Vector3.new(0, 24.0, front + 3.6),
		})
		for _, side in ipairs({ -1, 1 }) do
			set(bag, if side < 0 then "BagHandleLeft" else "BagHandleRight", {
				Size = Vector3.new(0.32, 0.55, 0.6),
				Offset = Vector3.new(side * 0.79, 23.6, front + 3.6),
			})
		end
		set(bag, "BagSymbol", {
			Size = Vector3.new(1.1, 1.1, 0.25),
			Offset = Vector3.new(0, 22.4, front + 4.05),
			Transparency = 0.1,
		})
	end

	----------------------------------------------------------------
	-- Vitrines : plus ouvertes, fond plus clair, produit plus grand
	----------------------------------------------------------------
	local windows = {
		{ Group = "SkillsWindow", Side = -1, Accent = DRAFT.Cyan, Symbol = "SkillSymbol" },
		{ Group = "CosmeticsWindow", Side = 1, Accent = DRAFT.Violet, Symbol = "CosmeticSymbol" },
	}
	for _, window in ipairs(windows) do
		local group = window.Group
		local cx = window.Side * 10.05
		set(group, "InteriorBox", {
			Size = Vector3.new(5.7, 6.8, 1.6),
			Offset = Vector3.new(cx, 7.4, front + 0.6),
			Color = DRAFT.WindowBack,
		})
		local frame = group .. "/Frame"
		set(frame, "FrameTop", {
			Size = Vector3.new(6.7, 0.5, 1.8),
			Offset = Vector3.new(cx, 11.05, front + 0.9),
			Color = DRAFT.Panel,
		})
		set(frame, "FrameBottom", {
			Size = Vector3.new(6.7, 0.5, 1.8),
			Offset = Vector3.new(cx, 3.75, front + 0.9),
			Color = DRAFT.Panel,
		})
		set(frame, "FrameLeft", {
			Size = Vector3.new(0.5, 6.8, 1.8),
			Offset = Vector3.new(cx - 3.1, 7.4, front + 0.9),
			Color = DRAFT.Panel,
		})
		set(frame, "FrameRight", {
			Size = Vector3.new(0.5, 6.8, 1.8),
			Offset = Vector3.new(cx + 3.1, 7.4, front + 0.9),
			Color = DRAFT.Panel,
		})
		set(group, "Glass", {
			Size = Vector3.new(5.7, 6.8, 0.15),
			Offset = Vector3.new(cx, 7.4, front + 1.5),
			Transparency = 0.68,
		})
		set(group, "Pedestal", {
			Size = Vector3.new(2.6, 0.8, 1.3),
			Offset = Vector3.new(cx, 4.4, front + 0.7),
			Color = DRAFT.PanelSoft,
		})
		set(group .. "/AccentLighting", "LightStrip", {
			Size = Vector3.new(5.4, 0.22, 0.16),
			Offset = Vector3.new(cx, 10.55, front + 0.8),
			Transparency = 0.12,
			Light = { Color = window.Accent, Brightness = 0.5, Range = 9 },
		})
		set(group, "LabelPlate", {
			Size = Vector3.new(6.4, 1.0, 0.4),
			Offset = Vector3.new(cx, 11.9, front + 1.15),
			Color = DRAFT.Panel,
		})

		local symbol = group .. "/" .. window.Symbol
		if window.Side < 0 then
			set(symbol, "BoltUpper", {
				Size = Vector3.new(0.68, 2.3, 0.34),
				Offset = Vector3.new(cx - 0.2, 7.5, front + 0.75),
			})
			set(symbol, "BoltLower", {
				Size = Vector3.new(0.68, 2.3, 0.34),
				Offset = Vector3.new(cx + 0.2, 6.15, front + 0.75),
			})
		else
			set(symbol, "CapCrown", {
				Size = Vector3.new(2.3, 1.2, 1.3),
				Offset = Vector3.new(cx, 5.45, front + 0.7),
			})
			set(symbol, "CapBrim", {
				Size = Vector3.new(2.6, 0.35, 1.3),
				Offset = Vector3.new(cx, 4.95, front + 0.75),
			})
		end

		-- Contour d'accent autour du cadre, plus épais que les filets d'origine.
		add(frame, "OutlineTop", Vector3.new(6.66, 0.26, 0.2), Vector3.new(cx, 11.35, front + 1.85), {
			Material = "Neon", Color = window.Accent, Transparency = 0.15,
		})
		add(frame, "OutlineBottom", Vector3.new(6.66, 0.26, 0.2), Vector3.new(cx, 3.45, front + 1.85), {
			Material = "Neon", Color = window.Accent, Transparency = 0.15,
		})
		add(frame, "OutlineLeft", Vector3.new(0.26, 8.0, 0.2), Vector3.new(cx - 3.2, 7.4, front + 1.85), {
			Material = "Neon", Color = window.Accent, Transparency = 0.15,
		})
		add(frame, "OutlineRight", Vector3.new(0.26, 8.0, 0.2), Vector3.new(cx + 3.2, 7.4, front + 1.85), {
			Material = "Neon", Color = window.Accent, Transparency = 0.15,
		})
		add(group .. "/AccentLighting", "PedestalGlow", Vector3.new(2.4, 0.12, 1.2), Vector3.new(cx, 4.86, front + 0.7), {
			Material = "Neon", Color = window.Accent, Transparency = 0.3,
		})
	end

	----------------------------------------------------------------
	-- Parvis : dalles plus claires, seuil plus lisible
	----------------------------------------------------------------
	do
		local decor = "EntranceDecor"
		set(decor, "Forecourt", { Color = DRAFT.StoneLight })
		set(decor, "Threshold", { Color = DRAFT.Steel })
		set(decor, "ThresholdGlow", {
			Size = Vector3.new(13.0, 0.14, 0.3),
			Offset = Vector3.new(0, 1.04, front + 1.6),
			Transparency = 0.15,
		})
		for _, side in ipairs({ -1, 1 }) do
			local post = decor .. "/" .. (if side < 0 then "LeftPost" else "RightPost")
			set(post, "PostBase", { Color = DRAFT.Navy })
			set(post, "PostBody", { Color = DRAFT.Steel })
			set(post, "PostLamp", {
				Size = Vector3.new(1.05, 0.4, 1.05),
				Transparency = 0.1,
			})
		end
		-- Nappe chaude posée sur le plancher juste à l'intérieur du seuil.
		add(decor, "EntranceFloorGlow", Vector3.new(13.0, 0.12, 2.0), Vector3.new(0, 1.03, 11.6), {
			Material = "Neon", Color = DRAFT.Warm, Transparency = 0.25,
		})
	end

	----------------------------------------------------------------
	-- Éclairage : toujours quatre sources, plus douces et mieux placées
	----------------------------------------------------------------
	do
		local lighting = "ExteriorLighting"
		set(lighting, "EntranceLightHost", {
			Size = Vector3.new(4.6, 0.28, 1.1),
			Offset = Vector3.new(0, 11.85, front + 1.9),
			Light = { Color = DRAFT.Warm, Brightness = 0.9, Range = 15 },
		})
		set(lighting, "SignLightHost", {
			Size = Vector3.new(10.0, 0.24, 0.7),
			Offset = Vector3.new(0, 15.72, front + 3.5),
			Color = DRAFT.SignGlow,
			Transparency = 0.25,
			Light = { Color = DRAFT.SignGlow, Brightness = 0.45, Range = 11 },
		})
	end

	return { Version = 1, Updates = updates, Additions = additions }
end

-- Façade telle qu'elle sera après application du polish : sert aux tests.
function ItemShopVisualShell.GetPolishedExteriorSpec(): { DraftPartSpec }
	local polish = ItemShopVisualShell.GetExteriorPolishSpec()
	local byKey: { [string]: DraftPartSpec } = {}
	local parts: { DraftPartSpec } = {}

	for _, part in ipairs(ItemShopVisualShell.GetExteriorDraftSpec()) do
		local copy: DraftPartSpec = {
			Name = part.Name,
			Path = part.Path,
			Size = part.Size,
			Offset = part.Offset,
			Rotation = part.Rotation,
			CanCollide = part.CanCollide,
			Material = part.Material,
			Color = part.Color,
			Transparency = part.Transparency,
			Text = part.Text,
			Light = part.Light,
		}
		byKey[part.Path .. "/" .. part.Name] = copy
		table.insert(parts, copy)
	end

	for _, update in ipairs(polish.Updates) do
		local target = byKey[update.Path .. "/" .. update.Name]
		if target then
			target.Size = update.Size or target.Size
			target.Offset = update.Offset or target.Offset
			target.Color = update.Color or target.Color
			target.Material = update.Material or target.Material
			target.Transparency = update.Transparency or target.Transparency
			target.Light = update.Light or target.Light
		end
	end

	for _, addition in ipairs(polish.Additions) do
		table.insert(parts, addition)
	end

	return parts
end

-- Vrai si la retouche vise une pièce réellement présente dans le brouillon.
function ItemShopVisualShell.HasDraftPart(path: string, name: string): boolean
	for _, part in ipairs(ItemShopVisualShell.GetExteriorDraftSpec()) do
		if part.Path == path and part.Name == name then
			return true
		end
	end
	return false
end

-- Un élément collisionnable ne doit jamais empiéter sur l'ouverture d'entrée.
function ItemShopVisualShell.BlocksEntrance(part: ShellPartSpec): boolean
	if not part.CanCollide then
		return false
	end
	local opening = ItemShopVisualShell.GetEntranceOpening()
	local halfX, halfY = part.Size.X / 2, part.Size.Y / 2
	local overlapsX = (part.Offset.X - halfX) < opening.MaxX and (part.Offset.X + halfX) > opening.MinX
	local overlapsY = (part.Offset.Y - halfY) < opening.MaxY and (part.Offset.Y + halfY) > opening.MinY
	local halfZ = part.Size.Z / 2
	local overlapsZ = (part.Offset.Z - halfZ) <= opening.Z and (part.Offset.Z + halfZ) >= opening.Z
	return overlapsX and overlapsY and overlapsZ
end

--------------------------------------------------------------------
-- Accès Workspace (lecture seule sur le décor manuel)
--------------------------------------------------------------------

function ItemShopVisualShell.FindStudioDecorationRoot(): Instance?
	return Workspace:FindFirstChild(ItemShopVisualShell.GetStudioDecorationRootName())
end

-- Lecture seule : aucun appelant ne doit écrire dans le modèle retourné.
function ItemShopVisualShell.FindVisualModel(): Instance?
	local root = ItemShopVisualShell.FindStudioDecorationRoot()
	if not root then
		return nil
	end
	return root:FindFirstChild(ItemShopVisualShell.GetVisualModelName())
end

function ItemShopVisualShell.IsVisualPresent(): boolean
	return ItemShopVisualShell.FindVisualModel() ~= nil
end

-- Vrai pour StudioDecoration et tous ses descendants : zone intouchable par le code.
function ItemShopVisualShell.IsProtectedInstance(instance: Instance?): boolean
	if not instance then
		return false
	end
	local target = instance :: Instance
	if target:GetAttribute("ManualDecor") == true or target:GetAttribute("BPW_ItemShopVisual") == true then
		return true
	end
	local root = ItemShopVisualShell.FindStudioDecorationRoot()
	if not root then
		return false
	end
	return target == root or target:IsDescendantOf(root)
end

function ItemShopVisualShell.EnsureStudioDecorationRoot(): Instance
	local existing = ItemShopVisualShell.FindStudioDecorationRoot()
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = ItemShopVisualShell.GetStudioDecorationRootName()
	folder.Parent = Workspace
	return folder
end

--------------------------------------------------------------------
-- Création de la coque éditable (Studio Edit uniquement, une seule fois)
--------------------------------------------------------------------

local MATERIALS: { [string]: Enum.Material }? = nil

local function resolveMaterial(name: string): Enum.Material
	if not MATERIALS then
		MATERIALS = {
			Slate = Enum.Material.Slate,
			SmoothPlastic = Enum.Material.SmoothPlastic,
			Metal = Enum.Material.Metal,
			Neon = Enum.Material.Neon,
			Glass = Enum.Material.Glass,
		}
	end
	return (MATERIALS :: any)[name] or Enum.Material.SmoothPlastic
end

local function ensureFolderPath(root: Instance, path: string): Instance
	local parent = root
	for segment in string.gmatch(path, "[^/]+") do
		local child = parent:FindFirstChild(segment)
		if not child then
			local folder = Instance.new("Folder")
			folder.Name = segment
			folder.Parent = parent
			child = folder
		end
		parent = child
	end
	return parent
end

function ItemShopVisualShell.CreateEditableShell(): Model?
	if RunService:IsRunning() then
		warn("[ItemShopVisualShell] Create ItemShop Editable Shell : mode Edit uniquement (pas en Play).")
		return nil
	end

	if ItemShopVisualShell.FindVisualModel() then
		warn("[ItemShopVisualShell] " .. ItemShopVisualShell.AlreadyExistsMessage)
		print("[ItemShopVisualShell] " .. ItemShopVisualShell.AlreadyExistsMessage)
		return nil
	end

	local root = ItemShopVisualShell.EnsureStudioDecorationRoot()
	local pivotCF = ItemShopVisualShell.GetPivotCFrame()

	local model = Instance.new("Model")
	model.Name = ItemShopVisualShell.GetVisualModelName()

	for _, section in ipairs(SECTIONS) do
		local folder = Instance.new("Folder")
		folder.Name = section
		folder.Parent = model
	end

	-- Référence d'alignement : GetPivot() du modèle == pivot de configuration.
	local pivotAnchor = Instance.new("Part")
	pivotAnchor.Name = "PivotAnchor"
	pivotAnchor.Size = Vector3.new(1, 1, 1)
	pivotAnchor.CFrame = pivotCF
	pivotAnchor.Anchored = true
	pivotAnchor.CanCollide = false
	pivotAnchor.CanTouch = false
	pivotAnchor.CanQuery = false
	pivotAnchor.CastShadow = false
	pivotAnchor.Transparency = 1
	pivotAnchor.Parent = model
	model.PrimaryPart = pivotAnchor

	for _, spec in ipairs(ItemShopVisualShell.GetShellSpec()) do
		local part = Instance.new("Part")
		part.Name = spec.Name
		part.Size = spec.Size
		part.CFrame = pivotCF * CFrame.new(spec.Offset)
		part.Color = spec.Color
		part.Material = resolveMaterial(spec.Material)
		part.Transparency = spec.Transparency or 0
		part.Anchored = true
		part.CanCollide = spec.CanCollide
		part.CanTouch = false
		part.CanQuery = spec.CanCollide
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = ensureFolderPath(model, spec.Path)
		if spec.Light then
			local light = Instance.new("PointLight")
			light.Name = "Light"
			light.Color = spec.Light.Color
			light.Brightness = spec.Light.Brightness
			light.Range = spec.Light.Range
			light.Shadows = false
			light.Parent = part
		end
	end

	for name, value in pairs(ItemShopVisualShell.GetAttributeSpec()) do
		model:SetAttribute(name, value)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = root

	print(
		string.format(
			"[ItemShopVisualShell] Créé: Workspace.%s.%s (pivot %s, yaw %d°)",
			ItemShopVisualShell.GetStudioDecorationRootName(),
			ItemShopVisualShell.GetVisualModelName(),
			tostring(ItemShopVisualShell.GetPivotPosition()),
			ItemShopVisualShell.GetPivotYaw()
		)
	)
	print("[ItemShopVisualShell] Décore librement ce modèle dans Studio, puis sauvegarde la place.")
	print("[ItemShopVisualShell] Le code ne le supprime, ne le vide et ne le reconstruit jamais.")
	return model
end

--------------------------------------------------------------------
-- Façade extérieure : commande Studio, une seule fois
--------------------------------------------------------------------

local function ensureModelPath(root: Instance, path: string): Instance
	local parent = root
	for segment in string.gmatch(path, "[^/]+") do
		local child = parent:FindFirstChild(segment)
		if not child then
			local model = Instance.new("Model")
			model.Name = segment
			model.Parent = parent
			child = model
		end
		parent = child
	end
	return parent
end

local SHAPES: { [string]: EnumItem } = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}

local TEXT_FACES: { [string]: EnumItem } = {
	Back = Enum.NormalId.Back,
	Front = Enum.NormalId.Front,
	Right = Enum.NormalId.Right,
	Left = Enum.NormalId.Left,
}

local function addSignSurface(host: BasePart, text: string, face: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "TextGui"
	gui.Face = TEXT_FACES[face or "Back"] or Enum.NormalId.Back -- +Z local par défaut
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1.1
	gui.Parent = host

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -6, 1, -6)
	label.Position = UDim2.new(0, 3, 0, 3)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = DRAFT.White
	label.Text = text
	label.Parent = gui
end

local function draftPartCFrame(spec: DraftPartSpec, pivotCF: CFrame): CFrame
	local cf = pivotCF * CFrame.new(spec.Offset)
	if spec.Rotation then
		cf *= CFrame.Angles(
			math.rad(spec.Rotation.X),
			math.rad(spec.Rotation.Y),
			math.rad(spec.Rotation.Z)
		)
	end
	return cf
end

local function spawnDraftPart(draft: Instance, spec: DraftPartSpec, pivotCF: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = spec.Name
	part.Size = spec.Size
	part.CFrame = draftPartCFrame(spec, pivotCF)
	part.Color = spec.Color
	part.Material = resolveMaterial(spec.Material)
	part.Transparency = spec.Transparency or 0
	part.Anchored = true
	part.CanCollide = spec.CanCollide
	part.CanTouch = false
	part.CanQuery = spec.CanCollide
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.Shape then
		part.Shape = (SHAPES[spec.Shape] or Enum.PartType.Block) :: any
	end
	part.Parent = ensureModelPath(draft, spec.Path)

	if spec.Text then
		addSignSurface(part, spec.Text, spec.TextFace)
	end
	if spec.Light then
		local light = Instance.new("PointLight")
		light.Name = "Light"
		light.Color = spec.Light.Color
		light.Brightness = spec.Light.Brightness
		light.Range = spec.Light.Range
		light.Shadows = false
		light.Parent = part
	end
	return part
end

-- Studio Edit uniquement. Ne touche jamais Workspace.ItemShop ni les guides
-- fonctionnels, et n'écrase jamais une façade déjà présente.
function ItemShopVisualShell.CreateExteriorDraft(): Model?
	if RunService:IsRunning() then
		warn("[ItemShopVisualShell] Create ItemShop Exterior Draft : mode Edit uniquement (pas en Play).")
		return nil
	end

	local visual = ItemShopVisualShell.FindVisualModel()
	if not visual then
		warn(
			"[ItemShopVisualShell] ItemShopVisual introuvable — lance d'abord Create ItemShop Editable Shell."
		)
		return nil
	end

	local exterior = visual:FindFirstChild(EXTERIOR_FOLDER)
	if not exterior then
		local folder = Instance.new("Folder")
		folder.Name = EXTERIOR_FOLDER
		folder.Parent = visual
		exterior = folder
	end

	if exterior:FindFirstChild(EXTERIOR_DRAFT_NAME) then
		warn("[ItemShopVisualShell] " .. ItemShopVisualShell.ExteriorAlreadyExistsMessage)
		print("[ItemShopVisualShell] " .. ItemShopVisualShell.ExteriorAlreadyExistsMessage)
		print("[ItemShopVisualShell] Supprime " .. EXTERIOR_DRAFT_NAME .. " à la main pour repartir de zéro.")
		return nil
	end

	local pivotCF = ItemShopVisualShell.GetPivotCFrame()
	local draft = Instance.new("Model")
	draft.Name = EXTERIOR_DRAFT_NAME
	draft:SetAttribute("ManualDecor", true)
	draft:SetAttribute("BPW_ExteriorDraft", true)
	draft:SetAttribute("BPW_PivotPosition", ItemShopVisualShell.GetPivotPosition())
	draft:SetAttribute("BPW_PivotYaw", ItemShopVisualShell.GetPivotYaw())

	local created, lights, surfaces = 0, 0, 0
	for _, spec in ipairs(ItemShopVisualShell.GetExteriorDraftSpec()) do
		local part = spawnDraftPart(draft, spec, pivotCF)
		created += 1
		if part:FindFirstChild("TextGui") then
			surfaces += 1
		end
		if part:FindFirstChild("Light") then
			lights += 1
		end
	end

	draft.WorldPivot = pivotCF
	draft.Parent = exterior

	print(string.format(
		"[ItemShopVisualShell] Créé: %s (%d Parts, %d lumières, %d SurfaceGui)",
		EXTERIOR_DRAFT_NAME,
		created,
		lights,
		surfaces
	))
	print("[ItemShopVisualShell] Modifie librement la façade dans Studio, puis sauvegarde la place.")
	print("[ItemShopVisualShell] Le placeholder Exterior/ShopSign/SignBoard est masqué par la nouvelle enseigne ; tu peux le supprimer.")
	return draft
end

-- Studio Edit uniquement. Crée l'intérieur artistique sous Interior, sans
-- toucher à la façade, à la coque ni à Workspace.ItemShop.
function ItemShopVisualShell.CreateInteriorDraft(): Model?
	if RunService:IsRunning() then
		warn("[ItemShopVisualShell] Create ItemShop Interior Draft : mode Edit uniquement (pas en Play).")
		return nil
	end

	local visual = ItemShopVisualShell.FindVisualModel()
	if not visual then
		warn(
			"[ItemShopVisualShell] ItemShopVisual introuvable — lance d'abord Create ItemShop Editable Shell."
		)
		return nil
	end

	local interior = visual:FindFirstChild(INTERIOR_FOLDER)
	if not interior then
		local folder = Instance.new("Folder")
		folder.Name = INTERIOR_FOLDER
		folder.Parent = visual
		interior = folder
	end

	if interior:FindFirstChild(INTERIOR_DRAFT_NAME) then
		warn("[ItemShopVisualShell] " .. ItemShopVisualShell.InteriorAlreadyExistsMessage)
		print("[ItemShopVisualShell] " .. ItemShopVisualShell.InteriorAlreadyExistsMessage)
		print("[ItemShopVisualShell] Supprime " .. INTERIOR_DRAFT_NAME .. " à la main pour repartir de zéro.")
		return nil
	end

	local pivotCF = ItemShopVisualShell.GetPivotCFrame()
	local draft = Instance.new("Model")
	draft.Name = INTERIOR_DRAFT_NAME
	draft:SetAttribute("ManualDecor", true)
	draft:SetAttribute("BPW_InteriorDraft", true)
	draft:SetAttribute("BPW_PivotPosition", ItemShopVisualShell.GetPivotPosition())
	draft:SetAttribute("BPW_PivotYaw", ItemShopVisualShell.GetPivotYaw())

	local created, lights, surfaces = 0, 0, 0
	for _, spec in ipairs(ItemShopVisualShell.GetInteriorDraftSpec()) do
		local part = spawnDraftPart(draft, spec, pivotCF)
		created += 1
		if part:FindFirstChild("TextGui") then
			surfaces += 1
		end
		if part:FindFirstChild("Light") then
			lights += 1
		end
	end

	draft.WorldPivot = pivotCF
	draft.Parent = interior

	print(string.format(
		"[ItemShopVisualShell] Créé: %s (%d Parts, %d lumières, %d SurfaceGui)",
		INTERIOR_DRAFT_NAME,
		created,
		lights,
		surfaces
	))
	print("[ItemShopVisualShell] Les socles de Displays/*DisplayVisual sont recouverts par les nouveaux podiums ; tu peux les supprimer.")
	print("[ItemShopVisualShell] Aménage librement l'intérieur dans Studio, puis sauvegarde la place.")
	return draft
end

local function findDraftInstance(draft: Instance, path: string, name: string): Instance?
	local parent: Instance? = draft
	for segment in string.gmatch(path, "[^/]+") do
		if not parent then
			return nil
		end
		parent = (parent :: Instance):FindFirstChild(segment)
	end
	if not parent then
		return nil
	end
	return (parent :: Instance):FindFirstChild(name)
end

function ItemShopVisualShell.FindExteriorDraft(): Instance?
	local visual = ItemShopVisualShell.FindVisualModel()
	if not visual then
		return nil
	end
	local exterior = visual:FindFirstChild(EXTERIOR_FOLDER)
	if not exterior then
		return nil
	end
	return exterior:FindFirstChild(EXTERIOR_DRAFT_NAME)
end

-- Studio Edit uniquement. Retouche les pièces existantes de ExteriorDraft_v1 et
-- ajoute quelques volumes de finition. Ne recrée jamais la façade, ne supprime
-- rien, et refuse une seconde application de la même version.
function ItemShopVisualShell.PolishExteriorDraftV1(): boolean
	if RunService:IsRunning() then
		warn("[ItemShopVisualShell] Polish ItemShop Exterior : mode Edit uniquement (pas en Play).")
		return false
	end

	local draft = ItemShopVisualShell.FindExteriorDraft()
	if not draft then
		warn("[ItemShopVisualShell] " .. ItemShopVisualShell.ExteriorMissingMessage)
		print("[ItemShopVisualShell] " .. ItemShopVisualShell.ExteriorMissingMessage)
		return false
	end

	local polish = ItemShopVisualShell.GetExteriorPolishSpec()
	if draft:GetAttribute("BPW_ExteriorPolishVersion") == polish.Version then
		warn("[ItemShopVisualShell] " .. ItemShopVisualShell.ExteriorPolishAppliedMessage)
		print("[ItemShopVisualShell] " .. ItemShopVisualShell.ExteriorPolishAppliedMessage)
		return false
	end

	local pivotCF = ItemShopVisualShell.GetPivotCFrame()
	local updated, missing, added = 0, 0, 0

	for _, update in ipairs(polish.Updates) do
		local instance = findDraftInstance(draft, update.Path, update.Name)
		if not instance or not instance:IsA("BasePart") then
			missing += 1
			warn(
				"[ItemShopVisualShell] Retouche ignorée, pièce absente : "
					.. update.Path
					.. "/"
					.. update.Name
			)
			continue
		end
		local part = instance :: BasePart
		if update.Size then
			part.Size = update.Size
		end
		if update.Offset then
			-- Conserve l'orientation d'origine : seul le centre est repositionné.
			local target = (pivotCF * CFrame.new(update.Offset)).Position
			part.CFrame = CFrame.new(target) * part.CFrame.Rotation
		end
		if update.Color then
			part.Color = update.Color
		end
		if update.Material then
			part.Material = resolveMaterial(update.Material)
		end
		if update.Transparency then
			part.Transparency = update.Transparency
		end
		if update.Light then
			local light = part:FindFirstChildWhichIsA("PointLight")
			if light then
				light.Color = update.Light.Color
				light.Brightness = update.Light.Brightness
				light.Range = update.Light.Range
			end
		end
		updated += 1
	end

	for _, spec in ipairs(polish.Additions) do
		if findDraftInstance(draft, spec.Path, spec.Name) then
			continue
		end
		spawnDraftPart(draft, spec, pivotCF)
		added += 1
	end

	draft:SetAttribute("BPW_ExteriorPolishVersion", polish.Version)

	print(string.format(
		"[ItemShopVisualShell] Polish v%d appliqué : %d Parts modifiées, %d Parts ajoutées, %d ignorées.",
		polish.Version,
		updated,
		added,
		missing
	))
	print("[ItemShopVisualShell] Sauvegarde la place pour conserver la finition.")
	return true
end

-- Migration de layout : aligne automatiquement le modèle manuel lorsque le
-- pivot de GameConfig change. Aucun descendant n'est reconstruit ou modifié ;
-- le modèle complet est seulement déplacé comme une unité.
function ItemShopVisualShell.EnsureVisualModelPivot(): boolean
	local model = ItemShopVisualShell.FindVisualModel()
	if not model or not model:IsA("Model") then
		return false
	end

	local target = model :: Model
	local expectedPosition = ItemShopVisualShell.GetPivotPosition()
	local expectedYaw = ItemShopVisualShell.GetPivotYaw()
	local actualPosition = target:GetPivot().Position
	local storedPosition = target:GetAttribute("BPW_PivotPosition")
	local storedYaw = target:GetAttribute("BPW_PivotYaw")

	local function samePosition(candidate: any): boolean
		if candidate == nil or type(candidate.X) ~= "number" then
			return false
		end
		return math.abs(candidate.X - expectedPosition.X) < 0.01
			and math.abs(candidate.Y - expectedPosition.Y) < 0.01
			and math.abs(candidate.Z - expectedPosition.Z) < 0.01
	end

	if samePosition(actualPosition) and samePosition(storedPosition) and storedYaw == expectedYaw then
		return false
	end

	target:PivotTo(ItemShopVisualShell.GetPivotCFrame())
	target:SetAttribute("BPW_PivotPosition", expectedPosition)
	target:SetAttribute("BPW_PivotYaw", expectedYaw)
	print("[ItemShopVisualShell] ItemShopVisual déplacé vers le pivot configuré.")
	return true
end

-- Réalignement manuel si le pivot du visuel a été déplacé par accident.
function ItemShopVisualShell.RealignVisualModel(): boolean
	if RunService:IsRunning() then
		warn("[ItemShopVisualShell] Réalignement : mode Edit uniquement.")
		return false
	end
	local model = ItemShopVisualShell.FindVisualModel()
	if not model or not model:IsA("Model") then
		warn("[ItemShopVisualShell] ItemShopVisual introuvable — rien à réaligner.")
		return false
	end
	local target = model :: Model
	target:PivotTo(ItemShopVisualShell.GetPivotCFrame())
	target:SetAttribute("BPW_PivotPosition", ItemShopVisualShell.GetPivotPosition())
	target:SetAttribute("BPW_PivotYaw", ItemShopVisualShell.GetPivotYaw())
	print("[ItemShopVisualShell] ItemShopVisual réaligné sur le pivot de configuration.")
	return true
end

--------------------------------------------------------------------
-- Rangement hub : ancienne boutique Studio hors Workspace (jamais dans le ciel)
--------------------------------------------------------------------
ItemShopVisualShell.ParkedFolderName = "BPW_ParkedLobbyDecor"
ItemShopVisualShell.ParkedFromAttribute = "BPW_ParkedFrom"
-- Au-dessus de ça, une géométrie de boutique restante est anormale (hub deck ~ Y 18).
ItemShopVisualShell.StrayShopMaxWorldY = 80

function ItemShopVisualShell.IsProtectedHubDeckShell(instance: Instance): boolean
	-- Exclusion : HubDeckShell_New (et legacy HubDeckShell) sous CentralHubVisual.
	local function isDeckName(name: string): boolean
		return name == "HubDeckShell_New" or name == "HubDeckShell" or name == "HubDeck"
	end
	if isDeckName(instance.Name) then
		return true
	end
	local parent = instance.Parent
	while parent do
		if isDeckName(parent.Name) then
			return true
		end
		parent = parent.Parent
	end
	return false
end

function ItemShopVisualShell.IsParkableLobbyShopVisual(instance: Instance): boolean
	if ItemShopVisualShell.IsProtectedHubDeckShell(instance) then
		return false
	end
	if instance:GetAttribute("BPW_HubAsset") == true then
		return false
	end
	if instance:GetAttribute("BPW_ItemShopVisual") == true then
		return true
	end
	if instance.Name == ItemShopVisualShell.GetVisualModelName() then
		return true
	end
	return false
end

local function parkedAncestor(instance: Instance): boolean
	local parent = instance.Parent
	while parent do
		if parent.Name == ItemShopVisualShell.ParkedFolderName then
			return true
		end
		parent = parent.Parent
	end
	return false
end

function ItemShopVisualShell.CollectParkableLobbyShopVisuals(): { Instance }
	local found: { Instance } = {}
	local seen: { [Instance]: boolean } = {}

	local function consider(inst: Instance?)
		if not inst or seen[inst] then
			return
		end
		if parkedAncestor(inst) then
			return
		end
		if not ItemShopVisualShell.IsParkableLobbyShopVisual(inst) then
			return
		end
		seen[inst] = true
		table.insert(found, inst)
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		consider(child)
		if child.Name == ItemShopVisualShell.GetStudioDecorationRootName() then
			for _, descendant in ipairs(child:GetDescendants()) do
				if descendant:IsA("Model") or descendant:IsA("Folder") then
					consider(descendant)
				end
			end
		end
		if child.Name == "BubblePopWorld" then
			local lobby = child:FindFirstChild("Lobby")
			if lobby then
				for _, descendant in ipairs(lobby:GetDescendants()) do
					if descendant:IsA("Model") then
						consider(descendant)
					end
				end
			end
		end
	end

	return found
end

function ItemShopVisualShell.ParkLobbyShopVisuals(parkedFolder: Instance): number
	local moved = 0
	local studioRootName = ItemShopVisualShell.GetStudioDecorationRootName()
	local studioRoot = Workspace:FindFirstChild(studioRootName)
	local world = Workspace:FindFirstChild("BubblePopWorld")
	local lobby = if world then world:FindFirstChild("Lobby") else nil

	for _, inst in ipairs(ItemShopVisualShell.CollectParkableLobbyShopVisuals()) do
		local from = "Workspace"
		if studioRoot and (inst == studioRoot or inst:IsDescendantOf(studioRoot)) then
			from = studioRootName
		elseif lobby and (inst == lobby or inst:IsDescendantOf(lobby)) then
			from = "Lobby"
		end
		inst:SetAttribute(ItemShopVisualShell.ParkedFromAttribute, from)
		inst.Parent = parkedFolder
		moved += 1
	end
	return moved
end

function ItemShopVisualShell.RestoreParkedLobbyShopVisuals(
	parkedFolder: Instance?,
	lobby: Instance?,
	studioDecoration: Instance?
): number
	if not parkedFolder then
		return 0
	end
	local restored = 0
	local attr = ItemShopVisualShell.ParkedFromAttribute
	local visualName = ItemShopVisualShell.GetVisualModelName()
	for _, child in ipairs(parkedFolder:GetChildren()) do
		local from = child:GetAttribute(attr)
		local dest: Instance? = nil
		if child.Name == visualName or child:GetAttribute("BPW_ItemShopVisual") == true then
			dest = studioDecoration
		elseif from == "Lobby" then
			dest = lobby
		elseif from == ItemShopVisualShell.GetStudioDecorationRootName() then
			dest = studioDecoration
		elseif lobby then
			dest = lobby
		else
			dest = studioDecoration
		end
		if dest then
			child.Parent = dest
			child:SetAttribute(attr, nil)
			restored += 1
		end
	end
	return restored
end

-- Chemins encore présents dans Workspace (anomalie si hub actif).
function ItemShopVisualShell.ListStrayShopVisualPaths(): { string }
	local paths: { string } = {}
	for _, inst in ipairs(ItemShopVisualShell.CollectParkableLobbyShopVisuals()) do
		local path = inst.Name
		pcall(function()
			path = inst:GetFullName()
		end)
		table.insert(paths, path)
	end
	return paths
end

-- true si une pièce de boutique parkable dépasse StrayShopMaxWorldY.
function ItemShopVisualShell.HasAbnormallyHighShopGeometry(): boolean
	local maxY = ItemShopVisualShell.StrayShopMaxWorldY
	local function partY(part: BasePart): number
		local cf = part.CFrame
		if typeof(cf) == "CFrame" then
			return cf.Position.Y
		end
		return part.Position.Y
	end
	for _, inst in ipairs(ItemShopVisualShell.CollectParkableLobbyShopVisuals()) do
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") and partY(d :: BasePart) > maxY then
				return true
			end
		end
		if inst:IsA("BasePart") and partY(inst :: BasePart) > maxY then
			return true
		end
	end
	return false
end

return ItemShopVisualShell
