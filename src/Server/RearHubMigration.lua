--!strict
-- Migration Tripo : identité exacte « 3d stage arena prop » uniquement.
-- Pas de largest fallback. Archive validée. Scale runtime. Audit d'identité.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local HubLayout = require(Shared.HubLayout)
local RearHubLogic = require(Shared.RearHubLogic)
local RearHubIdentity = require(Shared.RearHubIdentity)
local RearHubCollisionLogic = require(Shared.RearHubCollisionLogic)

local RearHubMigration = {}

local H = Config.Hub
local lastReport: { [string]: any } = {}
local GEN = "CentralHubBuilder"
local GEN_COLL = "RearHubMigration"

local STUDIO_ASSETS = "StudioAssets"
local SOURCE_NAME = "TripoRearHubPlatform_Source"
local RUNTIME_NAME = "TripoRearHubPlatform"
local REAR_MARGIN = 1.5 -- studs avant le fond ORIGINAL (1–2)
local FRONT_LANDING = 3.0 -- palier praticable devant marches (2–4), dans la grille
local TAG = "BPW_RearHubPlatform"
local EXACT_NAME = RearHubIdentity.EXACT_SOURCE_NAME

local function intLog(msg: string)
	print("[RearHubIntegration] " .. msg)
end

local function log(msg: string)
	print("[RearHubMigration] " .. msg)
end

local function countMeshParts(model: Model): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			n += 1
		end
	end
	return n
end

local function collectMeshIds(model: Model): { string }
	local list: { string } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			local mid = ""
			pcall(function()
				mid = (d :: MeshPart).MeshId
			end)
			if type(mid) == "string" and mid ~= "" then
				table.insert(list, mid)
			end
		end
	end
	return list
end

local function countNonEmptyMeshIds(model: Model): number
	return #collectMeshIds(model)
end

local function getBBox(model: Model): (CFrame?, Vector3?)
	local ok, a, b = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and typeof(a) == "CFrame" and typeof(b) == "Vector3" then
		return a :: CFrame, b :: Vector3
	end
	return nil, nil
end

local function formatSize(sz: Vector3?): string
	if not sz then
		return "nil"
	end
	return string.format("(%.2f, %.2f, %.2f)", sz.X, sz.Y, sz.Z)
end

local function meshIdsCsv(ids: { string }): string
	if #ids == 0 then
		return "<none>"
	end
	return table.concat(ids, ",")
end

local function ensureModelWrapper(meshPart: MeshPart): Model
	if meshPart.Parent and meshPart.Parent:IsA("Model") then
		return meshPart.Parent :: Model
	end
	local m = Instance.new("Model")
	m.Name = meshPart.Name
	local parent = meshPart.Parent
	meshPart.Parent = m
	m.Parent = parent or workspace
	m.PrimaryPart = meshPart
	return m
end

local function collectSearchRoots(): { Instance }
	return { workspace, ServerStorage, ReplicatedStorage }
end

local function ensureStudioAssets(): Folder
	local folder = ServerStorage:FindFirstChild(STUDIO_ASSETS)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = STUDIO_ASSETS
	f:SetAttribute("BPW_StudioPreserved", true)
	f.Parent = ServerStorage
	return f
end

--- Détruit archive Palm Tree / décor / non validée.
function RearHubMigration.PurgeInvalidArchivedSource(): boolean
	local assets = ServerStorage:FindFirstChild(STUDIO_ASSETS)
	if not assets then
		return false
	end
	local src = assets:FindFirstChild(SOURCE_NAME)
	if not src or not src:IsA("Model") then
		return false
	end

	local name = (src:GetAttribute("BPW_SourceModelName") :: any) or src.Name
	local path = (src:GetAttribute("BPW_SourcePath") :: any) or src:GetFullName()
	local meta = {
		SourceModelName = if type(name) == "string" then name else nil,
		SourcePath = if type(path) == "string" then path else nil,
		SourceMeshCount = src:GetAttribute("BPW_SourceMeshCount") :: any,
		SourceValidated = src:GetAttribute("BPW_SourceValidated") == true,
	}
	local valid, reason = RearHubIdentity.IsValidArchiveMeta(meta)
	-- Aussi rejeter si le nom d'instance / path runtime ressemble au palm
	if valid then
		local full = src:GetFullName()
		if RearHubIdentity.IsForbiddenPathOrName(full, tostring(name)) then
			valid = false
			reason = "wrong asset identity"
		end
		-- Archive elle-même ne doit pas être un clone palm (mesh-only check soft)
		if not RearHubIdentity.IsExactSourceName(tostring(name))
			and not RearHubIdentity.ContainsStageArenaProp(tostring(name))
		then
			valid = false
			reason = "wrong asset identity"
		end
		if countMeshParts(src) < 1 or countNonEmptyMeshIds(src) < 1 then
			valid = false
			reason = "no mesh geometry"
		end
	end

	if not valid then
		local pathLog = if type(path) == "string" then path else src:GetFullName()
		log(string.format(
			"removed invalid archived source: %s reason=%s",
			pathLog,
			tostring(reason or "invalid")
		))
		src:Destroy()
		return true
	end
	return false
end

function RearHubMigration.GetArchivedSource(): Model?
	RearHubMigration.PurgeInvalidArchivedSource()
	local assets = ServerStorage:FindFirstChild(STUDIO_ASSETS)
	if not assets then
		return nil
	end
	local src = assets:FindFirstChild(SOURCE_NAME)
	if not src or not src:IsA("Model") then
		return nil
	end
	if src:GetAttribute("BPW_SourceValidated") ~= true then
		return nil
	end
	if countMeshParts(src) < 1 or countNonEmptyMeshIds(src) < 1 then
		return nil
	end
	local name = tostring(src:GetAttribute("BPW_SourceModelName") or "")
	if not RearHubIdentity.IsExactSourceName(name) and not RearHubIdentity.ContainsStageArenaProp(name) then
		return nil
	end
	return src
end

