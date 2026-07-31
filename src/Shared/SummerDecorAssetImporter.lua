--!strict
-- Orchestration Studio Edit : import → split props → pending ; promote par TemplateKey.

local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local SummerDecorConfig = require(script.Parent.SummerDecorConfig)
local SummerDecorSecurity = require(script.Parent.SummerDecorSecurity)
local SummerDecorPropSplit = require(script.Parent.SummerDecorPropSplit)
local SummerDecorSceneClassifier = require(script.Parent.SummerDecorSceneClassifier)

local SummerDecorAssetImporter = {}

SummerDecorAssetImporter.FOLDER_QUARANTINE = "SummerDecorQuarantine"
SummerDecorAssetImporter.FOLDER_PENDING = "SummerDecorPendingApproval"
SummerDecorAssetImporter.FOLDER_ASSETS = "SummerDecorAssets"
SummerDecorAssetImporter.FOLDER_REJECTED = "SummerDecorRejectedDiagnostics"

local GENERATED_BY = "SummerDecorAssetImporter"
local GENERATOR_DECOR = "SummerZoneDecorationGenerator"

function SummerDecorAssetImporter.AssertEditMode(): boolean
	-- IsEdit requires Plugin capability; Play/server must treat that as not-edit (block import).
	local studioOk, isStudio = pcall(function()
		return RunService:IsStudio()
	end)
	if not studioOk or isStudio ~= true then
		return false
	end
	local editOk, isEdit = pcall(function()
		return RunService:IsEdit()
	end)
	if not editOk then
		return false
	end
	return isEdit == true
end

local function ensureFolder(name: string): Folder
	local existing = ServerStorage:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = ServerStorage
	return folder
end

function SummerDecorAssetImporter.EnsureFolders()
	ensureFolder(SummerDecorAssetImporter.FOLDER_QUARANTINE)
	ensureFolder(SummerDecorAssetImporter.FOLDER_PENDING)
	ensureFolder(SummerDecorAssetImporter.FOLDER_REJECTED)
	local assets = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_ASSETS)
	if not assets then
		ensureFolder(SummerDecorAssetImporter.FOLDER_ASSETS)
	end
end

function SummerDecorAssetImporter.ClearQuarantine()
	local folder = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_QUARANTINE)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		pcall(function()
			child:Destroy()
		end)
	end
end

local function unwrapLoaded(inst: Instance): Instance
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

local function loadIntoQuarantine(assetId: number, quarantine: Folder): (Instance?, string?)
	local ok, result = pcall(function()
		return AssetService:LoadAssetAsync(assetId)
	end)
	if not ok or typeof(result) ~= "Instance" then
		return nil, "load_failed"
	end
	local root = unwrapLoaded(result :: Instance)
	pcall(function()
		(root :: any).Sandboxed = true
	end)
	root.Parent = quarantine
	return root, nil
end

local function clearPendingAssetFolder(pending: Folder, assetId: number)
	local name = "Asset_" .. tostring(assetId)
	local existing = pending:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local function applyPropAttributes(propModel: Model, assetId: number, index: number, sourceName: string)
	local key = SummerDecorPropSplit.MakeTemplateKey(assetId, index)
	propModel.Name = SummerDecorPropSplit.SanitizePropName(sourceName, index)
	-- Retirer attrs générés par Rebuild (AssetId global) puis poser attrs prop
	propModel:SetAttribute("AssetId", nil)
	propModel:SetAttribute("SourceAssetId", assetId)
	propModel:SetAttribute("PropIndex", index)
	propModel:SetAttribute("TemplateKey", key)
	propModel:SetAttribute("SanitizedSummerAsset", true)
	propModel:SetAttribute("GeneratedBy", GENERATED_BY)
	propModel:SetAttribute("SanitizerVersion", SummerDecorConfig.Security.SanitizerVersion)
	propModel:SetAttribute("ImportedAt", os.time())
	local fp = SummerDecorSecurity.ComputeFingerprint(propModel)
	propModel:SetAttribute("SanitizedFingerprint", fp)
	SummerDecorPropSplit.ApplyGroundPivot(propModel)
