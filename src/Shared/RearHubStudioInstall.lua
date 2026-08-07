--!strict
-- Installation / bake Studio du hub Tripo (édition + serveur F5).
-- Aucune dépendance à Instances exclusives au serveur.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local HubLayout = require(Shared.HubLayout)
local RearHubLogic = require(Shared.RearHubLogic)
local RearHubIdentity = require(Shared.RearHubIdentity)
local RearHubCollisionLogic = require(Shared.RearHubCollisionLogic)

local RearHubStudioInstall = {}

local H = Config.Hub
local STUDIO_ASSETS = "StudioAssets"
local SOURCE_NAME = "TripoRearHubPlatform_Source"
local RUNTIME_NAME = "TripoRearHubPlatform"
local TAG = "BPW_RearHubPlatform"
local GEN = "RearHubStudioInstall"
local LOG = "[RearHubStudioInstaller] "

local function log(msg: string)
	print(LOG .. msg)
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

function RearHubStudioInstall.EnsureStudioAssets(): Folder
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

function RearHubStudioInstall.EnsureWorldHierarchy(): (Folder, Folder, Folder)
	local world = workspace:FindFirstChild("BubblePopWorld")
	if not (world and world:IsA("Folder")) then
		if world then
			world:Destroy()
		end
		world = Instance.new("Folder")
		world.Name = "BubblePopWorld"
		world.Parent = workspace
	end
	local hub = world:FindFirstChild("CentralHub")
	if not (hub and hub:IsA("Folder")) then
		if hub then
			hub:Destroy()
		end
		hub = Instance.new("Folder")
		hub.Name = "CentralHub"
		hub.Parent = world
	end
	local modules = hub:FindFirstChild("Modules")
	if not (modules and modules:IsA("Folder")) then
		if modules then
			modules:Destroy()
		end
		modules = Instance.new("Folder")
		modules.Name = "Modules"
		modules.Parent = hub
	end
	local rear = modules:FindFirstChild("RearHub")
	if not (rear and rear:IsA("Folder")) then
		if rear then
			rear:Destroy()
		end
		rear = Instance.new("Folder")
		rear.Name = "RearHub"
		rear:SetAttribute("BPW_RearHubFolder", true)
		rear.Parent = modules
	end
	return hub :: Folder, modules :: Folder, rear :: Folder
end

