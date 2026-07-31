--!strict
-- Scan / rejet / reconstruction whitelist / empreinte pour décors Summer.

local CollectionService = game:GetService("CollectionService")

local SummerDecorConfig = require(script.Parent.SummerDecorConfig)

local SummerDecorSecurity = {}

SummerDecorSecurity.FORBIDDEN_CLASSES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
}

SummerDecorSecurity.REMOVE_CLASSES = {
	RemoteEvent = true,
	RemoteFunction = true,
	UnreliableRemoteEvent = true,
	BindableEvent = true,
	BindableFunction = true,
	ProximityPrompt = true,
	ClickDetector = true,
	TouchTransmitter = true,
	Sound = true,
	Humanoid = true,
	AnimationController = true,
	Animator = true,
	ParticleEmitter = true,
	Trail = true,
	Beam = true,
	BodyVelocity = true,
	BodyForce = true,
	VectorForce = true,
	LinearVelocity = true,
	AngularVelocity = true,
	Seat = true,
	VehicleSeat = true,
}

SummerDecorSecurity.ALLOWED_CLASSES = {
	Model = true,
	Folder = true,
	Part = true,
	MeshPart = true,
	UnionOperation = true,
	TrussPart = true,
	WedgePart = true,
	CornerWedgePart = true,
	SpecialMesh = true,
	BlockMesh = true,
	CylinderMesh = true,
	Decal = true,
	Texture = true,
	Attachment = true,
	Weld = true,
	WeldConstraint = true,
	Motor6D = true,
	PointLight = true,
	SpotLight = true,
	SurfaceLight = true,
}

local GENERATED_BY = "SummerDecorAssetImporter"

local function fullPath(inst: Instance): string
	local ok, path = pcall(function()
		return inst:GetFullName()
	end)
	if ok and type(path) == "string" then
		return path
	end
	return inst.Name
end

function SummerDecorSecurity.CountInstances(root: Instance): number
	return 1 + #root:GetDescendants()
end

function SummerDecorSecurity.FindForbiddenScripts(root: Instance): { string }
	local paths: { string } = {}
	local function consider(inst: Instance)
		if SummerDecorSecurity.FORBIDDEN_CLASSES[inst.ClassName] then
			table.insert(paths, fullPath(inst))
		end
	end
	consider(root)
	for _, d in ipairs(root:GetDescendants()) do
		consider(d)
	end
	return paths
end

local function clearAttributesAndTags(inst: Instance)
	for name in pairs(inst:GetAttributes()) do
		inst:SetAttribute(name, nil)
	end
	for _, tag in ipairs(CollectionService:GetTags(inst)) do
		CollectionService:RemoveTag(inst, tag)
	end
end

local function copyBasePartProps(src: BasePart, dst: BasePart)
	dst.CFrame = src.CFrame
	dst.Size = src.Size
	dst.Color = src.Color
	dst.Material = src.Material
	dst.Transparency = src.Transparency
	dst.Reflectance = src.Reflectance
	dst.Anchored = true
	dst.CanCollide = false
	dst.CanTouch = false
	dst.CanQuery = false
	dst.Massless = true
	dst.CastShadow = false
	if src:IsA("Part") and dst:IsA("Part") then
		dst.Shape = src.Shape
	end
	if src:IsA("MeshPart") and dst:IsA("MeshPart") then
		pcall(function()
			(dst :: MeshPart).MeshId = (src :: MeshPart).MeshId
		end)
		pcall(function()
			(dst :: MeshPart).TextureID = (src :: MeshPart).TextureID
		end)
	end
end

local function copyLightProps(src: Instance, dst: Instance)
	if src:IsA("Light") and dst:IsA("Light") then
		dst.Brightness = src.Brightness
		dst.Color = src.Color
		dst.Range = src.Range
		dst.Shadows = src.Shadows
		dst.Enabled = src.Enabled
	end
	if src:IsA("SpotLight") and dst:IsA("SpotLight") then
		dst.Angle = src.Angle
		dst.Face = src.Face
	end
	if src:IsA("SurfaceLight") and dst:IsA("SurfaceLight") then
		dst.Angle = src.Angle
		dst.Face = src.Face
	end
end

