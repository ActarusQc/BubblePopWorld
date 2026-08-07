--!strict
-- Observateur temporaire : qui touche CFrame/Size de BubbleTransitInteractionAnchor.
-- Actif uniquement en Studio. Installe AVANT Builders / Migrations.

local RunService = game:GetService("RunService")

local TransitAnchorWatch = {}

local installed = false
local conns: { RBXScriptConnection } = {}

local function logChange(kind: string, detail: string)
	print("[TransitAnchorWatch]", kind)
	print("[TransitAnchorWatch]", detail)
	print("[TransitAnchorWatch] time=", os.clock())
	print("[TransitAnchorWatch] traceback:\n", debug.traceback())
end

local function watchPart(a: BasePart)
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)

	local lastCf = a.CFrame
	local lastSize = a.Size
	local lastParent = a.Parent

	table.insert(conns, a:GetPropertyChangedSignal("CFrame"):Connect(function()
		logChange(
			"CFrame changed",
			string.format("old=%s new=%s", tostring(lastCf), tostring(a.CFrame))
		)
		lastCf = a.CFrame
	end))
	table.insert(conns, a:GetPropertyChangedSignal("Size"):Connect(function()
		logChange(
			"Size changed",
			string.format("old=%s new=%s", tostring(lastSize), tostring(a.Size))
		)
		lastSize = a.Size
	end))
	table.insert(conns, a.AncestryChanged:Connect(function(_child, parent)
		logChange(
			"Parent changed",
			string.format("old=%s new=%s", tostring(lastParent), tostring(parent))
		)
		lastParent = parent
	end))
	table.insert(conns, a.Destroying:Connect(function()
		logChange("Destroying", a:GetFullName())
	end))
	print("[TransitAnchorWatch] watching", a:GetFullName(), "pos=", tostring(a.Position), "size=", tostring(a.Size))
end

function TransitAnchorWatch.Install()
	if not RunService:IsStudio() then
		return
	end
	if installed then
		return
	end
	installed = true
	print("[TransitAnchorWatch] installed (Studio only)")

	local existing = workspace:FindFirstChild("BubbleTransitInteractionAnchor")
	if existing and existing:IsA("BasePart") then
		watchPart(existing)
	end

	workspace.ChildAdded:Connect(function(child)
		if child.Name == "BubbleTransitInteractionAnchor" and child:IsA("BasePart") then
			print("[TransitAnchorWatch] ChildAdded", child:GetFullName())
			print("[TransitAnchorWatch] traceback:\n", debug.traceback())
			watchPart(child)
		end
	end)
end

return TransitAnchorWatch
