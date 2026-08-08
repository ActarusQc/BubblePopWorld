--!strict
-- Finition locale « Pearlescent Toy » pour les bulles.
-- Près du joueur, la Part serveur est masquée uniquement sur ce client puis remplacée par :
--   1) un rim/disque nacré;
--   2) un dôme plus haut et plus doux;
--   3) un petit reflet blanc fixe.
-- La Part serveur conserve toute la collision et toute la logique gameplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Style = require(Shared:WaitForChild("BubblePearlescentStyle")) :: any

if Style.Enabled ~= true then
	return
end

type Decoration = {
	rim: Part,
	dome: Part,
	domeMesh: SpecialMesh,
	glint: Part,
	glintMesh: SpecialMesh,
}

type Candidate = {
	part: BasePart,
	distance: number,
}

local gameZones = workspace:WaitForChild("GameZones")

local oldFolder = workspace:FindFirstChild("_BPW_ClientPearlVisuals")
if oldFolder then
	oldFolder:Destroy()
end

local visualFolder = Instance.new("Folder")
visualFolder.Name = "_BPW_ClientPearlVisuals"
visualFolder.Archivable = false
visualFolder.Parent = workspace

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local maxDistance = if isMobile then Style.MobileMaxDistance else Style.DesktopMaxDistance
local maxActiveBubbles = if isMobile then Style.MobileMaxActiveBubbles else Style.DesktopMaxActiveBubbles

local tracked: { [BasePart]: boolean } = {}
local decorated: { [BasePart]: Decoration } = {}
local wantedDistance: { [BasePart]: number } = {}

local function isBubblePart(inst: Instance): boolean
	if not inst:IsA("BasePart") then
		return false
	end
	if inst:GetAttribute("CellX") == nil or inst:GetAttribute("CellZ") == nil then
		return false
	end
	local zoneId = inst:GetAttribute("ZoneId")
	return type(zoneId) == "string" and Style.IsZoneEnabled(zoneId)
end

local function register(inst: Instance)
	if isBubblePart(inst) then
		tracked[inst :: BasePart] = true
	end
end

local function restoreSource(part: BasePart)
	if part.Parent then
		part.LocalTransparencyModifier = 0
	end
end

local function destroyDecoration(part: BasePart)
	local state = decorated[part]
	decorated[part] = nil
	wantedDistance[part] = nil
	restoreSource(part)
	if state then
		if state.rim.Parent then state.rim:Destroy() end
		if state.dome.Parent then state.dome:Destroy() end
		if state.glint.Parent then state.glint:Destroy() end
	end
end