end

function SummerDecorAssetImporter.GetPendingAssetFolders(): { Folder }
	SummerDecorAssetImporter.EnsureFolders()
	local pending = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_PENDING)
	local out: { Folder } = {}
	if not pending then
		return out
	end
	for _, child in ipairs(pending:GetChildren()) do
		if child:IsA("Folder") and string.match(child.Name, "^Asset_") then
			table.insert(out, child)
		end
	end
	return out
end

function SummerDecorAssetImporter.GetPendingProps(): { Model }
	local out: { Model } = {}
	for _, folder in ipairs(SummerDecorAssetImporter.GetPendingAssetFolders()) do
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("SanitizedSummerAsset") == true then
				table.insert(out, child)
			end
		end
	end
	table.sort(out, function(a, b)
		local ka = tostring(a:GetAttribute("TemplateKey") or a.Name)
		local kb = tostring(b:GetAttribute("TemplateKey") or b.Name)
		return ka < kb
	end)
	return out
end

-- Compat : retourne les props (plus les anciens Model plats)
function SummerDecorAssetImporter.GetPendingModels(): { Model }
	return SummerDecorAssetImporter.GetPendingProps()
end

function SummerDecorAssetImporter.FindApprovedProp(templateKey: string): Instance?
	local assets = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_ASSETS)
	if not assets then
		return nil
	end
	for _, child in ipairs(assets:GetDescendants()) do
		if child:IsA("Model") and child:GetAttribute("TemplateKey") == templateKey then
			if child:GetAttribute("SanitizedSummerAsset") == true then
				return child
			end
		end
	end
	return nil
end

function SummerDecorAssetImporter.FindApprovedCached(assetId: number): Instance?
	-- Premier prop approuvé pour cet SourceAssetId (compat guirlandes)
	local assets = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_ASSETS)
	if not assets then
		return nil
	end
	local best: Instance? = nil
	local bestIndex = math.huge
	for _, child in ipairs(assets:GetDescendants()) do
		if child:IsA("Model") and child:GetAttribute("SourceAssetId") == assetId then
			local key = child:GetAttribute("TemplateKey")
			if type(key) == "string" and SummerDecorConfig.IsTemplateApproved(key) then
				local idx = child:GetAttribute("PropIndex")
				local n = if type(idx) == "number" then idx else 9999
				if n < bestIndex then
					bestIndex = n
					best = child
				end
			end
		end
	end
	return best
end

function SummerDecorAssetImporter.ListMissingApprovedAssets(): { number }
	local missing: { number } = {}
	local seen: { [number]: boolean } = {}
	for key, approved in pairs(SummerDecorConfig.ApprovedTemplateKeys) do
		if approved == true then
			local assetId = tonumber(string.match(key, "^(%d+)_"))
			if assetId and not seen[assetId] then
				if SummerDecorAssetImporter.FindApprovedProp(key) == nil then
					seen[assetId] = true
					table.insert(missing, assetId)
					warn(("[SummerDecorAssets] Approved asset missing from persistent cache: %d"):format(assetId))
				end
			end
		end
	end
	-- Compat ancienne liste
	for assetId, approved in pairs(SummerDecorConfig.ApprovedAssetIds) do
		if approved == true and not seen[assetId] and SummerDecorAssetImporter.FindApprovedCached(assetId) == nil then
			table.insert(missing, assetId)
			warn(("[SummerDecorAssets] Approved asset missing from persistent cache: %d"):format(assetId))
		end
	end
	return missing
end

function SummerDecorAssetImporter.CloneForViewportPreview(pending: Instance, worldModel: Instance): Instance?
	local clone = pending:Clone()
	clone.Parent = worldModel
	return clone
end

function SummerDecorAssetImporter.RejectPendingProp(templateKey: string): boolean
	for _, prop in ipairs(SummerDecorAssetImporter.GetPendingProps()) do
		if prop:GetAttribute("TemplateKey") == templateKey then
			prop:Destroy()
			print(("[SummerDecorImporter] Rejected pending prop TemplateKey=%s"):format(templateKey))
			return true
		end
	end
	return false
