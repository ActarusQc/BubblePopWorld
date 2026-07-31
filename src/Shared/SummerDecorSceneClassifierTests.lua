--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classifier = require(Shared.SummerDecorSceneClassifier)

local SummerDecorSceneClassifierTests = {}

function SummerDecorSceneClassifierTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[SummerDecorSceneClassifierTests] FAIL:", msg)
			ok = false
		end
	end

	check(Classifier.IsForbiddenSceneName("tropical+beach+setup+3d+model") == true, "setup scene forbidden")
	check(Classifier.IsForbiddenSceneName("tripo_convert_ab71c6ea") == true, "tripo_convert forbidden")
	check(Classifier.LooksAtomicByName("Prop_01_PalmTree") == true, "palm atomic")
	check(Classifier.LooksAtomicByName("beach+lifeguard+tower+3d+model") == true, "lifeguard atomic name")

	do
		local m = Instance.new("Model")
		m.Name = "tropical+beach+setup+3d+model"
		local mesh = Instance.new("MeshPart")
		mesh.Name = "tripo_node_581b9abf"
		mesh.Size = Vector3.new(80, 20, 60)
		mesh.Parent = m
		local c = Classifier.Classify(m, m.Name)
		check(c.IsCompositeScene == true, "large setup = composite")
		check(c.Ok == false, "setup not placeable")
		m:Destroy()
	end

	do
		local m = Instance.new("Model")
		m.Name = "Prop_01_PalmTree"
		local mesh = Instance.new("MeshPart")
		mesh.Size = Vector3.new(4, 12, 4)
		mesh.Parent = m
		local placeOk = Classifier.ValidateForPlacement(m, m.Name)
		check(placeOk == true, "small palm placeable")
		m:Destroy()
	end

	if ok then
		print("[SummerDecorSceneClassifierTests] OK")
	end
	return ok
end

return SummerDecorSceneClassifierTests
