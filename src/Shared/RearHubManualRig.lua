--!strict
-- Collision rig manuel persistant du plateau Tripo.
-- Créé en mode édition (plugin), ajusté à la main, jamais recalculé au runtime.

local Workspace = game:GetService("Workspace")

local RearHubManualRig = {}

RearHubManualRig.CODE_VERSION = "MANUAL-RIG-V1"
RearHubManualRig.RIG_VERSION = "MANUAL_RIG_V1"
RearHubManualRig.RIG_NAME = "ManualCollisionRig"
RearHubManualRig.PLATFORM_NAME = "TripoRearHubPlatform"

local LOG = "[RearHubManualCollision] "
local EDIT_TRANSPARENCY = 0.35
local RUNTIME_TRANSPARENCY = 1

export type Kind = "Walkable" | "Ramp" | "Blocker"

export type PartSpec = {
	Name: string,
	Kind: Kind,
}

RearHubManualRig.SPECS = {
	{ Name = "UpperDeckFloor", Kind = "Walkable" :: Kind },
	{ Name = "LowerDeckFloor", Kind = "Walkable" :: Kind },
	{ Name = "FrontStairRamp", Kind = "Ramp" :: Kind },
	{ Name = "LeftDeckFloor", Kind = "Walkable" :: Kind },
	{ Name = "RightDeckFloor", Kind = "Walkable" :: Kind },
	{ Name = "LeftFoundationBlocker", Kind = "Blocker" :: Kind },
	{ Name = "RightFoundationBlocker", Kind = "Blocker" :: Kind },
	{ Name = "FrontFoundationBlockerLeft", Kind = "Blocker" :: Kind },
	{ Name = "FrontFoundationBlockerRight", Kind = "Blocker" :: Kind },
}

RearHubManualRig.REQUIRED_CORE = { "UpperDeckFloor", "LowerDeckFloor", "FrontStairRamp" }

-- Anciens systèmes automatiques à supprimer définitivement.
RearHubManualRig.LEGACY_FOLDERS = { "RearHubCollisions" }
RearHubManualRig.LEGACY_PARTS = {
	"FrontStairSafetyRamp",
	"UpperSpawnWalkSurface",
	"UpperDeckWalkSurface",
	"MainDeckWalkSurface",
	"MainFloorCollision",
	"FrontStairWalkSurface",
	"FrontAccessRamp",
	"LeftAccessRamp",
	"RightAccessRamp",
	"LeftDeckWalkSurface",
	"RightDeckWalkSurface",
	"PortalWalkSurface",
	"LeftFacadeBlocker",
	"RightFacadeBlocker",
	"FrontFacadeBlockerL",
	"FrontFacadeBlockerR",
	"FrontFoundationBlocker_Left",
	"FrontFoundationBlocker_Right",
}

local function log(msg: string)
	print(LOG .. msg)
end

function RearHubManualRig.ColorForKind(kind: Kind): Color3
	if kind == "Ramp" then
		return Color3.fromRGB(255, 214, 0) -- jaune
	elseif kind == "Blocker" then
		return Color3.fromRGB(220, 45, 45) -- rouge
	end
	return Color3.fromRGB(45, 210, 90) -- vert
end

function RearHubManualRig.KindForName(name: string): Kind?
	for _, spec in ipairs(RearHubManualRig.SPECS) do
		if spec.Name == name then
			return spec.Kind
		end
	end
	return nil
end

function RearHubManualRig.EditTransparency(): number
	return EDIT_TRANSPARENCY
end

function RearHubManualRig.RuntimeTransparency(): number
	return RUNTIME_TRANSPARENCY
end

--- Un collider marqué manuellement ne doit plus être ni déplacé ni redimensionné.
function RearHubManualRig.ShouldPreserveManualPart(manualPlacement: boolean?): boolean
	return manualPlacement == true
end

function RearHubManualRig.IsLegacyPartName(name: string): boolean
	for _, n in ipairs(RearHubManualRig.LEGACY_PARTS) do
		if name == n then
			return true
		end
	end
	return false
end

function RearHubManualRig.IsLegacyFolderName(name: string): boolean
	for _, n in ipairs(RearHubManualRig.LEGACY_FOLDERS) do
		if name == n then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------
