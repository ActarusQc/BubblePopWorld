--!strict
-- Finition locale « Pearlescent Toy » pour les bulles.
-- Une seule Part visuelle supplémentaire est utilisée par bulle proche du joueur.
-- Le coeur est Neon, sans lumière réelle ni collision : le rendu reste stable
-- quand la caméra tourne et n'altère jamais la logique serveur des bulles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Style = require(Shared:WaitForChild("BubblePearlescentStyle")) :: any

if Style.Enabled ~= true then
	return
end

type Decoration = {
	core: Part,
	mesh: SpecialMesh,
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
local maxActiveCores = if isMobile then Style.MobileMaxActiveCores else Style.DesktopMaxActiveCores

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
	if state and state.core.Parent then
		state.core:Destroy()
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

local function updateCoreGeometry(part: BasePart, state: Decoration)
	state.core.Size = part.Size
	local baseScale = baseMeshScale(part)
	state.mesh.Scale = Vector3.new(
		baseScale.X * Style.CoreScaleXZ,
		baseScale.Y * Style.CoreScaleY,
		baseScale.Z * Style.CoreScaleXZ
	)
end

local function ensureDecoration(part: BasePart): Decoration?
	local existing = decorated[part]
	if existing and existing.core.Parent then
		return existing
	end

	if not part.Parent then
		return nil
	end

	local core = Instance.new("Part")
	core.Name = Style.CoreName
	core.Archivable = false
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.CastShadow = false
	core.Massless = true
	core.Material = Style.CoreMaterial
	core.Reflectance = 0
	core.TopSurface = Enum.SurfaceType.Smooth
	core.BottomSurface = Enum.SurfaceType.Smooth
	core.Size = part.Size
	core.CFrame = part.CFrame * CFrame.new(0, Style.CoreYOffset, 0)
	core.Transparency = 1
	core.Parent = visualFolder

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "PearlCoreMesh"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = core

	local weld = Instance.new("WeldConstraint")
	weld.Name = "PearlCoreWeld"
	weld.Part0 = part
	weld.Part1 = core
	weld.Parent = core

	core.Anchored = false

	local state: Decoration = {
		core = core,
		mesh = mesh,
	}
	decorated[part] = state
	updateCoreGeometry(part, state)
	return state
end

local function updateDecoration(part: BasePart, distance: number)
	local state = decorated[part]
	if not state or not state.core.Parent or not part.Parent then
		return
	end

	local zoneIdAny = part:GetAttribute("ZoneId")
	if type(zoneIdAny) ~= "string" or not Style.IsZoneEnabled(zoneIdAny) then
		state.core.Transparency = 1
		return
	end

	local alive = part:GetAttribute("Alive") == true and part.Transparency < 0.99
	if not alive then
		state.core.Transparency = 1
		return
	end

	local isSpecial = part:GetAttribute("IsSpecial") == true
	state.core.Material = Style.CoreMaterial
	state.core.Color = Style.ResolveCoreColor(part.Color, isSpecial)
	state.core.Reflectance = 0
	state.core.CastShadow = false
	state.core.Transparency = Style.ResolveTransparency(distance, maxDistance)
	updateCoreGeometry(part, state)
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
	local count = math.min(#candidates, maxActiveCores)
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

print(("[BubblePearlescent] enabled | mobile=%s | max=%d | distance=%d")
	:format(tostring(isMobile), maxActiveCores, maxDistance))

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
