--!strict
-- Modèles 3D stylisés des Tools (Parts soudées au Handle).

local ToolModels = {}

local function weld(handle: BasePart, part: BasePart, offset: CFrame)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = handle.CFrame * offset
	part.Parent = handle.Parent
	local w = Instance.new("WeldConstraint")
	w.Part0 = handle
	w.Part1 = part
	w.Parent = part
end

local function baseHandle(tool: Tool, size: Vector3, color: Color3, material: Enum.Material): Part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.Color = color
	handle.Material = material
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.CanCollide = false
	handle.Massless = true
	handle.CastShadow = false
	handle.Parent = tool
	return handle
end

function ToolModels.Epingle(tool: Tool)
	local handle = baseHandle(tool, Vector3.new(0.11, 1.55, 0.11), Color3.fromRGB(175, 182, 195), Enum.Material.Metal)
	handle.Reflectance = 0.25

	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.08, 0.32, 0.08)
	tip.Color = Color3.fromRGB(200, 208, 220)
	tip.Material = Enum.Material.Metal
	local tipMesh = Instance.new("SpecialMesh")
	tipMesh.MeshType = Enum.MeshType.Sphere
	tipMesh.Scale = Vector3.new(0.55, 1.35, 0.55)
	tipMesh.Parent = tip
	weld(handle, tip, CFrame.new(0, -0.88, 0))

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(0.42, 0.42, 0.42)
	head.Color = Color3.fromRGB(255, 55, 75)
	head.Material = Enum.Material.SmoothPlastic
	weld(handle, head, CFrame.new(0, 0.92, 0))

	local collar = Instance.new("Part")
	collar.Name = "Collar"
	collar.Size = Vector3.new(0.2, 0.1, 0.2)
	collar.Color = Color3.fromRGB(150, 155, 165)
	collar.Material = Enum.Material.Metal
	weld(handle, collar, CFrame.new(0, 0.68, 0))

	tool.Grip = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-15), 0, math.rad(25))
end

function ToolModels.Bombe(tool: Tool)
	local handle = baseHandle(tool, Vector3.new(1.15, 1.15, 1.15), Color3.fromRGB(35, 35, 42), Enum.Material.SmoothPlastic)
	handle.Shape = Enum.PartType.Ball

	local band = Instance.new("Part")
	band.Name = "Band"
	band.Size = Vector3.new(1.05, 0.14, 1.05)
	band.Color = Color3.fromRGB(55, 55, 65)
	band.Material = Enum.Material.SmoothPlastic
	weld(handle, band, CFrame.new(0, 0.15, 0))

	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Size = Vector3.new(0.35, 0.22, 0.35)
	cap.Color = Color3.fromRGB(70, 70, 80)
	cap.Material = Enum.Material.Metal
	weld(handle, cap, CFrame.new(0, 0.62, 0))

	local fuse = Instance.new("Part")
	fuse.Name = "Fuse"
	fuse.Size = Vector3.new(0.1, 0.55, 0.1)
	fuse.Color = Color3.fromRGB(90, 70, 45)
	fuse.Material = Enum.Material.SmoothPlastic
	weld(handle, fuse, CFrame.new(0.08, 0.95, 0) * CFrame.Angles(0, 0, math.rad(18)))

	local spark = Instance.new("Part")
	spark.Name = "Spark"
	spark.Shape = Enum.PartType.Ball
	spark.Size = Vector3.new(0.22, 0.22, 0.22)
	spark.Color = Color3.fromRGB(255, 170, 50)
	spark.Material = Enum.Material.Neon
	weld(handle, spark, CFrame.new(0.18, 1.22, 0))

	tool.Grip = CFrame.new(0, -0.2, 0.1) * CFrame.Angles(math.rad(10), 0, 0)
end

function ToolModels.Marteau(tool: Tool)
	local handle = baseHandle(tool, Vector3.new(0.22, 1.7, 0.22), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.1, 0.55, 0.45)
	head.Color = Color3.fromRGB(160, 165, 175)
	head.Material = Enum.Material.Metal
	head.Reflectance = 0.15
	weld(handle, head, CFrame.new(0, 0.95, 0))

	local face = Instance.new("Part")
	face.Name = "Face"
	face.Size = Vector3.new(0.35, 0.5, 0.5)
	face.Color = Color3.fromRGB(190, 195, 205)
	face.Material = Enum.Material.Metal
	weld(handle, face, CFrame.new(0.55, 0.95, 0))

	tool.Grip = CFrame.new(0, -0.4, 0) * CFrame.Angles(0, 0, math.rad(-10))
end

