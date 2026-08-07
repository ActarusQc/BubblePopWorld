--!strict
-- Finition locale « Pearlescent Toy » pour les bulles.
-- Deux petites couches visuelles seulement sur les bulles proches :
--   1) un large dôme nacré translucide qui laisse la bordure colorée visible;
--   2) un petit reflet fixe qui donne l'aspect jouet/glossy.
-- Aucune vraie lumière, aucun Glass, aucune collision et aucune logique gameplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Style = require(Shared:WaitForChild("BubblePearlescentStyle")) :: any

if Style.Enabled ~= true then
	return
end

type Decoration = {
	shell: Part,
	shellMesh: SpecialMesh,
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

local function destroyDecoration(part: BasePart)
	local state = decorated[part]
	decorated[part] = nil
	wantedDistance[part] = nil
	if state then
		if state.shell.Parent then
			state.shell:Destroy()
		end
		if state.glint.Parent then
			state.glint:Destroy()
		end
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

local function makeVisualPart(name: string, source: BasePart, offset: Vector3): (Part, SpecialMesh)
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

local function shellOffset(part: BasePart): Vector3
	return Vector3.new(0, Style.ShellYOffset, 0)
end

local function glintOffset(part: BasePart): Vector3
	local f = Style.GlintOffsetFraction
	return Vector3.new(part.Size.X * f.X, part.Size.Y * f.Y, part.Size.Z * f.Z)
end

local function updateGeometry(part: BasePart, state: Decoration)
	local baseScale = baseMeshScale(part)

	state.shell.Size = part.Size
	state.shellMesh.Scale = Vector3.new(
		baseScale.X * Style.ShellScaleXZ,
		baseScale.Y * Style.ShellScaleY,
		baseScale.Z * Style.ShellScaleXZ
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
	if existing and existing.shell.Parent and existing.glint.Parent then
		return existing
	end
	if not part.Parent then
		return nil
	end

	local shell, shellMesh = makeVisualPart(Style.ShellName, part, shellOffset(part))
	local glint, glintMesh = makeVisualPart(Style.GlintName, part, glintOffset(part))

	local state: Decoration = {
		shell = shell,
		shellMesh = shellMesh,
		glint = glint,
		glintMesh = glintMesh,
	}
	decorated[part] = state
	updateGeometry(part, state)
	return state
end

local function hideDecoration(state: Decoration)
	state.shell.Transparency = 1
	state.glint.Transparency = 1
end

local function updateDecoration(part: BasePart, distance: number)
	local state = decorated[part]
	if not state or not state.shell.Parent or not state.glint.Parent or not part.Parent then
		return
	end

	local zoneIdAny = part:GetAttribute("ZoneId")
	if type(zoneIdAny) ~= "string" or not Style.IsZoneEnabled(zoneIdAny) then
		hideDecoration(state)
		return
	end

	local alive = part:GetAttribute("Alive") == true and part.Transparency < 0.99
	if not alive then
		hideDecoration(state)
		return
	end

	local isSpecial = part:GetAttribute("IsSpecial") == true
	state.shell.Material = Style.ShellMaterial
	state.shell.Color = Style.ResolveShellColor(part.Color, isSpecial)
	state.shell.Reflectance = 0
	state.shell.CastShadow = false
	state.shell.Transparency = Style.ResolveTransparency(distance, maxDistance)

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
					table.insert(candidates, {
						part = part,
						distance = distance,
					})
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

print(("[BubblePearlescent] v2 enabled | mobile=%s | max=%d | distance=%d")
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
