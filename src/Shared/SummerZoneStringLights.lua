--!strict
-- Placement Studio (Edit) des poteaux + guirlandes autour de la Summer Zone.
-- Écrit uniquement dans Workspace.StudioDecoration.SummerZoneDecor
--   Structures/LightPosts et Effects/StringLights.
-- Ne vide jamais SummerZoneDecor / StudioDecoration.
-- Usage (plugin ou Command Bar, Rojo connecté) :
--   require(...).CreateSummerPerimeterLights()
--   require(...).RefreshSummerPerimeterLights()
--   require(...).RemoveSummerPerimeterLights()
--
-- Toute la géométrie passe par les helpers AABB monde ci-dessous : le pivot des
-- assets importés n'est jamais supposé centré ni au sol.

local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

local SummerZoneStringLights = {}

local GENERATOR_ID = "SummerZoneStringLights"
local ATTR_FLAG = "SummerPerimeterLights"

local POST_ASSET_ID = 18953379883
local STRING_ASSET_ID = 93169410099587

-- Périmètre
local POST_SPACING = 30
local OUTER_INSET = 5
local BOARD_CLEARANCE = 3
local ENTRANCE_EXTRA_CLEAR = 10
local EXISTING_DECOR_CLEAR = 5
local MAX_POSTS = 36

-- Hauteurs (studs, relatives au sol sable de la zone)
local POST_TARGET_HEIGHT = 12
local POST_GROUND_SINK = 0.2
local STRING_ATTACH_BELOW_TOP = 0.5
local STRING_LOWEST_TARGET = 8.2
local STRING_LOWEST_MIN = 7
local STRING_CHAIN_PIECES = 3
local MIN_ASSET_SAG = 0.5

local STUDIO_ROOT = "StudioDecoration"
local DECOR_NAME = "SummerZoneDecor"
local STRUCTURES = "Structures"
local EFFECTS = "Effects"
local LIGHT_POSTS = "LightPosts"
local STRING_LIGHTS = "StringLights"

local function getZoneDefs()
	return require(script.Parent.ZoneDefs)
end

local function getGameConfig()
	return require(script.Parent.GameConfig)
end

local function getSummerPreview()
	return require(script.Parent.SummerZoneEditingPreview)
end

local function markGenerated(inst: Instance)
	inst:SetAttribute(ATTR_FLAG, true)
	inst:SetAttribute("GeneratedBy", GENERATOR_ID)
end

local function isGenerated(inst: Instance): boolean
	return inst:GetAttribute(ATTR_FLAG) == true
		or inst:GetAttribute("GeneratedBy") == GENERATOR_ID
end

local function ensureChildFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		warn("[SummerZoneStringLights] " .. name .. " existe déjà (" .. existing.ClassName .. ") — conservation.")
		return existing :: any
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getOrCreateTargets(): (Folder, Folder)
	local decor = getSummerPreview().EnsureSummerZoneDecor()
	local structures = ensureChildFolder(decor, STRUCTURES)
	local effects = ensureChildFolder(decor, EFFECTS)
	local posts = ensureChildFolder(structures, LIGHT_POSTS)
	local strings = ensureChildFolder(effects, STRING_LIGHTS)
	markGenerated(posts)
	markGenerated(strings)
	return posts, strings
end

local function findFolders(): (Folder?, Folder?)
	local root = workspace:FindFirstChild(STUDIO_ROOT)
	if not root then
		return nil, nil
	end
	local decor = root:FindFirstChild(DECOR_NAME)
	if not decor then
		return nil, nil
	end
	local structures = decor:FindFirstChild(STRUCTURES)
	local effects = decor:FindFirstChild(EFFECTS)
	local posts = if structures then structures:FindFirstChild(LIGHT_POSTS) else nil
	local strings = if effects then effects:FindFirstChild(STRING_LIGHTS) else nil
	return (posts :: any), (strings :: any)
end

--------------------------------------------------------------------
-- Géométrie : AABB monde, translation, rotation, échelle
--------------------------------------------------------------------

local function partAabb(p: BasePart): (Vector3, Vector3)
	local cf = p.CFrame
	local half = p.Size * 0.5
	local ex = cf.RightVector * half.X
	local ey = cf.UpVector * half.Y
	local ez = cf.LookVector * half.Z
	local extent = Vector3.new(
		math.abs(ex.X) + math.abs(ey.X) + math.abs(ez.X),
		math.abs(ex.Y) + math.abs(ey.Y) + math.abs(ez.Y),
		math.abs(ex.Z) + math.abs(ey.Z) + math.abs(ez.Z)
	)
	return cf.Position - extent, cf.Position + extent
end