local function unregister(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local part = inst :: BasePart
	tracked[part] = nil
	destroyDecoration(part)
end

local function baseMeshScale(part: BasePart): Vector3
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh:IsA("SpecialMesh") then
		return mesh.Scale
	end
	return Vector3.new(0.92, 0.98, 0.92)
end

local function makeSphereVisual(name: string, source: BasePart, offset: Vector3): (Part, SpecialMesh)
	local p = Instance.new("Part")
	p.Name = name
	p.Archivable = false
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Massless = true
	p.Reflectance = 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = source.Size
	p.CFrame = source.CFrame * CFrame.new(offset)
	p.Transparency = 1
	p.Parent = visualFolder

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = source
	weld.Part1 = p
	weld.Parent = p
	p.Anchored = false

	return p, mesh
end

local function makeRim(source: BasePart): Part
	local baseScale = baseMeshScale(source)
	local diameter = math.min(source.Size.X * baseScale.X, source.Size.Z * baseScale.Z) * Style.RimDiameterScale

	local rim = Instance.new("Part")
	rim.Name = Style.RimName
	rim.Archivable = false
	rim.Shape = Enum.PartType.Cylinder
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanTouch = false
	rim.CanQuery = false
	rim.CastShadow = false
	rim.Massless = true
	rim.Reflectance = 0
	rim.TopSurface = Enum.SurfaceType.Smooth
	rim.BottomSurface = Enum.SurfaceType.Smooth
	rim.Size = Vector3.new(Style.RimThickness, diameter, diameter)
	rim.CFrame = source.CFrame
		* CFrame.new(0, Style.RimYOffset, 0)
		* CFrame.Angles(0, 0, math.rad(90))
	rim.Transparency = 1
	rim.Parent = visualFolder

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = source
	weld.Part1 = rim
	weld.Parent = rim
	rim.Anchored = false

	return rim
end

local function glintOffset(part: BasePart): Vector3
	local f = Style.GlintOffsetFraction
	return Vector3.new(part.Size.X * f.X, part.Size.Y * f.Y, part.Size.Z * f.Z)
end

local function updateGeometry(part: BasePart, state: Decoration)
	local baseScale = baseMeshScale(part)
	local diameter = math.min(part.Size.X * baseScale.X, part.Size.Z * baseScale.Z) * Style.RimDiameterScale

	state.rim.Size = Vector3.new(Style.RimThickness, diameter, diameter)

	state.dome.Size = part.Size
	state.domeMesh.Scale = Vector3.new(
		baseScale.X * Style.DomeScaleXZ,
		baseScale.Y * Style.DomeScaleY,
		baseScale.Z * Style.DomeScaleXZ
	)

	state.glint.Size = part.Size
	local gs = Style.GlintScale
	state.glintMesh.Scale = Vector3.new(
		baseScale.X * gs.X,
		baseScale.Y * gs.Y,
		baseScale.Z * gs.Z
	)
end

local function ensureDecoration(part: BasePart): Decoration?
	local existing = decorated[part]
	if existing and existing.rim.Parent and existing.dome.Parent and existing.glint.Parent then
		return existing
	end
	if not part.Parent then
		return nil
	end

	local rim = makeRim(part)
	local dome, domeMesh = makeSphereVisual(
		Style.DomeName,
		part,
		Vector3.new(0, Style.DomeYOffset, 0)
	)
	local glint, glintMesh = makeSphereVisual(Style.GlintName, part, glintOffset(part))

	local state: Decoration = {
		rim = rim,
		dome = dome,
		domeMesh = domeMesh,
		glint = glint,
		glintMesh = glintMesh,
	}
	decorated[part] = state
	updateGeometry(part, state)
	return state
end

local function hideDecoration(part: BasePart, state: Decoration)
	state.rim.Transparency = 1
	state.dome.Transparency = 1
	state.glint.Transparency = 1
	restoreSource(part)
end

local function updateDecoration(part: BasePart, distance: number)
	local state = decorated[part]
	if not state or not state.rim.Parent or not state.dome.Parent or not state.glint.Parent or not part.Parent then
		return
	end

	local zoneIdAny = part:GetAttribute("ZoneId")
	if type(zoneIdAny) ~= "string" or not Style.IsZoneEnabled(zoneIdAny) then
		hideDecoration(part, state)
		return
	end

	local alive = part:GetAttribute("Alive") == true and part.Transparency < 0.99
	if not alive then
		hideDecoration(part, state)
		return
	end

	local isSpecial = part:GetAttribute("IsSpecial") == true
	local domeTransparency = Style.ResolveTransparency(distance, maxDistance)

	-- Masque seulement le rendu de la Part serveur sur ce client.
	-- Collision, attributs, pop et événements restent sur la vraie Part.
	part.LocalTransparencyModifier = 1

	state.rim.Material = Style.RimMaterial
	state.rim.Color = Style.ResolveRimColor(part.Color)
	state.rim.Reflectance = 0
	state.rim.CastShadow = false
	state.rim.Transparency = math.clamp(Style.RimTransparency + domeTransparency * 0.18, 0, 1)

	state.dome.Material = Style.DomeMaterial
	state.dome.Color = Style.ResolveDomeColor(part.Color, isSpecial)
	state.dome.Reflectance = 0
	state.dome.CastShadow = false
	state.dome.Transparency = domeTransparency

	state.glint.Material = Style.GlintMaterial
	state.glint.Color = Style.GlintColor
	state.glint.Reflectance = 0
	state.glint.CastShadow = false
	state.glint.Transparency = Style.ResolveGlintTransparency(distance, maxDistance)

	updateGeometry(part, state)
end

local function refreshLod()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraPos = camera.CFrame.Position
	local candidates: { Candidate } = {}

	for part in pairs(tracked) do
		if not part.Parent then
			tracked[part] = nil
			destroyDecoration(part)
		else
			local zoneId = part:GetAttribute("ZoneId")
			local alive = part:GetAttribute("Alive") == true and part.Transparency < 0.99
			if type(zoneId) == "string" and Style.IsZoneEnabled(zoneId) and alive then
				local distance = (cameraPos - part.Position).Magnitude
				if distance <= maxDistance then
					table.insert(candidates, { part = part, distance = distance })
				end
			end
		end
	end

	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.distance < b.distance
	end)

	local nextWanted: { [BasePart]: number } = {}
	local count = math.min(#candidates, maxActiveBubbles)
	for i = 1, count do
		local candidate = candidates[i]
		nextWanted[candidate.part] = candidate.distance
		ensureDecoration(candidate.part)
	end

	for part in pairs(decorated) do
		if nextWanted[part] == nil then
			destroyDecoration(part)
		end
	end

	wantedDistance = nextWanted
end

local function refreshVisuals()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPos = camera.CFrame.Position
	for part in pairs(wantedDistance) do
		if part.Parent and decorated[part] then
			local distance = (cameraPos - part.Position).Magnitude
			updateDecoration(part, distance)
		end
	end
end

for _, inst in ipairs(gameZones:GetDescendants()) do
	register(inst)
end

gameZones.DescendantAdded:Connect(register)
gameZones.DescendantRemoving:Connect(unregister)

refreshLod()
refreshVisuals()

print(("[BubblePearlescent] v3 enabled | mobile=%s | max=%d | distance=%d")
	:format(tostring(isMobile), maxActiveBubbles, maxDistance))

task.spawn(function()
	while visualFolder.Parent do
		task.wait(Style.LodRefreshSeconds)
		refreshLod()
	end
end)

task.spawn(function()
	while visualFolder.Parent do
		task.wait(Style.VisualRefreshSeconds)
		refreshVisuals()
	end
end)
