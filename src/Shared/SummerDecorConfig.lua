--!strict
-- Source de vérité Rojo : IDs candidats / approuvés, sécurité, placement lumières Summer.

local SummerZoneConfig = require(script.Parent.SummerZoneConfig)

local SummerDecorConfig = {}

SummerDecorConfig.Assets = {
	StringLightPosts = {
		18953379883,
	},
	StringLights = {
		93169410099587,
	},
	PalmTrees = {
		762353835,
	},
	Rocks = {
		4453595550,
		16810807451,
	},
	TropicalPlants = {
		101615260056563,
		121730956352570,
	},
	Parasols = {
		898706770,
		140479009547664,
	},
	LoungeChairs = {
		962686574,
	},
	Surfboards = {
		5561729910,
		5295475675,
		132165054275404,
	},
	BeachBalls = {
		12355957802,
		735737347,
	},
	Sandcastles = {
		89138199,
	},
	-- Scènes fusionnées retirées des candidats (voir CompositeRejectedAssetIds).
	BeachProps = {},
	-- Tour de sauveteur : Structures (pas Nature). ID à renseigner si asset atomique validé.
	LifeguardTowers = {},
	Structures = {},
	TikiLights = {
		9560932611,
	},
}

--[[
	SourceAssetId du kit tropical+beach+setup+3d+model (1 MeshPart tripo_node_…).
	Anciens BeachProps Marketplace + IDs confirmés scène fusionnée.
]]
SummerDecorConfig.CompositeRejectedAssetIds = {
	[4757336022] = true,
	[5633800112] = true,
} :: { [number]: boolean }

-- Alias compat
SummerDecorConfig.BlacklistedAssetIds = SummerDecorConfig.CompositeRejectedAssetIds

-- Noms / fragments à purger partout (Workspace + caches).
SummerDecorConfig.FusedSceneNamePatterns = {
	"tropical+beach+setup",
	"tropical beach setup",
	"tripo_node_",
	"tripo_convert_",
	"beach+setup",
	"+setup+",
}

SummerDecorConfig.ApprovedAssetIds = {} :: { [number]: boolean }
SummerDecorConfig.ApprovedTemplateKeys = {} :: { [string]: boolean }

SummerDecorConfig.Security = {
	RejectAssetsContainingScripts = true,
	RequireManualApproval = true,
	SanitizerVersion = 3,
}

local postIds = SummerDecorConfig.Assets.StringLightPosts
local stringIds = SummerDecorConfig.Assets.StringLights

SummerDecorConfig.Placement = {
	PostAssetId = postIds[1],
	StringAssetId = stringIds[1],
	LightPerimeterSpacing = SummerZoneConfig.LightPerimeterSpacing,
	BoardClearanceStuds = 8,
}

function SummerDecorConfig.IsApproved(assetId: number): boolean
	if SummerDecorConfig.IsCompositeRejected(assetId) then
		return false
	end
	if SummerDecorConfig.ApprovedAssetIds[assetId] == true then
		return true
	end
	local prefix = tostring(assetId) .. "_"
	for key, approved in pairs(SummerDecorConfig.ApprovedTemplateKeys) do
		if approved == true and string.sub(key, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

function SummerDecorConfig.IsTemplateApproved(templateKey: string): boolean
	local assetId = tonumber(string.match(templateKey, "^(%d+)_"))
	if assetId and SummerDecorConfig.IsCompositeRejected(assetId) then
		return false
	end
	if SummerDecorConfig.ApprovedTemplateKeys[templateKey] == true then
		return true
	end
	if assetId and SummerDecorConfig.ApprovedAssetIds[assetId] == true then
		return true
	end
	return false
end

function SummerDecorConfig.IsCompositeRejected(assetId: number): boolean
	return SummerDecorConfig.CompositeRejectedAssetIds[assetId] == true
end

function SummerDecorConfig.IsBlacklisted(assetId: number): boolean
	return SummerDecorConfig.IsCompositeRejected(assetId)
end

function SummerDecorConfig.RegisterCompositeRejected(assetId: number)
	SummerDecorConfig.CompositeRejectedAssetIds[assetId] = true
end

function SummerDecorConfig.MatchesFusedSceneName(name: string): boolean
	local lower = string.lower(name)
	for _, pattern in ipairs(SummerDecorConfig.FusedSceneNamePatterns) do
		if string.find(lower, string.lower(pattern), 1, true) then
			return true
		end
	end
	return false
end

function SummerDecorConfig.ListCandidateAssetIds(): { number }
	local seen: { [number]: boolean } = {}
	local out: { number } = {}
	for _, list in pairs(SummerDecorConfig.Assets) do
		for _, id in ipairs(list) do
			if type(id) == "number" and not seen[id] and not SummerDecorConfig.IsCompositeRejected(id) then
				seen[id] = true
				table.insert(out, id)
			end
		end
	end
	table.sort(out)
	return out
end

function SummerDecorConfig.GetCategoryForAssetId(assetId: number): string?
	for category, list in pairs(SummerDecorConfig.Assets) do
		for _, id in ipairs(list) do
			if id == assetId then
				return category
			end
		end
	end
	return nil
end

return SummerDecorConfig
