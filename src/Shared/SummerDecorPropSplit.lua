--!strict
-- Sépare un asset importé en props individuels (hiérarchie + soudures).
-- Ne découpe jamais un MeshPart / Union fusionné unique.

local SummerDecorPropSplit = {}

export type PropSource = {
	Name: string,
	Root: Instance, -- sous-arbre source (clone détaché)
}

local function collectBaseParts(root: Instance): { BasePart }
	local parts: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function countVisualParts(root: Instance): number
	return #collectBaseParts(root)
end

-- Asset impossible à séparer : une seule MeshPart/Union pour tout le contenu.
function SummerDecorPropSplit.IsInseparableComposite(root: Instance): boolean
	local parts = collectBaseParts(root)
	if #parts == 0 then
		return true
	end
	if #parts == 1 then
		local only = parts[1]
		return only:IsA("MeshPart") or only:IsA("UnionOperation")
	end
	return false
end

local function cloneSubtree(src: Instance): Instance
	return src:Clone()
end

local function hasVisual(inst: Instance): boolean
	return countVisualParts(inst) > 0
end

-- Union-find sur BasePart reliées par Weld / WeldConstraint / Motor6D dans `container`.
local function weldConnectedComponents(container: Instance, parts: { BasePart }): { { BasePart } }
	local parent: { [BasePart]: BasePart } = {}
	local function find(p: BasePart): BasePart
		local r = parent[p]
		if not r then
			parent[p] = p
			return p
		end
		if r ~= p then
			parent[p] = find(r)
		end
		return parent[p]
	end
	local function union(a: BasePart, b: BasePart)
		local ra, rb = find(a), find(b)
		if ra ~= rb then
			parent[rb] = ra
		end
	end

	for _, p in ipairs(parts) do
		parent[p] = p
	end

	local function considerConstraint(c: Instance)
		local p0: BasePart? = nil
		local p1: BasePart? = nil
		if c:IsA("WeldConstraint") then
			p0 = c.Part0
			p1 = c.Part1
		elseif c:IsA("Weld") or c:IsA("Motor6D") then
			p0 = c.Part0
			p1 = c.Part1
		end
		if p0 and p1 and parent[p0] and parent[p1] then
			union(p0, p1)
		end
	end

	if container:IsA("WeldConstraint") or container:IsA("Weld") or container:IsA("Motor6D") then
		considerConstraint(container)
	end
	for _, d in ipairs(container:GetDescendants()) do
		considerConstraint(d)
	end

	local groups: { [BasePart]: { BasePart } } = {}
	local order: { BasePart } = {}
	for _, p in ipairs(parts) do
		local r = find(p)
		if not groups[r] then
			groups[r] = {}
			table.insert(order, r)
		end
		table.insert(groups[r], p)
	end

	local out: { { BasePart } } = {}
	for _, r in ipairs(order) do
		table.insert(out, groups[r])
	end
	return out
end