function ToolModels.MegaRouleau(tool: Tool)
	local handle = baseHandle(tool, Vector3.new(0.25, 1.4, 0.25), Color3.fromRGB(70, 70, 80), Enum.Material.Metal)

	local roll = Instance.new("Part")
	roll.Name = "Roller"
	roll.Size = Vector3.new(1.6, 1.6, 1.6)
	roll.Color = Color3.fromRGB(255, 140, 60)
	roll.Material = Enum.Material.SmoothPlastic
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = roll
	-- Cylindre Roblox : axe X → on oriente pour un rouleau horizontal
	weld(handle, roll, CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)))

	local stripe = Instance.new("Part")
	stripe.Name = "Stripe"
	stripe.Size = Vector3.new(1.65, 0.2, 1.65)
	stripe.Color = Color3.fromRGB(255, 200, 80)
	stripe.Material = Enum.Material.Neon
	local sm = Instance.new("SpecialMesh")
	sm.MeshType = Enum.MeshType.Cylinder
	sm.Parent = stripe
	weld(handle, stripe, CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)))

	tool.Grip = CFrame.new(0, -0.3, 0)
end

function ToolModels.Laser(tool: Tool)
	local handle = baseHandle(tool, Vector3.new(0.28, 1.2, 0.28), Color3.fromRGB(50, 50, 60), Enum.Material.SmoothPlastic)

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.35, 0.5, 0.45)
	grip.Color = Color3.fromRGB(40, 40, 48)
	grip.Material = Enum.Material.SmoothPlastic
	weld(handle, grip, CFrame.new(0, -0.55, 0.1))

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.22, 0.9, 0.22)
	barrel.Color = Color3.fromRGB(90, 90, 110)
	barrel.Material = Enum.Material.Metal
	weld(handle, barrel, CFrame.new(0, 0.85, 0))

	local tip = Instance.new("Part")
	tip.Name = "Emitter"
	tip.Shape = Enum.PartType.Ball
	tip.Size = Vector3.new(0.35, 0.35, 0.35)
	tip.Color = Color3.fromRGB(255, 60, 90)
	tip.Material = Enum.Material.Neon
	weld(handle, tip, CFrame.new(0, 1.4, 0))

	local beam = Instance.new("Part")
	beam.Name = "BeamHint"
	beam.Size = Vector3.new(0.12, 0.7, 0.12)
	beam.Color = Color3.fromRGB(255, 80, 120)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.35
	weld(handle, beam, CFrame.new(0, 1.9, 0))

	tool.Grip = CFrame.new(0, 0, 0.1) * CFrame.Angles(math.rad(-90), 0, 0)
end

function ToolModels.Singularite(tool: Tool)
	local handle = baseHandle(tool, Vector3.new(1.0, 1.0, 1.0), Color3.fromRGB(40, 10, 60), Enum.Material.Neon)
	handle.Shape = Enum.PartType.Ball

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(0.55, 0.55, 0.55)
	core.Color = Color3.fromRGB(255, 90, 220)
	core.Material = Enum.Material.Neon
	weld(handle, core, CFrame.new())

	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Size = Vector3.new(1.5, 0.12, 1.5)
	ring.Color = Color3.fromRGB(180, 60, 255)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.25
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = ring
	weld(handle, ring, CFrame.Angles(0, 0, math.rad(90)))

	local ring2 = Instance.new("Part")
	ring2.Name = "Ring2"
	ring2.Size = Vector3.new(1.35, 0.1, 1.35)
	ring2.Color = Color3.fromRGB(120, 40, 200)
	ring2.Material = Enum.Material.Neon
	ring2.Transparency = 0.35
	local mesh2 = Instance.new("SpecialMesh")
	mesh2.MeshType = Enum.MeshType.Cylinder
	mesh2.Parent = ring2
	weld(handle, ring2, CFrame.Angles(math.rad(90), 0, 0))

	tool.Grip = CFrame.new(0, -0.2, 0)
end