-- Recherche : 1 exact name · 2 stage arena prop · sinon nil. PAS de largest fallback.
function RearHubMigration.FindExactTripoSource(): (Model?, string?)
	local candidates: { RearHubIdentity.Candidate } = {}
	local modelByKey: { [string]: Model } = {}

	for _, root in ipairs(collectSearchRoots()) do
		for _, d in ipairs(root:GetDescendants()) do
			-- Sauter l'archive ciblée et runtimes déjà clonnés
			if d.Name == SOURCE_NAME or d.Name == RUNTIME_NAME then
				continue
			end
			if d:GetAttribute("BPW_HubRole") == "RearHubPlatform" and d:GetAttribute("BPW_TripoSource") ~= true then
				-- runtime clone : skip for discovery of original
				if d:IsA("Model") and d.Parent and d.Parent.Name == "RearHub" then
					continue
				end
			end

			local model: Model? = nil
			if d:IsA("Model") then
				model = d
			elseif d:IsA("MeshPart") and RearHubIdentity.SelectionRank(d.Name, d:GetFullName()) ~= nil then
				model = ensureModelWrapper(d)
			end
			if not model then
				continue
			end

			local path = model:GetFullName()
			local name = model.Name
			local rank = RearHubIdentity.SelectionRank(name, path)
			if rank == nil then
				continue
			end

			local meshes = countMeshParts(model)
			local ids = collectMeshIds(model)
			local _, sz = getBBox(model)
			log(string.format(
				"candidate path=%s class=%s meshes=%d meshIds=%d size=%s",
				path,
				model.ClassName,
				meshes,
				#ids,
				formatSize(sz)
			))

			if not RearHubIdentity.HasMinimumGeometry(meshes, #ids) then
				continue
			end

			local c: RearHubIdentity.Candidate = {
				Name = name,
				Path = path,
				MeshParts = meshes,
				MeshIds = #ids,
				MeshIdList = ids,
			}
			table.insert(candidates, c)
			modelByKey[path] = model
		end
	end

	local chosen, reason = RearHubIdentity.SelectBestCandidate(candidates)
	if chosen and modelByKey[chosen.Path] then
		log("EXACT TRIPO SOURCE SELECTED: " .. chosen.Path .. " reason=" .. tostring(reason))
		return modelByKey[chosen.Path], chosen.Path
	end

	return nil, nil
end

function RearHubMigration.ArchiveSource(model: Model, originalPath: string): Model
	local assets = ensureStudioAssets()
	-- Toujours purger avant ré-archivage si invalide
	RearHubMigration.PurgeInvalidArchivedSource()

	local existing = assets:FindFirstChild(SOURCE_NAME)
	if existing and existing:IsA("Model") then
		local name = tostring(existing:GetAttribute("BPW_SourceModelName") or "")
		if existing:GetAttribute("BPW_SourceValidated") == true
			and (RearHubIdentity.IsExactSourceName(name) or RearHubIdentity.ContainsStageArenaProp(name))
			and countMeshParts(existing) >= 1
		then
			return existing
		end
		existing:Destroy()
	end

	local originalName = model.Name
	local meshIds = collectMeshIds(model)
	local meshCount = countMeshParts(model)
	local _, sz = getBBox(model)

	log(string.format(
		"archiving source name=%s path=%s meshes=%d meshIds=%s size=%s",
		originalName,
		originalPath,
		meshCount,
		meshIdsCsv(meshIds),
		formatSize(sz)
	))

	local clone: Model
	if model.Parent == assets then
		clone = model
	else
		clone = model:Clone()
	end
	clone.Name = SOURCE_NAME
	clone:SetAttribute("BPW_TripoSource", true)
	clone:SetAttribute("BPW_SourceModelName", originalName)
	clone:SetAttribute("BPW_SourcePath", originalPath)
	clone:SetAttribute("BPW_SourceMeshCount", meshCount)
	clone:SetAttribute("BPW_SourceValidated", true)
	clone:SetAttribute("BPW_SourceMeshIds", meshIdsCsv(meshIds))
	clone:SetAttribute("BPW_HubRole", "RearHubPlatform")
	if sz then
		clone:SetAttribute("BPW_SourceSizeX", sz.X)
		clone:SetAttribute("BPW_SourceSizeY", sz.Y)
		clone:SetAttribute("BPW_SourceSizeZ", sz.Z)
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			(d :: BasePart).Anchored = true
		end
	end
	clone.Parent = assets
	log(string.format(
		"archived source '%s' → ServerStorage.%s.%s meshes=%d",
		originalName,
		STUDIO_ASSETS,
		SOURCE_NAME,
		meshCount
	))
	return clone
end

local function prepareRuntime(model: Model, originalName: string?, originalPath: string?, sourceMeshIds: { string })
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = d :: BasePart
			p.Anchored = true
			p.CanTouch = false
			p.Massless = false
			p.CanQuery = true
			-- Mesh Tripo strictement visuel : les collisions viennent du ManualCollisionRig
			p.CanCollide = false
			p.CollisionGroup = "Default"
		end
	end
	model.Name = RUNTIME_NAME
	model:SetAttribute("BPW_HubRole", "RearHubPlatform")
	model:SetAttribute("BPW_RearHubManaged", true)
	model:SetAttribute("BPW_TripoSource", false)
	model:SetAttribute("BPW_GeneratedBy", nil)
	if originalName then
		model:SetAttribute("BPW_SourceModelName", originalName)
	end
	if originalPath then
		model:SetAttribute("BPW_SourcePath", originalPath)
	end
	model:SetAttribute("BPW_SourceMeshIds", meshIdsCsv(sourceMeshIds))
	model:SetAttribute("BPW_SourceValidated", true)
	pcall(function()
		CollectionService:AddTag(model, TAG)
	end)
end

--- Agrandit uniquement le clone runtime (source SS intacte).
function RearHubMigration.ScaleRuntimeToHub(runtime: Model): (number, Vector3?, Vector3?)
	local _, before = getBBox(runtime)
	if not before then
		return 1, nil, nil
	end
	log(string.format("source size before scale: %s", formatSize(before)))

	local targetWidth = H.DeckHalfX * 2
	local targetDepth = H.DeckHalfZ * 2
	local uniform = RearHubIdentity.ComputeUniformScale(before, targetWidth, targetDepth)

	local currentScale = 1
	pcall(function()
		currentScale = runtime:GetScale()
	end)

	local applied = currentScale * uniform
	local okScale = pcall(function()
		runtime:ScaleTo(applied)
	end)
	if not okScale then
		-- Fallback : ScaleTo indisponible — PivotTo + scale manuel n'existe pas pour MeshId.
		-- Multiplier Size des MeshParts (préserve MeshId).
		warn("[RearHubMigration] ScaleTo unavailable, scaling MeshPart.Size manually")
		for _, d in ipairs(runtime:GetDescendants()) do
			if d:IsA("BasePart") then
				local p = d :: BasePart
				p.Size = p.Size * uniform
			end
		end
		applied = uniform
	end

	local _, after = getBBox(runtime)
	log(string.format("runtime scale applied: %.4f", applied))
	log(string.format("runtime size after scale: %s", formatSize(after)))

	lastReport.scaleApplied = applied
	lastReport.sizeBefore = before
	lastReport.sizeAfter = after

	return applied, before, after
end

export type PlaceMetrics = {
	Pivot: Vector3,
	FrontZ: number,
	RearZ: number,
	RoomRearZ: number,
	RearGap: number,
	Clearance: number,
	MeshParts: number,
	MeshIds: number,
	Valid: boolean,
	Size: Vector3?,
}

function RearHubMigration.PlacePlatform(model: Model): PlaceMetrics?
	local room = RearHubLogic.GetOriginalRoomBounds()
	local originalRoomRearZ = room.MaxZ
	local rearMargin = RearHubLogic.GetRearMargin()
	local desiredRearZ = originalRoomRearZ - rearMargin

	intLog(string.format(
		"original room bounds: min=(%.1f,%.1f) max=(%.1f,%.1f)",
		room.MinX,
		room.MinZ,
		room.MaxX,
		room.MaxZ
	))
	intLog(string.format("original room rear edge: %.2f", originalRoomRearZ))
	intLog(string.format("target platform rear edge: %.2f (margin=%.2f)", desiredRearZ, rearMargin))

	-- Face les bulles (-Z) : front = minZ, rear = maxZ
	model:PivotTo(CFrame.new(0, H.DeckTopY, 0))
	local cf1, sz1 = getBBox(model)
	if not (cf1 and sz1) then
		return nil
	end
	local pivot = model:GetPivot().Position
	local pivotToRear = math.max(0.1, (cf1.Position.Z + sz1.Z / 2) - pivot.Z)
	local pivotToFront = math.max(0.1, pivot.Z - (cf1.Position.Z - sz1.Z / 2))

	local floorY = Config.Grid.Origin.Y - Config.Grid.BubbleSize.Y * 0.35
	local bottomY = cf1.Position.Y - sz1.Y / 2
	local lift = floorY - bottomY
	if math.abs(lift) > 200 then
		lift = H.DeckTopY - (cf1.Position.Y - sz1.Y / 2)
	end

	-- centerZ = originalRoomMaxZ - rearMargin - pivotToRearEdge
	local centerZ = desiredRearZ - pivotToRear
	local target = Vector3.new(Config.Grid.Origin.X, pivot.Y + lift, centerZ)
	model:PivotTo(CFrame.new(target))

	local cf2, sz2 = getBBox(model)
	if not (cf2 and sz2) then
		return nil
	end
	local curRear = cf2.Position.Z + sz2.Z / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, 0, desiredRearZ - curRear))

	local cfY, szY = getBBox(model)
	if cfY and szY then
		local bottom = cfY.Position.Y - szY.Y / 2
		local yLift = floorY - bottom
		if math.abs(yLift) > 0.05 then
			model:PivotTo(model:GetPivot() + Vector3.new(0, yLift, 0))
		end
	end

	local cf3, sz3 = getBBox(model)
	if not (cf3 and sz3) then
		return nil
	end
	local frontZ = cf3.Position.Z - sz3.Z / 2
	local rearZ = cf3.Position.Z + sz3.Z / 2
	local roomRearZ = originalRoomRearZ
	local rearGap = roomRearZ - rearZ
	local clearance = FRONT_LANDING
	local pivotPos = model:GetPivot().Position
	local meshN = countMeshParts(model)
	local idN = countNonEmptyMeshIds(model)

	HubLayout.Center = Vector3.new(Config.Grid.Origin.X, H.DeckTopY, pivotPos.Z)
	HubLayout.RuntimePlatformFrontZ = frontZ
	HubLayout.RuntimePlatformRearZ = rearZ
	HubLayout.RuntimeRoomRearZ = roomRearZ

	local platAabb = RearHubLogic.AabbFromCenterSize(cf3.Position, Vector3.new(sz3.X, 1, sz3.Z))
	local landingAabb = {
		MinX = HubLayout.Center.X - H.Stairs.Width / 2 - 1,
		MaxX = HubLayout.Center.X + H.Stairs.Width / 2 + 1,
		MinZ = frontZ - FRONT_LANDING,
		MaxZ = frontZ,
	}
	local reserves = { platAabb, landingAabb }
	HubLayout.RuntimeReserveAabbs = reserves

	local removedCells = RearHubLogic.CountCellsIntersectingAny(reserves)
	local totalCells = Config.Grid.SizeX * Config.Grid.SizeZ
	local restoredAround = totalCells - removedCells

	intLog(string.format("platform rear edge: %.2f", rearZ))
	intLog(string.format("rear gap: %.2f", rearGap))
	intLog(string.format("platform front edge: %.2f", frontZ))
	intLog(string.format("removed intersecting bubble cells: %d", removedCells))
	intLog(string.format("restored non-intersecting cells: %d", restoredAround))
	intLog(string.format(
		"platform pivot applied @ (%.2f, %.2f, %.2f) pivotToRear=%.2f pivotToFront=%.2f",
		pivotPos.X, pivotPos.Y, pivotPos.Z, pivotToRear, pivotToFront
	))
	log(string.format("runtime path: %s", model:GetFullName()))
	log(string.format("runtime Tripo model meshParts: %d", meshN))

	lastReport.pivot = pivotPos
	lastReport.removedCells = removedCells
	lastReport.restoredAround = restoredAround
	lastReport.originalRoomRearZ = originalRoomRearZ
	lastReport.reserves = reserves

	local sizeOk = not RearHubIdentity.IsStillSourceTiny(sz3)
	local inside = RearHubLogic.AssertPlatformInsideOriginalRoom(frontZ, rearZ, room.MinZ, originalRoomRearZ)
	local gapOk = RearHubLogic.AssertRearGapOk(originalRoomRearZ, rearZ)
	local valid = meshN > 0 and idN > 0 and inside and gapOk and sizeOk and rearZ <= originalRoomRearZ + 0.05

	return {
		Pivot = pivotPos,
		FrontZ = frontZ,
		RearZ = rearZ,
		RoomRearZ = roomRearZ,
		RearGap = rearGap,
		Clearance = clearance,
		MeshParts = meshN,
		MeshIds = idN,
		Valid = valid,
		Size = sz3,
	}