local function copyMeshProps(src: Instance, dst: Instance)
	if src:IsA("SpecialMesh") and dst:IsA("SpecialMesh") then
		dst.MeshType = src.MeshType
		dst.MeshId = src.MeshId
		dst.TextureId = src.TextureId
		dst.Scale = src.Scale
		dst.Offset = src.Offset
	elseif src:IsA("DataModelMesh") and dst:IsA("DataModelMesh") then
		dst.Scale = src.Scale
		dst.Offset = src.Offset
	end
end

local function copyDecalProps(src: Instance, dst: Instance)
	if src:IsA("Decal") and dst:IsA("Decal") then
		dst.Texture = src.Texture
		dst.Face = src.Face
		dst.Transparency = src.Transparency
		dst.Color3 = src.Color3
	elseif src:IsA("Texture") and dst:IsA("Texture") then
		dst.Texture = src.Texture
		dst.Face = src.Face
		dst.Transparency = src.Transparency
		dst.Color3 = src.Color3
		dst.StudsPerTileU = src.StudsPerTileU
		dst.StudsPerTileV = src.StudsPerTileV
	end
end

local function copyAttachmentProps(src: Attachment, dst: Attachment)
	dst.CFrame = src.CFrame
	dst.Visible = false
end

local function shouldSkipPart(part: BasePart, modelCenter: Vector3, maxSize: number): boolean
	if part.Transparency >= 1 then
		return true
	end
	if (part.Position - modelCenter).Magnitude > 500 then
		return true
	end
	local longest = math.max(part.Size.X, part.Size.Y, part.Size.Z)
	if maxSize > 0 and longest > maxSize * 8 then
		return true
	end
	return false
end

local function computeModelCenterAndMax(root: Instance): (Vector3, number)
	local sum = Vector3.zero
	local count = 0
	local maxSize = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			sum += d.Position
			count += 1
			maxSize = math.max(maxSize, d.Size.X, d.Size.Y, d.Size.Z)
		end
	end
	if root:IsA("BasePart") then
		sum += root.Position
		count += 1
		maxSize = math.max(maxSize, root.Size.X, root.Size.Y, root.Size.Z)
	end
	if count == 0 then
		return Vector3.zero, 1
	end
	return sum / count, maxSize
end

local function fingerprintChunk(inst: Instance): string
	local bits = { inst.ClassName, inst.Name }
	if inst:IsA("BasePart") then
		local p = inst :: BasePart
		table.insert(bits, string.format("%.3f,%.3f,%.3f", p.Size.X, p.Size.Y, p.Size.Z))
		table.insert(bits, string.format("%.3f,%.3f,%.3f", p.Position.X, p.Position.Y, p.Position.Z))
		table.insert(bits, string.format("%.3f", p.Transparency))
		table.insert(bits, tostring(p.Material))
	elseif inst:IsA("SpecialMesh") then
		table.insert(bits, (inst :: SpecialMesh).MeshId)
		table.insert(bits, (inst :: SpecialMesh).TextureId)
	elseif inst:IsA("MeshPart") then
		pcall(function()
			table.insert(bits, (inst :: MeshPart).MeshId)
		end)
	elseif inst:IsA("Light") then
		local L = inst :: Light
		table.insert(bits, string.format("%.3f", L.Brightness))
		table.insert(bits, string.format("%.3f", L.Range))
	end
	return table.concat(bits, "|")
end