-- Ailes collées dans le dos (pas un Tool en main).
function ToolModels.AttachWings(character: Model)
	local existing = character:FindFirstChild("BPW_Wings")
	if existing then existing:Destroy() end

	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
		or character:FindFirstChild("Torso") :: BasePart?
	if not torso then return end

	local folder = Instance.new("Folder")
	folder.Name = "BPW_Wings"
	folder.Parent = character

	local anchor = Instance.new("Part")
	anchor.Name = "WingAnchor"
	anchor.Size = Vector3.new(0.35, 0.35, 0.35)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.CastShadow = false
	anchor.Anchored = false
	anchor.CFrame = torso.CFrame * CFrame.new(0, 0.15, 0.85)
	anchor.Parent = folder

	local weldAnchor = Instance.new("WeldConstraint")
	weldAnchor.Part0 = torso
	weldAnchor.Part1 = anchor
	weldAnchor.Parent = anchor

	local function addWing(name: string, side: number)
		local w = Instance.new("Part")
		w.Name = name
		w.Size = Vector3.new(0.18, 1.35, 2.1)
		w.Color = Color3.fromRGB(140, 220, 255)
		w.Material = Enum.Material.SmoothPlastic
		w.Transparency = 0.12
		w.Reflectance = 0.12
		w.CanCollide = false
		w.CanQuery = false
		w.Massless = true
		w.CastShadow = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(0.3, 1.05, 1.35)
		mesh.Parent = w
		w.CFrame = anchor.CFrame
			* CFrame.new(side * 0.95, 0.15, 0.15)
			* CFrame.Angles(math.rad(-8), side * math.rad(28), side * math.rad(12))
		w.Parent = folder
		local ww = Instance.new("WeldConstraint")
		ww.Part0 = anchor
		ww.Part1 = w
		ww.Parent = w

		local tip = Instance.new("Part")
		tip.Name = name .. "Tip"
		tip.Size = Vector3.new(0.14, 0.55, 0.85)
		tip.Color = Color3.fromRGB(240, 250, 255)
		tip.Material = Enum.Material.SmoothPlastic
		tip.Transparency = 0.3
		tip.CanCollide = false
		tip.Massless = true
		tip.CFrame = anchor.CFrame * CFrame.new(side * 1.55, -0.05, -0.55)
		tip.Parent = folder
		local tw = Instance.new("WeldConstraint")
		tw.Part0 = anchor
		tw.Part1 = tip
		tw.Parent = tip
	end

	addWing("LeftWing", -1)
	addWing("RightWing", 1)

	local gem = Instance.new("Part")
	gem.Name = "Gem"
	gem.Shape = Enum.PartType.Ball
	gem.Size = Vector3.new(0.4, 0.4, 0.4)
	gem.Color = Color3.fromRGB(80, 200, 255)
	gem.Material = Enum.Material.Neon
	gem.CanCollide = false
	gem.Massless = true
	gem.CFrame = anchor.CFrame * CFrame.new(0, 0.15, 0.05)
	gem.Parent = folder
	local gw = Instance.new("WeldConstraint")
	gw.Part0 = anchor
	gw.Part1 = gem
	gw.Parent = gem
end

function ToolModels.DetachWings(character: Model)
	local existing = character:FindFirstChild("BPW_Wings")
	if existing then existing:Destroy() end
end

-- Petite icône hotbar pour activer/désactiver les ailes (pas le modèle dos)
function ToolModels.Ailes(tool: Tool)
	local handle = baseHandle(tool, Vector3.new(0.55, 0.55, 0.55), Color3.fromRGB(80, 200, 255), Enum.Material.Neon)
	handle.Shape = Enum.PartType.Ball

	local left = Instance.new("Part")
	left.Name = "IconL"
	left.Size = Vector3.new(0.12, 0.45, 0.7)
	left.Color = Color3.fromRGB(140, 220, 255)
	left.Material = Enum.Material.SmoothPlastic
	left.Transparency = 0.15
	weld(handle, left, CFrame.new(-0.45, 0, 0) * CFrame.Angles(0, 0, math.rad(20)))

	local right = Instance.new("Part")
	right.Name = "IconR"
	right.Size = Vector3.new(0.12, 0.45, 0.7)
	right.Color = Color3.fromRGB(140, 220, 255)
	right.Material = Enum.Material.SmoothPlastic
	right.Transparency = 0.15
	weld(handle, right, CFrame.new(0.45, 0, 0) * CFrame.Angles(0, 0, math.rad(-20)))

	tool.Grip = CFrame.new(0, -0.1, 0)
end

local BUILDERS: { [string]: (Tool) -> () } = {
	Epingle = ToolModels.Epingle,
	Bombe = ToolModels.Bombe,
	Marteau = ToolModels.Marteau,
	MegaRouleau = ToolModels.MegaRouleau,
	Laser = ToolModels.Laser,
	Singularite = ToolModels.Singularite,
	Ailes = ToolModels.Ailes,
}

function ToolModels.Apply(tool: Tool, id: string, def: any)
	local builder = BUILDERS[id]
	if builder then
		builder(tool)
		return
	end
	-- Fallback
	local handle = baseHandle(tool, Vector3.new(0.6, 2.4, 0.6), def.Color, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = 8
	light.Brightness = 2
	light.Parent = handle
end

return ToolModels
