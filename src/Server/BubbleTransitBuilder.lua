--!strict
-- Générateur idempotent : pastilles Bubble Transit ouvertes (départ = arrivée).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TravelConfig = require(Shared.TravelConfig)

local BubbleTransitBuilder = {}

local CYAN = Color3.fromRGB(60, 210, 255)
local BLUE = Color3.fromRGB(40, 120, 220)
local VIOLET = Color3.fromRGB(140, 90, 255)
local WHITE = Color3.fromRGB(240, 250, 255)

-- Anciennes pièces cabine / marqueurs séparés à purger.
local OBSOLETE_NAMES = {
	"GlassWallLeft",
	"GlassWallRight",
	"GlassWallBack",
	"PillarLeft",
	"PillarRight",
	"Roof",
	"TitleSign",
	"GlowRingHigh",
	"GlowRingLow",
	"LightHost",
	"Platform",
	"TitleBillboard",
}

local function tagGenerated(inst: Instance)
	inst:SetAttribute("GeneratedByCode", true)
	inst:SetAttribute("BubbleTransit", true)
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	tagGenerated(folder)
	return folder
end

local function ensurePart(parent: Instance, name: string): BasePart
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local p = Instance.new("Part")
	p.Name = name
	p.Parent = parent
	tagGenerated(p)
	return p
end

local function ensureAttachment(parent: BasePart, name: string): Attachment
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = parent
	tagGenerated(a)
	return a
end

local function ensureBillboard(parent: Instance, name: string): BillboardGui
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BillboardGui") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Parent = parent
	tagGenerated(gui)
	return gui
end

local function ensureParticle(parent: Instance, name: string): ParticleEmitter
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("ParticleEmitter") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local pe = Instance.new("ParticleEmitter")
	pe.Name = name
	pe.Parent = parent
	tagGenerated(pe)
	return pe
end

local function ensurePointLight(parent: Instance, name: string): PointLight
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("PointLight") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local light = Instance.new("PointLight")
	light.Name = name
	light.Parent = parent
	tagGenerated(light)
	return light
end

local function destroyNamed(parent: Instance, name: string)
	local child = parent:FindFirstChild(name)
	if child then
		child:Destroy()
	end
end

local function scrubNonPadCollisions(model: Model, pad: BasePart)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") and desc ~= pad then
			desc.CanCollide = false
			desc.CanTouch = false
			if desc.Name ~= "TransitTrigger" then
				desc.CanQuery = false
			end
		end
	end
end

