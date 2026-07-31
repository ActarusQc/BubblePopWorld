--!strict
-- Décide si un template est un objet atomique (OK) ou une scène fusionnée (rejet).

local SummerDecorConfig = require(script.Parent.SummerDecorConfig)

local SummerDecorSceneClassifier = {}

export type Classification = {
	Ok: boolean,
	Reason: string,
	BasePartCount: number,
	MeshPartCount: number,
	BoundSize: Vector3,
	IsAtomic: boolean,
	IsCompositeScene: boolean,
}

local ATOMIC_NAME_TOKENS = {
	"palm", "tree", "rock", "stone", "chair", "lounge", "surf", "board",
	"parasol", "umbrella", "ball", "buoy", "crate", "box", "sandcastle",
	"castle", "tiki", "torch", "plant", "fern", "lifeguard", "tower",
	"post", "pole", "light",
}

local SCENE_NAME_TOKENS = {
	"setup", "scene", "environment", "collection", "pack", "kit",
	"hangout", "resort", "island",
}

local function lower(s: string): string
	return string.lower(s)
end

local function nameHasToken(name: string, tokens: { string }): boolean
	local n = lower(name)
	for _, t in ipairs(tokens) do
		if string.find(n, t, 1, true) then
			return true
		end
	end
	return false
end

function SummerDecorSceneClassifier.CountParts(root: Instance): (number, number)
	local base, mesh = 0, 0
	local function consider(inst: Instance)
		if inst:IsA("MeshPart") then
			mesh += 1
			base += 1
		elseif inst:IsA("UnionOperation") then
			mesh += 1
			base += 1
		elseif inst:IsA("BasePart") then
			base += 1
		end
	end
	consider(root)
	for _, d in ipairs(root:GetDescendants()) do
		consider(d)
	end
	return base, mesh
end

function SummerDecorSceneClassifier.GetBoundSize(root: Instance): Vector3
	if root:IsA("Model") then
		local ok, size = pcall(function()
			local _, sz = (root :: Model):GetBoundingBox()
			return sz
		end)
		if ok and typeof(size) == "Vector3" then
			return size
		end
	end
	if root:IsA("BasePart") then
		return root.Size
	end
	return Vector3.new(1, 1, 1)
end

function SummerDecorSceneClassifier.IsForbiddenSceneName(name: string): boolean
	local n = lower(name)
	-- Exception : tour de sauveteur atomique
	if string.find(n, "lifeguard", 1, true) and not string.find(n, "setup", 1, true) then
		return false
	end
	if SummerDecorConfig.MatchesFusedSceneName(name) then
		return true
	end
	-- Tokens scène génériques
	for _, token in ipairs(SCENE_NAME_TOKENS) do
		if string.find(n, token, 1, true) then
			if token == "pack" or token == "kit" or token == "collection" then
				if string.find(n, "beach", 1, true)
					or string.find(n, "tropical", 1, true)
					or string.find(n, "decor", 1, true)
					or string.find(n, "prop", 1, true)
					or string.find(n, "setup", 1, true)
				then
					return true
				end
			else
				return true
			end
		end
	end
	if string.find(n, "tripo_", 1, true) then
		return true
	end
	return false
end

function SummerDecorSceneClassifier.LooksAtomicByName(name: string): boolean
	-- Lifeguard tower : atomique même si le nom contient "3d+model"
	local n = lower(name)
	if string.find(n, "lifeguard", 1, true) or (string.find(n, "tower", 1, true) and not string.find(n, "setup", 1, true)) then
		return not string.find(n, "setup", 1, true)
	end
	return nameHasToken(name, ATOMIC_NAME_TOKENS) and not SummerDecorSceneClassifier.IsForbiddenSceneName(name)
end

function SummerDecorSceneClassifier.Classify(root: Instance, displayName: string?): Classification
	local name = displayName or root.Name
	local baseCount, meshCount = SummerDecorSceneClassifier.CountParts(root)
	local bound = SummerDecorSceneClassifier.GetBoundSize(root)
	local footprint = math.max(bound.X, bound.Z)
	local volumeApprox = bound.X * bound.Y * bound.Z

	local forbiddenName = SummerDecorSceneClassifier.IsForbiddenSceneName(name)
	local atomicName = SummerDecorSceneClassifier.LooksAtomicByName(name)

	-- Scène fusionnée typique : 1 mesh, grande emprise
	local largeSingleMesh = (baseCount == 1 and meshCount == 1 and footprint >= 28)
	local hugeSingleMesh = (baseCount == 1 and meshCount == 1 and volumeApprox >= 8000)

	local isComposite = forbiddenName or largeSingleMesh or hugeSingleMesh

	-- 1 MeshPart atomique (palmier, chaise, …) : petit footprint + nom atomique
	local isAtomicSingle = baseCount == 1
		and meshCount == 1
		and footprint < 28
		and volumeApprox < 8000
		and atomicName
		and not forbiddenName

	-- Multi-parts sans nom scène : OK
	local isAtomicMulti = baseCount >= 2 and not forbiddenName and footprint < 60

	local isAtomic = isAtomicSingle or isAtomicMulti
	if isComposite then
		isAtomic = false
	end

	local ok = isAtomic and not isComposite and baseCount >= 1
	local reason = "ok"
	if forbiddenName then
		reason = "forbidden_scene_name"
	elseif largeSingleMesh or hugeSingleMesh then
		reason = "inseparable_scene_mesh"
	elseif baseCount == 0 then
		reason = "no_geometry"
	elseif not isAtomic then
		reason = "not_atomic"
	end

	return {
		Ok = ok,
		Reason = reason,
		BasePartCount = baseCount,
		MeshPartCount = meshCount,
		BoundSize = bound,
		IsAtomic = isAtomic,
		IsCompositeScene = isComposite or (not isAtomic and baseCount == 1 and meshCount == 1),
	}
end

-- Validation obligatoire avant placement Summer Zone.
function SummerDecorSceneClassifier.ValidateForPlacement(root: Instance, displayName: string?): (boolean, Classification)
	local c = SummerDecorSceneClassifier.Classify(root, displayName)
	return c.Ok, c
end

return SummerDecorSceneClassifier