-- Boîte englobante monde réelle (le pivot des assets n'est pas fiable).
local function worldAabb(inst: Instance): (Vector3?, Vector3?)
	local found = false
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	local function consider(p: BasePart)
		local lo, hi = partAabb(p)
		found = true
		minX = math.min(minX, lo.X)
		minY = math.min(minY, lo.Y)
		minZ = math.min(minZ, lo.Z)
		maxX = math.max(maxX, hi.X)
		maxY = math.max(maxY, hi.Y)
		maxZ = math.max(maxZ, hi.Z)
	end

	if inst:IsA("BasePart") then
		consider(inst :: BasePart)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			consider(d)
		end
	end
	if not found then
		return nil, nil
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

local function aabbCenter(inst: Instance): Vector3?
	local minV, maxV = worldAabb(inst)
	if not (minV and maxV) then
		return nil
	end
	return (minV + maxV) * 0.5
end

local function pivotOf(inst: Instance): CFrame
	if inst:IsA("Model") then
		return (inst :: Model):GetPivot()
	elseif inst:IsA("BasePart") then
		return (inst :: BasePart).CFrame
	end
	return CFrame.identity
end

-- WorldPivot déplace le pivot sans bouger la géométrie : indispensable pour que
-- rotations et translations partent d'un repère connu. PrimaryPart doit être vide,
-- sinon WorldPivot suit la CFrame de cette part et l'orientation reste inconnue.
local function normalizePivot(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local center = aabbCenter(inst)
	if not center then
		return
	end
	local model = inst :: Model
	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new(center)
end

local function moveBy(inst: Instance, delta: Vector3)
	if delta.Magnitude < 1e-4 then
		return
	end
	if inst:IsA("Model") then
		local m = inst :: Model
		m:PivotTo(m:GetPivot() + delta)
	elseif inst:IsA("BasePart") then
		local p = inst :: BasePart
		p.CFrame = p.CFrame + delta
	end
end

local function rotateAround(inst: Instance, point: Vector3, rot: CFrame)
	local xf = CFrame.new(point) * rot * CFrame.new(-point)
	if inst:IsA("Model") then
		local m = inst :: Model
		m:PivotTo(xf * m:GetPivot())
	elseif inst:IsA("BasePart") then
		local p = inst :: BasePart
		p.CFrame = xf * p.CFrame
	end
end

-- Oriente l'objet autour de sa boîte englobante (indépendant du pivot d'origine).
local function setOrientationAboutCenter(inst: Instance, targetRot: CFrame)
	local center = aabbCenter(inst)
	if not center then
		return
	end
	local delta = targetRot.Rotation * pivotOf(inst).Rotation:Inverse()
	rotateAround(inst, center, delta)
end

local function currentScale(inst: Instance): number
	if inst:IsA("Model") then
		local ok, scale = pcall(function()
			return (inst :: Model):GetScale()
		end)
		if ok and type(scale) == "number" and scale > 0 then
			return scale
		end
	end
	return 1
end

local function scaleManually(inst: Instance, factor: number)
	local center = aabbCenter(inst)
	if not center then
		return
	end
	local parts: { BasePart } = {}
	if inst:IsA("BasePart") then
		table.insert(parts, inst :: BasePart)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	for _, p in ipairs(parts) do
		local offset = p.Position - center
		p.Size = p.Size * factor
		p.CFrame = p.CFrame + (center + offset * factor - p.Position)
	end
end

-- Échelle uniforme jusqu'à une dimension cible. ScaleTo est ABSOLU (relatif à la
-- taille d'origine de l'asset) : on multiplie donc par l'échelle courante et on
-- vérifie le résultat au lieu de supposer une échelle de 1.
local function fitDimension(inst: Instance, axis: string, target: number): number
	for _ = 1, 4 do
		local minV, maxV = worldAabb(inst)
		if not (minV and maxV) then
			return 0
		end
		local size = maxV - minV
		local actual = if axis == "Y" then size.Y elseif axis == "Z" then size.Z else size.X
		if actual < 1e-3 then
			return actual
		end
		local ratio = target / actual
		if math.abs(ratio - 1) < 0.01 then
			return actual
		end
		local applied = false
		if inst:IsA("Model") then
			applied = pcall(function()
				(inst :: Model):ScaleTo(currentScale(inst) * ratio)
			end)
		end
		if not applied then
			scaleManually(inst, ratio)
		end
	end
	local minV, maxV = worldAabb(inst)
	if minV and maxV then
		local size = maxV - minV
		return if axis == "Y" then size.Y elseif axis == "Z" then size.Z else size.X
	end
	return 0
end

local function alignBottomTo(inst: Instance, y: number)
	local minV, _maxV = worldAabb(inst)
	if not minV then
		return
	end
	moveBy(inst, Vector3.new(0, y - minV.Y, 0))
end