end

local function resolveSourceAssetId(inst: Instance): number?
	local sid = inst:GetAttribute("SourceAssetId")
	if type(sid) == "number" then
		return sid
	end
	local aid = inst:GetAttribute("AssetId")
	if type(aid) == "number" then
		return aid
	end
	return nil
end

local function shouldPurgeWorkspaceInstance(inst: Instance): boolean
	if not inst:IsA("Model") and not inst:IsA("BasePart") then
		return false
	end
	local by = inst:GetAttribute("GeneratedBy")
	if by == GENERATED_BY or by == GENERATOR_DECOR then
		return true
	end
	local sid = resolveSourceAssetId(inst)
	if sid and SummerDecorConfig.IsCompositeRejected(sid) then
		return true
	end
	-- Scènes fusionnées connues : jamais autorisées dans SummerZoneDecor
	if SummerDecorConfig.MatchesFusedSceneName(inst.Name) then
		return true
	end
	local mesh = if inst:IsA("Model") then inst:FindFirstChildWhichIsA("MeshPart", true) else nil
	if mesh and SummerDecorConfig.MatchesFusedSceneName(mesh.Name) then
		return true
	end
	local ok, cls = SummerDecorSceneClassifier.ValidateForPlacement(inst, inst.Name)
	if not ok and cls.IsCompositeScene then
		-- Ne purger les « composite » sans marquage que s'ils sont auto-générés ou nom scène
		if by == GENERATED_BY or by == GENERATOR_DECOR or SummerDecorSceneClassifier.IsForbiddenSceneName(inst.Name) then
			return true
		end
	end
	return false
end

-- Découvre SourceAssetId des kits tropical/tripo et les enregistre comme rejetés.
function SummerDecorAssetImporter.DiscoverAndRegisterCompositeIds(): { number }
	local found: { number } = {}
	local function scan(root: Instance?)
		if not root then
			return
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") or d:IsA("BasePart") then
				if SummerDecorConfig.MatchesFusedSceneName(d.Name)
					or (d:IsA("Model") and d:FindFirstChildWhichIsA("MeshPart", true)
						and SummerDecorConfig.MatchesFusedSceneName(
							(d:FindFirstChildWhichIsA("MeshPart", true) :: Instance).Name
						))
				then
					local sid = resolveSourceAssetId(d)
					if sid then
						SummerDecorConfig.RegisterCompositeRejected(sid)
						table.insert(found, sid)
						print(("[SummerDecorImporter] REJECTED_COMPOSITE: %d"):format(sid))
					else
						print(("[SummerDecorImporter] REJECTED_COMPOSITE: name=%s (no SourceAssetId on instance)"):format(d.Name))
					end
				end
			end
		end
	end
	scan(Workspace:FindFirstChild("StudioDecoration"))
	scan(ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_PENDING))
	scan(ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_ASSETS))
	-- Toujours logger les IDs config
	for id, rejected in pairs(SummerDecorConfig.CompositeRejectedAssetIds) do
		if rejected then
			print(("[SummerDecorImporter] REJECTED_COMPOSITE: %d"):format(id))
		end
	end
	return found
end