-- Hiérarchie
--------------------------------------------------------------------

function RearHubManualRig.GetHubRoot(): Folder?
	local world = Workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild("CentralHub")
	if hub and hub:IsA("Folder") then
		return hub
	end
	return nil
end

function RearHubManualRig.GetRearFolder(): Folder?
	local hub = RearHubManualRig.GetHubRoot()
	local modules = hub and hub:FindFirstChild("Modules")
	local rear = modules and modules:FindFirstChild("RearHub")
	if rear and rear:IsA("Folder") then
		return rear
	end
	return nil
end

function RearHubManualRig.FindPlatform(): Model?
	local rear = RearHubManualRig.GetRearFolder()
	local m = rear and rear:FindFirstChild(RearHubManualRig.PLATFORM_NAME)
	if m and m:IsA("Model") then
		return m
	end
	local hub = RearHubManualRig.GetHubRoot()
	if hub then
		for _, d in ipairs(hub:GetDescendants()) do
			if d:IsA("Model") and d.Name == RearHubManualRig.PLATFORM_NAME then
				return d
			end
		end
	end
	return nil
end

function RearHubManualRig.FindRig(): Folder?
	local rear = RearHubManualRig.GetRearFolder()
	local rig = rear and rear:FindFirstChild(RearHubManualRig.RIG_NAME)
	if rig and rig:IsA("Folder") then
		return rig
	end
	return nil
end

--- Mesh Tripo : visuel uniquement. CastShadow=false (grands panneaux mesh
--- projetaient une ombre noire sur le palier). Aucune modif CollisionFidelity / CFrame.
function RearHubManualRig.MakeMeshVisualOnly(platform: Model): number
	local n = 0
	for _, d in ipairs(platform:GetDescendants()) do
		if d:IsA("BasePart") then
			local p = d :: BasePart
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = true
			p.CastShadow = false
			n += 1
		end
	end
	return n
end

--- Fill lights local RearHub (portée limitée). N'altère jamais Lighting global.
function RearHubManualRig.EnsureLocalFillLights(): boolean
	local rear = RearHubManualRig.GetRearFolder()
	if not rear then
		return false
	end
	local platform = RearHubManualRig.FindPlatform()
	if not platform then
		return false
	end
	local folder = rear:FindFirstChild("RearHubLighting")
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "RearHubLighting"
		f.Parent = rear
		folder = f
	end
	local root = folder :: Folder
	local pivot = platform:GetPivot()
	local specs = {
		{ Name = "UpperDeckFillLight", Offset = Vector3.new(0, 6.5, 2), Brightness = 0.55, Range = 28 },
		{ Name = "LowerDeckFillLight", Offset = Vector3.new(0, 2.2, 4), Brightness = 0.4, Range = 22 },
	}
	for _, s in ipairs(specs) do
		local host = root:FindFirstChild(s.Name)
		if host and not host:IsA("BasePart") then
			host:Destroy()
			host = nil
		end
		if not host then
			local p = Instance.new("Part")
			p.Name = s.Name
			p.Size = Vector3.new(0.2, 0.2, 0.2)
			p.Transparency = 1
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
			p.Massless = true
			p.Parent = root
			host = p
		end
		local part = host :: BasePart
		-- Positions relatives au mesh — pas de rejeu chaque frame, mais OK au ensure
		part.CFrame = pivot * CFrame.new(s.Offset)
		part.CastShadow = false
		local light = part:FindFirstChildOfClass("PointLight")
		if not light then
			light = Instance.new("PointLight")
			light.Parent = part
		end
		light.Brightness = s.Brightness
		light.Range = s.Range
		light.Color = Color3.fromRGB(210, 230, 255)
		light.Shadows = false
		light.Enabled = true
	end
	log("RearHubLighting fill lights ensured (local only)")
	return true
end

function RearHubManualRig.CountCollidableMeshes(platform: Model?): number
	if not platform then
		return 0
	end
	local n = 0
	for _, d in ipairs(platform:GetDescendants()) do
		if d:IsA("BasePart") and (d :: BasePart).CanCollide then
			n += 1
		end
	end
	return n
end

