--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.SummerDecorConfig)

local SummerDecorConfigTests = {}

function SummerDecorConfigTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[SummerDecorConfigTests] FAIL:", msg)
			ok = false
		end
	end

	check(Config.ApprovedAssetIds[18953379883] == nil, "posts not approved")
	check(Config.IsApproved(18953379883) == false, "IsApproved false")
	check(Config.Assets.StringLightPosts[1] == 18953379883, "post id")
	check(Config.Assets.StringLights[1] == 93169410099587, "string id")
	check(Config.Security.RequireManualApproval == true, "manual approval")
	check(Config.Security.SanitizerVersion >= 2, "sanitizer version")
	check(Config.Placement.PostAssetId == 18953379883, "Placement.PostAssetId")
	check(Config.Placement.StringAssetId == 93169410099587, "Placement.StringAssetId")
	check(type(Config.ApprovedTemplateKeys) == "table", "ApprovedTemplateKeys")
	check(Config.IsTemplateApproved("999_1") == false, "template not approved by default")
	check(Config.IsCompositeRejected(4757336022) == true, "fused beach kit CompositeRejected")
	check(Config.IsCompositeRejected(5633800112) == true, "second fused kit rejected")
	check(Config.MatchesFusedSceneName("tropical+beach+setup+3d+model") == true, "fused name pattern")
	check(Config.MatchesFusedSceneName("tripo_convert_ab71c6ea") == true, "tripo_convert pattern")
	check(Config.MatchesFusedSceneName("beach+lifeguard+tower+3d+model") == false, "lifeguard not fused-by-name")
	local ids = Config.ListCandidateAssetIds()
	check(table.find(ids, 4757336022) == nil, "rejected not in candidates")
	check(#ids >= 14, "candidates listed without fused kits")
	check(Config.GetCategoryForAssetId(762353835) == "PalmTrees", "PalmTrees category")
	check(Config.Assets.LifeguardTowers ~= nil, "LifeguardTowers category Structures")

	if ok then
		print("[SummerDecorConfigTests] OK")
	end
	return ok
end

return SummerDecorConfigTests
