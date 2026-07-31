--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Split = require(Shared.SummerDecorPropSplit)

local SummerDecorPropSplitTests = {}

function SummerDecorPropSplitTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[SummerDecorPropSplitTests] FAIL:", msg)
			ok = false
		end
	end

	-- Inseparable single MeshPart
	do
		local root = Instance.new("Model")
		local m = Instance.new("MeshPart")
		m.Size = Vector3.new(10, 10, 10)
		m.Parent = root
		check(Split.IsInseparableComposite(root) == true, "single MeshPart inseparable")
		local props, err = Split.SplitIntoPropSources(root)
		check(err == "inseparable_mesh" and #props == 0, "split rejects inseparable")
		root:Destroy()
	end

	-- Multi Model children → multiple props
	do
		local root = Instance.new("Model")
		for i = 1, 3 do
			local sub = Instance.new("Model")
			sub.Name = "Item" .. i
			local p = Instance.new("Part")
			p.Size = Vector3.new(1, 1, 1)
			p.Parent = sub
			sub.Parent = root
		end
		check(Split.IsInseparableComposite(root) == false, "multi model separable")
		local props, err = Split.SplitIntoPropSources(root)
		check(err == nil and #props == 3, "split into 3 models")
		for _, p in ipairs(props) do
			p.Root:Destroy()
		end
		root:Destroy()
	end

	-- Welded parts stay one prop
	do
		local root = Instance.new("Model")
		local a = Instance.new("Part")
		a.Name = "Seat"
		a.Parent = root
		local b = Instance.new("Part")
		b.Name = "Back"
		b.Parent = root
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = b
		w.Parent = root
		local props, err = Split.SplitIntoPropSources(root)
		check(err == nil and #props == 1, "welded pair = one prop")
		if props[1] then
			local n = 0
			for _, d in ipairs(props[1].Root:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			if props[1].Root:IsA("BasePart") then
				n += 1
			end
			check(n >= 2, "welded prop keeps both parts")
			props[1].Root:Destroy()
		end
		root:Destroy()
	end

	-- Ground pivot
	do
		local m = Instance.new("Model")
		local p = Instance.new("Part")
		p.Size = Vector3.new(2, 4, 2)
		p.CFrame = CFrame.new(10, 20, 30)
		p.Parent = m
		Split.ApplyGroundPivot(m)
		local cf, size = m:GetBoundingBox()
		local pivot = m:GetPivot()
		check(math.abs(pivot.Position.Y - (cf.Position.Y - size.Y * 0.5)) < 0.05, "pivot at base")
		check(p.Anchored == true, "anchored")
		m:Destroy()
	end

	check(Split.MakeTemplateKey(123, 2) == "123_2", "TemplateKey format")

	if ok then
		print("[SummerDecorPropSplitTests] OK")
	end
	return ok
end

return SummerDecorPropSplitTests