--- Purge des anciens systèmes automatiques.
function RearHubManualRig.DestroyLegacy(): number
	local hub = RearHubManualRig.GetHubRoot()
	if not hub then
		return 0
	end
	local destroyed = 0
	for _, d in ipairs(hub:GetDescendants()) do
		if d:IsA("Folder") and RearHubManualRig.IsLegacyFolderName(d.Name) then
			d:Destroy()
			destroyed += 1
		end
	end
	for _, d in ipairs(hub:GetDescendants()) do
		if d:IsA("BasePart") and not d:IsA("MeshPart") and RearHubManualRig.IsLegacyPartName(d.Name) then
			d:Destroy()
			destroyed += 1
		end
	end
	if destroyed > 0 then
		log(string.format("legacy automatic collisions destroyed: %d", destroyed))
	end
	return destroyed
end

--------------------------------------------------------------------
-- Création (mode édition, seulement les pièces manquantes)
--------------------------------------------------------------------

local function applyLook(part: BasePart, kind: Kind, editVisible: boolean)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.CollisionGroup = "Default"
	part.Material = Enum.Material.ForceField
	part.Color = RearHubManualRig.ColorForKind(kind)
	part.Transparency = if editVisible then EDIT_TRANSPARENCY else RUNTIME_TRANSPARENCY
end

RearHubManualRig.ApplyLook = applyLook

type Guess = { Size: Vector3, CFrame: CFrame }

--- Placements initiaux grossiers : à ajuster à la main dans Studio.
function RearHubManualRig.BuildGuesses(platform: Model, spawn: BasePart?): { [string]: Guess }
	local ok, cf, sz = pcall(function()
		return platform:GetBoundingBox()
	end)
	local center = Vector3.new(0, 12, 0)
	local size = Vector3.new(40, 12, 40)
	if ok and typeof(cf) == "CFrame" and typeof(sz) == "Vector3" then
		center = (cf :: CFrame).Position
		size = sz :: Vector3
	end

	local frontZ = center.Z - size.Z / 2
	local rearZ = center.Z + size.Z / 2
	local upperY = if spawn then spawn.Position.Y - spawn.Size.Y / 2 else center.Y + size.Y * 0.2
	local lowerY = upperY - math.max(3, size.Y * 0.22)
	local upperX = if spawn then spawn.Position.X else center.X
	local upperZ = if spawn then spawn.Position.Z else (frontZ + (rearZ - frontZ) * 0.75)
	local thick = 1

	local upperDia = math.clamp(math.min(size.X, size.Z) * 0.45, 10, 30)
	local stairFrontZ = frontZ + (rearZ - frontZ) * 0.25
	local stairRearZ = upperZ - upperDia / 2
	if stairRearZ <= stairFrontZ then
		stairRearZ = stairFrontZ + math.max(4, (rearZ - frontZ) * 0.2)
	end
	local rise = math.max(1, upperY - lowerY)
	local run = math.max(4, stairRearZ - stairFrontZ)
	local angle = math.atan2(rise, run)
	local slope = math.sqrt(rise * rise + run * run)
	local stairWidth = math.clamp(size.X * 0.28, 8, 16)

	local lowerDepth = math.max(8, stairFrontZ - frontZ + 4)
	local sideWidth = math.clamp(size.X * 0.16, 4, 10)
	local sideDepth = math.max(8, (rearZ - frontZ) * 0.35)
	local wallH = math.max(4, rise + 3)
	local wallT = 1.2
	local wallMidY = lowerY - wallH / 2 + 0.5
	local openHalf = stairWidth / 2 + 2
	local frontSegW = math.max(4, size.X * 0.35 - openHalf)

	local guesses: { [string]: Guess } = {}

	guesses.UpperDeckFloor = {
		Size = Vector3.new(upperDia, thick, upperDia),
		CFrame = CFrame.new(upperX, upperY - thick / 2, upperZ),
	}
	guesses.LowerDeckFloor = {
		Size = Vector3.new(size.X * 0.7, thick, lowerDepth),
		CFrame = CFrame.new(center.X, lowerY - thick / 2, (frontZ + stairFrontZ) / 2 + 1),
	}
	guesses.FrontStairRamp = {
		Size = Vector3.new(stairWidth, 0.8, slope),
		CFrame = CFrame.new(center.X, (lowerY + upperY) / 2 - 0.4, (stairFrontZ + stairRearZ) / 2)
			* CFrame.Angles(-angle, 0, 0),
	}
	guesses.LeftDeckFloor = {
		Size = Vector3.new(sideWidth, thick, sideDepth),
		CFrame = CFrame.new(center.X - size.X * 0.28, lowerY - thick / 2, center.Z),
	}
	guesses.RightDeckFloor = {
		Size = Vector3.new(sideWidth, thick, sideDepth),
		CFrame = CFrame.new(center.X + size.X * 0.28, lowerY - thick / 2, center.Z),
	}
	guesses.LeftFoundationBlocker = {
		Size = Vector3.new(wallT, wallH, (rearZ - frontZ) * 0.6),
		CFrame = CFrame.new(center.X - size.X * 0.45, wallMidY, center.Z),
	}
	guesses.RightFoundationBlocker = {
		Size = Vector3.new(wallT, wallH, (rearZ - frontZ) * 0.6),
		CFrame = CFrame.new(center.X + size.X * 0.45, wallMidY, center.Z),
	}
	guesses.FrontFoundationBlockerLeft = {
		Size = Vector3.new(frontSegW, wallH, wallT),
		CFrame = CFrame.new(center.X - (openHalf + frontSegW / 2), wallMidY, frontZ + wallT),
	}
	guesses.FrontFoundationBlockerRight = {
		Size = Vector3.new(frontSegW, wallH, wallT),
		CFrame = CFrame.new(center.X + (openHalf + frontSegW / 2), wallMidY, frontZ + wallT),
	}
	return guesses