local function buildPadModel(parent: Folder, placementKey: string, placement: any): Model
	local modelName = "BubbleTransit_" .. placement.TransitId
	local existing = parent:FindFirstChild(modelName)
	local model: Model
	if existing and existing:IsA("Model") then
		model = existing
	else
		if existing then
			existing:Destroy()
		end
		model = Instance.new("Model")
		model.Name = modelName
		model.Parent = parent
		tagGenerated(model)
	end

	for _, name in ipairs(OBSOLETE_NAMES) do
		destroyNamed(model, name)
	end

	local cf = TravelConfig.ResolveWorldCFrame(placement)
	model:SetAttribute("TransitId", placement.TransitId)
	model:SetAttribute("CurrentArea", placement.CurrentArea)
	model:SetAttribute("PlacementKey", placementKey)
	model:SetAttribute("ArrivalMarkerName", placement.ArrivalMarkerName)

	local D = TravelConfig.PadDimensions
	local dia = D.PadDiameter
	local height = D.PadHeight

	-- Seule pièce collision : pastille au sol
	local pad = ensurePart(model, "Pad")
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanTouch = false
	pad.CanQuery = true
	pad.CastShadow = false
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(height, dia, dia)
	pad.Material = Enum.Material.SmoothPlastic
	pad.Color = BLUE
	pad.Transparency = 0
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth
	-- Cylindre : axe X → rotation pour pose à plat sur le sol.
	pad.CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, height * 0.5, 0)

	-- Anneau néon (décor)
	local ring = ensurePart(model, "GlowRing")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, dia + 0.35, dia + 0.35)
	ring.Material = Enum.Material.Neon
	ring.Color = CYAN
	ring.Transparency = 0
	ring.CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, height + 0.06, 0)

	-- Centre lumineux
	local center = ensurePart(model, "GlowCenter")
	center.Anchored = true
	center.CanCollide = false
	center.CanTouch = false
	center.CanQuery = false
	center.CastShadow = false
	center.Shape = Enum.PartType.Cylinder
	center.Size = Vector3.new(0.08, dia * 0.45, dia * 0.45)
	center.Material = Enum.Material.Neon
	center.Color = VIOLET
	center.Transparency = 0.15
	center.CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, height + 0.04, 0)

	local effects = ensureFolder(model, "Effects")
	-- Host invisible pour lumière + particules (pas de collision)
	local fxHost = ensurePart(effects, "FxHost")
	fxHost.Anchored = true
	fxHost.CanCollide = false
	fxHost.CanTouch = false
	fxHost.CanQuery = false
	fxHost.Transparency = 1
	fxHost.Size = Vector3.new(0.2, 0.2, 0.2)
	fxHost.CFrame = cf * CFrame.new(0, height + 0.5, 0)

	local light = ensurePointLight(fxHost, "AmbientLight")
	light.Color = CYAN
	light.Brightness = 0.7
	light.Range = 6

	local sparkles = ensureParticle(fxHost, "Sparkles")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 5
	sparkles.Lifetime = NumberRange.new(0.9, 1.6)
	sparkles.Speed = NumberRange.new(0.6, 1.4)
	sparkles.SpreadAngle = Vector2.new(12, 12)
	sparkles.Acceleration = Vector3.new(0, 1.5, 0)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Color = ColorSequence.new(CYAN, VIOLET)
	sparkles.LightEmission = 0.55
	sparkles.LockedToPart = true

	-- Label flottant (aucun obstacle vertical)
	local labelHost = ensurePart(model, "BubbleTransitLabel")
	labelHost.Anchored = true
	labelHost.CanCollide = false
	labelHost.CanTouch = false
	labelHost.CanQuery = false
	labelHost.Transparency = 1
	labelHost.Size = Vector3.new(0.2, 0.2, 0.2)
	labelHost.CFrame = cf * CFrame.new(0, height + 3.2, 0)

	local billboard = ensureBillboard(labelHost, "LabelBillboard")
	billboard.Size = UDim2.fromOffset(150, 28)
	billboard.StudsOffset = Vector3.zero
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 48
	local title = billboard:FindFirstChild("Title")
	if not (title and title:IsA("TextLabel")) then
		if title then
			title:Destroy()
		end
		local t = Instance.new("TextLabel")
		t.Name = "Title"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.Text = "BUBBLE TRANSIT"
		t.TextColor3 = WHITE
		t.TextScaled = true
		t.Parent = billboard
		tagGenerated(t)
	else
		(title :: TextLabel).Text = "BUBBLE TRANSIT"
	end

	-- Trigger : uniquement au-dessus de la pastille
	local trigger = ensurePart(model, "TransitTrigger")
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanTouch = false
	trigger.CanQuery = true
	trigger.Transparency = 1
	trigger.CastShadow = false
	trigger.Size = D.TriggerSize
	trigger.CFrame = cf * CFrame.new(0, height + D.TriggerSize.Y * 0.5, 0)
	trigger:SetAttribute("TransitId", placement.TransitId)
	trigger:SetAttribute("CurrentArea", placement.CurrentArea)

	-- Attachment d'arrivée (référence hauteur spawn)
	local arrivalAttach = ensureAttachment(pad, "ArrivalAttachment")
	arrivalAttach.Position = Vector3.new(0, 3, 0)

	-- Marqueur d'arrivée invisible (même pastille, pas de 2e plateforme)
	local arrival = ensurePart(model, placement.ArrivalMarkerName)
	arrival.Name = placement.ArrivalMarkerName
	arrival.Anchored = true
	arrival.CanCollide = false
	arrival.CanTouch = false
	arrival.CanQuery = false
	arrival.Transparency = 1
	arrival.CastShadow = false
	arrival.Size = Vector3.new(1, 1, 1)
	-- Centre pastille ; TravelService fait encore marker.CFrame * CFrame.new(0, 3, 0)
	arrival.CFrame = cf * CFrame.new(0, height * 0.5, 0)
	arrival:SetAttribute("TravelArrival", true)

	-- Alias stable pour recherche
	destroyNamed(model, "TravelArrival")
	local alias = ensurePart(model, "TravelArrival")
	alias.Anchored = true
	alias.CanCollide = false
	alias.CanTouch = false
	alias.CanQuery = false
	alias.Transparency = 1
	alias.Size = Vector3.new(1, 1, 1)
	alias.CFrame = arrival.CFrame
	alias:SetAttribute("TravelArrival", true)
	alias:SetAttribute("MarkerName", placement.ArrivalMarkerName)

	scrubNonPadCollisions(model, pad)
	model.PrimaryPart = pad
	return model
end

local function clearLegacyArrivalFolder(root: Folder)
	local arrivals = root:FindFirstChild("ArrivalMarkers")
	if not arrivals then
		return
	end
	for _, child in ipairs(arrivals:GetChildren()) do
		child:Destroy()
	end
	arrivals:Destroy()
end

function BubbleTransitBuilder.EnsureTerminals(): Folder
	local gameZones = Workspace:FindFirstChild("GameZones")
	if not (gameZones and gameZones:IsA("Folder")) then
		gameZones = Instance.new("Folder")
		gameZones.Name = "GameZones"
		gameZones.Parent = Workspace
	end

	local root = ensureFolder(gameZones, "TravelTerminals")
	clearLegacyArrivalFolder(root)

	for key, placement in pairs(TravelConfig.CapsulePlacements) do
		buildPadModel(root, key, placement)
	end

	return root
end

function BubbleTransitBuilder.FindTerminalByTransitId(transitId: string): Model?
	local gameZones = Workspace:FindFirstChild("GameZones")
	local root = gameZones and gameZones:FindFirstChild("TravelTerminals")
	if not root then
		return nil
	end
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("TransitId") == transitId then
			return child
		end
	end
	return nil
end

function BubbleTransitBuilder.FindArrivalMarker(markerName: string): BasePart?
	local gameZones = Workspace:FindFirstChild("GameZones")
	local root = gameZones and gameZones:FindFirstChild("TravelTerminals")
	if not root then
		return nil
	end
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Model") then
			local named = child:FindFirstChild(markerName)
			if named and named:IsA("BasePart") then
				return named
			end
			local attrName = child:GetAttribute("ArrivalMarkerName")
			if attrName == markerName then
				local alias = child:FindFirstChild("TravelArrival")
				if alias and alias:IsA("BasePart") then
					return alias
				end
			end
		end
	end
	local found = Workspace:FindFirstChild(markerName, true)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

function BubbleTransitBuilder.GetTrigger(terminal: Model): BasePart?
	local trigger = terminal:FindFirstChild("TransitTrigger")
	if trigger and trigger:IsA("BasePart") then
		return trigger
	end
	return nil
end

return BubbleTransitBuilder