local function alignTopTo(inst: Instance, y: number)
	local _minV, maxV = worldAabb(inst)
	if not maxV then
		return
	end
	moveBy(inst, Vector3.new(0, y - maxV.Y, 0))
end

local function setHorizontalCenter(inst: Instance, pos: Vector3)
	local center = aabbCenter(inst)
	if not center then
		return
	end
	moveBy(inst, Vector3.new(pos.X - center.X, 0, pos.Z - center.Z))
end

local function setBoundsCenter(inst: Instance, pos: Vector3)
	local center = aabbCenter(inst)
	if not center then
		return
	end
	moveBy(inst, pos - center)
end

-- Repère orthonormé dont l'axe demandé suit `dir` (gère une pente).
local function frameAlong(dir: Vector3, axis: string): CFrame
	local d = dir.Unit
	local upRef = Vector3.yAxis
	if math.abs(d:Dot(upRef)) > 0.99 then
		upRef = Vector3.xAxis
	end
	local side = upRef:Cross(d)
	if side.Magnitude < 1e-4 then
		side = Vector3.xAxis
	end
	side = side.Unit
	local up = d:Cross(side).Unit
	if axis == "X" then
		return CFrame.fromMatrix(Vector3.zero, d, up)
	end
	-- axis "Z" : ZVector = side × up = dir
	return CFrame.fromMatrix(Vector3.zero, side, up)
end

local function flipAboutAxis(axis: string): CFrame
	if axis == "X" then
		return CFrame.Angles(math.pi, 0, 0)
	end
	return CFrame.Angles(0, 0, math.pi)
end

--------------------------------------------------------------------
-- Chargement d’assets (Studio plugin → GetObjects ; sinon InsertService)
--------------------------------------------------------------------

local function unwrapAsset(loaded: any): Instance?
	if typeof(loaded) ~= "Instance" then
		if type(loaded) == "table" and loaded[1] and typeof(loaded[1]) == "Instance" then
			return loaded[1] :: Instance
		end
		return nil
	end
	local inst = loaded :: Instance
	if inst:IsA("Model") or inst:IsA("Folder") then
		local children = inst:GetChildren()
		if #children == 1 and (children[1]:IsA("Model") or children[1]:IsA("BasePart") or children[1]:IsA("Folder")) then
			local only = children[1]
			only.Parent = nil
			inst:Destroy()
			return only
		end
	end
	return inst
end

function SummerZoneStringLights.LoadAssetTemplate(assetId: number): Instance?
	local okGet, getResult = pcall(function()
		return (game :: any):GetObjects("rbxassetid://" .. tostring(assetId))
	end)
	if okGet then
		local unwrapped = unwrapAsset(getResult)
		if unwrapped then
			return unwrapped
		end
	end

	local okIns, insResult = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if okIns then
		local unwrapped = unwrapAsset(insResult)
		if unwrapped then
			return unwrapped
		end
	end

	warn(string.format(
		"[SummerZoneStringLights] Impossible de charger l'asset %d (GetObjects/InsertService).",
		assetId
	))
	return nil
end

--------------------------------------------------------------------
-- Préparation modèle (collisions, perfs)
--------------------------------------------------------------------

local function prepareDecorModel(inst: Instance)
	local function applyPart(p: BasePart)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
	end

	if inst:IsA("BasePart") then
		applyPart(inst :: BasePart)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			applyPart(d)
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			-- Mobile : rendu néon suffisant, pas de lumière dynamique.
			d.Enabled = false
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			d.Enabled = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
end

--------------------------------------------------------------------
-- Sol de la Summer Zone
--------------------------------------------------------------------

-- Dessus du plancher sable construit par ZoneBuilder (ZoneFloor).
function SummerZoneStringLights.GetGroundY(layout: any?): number
	local ZoneDefs = getZoneDefs()
	local L = layout or ZoneDefs.GetSummerBridgeLayout()
	local Config = getGameConfig()
	return L.Y - Config.Grid.BubbleSize.Y * 0.35
end

-- Raycast vers le bas si un vrai sol existe en Edit ; sinon hauteur théorique.
local function groundYAt(x: number, z: number, layout: any, ignore: { Instance }): number
	local fallback = SummerZoneStringLights.GetGroundY(layout)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local origin = Vector3.new(x, fallback + 30, z)
	local ok, result = pcall(function()
		return workspace:Raycast(origin, Vector3.new(0, -60, 0), params)
	end)
	if ok and result then
		local hitY = (result :: RaycastResult).Position.Y
		if math.abs(hitY - fallback) <= 8 then
			return hitY
		end
	end
	return fallback
end

--------------------------------------------------------------------
-- Géométrie du périmètre
--------------------------------------------------------------------

