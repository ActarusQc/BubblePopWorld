--!strict
-- Effet client léger pour les bulles ciblées par Color Rush.
-- Le serveur ne conserve que le tag de gameplay; aucun SelectionBox cubique n'est créé.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ColorRushBubbleEffects = {}

local TARGET_TAG = "BPW_ColorRushTarget"
local EFFECT_NAME = "ColorRushPulse"
local active: { [BasePart]: Highlight } = {}
local started = false

local function removeEffect(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local highlight = active[instance]
	if highlight then
		active[instance] = nil
		highlight:Destroy()
	end
	local legacy = instance:FindFirstChild("EventMarkRing")
	if legacy and legacy:IsA("SelectionBox") then
		legacy:Destroy()
	end
end

local function addEffect(instance: Instance)
	if not instance:IsA("BasePart") or active[instance] then
		return
	end

	local legacy = instance:FindFirstChild("EventMarkRing")
	if legacy and legacy:IsA("SelectionBox") then
		legacy:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = EFFECT_NAME
	highlight.Adornee = instance
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = instance.Color:Lerp(Color3.new(1, 1, 1), 0.24)
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.78
	highlight.OutlineTransparency = 0.16
	highlight.Parent = instance
	active[instance] = highlight
end

function ColorRushBubbleEffects.Start()
	if started then
		return
	end
	started = true

	for _, instance in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		addEffect(instance)
	end

	CollectionService:GetInstanceAddedSignal(TARGET_TAG):Connect(addEffect)
	CollectionService:GetInstanceRemovedSignal(TARGET_TAG):Connect(removeEffect)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for bubble, highlight in pairs(active) do
			if not bubble.Parent or not highlight.Parent or not CollectionService:HasTag(bubble, TARGET_TAG) then
				removeEffect(bubble)
				continue
			end

			-- Décalage selon la position : les bulles respirent en vague plutôt qu'en bloc.
			local phaseOffset = (bubble.Position.X + bubble.Position.Z) * 0.075
			local wave = (math.sin(now * 3.2 + phaseOffset) + 1) * 0.5
			local markColor = bubble:GetAttribute("EventMarkColor")
			local baseColor = if typeof(markColor) == "Color3" then markColor :: Color3 else bubble.Color
			highlight.FillColor = baseColor:Lerp(Color3.new(1, 1, 1), 0.18 + wave * 0.18)
			highlight.OutlineColor = baseColor:Lerp(Color3.new(1, 1, 1), 0.58 + wave * 0.32)
			highlight.FillTransparency = 0.86 - wave * 0.16
			highlight.OutlineTransparency = 0.38 - wave * 0.26
		end
	end)
end

return ColorRushBubbleEffects