function SummerDecorSecurity.ComputeFingerprint(cleanRoot: Instance): string
	local chunks: { string } = {}
	table.insert(chunks, fingerprintChunk(cleanRoot))
	for _, d in ipairs(cleanRoot:GetDescendants()) do
		table.insert(chunks, fingerprintChunk(d))
	end
	table.sort(chunks)
	local joined = table.concat(chunks, ";")
	-- Hash simple stable (djb2)
	local hash = 5381
	for i = 1, #joined do
		hash = bit32.band((hash * 33 + string.byte(joined, i)), 0x7fffffff)
	end
	return string.format("%08x:%d", hash, #chunks)
end

local function trySetSandboxed(inst: Instance)
	pcall(function()
		(inst :: any).Sandboxed = true
	end)
end

function SummerDecorSecurity.RebuildWhitelisted(sourceRoot: Instance, assetId: number): (Model?, string?)
	trySetSandboxed(sourceRoot)
	for _, d in ipairs(sourceRoot:GetDescendants()) do
		trySetSandboxed(d)
	end

	local scripts = SummerDecorSecurity.FindForbiddenScripts(sourceRoot)
	if #scripts > 0 then
		return nil, "executable_code"
	end

	local center, maxSize = computeModelCenterAndMax(sourceRoot)
	local clean = Instance.new("Model")
	clean.Name = "Sanitized_" .. tostring(assetId)

	local map: { [Instance]: Instance } = {}
	local removed = 0
	local originalCount = SummerDecorSecurity.CountInstances(sourceRoot)

	local function canCopy(inst: Instance): boolean
		if SummerDecorSecurity.FORBIDDEN_CLASSES[inst.ClassName] then
			return false
		end
		if SummerDecorSecurity.REMOVE_CLASSES[inst.ClassName] then
			return false
		end
		if not SummerDecorSecurity.ALLOWED_CLASSES[inst.ClassName] then
			return false
		end
		if inst:IsA("BasePart") and shouldSkipPart(inst, center, maxSize) then
			return false
		end
		return true
	end

	-- Parcours ordre: parents avant enfants (GetDescendants est profondeur d'abord;
	-- on reconstruit via pile parentée en listant tous puis triant par profondeur).
	local ordered: { Instance } = { sourceRoot }
	for _, d in ipairs(sourceRoot:GetDescendants()) do
		table.insert(ordered, d)
	end

	local function materialize(src: Instance, dstParent: Instance): Instance?
		if not canCopy(src) then
			removed += 1
			return nil
		end
		local okClone, cloneOrErr = pcall(function()
			return Instance.new(src.ClassName)
		end)
		if not okClone or typeof(cloneOrErr) ~= "Instance" then
			removed += 1
			return nil
		end
		local clone = cloneOrErr :: Instance
		clone.Name = src.Name
		clearAttributesAndTags(clone)

		if src:IsA("BasePart") and clone:IsA("BasePart") then
			copyBasePartProps(src, clone)
		elseif src:IsA("Light") then
			copyLightProps(src, clone)
		elseif src:IsA("SpecialMesh") or src:IsA("DataModelMesh") then
			copyMeshProps(src, clone)
		elseif src:IsA("Decal") or src:IsA("Texture") then
			copyDecalProps(src, clone)
		elseif src:IsA("Attachment") and clone:IsA("Attachment") then
			copyAttachmentProps(src, clone)
		end

		clone.Parent = dstParent
		map[src] = clone
		return clone
	end

	map[sourceRoot] = clean
	-- Racine non-container : la recopier comme enfant du Model propre.
	if not sourceRoot:IsA("Model") and not sourceRoot:IsA("Folder") then
		materialize(sourceRoot, clean)
	end

	for _, src in ipairs(ordered) do
		if src == sourceRoot then
			continue
		end
		local srcParent = src.Parent
		local dstParent = if srcParent then map[srcParent] else nil
		if not dstParent then
			removed += 1
			continue
		end
		materialize(src, dstParent)
	end

	-- Remap contraintes après les parts
	for src, clone in pairs(map) do
		if src:IsA("WeldConstraint") and clone:IsA("WeldConstraint") then
			local p0 = src.Part0 and map[src.Part0]
			local p1 = src.Part1 and map[src.Part1]
			if p0 and p0:IsA("BasePart") and p1 and p1:IsA("BasePart") then
				clone.Part0 = p0
				clone.Part1 = p1
			else
				clone:Destroy()
				map[src] = nil
				removed += 1
			end
		elseif src:IsA("Weld") and clone:IsA("Weld") then
			local p0 = src.Part0 and map[src.Part0]
			local p1 = src.Part1 and map[src.Part1]
			if p0 and p0:IsA("BasePart") and p1 and p1:IsA("BasePart") then
				clone.Part0 = p0
				clone.Part1 = p1
				clone.C0 = src.C0
				clone.C1 = src.C1
			else
				clone:Destroy()
				map[src] = nil
				removed += 1
			end
		elseif src:IsA("Motor6D") and clone:IsA("Motor6D") then
			local p0 = src.Part0 and map[src.Part0]
			local p1 = src.Part1 and map[src.Part1]
			if p0 and p0:IsA("BasePart") and p1 and p1:IsA("BasePart") then
				clone.Part0 = p0
				clone.Part1 = p1
				clone.C0 = src.C0
				clone.C1 = src.C1
			else
				clone:Destroy()
				map[src] = nil
				removed += 1
			end
		end
	end

	local fingerprint = SummerDecorSecurity.ComputeFingerprint(clean)
	clearAttributesAndTags(clean)
	clean:SetAttribute("AssetId", assetId)
	clean:SetAttribute("SanitizedSummerAsset", true)
	clean:SetAttribute("GeneratedBy", GENERATED_BY)
	clean:SetAttribute("SanitizerVersion", SummerDecorConfig.Security.SanitizerVersion)
	clean:SetAttribute("ImportedAt", os.time())
	clean:SetAttribute("SanitizedFingerprint", fingerprint)

	local valid, reason = SummerDecorSecurity.ValidateCleanModel(clean)
	if not valid then
		clean:Destroy()
		return nil, reason or "validation_failed"
	end

	-- Stash counts on attributes for importer reports (not original attrs)
	clean:SetAttribute("_OriginalCount", originalCount)
	clean:SetAttribute("_RemovedCount", removed)
	clean:SetAttribute("_CleanCount", SummerDecorSecurity.CountInstances(clean))

	return clean, nil
end

function SummerDecorSecurity.ValidateCleanModel(clean: Instance): (boolean, string?)
	local function checkOne(inst: Instance): (boolean, string?)
		if inst:IsA("LuaSourceContainer") then
			return false, "Executable object remained after sanitization"
		end
		if SummerDecorSecurity.FORBIDDEN_CLASSES[inst.ClassName] then
			return false, "Executable object remained after sanitization"
		end
		if not SummerDecorSecurity.ALLOWED_CLASSES[inst.ClassName] then
			return false, "Unexpected class remained: " .. inst.ClassName
		end
		if SummerDecorSecurity.REMOVE_CLASSES[inst.ClassName] then
			return false, "Unexpected class remained: " .. inst.ClassName
		end
		return true, nil
	end

	local okRoot, errRoot = checkOne(clean)
	if not okRoot then
		return false, errRoot
	end
	for _, d in ipairs(clean:GetDescendants()) do
		local ok, err = checkOne(d)
		if not ok then
			return false, err
		end
	end
	return true, nil
end

function SummerDecorSecurity.LogScanHeader(assetId: number)
	print(("[SummerDecorSecurity] Scanning asset: %d"):format(assetId))
end

function SummerDecorSecurity.LogCounts(original: number, removed: number, cleanCount: number)
	print(("[SummerDecorSecurity] Original instances: %d"):format(original))
	print(("[SummerDecorSecurity] Removed instances: %d"):format(removed))
	print(("[SummerDecorSecurity] Clean instances: %d"):format(cleanCount))
end

function SummerDecorSecurity.LogSanitized(assetId: number)
	print(("[SummerDecorSecurity] SANITIZED asset: %d"):format(assetId))
end

function SummerDecorSecurity.LogPending(assetId: number)
	print(("[SummerDecorSecurity] PENDING MANUAL APPROVAL: %d"):format(assetId))
end

function SummerDecorSecurity.LogRejected(assetId: number, reason: string?)
	print(("[SummerDecorSecurity] REJECTED asset: %d"):format(assetId))
	if reason == "executable_code" or reason == nil then
		print("[SummerDecorSecurity] REJECTED asset ID: executable code detected")
	end
end

function SummerDecorSecurity.LogScriptPaths(paths: { string })
	for _, path in ipairs(paths) do
		print(("[SummerDecorSecurity] Found Script at: %s"):format(path))
	end
end

function SummerDecorSecurity.LogUpdateRequiresReview(assetId: number)
	print(("[SummerDecorSecurity] UPDATE REQUIRES REVIEW: %d"):format(assetId))
end

function SummerDecorSecurity.LogPromoted(assetId: number)
	print(("[SummerDecorSecurity] PROMOTED approved asset: %d"):format(assetId))
end

return SummerDecorSecurity
