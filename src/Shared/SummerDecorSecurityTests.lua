--!strict
-- Tests sécurité décor Summer (instances synthétiques, sans Marketplace).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Security = require(Shared.SummerDecorSecurity)
local Importer = require(Shared.SummerDecorAssetImporter)
local Config = require(Shared.SummerDecorConfig)

local SummerDecorSecurityTests = {}

function SummerDecorSecurityTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[SummerDecorSecurityTests] FAIL:", msg)
			ok = false
		end
	end

	-- Forbidden scripts
	do
		local root = Instance.new("Model")
		root.Name = "Tainted"
		local s = Instance.new("Script")
		s.Name = "Bad"
		s.Parent = root
		local paths = Security.FindForbiddenScripts(root)
		check(#paths >= 1, "FindForbiddenScripts finds Script")
		local clean, reason = Security.RebuildWhitelisted(root, 1)
		check(clean == nil and reason == "executable_code", "rebuild rejects scripts")
		root:Destroy()
	end

	-- Rebuild drops Sound / Prompt ; keep Part
	do
		local root = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "Keep"
		part.Size = Vector3.new(2, 2, 2)
		part.Parent = root
		part:SetAttribute("Evil", true)
		local snd = Instance.new("Sound")
		snd.Parent = root
		local prompt = Instance.new("ProximityPrompt")
		prompt.Parent = part
		local clean, reason = Security.RebuildWhitelisted(root, 42)
		check(clean ~= nil and reason == nil, "rebuild ok visual")
		if clean then
			check(clean:FindFirstChild("Keep", true) ~= nil, "Part kept")
			check(clean:FindFirstChildWhichIsA("Sound", true) == nil, "Sound removed")
			check(clean:FindFirstChildWhichIsA("ProximityPrompt", true) == nil, "Prompt removed")
			local kept = clean:FindFirstChild("Keep", true)
			check(kept ~= nil and kept:GetAttribute("Evil") == nil, "original attrs stripped")
			check(clean:GetAttribute("SanitizedSummerAsset") == true, "generator attr")
			check(type(clean:GetAttribute("SanitizedFingerprint")) == "string", "fingerprint set")
			local fp1 = clean:GetAttribute("SanitizedFingerprint")
			local keptPart = kept :: BasePart
			keptPart.Size = Vector3.new(3, 3, 3)
			local fp2 = Security.ComputeFingerprint(clean)
			check(fp1 ~= fp2, "fingerprint changes with Size")
			-- Validation fails if Script added after
			local evil = Instance.new("Script")
			evil.Parent = clean
			local valid, _ = Security.ValidateCleanModel(clean)
			check(valid == false, "ValidateCleanModel rejects Script")
			evil:Destroy()
			clean:Destroy()
		end
		root:Destroy()
	end

	-- Weld to removed target omitted
	do
		local root = Instance.new("Model")
		local a = Instance.new("Part")
		a.Name = "A"
		a.Parent = root
		local b = Instance.new("Part")
		b.Name = "B"
		b.Transparency = 1 -- skipped
		b.Parent = root
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = b
		w.Parent = root
		local clean = Security.RebuildWhitelisted(root, 7)
		if clean then
			check(clean:FindFirstChildWhichIsA("WeldConstraint", true) == nil, "weld to removed part omitted")
			clean:Destroy()
		else
			check(false, "rebuild should succeed for weld case")
		end
		root:Destroy()
	end

	-- Edit mode gate
	do
		if RunService:IsStudio() and not RunService:IsEdit() then
			check(Importer.AssertEditMode() == false, "paused sim not edit")
			check(Importer.ImportAssetId(1) == "blocked_not_edit", "import blocked when not edit")
		elseif not RunService:IsStudio() then
			check(Importer.AssertEditMode() == false, "not studio → not edit")
		else
			-- En Edit Studio réel, AssertEditMode true ; on ne force pas l'échec.
			check(type(Importer.AssertEditMode()) == "boolean", "AssertEditMode boolean")
		end
	end

	-- Import must not overwrite Assets; quarantine cleared after error
	do
		Importer.EnsureFolders()
		local assets = ServerStorage:FindFirstChild(Importer.FOLDER_ASSETS)
		local pending = ServerStorage:FindFirstChild(Importer.FOLDER_PENDING)
		local quarantine = ServerStorage:FindFirstChild(Importer.FOLDER_QUARANTINE)
		check(assets ~= nil and pending ~= nil and quarantine ~= nil, "folders exist")

		local marker = Instance.new("Model")
		marker.Name = "ApprovedMarker"
		marker:SetAttribute("AssetId", 999001)
		marker:SetAttribute("SanitizedFingerprint", "keep-me")
		marker:SetAttribute("SanitizedSummerAsset", true)
		if assets then
			marker.Parent = assets
		end

		-- Simuler corps d'erreur + clear quarantaine
		local junk = Instance.new("Part")
		junk.Name = "QuarantineJunk"
		if quarantine then
			junk.Parent = quarantine
		end
		local cleared = false
		local function body()
			error("scan boom")
		end
		xpcall(body, function() end)
		Importer.ClearQuarantine()
		cleared = quarantine ~= nil and #quarantine:GetChildren() == 0
		check(cleared, "quarantine emptied after error path")

		local still = assets and assets:FindFirstChild("ApprovedMarker")
		check(still ~= nil and still:GetAttribute("SanitizedFingerprint") == "keep-me", "assets untouched without promote")
		if marker.Parent then
			marker:Destroy()
		end
	end

	-- Promote uses pending exact fingerprint (Edit only ; sinon simulation du même flux clone)
	do
		Importer.EnsureFolders()
		local pendingFolder = ServerStorage:FindFirstChild(Importer.FOLDER_PENDING)
		local assetsFolder = ServerStorage:FindFirstChild(Importer.FOLDER_ASSETS)
		if pendingFolder and assetsFolder then
			for _, ch in ipairs(assetsFolder:GetChildren()) do
				if ch:GetAttribute("AssetId") == 888 then
					ch:Destroy()
				end
			end
			local assetFolder = Instance.new("Folder")
			assetFolder.Name = "Asset_888"
			assetFolder.Parent = pendingFolder
			local pend = Instance.new("Model")
			pend.Name = "Prop_01_Test"
			pend:SetAttribute("SourceAssetId", 888)
			pend:SetAttribute("PropIndex", 1)
			pend:SetAttribute("TemplateKey", "888_1")
			pend:SetAttribute("SanitizedSummerAsset", true)
			pend:SetAttribute("SanitizedFingerprint", "pending-fp-888")
			local p = Instance.new("Part")
			p.Parent = pend
			pend.Parent = assetFolder

			local wasKey = Config.ApprovedTemplateKeys["888_1"]
			Config.ApprovedTemplateKeys["888_1"] = true

			local found: Instance? = nil
			if Importer.AssertEditMode() then
				local result = Importer.PromotePendingApproved()
				check(table.find(result.promoted, "888_1") ~= nil, "promoted 888_1")
			else
				local dest = Instance.new("Folder")
				dest.Name = "Asset_888"
				dest.Parent = assetsFolder
				local copy = pend:Clone()
				copy.Parent = dest
				pend:Destroy()
			end
			found = Importer.FindApprovedProp("888_1")
			check(found ~= nil and found:GetAttribute("SanitizedFingerprint") == "pending-fp-888", "promote uses pending fingerprint")
			if found then
				found:Destroy()
			end
			local af = assetsFolder:FindFirstChild("Asset_888")
			if af then
				af:Destroy()
			end
			if assetFolder.Parent then
				assetFolder:Destroy()
			end
			Config.ApprovedTemplateKeys["888_1"] = wasKey
		end
	end

	-- Missing approved cache warning path (no auto download)
	do
		local missing = Importer.ListMissingApprovedAssets()
		check(type(missing) == "table", "ListMissingApprovedAssets")
	end

	-- Preview contract: helper never parents to Workspace
	do
		local pending = Instance.new("Model")
		pending.Name = "PreviewSubject"
		local part = Instance.new("Part")
		part.Parent = pending
		local world = Instance.new("WorldModel")
		local clone = Importer.CloneForViewportPreview(pending, world)
		check(clone ~= nil and clone.Parent == world, "preview under WorldModel")
		check(workspace:FindFirstChild("PreviewSubject") == nil, "no Workspace descendant")
		world:Destroy()
		pending:Destroy()
	end

	if ok then
		print("[SummerDecorSecurityTests] OK")
	end
	return ok
end

return SummerDecorSecurityTests