function RearHubStudioInstall.FindExactTripoSource(): (Model?, string?)
	local candidates: { RearHubIdentity.Candidate } = {}
	local modelByKey: { [string]: Model } = {}
	for _, root in ipairs({ workspace, ServerStorage, ReplicatedStorage }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == SOURCE_NAME or d.Name == RUNTIME_NAME then
				continue
			end
			if d:GetAttribute("BPW_BakedStudioHub") == true then
				continue
			end
			if not d:IsA("Model") then
				continue
			end
			local path = d:GetFullName()
			local rank = RearHubIdentity.SelectionRank(d.Name, path)
			if rank == nil then
				continue
			end
			local meshes = countMeshParts(d)
			local ids = collectMeshIds(d)
			if not RearHubIdentity.HasMinimumGeometry(meshes, #ids) then
				continue
			end
			local c: RearHubIdentity.Candidate = {
				Name = d.Name,
				Path = path,
				MeshParts = meshes,
				MeshIds = #ids,
				MeshIdList = ids,
			}
			table.insert(candidates, c)
			modelByKey[path] = d
		end
	end
	local chosen, _reason = RearHubIdentity.SelectBestCandidate(candidates)
	if chosen and modelByKey[chosen.Path] then
		return modelByKey[chosen.Path], chosen.Path
	end
	return nil, nil
end

function RearHubStudioInstall.GetBakedHub(): Model?
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	local modules = hub and hub:FindFirstChild("Modules")
	local rear = modules and modules:FindFirstChild("RearHub")
	if not rear then
		return nil
	end
	local m = rear:FindFirstChild(RUNTIME_NAME)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

function RearHubStudioInstall.IsValidBakedHub(model: Model): boolean
	if model:GetAttribute("BPW_HubRole") ~= "RearHubPlatform" then
		return false
	end
	if model:GetAttribute("BPW_SourceValidated") ~= true then
		return false
	end
	if model:GetAttribute("BPW_BakedStudioHub") ~= true then
		return false
	end
	if countMeshParts(model) < 1 or #collectMeshIds(model) < 1 then
		return false
	end
	local _, sz = getBBox(model)
	if not sz or RearHubIdentity.IsStillSourceTiny(sz) then
		return false
	end
	return true
end

function RearHubStudioInstall.ArchiveSource(model: Model, originalPath: string): Model
	local assets = RearHubStudioInstall.EnsureStudioAssets()
	local existing = assets:FindFirstChild(SOURCE_NAME)
	if existing and existing:IsA("Model") then
		existing:Destroy()
	end

	local originalName = model.Name
	local meshIds = collectMeshIds(model)
	local meshCount = countMeshParts(model)
	local _, sz = getBBox(model)

	local archive: Model = model:Clone()
	archive.Name = SOURCE_NAME
	archive:SetAttribute("BPW_TripoSource", true)
	archive:SetAttribute("BPW_SourceModelName", originalName)
	archive:SetAttribute("BPW_SourcePath", originalPath)
	archive:SetAttribute("BPW_SourceMeshCount", meshCount)
	archive:SetAttribute("BPW_SourceValidated", true)
	archive:SetAttribute("BPW_SourceMeshIds", meshIdsCsv(meshIds))
	archive:SetAttribute("BPW_HubRole", "RearHubPlatform")
	if sz then
		archive:SetAttribute("BPW_SourceSizeX", sz.X)
		archive:SetAttribute("BPW_SourceSizeY", sz.Y)
		archive:SetAttribute("BPW_SourceSizeZ", sz.Z)
	end
	for _, d in ipairs(archive:GetDescendants()) do
		if d:IsA("BasePart") then
			(d :: BasePart).Anchored = true
		end
	end
	archive.Parent = assets

	-- Retirer le modèle Workspace (source n'est plus flottante)
	if model.Parent and model.Parent ~= assets then
		log("removed obsolete floating object: " .. model:GetFullName())
		model:Destroy()
	end

	log("source archived: ServerStorage." .. STUDIO_ASSETS .. "." .. SOURCE_NAME)
	return archive
end

function RearHubStudioInstall.ScaleModelToHub(model: Model): number
	local _, before = getBBox(model)
	if not before then
		return 1
	end
	local targetWidth = H.DeckHalfX * 2
	local targetDepth = H.DeckHalfZ * 2
	local uniform = RearHubIdentity.ComputeUniformScale(before, targetWidth, targetDepth)
	local currentScale = 1
	pcall(function()
		currentScale = model:GetScale()
	end)
	local applied = currentScale * uniform
	local ok = pcall(function()
		model:ScaleTo(applied)
	end)
	if not ok then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				(d :: BasePart).Size = (d :: BasePart).Size * uniform
			end
		end
		applied = uniform
	end
	log(string.format("scale applied: %.4f", applied))
	local _, after = getBBox(model)
	log(string.format("size after scale: %s", formatSize(after)))
	return applied
end

function RearHubStudioInstall.PlaceModelInOriginalRoom(model: Model): (Vector3?, number?, number?)
	local room = RearHubLogic.GetOriginalRoomBounds()
	local rearMargin = RearHubLogic.GetRearMargin()
	local desiredRearZ = room.MaxZ - rearMargin

	model:PivotTo(CFrame.new(0, H.DeckTopY, 0))
	local cf1, sz1 = getBBox(model)
	if not (cf1 and sz1) then
		return nil, nil, nil
	end
	local pivot = model:GetPivot().Position
	local pivotToRear = math.max(0.1, (cf1.Position.Z + sz1.Z / 2) - pivot.Z)

	local floorY = Config.Grid.Origin.Y - Config.Grid.BubbleSize.Y * 0.35
	local bottomY = cf1.Position.Y - sz1.Y / 2
	local lift = floorY - bottomY

	local centerZ = desiredRearZ - pivotToRear
	model:PivotTo(CFrame.new(Config.Grid.Origin.X, pivot.Y + lift, centerZ))

	local cf2, sz2 = getBBox(model)
	if cf2 and sz2 then
		local curRear = cf2.Position.Z + sz2.Z / 2
		model:PivotTo(model:GetPivot() + Vector3.new(0, 0, desiredRearZ - curRear))
	end

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
		return nil, nil, nil
	end
	local frontZ = cf3.Position.Z - sz3.Z / 2
	local rearZ = cf3.Position.Z + sz3.Z / 2
	local pivotPos = model:GetPivot().Position

	HubLayout.Center = Vector3.new(Config.Grid.Origin.X, H.DeckTopY, pivotPos.Z)
	HubLayout.FrontSign = -1
	HubLayout.RuntimePlatformFrontZ = frontZ
	HubLayout.RuntimePlatformRearZ = rearZ
	HubLayout.RuntimeRoomRearZ = room.MaxZ

	log(string.format("final pivot: (%.2f, %.2f, %.2f)", pivotPos.X, pivotPos.Y, pivotPos.Z))
	return pivotPos, frontZ, rearZ
end

function RearHubStudioInstall.TagBakedHub(model: Model, originalName: string, originalPath: string, meshIds: { string })
	model.Name = RUNTIME_NAME
	model:SetAttribute("BPW_HubRole", "RearHubPlatform")
	model:SetAttribute("BPW_BakedStudioHub", true)
	model:SetAttribute("BPW_SourceValidated", true)
	model:SetAttribute("BPW_SourceModelName", originalName)
	model:SetAttribute("BPW_SourcePath", originalPath)
	model:SetAttribute("BPW_SourceMeshIds", meshIdsCsv(meshIds))
	model:SetAttribute("BPW_TripoSource", false)
	model:SetAttribute("BPW_RearHubManaged", true)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = d :: BasePart
			p.Anchored = true
			p.CanTouch = false
			p.CanQuery = true
			-- Mesh Tripo strictement visuel (collisions = ManualCollisionRig)
			p.CanCollide = false
			p.CollisionGroup = "Default"
		end
	end
	pcall(function()
		CollectionService:AddTag(model, TAG)
	end)
end

function RearHubStudioInstall.InitManualTransitAnchor(_hubModel: Model, _forceReset: boolean?): BasePart
	local TransitAnchorLogic = require(script.Parent.TransitAnchorLogic)
	local name = TransitAnchorLogic.NAME
	local existing = workspace:FindFirstChild(name)

	if existing and existing:IsA("BasePart") then
		local a = existing :: BasePart
		-- Migration unique : ancienne pose plugin (0,8,19)/(2,4,2) uniquement.
		local migratedFlag = a:GetAttribute(TransitAnchorLogic.LEGACY_MIGRATED_ATTR) == true
		if TransitAnchorLogic.ShouldMigrateLegacyPose(migratedFlag, a.Size, a.Position) then
			a.Size = TransitAnchorLogic.FALLBACK_SIZE
			a.CFrame = TransitAnchorLogic.FallbackCFrame()
			a:SetAttribute(TransitAnchorLogic.LEGACY_MIGRATED_ATTR, true)
			log(string.format(
				"manual transit LEGACY migrated → (%.2f, %.2f, %.2f) size=(%.2f,%.2f,%.2f)",
				a.Position.X,
				a.Position.Y,
				a.Position.Z,
				a.Size.X,
				a.Size.Y,
				a.Size.Z
			))
		else
			log(string.format(
				"manual transit anchor PRESERVED (no CFrame write): (%.2f, %.2f, %.2f) size=(%.2f,%.2f,%.2f)",
				a.Position.X,
				a.Position.Y,
				a.Position.Z,
				a.Size.X,
				a.Size.Y,
				a.Size.Z
			))
		end
		a:SetAttribute(TransitAnchorLogic.MANUAL_ATTR, true)
		a:SetAttribute(TransitAnchorLogic.INIT_ATTR, true)
		a.Anchored = true
		a.CanCollide = false
		a.CanTouch = false
		a.CanQuery = true
		a.CastShadow = false
		a.Transparency = 0.45
		a.Color = Color3.fromRGB(255, 0, 255)
		a.Material = Enum.Material.Neon
		-- ensure prompt
		local attach = a:FindFirstChild("PromptAttachment")
		if not (attach and attach:IsA("Attachment")) then
			if attach then
				attach:Destroy()
			end
			attach = Instance.new("Attachment")
			attach.Name = "PromptAttachment"
			attach.Parent = a
		end
		if not a:FindFirstChild("BubbleTransitPrompt", true) then
			local pr = Instance.new("ProximityPrompt")
			pr.Name = "BubbleTransitPrompt"
			pr.RequiresLineOfSight = false
			pr.HoldDuration = 0
			pr.MaxActivationDistance = 8
			pr.ActionText = "Travel"
			pr.ObjectText = "Bubble Transit"
			pr:SetAttribute("TransitId", "LobbyTransit")
			pr.Parent = attach
		end
		return a
	end

	if existing then
		existing:Destroy()
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Size = TransitAnchorLogic.FALLBACK_SIZE
	p.CFrame = TransitAnchorLogic.FallbackCFrame()
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.CastShadow = false
	p.Transparency = 0.45
	p.Color = Color3.fromRGB(255, 0, 255)
	p.Material = Enum.Material.Neon
	p:SetAttribute(TransitAnchorLogic.MANUAL_ATTR, true)
	p:SetAttribute(TransitAnchorLogic.INIT_ATTR, true)
	p:SetAttribute("BPW_Role", "BubbleTransitInteractionAnchor")
	p.Parent = workspace
	local attach = Instance.new("Attachment")
	attach.Name = "PromptAttachment"
	attach.Parent = p
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "BubbleTransitPrompt"
	pr.RequiresLineOfSight = false
	pr.HoldDuration = 0
	pr.MaxActivationDistance = 8
	pr.ActionText = "Travel"
	pr.ObjectText = "Bubble Transit"
	pr:SetAttribute("TransitId", "LobbyTransit")
	pr.Parent = attach
	log("manual transit anchor created FALLBACK only (place in Studio, then save place file)")
	return p
end

function RearHubStudioInstall.InitSpawnLocation(hubRoot: Folder, hubModel: Model, forceReset: boolean?): SpawnLocation
	local existing = hubRoot:FindFirstChild("HubSpawnLocation")
	if not (existing and existing:IsA("SpawnLocation")) then
		local fn = hubRoot:FindFirstChild("HubFunction")
		local nested = fn and fn:FindFirstChild("HubSpawnLocation")
		if nested and nested:IsA("SpawnLocation") then
			nested.Parent = hubRoot
			existing = nested
		else
			if existing then
				existing:Destroy()
			end
			local sl = Instance.new("SpawnLocation")
			sl.Name = "HubSpawnLocation"
			sl.Parent = hubRoot
			existing = sl
		end
	end
	local sl = existing :: SpawnLocation
	sl.Anchored = true
	sl.CanCollide = false
	sl.CanTouch = false
	sl.Neutral = true
	sl.Duration = 0
	sl.Enabled = true
	sl.Size = Vector3.new(6, 1, 6)
	-- Édition : semi-visible. Runtime → Transparency 1.
	sl.Transparency = 0.5
	sl.Material = Enum.Material.SmoothPlastic
	sl.Color = Color3.fromRGB(80, 200, 120)

	local already = sl:GetAttribute("BPW_SpawnManualInitialized") == true
		or sl:GetAttribute("BPW_ManualPlacement") == true
	if not already or forceReset == true then
		local frontZ = HubLayout.RuntimePlatformFrontZ or HubLayout.Center.Z - 10
		local rearZ = HubLayout.RuntimePlatformRearZ or HubLayout.Center.Z + 10
		local xz = RearHubCollisionLogic.SafeSpawnXZ(HubLayout.Center, frontZ :: number, rearZ :: number, 10)
		local cf, sz = getBBox(hubModel)
		local topY = if cf and sz then cf.Position.Y + sz.Y * 0.15 else H.DeckTopY
		if cf and sz then
			-- surface approx centrale deck
			topY = cf.Position.Y
		end
		local cy = RearHubCollisionLogic.SpawnCenterY(topY, sl.Size.Y)
		sl.CFrame = CFrame.new(xz.X, cy, xz.Z)
		sl:SetAttribute("BPW_SpawnManualInitialized", true)
		sl:SetAttribute("BPW_ManualPlacement", true)
		sl:SetAttribute("BPW_Role", "HubSpawnLocation")
		log(string.format("spawn initialized: (%.2f, %.2f, %.2f)", sl.Position.X, sl.Position.Y, sl.Position.Z))
	else
		local preserved = sl.CFrame
		sl:SetAttribute("BPW_SpawnManualInitialized", true)
		sl:SetAttribute("BPW_ManualPlacement", true)
		sl:SetAttribute("BPW_Role", "HubSpawnLocation")
		sl.CFrame = preserved
		log(string.format("spawn preserved: (%.2f, %.2f, %.2f)", sl.Position.X, sl.Position.Y, sl.Position.Z))
	end
	return sl
end

function RearHubStudioInstall.RemoveObsoleteFloatingObjects(): number
	local removed = 0
	local doomedNames = {
		["3d stage arena prop"] = true,
		["3D Stage Arena Prop"] = true,
	}
	-- Source encore dans Workspace
	for _, child in ipairs(workspace:GetChildren()) do
		local lname = string.lower(child.Name)
		if doomedNames[child.Name]
			or string.find(lname, "3d stage arena prop", 1, true)
			or string.find(lname, "stage arena prop", 1, true)
		then
			if child:IsA("Model") or child:IsA("BasePart") then
				log("removed obsolete floating object: " .. child:GetFullName())
				child:Destroy()
				removed += 1
			end
		end
	end

	-- Spawn icons orphelins / pieces grises orphelines hors hiérarchie hub
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d.Name ~= "HubSpawnLocation" and d.Name ~= "GameRoomSpawnLocation" then
			local path = d:GetFullName()
			if not string.find(path, "BubblePopWorld", 1, true)
				and not string.find(path, "GameRoom", 1, true)
			then
				log("removed obsolete floating object: " .. path)
				d:Destroy()
				removed += 1
			end
		end
	end

	-- Anciens doublons runtime non bakés sous RearHub (sauf le hub bake)
	local baked = RearHubStudioInstall.GetBakedHub()
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	local modules = hub and hub:FindFirstChild("Modules")
	local rear = modules and modules:FindFirstChild("RearHub")
	if rear then
		for _, c in ipairs(rear:GetChildren()) do
			if c:IsA("Model") and c.Name == RUNTIME_NAME and c ~= baked then
				if c:GetAttribute("BPW_BakedStudioHub") ~= true then
					log("removed obsolete floating object: " .. c:GetFullName())
					c:Destroy()
					removed += 1
				end
			end
		end
	end

	log(string.format("obsolete floating objects removed: %d", removed))
	return removed
end

export type InstallResult = {
	Ok: boolean,
	BakedPath: string?,
	SourcePath: string?,
	Pivot: Vector3?,
	Scale: number?,
}

--- Installation complète (plugin Studio / Command bar).
function RearHubStudioInstall.RunFullInstall(forceResetPlacements: boolean?): InstallResult
	local found, foundPath = RearHubStudioInstall.FindExactTripoSource()
	local assetsFolder = ServerStorage:FindFirstChild(STUDIO_ASSETS)
	local archiveInst = assetsFolder and assetsFolder:FindFirstChild(SOURCE_NAME)

	local sourceModel: Model? = nil
	local originalPath: string? = nil
	local originalName: string = RearHubIdentity.EXACT_SOURCE_NAME

	if found and foundPath then
		log("exact Tripo source found: " .. foundPath)
		sourceModel = RearHubStudioInstall.ArchiveSource(found, foundPath)
		originalPath = foundPath
		originalName = found.Name
	elseif archiveInst and archiveInst:IsA("Model") then
		sourceModel = archiveInst
		originalPath = tostring(archiveInst:GetAttribute("BPW_SourcePath") or archiveInst:GetFullName())
		originalName = tostring(archiveInst:GetAttribute("BPW_SourceModelName") or originalName)
		log("using archived source: " .. originalPath)
	else
		warn(LOG .. "FATAL: no Tripo source found (Workspace.3d stage arena prop or archive)")
		return { Ok = false, BakedPath = nil, SourcePath = nil, Pivot = nil, Scale = nil }
	end

	local meshIds = collectMeshIds(sourceModel)
	if #meshIds < 1 then
		warn(LOG .. "FATAL: source has no MeshIds")
		return { Ok = false, BakedPath = nil, SourcePath = originalPath, Pivot = nil, Scale = nil }
	end

	local hubRoot, _modules, rear = RearHubStudioInstall.EnsureWorldHierarchy()

	-- Remplacer bake existant (idempotent refresh)
	local old = rear:FindFirstChild(RUNTIME_NAME)
	if old then
		old:Destroy()
	end

	local baked = sourceModel:Clone()
	baked.Name = RUNTIME_NAME
	baked.Parent = rear
	RearHubStudioInstall.TagBakedHub(baked, originalName, originalPath or "", meshIds)

	local scale = RearHubStudioInstall.ScaleModelToHub(baked)
	local pivot, _f, _r = RearHubStudioInstall.PlaceModelInOriginalRoom(baked)
	RearHubStudioInstall.TagBakedHub(baked, originalName, originalPath or "", meshIds)

	log("baked hub created: " .. baked:GetFullName())

	RearHubStudioInstall.InitManualTransitAnchor(baked, forceResetPlacements)
	RearHubStudioInstall.InitSpawnLocation(hubRoot, baked, forceResetPlacements)

	-- Collisions : rig manuel persistant (crée uniquement les pièces manquantes)
	local ManualRig = require(Shared.RearHubManualRig)
	local ensured = ManualRig.EnsureRig(true)
	if ensured then
		log(string.format(
			"manual collision rig: %s (created=%d preserved=%d)",
			ensured.Rig:GetFullName(),
			#ensured.Created,
			#ensured.Preserved
		))
	end

	local n = RearHubStudioInstall.RemoveObsoleteFloatingObjects()
	log(string.format("obsolete floating objects removed: %d", n))
	log("installation complete")

	return {
		Ok = true,
		BakedPath = baked:GetFullName(),
		SourcePath = "ServerStorage." .. STUDIO_ASSETS .. "." .. SOURCE_NAME,
		Pivot = pivot,
		Scale = scale,
	}
end

function RearHubStudioInstall.CollectMetricsFromBaked(model: Model): {
	Pivot: Vector3,
	FrontZ: number,
	RearZ: number,
	RoomRearZ: number,
	RearGap: number,
	Size: Vector3?,
}?
	local room = RearHubLogic.GetOriginalRoomBounds()
	local cf, sz = getBBox(model)
	if not (cf and sz) then
		return nil
	end
	local frontZ = cf.Position.Z - sz.Z / 2
	local rearZ = cf.Position.Z + sz.Z / 2
	local pivotPos = model:GetPivot().Position
	HubLayout.Center = Vector3.new(Config.Grid.Origin.X, H.DeckTopY, pivotPos.Z)
	HubLayout.FrontSign = -1
	HubLayout.RuntimePlatformFrontZ = frontZ
	HubLayout.RuntimePlatformRearZ = rearZ
	HubLayout.RuntimeRoomRearZ = room.MaxZ

	local platAabb = RearHubLogic.AabbFromCenterSize(cf.Position, Vector3.new(sz.X, 1, sz.Z))
	local landingAabb = {
		MinX = HubLayout.Center.X - H.Stairs.Width / 2 - 1,
		MaxX = HubLayout.Center.X + H.Stairs.Width / 2 + 1,
		MinZ = frontZ - 3,
		MaxZ = frontZ,
	}
	HubLayout.RuntimeReserveAabbs = { platAabb, landingAabb }

	return {
		Pivot = pivotPos,
		FrontZ = frontZ,
		RearZ = rearZ,
		RoomRearZ = room.MaxZ,
		RearGap = room.MaxZ - rearZ,
		Size = sz,
	}
end

return RearHubStudioInstall
