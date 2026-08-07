--!strict
-- Identité + sélection du modèle hub Tripo (pure, sans Instance).
-- Priorité nom exact > quantité MeshParts. Aucun « largest fallback ».

local RearHubIdentity = {}

RearHubIdentity.EXACT_SOURCE_NAME = "3d stage arena prop"
RearHubIdentity.STAGE_ARENA_TOKEN = "stage arena prop"

export type Candidate = {
	Name: string,
	Path: string,
	MeshParts: number,
	MeshIds: number,
	MeshIdList: { string }?,
}

export type ArchiveMeta = {
	SourceModelName: string?,
	SourcePath: string?,
	SourceMeshCount: number?,
	SourceValidated: boolean?,
	MeshIdList: { string }?,
}

local function lower(s: string): string
	return string.lower(s)
end

function RearHubIdentity.IsForbiddenPathOrName(path: string, name: string): boolean
	local lp = lower(path)
	local ln = lower(name)

	if string.find(ln, "palm tree", 1, true) then
		return true
	end
	if string.find(lp, "palm tree", 1, true) then
		return true
	end
	if string.find(lp, "summerzonedecor", 1, true) then
		return true
	end
	if string.find(lp, "palmtrees", 1, true) then
		return true
	end
	-- Dossiers décor / nature / assets (pas Workspace root) — .nature. ou segment
	if string.find(lp, ".nature.", 1, true) or string.find(lp, "nature.", 1, true) then
		-- Ne bloquer que si chemin décoratif typique, pas un nom "Nature" isolé dans Tripo
		if string.find(lp, "summerzonedecor", 1, true)
			or string.find(lp, "studiodecoration", 1, true)
			or string.find(lp, "decor", 1, true)
		then
			return true
		end
	end
	if string.find(lp, "studiodecoration", 1, true) then
		return true
	end
	-- Segments .Decor. / /Decor/
	if string.find(lp, ".decor.", 1, true) or string.find(lp, "decoration", 1, true) then
		return true
	end
	-- Évite de prendre des dossiers d'assets génériques sous Summer
	if string.find(lp, "summerzonedecor", 1, true) then
		return true
	end

	return false
end

function RearHubIdentity.IsExactSourceName(name: string): boolean
	return lower(name) == lower(RearHubIdentity.EXACT_SOURCE_NAME)
end

function RearHubIdentity.ContainsStageArenaProp(name: string): boolean
	return string.find(lower(name), lower(RearHubIdentity.STAGE_ARENA_TOKEN), 1, true) ~= nil
end

--- Rang de sélection : 1 = exact, 2 = partial stage arena, nil = rejeter.
function RearHubIdentity.SelectionRank(name: string, path: string): number?
	if RearHubIdentity.IsForbiddenPathOrName(path, name) then
		return nil
	end
	if RearHubIdentity.IsExactSourceName(name) then
		return 1
	end
	if RearHubIdentity.ContainsStageArenaProp(name) then
		return 2
	end
	return nil
end

function RearHubIdentity.HasMinimumGeometry(meshParts: number, meshIds: number): boolean
	return meshParts >= 1 and meshIds >= 1
end

--- Sélection stricte parmi une liste de candidats (tests + runtime).
--- 1 exact · 2 stage arena · aucun largest fallback.
function RearHubIdentity.SelectBestCandidate(candidates: { Candidate }): (Candidate?, string?)
	local bestExact: Candidate? = nil
	local bestPartial: Candidate? = nil

	for _, c in ipairs(candidates) do
		if not RearHubIdentity.HasMinimumGeometry(c.MeshParts, c.MeshIds) then
			continue
		end
		local rank = RearHubIdentity.SelectionRank(c.Name, c.Path)
		if rank == 1 then
			if not bestExact then
				bestExact = c
			end
		elseif rank == 2 then
			if not bestPartial then
				bestPartial = c
			end
		end
	end

	if bestExact then
		return bestExact, "exact_name"
	end
	if bestPartial then
		return bestPartial, "stage_arena_partial"
	end
	return nil, nil
end

function RearHubIdentity.IsValidArchiveMeta(meta: ArchiveMeta): (boolean, string?)
	local name = meta.SourceModelName
	local path = meta.SourcePath or ""
	if type(name) ~= "string" or name == "" then
		return false, "missing BPW_SourceModelName"
	end
	if meta.SourceValidated ~= true then
		return false, "BPW_SourceValidated != true"
	end
	if RearHubIdentity.IsForbiddenPathOrName(path, name) then
		return false, "wrong asset identity (decor/palm)"
	end
	if not RearHubIdentity.IsExactSourceName(name) and not RearHubIdentity.ContainsStageArenaProp(name) then
		return false, "wrong asset identity"
	end
	if type(meta.SourceMeshCount) == "number" and (meta.SourceMeshCount :: number) < 1 then
		return false, "SourceMeshCount < 1"
	end
	return true, nil
end

function RearHubIdentity.ComputeUniformScale(sourceSize: Vector3, targetWidth: number, targetDepth: number): number
	if sourceSize.X < 1e-3 or sourceSize.Z < 1e-3 then
		return 1
	end
	local widthScale = targetWidth / sourceSize.X
	local depthScale = targetDepth / sourceSize.Z
	local uniform = math.min(widthScale, depthScale)
	-- Garde-fous : éviter collapse ou explosion aberrante
	if uniform < 0.01 then
		uniform = 0.01
	elseif uniform > 500 then
		uniform = 500
	end
	return uniform
end

-- Taille source observée ~ (3.5, 1.2, 2.8) — encore trop petite après ScaleTo = FAIL
function RearHubIdentity.IsStillSourceTiny(size: Vector3): boolean
	return size.X < 12 and size.Y < 6 and size.Z < 12
end

function RearHubIdentity.IdentityMatchesExact(
	sourceModelName: string?,
	sourcePath: string?,
	runtimeMeshIds: { string },
	sourceMeshIds: { string }
): (boolean, string?)
	if type(sourceModelName) ~= "string" or not RearHubIdentity.IsExactSourceName(sourceModelName) then
		return false, "source model name not exact Tripo"
	end
	local path = sourcePath or ""
	if RearHubIdentity.IsForbiddenPathOrName(path, sourceModelName) then
		return false, "source path is decor/palm"
	end
	if #sourceMeshIds < 1 or #runtimeMeshIds < 1 then
		return false, "missing mesh ids"
	end
	-- Tous les meshIds source doivent apparaître côté runtime (ScaleTo conserve MeshId)
	local runtimeSet: { [string]: boolean } = {}
	for _, id in ipairs(runtimeMeshIds) do
		if id ~= "" then
			runtimeSet[id] = true
		end
	end
	for _, id in ipairs(sourceMeshIds) do
		if id ~= "" and not runtimeSet[id] then
			return false, "runtime mesh ids mismatch source"
		end
	end
	return true, nil
end

function RearHubIdentity.MeshIdsEqual(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	local counts: { [string]: number } = {}
	for _, id in ipairs(a) do
		counts[id] = (counts[id] or 0) + 1
	end
	for _, id in ipairs(b) do
		if not counts[id] or counts[id] < 1 then
			return false
		end
		counts[id] -= 1
	end
	return true
end

return RearHubIdentity
