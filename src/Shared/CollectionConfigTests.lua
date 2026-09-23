--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared").CollectionConfig)
local Tests = {}

function Tests.Run(): boolean
	local ok = true
	local function check(condition: boolean, message: string)
		if not condition then ok = false warn("[CollectionConfigTests] FAIL:", message) end
	end
	check(#Config.Items == 22, "22 bulles au catalogue")
	check(#Config.ByRarity.Common == 12, "12 communes")
	check(#Config.ByRarity.Rare == 6, "6 rares")
	check(#Config.ByRarity.Epic == 4, "4 épiques")
	check(Config.Rarities.Common.ZoneId == "ClassicZone", "communes dans ClassicZone")
	check(Config.Rarities.Rare.ZoneId == "SummerZone", "rares dans SummerZone")
	check(Config.Rarities.Epic.Enabled == false, "épiques désactivées avant la future zone")
	check(Config.PersonalChance(249) == 0, "pitié inactive avant 250 pops")
	check(Config.PersonalChance(250) == 1 / 500, "palier 250")
	check(Config.PersonalChance(400) == 1 / 250, "palier 400")
	check(Config.PersonalChance(550) == 1 / 100, "palier 550")
	check(Config.PersonalChance(650) == 1, "garantie 650")
	check(Config.RarityForZone("ClassicZone") == "Common", "cible personnelle commune en Classic")
	check(Config.RarityForZone("SummerZone") == "Rare", "cible personnelle rare en Summer")
	local ids = {}
	for _, def in ipairs(Config.Items) do
		check(ids[def.Id] == nil, "identifiant unique: " .. def.Id)
		ids[def.Id] = true
	end
	if ok then print("[CollectionConfigTests] OK") end
	return ok
end

return Tests