export type PerimeterPoint = {
	Position: Vector3,
	Edge: string,
	Index: number,
}

local function sampleEdge(from: Vector3, to: Vector3, spacing: number, edgeName: string, out: { PerimeterPoint })
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local count = math.max(1, math.floor(length / spacing + 0.5))
	for i = 0, count do
		local t = i / count
		table.insert(out, {
			Position = from:Lerp(to, t),
			Edge = edgeName,
			Index = #out + 1,
		})
	end
end

local function nearBoard(pos: Vector3, boardO: Vector3, boardEx: number, boardEz: number, clearance: number): boolean
	return math.abs(pos.X - boardO.X) <= boardEx + clearance
		and math.abs(pos.Z - boardO.Z) <= boardEz + clearance
end

local function inEntranceGap(pos: Vector3, layout: any): boolean
	local half = (layout.ArchGap or 18) / 2 + ENTRANCE_EXTRA_CLEAR
	local nearWest = pos.X <= layout.ZoneOrigin.X - layout.Ex + OUTER_INSET + 12
	return nearWest and math.abs(pos.Z - layout.ArchZ) <= half
end

local function dedupePoints(points: { PerimeterPoint }, minDist: number): { PerimeterPoint }
	local result: { PerimeterPoint } = {}
	for _, p in ipairs(points) do
		local tooClose = false
		for _, q in ipairs(result) do
			local dx = p.Position.X - q.Position.X
			local dz = p.Position.Z - q.Position.Z
			if dx * dx + dz * dz < minDist * minDist then
				tooClose = true
				break
			end
		end
		if not tooClose then
			table.insert(result, p)
		end
	end
	return result
end