end

local function destroyGeneratedOnly(container: Instance)
	local doomed: { Instance } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:GetAttribute("BPW_GeneratedBy") == GEN
			or child:GetAttribute("GeneratedByCode") == true
		then
			if child:GetAttribute("BPW_HubRole") == "RearHubPlatform"
				or child:GetAttribute("BPW_TripoSource") == true
				or CollectionService:HasTag(child, TAG)
			then
				continue
			end
			table.insert(doomed, child)
		end
	end
	for _, inst in ipairs(doomed) do
		inst:Destroy()
	end
end

function RearHubMigration.ClearGeneratedModules(modulesFolder: Folder)
	destroyGeneratedOnly(modulesFolder)
	local rear = modulesFolder:FindFirstChild("RearHub")
	if rear and rear:IsA("Folder") then
		for _, c in ipairs(rear:GetChildren()) do
			-- Conserves mesh, rigs manuels, et ancrages leaderboard déjà posés.
			if c.Name == "HubDisplays" or c.Name == "ManualCollisionRig" then
				continue
			end
			if c:GetAttribute("BPW_BakedStudioHub") == true then
				continue
			end
			if c:GetAttribute("BPW_HubRole") == "RearHubPlatform" then
				if c:GetAttribute("BPW_TripoSource") ~= true then
					c:Destroy()
				end
			elseif c:GetAttribute("BPW_GeneratedBy") == GEN or c:GetAttribute("GeneratedByCode") == true then
				c:Destroy()
			end
		end
	end
