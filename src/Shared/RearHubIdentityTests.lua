--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RearHubIdentity = require(Shared.RearHubIdentity)

local RearHubIdentityTests = {}

function RearHubIdentityTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[RearHubIdentityTests] FAIL:", msg)
			ok = false
		end
	end

	--------------------------------------------------------------------
	-- Exact 1 MeshPart gagne contre Palm Tree 4 MeshParts
	--------------------------------------------------------------------
	local candidates = {
		{
			Name = "Palm Tree.",
			Path = "Workspace.StudioDecoration.SummerZoneDecor.Nature.Palm Tree.",
			MeshParts = 4,
			MeshIds = 4,
		},
		{
			Name = "3d stage arena prop",
			Path = "Workspace.3d stage arena prop",
			MeshParts = 1,
			MeshIds = 1,
			MeshIdList = { "rbxassetid://111" },
		},
	}
	local chosen, reason = RearHubIdentity.SelectBestCandidate(candidates)
	check(chosen ~= nil, "un candidat doit être choisi")
	if chosen then
		check(chosen.Name == "3d stage arena prop", "modèle exact gagne (pas le palmier)")
		check(chosen.MeshParts == 1, "le gagnant a 1 MeshPart")
		check(reason == "exact_name", "raison = exact_name")
	end
	check(RearHubIdentity.IsForbiddenPathOrName(candidates[1].Path, candidates[1].Name), "palmier rejeté")
	check(RearHubIdentity.SelectionRank(candidates[1].Name, candidates[1].Path) == nil, "rank palm = nil")

	-- Aucun « largest » : uniquement palm → aucun candidat
	local onlyPalm = {
		{
			Name = "Palm Tree.",
			Path = "Workspace.StudioDecoration.SummerZoneDecor.Nature.Palm Tree.",
			MeshParts = 4,
			MeshIds = 4,
		},
	}
	local none, noneReason = RearHubIdentity.SelectBestCandidate(onlyPalm)
	check(none == nil and noneReason == nil, "pas de largest fallback : palm seul → nil")

	--------------------------------------------------------------------
	-- Archive Palm Tree invalide
	--------------------------------------------------------------------
	local palmArchive: any = {
		SourceModelName = "Palm Tree.",
		SourcePath = "Workspace.StudioDecoration.SummerZoneDecor.Nature.Palm Tree.",
		SourceMeshCount = 4,
		SourceValidated = true,
	}
	local validPalm, reasonPalm = RearHubIdentity.IsValidArchiveMeta(palmArchive)
	check(not validPalm, "archive Palm Tree invalide")
	check(type(reasonPalm) == "string", "raison invalidation présente")

	local goodArchive: any = {
		SourceModelName = "3d stage arena prop",
		SourcePath = "Workspace.3d stage arena prop",
		SourceMeshCount = 1,
		SourceValidated = true,
	}
	local validGood, reasonGood = RearHubIdentity.IsValidArchiveMeta(goodArchive)
	check(validGood, "archive exacte valide: " .. tostring(reasonGood))

	--------------------------------------------------------------------
	-- Échelle uniforme
	--------------------------------------------------------------------
	local srcSz = Vector3.new(3.5, 1.2, 2.8)
	local scale = RearHubIdentity.ComputeUniformScale(srcSz, 84, 60)
	check(scale > 10, "échelle doit agrandir fortement le modèle miniature")
	local after = Vector3.new(srcSz.X * scale, srcSz.Y * scale, srcSz.Z * scale)
	check(not RearHubIdentity.IsStillSourceTiny(after), "après scale, plus tiny")
	check(RearHubIdentity.IsStillSourceTiny(srcSz), "source reste tiny avant scale")

	--------------------------------------------------------------------
	-- Identity match MeshIds
	--------------------------------------------------------------------
	local ids = { "rbxassetid://999" }
	local match, why = RearHubIdentity.IdentityMatchesExact(
		"3d stage arena prop",
		"Workspace.3d stage arena prop",
		ids,
		ids
	)
	check(match, "identity ok: " .. tostring(why))
	local noMatch, _ = RearHubIdentity.IdentityMatchesExact(
		"3d stage arena prop",
		"Workspace.3d stage arena prop",
		{ "rbxassetid://1" },
		{ "rbxassetid://999" }
	)
	check(not noMatch, "mesh ids mismatch → fail")
	local palmPath, _ = RearHubIdentity.IdentityMatchesExact(
		"3d stage arena prop",
		"Workspace.SummerZoneDecor.Palm Tree.",
		ids,
		ids
	)
	check(not palmPath, "chemin palm → fail identity")

	if ok then
		print("[RearHubIdentityTests] ALL PASS")
	else
		warn("[RearHubIdentityTests] SOME FAILED")
	end
	return ok
end

return RearHubIdentityTests
