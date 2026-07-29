--!strict
-- Placement Studio (Edit) des poteaux + guirlandes autour de la Summer Zone.
-- Écrit uniquement dans Workspace.StudioDecoration.SummerZoneDecor
--   Structures/LightPosts et Effects/StringLights.
-- Ne vide jamais SummerZoneDecor / StudioDecoration.
-- Usage (plugin ou Command Bar, Rojo connecté) :
--   require(...).CreateSummerPerimeterLights()
--   require(...).RemoveSummerPerimeterLights()

local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")

local SummerZoneStringLights = {}

local GENERATOR_ID = "SummerZoneStringLights"
local ATTR_FLAG = "SummerPerimeterLights"

local POST_ASSET_ID = 18953379883
local STRING_ASSET_ID = 93169410099587

-- Espacement / hauteur (studs au-dessus du sol de zone = layout.Y)
local POST_SPACING = 30
local OUTER_INSET = 5
local BOARD_CLEARANCE = 3
local ENTRANCE_EXTRA_CLEAR = 10
local EXISTING_DECOR_CLEAR = 5
local POST_TARGET_HEIGHT = 10.5
local LIGHT_ATTACH_ABOVE_GROUND = 8.5
local STRING_SAG = 0.75
local MAX_POSTS = 36

local STUDIO_ROOT = "StudioDecoration"
local DECOR_NAME = "SummerZoneDecor"
local STRUCTURES = "Structures"
local EFFECTS = "Effects"
local LIGHT_POSTS = "LightPosts"
local STRING_LIGHTS = "StringLights"

local function getZoneDefs()
	return require(script.Parent.ZoneDefs)
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
	local preview = getSummerPreview()
	local decor = preview.EnsureSummerZoneDecor()
	local structures = ensureChildFolder(decor, STRUCTURES)
	local effects = ensureChildFolder(decor, EFFECTS)
	local posts = ensureChildFolder(structures, LIGHT_POSTS)
	local strings = ensureChildFolder(effects, STRING_LIGHTS)
	markGenerated(posts)
	markGenerated(strings)
	return posts, strings
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
-- Préparation modèle (échelle, collisions, perfs)
--------------------------------------------------------------------

local function getBoundingSize(inst: Instance): Vector3
	if inst:IsA("Model") then
		local _cf, size = (inst :: Model):GetBoundingBox()
		return size
	elseif inst:IsA("BasePart") then
		return (inst :: BasePart).Size
	end
	local model = Instance.new("Model")
	local parent = inst.Parent
	inst.Parent = model
	local _cf, size = model:GetBoundingBox()
	inst.Parent = parent
	model:Destroy()
	return size
end

local function scaleInstanceToHeight(inst: Instance, targetHeight: number)
	local size = getBoundingSize(inst)
	if size.Y < 0.05 then
		return
	end
	local factor = targetHeight / size.Y
	if inst:IsA("Model") then
		local ok = pcall(function()
			(inst :: Model):ScaleTo(factor)
		end)
		if not ok then
			local pivot = (inst :: Model):GetPivot().Position
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Size = d.Size * factor
					local offset = d.Position - pivot
					d.CFrame = CFrame.new(pivot + offset * factor) * (d.CFrame - d.CFrame.Position)
				end
			end
		end
	elseif inst:IsA("BasePart") then
		local p = inst :: BasePart
		p.Size = p.Size * factor
	end
end

local function scaleInstanceLength(inst: Instance, targetLength: number, alongAxis: string)
	local size = getBoundingSize(inst)
	local current = if alongAxis == "Z" then size.Z elseif alongAxis == "Y" then size.Y else size.X
	if current < 0.05 then
		return
	end
	local factor = targetLength / current
	if inst:IsA("Model") then
		-- ScaleTo uniforme : approche la longueur cible sans déformer le mesh à la main.
		pcall(function()
			(inst :: Model):ScaleTo(factor)
		end)
	elseif inst:IsA("BasePart") then
		local p = inst :: BasePart
		if alongAxis == "Z" then
			p.Size = Vector3.new(p.Size.X, p.Size.Y, targetLength)
		elseif alongAxis == "Y" then
			p.Size = Vector3.new(p.Size.X, targetLength, p.Size.Z)
		else
			p.Size = Vector3.new(targetLength, p.Size.Y, p.Size.Z)
		end
	end
end

local function longestHorizontalAxis(size: Vector3): string
	if size.Z >= size.X then
		return "Z"
	end
	return "X"
end

local function prepareDecorModel(inst: Instance, asStringLight: boolean)
	if inst:IsA("Model") then
		local model = inst :: Model
		if not model.PrimaryPart then
			local first: BasePart? = nil
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					first = d
					break
				end
			end
			if first then
				model.PrimaryPart = first
			end
		end
	end

	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			if asStringLight then
				d.CanTouch = false
				d.CanQuery = false
			else
				d.CanTouch = false
				d.CanQuery = false
			end
			d.CastShadow = false
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			-- Mobile : garder un rendu léger (asset peut déjà avoir des ampoules néon).
			d.Enabled = false
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			d.Enabled = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end

	if inst:IsA("BasePart") then
		local p = inst :: BasePart
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
	end