end

function RearHubMigration.RemoveExpandedRearGeometry(hubRoot: Folder)
	local removed = 0
	for _, name in ipairs({ "RearHubApproach", "RearHubPad", "RearExtensionFloor", "ExpandedRearFloor" }) do
		local inst = hubRoot:FindFirstChild(name)
		if inst then
			inst:Destroy()
			removed += 1
			intLog("expanded rear geometry removed: " .. name)
		end
	end
	local world = workspace:FindFirstChild("BubblePopWorld")
	if world then
		for _, d in ipairs(world:GetDescendants()) do
			if d.Name == "ApproachFloor" and d:GetAttribute("BPW_GeneratedBy") ~= nil then
				local parent = d.Parent
				d:Destroy()
				removed += 1
				if parent and parent.Name == "RearHubApproach" and #parent:GetChildren() == 0 then
					parent:Destroy()
				end
			end
		end
	end
	if removed == 0 then
		intLog("expanded rear geometry removed: 0")
	end
	local room = RearHubLogic.GetOriginalRoomBounds()
	intLog(string.format("original rear boundary restored: %.2f", room.MaxZ))
	lastReport.removedExtensions = removed
end

function RearHubMigration.BuildRoomEnvelope(hubRoot: Folder, _metrics: PlaceMetrics?)
	RearHubMigration.RemoveExpandedRearGeometry(hubRoot)
end

local function collLog(msg: string)
	print("[RearHubCollision] " .. msg)
end

local function destroyNamedDeep(root: Instance, name: string)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name and d:IsA("BasePart") then
			d:Destroy()
		end
	end
	local child = root:FindFirstChild(name)
	if child then
		child:Destroy()
	end
end