function SummerDecorAssetImporter.PurgeCompositeRejected(): number
	SummerDecorAssetImporter.EnsureFolders()
	SummerDecorAssetImporter.DiscoverAndRegisterCompositeIds()

	local removed = 0
	local pending = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_PENDING)
	local assets = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_ASSETS)

	local function purgeFolder(folder: Instance?, label: string)
		if not folder then
			return
		end
		local kill: { Instance } = {}
		for _, d in ipairs(folder:GetDescendants()) do
			local sid = resolveSourceAssetId(d)
			local nameHit = SummerDecorConfig.MatchesFusedSceneName(d.Name)
			local mesh = if d:IsA("Model") then d:FindFirstChildWhichIsA("MeshPart", true) else nil
			local meshHit = mesh ~= nil and SummerDecorConfig.MatchesFusedSceneName(mesh.Name)
			if (sid and SummerDecorConfig.IsCompositeRejected(sid)) or nameHit or meshHit then
				table.insert(kill, d)
			end
		end
		table.sort(kill, function(a, b)
			return #a:GetFullName() > #b:GetFullName()
		end)
		local seen: { [Instance]: boolean } = {}
		for _, inst in ipairs(kill) do
			local sid = resolveSourceAssetId(inst)
			local root = inst
			local walk: Instance? = inst
			while walk and walk.Parent and walk.Parent ~= folder do
				if walk:IsA("Model") or walk:IsA("Folder") then
					root = walk
				end
				walk = walk.Parent
			end
			if walk and (walk:IsA("Model") or walk:IsA("Folder")) and walk.Parent == folder then
				root = walk
			end
			if not seen[root] and root.Parent then
				seen[root] = true
				print(("[SummerDecorImporter] Removed stale %s template: %s"):format(
					label,
					tostring(sid or root.Name)
				))
				root:Destroy()
				removed += 1
			end
		end
	end

	purgeFolder(pending, "pending")
	purgeFolder(assets, "approved")

	local studio = Workspace:FindFirstChild("StudioDecoration")
	local decor = studio and studio:FindFirstChild("SummerZoneDecor")
	if decor then
		local kill: { Instance } = {}
		for _, d in ipairs(decor:GetDescendants()) do
			if shouldPurgeWorkspaceInstance(d) then
				table.insert(kill, d)
			end
		end
		table.sort(kill, function(a, b)
			return #a:GetFullName() > #b:GetFullName()
		end)
		local seen: { [Instance]: boolean } = {}
		for _, inst in ipairs(kill) do
			local target = inst
			local walk: Instance? = inst
			while walk and walk ~= decor do
				if walk:IsA("Model") and shouldPurgeWorkspaceInstance(walk) then
					target = walk
				end
				walk = walk.Parent
			end
			if not seen[target] and target.Parent then
				seen[target] = true
				print(("[SummerDecorImporter] Removed from SummerZoneDecor: %s"):format(target:GetFullName()))
				target:Destroy()
				removed += 1
			end
		end
	end

	SummerDecorAssetImporter.ClearQuarantine()
	return removed
end

function SummerDecorAssetImporter.RemoveFusedSceneDecor(): number
	return SummerDecorAssetImporter.PurgeCompositeRejected()
end

function SummerDecorAssetImporter.RemoveAutoGeneratedDecor(): number
	return SummerDecorAssetImporter.PurgeCompositeRejected()
end

local function rejectComposite(assetId: number, loaded: Instance)
	SummerDecorConfig.RegisterCompositeRejected(assetId)
	print(("[SummerDecorImporter] REJECTED_COMPOSITE: %d"):format(assetId))
	print("[SummerDecorImporter] Asset contains one inseparable MeshPart or UnionOperation")
	local diag = ensureFolder(SummerDecorAssetImporter.FOLDER_REJECTED)
	local old = diag:FindFirstChild("Rejected_" .. tostring(assetId))
	if old then
		old:Destroy()
	end
	local marker = Instance.new("Folder")
	marker.Name = "Rejected_" .. tostring(assetId)
	marker:SetAttribute("SourceAssetId", assetId)
	marker:SetAttribute("RejectReason", "inseparable_mesh")
	marker.Parent = diag
	loaded:Destroy()
end

