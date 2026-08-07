--!strict
-- Tests purs TutorialConfig (sans Instances Roblox).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TutorialConfig = require(Shared.TutorialConfig)

local TutorialConfigTests = {}

function TutorialConfigTests.Run()
	local function check(cond: boolean, msg: string)
		if not cond then
			error("[TutorialConfigTests] " .. msg, 2)
		end
	end

	check(TutorialConfig.Enabled == true or TutorialConfig.Enabled == false, "Enabled bool")
	check(#TutorialConfig.Steps == 4, "exactement 4 étapes")
	check(TutorialConfig.FirstStepId() == 1, "FirstStepId == 1")
	check(TutorialConfig.LastStepId() == 4, "LastStepId == 4")
	check(TutorialConfig.NextStepId(1) == 2, "1 → 2")
	check(TutorialConfig.NextStepId(4) == nil, "4 → fin")

	local s1 = TutorialConfig.GetStep(1)
	check(s1 ~= nil and s1.Condition == "PopCount", "étape 1 PopCount")
	check(s1 ~= nil and (s1.Threshold or 0) >= 1, "étape 1 seuil > 0")
	check(s1 ~= nil and s1.Reward.Kind == "Coins", "étape 1 coins")

	local s2 = TutorialConfig.GetStep(2)
	check(s2 ~= nil and s2.Condition == "BackpackSold", "étape 2 vente")

	local s3 = TutorialConfig.GetStep(3)
	check(s3 ~= nil and s3.Condition == "AcquireTool", "étape 3 outil")
	check(s3 ~= nil and s3.Guide == true, "étape 3 guide")
	check(s3 ~= nil and s3.ToolId == TutorialConfig.Ids.HammerToolId, "étape 3 marteau")

	local s4 = TutorialConfig.GetStep(4)
	check(s4 ~= nil and s4.Condition == "ToolMultiPop", "étape 4 multi")
	check(s4 ~= nil and (s4.Threshold or 0) >= 2, "étape 4 seuil multi ≥ 2")

	local ids: { [number]: boolean } = {}
	for _, step in ipairs(TutorialConfig.Steps) do
		check(type(step.Message) == "string" and step.Message ~= "", "message étape " .. step.Id)
		check(ids[step.Id] ~= true, "id unique " .. step.Id)
		ids[step.Id] = true
		check(step.Reward ~= nil, "reward étape " .. step.Id)
	end

	print("[TutorialConfigTests] OK")
end

return TutorialConfigTests