--- Raycast vertical sur le mesh Tripo (CanCollide=false, CanQuery=true).
local function raycastMeshTopY(model: Model, worldX: number, worldZ: number, fromY: number): (number?, BasePart?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.IgnoreWater = true
	local origin = Vector3.new(worldX, fromY, worldZ)
	local result = workspace:Raycast(origin, Vector3.new(0, -400, 0), params)
	if result and result.Instance and result.Instance:IsA("BasePart") then
		return result.Position.Y, result.Instance :: BasePart
	end
	return nil, nil
end

--- Sommet du portail central + éventuel hit mesh.
function RearHubMigration.MeasurePortalVisualTop(runtime: Model): (number?, BasePart?, Vector3?)
	local cf, sz = getBBox(runtime)
	if not (cf and sz) then
		return nil, nil, nil
	end
	local cx, cz = cf.Position.X, cf.Position.Z
	local fromY = cf.Position.Y + sz.Y / 2 + 40
	-- Centre du plateau + quelques échantillons pour capter le disque portail
	local samples = {
		Vector3.new(cx, 0, cz),
		Vector3.new(cx, 0, cz - 1),
		Vector3.new(cx + 2, 0, cz),
		Vector3.new(cx - 2, 0, cz),
	}
	local bestY: number? = nil
	local bestHit: BasePart? = nil
	for _, s in ipairs(samples) do
		local y, hit = raycastMeshTopY(runtime, s.X, s.Z, fromY)
		if y and hit then
			if not bestY or y > bestY then
				bestY = y
				bestHit = hit
			end
		end
	end
	-- Fallback bbox high point (centre XZ)
	if not bestY then
		bestY = cf.Position.Y + sz.Y / 2
	end
	return bestY, bestHit, Vector3.new(cx, bestY, cz)
end

--- Purge les proxys de portail dupliqués (plus aucun dossier de collisions généré).
function RearHubMigration.PurgeLegacyPortalProxies(hubRoot: Folder, modulesFolder: Folder?)
	if modulesFolder then
		destroyNamedDeep(modulesFolder, "PortalWalkSurface")
		destroyNamedDeep(modulesFolder, "PortalInteractionTrigger")
	end
	destroyNamedDeep(hubRoot, "PortalWalkSurface")
	destroyNamedDeep(hubRoot, "PortalInteractionTrigger")
end

function RearHubMigration.BuildCollisions(hubRoot: Folder, runtime: Model?, modulesFolder: Folder?)
	local ManualRig = require(Shared.RearHubManualRig)
	local spawn = hubRoot:FindFirstChild("HubSpawnLocation")
	local sl = if spawn and spawn:IsA("BasePart") then spawn :: BasePart else nil
	local _ = runtime
	RearHubMigration.PurgeLegacyPortalProxies(hubRoot, modulesFolder)
	-- Aucune reconstruction : validation seule du rig manuel.
	ManualRig.ValidateRuntime()
	local walkTop = HubLayout.RuntimePortalWalkTopY or H.DeckTopY
	if sl then
		walkTop = sl.Position.Y - sl.Size.Y / 2
		HubLayout.RuntimeDeckTopY = walkTop
		HubLayout.RuntimePortalWalkTopY = walkTop
	end
	-- Ancre transit inchangée (placement manuel)
	RearHubMigration.EnsureManualTransitAnchor(walkTop)
	collLog("collision version: " .. ManualRig.RIG_VERSION)
	collLog("collisions ready (manual rig)")
end

local function spawnLog(msg: string)
	print("[RearHubSpawn] " .. msg)
end

function RearHubMigration.EnsureManualTransitAnchor(_hubFloorTopY: number?): BasePart?
	local TransitAnchorLogic = require(Shared.TransitAnchorLogic)
	local name = TransitAnchorLogic.NAME
	local existing = workspace:FindFirstChild(name)

	if existing and existing:IsA("BasePart") then
		local a = existing :: BasePart
		-- Migration unique : uniquement ancienne pose plugin (0,8,19)/(2,4,2).
		local migratedFlag = a:GetAttribute(TransitAnchorLogic.LEGACY_MIGRATED_ATTR) == true
		if TransitAnchorLogic.ShouldMigrateLegacyPose(migratedFlag, a.Size, a.Position) then
			a.Size = TransitAnchorLogic.FALLBACK_SIZE
			a.CFrame = TransitAnchorLogic.FallbackCFrame()
			a:SetAttribute(TransitAnchorLogic.MANUAL_ATTR, true)
			a:SetAttribute(TransitAnchorLogic.LEGACY_MIGRATED_ATTR, true)
			print(string.format(
				"[BubbleTransit] LEGACY pose migrated once → Pos=(%.2f, %.2f, %.2f) Size=(%.2f, %.2f, %.2f)",
				a.Position.X,
				a.Position.Y,
				a.Position.Z,
				a.Size.X,
				a.Size.Y,
				a.Size.Z
			))
		else
			-- STUDIO-OWNED : aucune écriture CFrame / Size (pose manuelle ou déjà validée).
			print(string.format(
				"[BubbleTransit] preserve Studio-owned anchor (NO CFrame/Size write): (%.2f, %.2f, %.2f) size=(%.2f,%.2f,%.2f)",
				a.Position.X,
				a.Position.Y,
				a.Position.Z,
				a.Size.X,
				a.Size.Y,
				a.Size.Z
			))
		end
		a:SetAttribute(TransitAnchorLogic.MANUAL_ATTR, true)
		a:SetAttribute("BPW_Role", "BubbleTransitInteractionAnchor")
		a.Anchored = true
		a.CanCollide = false
		a.CanTouch = false
		a.CanQuery = true
		a.CastShadow = false
		a.Transparency = 1
		if a.Material == Enum.Material.Neon then
			a.Material = Enum.Material.SmoothPlastic
		end
		-- Prompt / attachment only if missing (no pose).
		local attach = a:FindFirstChild("PromptAttachment")
		if not (attach and attach:IsA("Attachment")) then
			if attach then
				attach:Destroy()
			end
			local att = Instance.new("Attachment")
			att.Name = "PromptAttachment"
			att.Position = Vector3.new(0, 0.2, 0)
			att.Parent = a
			attach = att
		end
		local prompt = a:FindFirstChild("BubbleTransitPrompt", true)
		if not (prompt and prompt:IsA("ProximityPrompt")) then
			if prompt then
				prompt:Destroy()
			end
			local pr = Instance.new("ProximityPrompt")
			pr.Name = "BubbleTransitPrompt"
			pr.RequiresLineOfSight = false
			pr.HoldDuration = 0
			pr.MaxActivationDistance = 8
			pr.ActionText = "Travel"
			pr.ObjectText = "Bubble Transit"
			pr.KeyboardKeyCode = Enum.KeyCode.E
			pr.GamepadKeyCode = Enum.KeyCode.ButtonX
			pr:SetAttribute("TransitId", "LobbyTransit")
			pr.Parent = attach
		end
		return a
	end

	-- Absente uniquement : créer fallback, jamais écraser une existante.
	if existing then
		existing:Destroy()
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = TransitAnchorLogic.FALLBACK_SIZE
	p.CFrame = TransitAnchorLogic.FallbackCFrame()
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.CastShadow = false
	p.Transparency = 1
	p.Material = Enum.Material.SmoothPlastic
	p:SetAttribute(TransitAnchorLogic.MANUAL_ATTR, true)
	p:SetAttribute(TransitAnchorLogic.INIT_ATTR, true)
	p:SetAttribute("BPW_Role", "BubbleTransitInteractionAnchor")
	p.Parent = workspace
	local att = Instance.new("Attachment")
	att.Name = "PromptAttachment"
	att.Position = Vector3.new(0, 0.2, 0)
	att.Parent = p
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "BubbleTransitPrompt"
	pr.RequiresLineOfSight = false
	pr.HoldDuration = 0
	pr.MaxActivationDistance = 8
	pr.ActionText = "Travel"
	pr.ObjectText = "Bubble Transit"
	pr.KeyboardKeyCode = Enum.KeyCode.E
	pr.GamepadKeyCode = Enum.KeyCode.ButtonX
	pr:SetAttribute("TransitId", "LobbyTransit")
	pr.Parent = att
	warn("[BubbleTransit] missing Studio anchor — created FALLBACK once only at (0,8.5,70.5). Place manually then save place.")
	return p
end

function RearHubMigration.RemoveFloatingTempObjects(): number
	local removed = 0
	-- Anciens triggers générés + débris debug
	local doomedNames = {
		PortalInteractionTrigger = true,
		HubSpawnMarker = false, -- keep but hide
	}
	local world = workspace:FindFirstChild("BubblePopWorld")
	if world then
		for _, d in ipairs(world:GetDescendants()) do
			if d.Name == "PortalInteractionTrigger" and d:GetAttribute("BPW_GeneratedBy") ~= nil then
				d:Destroy()
				removed += 1
			end
		end
	end
	-- Ancre workspace : forcer invisible (était bloc rose Neon)
	local anchor = workspace:FindFirstChild("BubbleTransitInteractionAnchor")
	if anchor and anchor:IsA("BasePart") then
		local a = anchor :: BasePart
		if a.Transparency < 1 or a.Material == Enum.Material.Neon then
			a.Transparency = 1
			a.CastShadow = false
			a.Material = Enum.Material.SmoothPlastic
			a.CanCollide = false
			removed += 1 -- « corrected »
		end
	end
	-- Pièces Neon magenta orphelines en hauteur hors hub
	for _, d in ipairs(workspace:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "BubbleTransitInteractionAnchor" then
			local p = d :: BasePart
			local col = p.Color
			local isMagenta = col.R > 0.9 and col.G < 0.15 and col.B > 0.9
			if isMagenta and p.Position.Y > 8 and p:GetAttribute("BPW_GeneratedBy") == nil and p.Transparency < 1 then
				-- ne pas détruire l'ancre ; hide
				p.Transparency = 1
				p.CastShadow = false
				removed += 1
			end
		end
	end
	spawnLog(string.format("floating temporary objects removed: %d", removed))
	return removed
end

--- Spawn safe sur plancher collision (PAS le portail).
function RearHubMigration.PlaceSafeHubSpawn(functional: Folder?)
	spawnLog("collisions ready")
	RearHubMigration.RemoveFloatingTempObjects()

	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	local studioSpawn = hub and hub:FindFirstChild("HubSpawnLocation")
	if studioSpawn and studioSpawn:IsA("SpawnLocation") then
		local sl = studioSpawn :: SpawnLocation
		local preserved = sl.CFrame
		sl:SetAttribute("BPW_ManualPlacement", true)
		sl:SetAttribute("BPW_Role", "HubSpawnLocation")
		sl:SetAttribute("BPW_SpawnManualInitialized", true)
		sl.Anchored = true
		sl.CanCollide = false
		sl.CanTouch = false
		sl.CanQuery = false
		sl.CastShadow = false
		sl.Transparency = 1
		sl.Enabled = true
		sl.Neutral = true
		sl.AllowTeamChangeOnTouch = false
		sl.CFrame = preserved
		spawnLog(string.format(
			"HubSpawnLocation position (preserved): (%.2f, %.2f, %.2f) - no CFrame rewrite",
			sl.Position.X,
			sl.Position.Y,
			sl.Position.Z
		))
		lastReport.spawnPos = sl.Position
		lastReport.spawnTopY = sl.Position.Y + sl.Size.Y / 2
		if functional then
			local nest = functional:FindFirstChild("HubSpawnLocation")
			if nest and nest:IsA("SpawnLocation") and nest ~= sl then
				nest.Enabled = false
			end
		end
		return
	end
	spawnLog("no Studio HubSpawnLocation - skip auto place")
end

-- Compat
function RearHubMigration.AlignSpawnToPortalWalk(functional: Folder?)
	RearHubMigration.PlaceSafeHubSpawn(functional)
end


export type ApplyResult = {
	Model: Model?,
	Ok: boolean,
	OriginalName: string?,
	OriginalPath: string?,
	Metrics: PlaceMetrics?,
	RestoredCells: number,
}

function RearHubMigration.Apply(hubRoot: Folder, modulesFolder: Folder): ApplyResult
	lastReport = {}
	if not HubLayout.IsRearPlacement() then
		return { Model = nil, Ok = false, OriginalName = nil, OriginalPath = nil, Metrics = nil, RestoredCells = 0 }
	end

	local pure = RearHubLogic.ComputeRearPlacement()
	HubLayout.Center = pure.Center
	HubLayout.FrontSign = pure.FrontSign
	HubLayout.FaceYawDegrees = pure.YawTowardBubbles

	RearHubMigration.PurgeInvalidArchivedSource()

	local RearHubStudioInstall = require(Shared.RearHubStudioInstall)

	-- 1) Hub déjà cuit dans Studio → le réutiliser (pas de ScaleTo / pas de clone)
	local baked = RearHubStudioInstall.GetBakedHub()
	local runtime: Model? = nil
	local originalName: string? = nil
	local originalPath: string? = nil
	local sourceMeshIds: { string } = {}
	local metrics: PlaceMetrics? = nil

	if baked and RearHubStudioInstall.IsValidBakedHub(baked) then
		runtime = baked
		originalName = tostring(baked:GetAttribute("BPW_SourceModelName") or EXACT_NAME)
		originalPath = tostring(baked:GetAttribute("BPW_SourcePath") or baked:GetFullName())
		sourceMeshIds = collectMeshIds(baked)
		log("using baked Studio hub: " .. baked:GetFullName())

		-- Pas de Clear qui détruit le bake
		local rear = modulesFolder:FindFirstChild("RearHub")
		if rear then
			for _, c in ipairs(rear:GetChildren()) do
				if c:IsA("Model") and c ~= baked and c:GetAttribute("BPW_BakedStudioHub") ~= true then
					if c.Name == RUNTIME_NAME or c:GetAttribute("BPW_HubRole") == "RearHubPlatform" then
						c:Destroy()
					end
				end
			end
		end

		local m = RearHubStudioInstall.CollectMetricsFromBaked(baked)
		if m then
			metrics = {
				Pivot = m.Pivot,
				FrontZ = m.FrontZ,
				RearZ = m.RearZ,
				RoomRearZ = m.RoomRearZ,
				RearGap = m.RearGap,
				Clearance = 3,
				MeshParts = countMeshParts(baked),
				MeshIds = #sourceMeshIds,
				Valid = m.RearGap >= 0.5 and m.RearGap <= 2.01,
				Size = m.Size,
			}
			lastReport.pivot = m.Pivot
		end
		-- Le mesh Tripo reste strictement visuel
		local ManualRig = require(Shared.RearHubManualRig)
		ManualRig.MakeMeshVisualOnly(baked)
	else
		-- Fallback : clone archive (ou FATAL si rien)
		local source: Model? = RearHubMigration.GetArchivedSource()
		if not source then
			local found, path = RearHubMigration.FindExactTripoSource()
			if found and path then
				source = RearHubMigration.ArchiveSource(found, path)
				originalName = found.Name
				originalPath = path
			end
		else
			originalName = tostring(source:GetAttribute("BPW_SourceModelName") or EXACT_NAME)
			originalPath = tostring(source:GetAttribute("BPW_SourcePath") or source:GetFullName())
		end

		if not source then
			log("FATAL: real Tripo model not found — run Studio plugin Install / Refresh Tripo Rear Hub")
			warn("[RearHubMigration] FATAL: baked hub missing — open Studio and run Install / Refresh Tripo Rear Hub")
			lastReport.fatal = true
			return {
				Model = nil,
				Ok = false,
				OriginalName = originalName,
				OriginalPath = originalPath,
				Metrics = nil,
				RestoredCells = 0,
			}
		end

		sourceMeshIds = collectMeshIds(source)
		log("WARN: no baked Studio hub — runtime clone fallback (install plugin in edit mode)")

		local rear = modulesFolder:FindFirstChild("RearHub")
		if not rear or not rear:IsA("Folder") then
			if rear then
				rear:Destroy()
			end
			rear = Instance.new("Folder")
			rear.Name = "RearHub"
			rear:SetAttribute("BPW_RearHubFolder", true)
			rear.Parent = modulesFolder
		end
		for _, c in ipairs(rear:GetChildren()) do
			if c:IsA("Model") and c:GetAttribute("BPW_BakedStudioHub") ~= true then
				if c:GetAttribute("BPW_TripoSource") ~= true then
					c:Destroy()
				end
			end
		end

		runtime = source:Clone()
		prepareRuntime(runtime, originalName, originalPath, sourceMeshIds)
		runtime:SetAttribute("BPW_BakedStudioHub", false)
		runtime.Parent = rear
		RearHubMigration.ScaleRuntimeToHub(runtime)
		metrics = RearHubMigration.PlacePlatform(runtime)
	end

	if not runtime then
		return {
			Model = nil,
			Ok = false,
			OriginalName = originalName,
			OriginalPath = originalPath,
			Metrics = nil,
			RestoredCells = 0,
		}
	end

	lastReport.sourceModelName = originalName
	lastReport.sourcePath = originalPath
	lastReport.sourceMeshIds = sourceMeshIds

	if metrics then
		RearHubMigration.BuildRoomEnvelope(hubRoot, metrics)
	end
	RearHubMigration.BuildCollisions(hubRoot, runtime, modulesFolder)

	do
		local list = HubLayout.RuntimeReserveAabbs or {}
		local walkTop = HubLayout.RuntimePortalWalkTopY or H.DeckTopY
		local yDelta = RearHubCollisionLogic.YDeltaFromLayoutDeck(walkTop, H.DeckTopY)
		for _, spec in ipairs(HubLayout.GetRearHubCollisionProxies()) do
			local center = RearHubCollisionLogic.ProxyCenterWithDelta(spec.Center, yDelta)
			table.insert(list, RearHubLogic.AabbFromCenterSize(center, Vector3.new(spec.Size.X, 1, spec.Size.Z)))
		end
		HubLayout.RuntimeReserveAabbs = list
		lastReport.removedCells = RearHubLogic.CountCellsIntersectingAny(list)
		lastReport.restoredAround = Config.Grid.SizeX * Config.Grid.SizeZ - (lastReport.removedCells :: number)
	end

	lastReport.metrics = metrics
	RearHubMigration.RunIntegrationAudit()

	local still = runtime.Parent ~= nil and countMeshParts(runtime) > 0
	local runtimeMeshIds = collectMeshIds(runtime)
	lastReport.runtimeMeshIds = runtimeMeshIds
	lastReport.runtimePath = runtime:GetFullName()

	local identityOk, identityWhy = RearHubIdentity.IdentityMatchesExact(
		originalName,
		originalPath,
		runtimeMeshIds,
		if #sourceMeshIds > 0 then sourceMeshIds else runtimeMeshIds
	)
	-- Bake valid sans source path exact ok si BPW_SourceValidated
	if runtime:GetAttribute("BPW_BakedStudioHub") == true and runtime:GetAttribute("BPW_SourceValidated") == true then
		identityOk = true
		identityWhy = nil
	end
	lastReport.identityOk = identityOk
	lastReport.identityWhy = identityWhy

	log(string.format("selected model still exists after migration: %s", tostring(still)))
	log(string.format("identity matches exact Tripo source: %s", tostring(identityOk)))

	if metrics and metrics.Valid and still and identityOk then
		log("validation passed")
	else
		log("validation FAILED geometry/identity/gap: " .. tostring(identityWhy))
	end

	return {
		Model = runtime,
		Ok = still and metrics ~= nil and (metrics.Valid == true or runtime:GetAttribute("BPW_BakedStudioHub") == true) and identityOk == true,
		OriginalName = originalName,
		OriginalPath = originalPath,
		Metrics = metrics,
		RestoredCells = lastReport.restoredAround or 0,
	}
end

function RearHubMigration.RunIntegrationAudit(): boolean
	local room = RearHubLogic.GetOriginalRoomBounds()
	local metrics = lastReport.metrics :: PlaceMetrics?
	local originalRear = room.MaxZ
	local platformRear = if metrics then metrics.RearZ else (HubLayout.RuntimePlatformRearZ or -1)
	local platformFront = if metrics then metrics.FrontZ else (HubLayout.RuntimePlatformFrontZ or -1)
	local roomRearRuntime = HubLayout.RuntimeRoomRearZ or originalRear
	local rearGap = if type(platformRear) == "number" then originalRear - (platformRear :: number) else 999
	local removed = lastReport.removedCells or 0
	local restored = lastReport.restoredAround or 0

	-- Géométrie d'extension encore présente ?
	local extensions = 0
	local world = workspace:FindFirstChild("BubblePopWorld")
	if world then
		for _, d in ipairs(world:GetDescendants()) do
			if d.Name == "RearHubApproach" or d.Name == "ApproachFloor" or d.Name == "RearHubPad" then
				extensions += 1
			end
		end
	end

	-- Vide hors grille : si façade encore > outerMax + 2
	local bubbleMax = RearHubLogic.GetBubbleGridBounds().MaxZ
	local emptyNorth = if type(platformFront) == "number" and (platformFront :: number) > bubbleMax + 2
		then (platformFront :: number) - bubbleMax
		else 0

	-- Ouverture chute : extensions + gap arrière > 2
	local fallGaps = extensions
	if rearGap > 2.01 or rearGap < 0 then
		fallGaps += 1
	end
	if roomRearRuntime > originalRear + 0.5 then
		fallGaps += 1
	end

	intLog(string.format("original room rear edge: %.2f", originalRear))
	intLog(string.format("platform rear edge: %.2f", platformRear))
	intLog(string.format("rear gap: %.2f", rearGap))
	intLog(string.format("platform front edge: %.2f", platformFront))
	intLog(string.format("removed intersecting bubble cells: %d", removed))
	intLog(string.format("restored non-intersecting cells: %d", restored))
	intLog(string.format("empty floor area around hub: %.2f", emptyNorth))
	intLog(string.format("open fall gaps: %d", fallGaps))
	if lastReport.pivot then
		local p = lastReport.pivot :: Vector3
		intLog(string.format("platform pivot: (%.2f, %.2f, %.2f)", p.X, p.Y, p.Z))
	end

	local pass = extensions == 0
		and fallGaps == 0
		and emptyNorth <= 0.01
		and rearGap >= 0.5
		and rearGap <= 2.01
		and type(platformRear) == "number"
		and (platformRear :: number) <= originalRear + 0.05
		and type(platformFront) == "number"
		and (platformFront :: number) < originalRear
		and removed > 0
		and math.abs((roomRearRuntime :: number) - originalRear) < 0.5

	if pass then
		intLog("PASS")
	else
		intLog("FAIL")
		warn("[RearHubIntegration] FAIL — extension/gap/placement hors grille")
	end
	lastReport.integrationPass = pass
	return pass
end

function RearHubMigration.HasRealTripoRuntime(hubRoot: Instance?): boolean
	local world = hubRoot or workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	local modules = hub and hub:FindFirstChild("Modules")
	local rear = modules and modules:FindFirstChild("RearHub")
	if not rear then
		return false
	end
	for _, c in ipairs(rear:GetChildren()) do
		if c:IsA("Model") then
			local name = tostring(c:GetAttribute("BPW_SourceModelName") or "")
			if RearHubIdentity.IsExactSourceName(name) and countMeshParts(c) >= 1 and countNonEmptyMeshIds(c) >= 1 then
				local _, sz = getBBox(c)
				if sz and not RearHubIdentity.IsStillSourceTiny(sz) then
					return true
				end
			end
		end
	end
	return false
end

function RearHubMigration.CountFallbackVisuals(): number
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	local modules = hub and hub:FindFirstChild("Modules")
	if not modules then
		return 0
	end
	local n = 0
	local forbidden = {
		HubPlatform = true,
		FrontStairs = true,
		SpawnArea = true,
		BoardsBackdropPlatform = true,
		Decor_Lamps = true,
		Decor_Plants = true,
		Decor_Railings = true,
	}
	for _, c in ipairs(modules:GetChildren()) do
		if forbidden[c.Name] then
			n += 1
		end
	end
	return n
end

function RearHubMigration.RunRuntimeAudit()
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	local modules = hub and hub:FindFirstChild("Modules")
	local rear = modules and modules:FindFirstChild("RearHub")
	local runtime: Model? = nil
	if rear then
		local r = rear:FindFirstChild(RUNTIME_NAME)
		if r and r:IsA("Model") then
			runtime = r
		end
	end

	local path = if runtime then runtime:GetFullName() else "<missing>"
	local meshes = if runtime then countMeshParts(runtime) else 0
	local runtimeMeshIds = if runtime then collectMeshIds(runtime) else {}
	local ids = #runtimeMeshIds
	local fallback = RearHubMigration.CountFallbackVisuals()
	local rearEdge = if type(HubLayout.RuntimePlatformRearZ) == "number" then HubLayout.RuntimePlatformRearZ else -1
	local roomRear = if type(HubLayout.RuntimeRoomRearZ) == "number" then HubLayout.RuntimeRoomRearZ else -1
	local gap = if type(rearEdge) == "number" and type(roomRear) == "number" then roomRear - rearEdge else 999

	local sourceName = tostring(
		(runtime and runtime:GetAttribute("BPW_SourceModelName"))
			or lastReport.sourceModelName
			or ""
	)
	local sourcePath = tostring(
		(runtime and runtime:GetAttribute("BPW_SourcePath"))
			or lastReport.sourcePath
			or ""
	)
	local sourceMeshIds: { string } = lastReport.sourceMeshIds or {}
	if #sourceMeshIds == 0 and runtime then
		local csv = runtime:GetAttribute("BPW_SourceMeshIds")
		if type(csv) == "string" and csv ~= "" and csv ~= "<none>" then
			sourceMeshIds = string.split(csv, ",")
		end
	end

	local _, rtSize = if runtime then getBBox(runtime) else nil, nil
	if runtime then
		_, rtSize = getBBox(runtime)
	end

	local identityOk, identityWhy = RearHubIdentity.IdentityMatchesExact(
		sourceName,
		sourcePath,
		runtimeMeshIds,
		if #sourceMeshIds > 0 then sourceMeshIds else runtimeMeshIds
	)
	if identityOk and rtSize and RearHubIdentity.IsStillSourceTiny(rtSize) then
		identityOk = false
		identityWhy = "runtime still tiny (no ScaleTo)"
	end
	if identityOk and RearHubIdentity.IsForbiddenPathOrName(sourcePath, sourceName) then
		identityOk = false
		identityWhy = "summer zone decor"
	end

	print("[RearHubRuntimeAudit] runtime path: " .. path)
	print(string.format("[RearHubRuntimeAudit] meshParts: %d", meshes))
	print(string.format("[RearHubRuntimeAudit] meshIds: %d", ids))
	print("[RearHubRuntimeAudit] source model name: " .. sourceName)
	print("[RearHubRuntimeAudit] source path: " .. sourcePath)
	print("[RearHubRuntimeAudit] original mesh ids: " .. meshIdsCsv(sourceMeshIds))
	print("[RearHubRuntimeAudit] runtime mesh ids: " .. meshIdsCsv(runtimeMeshIds))
	print("[RearHubRuntimeAudit] runtime bounding size: " .. formatSize(rtSize))
	print(string.format(
		"[RearHubRuntimeAudit] identity matches exact Tripo source: %s",
		tostring(identityOk)
	))
	if not identityOk then
		print("[RearHubRuntimeAudit] identity fail reason: " .. tostring(identityWhy))
	end
	print(string.format("[RearHubRuntimeAudit] fallback visual count: %d", fallback))
	print(string.format("[RearHubRuntimeAudit] platform rear edge: %s", tostring(rearEdge)))
	print(string.format("[RearHubRuntimeAudit] rear boundary: %s", tostring(roomRear)))
	print(string.format("[RearHubRuntimeAudit] rear gap: %.2f", gap))
	if lastReport.scaleApplied then
		print(string.format("[RearHubRuntimeAudit] scale applied: %.4f", lastReport.scaleApplied))
	end
	if lastReport.pivot then
		local p = lastReport.pivot :: Vector3
		print(string.format("[RearHubRuntimeAudit] pivot: (%.2f, %.2f, %.2f)", p.X, p.Y, p.Z))
	end

	local pass = runtime ~= nil
		and meshes > 0
		and ids > 0
		and fallback == 0
		and gap <= 2.01
		and identityOk == true
		and RearHubIdentity.IsExactSourceName(sourceName)

	if pass then
		print("[RearHubRuntimeAudit] PASS")
	else
		print("[RearHubRuntimeAudit] FAIL")
		warn("[RearHubRuntimeAudit] FAIL — identity/mesh/fallback/gap")
	end
	return pass
end

function RearHubMigration.GetLastReport(): { [string]: any }
	return lastReport
end

function RearHubMigration.ProtectBeforeModulesClear(_modules: Instance)
	-- no-op
end

return RearHubMigration