function SummerDecorAssetImporter.ImportAssetId(assetId: number): string
	if not SummerDecorAssetImporter.AssertEditMode() then
		warn("[SummerDecorAssetImporter] Import blocked: not in Studio Edit mode")
		return "blocked_not_edit"
	end

	if SummerDecorConfig.IsCompositeRejected(assetId) then
		print(("[SummerDecorImporter] REJECTED_COMPOSITE: %d"):format(assetId))
		print("[SummerDecorImporter] Asset contains one inseparable MeshPart or UnionOperation")
		return "rejected_composite"
	end

	SummerDecorAssetImporter.EnsureFolders()
	local status = "error"
	local splitCount = 0

	local function body()
		SummerDecorSecurity.LogScanHeader(assetId)
		local quarantine = ensureFolder(SummerDecorAssetImporter.FOLDER_QUARANTINE)
		local pending = ensureFolder(SummerDecorAssetImporter.FOLDER_PENDING)

		local loaded, loadErr = loadIntoQuarantine(assetId, quarantine)
		if not loaded then
			SummerDecorSecurity.LogRejected(assetId, loadErr)
			status = "rejected"
			return
		end

		local scripts = SummerDecorSecurity.FindForbiddenScripts(loaded)
		if #scripts > 0 then
			SummerDecorSecurity.LogRejected(assetId, "executable_code")
			SummerDecorSecurity.LogScriptPaths(scripts)
			status = "rejected"
			return
		end

		if SummerDecorConfig.MatchesFusedSceneName(loaded.Name) then
			rejectComposite(assetId, loaded)
			status = "rejected_composite"
			return
		end

		local placeOk, placeCls = SummerDecorSceneClassifier.ValidateForPlacement(loaded, loaded.Name)
		if not placeOk and placeCls.IsCompositeScene then
			rejectComposite(assetId, loaded)
			status = "rejected_composite"
			return
		end

		if SummerDecorPropSplit.IsInseparableComposite(loaded) then
			rejectComposite(assetId, loaded)
			status = "rejected_composite"
			return
		end

		local propSources, splitErr = SummerDecorPropSplit.SplitIntoPropSources(loaded)
		if splitErr == "inseparable_mesh" or #propSources == 0 then
			rejectComposite(assetId, loaded)
			status = "rejected_composite"
			return
		end

		clearPendingAssetFolder(pending, assetId)
		local assetFolder = Instance.new("Folder")
		assetFolder.Name = "Asset_" .. tostring(assetId)
		assetFolder:SetAttribute("SourceAssetId", assetId)
		assetFolder.Parent = pending

		local totalOriginal = SummerDecorSecurity.CountInstances(loaded)
		local totalRemoved = 0
		local totalClean = 0

		for index, src in ipairs(propSources) do
			local clean, reason = SummerDecorSecurity.RebuildWhitelisted(src.Root, assetId)
			src.Root:Destroy()
			if not clean then
				warn(("[SummerDecorImporter] prop %d of %d failed: %s"):format(index, assetId, tostring(reason)))
				continue
			end
			local original = clean:GetAttribute("_OriginalCount")
			local removed = clean:GetAttribute("_RemovedCount")
			local cleanCount = clean:GetAttribute("_CleanCount")
			if type(removed) == "number" then
				totalRemoved += removed
			end
			if type(cleanCount) == "number" then
				totalClean += cleanCount
			end
			clean:SetAttribute("_OriginalCount", nil)
			clean:SetAttribute("_RemovedCount", nil)
			clean:SetAttribute("_CleanCount", nil)

			applyPropAttributes(clean, assetId, index, src.Name)
			local propOk, propCls = SummerDecorSceneClassifier.ValidateForPlacement(clean, clean.Name)
			if not propOk then
				warn(("[SummerDecorImporter] prop rejected (%s): %s"):format(propCls.Reason, clean.Name))
				clean:Destroy()
				continue
			end
			clean.Parent = assetFolder
			splitCount += 1

			-- Fingerprint review vs cache
			local key = clean:GetAttribute("TemplateKey")
			if type(key) == "string" then
				local existing = SummerDecorAssetImporter.FindApprovedProp(key)
				if existing then
					local oldFp = existing:GetAttribute("SanitizedFingerprint")
					local newFp = clean:GetAttribute("SanitizedFingerprint")
					if type(oldFp) == "string" and type(newFp) == "string" and oldFp ~= newFp then
						SummerDecorSecurity.LogUpdateRequiresReview(assetId)
						print(("[SummerDecorSecurity] UPDATE REQUIRES REVIEW: TemplateKey=%s"):format(key))
					end
				end
			end
		end

		SummerDecorSecurity.LogCounts(totalOriginal, totalRemoved, totalClean)
		SummerDecorSecurity.LogSanitized(assetId)
		print(("[SummerDecorImporter] SPLIT asset %d into %d prop(s)"):format(assetId, splitCount))
		SummerDecorSecurity.LogPending(assetId)
		status = if splitCount > 0 then "sanitized_pending" else "rejected"
	end

	xpcall(body, function(err)
		warn("[SummerDecorAssetImporter] import error:", err)
		status = "error"
	end)

	SummerDecorAssetImporter.ClearQuarantine()
	return status