-- Regroupe une composante soudée (+ descendants non-part déjà sous ces parts) dans un Model.
local function bundlePartsAsModel(parts: { BasePart }, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	-- Cloner chaque part avec ses enfants non-BasePart (mesh, decal, light, attachment)
	-- et les contraintes internes.
	local map: { [Instance]: Instance } = {}
	for _, part in ipairs(parts) do
		local clone = part:Clone()
		-- Retirer les BasePart enfants du clone (appartiennent peut‑être à d'autres groupes)
		for _, ch in ipairs(clone:GetDescendants()) do
			if ch:IsA("BasePart") then
				ch:Destroy()
			end
		end
		clone.Parent = model
		map[part] = clone
	end

	-- Recopier welds internes entre parts du groupe (depuis l'original)
	local seenConstraint: { [Instance]: boolean } = {}
	for _, part in ipairs(parts) do
		local searchRoot = part.Parent or part
		local candidates = { searchRoot }
		for _, d in ipairs(searchRoot:GetDescendants()) do
			table.insert(candidates, d)
		end
		-- Aussi remonter au modèle ancestor
		local anc = part
		while anc and anc.Parent do
			anc = anc.Parent
			for _, d in ipairs(anc:GetDescendants()) do
				if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then
					if not seenConstraint[d] then
						table.insert(candidates, d)
						seenConstraint[d] = true
					end
				end
			end
			if anc:IsA("Model") or anc:IsA("Folder") then
				-- continue up a bit
			end
			if anc.Parent == nil or anc:IsA("Workspace") or anc:IsA("ServerStorage") then
				break
			end
		end
	end

	-- Plus simple : scanner parent commun
	local commonParent = parts[1].Parent
	if commonParent then
		local function tryCopyConstraint(c: Instance)
			local p0: BasePart? = nil
			local p1: BasePart? = nil
			if c:IsA("WeldConstraint") then
				p0, p1 = c.Part0, c.Part1
			elseif c:IsA("Weld") or c:IsA("Motor6D") then
				p0, p1 = c.Part0, c.Part1
			else
				return
			end
			if not (p0 and p1 and map[p0] and map[p1]) then
				return
			end
			local clone = c:Clone()
			if clone:IsA("WeldConstraint") then
				clone.Part0 = map[p0] :: BasePart
				clone.Part1 = map[p1] :: BasePart
			elseif clone:IsA("Weld") or clone:IsA("Motor6D") then
				(clone :: Weld).Part0 = map[p0] :: BasePart
				(clone :: Weld).Part1 = map[p1] :: BasePart
			end
			clone.Parent = model
		end
		tryCopyConstraint(commonParent)
		for _, d in ipairs(commonParent:GetDescendants()) do
			tryCopyConstraint(d)
		end
		if commonParent.Parent then
			for _, d in ipairs(commonParent.Parent:GetDescendants()) do
				tryCopyConstraint(d)
			end
		end
	end

	return model
end

--[[
	Ordre :
	1) enfants Model
	2) enfants Folder avec visuels
	3) groupes soudés parmi BasePart restantes
	4) BasePart isolés
]]
function SummerDecorPropSplit.SplitIntoPropSources(root: Instance): ({ PropSource }, string?)
	if SummerDecorPropSplit.IsInseparableComposite(root) then
		return {}, "inseparable_mesh"
	end

	local props: { PropSource } = {}
	local claimed: { [Instance]: boolean } = {}

	local function claimTree(inst: Instance)
		claimed[inst] = true
		for _, d in ipairs(inst:GetDescendants()) do
			claimed[d] = true
		end
	end

	local function addProp(name: string, src: Instance)
		if not hasVisual(src) then
			return
		end
		-- Sous-arbre déjà inseparable seul ?
		if SummerDecorPropSplit.IsInseparableComposite(src) and countVisualParts(src) == 1 then
			-- Un MeshPart unique comme prop isolé (ex. un rocher) est OK s'il y a PLUSIEURS props.
			-- Le rejet global ne s'applique que si c'est le seul contenu de l'asset.
		end
		table.insert(props, {
			Name = name,
			Root = cloneSubtree(src),
		})
		claimTree(src)
	end

	local children = root:GetChildren()
	-- 1) Models
	for _, ch in ipairs(children) do
		if ch:IsA("Model") and hasVisual(ch) then
			addProp(ch.Name, ch)
		end
	end
	-- 2) Folders
	for _, ch in ipairs(children) do
		if ch:IsA("Folder") and hasVisual(ch) and not claimed[ch] then
			addProp(ch.Name, ch)
		end
	end

	-- 3–4) BaseParts restantes sous root (directes ou dans containers non claimés)
	local remaining: { BasePart } = {}
	local function gatherRemaining(inst: Instance)
		if claimed[inst] then
			return
		end
		if inst:IsA("BasePart") then
			table.insert(remaining, inst)
		end
		for _, ch in ipairs(inst:GetChildren()) do
			if not claimed[ch] then
				if ch:IsA("Model") or ch:IsA("Folder") then
					-- déjà traités ou vides
					if not claimed[ch] and not ch:IsA("Model") then
						gatherRemaining(ch)
					elseif not claimed[ch] and ch:IsA("Folder") then
						gatherRemaining(ch)
					end
				else
					gatherRemaining(ch)
				end
			end
		end
	end

	-- Collecter parts non claimées
	if root:IsA("BasePart") and not claimed[root] then
		table.insert(remaining, root)
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and not claimed[d] then
			table.insert(remaining, d)
		end
	end

	if #remaining > 0 then
		local components = weldConnectedComponents(root, remaining)
		for i, group in ipairs(components) do
			local name = if #group == 1 then group[1].Name else ("WeldGroup_" .. tostring(i))
			local bundled = bundlePartsAsModel(group, name)
			table.insert(props, {
				Name = name,
				Root = bundled,
			})
			for _, p in ipairs(group) do
				claimTree(p)
			end
		end
	end

	-- Si la racine était un Model unique sans enfants Model (tout en descendants),
	-- et qu'on n'a rien extrait, traiter la racine comme un seul prop (si séparable).
	if #props == 0 and hasVisual(root) and not SummerDecorPropSplit.IsInseparableComposite(root) then
		table.insert(props, {
			Name = root.Name,
			Root = cloneSubtree(root),
		})
	end

	if #props == 0 then
		return {}, "no_props"
	end

	-- Un seul MeshPart/Union pour tout l'asset → incompatible générateur
	if #props == 1 and SummerDecorPropSplit.IsInseparableComposite(props[1].Root) then
		for _, p in ipairs(props) do
			p.Root:Destroy()
		end
		return {}, "inseparable_mesh"
	end

	return props, nil
end

-- Pivot horizontal au centre, hauteur à la base ; Anchor + PivotTo-ready.
function SummerDecorPropSplit.ApplyGroundPivot(propModel: Model)
	local parts = collectBaseParts(propModel)
	if #parts == 0 then
		return
	end
	for _, p in ipairs(parts) do
		p.Anchored = true
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
	end

	local cf, size = propModel:GetBoundingBox()
	local center = cf.Position
	local baseY = center.Y - size.Y * 0.5
	local pivotPos = Vector3.new(center.X, baseY, center.Z)
	propModel.WorldPivot = CFrame.new(pivotPos)

	-- PrimaryPart pour stabilité Studio
	local primary: BasePart? = nil
	local bestDist = math.huge
	for _, p in ipairs(parts) do
		local d = (Vector3.new(p.Position.X, baseY, p.Position.Z) - pivotPos).Magnitude
		if d < bestDist then
			bestDist = d
			primary = p
		end
	end
	if primary then
		propModel.PrimaryPart = primary
	end
end

function SummerDecorPropSplit.SanitizePropName(name: string, index: number): string
	local cleaned = string.gsub(name, "[^%w_]+", "")
	if cleaned == "" then
		cleaned = "Prop"
	end
	return string.format("Prop_%02d_%s", index, cleaned)
end

function SummerDecorPropSplit.MakeTemplateKey(assetId: number, index: number): string
	return tostring(assetId) .. "_" .. tostring(index)
end

return SummerDecorPropSplit