end

export type EnsureResult = {
	Rig: Folder,
	Created: { string },
	Preserved: { string },
}

--- Crée le rig et UNIQUEMENT les collisions manquantes. Ne touche jamais un
--- collider portant BPW_ManualPlacement (CFrame / Size préservés).
function RearHubManualRig.EnsureRig(editVisible: boolean): EnsureResult?
	local rear = RearHubManualRig.GetRearFolder()
	if not rear then
		warn(LOG .. "RearHub introuvable — lancer d'abord Install / Refresh")
		return nil
	end
	local platform = RearHubManualRig.FindPlatform()
	if not platform then
		warn(LOG .. "TripoRearHubPlatform introuvable")
		return nil
	end

	RearHubManualRig.DestroyLegacy()
	RearHubManualRig.MakeMeshVisualOnly(platform)

	local rig = rear:FindFirstChild(RearHubManualRig.RIG_NAME)
	if rig and not rig:IsA("Folder") then
		rig:Destroy()
		rig = nil
	end
	if not rig then
		local f = Instance.new("Folder")
		f.Name = RearHubManualRig.RIG_NAME
		f.Parent = rear
		rig = f
	end
	local folder = rig :: Folder
	folder:SetAttribute("BPW_ManualCollisionRig", true)
	folder:SetAttribute("BPW_CollisionVersion", RearHubManualRig.RIG_VERSION)

	local hub = RearHubManualRig.GetHubRoot()
	local spawnInst = hub and hub:FindFirstChild("HubSpawnLocation")
	local spawn = if spawnInst and spawnInst:IsA("BasePart") then spawnInst :: BasePart else nil
	local guesses = RearHubManualRig.BuildGuesses(platform, spawn)

	local created: { string } = {}
	local preserved: { string } = {}

	for _, spec in ipairs(RearHubManualRig.SPECS) do
		local existing = folder:FindFirstChild(spec.Name)
		if existing and not existing:IsA("BasePart") then
			existing:Destroy()
			existing = nil
		end
		if existing and existing:IsA("BasePart") then
			local part = existing :: BasePart
			if RearHubManualRig.ShouldPreserveManualPart(part:GetAttribute("BPW_ManualPlacement") == true) then
				-- Apparence seulement : CFrame et Size intacts
				local cf, size = part.CFrame, part.Size
				applyLook(part, spec.Kind, editVisible)
				part.CFrame = cf
				part.Size = size
				table.insert(preserved, spec.Name)
				log("preserved manual collider: " .. spec.Name)
			else
				applyLook(part, spec.Kind, editVisible)
				part:SetAttribute("BPW_ManualPlacement", true)
				table.insert(preserved, spec.Name)
			end
		else
			local g = guesses[spec.Name]
			local part = Instance.new("Part")
			part.Name = spec.Name
			part.Size = if g then g.Size else Vector3.new(10, 1, 10)
			part.CFrame = if g then g.CFrame else CFrame.new(0, 20, 0)
			applyLook(part, spec.Kind, editVisible)
			part:SetAttribute("BPW_ManualPlacement", true)
			part:SetAttribute("BPW_CollisionKind", spec.Kind)
			part.Parent = folder
			table.insert(created, spec.Name)
			log("created collider (adjust manually in Studio): " .. spec.Name)
		end
	end

	log(string.format("rig ready: %s", folder:GetFullName()))
	log(string.format("created: %d, preserved: %d", #created, #preserved))
	return { Rig = folder, Created = created, Preserved = preserved }
end

--- Bouton Show / Hide (mode édition uniquement) : n'affecte que Transparency.
function RearHubManualRig.SetCollidersVisible(visible: boolean): number
	local rig = RearHubManualRig.FindRig()
	if not rig then
		warn(LOG .. "ManualCollisionRig absent — lancer Install / Refresh Tripo Rear Hub")
		return 0
	end
	local n = 0
	for _, d in ipairs(rig:GetChildren()) do
		if d:IsA("BasePart") then
			(d :: BasePart).Transparency = if visible then EDIT_TRANSPARENCY else RUNTIME_TRANSPARENCY
			n += 1
		end
	end
	log(string.format("colliders %s (%d)", if visible then "shown" else "hidden", n))
	return n
end

--------------------------------------------------------------------
-- Runtime : validation seule (aucun repositionnement)
--------------------------------------------------------------------

local runtimeRepositionCount = 0

function RearHubManualRig.GetRuntimeRepositionCount(): number
	return runtimeRepositionCount
end

function RearHubManualRig.ValidateRuntime(): boolean
	log("CODE VERSION " .. RearHubManualRig.CODE_VERSION)
	local platform = RearHubManualRig.FindPlatform()
	local rig = RearHubManualRig.FindRig()

	-- Mesh strictement visuel + pas d'ombre monolithe sur le palier
	if platform then
		RearHubManualRig.MakeMeshVisualOnly(platform)
		log("TripoRearHubPlatform CastShadow=false on all mesh parts")
	end
	RearHubManualRig.DestroyLegacy()
	-- Soft fill local si le mesh reste sombre (ne touche pas Lighting global)
	RearHubManualRig.EnsureLocalFillLights()

	log(string.format("rig found: %s", tostring(rig ~= nil)))
	local colliders = 0
	if rig then
		for _, spec in ipairs(RearHubManualRig.SPECS) do
			local p = rig:FindFirstChild(spec.Name)
			local found = p ~= nil and p:IsA("BasePart")
			if table.find(RearHubManualRig.REQUIRED_CORE, spec.Name) then
				log(string.format("%s found: %s", spec.Name, tostring(found)))
			end
				if found then
				local part = p :: BasePart
				-- Invisible au runtime, CFrame / Size jamais touchés
				part.Transparency = RUNTIME_TRANSPARENCY
				if not part.CanCollide then
					part.CanCollide = true
				end
				part.CanTouch = false
				part.CanQuery = true
				part.Anchored = true
				part.CastShadow = false
				colliders += 1
			end
		end
	end

	local collidableMeshes = RearHubManualRig.CountCollidableMeshes(platform)
	log(string.format("Tripo collidable mesh count: %d", collidableMeshes))
	log(string.format("manual colliders: %d", colliders))
	log(string.format("runtime reposition count: %d", runtimeRepositionCount))

	local coreOk = rig ~= nil
	if rig then
		for _, name in ipairs(RearHubManualRig.REQUIRED_CORE) do
			local p = rig:FindFirstChild(name)
			if not (p and p:IsA("BasePart") and (p :: BasePart).CanCollide) then
				coreOk = false
			end
		end
	end

	local pass = coreOk and collidableMeshes == 0 and runtimeRepositionCount == 0
	if pass then
		log("PASS")
	else
		log("FAIL")
		warn(LOG .. "FAIL — cliquer Install / Refresh Tripo Rear Hub puis ajuster le rig dans Studio")
	end
	return pass
end

return RearHubManualRig