end

local function setPivotWorld(inst: Instance, cf: CFrame)
	if inst:IsA("Model") then
		(inst :: Model):PivotTo(cf)
	elseif inst:IsA("BasePart") then
		(inst :: BasePart).CFrame = cf
	end
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
	local delta = to - from
	local length = delta.Magnitude
	if length < 1 then
		return
	end
	local count = math.max(1, math.floor(length / spacing + 0.5))
	for i = 0, count do
		local t = i / count
		local pos = from:Lerp(to, t)
		table.insert(out, {
			Position = pos,
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
	local y = L.Y
	local ex, ez = L.Ex, L.Ez
	local boardO = L.BoardOrigin

	local minX = o.X - ex + OUTER_INSET
	local maxX = o.X + ex - OUTER_INSET
	local minZ = o.Z - ez + OUTER_INSET
	local maxZ = o.Z + ez - OUTER_INSET

	local groundY = y
	local corners = {
		Vector3.new(minX, groundY, minZ),
		Vector3.new(maxX, groundY, minZ),
		Vector3.new(maxX, groundY, maxZ),
		Vector3.new(minX, groundY, maxZ),
	}

	local raw: { PerimeterPoint } = {}
	sampleEdge(corners[1], corners[2], POST_SPACING, "South", raw) -- +X
	sampleEdge(corners[2], corners[3], POST_SPACING, "East", raw) -- +Z
	sampleEdge(corners[3], corners[4], POST_SPACING, "North", raw) -- -X
	sampleEdge(corners[4], corners[1], POST_SPACING, "West", raw) -- -Z

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
		-- Sous-échantillonner uniformément pour mobile.
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
-- Création / suppression
--------------------------------------------------------------------

function SummerZoneStringLights.RemoveSummerPerimeterLights()
	local root = workspace:FindFirstChild(STUDIO_ROOT)
	if not root then
		print("[SummerZoneStringLights] Rien à supprimer (pas de StudioDecoration).")
		return
	end
	local decor = root:FindFirstChild(DECOR_NAME)
	if not decor then
		print("[SummerZoneStringLights] Rien à supprimer (pas de SummerZoneDecor).")
		return
	end

	local removed = 0
	local structures = decor:FindFirstChild(STRUCTURES)
	if structures then
		local posts = structures:FindFirstChild(LIGHT_POSTS)
		if posts and isGenerated(posts) then
			removed += #posts:GetChildren()
			posts:ClearAllChildren()
		elseif posts then
			for _, child in ipairs(posts:GetChildren()) do
				if isGenerated(child) then
					child:Destroy()
					removed += 1
				end
			end
		end
	end

	local effects = decor:FindFirstChild(EFFECTS)
	if effects then
		local strings = effects:FindFirstChild(STRING_LIGHTS)
		if strings and isGenerated(strings) then
			removed += #strings:GetChildren()
			strings:ClearAllChildren()
		elseif strings then
			for _, child in ipairs(strings:GetChildren()) do
				if isGenerated(child) then
					child:Destroy()
					removed += 1
				end
			end
		end
	end

	-- Filet de sécurité : attributs orphelins sous SummerZoneDecor uniquement.
	for _, d in ipairs(decor:GetDescendants()) do
		if isGenerated(d) and d.Name ~= LIGHT_POSTS and d.Name ~= STRING_LIGHTS then
			if d.Parent and (d.Parent.Name == LIGHT_POSTS or d.Parent.Name == STRING_LIGHTS) then
				d:Destroy()
				removed += 1
			end
		end
	end

	print(string.format("[SummerZoneStringLights] Supprimé %d objet(s) généré(s). SummerZoneDecor conservé.", removed))
end

local function placePost(template: Instance, pos: Vector3, index: number, parent: Folder): Instance
	local clone = template:Clone()
	clone.Name = string.format("LightPost_%02d", index)
	markGenerated(clone)
	prepareDecorModel(clone, false)
	scaleInstanceToHeight(clone, POST_TARGET_HEIGHT)

	local size = getBoundingSize(clone)
	local ground = Vector3.new(pos.X, pos.Y, pos.Z)
	local pivot = CFrame.new(ground + Vector3.new(0, size.Y / 2, 0))
	setPivotWorld(clone, pivot)
	clone.Parent = parent
	return clone
end

local function attachHeight(post: Instance, layoutY: number): Vector3
	local size = getBoundingSize(post)
	local pivotPos: Vector3
	if post:IsA("Model") then
		pivotPos = (post :: Model):GetPivot().Position
	elseif post:IsA("BasePart") then
		pivotPos = (post :: BasePart).Position
	else
		pivotPos = Vector3.new(0, layoutY, 0)
	end
	local topY = math.max(pivotPos.Y + size.Y / 2 - 0.5, layoutY + LIGHT_ATTACH_ABOVE_GROUND)
	-- Cible visuelle : bas des ampoules ~7–9 studs au-dessus du sol.
	local hangY = layoutY + LIGHT_ATTACH_ABOVE_GROUND
	return Vector3.new(pivotPos.X, math.clamp(hangY, layoutY + 7, topY), pivotPos.Z)
end

local function placeString(
	template: Instance,
	a: Vector3,
	b: Vector3,
	index: number,
	parent: Folder
): Instance?
	local dist = (b - a).Magnitude
	if dist < 4 then
		return nil
	end

	local clone = template:Clone()
	clone.Name = string.format("StringLight_%02d", index)
	markGenerated(clone)
	prepareDecorModel(clone, true)

	local size = getBoundingSize(clone)
	local axis = longestHorizontalAxis(size)
	scaleInstanceLength(clone, dist * 0.98, axis)

	local mid = a:Lerp(b, 0.5) - Vector3.new(0, STRING_SAG, 0)
	local look = CFrame.lookAt(mid, b, Vector3.yAxis)
	-- lookAt pointe -Z ; si l’axe long est X, tourner de 90°.
	if axis == "X" then
		look = look * CFrame.Angles(0, math.rad(90), 0)
	end
	setPivotWorld(clone, look)
	clone.Parent = parent
	return clone
end

export type CreateResult = {
	PostCount: number,
	StringCount: number,
	AttachHeightAboveGround: number,
	PostHeight: number,
}

function SummerZoneStringLights.CreateSummerPerimeterLights(): CreateResult?
	if RunService:IsRunning() then
		warn("[SummerZoneStringLights] Create uniquement en mode Edit (pas en Play).")
		return nil
	end

	-- Remplace seulement les objets générés par cet outil.
	SummerZoneStringLights.RemoveSummerPerimeterLights()
	local postsFolder, stringsFolder = getOrCreateTargets()

	local ZoneDefs = getZoneDefs()
	local layout = ZoneDefs.GetSummerBridgeLayout()
	local points = SummerZoneStringLights.ComputePerimeterPoints(layout)

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

	-- Templates hors Workspace pendant le clonage.
	postTemplate.Parent = nil
	stringTemplate.Parent = nil

	local posts: { Instance } = {}
	local attachPoints: { Vector3 } = {}

	for _, p in ipairs(points) do
		if tooCloseToExisting(p.Position, avoid, EXISTING_DECOR_CLEAR) then
			continue
		end
		local post = placePost(postTemplate, p.Position, #posts + 1, postsFolder)
		table.insert(posts, post)
		table.insert(attachPoints, attachHeight(post, layout.Y))
	end

	local stringCount = 0
	-- Relier les poteaux consécutifs sur le même parcours + boucler si proche.
	for i = 1, #attachPoints do
		local a = attachPoints[i]
		local b = attachPoints[if i < #attachPoints then i + 1 else 1]
		local dist = (b - a).Magnitude
		-- Ne pas fermer un grand gap (entrée) ni des segments trop longs.
		if dist > POST_SPACING * 1.65 then
			continue
		end
		if dist < 4 then
			continue
		end
		local s = placeString(stringTemplate, a, b, stringCount + 1, stringsFolder)
		if s then
			stringCount += 1
		end
	end

	postTemplate:Destroy()
	stringTemplate:Destroy()

	local result: CreateResult = {
		PostCount = #posts,
		StringCount = stringCount,
		AttachHeightAboveGround = LIGHT_ATTACH_ABOVE_GROUND,
		PostHeight = POST_TARGET_HEIGHT,
	}

	print(string.format(
		"[SummerZoneStringLights] OK — %d poteaux, %d guirlandes | hauteur ampoules ~%.1f studs | poteaux ~%.1f studs",
		result.PostCount,
		result.StringCount,
		result.AttachHeightAboveGround,
		result.PostHeight
	))
	print("[SummerZoneStringLights] Emplacement: StudioDecoration/SummerZoneDecor/Structures/LightPosts + Effects/StringLights")
	return result
end

-- Constantes exposées pour tests / rapport.
SummerZoneStringLights.POST_ASSET_ID = POST_ASSET_ID
SummerZoneStringLights.STRING_ASSET_ID = STRING_ASSET_ID
SummerZoneStringLights.POST_SPACING = POST_SPACING
SummerZoneStringLights.POST_TARGET_HEIGHT = POST_TARGET_HEIGHT
SummerZoneStringLights.LIGHT_ATTACH_ABOVE_GROUND = LIGHT_ATTACH_ABOVE_GROUND
SummerZoneStringLights.GENERATOR_ID = GENERATOR_ID

return SummerZoneStringLights