function SummerZoneStringLights.ComputePerimeterPoints(layout: any?): { PerimeterPoint }
	local ZoneDefs = getZoneDefs()
	local L = layout or ZoneDefs.GetSummerBridgeLayout()
	local o = L.ZoneOrigin
	local ex, ez = L.Ex, L.Ez
	local boardO = L.BoardOrigin

	local minX = o.X - ex + OUTER_INSET
	local maxX = o.X + ex - OUTER_INSET
	local minZ = o.Z - ez + OUTER_INSET
	local maxZ = o.Z + ez - OUTER_INSET
	local groundY = SummerZoneStringLights.GetGroundY(L)

	local corners = {
		Vector3.new(minX, groundY, minZ),
		Vector3.new(maxX, groundY, minZ),
		Vector3.new(maxX, groundY, maxZ),
		Vector3.new(minX, groundY, maxZ),
	}

	local raw: { PerimeterPoint } = {}
	sampleEdge(corners[1], corners[2], POST_SPACING, "South", raw)
	sampleEdge(corners[2], corners[3], POST_SPACING, "East", raw)
	sampleEdge(corners[3], corners[4], POST_SPACING, "North", raw)
	sampleEdge(corners[4], corners[1], POST_SPACING, "West", raw)

	local filtered: { PerimeterPoint } = {}
	for _, p in ipairs(raw) do
		if nearBoard(p.Position, boardO, L.BoardEx, L.BoardEz, BOARD_CLEARANCE) then
			continue
		end
		if inEntranceGap(p.Position, L) then
			continue
		end
		table.insert(filtered, p)
	end

	local unique = dedupePoints(filtered, POST_SPACING * 0.55)
	if #unique > MAX_POSTS then
		local step = #unique / MAX_POSTS
		local reduced: { PerimeterPoint } = {}
		local i = 1.0
		while #reduced < MAX_POSTS and i <= #unique + 0.001 do
			local idx = math.clamp(math.floor(i + 0.5), 1, #unique)
			table.insert(reduced, unique[idx])
			i += step
		end
		unique = dedupePoints(reduced, POST_SPACING * 0.45)
	end

	for i, p in ipairs(unique) do
		p.Index = i
	end
	return unique
end

local function collectExistingDecorAvoid(decor: Instance, postsFolder: Instance, stringsFolder: Instance): { Vector3 }
	local points: { Vector3 } = {}
	for _, d in ipairs(decor:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:IsDescendantOf(postsFolder) or d:IsDescendantOf(stringsFolder) then
				continue
			end
			if isGenerated(d) then
				continue
			end
			table.insert(points, d.Position)
		end
	end
	return points
end

local function tooCloseToExisting(pos: Vector3, avoid: { Vector3 }, radius: number): boolean
	local r2 = radius * radius
	for _, p in ipairs(avoid) do
		local dx = pos.X - p.X
		local dz = pos.Z - p.Z
		if dx * dx + dz * dz <= r2 then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------
-- Courbe de suspension (fonction pure, testable)
--------------------------------------------------------------------

-- Parabole de suspension : les extrémités restent en haut, le centre descend de `sag`.
function SummerZoneStringLights.ComputeSagNodes(a: Vector3, b: Vector3, sag: number, pieces: number): { Vector3 }
	local count = math.max(1, math.floor(pieces))
	local nodes: { Vector3 } = {}
	for i = 0, count do
		local t = i / count
		local flat = a:Lerp(b, t)
		table.insert(nodes, flat - Vector3.new(0, 4 * sag * t * (1 - t), 0))
	end
	return nodes
end

-- Profondeur de courbe admissible pour garder les ampoules au-dessus des têtes.
function SummerZoneStringLights.ComputeSagDepth(attachY: number, groundY: number): number
	local target = attachY - (groundY + STRING_LOWEST_TARGET)
	local maxSag = attachY - (groundY + STRING_LOWEST_MIN)
	return math.clamp(target, 0.6, math.max(0.6, maxSag))
end

-- Les segments droits relient des noeuds, jamais le creux théorique de la parabole :
-- ce facteur convertit une descente voulue au noeud le plus bas en paramètre de sag.
function SummerZoneStringLights.MaxNodeSagFactor(pieces: number): number
	local count = math.max(1, math.floor(pieces))
	local factor = 0
	for i = 0, count do
		local t = i / count
		factor = math.max(factor, 4 * t * (1 - t))
	end
	return if factor > 1e-3 then factor else 1
end

--------------------------------------------------------------------
-- Analyse du modèle de guirlande
--------------------------------------------------------------------

export type TemplateInfo = {
	LongAxis: string,
	Length: number,
	Height: number,
	SagDepth: number,
	CurveUp: boolean,
	PartCount: number,
}

local function analyzeStringTemplate(template: Instance): TemplateInfo
	local minV, maxV = worldAabb(template)
	local size = if minV and maxV then maxV - minV else Vector3.one
	local center = if minV and maxV then (minV + maxV) * 0.5 else Vector3.zero
	local axis = if size.Z >= size.X then "Z" else "X"
	local length = if axis == "Z" then size.Z else size.X

	local parts: { BasePart } = {}
	if template:IsA("BasePart") then
		table.insert(parts, template :: BasePart)
	end
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end

	local midSum, midCount = 0, 0
	local endSum, endCount = 0, 0
	local half = math.max(length * 0.5, 1e-3)
	for _, p in ipairs(parts) do
		local along = if axis == "Z" then p.Position.Z - center.Z else p.Position.X - center.X
		local t = math.clamp(along / half, -1, 1)
		if math.abs(t) <= 0.3 then
			midSum += p.Position.Y
			midCount += 1
		elseif math.abs(t) >= 0.6 then
			endSum += p.Position.Y
			endCount += 1
		end
	end

	local sag = 0
	local curveUp = false
	if midCount > 0 and endCount > 0 then
		local midY = midSum / midCount
		local endY = endSum / endCount
		sag = math.abs(endY - midY)
		curveUp = midY > endY + 0.05
	end

	return {
		LongAxis = axis,
		Length = length,
		Height = size.Y,
		SagDepth = sag,
		CurveUp = curveUp,
		PartCount = #parts,
	}
end

--------------------------------------------------------------------
-- Suppression ciblée
--------------------------------------------------------------------

local function clearGeneratedChildren(folder: Instance?): number
	if not folder then
		return 0
	end
	local removed = 0
	for _, child in ipairs(folder:GetChildren()) do
		if isGenerated(child) or isGenerated(folder) then
			child:Destroy()
			removed += 1
		end
	end
	return removed
end

function SummerZoneStringLights.RemoveSummerPerimeterLights(): number
	local posts, strings = findFolders()
	if not (posts or strings) then
		print("[SummerZoneStringLights] Rien à supprimer.")
		return 0
	end
	local removed = clearGeneratedChildren(posts) + clearGeneratedChildren(strings)
	print(string.format("[SummerZoneStringLights] Supprimé %d objet(s) généré(s). SummerZoneDecor conservé.", removed))
	return removed
end

function SummerZoneStringLights.RemoveGeneratedStringLights(): number
	local _posts, strings = findFolders()
	return clearGeneratedChildren(strings)
end

--------------------------------------------------------------------
-- Poteaux
--------------------------------------------------------------------

export type PostPlacement = {
	Instance: Instance,
	Attach: Vector3,
	GroundY: number,
	TopY: number,
}

-- Redresse (axe long vertical), met à l'échelle, puis pose la base sur le sol.
local function fitPostToGround(post: Instance, groundY: number): PostPlacement?
	normalizePivot(post)
	local minV, maxV = worldAabb(post)
	if not (minV and maxV) then
		return nil
	end
	local size = maxV - minV
	if size.Y + 0.01 < math.max(size.X, size.Z) then
		local center = (minV + maxV) * 0.5
		local rot = if size.X >= size.Z then CFrame.Angles(0, 0, math.pi / 2) else CFrame.Angles(math.pi / 2, 0, 0)
		rotateAround(post, center, rot)
	end

	fitDimension(post, "Y", POST_TARGET_HEIGHT)
	alignBottomTo(post, groundY - POST_GROUND_SINK)

	local newMin, newMax = worldAabb(post)
	if not (newMin and newMax) then
		return nil
	end
	local center = (newMin + newMax) * 0.5
	local topY = newMax.Y
	local attachY = math.max(topY - STRING_ATTACH_BELOW_TOP, groundY + STRING_LOWEST_TARGET + 1)

	return {
		Instance = post,
		Attach = Vector3.new(center.X, attachY, center.Z),
		GroundY = groundY,
		TopY = topY,
	}
end

local function placePost(template: Instance, groundPos: Vector3, index: number, parent: Folder, ignore: { Instance }, layout: any): PostPlacement?
	local clone = template:Clone()
	clone.Name = string.format("LightPost_%02d", index)
	markGenerated(clone)
	prepareDecorModel(clone)
	clone.Parent = parent

	setHorizontalCenter(clone, groundPos)
	local groundY = groundYAt(groundPos.X, groundPos.Z, layout, ignore)
	local placement = fitPostToGround(clone, groundY)
	if not placement then
		clone:Destroy()
		return nil
	end
	return placement
end

--------------------------------------------------------------------
-- Guirlandes
--------------------------------------------------------------------

local function compressSagToMinHeight(inst: Instance, topY: number, minY: number)
	local lowMin, _lowMax = worldAabb(inst)
	if not lowMin then
		return
	end
	if lowMin.Y >= minY then
		return
	end
	local actual = topY - lowMin.Y
	local allowed = topY - minY
	if actual <= 1e-3 or allowed <= 0 then
		moveBy(inst, Vector3.new(0, minY - lowMin.Y, 0))
		return
	end
	local factor = allowed / actual

	local parts: { BasePart } = {}
	if inst:IsA("BasePart") then
		table.insert(parts, inst :: BasePart)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts <= 3 then
		-- Modèle monobloc : on remonte l'ensemble plutôt que de déformer le mesh.
		moveBy(inst, Vector3.new(0, minY - lowMin.Y, 0))
		return
	end
	for _, p in ipairs(parts) do
		local pos = p.Position
		local newY = topY - (topY - pos.Y) * factor
		p.CFrame = p.CFrame + Vector3.new(0, newY - pos.Y, 0)
	end
end

-- Segment monobloc : l'asset possède déjà sa courbe pendante.
local function placeCurvedSegment(
	template: Instance,
	info: TemplateInfo,
	a: Vector3,
	b: Vector3,
	groundY: number,
	name: string,
	parent: Instance
): Instance?
	local dist = (b - a).Magnitude
	local clone = template:Clone()
	clone.Name = name
	markGenerated(clone)
	prepareDecorModel(clone)
	clone.Parent = parent

	-- Mise à l'échelle avant rotation : les extents sont encore alignés aux axes monde.
	normalizePivot(clone)
	fitDimension(clone, info.LongAxis, dist * 0.98)

	local dir = (b - a).Unit
	local rot = frameAlong(dir, info.LongAxis)
	if info.CurveUp then
		rot = rot * flipAboutAxis(info.LongAxis)
	end
	setOrientationAboutCenter(clone, rot)

	local attachY = math.min(a.Y, b.Y)
	setHorizontalCenter(clone, a:Lerp(b, 0.5))
	alignTopTo(clone, attachY)
	compressSagToMinHeight(clone, attachY, groundY + STRING_LOWEST_MIN)
	return clone
end

-- Segment chaîné : l'asset est (quasi) droit, on construit la courbe nous-mêmes.
local function placeChainedSegment(
	template: Instance,
	info: TemplateInfo,
	a: Vector3,
	b: Vector3,
	groundY: number,
	name: string,
	parent: Instance
): Instance?
	local attachY = math.min(a.Y, b.Y)
	local sag = SummerZoneStringLights.ComputeSagDepth(attachY, groundY)
	local nodes = SummerZoneStringLights.ComputeSagNodes(
		Vector3.new(a.X, attachY, a.Z),
		Vector3.new(b.X, attachY, b.Z),
		sag / SummerZoneStringLights.MaxNodeSagFactor(STRING_CHAIN_PIECES),
		STRING_CHAIN_PIECES
	)

	local segment = Instance.new("Model")
	segment.Name = name
	markGenerated(segment)
	segment.Parent = parent

	for i = 1, #nodes - 1 do
		local p1, p2 = nodes[i], nodes[i + 1]
		local chord = p2 - p1
		if chord.Magnitude < 0.5 then
			continue
		end
		local piece = template:Clone()
		piece.Name = string.format("Span_%02d", i)
		markGenerated(piece)
		prepareDecorModel(piece)
		piece.Parent = segment

		normalizePivot(piece)
		fitDimension(piece, info.LongAxis, chord.Magnitude * 1.02)

		local rot = frameAlong(chord.Unit, info.LongAxis)
		if info.CurveUp then
			rot = rot * flipAboutAxis(info.LongAxis)
		end
		setOrientationAboutCenter(piece, rot)
		setBoundsCenter(piece, p1:Lerp(p2, 0.5))
	end

	if #segment:GetChildren() == 0 then
		segment:Destroy()
		return nil
	end
	segment.PrimaryPart = nil
	return segment
end

local function buildSegments(
	stringTemplate: Instance,
	attachPoints: { Vector3 },
	groundY: number,
	stringsFolder: Folder
): (number, string, number)
	local info = analyzeStringTemplate(stringTemplate)
	local scaledSag = if info.Length > 1e-3 then info.SagDepth * (POST_SPACING / info.Length) else 0
	local mode = if scaledSag >= MIN_ASSET_SAG and info.PartCount > 1 then "asset-curve" else "chained"

	local count = 0
	local lowest = math.huge
	for i = 1, #attachPoints do
		local a = attachPoints[i]
		local b = attachPoints[if i < #attachPoints then i + 1 else 1]
		local dist = (b - a).Magnitude
		if dist > POST_SPACING * 1.65 or dist < 4 then
			continue
		end
		local name = string.format("StringLight_%02d", count + 1)
		local created: Instance? = if mode == "asset-curve"
			then placeCurvedSegment(stringTemplate, info, a, b, groundY, name, stringsFolder)
			else placeChainedSegment(stringTemplate, info, a, b, groundY, name, stringsFolder)
		if created then
			count += 1
			local minV = select(1, worldAabb(created))
			if minV then
				lowest = math.min(lowest, minV.Y)
			end
		end
	end

	local lowestAboveGround = if lowest < math.huge then lowest - groundY else 0
	return count, mode, lowestAboveGround
end

--------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------

export type CreateResult = {
	PostCount: number,
	StringCount: number,
	PostHeight: number,
	GroundY: number,
	AttachHeightAboveGround: number,
	LowestBulbAboveGround: number,
	Mode: string,
}

local function report(result: CreateResult)
	print(string.format(
		"[SummerZoneStringLights] OK — %d poteaux (%.1f studs), %d guirlandes (%s) | attache ~%.1f studs | point bas ~%.1f studs",
		result.PostCount,
		result.PostHeight,
		result.StringCount,
		result.Mode,
		result.AttachHeightAboveGround,
		result.LowestBulbAboveGround
	))
	print("[SummerZoneStringLights] Emplacement: StudioDecoration/SummerZoneDecor/Structures/LightPosts + Effects/StringLights")
end

function SummerZoneStringLights.CreateSummerPerimeterLights(): CreateResult?
	if RunService:IsRunning() then
		warn("[SummerZoneStringLights] Create uniquement en mode Edit (pas en Play).")
		return nil
	end

	SummerZoneStringLights.RemoveSummerPerimeterLights()
	local postsFolder, stringsFolder = getOrCreateTargets()

	local ZoneDefs = getZoneDefs()
	local layout = ZoneDefs.GetSummerBridgeLayout()
	local points = SummerZoneStringLights.ComputePerimeterPoints(layout)
	local groundY = SummerZoneStringLights.GetGroundY(layout)

	local decor = getSummerPreview().EnsureSummerZoneDecor()
	local avoid = collectExistingDecorAvoid(decor, postsFolder, stringsFolder)

	local postTemplate = SummerZoneStringLights.LoadAssetTemplate(POST_ASSET_ID)
	local stringTemplate = SummerZoneStringLights.LoadAssetTemplate(STRING_ASSET_ID)
	if not postTemplate or not stringTemplate then
		warn("[SummerZoneStringLights] Abandon : assets introuvables.")
		if postTemplate then
			postTemplate:Destroy()
		end
		if stringTemplate then
			stringTemplate:Destroy()
		end
		return nil
	end
	postTemplate.Parent = nil
	stringTemplate.Parent = nil

	local ignore: { Instance } = { postsFolder, stringsFolder }
	local previewFolder = workspace:FindFirstChild(STUDIO_ROOT)
	if previewFolder then
		local preview = previewFolder:FindFirstChild("SummerZonePreview")
		if preview then
			table.insert(ignore, preview)
		end
	end

	local placements: { PostPlacement } = {}
	for _, p in ipairs(points) do
		if tooCloseToExisting(p.Position, avoid, EXISTING_DECOR_CLEAR) then
			continue
		end
		local placement = placePost(postTemplate, p.Position, #placements + 1, postsFolder, ignore, layout)
		if placement then
			table.insert(placements, placement)
		end
	end

	local attachPoints: { Vector3 } = {}
	for _, placement in ipairs(placements) do
		table.insert(attachPoints, placement.Attach)
	end

	local stringCount, mode, lowest = buildSegments(stringTemplate, attachPoints, groundY, stringsFolder)

	postTemplate:Destroy()
	stringTemplate:Destroy()

	local attachAbove = if #placements > 0 then placements[1].Attach.Y - placements[1].GroundY else 0
	local result: CreateResult = {
		PostCount = #placements,
		StringCount = stringCount,
		PostHeight = POST_TARGET_HEIGHT,
		GroundY = groundY,
		AttachHeightAboveGround = attachAbove,
		LowestBulbAboveGround = lowest,
		Mode = mode,
	}
	report(result)
	return result
end

-- Corrige les poteaux déjà générés (sol + hauteur) puis reconstruit les guirlandes.
function SummerZoneStringLights.RefreshSummerPerimeterLights(): CreateResult?
	if RunService:IsRunning() then
		warn("[SummerZoneStringLights] Refresh uniquement en mode Edit (pas en Play).")
		return nil
	end

	local postsFolder, stringsFolder = findFolders()
	local existing: { Instance } = {}
	if postsFolder then
		for _, child in ipairs(postsFolder:GetChildren()) do
			if isGenerated(child) or isGenerated(postsFolder) then
				table.insert(existing, child)
			end
		end
	end
	if #existing == 0 or not postsFolder or not stringsFolder then
		print("[SummerZoneStringLights] Aucun poteau généré — création complète.")
		return SummerZoneStringLights.CreateSummerPerimeterLights()
	end

	table.sort(existing, function(a, b)
		return a.Name < b.Name
	end)

	local ZoneDefs = getZoneDefs()
	local layout = ZoneDefs.GetSummerBridgeLayout()
	local groundY = SummerZoneStringLights.GetGroundY(layout)
	local ignore: { Instance } = { postsFolder, stringsFolder }

	local placements: { PostPlacement } = {}
	for _, post in ipairs(existing) do
		prepareDecorModel(post)
		local center = aabbCenter(post)
		if not center then
			continue
		end
		local localGround = groundYAt(center.X, center.Z, layout, ignore)
		local placement = fitPostToGround(post, localGround)
		if placement then
			table.insert(placements, placement)
		end
	end

	SummerZoneStringLights.RemoveGeneratedStringLights()

	local stringTemplate = SummerZoneStringLights.LoadAssetTemplate(STRING_ASSET_ID)
	if not stringTemplate then
		warn("[SummerZoneStringLights] Poteaux corrigés, mais asset guirlande introuvable.")
		return nil
	end
	stringTemplate.Parent = nil

	local attachPoints: { Vector3 } = {}
	for _, placement in ipairs(placements) do
		table.insert(attachPoints, placement.Attach)
	end

	local stringCount, mode, lowest = buildSegments(stringTemplate, attachPoints, groundY, stringsFolder :: Folder)
	stringTemplate:Destroy()

	local attachAbove = if #placements > 0 then placements[1].Attach.Y - placements[1].GroundY else 0
	local result: CreateResult = {
		PostCount = #placements,
		StringCount = stringCount,
		PostHeight = POST_TARGET_HEIGHT,
		GroundY = groundY,
		AttachHeightAboveGround = attachAbove,
		LowestBulbAboveGround = lowest,
		Mode = mode,
	}
	report(result)
	return result
end

-- Constantes exposées pour tests / rapport.
SummerZoneStringLights.POST_ASSET_ID = POST_ASSET_ID
SummerZoneStringLights.STRING_ASSET_ID = STRING_ASSET_ID
SummerZoneStringLights.POST_SPACING = POST_SPACING
SummerZoneStringLights.POST_TARGET_HEIGHT = POST_TARGET_HEIGHT
SummerZoneStringLights.POST_GROUND_SINK = POST_GROUND_SINK
SummerZoneStringLights.STRING_ATTACH_BELOW_TOP = STRING_ATTACH_BELOW_TOP
SummerZoneStringLights.STRING_LOWEST_TARGET = STRING_LOWEST_TARGET
SummerZoneStringLights.STRING_LOWEST_MIN = STRING_LOWEST_MIN
SummerZoneStringLights.STRING_CHAIN_PIECES = STRING_CHAIN_PIECES
SummerZoneStringLights.GENERATOR_ID = GENERATOR_ID

return SummerZoneStringLights