end

function SummerDecorAssetImporter.ImportAllCandidates(): { [number]: string }
	local results: { [number]: string } = {}
	if not SummerDecorAssetImporter.AssertEditMode() then
		warn("[SummerDecorAssetImporter] ImportAll blocked: not in Studio Edit mode")
		return results
	end
	SummerDecorAssetImporter.PurgeCompositeRejected()
	for _, assetId in ipairs(SummerDecorConfig.ListCandidateAssetIds()) do
		results[assetId] = SummerDecorAssetImporter.ImportAssetId(assetId)
	end
	-- Re-purge au cas où un import aurait laissé des restes
	SummerDecorAssetImporter.PurgeCompositeRejected()
	SummerDecorAssetImporter.ClearQuarantine()
	return results
end

export type PromoteResult = {
	promoted: { string },
	missing: { string },
}

function SummerDecorAssetImporter.PromotePendingApproved(): PromoteResult
	local promoted: { string } = {}
	local missing: { string } = {}

	if not SummerDecorAssetImporter.AssertEditMode() then
		warn("[SummerDecorAssetImporter] Promote blocked: not in Studio Edit mode")
		return { promoted = promoted, missing = missing }
	end

	SummerDecorAssetImporter.EnsureFolders()
	local assets = ServerStorage:FindFirstChild(SummerDecorAssetImporter.FOLDER_ASSETS)
	if not assets then
		assets = ensureFolder(SummerDecorAssetImporter.FOLDER_ASSETS)
	end

	local pendingByKey: { [string]: Model } = {}
	for _, prop in ipairs(SummerDecorAssetImporter.GetPendingProps()) do
		local key = prop:GetAttribute("TemplateKey")
		if type(key) == "string" then
			pendingByKey[key] = prop
		end
	end

	local function promoteKey(key: string)
		local pend = pendingByKey[key]
		if pend then
			local old = SummerDecorAssetImporter.FindApprovedProp(key)
			if old then
				old:Destroy()
			end
			local sourceId = pend:GetAttribute("SourceAssetId")
			local assetFolderName = "Asset_" .. tostring(sourceId)
			local destFolder = assets:FindFirstChild(assetFolderName)
			if not destFolder then
				destFolder = Instance.new("Folder")
				destFolder.Name = assetFolderName
				destFolder.Parent = assets
			end
			local copy = pend:Clone()
			copy.Parent = destFolder
			pend:Destroy()
			table.insert(promoted, key)
			print(("[SummerDecorSecurity] PROMOTED approved asset: %s"):format(key))
		else
			if SummerDecorAssetImporter.FindApprovedProp(key) == nil then
				table.insert(missing, key)
				warn(("[SummerDecorAssets] Approved asset missing from persistent cache: %s"):format(key))
			end
		end
	end

	for key, approved in pairs(SummerDecorConfig.ApprovedTemplateKeys) do
		if approved == true then
			promoteKey(key)
		end
	end

	-- Compat : ApprovedAssetIds → tous les props pending de cet ID
	for assetId, approved in pairs(SummerDecorConfig.ApprovedAssetIds) do
		if approved == true then
			for key, pend in pairs(pendingByKey) do
				if pend:GetAttribute("SourceAssetId") == assetId then
					if not SummerDecorConfig.ApprovedTemplateKeys[key] then
						promoteKey(key)
					end
				end
			end
		end
	end

	return { promoted = promoted, missing = missing }
end

return SummerDecorAssetImporter
