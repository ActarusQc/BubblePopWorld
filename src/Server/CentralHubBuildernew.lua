--!strict
-- Hub central « Concept 2 — Équilibré » : plateforme octogonale posée au milieu de la
-- planche de bulles. Regroupe spawn, boucle POP → SELL → UPGRADE, vente, boutique,
-- TOP 3, règles et pastille Bubble Transit, avec une descente frontale vers les bulles.
--
-- Ce module ne fait QUE de la construction visuelle + repères fonctionnels :
--   * la géométrie vient de Shared/HubLayout (module pur, testé) ;
--   * la vente reste la vente automatique de ZoneService (présence dans SellZone) ;
--   * la boutique reste ItemShopBuilder ; le classement reste LeaderboardService ;
--   * le transit reste BubbleTransitBuilder.
--
-- Visuel hub autoritatif : Workspace.HubDeckShell_New (FullHubComposite).
-- En mode FullHub : aucun prototype blanc/cyan ; props collision seules sur le mesh.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local HubLayout = require(Shared.HubLayout)
local HubAssetContract = require(Shared.HubAssetContract)
local HubShopPromptLogic = require(Shared.HubShopPromptLogic)
local L10n = require(Shared.LocalizationStrings)
local L10nUtil = require(Shared.LocalizationUtil)

local CentralHubBuilder = {}

local H = Config.Hub
local C = H.Colors

local ROOT_NAME = "CentralHub"
local STRUCTURE = "HubStructure"
local FUNCTION = "HubFunction"
local ANCHORS = "HubAnchors"
local COMPOSITE_PROXIES = "CompositeCollisionProxies"
local HUB_COLLISION_PROXIES = "HubCollisionProxies"
local HUB_LIGHTING_RIG = "HubLightingRig"
local LEGACY_PROXY_FOLDERS = {
	"CompositeCollisionProxies",
	"FullHubCollisionProxies",
	"HubCollisionProxies",
	"FinalHubCollisionProxies",
}

-- Pièces Sell/Shop : visuels non collisionnables ; seul le dosseret reste solide.
local STAND_VISUAL_NO_COLLIDE = {
	"HubSellCounter",
	"HubSellCounterTop",
	"HubSellCanopy",
	"HubSellCanopyEdge",
	"HubSellSign",
	"HubSellPostL",
	"HubSellPostR",
	"HubSellPad",
	"HubSellValueBoard",
	"HubShopCanopy",
	"HubShopCanopyEdge",
	"HubShopCounterL",
	"HubShopCounterR",
	"HubShopCounterTopL",
	"HubShopCounterTopR",
	"HubShopSideWallL",
	"HubShopSideWallR",
	"HubShopSign",
	"HubShopShelf1",
	"HubShopShelf2",
}

-- Anciennes collisions prototype à désactiver dès que le Composite est actif.
local PROTOTYPE_COLLIDER_NAMES = {
	"HubFoundation",
	"HubFoundationGlow",
	"DeckMiddle",
	"DeckFront",
	"DeckBack",
	"DeckFrontLeft",
	"DeckFrontRight",
	"DeckBackLeft",
	"DeckBackRight",
	"PlinthMiddle",
	"PlinthFront",
	"PlinthBack",
	"PlinthFrontLeft",
	"PlinthFrontRight",
	"PlinthBackLeft",
	"PlinthBackRight",
	"DeckInlay",
	"HubSellPlatform",
	"HubShopPlatform",
	"HubSellPlatformCollider",
	"HubShopPlatformCollider",
	"RailFrontLeft",
	"RailFrontRight",
	"RailBack",
	"RailWest",
	"RailEast",
	"RailFrontLeftCollider",
	"RailFrontRightCollider",
	"RailBackCollider",
	"RailWestCollider",
	"RailEastCollider",
	"RailFrontLeftCap",
	"RailFrontRightCap",
	"RailBackCap",
	"RailWestCap",
	"RailEastCap",
}

--------------------------------------------------------------------
-- Références exposées à ZoneService / LeaderboardService
--------------------------------------------------------------------
local spawnMarker: BasePart? = nil
local spawnLocation: SpawnLocation? = nil
local sellZone: BasePart? = nil
local topBoard: BasePart? = nil
local sellValueBoard: BasePart? = nil

--------------------------------------------------------------------
-- Aides
--------------------------------------------------------------------
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
	folder:SetAttribute("GeneratedByCode", true)
	folder.Parent = parent
	return folder
end

type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	Shape: Enum.PartType?,
	Parent: Instance?,
}

local function makePart(props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or C.Deck
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.Reflectance = props.Reflectance or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	p:SetAttribute("GeneratedByCode", true)
	p.Parent = props.Parent
	return p
end

-- Cylindre Roblox : axe le long de X. `diameter` sur XZ monde, `height` sur Y.
local function makeDisc(props: {
	Name: string,
	Diameter: number,
	Height: number,
	Center: Vector3,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	Parent: Instance?,
}): Part
	return makePart({
		Name = props.Name,
		Size = Vector3.new(props.Height, props.Diameter, props.Diameter),
		CFrame = CFrame.new(props.Center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = props.Color,
		Material = props.Material,
		Transparency = props.Transparency,
		CanCollide = props.CanCollide,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
		Parent = props.Parent,
	})
end

local function makeWedge(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Parent: Instance?,
}): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = props.Name
	w.Anchored = true
	w.Size = props.Size
	w.CFrame = props.CFrame
	w.Color = props.Color or C.Deck
	w.Material = props.Material or Enum.Material.SmoothPlastic
	w.CanCollide = true
	w.CanTouch = false
	w.CastShadow = false
	w:SetAttribute("GeneratedByCode", true)
	w.Parent = props.Parent
	return w
end

local function localCF(base: CFrame, offset: Vector3, extraYaw: number?): CFrame
	local cf = base * CFrame.new(offset)
	if extraYaw then
		cf = cf * CFrame.Angles(0, math.rad(extraYaw), 0)
	end
	return cf
end

--------------------------------------------------------------------
-- Surfaces GUI
--------------------------------------------------------------------
local function newSurface(part: BasePart, face: Enum.NormalId, pixelsPerStud: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "HubGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 24
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ZOffset = 0.05
	gui.Parent = part
	return gui
end

local function newFrame(parent: Instance, size: UDim2, position: UDim2, color: Color3, corner: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, corner)
		c.Parent = f
	end
	return f
end

local function newLabel(parent: Instance, props: {
	Text: string,
	Size: UDim2,
	Position: UDim2,
	Color: Color3?,
	Font: Enum.Font?,
	Align: Enum.TextXAlignment?,
	Stroke: Color3?,
	Dynamic: boolean?,
}): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = props.Size
	l.Position = props.Position
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.TextColor3 = props.Color or C.White
	l.Font = props.Font or Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextXAlignment = props.Align or Enum.TextXAlignment.Center
	l.Parent = parent
	if props.Stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = props.Stroke
		stroke.Parent = l
	end
	if props.Dynamic then
		L10nUtil.dynamic(l, props.Text)
	else
		L10nUtil.localize(l, props.Text)
	end
	return l
end

-- Fond sombre commun à tous les panneaux (lisibilité à distance).
local function panelBackdrop(gui: SurfaceGui, accent: Color3): Frame
	local bg = newFrame(gui, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), C.PanelDeep, 18)
	local inner = newFrame(bg, UDim2.fromScale(0.96, 0.94), UDim2.fromScale(0.5, 0.5), C.Panel, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = accent
	stroke.Transparency = 0.15
	stroke.Parent = inner
	return inner
end

--------------------------------------------------------------------
-- Pipeline assets importés / FullHubComposite
--------------------------------------------------------------------
local FULL_HUB_MODEL_NAME = "HubDeckShell_New"
local FULL_HUB_VARIANT = "FullHubComposite"

local deckImportActive = false
local deckIsComposite = false
local fullHubActive = false
local fullHubSource: Model? = nil

local function importedVisualFolder(): Instance?
	local decor = workspace:FindFirstChild(H.Visual.StudioDecorationRoot)
	if not decor then
		return nil
	end
	return decor:FindFirstChild(H.Visual.VisualFolder)
end

local function fullPath(inst: Instance): string
	local parts = { inst.Name }
	local parent = inst.Parent
	while parent and parent ~= game do
		table.insert(parts, 1, parent.Name)
		parent = parent.Parent
	end
	return table.concat(parts, ".")
end

local function importedModel(assetKey: string): Instance?
	-- Deck : Workspace.HubDeckShell_New, sinon StudioDecoration.CentralHubVisual.
	if assetKey == "Deck" then
		for _, name in ipairs({ "HubDeckShell_New", "HubDeckShell" }) do
			local root = workspace:FindFirstChild(name)
			if root and root:IsA("Model") then
				return root
			end
		end
		local folder = importedVisualFolder()
		if folder then
			for _, name in ipairs({ "HubDeckShell_New", "HubDeckShell" }) do
				local nested = folder:FindFirstChild(name)
				if nested and nested:IsA("Model") then
					return nested
				end
			end
		end
		return nil
	end
	local modelName = HubLayout.GetAssetModelName(assetKey)
	if not modelName then
		return nil
	end
	local folder = importedVisualFolder()
	if not folder then
		return nil
	end
	return folder:FindFirstChild(modelName)
end

local function findPrimaryMeshPart(model: Model): MeshPart?
	local direct: MeshPart? = nil
	local any: MeshPart? = nil
	local count = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("MeshPart") then
			count += 1
			local mesh = descendant :: MeshPart
			if any == nil then
				any = mesh
			end
			if mesh.Parent == model then
				direct = mesh
			end
		end
	end
	if count == 0 then
		return nil
	end
	return direct or any
end

local function meshHasAppearance(mesh: MeshPart): boolean
	for _, child in ipairs(mesh:GetChildren()) do
		if child:IsA("SurfaceAppearance") then
			return true
		end
	end
	local ok, textureId = pcall(function()
		return (mesh :: any).TextureID
	end)
	return ok and type(textureId) == "string" and textureId ~= ""
end

local function logFinalFix(...: any)
	local parts = { "[HubFinalFix]" }
	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end
	print(table.concat(parts, " "))
end

local function logSurfaceFix(...: any)
	local parts = { "[HubSurfaceFix]" }
	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end
	print(table.concat(parts, " "))
end

local function resolveFullHubSource(): (Model?, string?)
	local candidates: { Instance? } = {
		workspace:FindFirstChild("HubDeckShell_New"),
		workspace:FindFirstChild("HubDeckShell"),
	}
	local decor = workspace:FindFirstChild(H.Visual.StudioDecorationRoot)
	local visualFolder = if decor then decor:FindFirstChild(H.Visual.VisualFolder) else nil
	if visualFolder then
		table.insert(candidates, visualFolder:FindFirstChild("HubDeckShell_New"))
		table.insert(candidates, visualFolder:FindFirstChild("HubDeckShell"))
	end

	local inst: Instance? = nil
	for _, candidate in ipairs(candidates) do
		if candidate then
			inst = candidate
			break
		end
	end
	if not inst then
		return nil, "HubDeckShell_New/HubDeckShell introuvable (Workspace ou StudioDecoration.CentralHubVisual)"
	end
	if not inst:IsA("Model") then
		return nil, "source hub n'est pas un Model"
	end
	local model = inst :: Model
	logSurfaceFix("Active visual:", fullPath(model))
	local mesh = findPrimaryMeshPart(model)
	if not mesh then
		return nil, "aucun MeshPart dans le hub 3D"
	end
	if not meshHasAppearance(mesh) then
		return nil, "MeshPart sans texture ni SurfaceAppearance"
	end
	if mesh.Size.Magnitude < 1e-3 then
		return nil, "MeshPart Size invalide"
	end
	return model, nil
end

local function prepareFullHubSource(model: Model)
	-- Props runtime uniquement — jamais CFrame / Size / Orientation / textures.
	local primary = findPrimaryMeshPart(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			part.Anchored = true
			part.CanTouch = false
			part.CastShadow = false
			if descendant:IsA("MeshPart") then
				-- Collision réelle du mesh Tripo (murs, comptoirs, portail, escaliers).
				part.CanCollide = true
				part.CanQuery = true
				local okFidelity = pcall(function()
					(part :: MeshPart).CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
				end)
				if part == primary then
					print("[HubMeshCollision] Active MeshPart:", fullPath(part))
					print(
						"[HubMeshCollision] CollisionFidelity:",
						if okFidelity then "PreciseConvexDecomposition" else "(unsupported)"
					)
				end
			else
				part.CanCollide = false
				part.CanQuery = true
			end
		end
	end
end

local function snapshotFullHubMesh(model: Model): (CFrame?, Vector3?, Instance?)
	local mesh = findPrimaryMeshPart(model)
	if not mesh then
		return nil, nil, model.Parent
	end
	return mesh.CFrame, mesh.Size, model.Parent
end

local function fullHubTransformModified(
	model: Model,
	beforeCF: CFrame?,
	beforeSize: Vector3?,
	beforeParent: Instance?
): boolean
	local afterCF, afterSize, afterParent = snapshotFullHubMesh(model)
	if afterParent ~= beforeParent then
		return true
	end
	if beforeCF == nil or afterCF == nil or beforeSize == nil or afterSize == nil then
		return true
	end
	if (afterSize - beforeSize).Magnitude > 1e-6 then
		return true
	end
	if (afterCF.Position - beforeCF.Position).Magnitude > 1e-6 then
		return true
	end
	if math.abs(afterCF.LookVector:Dot(beforeCF.LookVector) - 1) > 1e-6 then
		return true
	end
	if math.abs(afterCF.UpVector:Dot(beforeCF.UpVector) - 1) > 1e-6 then
		return true
	end
	return false
end

local function logFullHub(...: any)
	local parts = { "[FullHubComposite]" }
	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end
	print(table.concat(parts, " "))
end

local function logCompositeDebug(...: any)
	local parts = { "[HubCompositeDebug]" }
	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end
	print(table.concat(parts, " "))
end

local function describeCFrame(cf: CFrame): string
	local p = cf.Position
	local look = cf.LookVector
	local up = cf.UpVector
	return ("pos=(%.2f, %.2f, %.2f) look=(%.3f, %.3f, %.3f) up=(%.3f, %.3f, %.3f)"):format(
		p.X, p.Y, p.Z, look.X, look.Y, look.Z, up.X, up.Y, up.Z
	)
end

local function auditCompositeDecision(decision: any, folder: Instance?, useImported: boolean)
	local modelName = HubLayout.GetAssetModelName("Deck") or "HubDeckShell"
	local model = if folder then folder:FindFirstChild(modelName) else nil
	local path = if model then fullPath(model) else "(absent)"
	logCompositeDebug("1) source Studio :", if model then "PRÉSENTE" else "ABSENTE")
	logCompositeDebug("2) chemin :", path)
	logCompositeDebug("5) UseImported :", tostring(useImported))

	if model then
		local A = HubAssetContract.Attributes
		logCompositeDebug("6) BPW_HubAssetVariant :", tostring(model:GetAttribute(A.Variant)))
		logCompositeDebug("   BPW_AuthoredYaw :", tostring(model:GetAttribute(A.AuthoredYaw)))
		logCompositeDebug("   BPW_AuthoredSize :", tostring(model:GetAttribute(A.AuthoredSize)))

		local pivotOk, pivot = pcall(function()
			return (model :: Model):GetPivot()
		end)
		if pivotOk and pivot then
			logCompositeDebug("9) pivot parent :", describeCFrame(pivot))
		end

		local bbOk, packed = pcall(function()
			local cf, size = (model :: Model):GetBoundingBox()
			return { cf, size }
		end)
		if bbOk and type(packed) == "table" then
			logCompositeDebug("7) taille mesurée :", tostring(packed[2]))
			if typeof(packed[1]) == "CFrame" then
				logCompositeDebug("8) bounding box :", describeCFrame(packed[1] :: CFrame),
					"size=", tostring(packed[2]))
			end
		else
			logCompositeDebug("7/8) bounding box : lecture impossible")
		end

		local visual = model:FindFirstChild("Visual")
		if visual and visual:IsA("BasePart") then
			logCompositeDebug("10) Visual local/world :", describeCFrame(visual.CFrame))
			local parentModel = model :: Model
			local localOk, localCF = pcall(function()
				return parentModel:GetPivot():ToObjectSpace(visual.CFrame)
			end)
			if localOk and localCF then
				logCompositeDebug("10b) Visual en espace modèle :", describeCFrame(localCF))
			end
		else
			logCompositeDebug("10) MeshPart Visual : absent")
		end
	end

	local result = decision.Result
	if result then
		logCompositeDebug("3) Validate.Valid :", tostring(result.Valid))
		if result.Issues and #result.Issues > 0 then
			for _, issue in ipairs(result.Issues) do
				logCompositeDebug("4) issue", issue.Code .. ":", issue.Message)
			end
		else
			logCompositeDebug("4) issues : (aucune)")
		end
	else
		logCompositeDebug("3) Validate : (pas de Result — status=" .. tostring(decision.Status) .. ")")
	end

	logCompositeDebug(
		"11) DecideVisualMode/Decide :",
		("Status=%s BuildPrototype=%s"):format(
			tostring(decision.Status), tostring(decision.BuildPrototype)
		)
	)
	if decision.Message then
		logCompositeDebug("4) warning/message :", decision.Message)
	end
end

local function decideDeckImport(): any
	-- FullHubComposite : HubDeckShell_New / HubDeckShell (Workspace ou CentralHubVisual).
	local useImported = H.Assets.Deck ~= nil and H.Assets.Deck.UseImported == true
	local source, err = resolveFullHubSource()
	if source then
		fullHubSource = source
		fullHubActive = true
		return {
			Key = "Deck",
			Status = "imported",
			BuildPrototype = false,
			Message = nil,
			Variant = FULL_HUB_VARIANT,
		}
	end
	fullHubSource = nil
	fullHubActive = false
	if useImported then
		local message = ("[FullHubComposite] Source missing/invalid: Workspace.%s or StudioDecoration.CentralHubVisual (%s).")
			:format(FULL_HUB_MODEL_NAME, err or "absent")
		warn(message)
		return {
			Key = "Deck",
			Status = "missing",
			BuildPrototype = true,
			Message = message,
		}
	end
	return {
		Key = "Deck",
		Status = "disabled",
		BuildPrototype = true,
		Message = nil,
	}
end

-- true : le code doit générer la forme (aucun asset importé actif pour ce module).
local function shouldBuild(assetKey: string): boolean
	-- FullHubComposite remplace tout le visuel code du hub.
	if fullHubActive then
		return false
	end
	if assetKey == "Deck" then
		return not deckImportActive
	end
	-- Composite Tripo : rim / médaillon / boucle / escaliers code remplacés par le mesh.
	if deckIsComposite then
		if assetKey == "DeckRim"
			or assetKey == "SpawnMedallion"
			or assetKey == "LoopPanel"
			or assetKey == "Stairs" then
			return false
		end
	end
	return HubLayout.ShouldBuildCodeVisual(assetKey, importedModel(assetKey) ~= nil)
end

local function debugProxiesEnabled(): boolean
	if H.DebugCollisionProxies ~= true then
		return false
	end
	local ok, studio = pcall(function()
		return RunService:IsStudio()
	end)
	return ok and studio == true
end

local function disablePrototypeColliders(structure: Folder)
	local disabled: { string } = {}
	local nameSet: { [string]: boolean } = {}
	for _, name in ipairs(PROTOTYPE_COLLIDER_NAMES) do
		nameSet[name] = true
	end
	for _, desc in ipairs(structure:GetDescendants()) do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			local isLegacy = nameSet[part.Name] == true
				or string.find(part.Name, "Collider", 1, true) ~= nil
				or string.sub(part.Name, 1, 4) == "Rail"
				or string.sub(part.Name, 1, 4) == "Deck"
				or string.sub(part.Name, 1, 6) == "Plinth"
			if isLegacy and part.CanCollide then
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				table.insert(disabled, fullPath(part))
				if debugProxiesEnabled() then
					part.Transparency = 0.55
					part.Color = Color3.fromRGB(255, 80, 80)
				end
			end
		end
	end
	if debugProxiesEnabled() and #disabled > 0 then
		print("[CentralHub] anciennes collisions prototype désactivées :")
		for _, path in ipairs(disabled) do
			print("  " .. path)
		end
	end
	return disabled
end

local function softenStandCollisions(structure: Folder)
	local noCollide: { [string]: boolean } = {}
	for _, name in ipairs(STAND_VISUAL_NO_COLLIDE) do
		noCollide[name] = true
	end
	for _, desc in ipairs(structure:GetDescendants()) do
		if desc:IsA("BasePart") and noCollide[desc.Name] then
			local part = desc :: BasePart
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end
	-- Dosserets intentionnels uniquement (derrière le comptoir).
	for _, name in ipairs({ "HubSellBackWall", "HubShopBackWall" }) do
		local wall = structure:FindFirstChild(name)
		if wall and wall:IsA("BasePart") then
			wall.CanCollide = true
			wall.CanTouch = false
		end
	end
end

local function clearAllCollisionProxyFolders(functional: Folder)
	for _, name in ipairs(LEGACY_PROXY_FOLDERS) do
		local existing = functional:FindFirstChild(name)
		if existing then
			logFinalFix("Removed proxy folder:", fullPath(existing))
			existing:Destroy()
		end
	end
end

local function clearCompositeProxies(functional: Folder)
	clearAllCollisionProxyFolders(functional)
end

local function auditNearbyColliders(hubCenter: Vector3, radius: number)
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			if part.CanCollide then
				local pos = part.Position
				local flat = Vector3.new(pos.X - hubCenter.X, 0, pos.Z - hubCenter.Z)
				if flat.Magnitude <= radius then
					local topY = pos.Y + part.Size.Y * 0.5
					local orient = part.Orientation
					logFinalFix("Collider:")
					logFinalFix("Path:", fullPath(part))
					logFinalFix("Name:", part.Name)
					logFinalFix("Position:", tostring(pos))
					logFinalFix("Size:", tostring(part.Size))
					logFinalFix("Orientation:", tostring(orient))
					logFinalFix("Transparency:", tostring(part.Transparency))
					logFinalFix("TopY:", tostring(topY))
				end
			end
		end
	end
end

local LEGACY_WALL_COUNTER_NAMES: { [string]: boolean } = {
	OuterRail_Left = true,
	OuterRail_Right = true,
	OuterRail_BackLeft = true,
	OuterRail_BackRight = true,
	SellCounterCollider = true,
	SellWallLeftCollider = true,
	SellWallRightCollider = true,
	ShopCounterCollider = true,
	ShopWallLeftCollider = true,
	ShopWallRightCollider = true,
	TransitWallLeftCollider = true,
	TransitWallRightCollider = true,
	TransitTopCollider = true,
}

local function isLegacyWallOrCounterName(name: string): boolean
	if LEGACY_WALL_COUNTER_NAMES[name] then
		return true
	end
	if string.find(name, "OuterRail_", 1, true)
		or string.find(name, "SellWall", 1, true)
		or string.find(name, "ShopWall", 1, true)
		or string.find(name, "TransitWall", 1, true)
		or name == "SellCounterCollider"
		or name == "ShopCounterCollider"
		or name == "TransitTopCollider"
	then
		return true
	end
	return string.find(name, "Kiosk", 1, true) ~= nil
		and string.find(name, "Collider", 1, true) ~= nil
end

local function disableLegacyHubColliders(root: Folder, structure: Folder)
	local keepParents: { [Instance]: boolean } = {}
	local keepFloorNames: { [string]: boolean } = {
		MainHubFloor = true,
		SellFloor = true,
		ShopFloor = true,
		TransitFloor = true,
	}
	local finalFolder = root:FindFirstChild(FUNCTION)
	local proxies = if finalFolder then finalFolder:FindFirstChild(HUB_COLLISION_PROXIES) else nil
	if proxies then
		keepParents[proxies] = true
	end

	-- Retirer les anciens proxies murs/comptoirs (ne doivent pas se superposer au MeshPart).
	local toRemove: { Instance } = {}
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("BasePart") and isLegacyWallOrCounterName(desc.Name) and not keepFloorNames[desc.Name] then
			table.insert(toRemove, desc)
		end
	end
	for _, desc in ipairs(toRemove) do
		logFinalFix("Removed legacy wall/counter collider:", fullPath(desc))
		desc:Destroy()
	end

	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			if part:IsA("MeshPart") then
				continue
			end
			if part.CanCollide and part.Transparency >= 0.99 then
				local parent = part.Parent
				if parent and keepParents[parent] and keepFloorNames[part.Name] then
					continue
				end
				local name = part.Name
				local path = fullPath(part)
				local isLegacy = string.find(path, COMPOSITE_PROXIES, 1, true)
					or string.find(path, "FullHubCollisionProxies", 1, true)
					or (string.find(path, "HubCollisionProxies", 1, true) and not keepFloorNames[name])
					or string.find(name, "Deck", 1, true)
					or string.find(name, "Rail", 1, true)
					or string.find(name, "Step", 1, true)
					or string.find(name, "Stairs", 1, true)
					or string.find(name, "Platform", 1, true)
					or string.find(name, "Foundation", 1, true)
					or string.find(name, "Plinth", 1, true)
					or (part:GetAttribute("GeneratedByCode") == true and not keepFloorNames[name])
				if isLegacy then
					logFinalFix("Disabled legacy collider:", path)
					part.CanCollide = false
					part.CanTouch = false
					part.CanQuery = false
				end
			end
		end
	end
	-- Structure visible prototype résiduelle : jamais collisionnable en FullHub.
	for _, desc in ipairs(structure:GetDescendants()) do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			if part.CanCollide then
				logFinalFix("Disabled structure collider:", fullPath(part))
				part.CanCollide = false
			end
		end
	end
end

local function logCollisionFix(...: any)
	local parts = { "[HubCollisionFix]" }
	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end
	print(table.concat(parts, " "))
end

local function isHorizontallyLevel(cf: CFrame): boolean
	return math.abs(cf.UpVector:Dot(Vector3.yAxis) - 1) < 0.001
		and math.abs(cf.LookVector.Y) < 0.001
		and math.abs(cf.RightVector.Y) < 0.001
end

local function auditCollisionFix(runtime: Model, proxiesFolder: Folder)
	local pivotOk, pivot = pcall(function()
		return runtime:GetPivot()
	end)
	if pivotOk and pivot then
		logCollisionFix("CFrame/pivot parent :", describeCFrame(pivot))
		logCollisionFix(
			"rotation parent horizontale :",
			tostring(isHorizontallyLevel(pivot))
		)
	end
	local bbOk, packed = pcall(function()
		local cf, size = runtime:GetBoundingBox()
		return { cf, size }
	end)
	if bbOk and type(packed) == "table" then
		logCollisionFix("taille mesurée :", tostring(packed[2]))
		if typeof(packed[1]) == "CFrame" then
			logCollisionFix("bbox :", describeCFrame(packed[1] :: CFrame))
		end
	end
	local visual = runtime:FindFirstChild("Visual")
	if visual and visual:IsA("BasePart") then
		local part = visual :: BasePart
		logCollisionFix("Visual CFrame :", describeCFrame(part.CFrame))
		logCollisionFix("Visual horizontal :", tostring(isHorizontallyLevel(part.CFrame)))
		logCollisionFix(
			"Visual CanCollide/Touch/Query/Anchored :",
			tostring(part.CanCollide),
			tostring(part.CanTouch),
			tostring(part.CanQuery),
			tostring(part.Anchored)
		)
	else
		logCollisionFix("Visual MeshPart : absent")
	end
	logCollisionFix("proxies créés :")
	local allLevel = true
	for _, child in ipairs(proxiesFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local part = child :: BasePart
			local pos = part.CFrame.Position
			local top = pos.Y + part.Size.Y * 0.5
			local level = isHorizontallyLevel(part.CFrame)
			allLevel = allLevel and level
			logCollisionFix(
				("  %s size=%s center=%s topY=%.2f horizontal=%s collide=%s T=%.2f"):format(
					part.Name,
					tostring(part.Size),
					tostring(pos),
					top,
					tostring(level),
					tostring(part.CanCollide),
					part.Transparency
				)
			)
		end
	end
	logCollisionFix("deck gameplay horizontal (tous proxies) :", tostring(allLevel))
	logCollisionFix(
		"hauteurs cibles : deck=",
		tostring(H.DeckTopY),
		"ailes=",
		tostring(H.DeckTopY + H.SidePlatform.Rise)
	)
end

local function medianNumber(values: { number }): number
	local sorted = {}
	for i, value in ipairs(values) do
		sorted[i] = value
	end
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		error("[HubSurfaceFix] medianNumber: liste vide")
	end
	if n % 2 == 1 then
		return sorted[math.floor(n / 2) + 1]
	end
	return (sorted[n / 2] + sorted[n / 2 + 1]) * 0.5
end

local function raycastHubSurfaceY(visual: Model, x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { visual }
	params.IgnoreWater = true
	local origin = Vector3.new(x, 50, z)
	local result = workspace:Raycast(origin, Vector3.new(0, -120, 0), params)
	if not result then
		error(("[HubSurfaceFix] raycast échoué en (%.2f, %.2f) — surface introuvable"):format(x, z))
	end
	return result.Position.Y
end

local function measureHubSurfaceHeights(visual: Model): {
	MainTopY: number,
	SellTopY: number,
	ShopTopY: number,
	TransitTopY: number,
	CenterSamples: { number },
}
	local spawn = HubLayout.Spawn.Center
	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(4, 0, 0),
		Vector3.new(-4, 0, 0),
		Vector3.new(0, 0, 4),
		Vector3.new(0, 0, -4),
	}
	local centerSamples: { number } = {}
	for _, offset in ipairs(offsets) do
		local y = raycastHubSurfaceY(visual, spawn.X + offset.X, spawn.Z + offset.Z)
		table.insert(centerSamples, y)
	end
	logSurfaceFix("Center sample heights:", table.concat(
		(function()
			local s = {}
			for _, v in ipairs(centerSamples) do
				table.insert(s, string.format("%.3f", v))
			end
			return s
		end)(),
		", "
	))

	local mainTopY = medianNumber(centerSamples)
	local sellCenter = HubLayout.SellPlatform.Center
	local shopCenter = HubLayout.ShopPlatform.Center
	local transitXZ = HubLayout.GetTransitPosition()
	local sellTopY = raycastHubSurfaceY(visual, sellCenter.X, sellCenter.Z)
	local shopTopY = raycastHubSurfaceY(visual, shopCenter.X, shopCenter.Z)
	local transitTopY = raycastHubSurfaceY(visual, transitXZ.X, transitXZ.Z)

	logSurfaceFix("Main floor Y:", mainTopY)
	logSurfaceFix("Sell floor Y:", sellTopY)
	logSurfaceFix("Shop floor Y:", shopTopY)
	logSurfaceFix("Transit floor Y:", transitTopY)

	return {
		MainTopY = mainTopY,
		SellTopY = sellTopY,
		ShopTopY = shopTopY,
		TransitTopY = transitTopY,
		CenterSamples = centerSamples,
	}
end

local function makeCollisionProxy(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Parent: Instance,
	Role: string,
	MeasuredTopY: number?,
}): Part
	local p = makePart({
		Name = props.Name,
		Size = props.Size,
		CFrame = props.CFrame,
		Transparency = 1,
		CanCollide = true,
		CanQuery = false,
		Parent = props.Parent,
	})
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("HubColliderRole", props.Role)
	if props.MeasuredTopY ~= nil then
		p:SetAttribute("MeasuredTopY", props.MeasuredTopY)
	end
	return p
end

local function applyCollisionProxyDebug(folder: Folder)
	if not debugProxiesEnabled() then
		for _, child in ipairs(folder:GetDescendants()) do
			if child:IsA("BasePart") then
				child.Transparency = 1
				local bill = child:FindFirstChild("DebugLabel")
				if bill then
					bill:Destroy()
				end
			end
		end
		return
	end
	local roleColors: { [string]: Color3 } = {
		Floor = Color3.fromRGB(70, 160, 255),
		Sell = Color3.fromRGB(90, 230, 140),
		Shop = Color3.fromRGB(180, 90, 230),
		Transit = Color3.fromRGB(70, 220, 230),
		Outer = Color3.fromRGB(255, 160, 60),
	}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local role = child:GetAttribute("HubColliderRole")
			local color = roleColors[if type(role) == "string" then role else ""] or Color3.fromRGB(200, 200, 200)
			child.Transparency = 0.45
			child.Color = color
			child.Material = Enum.Material.Neon
			local existing = child:FindFirstChild("DebugLabel")
			if existing then
				existing:Destroy()
			end
			local bill = Instance.new("BillboardGui")
			bill.Name = "DebugLabel"
			bill.Size = UDim2.fromOffset(160, 28)
			bill.StudsOffset = Vector3.new(0, child.Size.Y * 0.5 + 1.5, 0)
			bill.AlwaysOnTop = true
			bill.Parent = child
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.TextColor3 = Color3.new(1, 1, 1)
			label.Text = child.Name
			label.Parent = bill
			print(("[HubGameplayFix] Collider %s path=%s pos=%s size=%s role=%s"):format(
				child.Name,
				fullPath(child),
				tostring(child.Position),
				tostring(child.Size),
				tostring(role)
			))
		end
	end
end

local function buildHubCollisionProxies(functional: Folder)
	local visual = fullHubSource
	if not visual then
		error("[HubGameplayFix] aucun modèle 3D actif pour mesurer les sols")
	end
	clearAllCollisionProxyFolders(functional)
	local mesh = findPrimaryMeshPart(visual)
	if mesh then
		print("[HubMeshCollision] Active MeshPart:", fullPath(mesh))
	end
	local bboxCF, bboxSize = visual:GetBoundingBox()
	print("[HubGameplayFix] Active visual:", fullPath(visual))
	print("[HubGameplayFix] Visual bounding box:", tostring(bboxCF.Position), tostring(bboxSize))

	local heights = measureHubSurfaceHeights(visual)
	local folder = Instance.new("Folder")
	folder.Name = HUB_COLLISION_PROXIES
	folder:SetAttribute("GeneratedByCode", true)
	folder.Parent = functional

	-- Sols pour placement spawn uniquement — murs/comptoirs = MeshPart PreciseConvex.
	local floors = {
		{ Name = "MainHubFloor", Size = Vector3.new(58, 1, 42), X = 0, Z = 0, TopY = heights.MainTopY, Role = "Floor" },
		{
			Name = "SellFloor",
			Size = Vector3.new(22, 1, 19),
			X = HubLayout.SellPlatform.Center.X,
			Z = HubLayout.SellPlatform.Center.Z,
			TopY = heights.SellTopY,
			Role = "Sell",
		},
		{
			Name = "ShopFloor",
			Size = Vector3.new(22, 1, 19),
			X = HubLayout.ShopPlatform.Center.X,
			Z = HubLayout.ShopPlatform.Center.Z,
			TopY = heights.ShopTopY,
			Role = "Shop",
		},
		{
			Name = "TransitFloor",
			Size = Vector3.new(12, 1, 12),
			X = 0,
			Z = HubLayout.GetTransitPosition().Z + 2,
			TopY = heights.TransitTopY,
			Role = "Transit",
		},
	}
	for _, spec in ipairs(floors) do
		makeCollisionProxy({
			Name = spec.Name,
			Size = spec.Size,
			CFrame = CFrame.new(spec.X, spec.TopY - spec.Size.Y / 2, spec.Z),
			Parent = folder,
			Role = spec.Role,
			MeasuredTopY = spec.TopY,
		})
	end

	applyCollisionProxyDebug(folder)
	print("[HubMeshCollision] Floor proxies only:", #folder:GetChildren())
	return folder, heights
end

local function buildFinalHubCollisionProxies(functional: Folder)
	return buildHubCollisionProxies(functional)
end

local function buildHubLightingRig(functional: Folder)
	local existing = functional:FindFirstChild(HUB_LIGHTING_RIG)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = HUB_LIGHTING_RIG
	folder:SetAttribute("GeneratedByCode", true)
	folder.Parent = functional

	local lights = {
		{ Name = "CenterFill", Position = Vector3.new(0, 34, 0) },
		{ Name = "SellFill", Position = Vector3.new(HubLayout.SellPlatform.Center.X, 30, 0) },
		{ Name = "ShopFill", Position = Vector3.new(HubLayout.ShopPlatform.Center.X, 30, 0) },
	}
	for _, spec in ipairs(lights) do
		local host = makePart({
			Name = spec.Name,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(spec.Position),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = folder,
		})
		host.CanTouch = false
		host.CastShadow = false
		local light = Instance.new("SurfaceLight")
		light.Name = "Fill"
		light.Face = Enum.NormalId.Bottom
		light.Brightness = 2
		light.Range = 38
		light.Angle = 120
		light.Shadows = false
		light.Color = Color3.fromRGB(220, 235, 255)
		light.Parent = host
	end
	logSurfaceFix("HubLightingRig lights:", #lights)
	return folder
end

local function buildCompositeCollisionProxies(functional: Folder, _structure: Folder)
	buildFinalHubCollisionProxies(functional)
end

local function purgeLegacyBubbleTransit()
	local gameZones = workspace:FindFirstChild("GameZones")
	local terminals = gameZones and gameZones:FindFirstChild("TravelTerminals")
	if terminals then
		for _, child in ipairs(terminals:GetChildren()) do
			local isLobby = child.Name == "BubbleTransit_LobbyTransit"
				or child:GetAttribute("TransitId") == "LobbyTransit"
				or child:GetAttribute("PlacementKey") == "Lobby"
			if isLobby then
				logFinalFix("Transit object:", fullPath(child))
				child:Destroy()
			end
		end
	end
	-- Anciens pads / anneaux générés hors TravelTerminals.
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:GetAttribute("BubbleTransit") == true then
			local path = fullPath(desc)
			if string.find(path, "LobbyTransit", 1, true)
				or string.find(path, "HubTransit", 1, true)
			then
				if not string.find(path, "CentralHub.HubFunction", 1, true)
					and not string.find(path, "BubbleTransitInteractionAnchor", 1, true)
				then
					logFinalFix("Transit object:", path)
					desc:Destroy()
				end
			end
		end
	end
end

-- =============================================================================
-- Bubble Transit — propriétaire unique du ProximityPrompt hub
-- =============================================================================
-- Ancre permanente (Studio / Rojo) UNIQUEMENT :
--   Workspace.BubbleTransitInteractionAnchor
-- Jamais sous CentralHub runtime. Jamais CFrame/Position/PivotTo/Parent vers hub.
local TRANSIT_IMPLEMENTATION_VERSION = 9101
local TRANSIT_IMPLEMENTATION_TAG = "STUDIO_PERMANENT_ANCHOR"
local TRANSIT_OWNER_SCRIPT = (function()
	local ok, name = pcall(function()
		return script:GetFullName()
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return "ServerScriptService.Server.CentralHubBuilder"
end)()

local PERMANENT_ANCHOR_NAME = "BubbleTransitInteractionAnchor"

local function isHubBubbleTransitPrompt(desc: Instance): boolean
	if not desc:IsA("ProximityPrompt") then
		return false
	end
	local p = desc :: ProximityPrompt
	if p.Name == "BubbleTransitPrompt" then
		return true
	end
	if string.find(p.ObjectText or "", "Bubble Transit", 1, true) then
		return true
	end
	if p:GetAttribute("TransitImplementation") == TRANSIT_IMPLEMENTATION_TAG then
		return true
	end
	return false
end

local function stripBubbleTransitDebugVisuals()
	local toDestroy: { Instance } = {}
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc.Name == "BubbleTransitDebugAnchorLabel"
			or desc.Name == "ACTIVE_TRANSIT_PROMPT_MARKER_v9003"
		then
			table.insert(toDestroy, desc)
		elseif desc:IsA("BillboardGui") then
			for _, child in ipairs(desc:GetDescendants()) do
				if child:IsA("TextLabel") and (
					string.find(child.Text, "BUBBLE TRANSIT ANCHOR", 1, true)
						or string.find(child.Text, "Travel v9003", 1, true)
					)
				then
					table.insert(toDestroy, desc)
					break
				end
			end
		end
	end
	for _, inst in ipairs(toDestroy) do
		if inst.Parent then
			inst:Destroy()
		end
	end
end

-- Rendre invisible en F5 ; ne touche JAMAIS CFrame / Position / Parent.
local function applyPlayModeAnchorProps(anchor: BasePart)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	if anchor.Material == Enum.Material.Neon then
		anchor.Material = Enum.Material.SmoothPlastic
	end
end

-- Exclusif : enfant direct de Workspace (permanent Studio).
local function findPermanentStudioAnchor(): BasePart?
	local direct = workspace:FindFirstChild(PERMANENT_ANCHOR_NAME)
	if direct and direct:IsA("BasePart") then
		return direct
	end
	return nil
end

local function destroyCompetingTransitInstances(keepAnchor: BasePart?)
	local toDestroy: { Instance } = {}
	for _, desc in ipairs(workspace:GetDescendants()) do
		local name = desc.Name
		if desc:IsA("ProximityPrompt") and isHubBubbleTransitPrompt(desc) then
			if not (keepAnchor and desc:IsDescendantOf(keepAnchor)) then
				table.insert(toDestroy, desc)
			end
		elseif name == "BubbleTransitDebugAnchorLabel"
			or name == "ACTIVE_TRANSIT_PROMPT_MARKER_v9003"
			or name == "BubbleTransitPortal"
			or name == "BubbleTransitPortalZone"
			or name == "BubbleTransitInteraction"
			or name == "HubBubbleTransitTrigger"
			or name == "TransitPrompt"
		then
			table.insert(toDestroy, desc)
		elseif name == PERMANENT_ANCHOR_NAME and desc:IsA("BasePart") then
			-- Supprime les anciennes ancres sous CentralHub / runtime (conserve Workspace.*).
			if keepAnchor then
				if desc ~= keepAnchor then
					table.insert(toDestroy, desc)
				end
			elseif desc.Parent ~= workspace then
				table.insert(toDestroy, desc)
			end
		elseif name == "BubbleTransitTrigger" and desc:IsA("BasePart") then
			local path = fullPath(desc)
			if string.find(path, "CentralHub", 1, true) or string.find(path, "HubDeckShell", 1, true) then
				table.insert(toDestroy, desc)
			end
		end
	end
	for _, inst in ipairs(toDestroy) do
		if inst.Parent then
			logFinalFix("Transit purge/competing:", fullPath(inst))
			inst:Destroy()
		end
	end
	stripBubbleTransitDebugVisuals()
end

local function ensurePromptOnAnchor(anchor: BasePart, maxDist: number): ProximityPrompt
	local attach = anchor:FindFirstChild("PromptAttachment")
	if not (attach and attach:IsA("Attachment")) then
		if attach then
			attach:Destroy()
		end
		local a = Instance.new("Attachment")
		a.Name = "PromptAttachment"
		a.Position = Vector3.new(0, 0.2, 0)
		a.Parent = anchor
		attach = a
	end

	local promptInst = attach:FindFirstChild("BubbleTransitPrompt")
	if not (promptInst and promptInst:IsA("ProximityPrompt")) then
		if promptInst then
			promptInst:Destroy()
		end
		local p = Instance.new("ProximityPrompt")
		p.Name = "BubbleTransitPrompt"
		p.Parent = attach
		promptInst = p
	end
	local prompt = promptInst :: ProximityPrompt
	prompt.ActionText = "Travel"
	prompt.ObjectText = "Bubble Transit"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = maxDist
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = true
	prompt:SetAttribute("DiagnosticVersion", nil)
	prompt:SetAttribute("DetectedByScript", nil)
	prompt:SetAttribute("CreatedByScript", TRANSIT_OWNER_SCRIPT)
	prompt:SetAttribute("TransitImplementation", TRANSIT_IMPLEMENTATION_TAG)
	prompt:SetAttribute("TransitVersion", TRANSIT_IMPLEMENTATION_VERSION)

	anchor:SetAttribute("BubbleTransit", true)
	anchor:SetAttribute("TransitId", "LobbyTransit")
	anchor:SetAttribute("CurrentArea", "Lobby")
	anchor:SetAttribute("HubInteraction", "Transit")
	anchor:SetAttribute("PersistentStudioPlacement", true)
	anchor:SetAttribute("TransitImplementation", TRANSIT_IMPLEMENTATION_TAG)

	return prompt
end

local function countActiveTransitPrompts(): number
	local n = 0
	for _, desc in ipairs(workspace:GetDescendants()) do
		if isHubBubbleTransitPrompt(desc) then
			n += 1
		end
	end
	return n
end

local function ensureLobbyArrivalTerminal(functional: Folder, floorY: number, anchor: BasePart)
	local terminal = functional:FindFirstChild("BubbleTransit_LobbyTransit")
	if terminal and not terminal:IsA("Model") then
		terminal:Destroy()
		terminal = nil
	end
	if not terminal then
		local model = Instance.new("Model")
		model.Name = "BubbleTransit_LobbyTransit"
		model.Parent = functional
		terminal = model
	end
	local term = terminal :: Model
	term:SetAttribute("GeneratedByCode", true)
	term:SetAttribute("BubbleTransit", true)
	term:SetAttribute("TransitId", "LobbyTransit")
	term:SetAttribute("CurrentArea", "Lobby")
	term:SetAttribute("PlacementKey", "Lobby")
	term:SetAttribute("ArrivalMarkerName", "LobbyTravelArrival")

	local arrivalY = floorY + 3
	local function ensureInvisibleMarker(name: string): BasePart
		local marker = term:FindFirstChild(name)
		if marker and not marker:IsA("BasePart") then
			marker:Destroy()
			marker = nil
		end
		local part: BasePart
		if marker and marker:IsA("BasePart") then
			part = marker
		else
			part = Instance.new("Part")
			part.Name = name
			part.Parent = term
		end
		part.Anchored = true
		part.Size = Vector3.new(1, 1, 1)
		-- Arrivée suit l’ancre Workspace (lecture Position seulement).
		part.CFrame = CFrame.new(anchor.Position.X, arrivalY, anchor.Position.Z)
			* CFrame.Angles(0, math.rad(H.Transit.YawDegrees), 0)
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part:SetAttribute("GeneratedByCode", true)
		part:SetAttribute("TravelArrival", true)
		return part
	end
	local arrival = ensureInvisibleMarker("LobbyTravelArrival")
	ensureInvisibleMarker("TravelArrival")
	term.PrimaryPart = arrival

	local link = functional:FindFirstChild("BubbleTransitInteractionAnchorLink")
	if link then
		link:Destroy()
	end
	local objectLink = Instance.new("ObjectValue")
	objectLink.Name = "BubbleTransitInteractionAnchorLink"
	objectLink.Value = anchor
	objectLink.Parent = functional
end

local function buildBubbleTransitPortalZone(functional: Folder, mainFloorTopY: number?)
	local floorY = if type(mainFloorTopY) == "number" then mainFloorTopY else H.DeckTopY
	local maxDist = HubLayout.GetBubbleTransitMaxActivationDistance()

	stripBubbleTransitDebugVisuals()

	-- Uniquement Workspace.BubbleTransitInteractionAnchor (permanent édition).
	local anchor = findPermanentStudioAnchor()
	if not anchor then
		warn("[BubbleTransit] Missing permanent anchor: Workspace.BubbleTransitInteractionAnchor")
		destroyCompetingTransitInstances(nil)
		return nil
	end

	-- JAMAIS anchor.CFrame / Position / PivotTo / Parent = CentralHub.
	-- JAMAIS Size — placement manuel Studio autoritaire (preservé).
	applyPlayModeAnchorProps(anchor)

	destroyCompetingTransitInstances(anchor)

	local prompt = ensurePromptOnAnchor(anchor, maxDist)
	ensureLobbyArrivalTerminal(functional, floorY, anchor)

	local promptCount = countActiveTransitPrompts()
	print("[BubbleTransit] PlacementSource=Workspace.BubbleTransitInteractionAnchor")
	print("[BubbleTransit] AnchorPath=" .. fullPath(anchor))
	print("[BubbleTransit] AnchorWorldPosition=" .. tostring(anchor.Position) .. " (unchanged by code)")
	print("[BubbleTransit] ActivePromptCount=" .. tostring(promptCount))
	print("[BubbleTransit] OwnerScript=" .. TRANSIT_OWNER_SCRIPT)
	print("[BubbleTransit] TransitVersion=" .. tostring(TRANSIT_IMPLEMENTATION_VERSION))

	if promptCount ~= 1 then
		warn("[BubbleTransit] Expected ActivePromptCount=1, got " .. tostring(promptCount))
	end

	return anchor, anchor.Position, anchor.Position
end

local function buildBubbleTransitTrigger(functional: Folder, transitTopY: number?)
	return buildBubbleTransitPortalZone(functional, transitTopY)
end


local function sanitizeAllSpawnLocations(activeSpawn: SpawnLocation)
	local found: { SpawnLocation } = {}
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("SpawnLocation") then
			table.insert(found, desc :: SpawnLocation)
		end
	end
	for _, sl in ipairs(found) do
		logFinalFix("SpawnLocation found:", fullPath(sl))
		local function stripVisuals(root: Instance)
			for _, child in ipairs(root:GetDescendants()) do
				if child:IsA("Decal")
					or child:IsA("Texture")
					or child:IsA("SurfaceGui")
					or child:IsA("BillboardGui")
					or child:IsA("SelectionBox")
				then
					child:Destroy()
				end
			end
		end
		stripVisuals(sl)
		sl.Transparency = 1
		sl.CanCollide = false
		sl.CanTouch = false
		sl.CanQuery = false
		sl.CastShadow = false
		if sl == activeSpawn then
			sl.Enabled = true
			sl.Neutral = true
		else
			sl.Enabled = false
		end
	end
end

local function auditHubColliders(root: Folder)
	if not debugProxiesEnabled() then
		return
	end
	print("[CentralHub] Audit BasePart CanCollide=true près du hub :")
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			if part.CanCollide then
				local builder = if part:GetAttribute("GeneratedByCode") == true
					then "CentralHubBuilder"
					elseif part:IsDescendantOf(root:FindFirstChild(STRUCTURE) or root)
					then "structure"
					else "?"
				local role = "autre"
				local path = fullPath(part)
				if string.find(path, COMPOSITE_PROXIES, 1, true) then
					role = "collision-fonctionnelle"
				elseif string.find(path, "HubDeckShell", 1, true) then
					role = "composite-visuel-studio"
				elseif string.find(part.Name, "Sell", 1, true) then
					role = "Sell"
				elseif string.find(part.Name, "Shop", 1, true) then
					role = "Shop"
				elseif string.find(part.Name, "Step", 1, true) or string.find(part.Name, "Stairs", 1, true) then
					role = "escalier"
				elseif string.find(part.Name, "Rail", 1, true) or string.find(part.Name, "Deck", 1, true) then
					role = "prototype"
				end
				print(("  %s | %s | pos=%s size=%s T=%.2f | %s | %s"):format(
					part.Name,
					path,
					tostring(part.Position),
					tostring(part.Size),
					part.Transparency,
					builder,
					role
				))
			end
		end
	end
end

local function mountFullHubSource(): boolean
	local source = fullHubSource
	if not source then
		return false
	end
	local beforeCF, beforeSize, beforeParent = snapshotFullHubMesh(source)
	prepareFullHubSource(source)
	local modified = fullHubTransformModified(source, beforeCF, beforeSize, beforeParent)
	logFullHub("Source found:", fullPath(source))
	logFullHub("Visual mode:", FULL_HUB_VARIANT)
	logFullHub("Prototype visual generated: false")
	logFullHub("Source transform modified:", tostring(modified))
	if modified then
		error("[FullHubComposite] transform source modifiée — interdit")
	end
	return true
end

-- Panneaux freestanding générés sous CentralHub uniquement (jamais StudioDecoration).
local LEGACY_BOARD_NAME_PREFIXES = {
	"GlobalLeaderboardBoard",
	"HubRulesBoard",
	"Top3Face",
	"HubTopBoard",
	"HubRulesBoardFrame",
	"HubTop3BoardFrame",
	"HubArchPanels",
	"HubArchTop5Face",
	"HubArchRulesFace",
	"HubArchTrophyIcon",
	"HubArchClipboardIcon",
	"LeftArchTop5Display",
	"RightArchRulesDisplay",
	"LeftArchDisplay",
	"RightArchDisplay",
	"Top5Display",
	"RulesDisplay",
	"LeftArchTrophyIcon",
	"RightArchClipboardIcon",
	"Top3Board",
	"RulesBoard",
	"TrophyIcon",
	"ClipboardIcon",
}

local function destroyLegacyBoardParts(root: Instance)
	local toDestroy: { Instance } = {}
	for _, desc in ipairs(root:GetDescendants()) do
		-- Ne jamais toucher aux repères Studio persistants.
		local path = fullPath(desc)
		if string.find(path, "StudioDecoration", 1, true) then
			continue
		end
		for _, prefix in ipairs(LEGACY_BOARD_NAME_PREFIXES) do
			if desc.Name == prefix or string.sub(desc.Name, 1, #prefix) == prefix then
				table.insert(toDestroy, desc)
				break
			end
		end
	end
	for _, inst in ipairs(toDestroy) do
		if inst.Parent then
			inst:Destroy()
		end
	end
	topBoard = nil
end

local function findStudioHubDisplays(): Instance?
	local decor = workspace:FindFirstChild(H.Visual.StudioDecorationRoot)
	local visual = decor and decor:FindFirstChild(H.Visual.VisualFolder)
	local displays = visual and visual:FindFirstChild("HubDisplays")
	if displays then
		return displays
	end
	return nil
end

local function resolveGuiFaceTowardHub(part: BasePart, hubCenter: Vector3): Enum.NormalId
	local toHub = hubCenter - part.Position
	if toHub.Magnitude < 1e-6 then
		return Enum.NormalId.Front
	end
	toHub = toHub.Unit
	-- LookVector = normale sortante de la face Front.
	if part.CFrame.LookVector:Dot(toHub) >= 0 then
		return Enum.NormalId.Front
	end
	return Enum.NormalId.Back
end

local function applyInvisibleMarkerProps(part: BasePart)
	-- Props runtime uniquement — jamais CFrame / Size / Orientation / Parent.
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
end

local ARCH_SCREEN_BG = Color3.fromRGB(6, 12, 26)
local ARCH_STROKE_METAL = Color3.fromRGB(72, 80, 94)
local ARCH_STROKE_CYAN = Color3.fromRGB(70, 210, 255)

local function ensureNamedSurfaceGui(
	part: BasePart,
	name: string,
	face: Enum.NormalId,
	canvas: Vector2?
): SurfaceGui
	local existing = part:FindFirstChild(name)
	if existing and not existing:IsA("SurfaceGui") then
		existing:Destroy()
		existing = nil
	end
	local gui: SurfaceGui
	if existing and existing:IsA("SurfaceGui") then
		gui = existing
	else
		gui = Instance.new("SurfaceGui")
		gui.Name = name
		gui.Parent = part
	end
	gui.Adornee = part
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas or Vector2.new(1024, 768)
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ZOffset = 1
	gui.Enabled = true
	return gui
end

local function styleArchScreenRoot(gui: SurfaceGui): Frame
	for _, child in ipairs(gui:GetChildren()) do
		child:Destroy()
	end
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = ARCH_SCREEN_BG
	root.BackgroundTransparency = 0.12
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = root

	local metal = Instance.new("UIStroke")
	metal.Name = "MetalStroke"
	metal.Color = ARCH_STROKE_METAL
	metal.Thickness = 3
	metal.Transparency = 0.15
	metal.Parent = root

	local glow = Instance.new("Frame")
	glow.Name = "CyanRim"
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.Parent = root
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 18)
	glowCorner.Parent = glow
	local cyan = Instance.new("UIStroke")
	cyan.Name = "CyanStroke"
	cyan.Color = ARCH_STROKE_CYAN
	cyan.Thickness = 1.5
	cyan.Transparency = 0.4
	cyan.Parent = glow

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.04, 0)
	padding.PaddingBottom = UDim.new(0.04, 0)
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = root

	return root
end

local function purgeIconBillboards()
	local doomed: { Instance } = {}
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("BillboardGui") then
			local name = desc.Name
			if name == "TrophyBillboard"
				or name == "ClipboardBillboard"
				or name == "LeftArchTrophyIcon"
				or name == "RightArchClipboardIcon"
				or name == "HubArchTrophyIcon"
				or name == "HubArchClipboardIcon"
				or name == "TrophyIcon"
				or name == "ClipboardIcon"
			then
				table.insert(doomed, desc)
			else
				for _, child in ipairs(desc:GetDescendants()) do
					if child:IsA("TextLabel") and (child.Text == "🏆" or child.Text == "📋") then
						table.insert(doomed, desc)
						break
					end
				end
			end
		end
	end
	for _, inst in ipairs(doomed) do
		if inst.Parent then
			inst:Destroy()
		end
	end
end

local function ensureEmojiSurfaceGui(anchor: BasePart, name: string, emoji: string, face: Enum.NormalId): SurfaceGui
	for _, child in ipairs(anchor:GetChildren()) do
		if child:IsA("BillboardGui")
			or child.Name == "TrophyBillboard"
			or child.Name == "ClipboardBillboard"
		then
			child:Destroy()
		end
	end

	local gui = ensureNamedSurfaceGui(anchor, name, face, Vector2.new(256, 256))
	for _, child in ipairs(gui:GetChildren()) do
		child:Destroy()
	end
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = gui

	local text = Instance.new("TextLabel")
	text.Name = "Emoji"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(0.75, 0.75)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Text = emoji
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.Parent = root
	return gui
end

local function buildRulesContent(gui: SurfaceGui)
	local frame = styleArchScreenRoot(gui)

	newLabel(frame, {
		Text = L10n.HubRulesTitle,
		Size = UDim2.fromScale(0.92, 0.16),
		Position = UDim2.fromScale(0.5, 0.12),
		Color = ARCH_STROKE_CYAN,
		Stroke = ARCH_STROKE_METAL,
	})

	local rules = { L10n.HubRule1, L10n.HubRule2, L10n.HubRule3, L10n.HubRule4 }
	for i, text in ipairs(rules) do
		local y = 0.30 + (i - 1) * 0.165
		local row = newFrame(
			frame,
			UDim2.fromScale(0.94, 0.14),
			UDim2.fromScale(0.5, y),
			Color3.fromRGB(12, 20, 36),
			12
		)
		row.BackgroundTransparency = 0.35
		newLabel(row, {
			Text = tostring(i),
			Size = UDim2.fromScale(0.12, 0.72),
			Position = UDim2.fromScale(0.1, 0.5),
			Color = ARCH_STROKE_CYAN,
			Dynamic = true,
		})
		newLabel(row, {
			Text = text,
			Size = UDim2.fromScale(0.76, 0.7),
			Position = UDim2.fromScale(0.56, 0.5),
			Color = C.White,
			Font = Enum.Font.GothamBold,
			Align = Enum.TextXAlignment.Left,
		})
	end
end

-- Bind UI sur les repères Studio HubDisplays (positions manuelles intouchables).
local function buildHubArchIntegratedPanels(functional: Folder, _mainFloorTopY: number?)
	local hubRoot = functional.Parent
	if hubRoot then
		destroyLegacyBoardParts(hubRoot)
	end
	-- Purge copies flottantes hors StudioDecoration.
	local floatingNames = {
		LeftArchTop5Display = true,
		RightArchRulesDisplay = true,
		Top5Display = true,
		RulesDisplay = true,
		Top3Board = true,
		RulesBoard = true,
		TrophyIcon = true,
		ClipboardIcon = true,
		HubArchPanels = true,
		TrophyBillboard = true,
		ClipboardBillboard = true,
	}
	local floatingToDestroy: { Instance } = {}
	for _, desc in ipairs(workspace:GetDescendants()) do
		if floatingNames[desc.Name] and not string.find(fullPath(desc), "StudioDecoration", 1, true) then
			table.insert(floatingToDestroy, desc)
		end
	end
	for _, inst in ipairs(floatingToDestroy) do
		if inst.Parent then
			inst:Destroy()
		end
	end
	purgeIconBillboards()

	local displays = findStudioHubDisplays()
	if not displays then
		warn("[HubDisplays] StudioDecoration.CentralHubVisual.HubDisplays introuvable")
		return
	end

	local top5Face = displays:FindFirstChild("Top5Face")
	local rulesFace = displays:FindFirstChild("RulesFace")
	local trophyAnchor = displays:FindFirstChild("TrophyAnchor")
	local clipboardAnchor = displays:FindFirstChild("ClipboardAnchor")
	if not (top5Face and top5Face:IsA("BasePart")
		and rulesFace and rulesFace:IsA("BasePart")
		and trophyAnchor and trophyAnchor:IsA("BasePart")
		and clipboardAnchor and clipboardAnchor:IsA("BasePart"))
	then
		warn("[HubDisplays] Top5Face/RulesFace/TrophyAnchor/ClipboardAnchor incomplets")
		return
	end

	-- Snapshot : garantir qu'aucune transform n'est modifiée.
	local top5CF, top5Size = top5Face.CFrame, top5Face.Size
	local rulesCF, rulesSize = rulesFace.CFrame, rulesFace.Size
	local trophyCF, trophySize = trophyAnchor.CFrame, trophyAnchor.Size
	local clipCF, clipSize = clipboardAnchor.CFrame, clipboardAnchor.Size

	local hubCenter = HubLayout.Center
	local proxies = functional:FindFirstChild(HUB_COLLISION_PROXIES)
	local mainFloor = proxies and proxies:FindFirstChild("MainHubFloor")
	if mainFloor and mainFloor:IsA("BasePart") then
		local floorTopY = mainFloor.Position.Y + mainFloor.Size.Y / 2
		hubCenter = Vector3.new(mainFloor.Position.X, floorTopY, mainFloor.Position.Z)
	end

	local top5GuiFace = resolveGuiFaceTowardHub(top5Face, hubCenter)
	local rulesGuiFace = resolveGuiFaceTowardHub(rulesFace, hubCenter)
	local trophyGuiFace = resolveGuiFaceTowardHub(trophyAnchor, hubCenter)
	local clipboardGuiFace = resolveGuiFaceTowardHub(clipboardAnchor, hubCenter)

	applyInvisibleMarkerProps(top5Face)
	applyInvisibleMarkerProps(rulesFace)
	applyInvisibleMarkerProps(trophyAnchor)
	applyInvisibleMarkerProps(clipboardAnchor)

	top5Face:SetAttribute("BPW_HubLeaderboard", true)
	top5Face:SetAttribute("BPW_Rows", H.Leaderboard.Rows)
	top5Face:SetAttribute("BPW_DisplaySurface", true)
	top5Face:SetAttribute("BPW_GuiFace", top5GuiFace.Name)
	top5Face:SetAttribute("BPW_ArchScreen", 2)
	rulesFace:SetAttribute("BPW_GuiFace", rulesGuiFace.Name)
	trophyAnchor:SetAttribute("BPW_GuiFace", trophyGuiFace.Name)
	clipboardAnchor:SetAttribute("BPW_GuiFace", clipboardGuiFace.Name)
	topBoard = top5Face

	local top5Gui = ensureNamedSurfaceGui(top5Face, "Top5SurfaceGui", top5GuiFace)
	top5Gui.Name = "Top5SurfaceGui"

	local rulesGui = ensureNamedSurfaceGui(rulesFace, "RulesSurfaceGui", rulesGuiFace)
	buildRulesContent(rulesGui)

	ensureEmojiSurfaceGui(trophyAnchor, "TrophySurfaceGui", "🏆", trophyGuiFace)
	ensureEmojiSurfaceGui(clipboardAnchor, "ClipboardSurfaceGui", "📋", clipboardGuiFace)

	-- Vérification anti-déplacement.
	assert((top5Face.CFrame.Position - top5CF.Position).Magnitude < 1e-6, "Top5Face CFrame modifié")
	assert((top5Face.Size - top5Size).Magnitude < 1e-6, "Top5Face Size modifié")
	assert((rulesFace.CFrame.Position - rulesCF.Position).Magnitude < 1e-6, "RulesFace CFrame modifié")
	assert((rulesFace.Size - rulesSize).Magnitude < 1e-6, "RulesFace Size modifié")
	assert((trophyAnchor.CFrame.Position - trophyCF.Position).Magnitude < 1e-6, "TrophyAnchor CFrame modifié")
	assert((trophyAnchor.Size - trophySize).Magnitude < 1e-6, "TrophyAnchor Size modifié")
	assert((clipboardAnchor.CFrame.Position - clipCF.Position).Magnitude < 1e-6, "ClipboardAnchor CFrame modifié")
	assert((clipboardAnchor.Size - clipSize).Magnitude < 1e-6, "ClipboardAnchor Size modifié")

	print("[HubDisplays] Top5Face gui face:", top5GuiFace.Name)
	print("[HubDisplays] RulesFace gui face:", rulesGuiFace.Name)
	print("[HubDisplays] TrophyAnchor gui face:", trophyGuiFace.Name)
	print("[HubDisplays] ClipboardAnchor gui face:", clipboardGuiFace.Name)
	print("[HubDisplays] Bound Top5/Rules/Trophy/Clipboard SurfaceGui")
end

local function buildFullHubSellValueBoard(_parent: Folder)
	-- FullHub : panneau Bag value world-space retiré (valeur conservée dans HUD / données).
	sellValueBoard = nil
end

--------------------------------------------------------------------
-- Structure : fondation, deck, liseré, garde-corps
--------------------------------------------------------------------
local function buildFoundation(parent: Folder)
	local size, center = HubLayout.GetFoundation()
	makePart({
		Name = "HubFoundation",
		Size = size,
		CFrame = CFrame.new(center),
		Color = C.FoundationDeep,
		Material = Enum.Material.Slate,
		Parent = parent,
	})
	-- Ceinture lumineuse au ras du sol : ancre visuellement l'île dans les bulles.
	makePart({
		Name = "HubFoundationGlow",
		Size = Vector3.new(size.X + 3, 0.6, size.Z + 3),
		CFrame = CFrame.new(center.X, center.Y + size.Y / 2 - 0.3, center.Z),
		Color = C.Trim,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
end

local function buildSlabs(parent: Folder, slabs: { any }, color: Color3, material: Enum.Material)
	for _, slab in ipairs(slabs) do
		local cf = CFrame.new(slab.Center) * CFrame.Angles(0, math.rad(slab.YawDegrees), 0)
		if slab.IsWedge then
			-- Roll +90° : le prisme devient une plaque horizontale, angle droit sur le coin.
			makeWedge({
				Name = slab.Name,
				Size = slab.Size,
				CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
				Color = color,
				Material = material,
				Parent = parent,
			})
		else
			makePart({
				Name = slab.Name,
				Size = slab.Size,
				CFrame = cf,
				Color = color,
				Material = material,
				Parent = parent,
			})
		end
	end
end

local function buildDeck(parent: Folder)
	buildSlabs(parent, HubLayout.GetPlinthSlabs(), C.Foundation, Enum.Material.SmoothPlastic)
	buildSlabs(parent, HubLayout.GetDeckSlabs(), C.Deck, Enum.Material.SmoothPlastic)

	-- Incrustation centrale : cercle sombre sous le médaillon de spawn, comme la maquette.
	makeDisc({
		Name = "DeckInlay",
		Diameter = H.Spawn.PadDiameter + 12,
		Height = 0.12,
		Center = HubLayout.Spawn.Center + Vector3.new(0, 0.06, 0),
		Color = C.DeckInlay,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})
end

local function buildDeckRim(parent: Folder)
	-- Liseré néon exactement sur le périmètre (mêmes segments que le garde-corps).
	local segments = HubLayout.GetPerimeterSegments(0.5, H.RailingThickness + 0.5, H.DeckTopY + 0.15)
	for _, seg in ipairs(segments) do
		makePart({
			Name = seg.Name .. "Trim",
			Size = seg.Size,
			CFrame = CFrame.new(seg.Center) * CFrame.Angles(0, math.rad(seg.YawDegrees), 0),
			Color = C.Trim,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
	end
end

local function buildRailings(parent: Folder)
	for _, rail in ipairs(HubLayout.GetRailings()) do
		local cf = CFrame.new(rail.Center) * CFrame.Angles(0, math.rad(rail.YawDegrees), 0)
		makePart({
			Name = rail.Name,
			Size = rail.Size,
			CFrame = cf,
			Color = C.Foundation,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
		-- Main courante néon : lecture du contour à distance.
		makePart({
			Name = rail.Name .. "Cap",
			Size = Vector3.new(rail.Size.X + 0.3, 0.35, rail.Size.Z + 0.3),
			CFrame = cf * CFrame.new(0, rail.Size.Y / 2 + 0.15, 0),
			Color = C.Trim,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
	end
end

--------------------------------------------------------------------
-- Descente frontale vers les bulles
--------------------------------------------------------------------
local function buildStairs(parent: Folder)
	for _, step in ipairs(HubLayout.GetStairSteps()) do
		makePart({
			Name = "HubStep" .. tostring(step.Index),
			Size = step.Size,
			CFrame = CFrame.new(step.Center),
			Color = if step.Index % 2 == 0 then C.DeckInlay else C.Deck,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
		-- Nez de marche lumineux : chaque marche reste visible en descente.
		makePart({
			Name = "HubStepNose" .. tostring(step.Index),
			Size = Vector3.new(step.Size.X, 0.25, 0.5),
			CFrame = CFrame.new(step.Center.X, step.TopY + 0.1, step.Center.Z + step.Size.Z / 2 - 0.25),
			Color = C.Trim,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
		for _, sign in ipairs({ -1, 1 }) do
			makePart({
				Name = ("HubStepRail%d%s"):format(step.Index, if sign < 0 then "L" else "R"),
				Size = Vector3.new(0.9, 2.6, step.Size.Z),
				CFrame = CFrame.new(
					step.Center.X + sign * (step.Size.X / 2 - 0.45),
					step.TopY + 1.3,
					step.Center.Z
				),
				Color = C.Foundation,
				Material = Enum.Material.SmoothPlastic,
				Parent = parent,
			})
		end
	end

	local landingSize, landingCenter = HubLayout.GetLanding()
	makePart({
		Name = "HubStairsLanding",
		Size = landingSize,
		CFrame = CFrame.new(landingCenter),
		Color = C.Deck,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

--------------------------------------------------------------------
-- Spawn : médaillon central + SpawnLocation
--------------------------------------------------------------------
local function buildSpawnMedallion(parent: Folder)
	local center = HubLayout.Spawn.Center
	local padTop = center.Y + H.Spawn.PadHeight

	makeDisc({
		Name = "HubSpawnPad",
		Diameter = H.Spawn.PadDiameter,
		Height = H.Spawn.PadHeight,
		Center = center + Vector3.new(0, H.Spawn.PadHeight / 2, 0),
		Color = C.White,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		Parent = parent,
	})
	makeDisc({
		Name = "HubSpawnRing",
		Diameter = H.Spawn.PadDiameter + 1.6,
		Height = 0.22,
		Center = center + Vector3.new(0, 0.11, 0),
		Color = C.Trim,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		Parent = parent,
	})

	-- Étoile de spawn : 4 barres croisées (motif de la maquette).
	for i = 0, 3 do
		makePart({
			Name = "HubSpawnStar" .. tostring(i + 1),
			Size = Vector3.new(H.Spawn.PadDiameter * 0.62, 0.1, 1.5),
			CFrame = CFrame.new(center.X, padTop + 0.05, center.Z)
				* CFrame.Angles(0, math.rad(i * 45), 0),
			Color = C.Panel,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
	end
	makeDisc({
		Name = "HubSpawnCore",
		Diameter = 3.2,
		Height = 0.16,
		Center = Vector3.new(center.X, padTop + 0.08, center.Z),
		Color = C.Trim,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		CanCollide = false,
		Parent = parent,
	})

	-- Plaque SPAWN côté bulles (visible en remontant l'escalier).
	local plaque = makePart({
		Name = "HubSpawnPlaque",
		Size = Vector3.new(14, 0.1, 3.2),
		CFrame = CFrame.new(center.X, H.DeckTopY + 0.08, center.Z + H.Spawn.PadDiameter / 2 + 2),
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
	local gui = newSurface(plaque, Enum.NormalId.Top, 30)
	newLabel(gui, {
		Text = L10n.HubSpawnLabel,
		Size = UDim2.fromScale(1, 0.85),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = C.White,
		Stroke = C.PanelDeep,
	})
end

local function ensureSpawn(functional: Folder)
	local marker = functional:FindFirstChild("HubSpawnMarker")
	if not (marker and marker:IsA("BasePart")) then
		if marker then
			marker:Destroy()
		end
		marker = makePart({
			Name = "HubSpawnMarker",
			Size = Vector3.new(4, 1, 4),
			CFrame = HubLayout.GetSpawnCFrame(),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = functional,
		})
	else
		(marker :: BasePart).CFrame = HubLayout.GetSpawnCFrame()
	end
	spawnMarker = marker :: BasePart

	local loc = functional:FindFirstChild("HubSpawnLocation")
	if not (loc and loc:IsA("SpawnLocation")) then
		if loc then
			loc:Destroy()
		end
		local fresh = Instance.new("SpawnLocation")
		fresh.Name = "HubSpawnLocation"
		fresh.Parent = functional
		loc = fresh
	end
	local sl = loc :: SpawnLocation
	sl.Anchored = true
	sl.CanCollide = false
	sl.CanQuery = false
	sl.CanTouch = false
	sl.CastShadow = false
	sl.Transparency = 1
	sl.Material = Enum.Material.SmoothPlastic
	sl.Size = Vector3.new(12, 1, 12)
	sl.Neutral = true
	sl.Duration = 0
	sl.AllowTeamChangeOnTouch = false
	sl.Enabled = true
	sl.CFrame = HubLayout.GetSpawnCFrame()
	sl:SetAttribute("GeneratedByCode", true)
	local function stripSpawnVisuals(root: Instance)
		for _, child in ipairs(root:GetDescendants()) do
			if child:IsA("Decal")
				or child:IsA("Texture")
				or child:IsA("SurfaceGui")
				or child:IsA("BillboardGui")
				or child:IsA("SelectionBox")
			then
				child:Destroy()
			end
		end
	end
	stripSpawnVisuals(sl)
	if sl:GetAttribute("BPW_SpawnVisualHidden") ~= true then
		pcall(function()
			sl.ChildAdded:Connect(function(child)
				if child:IsA("Decal")
					or child:IsA("Texture")
					or child:IsA("SurfaceGui")
					or child:IsA("BillboardGui")
					or child:IsA("SelectionBox")
				then
					task.defer(function()
						if child.Parent then
							child:Destroy()
						end
					end)
				end
			end)
		end)
		sl:SetAttribute("BPW_SpawnVisualHidden", true)
	end
	spawnLocation = sl
	sanitizeAllSpawnLocations(sl)
end

--------------------------------------------------------------------
-- Panneau principal POP → SELL → UPGRADE
--------------------------------------------------------------------
local function buildLoopPanel(parent: Folder)
	local L = HubLayout.LoopPanel
	local cf = HubLayout.YawCFrame(L.Center, L.YawDegrees)

	makePart({
		Name = "HubLoopPlinth",
		Size = Vector3.new(L.Size.X + 1.6, L.PlinthHeight, L.Size.Z + 2.4),
		CFrame = CFrame.new(L.Center.X, H.DeckTopY + L.PlinthHeight / 2, L.Center.Z),
		Color = C.Foundation,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local panel = makePart({
		Name = "HubLoopPanel",
		Size = L.Size,
		CFrame = cf,
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	makePart({
		Name = "HubLoopPanelGlow",
		Size = Vector3.new(L.Size.X + 1.2, L.Size.Y + 1.2, L.Size.Z - 0.3),
		CFrame = cf,
		Color = C.Loop,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})

	-- Face lisible depuis le spawn : yaw 180 → la façade est la face Front locale.
	local gui = newSurface(panel, Enum.NormalId.Front, 26)
	local inner = panelBackdrop(gui, C.Loop)

	local steps = {
		{ Text = L10n.HubLoopPop, Color = C.Loop },
		{ Text = L10n.HubLoopSell, Color = C.Sell },
		{ Text = L10n.HubLoopUpgrade, Color = C.Violet },
	}
	-- 3 blocs + 2 flèches sur une ligne : 5 colonnes régulières.
	local slotW = 0.26
	local arrowW = 0.09
	for i, step in ipairs(steps) do
		local x = 0.5 + (i - 2) * (slotW + arrowW)
		newLabel(inner, {
			Text = step.Text,
			Size = UDim2.fromScale(slotW, 0.62),
			Position = UDim2.fromScale(x, 0.5),
			Color = step.Color,
			Stroke = C.PanelDeep,
		})
		if i < #steps then
			newLabel(inner, {
				Text = L10n.HubLoopArrow,
				Size = UDim2.fromScale(arrowW, 0.5),
				Position = UDim2.fromScale(x + (slotW + arrowW) / 2, 0.5),
				Color = C.White,
				Dynamic = true,
			})
		end
	end
end

--------------------------------------------------------------------
-- Panneaux arrière : TOP 3 (gauche) et RULES (droite)
--------------------------------------------------------------------
local function buildBoardShell(parent: Folder, name: string, spec: any, accent: Color3): BasePart
	local cf = HubLayout.YawCFrame(spec.Center, spec.YawDegrees)
	local board = makePart({
		Name = name,
		Size = spec.Size,
		CFrame = cf,
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	makePart({
		Name = name .. "Frame",
		Size = Vector3.new(spec.Size.X + 1.4, spec.Size.Y + 1.4, spec.Size.Z - 0.25),
		CFrame = cf,
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
	-- Pieds : le panneau ne flotte jamais au-dessus du deck.
	for _, sign in ipairs({ -1, 1 }) do
		local height = spec.BottomY - H.DeckTopY
		makePart({
			Name = name .. (if sign < 0 then "LegL" else "LegR"),
			Size = Vector3.new(1.6, height, 1.6),
			CFrame = CFrame.new(
				spec.Center.X + sign * (spec.Size.X / 2 - 1.6),
				H.DeckTopY + height / 2,
				spec.Center.Z
			),
			Color = C.Foundation,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
	return board
end

local function disableBoardShadows(board: BasePart)
	-- Gros panneaux arrière : pas d’ombre portée sur le plateau (lisibilité / clarté hub).
	board.CastShadow = false
	local parent = board.Parent
	if not parent then
		return
	end
	for _, sibling in ipairs(parent:GetChildren()) do
		if sibling:IsA("BasePart") and string.find(sibling.Name, board.Name, 1, true) == 1 then
			sibling.CastShadow = false
		end
	end
end

local function buildTopBoard(parent: Folder)
	local board = buildBoardShell(parent, "GlobalLeaderboardBoard", HubLayout.TopBoard, C.Gold)
	-- LeaderboardService remplit la face avant (mêmes noms que le panneau lobby).
	board:SetAttribute("BPW_HubLeaderboard", true)
	board:SetAttribute("BPW_Rows", H.Leaderboard.Rows)
	disableBoardShadows(board)
	-- Legs / frame nommés GlobalLeaderboardBoard*
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("BasePart") and string.sub(child.Name, 1, #"GlobalLeaderboardBoard") == "GlobalLeaderboardBoard" then
			child.CastShadow = false
		end
	end
	topBoard = board
end

local function buildRulesBoard(parent: Folder)
	local board = buildBoardShell(parent, "HubRulesBoard", HubLayout.RulesBoard, C.Amber)
	disableBoardShadows(board)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("BasePart") and string.sub(child.Name, 1, #"HubRulesBoard") == "HubRulesBoard" then
			child.CastShadow = false
		end
	end
	local gui = newSurface(board, Enum.NormalId.Front, 22)
	local inner = panelBackdrop(gui, C.Amber)

	newLabel(inner, {
		Text = L10n.HubRulesTitle,
		Size = UDim2.fromScale(0.9, 0.16),
		Position = UDim2.fromScale(0.5, 0.12),
		Color = C.Amber,
		Stroke = C.PanelDeep,
	})

	local rules = { L10n.HubRule1, L10n.HubRule2, L10n.HubRule3 }
	for i, text in ipairs(rules) do
		local row = newFrame(
			inner,
			UDim2.fromScale(0.88, 0.17),
			UDim2.fromScale(0.5, 0.32 + (i - 1) * 0.2),
			C.PanelDeep,
			10
		)
		newLabel(row, {
			Text = tostring(i),
			Size = UDim2.fromScale(0.12, 0.7),
			Position = UDim2.fromScale(0.09, 0.5),
			Color = C.Amber,
			Dynamic = true,
		})
		newLabel(row, {
			Text = text,
			Size = UDim2.fromScale(0.78, 0.62),
			Position = UDim2.fromScale(0.56, 0.5),
			Color = C.White,
			Font = Enum.Font.GothamBold,
			Align = Enum.TextXAlignment.Left,
		})
	end

	newLabel(inner, {
		Text = L10n.HubRulesFooter,
		Size = UDim2.fromScale(0.7, 0.11),
		Position = UDim2.fromScale(0.5, 0.9),
		Color = C.Sell,
		Font = Enum.Font.GothamBold,
	})
end

--------------------------------------------------------------------
-- Plateformes latérales
--------------------------------------------------------------------
local function buildSidePlatform(parent: Folder, name: string, spec: any, accent: Color3)
	makePart({
		Name = name,
		Size = spec.Size,
		CFrame = CFrame.new(spec.Center),
		Color = C.Deck,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	makePart({
		Name = name .. "Trim",
		Size = Vector3.new(spec.Size.X + 0.8, 0.3, spec.Size.Z + 0.8),
		CFrame = CFrame.new(spec.Center.X, spec.TopY - 0.15, spec.Center.Z),
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
end

--------------------------------------------------------------------
-- SELL : stand compact, vente automatique conservée
--------------------------------------------------------------------
-- Architecture du stand SELL (dosseret, canopy, poteaux) : déjà fournie par le mesh
-- Tripo importé en mode FullHubComposite — n'est appelée que dans la branche FALLBACK
-- (aucun mesh importé), jamais par-dessus HubDeckShell_New.
local function buildSellShell(parent: Folder)
	local S = H.Sell
	local base = HubLayout.GetSellBaseCFrame()

	makePart({
		Name = "HubSellBackWall",
		Size = Vector3.new(17, 9, 1.2),
		CFrame = localCF(base, Vector3.new(0, 4.5, -8)),
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	makePart({
		Name = "HubSellCanopy",
		Size = S.CanopySize,
		CFrame = localCF(base, Vector3.new(0, 9.6, -4.5)),
		Color = C.Panel,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	makePart({
		Name = "HubSellCanopyEdge",
		Size = Vector3.new(S.CanopySize.X + 0.6, 0.4, S.CanopySize.Z + 0.6),
		CFrame = localCF(base, Vector3.new(0, 9.05, -4.5)),
		Color = C.Sell,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
	for _, sign in ipairs({ -1, 1 }) do
		makePart({
			Name = "HubSellPost" .. (if sign < 0 then "L" else "R"),
			Size = Vector3.new(1.3, 9.1, 1.3),
			CFrame = localCF(base, Vector3.new(sign * 7.9, 4.55, -1)),
			Color = C.FoundationDeep,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end

	-- Enseigne SELL (face tournée vers le centre du hub = +Z local).
	local signPart = makePart({
		Name = "HubSellSign",
		Size = S.SignSize,
		CFrame = localCF(base, Vector3.new(0, 11.8, -4.5)),
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local signGui = newSurface(signPart, Enum.NormalId.Back, 26)
	local signInner = panelBackdrop(signGui, C.Sell)
	newLabel(signInner, {
		Text = L10n.HubLoopSell,
		Size = UDim2.fromScale(0.9, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = C.Sell,
		Stroke = C.PanelDeep,
	})

	-- Panneau valeur du sac (alias HUD : SellValueBoard). Prototype seulement : en
	-- FullHub la valeur est affichée dans le HUD (voir buildFullHubSellValueBoard).
	local valueBoard = makePart({
		Name = "SellValueBoard",
		Size = S.ValueBoardSize,
		CFrame = localCF(base, Vector3.new(0, 5.8, -7.2)),
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})
	local valueGui = newSurface(valueBoard, Enum.NormalId.Back, 40)
	valueGui.Name = "SellValueGui"
	local valueInner = panelBackdrop(valueGui, C.Sell)
	newLabel(valueInner, {
		Text = L10n.BagValue,
		Size = UDim2.fromScale(0.9, 0.26),
		Position = UDim2.fromScale(0.5, 0.24),
		Color = C.White,
		Font = Enum.Font.GothamBold,
	})
	local amount = newLabel(valueInner, {
		Text = "0",
		Size = UDim2.fromScale(0.86, 0.44),
		Position = UDim2.fromScale(0.5, 0.6),
		Color = C.Gold,
		Dynamic = true,
	})
	amount.Name = "Label"
	sellValueBoard = valueBoard
end

-- Détail de comptoir SELL (bacs, pièces, bulle en verre) : Parts natives nettes,
-- posées par-dessus le comptoir baked du mesh Tripo (texture IA basse densité de
-- texel = flou en gros plan). Appelée à la fois par le prototype FALLBACK et par
-- la branche FullHubComposite. Les marges de recouvrement (+15% taille, +0.05 Y)
-- sont réglées à l'œil pour ce mesh — un futur export Tripo avec une niche de
-- comptoir de profondeur différente pourra nécessiter un réajustement manuel.
local function buildSellCounterDetail(parent: Folder)
	local S = H.Sell
	local base = HubLayout.GetSellBaseCFrame()
	local overlapScale = 1.15
	local liftY = 0.05

	makePart({
		Name = "HubSellCounter",
		Size = S.CounterSize * Vector3.new(overlapScale, 1, overlapScale),
		CFrame = localCF(base, Vector3.new(0, S.CounterSize.Y / 2 + liftY, -3)),
		Color = C.Panel,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	makePart({
		Name = "HubSellCounterTop",
		Size = Vector3.new(S.CounterSize.X + 1, 0.5, S.CounterSize.Z + 1) * Vector3.new(overlapScale, 1, overlapScale),
		CFrame = localCF(base, Vector3.new(0, S.CounterSize.Y + 0.25 + liftY, -3)),
		Color = C.Sell,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		Parent = parent,
	})

	-- Accents money : piles de pièces (lecture immédiate de la fonction).
	for i, offset in ipairs({
		Vector3.new(-5.2, 0, -2.4),
		Vector3.new(-3.6, 0, -3.6),
		Vector3.new(5.2, 0, -2.4),
	}) do
		for layer = 1, 3 do
			makeDisc({
				Name = ("HubSellCoin%d_%d"):format(i, layer),
				Diameter = 2,
				Height = 0.34,
				Center = localCF(
					base,
					Vector3.new(offset.X, S.CounterSize.Y + 0.5 + liftY + (layer - 0.5) * 0.34, offset.Z)
				).Position,
				Color = C.Gold,
				Material = Enum.Material.Neon,
				Transparency = 0.1,
				CanCollide = false,
				Parent = parent,
			})
		end
	end
	makePart({
		Name = "HubSellBubbleTank",
		Size = Vector3.new(3.4, 4.6, 3.4),
		CFrame = localCF(base, Vector3.new(0, S.CounterSize.Y + 2.8, -6)),
		Color = C.Trim,
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		Reflectance = 0.15,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
end

local function buildSellStand(parent: Folder)
	buildSellShell(parent)
	buildSellCounterDetail(parent)
end

local function buildHubSellZone(functional: Folder, sellTopY: number)
	for _, name in ipairs({ "HubSellZone", "SellZone" }) do
		local old = functional:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local zoneSize = H.Sell.ZoneSize
	local base = HubLayout.GetSellBaseCFrame()
	local flat = base * CFrame.new(H.Sell.ZoneLocalOffset.X, 0, H.Sell.ZoneLocalOffset.Z)
	local centerY = sellTopY + zoneSize.Y / 2
	local zone = makePart({
		Name = "HubSellZone",
		Size = zoneSize,
		CFrame = CFrame.new(flat.Position.X, centerY, flat.Position.Z),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = functional,
	})
	zone.CanTouch = true
	zone.CastShadow = false
	zone:SetAttribute("GeneratedByCode", true)
	zone:SetAttribute("HubInteraction", "Sell")
	for _, child in ipairs(zone:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
	sellZone = zone
	logSurfaceFix("HubSellZone:", fullPath(zone), "pos", tostring(zone.Position))
	return zone
end

local function buildHubShopPrompt(functional: Folder, shopTopY: number)
	for _, name in ipairs({ "HubShopPrompt", "HubShopPromptAnchor" }) do
		local old = functional:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local base = HubLayout.GetShopBaseCFrame()
	-- Devant le comptoir violet, à portée normale.
	local localPos = Vector3.new(0, 3.2, 5.5)
	local flat = base * CFrame.new(localPos.X, 0, localPos.Z)
	local anchor = makePart({
		Name = "HubShopPrompt",
		Size = Vector3.new(4, 5, 2),
		CFrame = CFrame.new(flat.Position.X, shopTopY + localPos.Y, flat.Position.Z)
			* CFrame.Angles(0, math.rad(H.Shop.YawDegrees), 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = functional,
	})
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor:SetAttribute("GeneratedByCode", true)
	anchor:SetAttribute("HubInteraction", "Shop")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BrowsePrompt"
	prompt.ActionText = L10n.OpenShop or "Open Shop"
	prompt.ObjectText = L10n.ShopSign or "SHOP"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = H.Shop.PromptMaxDistance or 13
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	-- Boutique complète : ouverture sur SKILLS ; onglets UI pour Items / Cosmetics.
	prompt:SetAttribute("BPW_ShopCategory", "Skills")
	prompt:SetAttribute("BPW_OpenFullShop", true)
	prompt.Parent = anchor
	print("[HubGameplayFix] HubShopPrompt:", fullPath(anchor), "category=Skills fullShop=true")
	return anchor
end

local function applyDebugInteractionZones(functional: Folder)
	if H.DebugInteractionZones ~= true then
		return
	end
	local specs = {
		{ Name = "HubSellZone", Color = Color3.fromRGB(90, 230, 140), Label = "SELL" },
		{ Name = "HubShopPrompt", Color = Color3.fromRGB(180, 90, 230), Label = "SHOP" },
	}
	for _, spec in ipairs(specs) do
		local part = functional:FindFirstChild(spec.Name, true)
		if not part then
			local hub = functional.Parent
			part = hub and hub:FindFirstChild(spec.Name, true)
		end
		if part and part:IsA("BasePart") then
			part.Transparency = 0.55
			part.Color = spec.Color
			part.Material = Enum.Material.Neon
			print(("[HubInteractionDebug] %s path=%s pos=%s size=%s"):format(
				spec.Label,
				fullPath(part),
				tostring(part.Position),
				tostring(part.Size)
			))
		end
	end
end

local function buildSellFunctional(parent: Folder, structure: Folder)
	local S = H.Sell
	local base = HubLayout.GetSellBaseCFrame()

	-- Pad visuel prototype seulement (FullHub : mesh déjà en place).
	if not fullHubActive then
		makePart({
			Name = "HubSellPad",
			Size = S.PadSize,
			CFrame = localCF(base, S.PadLocalOffset),
			Color = C.Sell,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			CanCollide = false,
			CanQuery = false,
			Parent = structure,
		})
		makePart({
			Name = "HubSellPadRing",
			Size = Vector3.new(S.PadSize.X + 0.8, 0.3, S.PadSize.Z + 0.8),
			CFrame = localCF(base, S.PadLocalOffset + Vector3.new(0, -0.1, 0)),
			Color = C.Sell,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
			Parent = structure,
		})
		-- Trigger de vente automatique (ZoneService.watchAutoSell).
		local zone = parent:FindFirstChild("SellZone") or parent:FindFirstChild("HubSellZone")
		if not (zone and zone:IsA("BasePart")) then
			if zone then
				zone:Destroy()
			end
			zone = makePart({
				Name = "SellZone",
				Size = S.ZoneSize,
				CFrame = HubLayout.GetSellZoneCFrame(),
				Transparency = 1,
				CanCollide = false,
				CanQuery = true,
				Parent = parent,
			})
		else
			local z = zone :: BasePart
			z.Name = "SellZone"
			z.Size = S.ZoneSize
			z.CFrame = HubLayout.GetSellZoneCFrame()
			z.Transparency = 1
			z.CanCollide = false
		end
		for _, child in ipairs((zone :: Instance):GetChildren()) do
			if child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end
		sellZone = zone :: BasePart
	end
end

--------------------------------------------------------------------
-- SHOP : stand ouvert (jamais un bâtiment où l'on entre)
--------------------------------------------------------------------
-- Architecture du stand SHOP (murs, canopy, enseigne) : déjà fournie par le mesh
-- Tripo importé en mode FullHubComposite — n'est appelée que dans la branche FALLBACK,
-- jamais par-dessus HubDeckShell_New.
local function buildShopShell(parent: Folder)
	local S = H.Shop
	local base = HubLayout.GetShopBaseCFrame()
	local halfW, halfD = S.Width / 2, S.Depth / 2
	local t = S.WallThickness

	makePart({
		Name = "HubShopBackWall",
		Size = Vector3.new(S.Width, S.WallHeight, t),
		CFrame = localCF(base, Vector3.new(0, S.WallHeight / 2, -halfD + t / 2)),
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	for _, sign in ipairs({ -1, 1 }) do
		makePart({
			Name = "HubShopSideWall" .. (if sign < 0 then "L" else "R"),
			Size = Vector3.new(t, S.WallHeight, S.SideWallDepth),
			CFrame = localCF(
				base,
				Vector3.new(sign * (halfW - t / 2), S.WallHeight / 2, -halfD + S.SideWallDepth / 2)
			),
			Color = C.Panel,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end

	-- Auvent : couvre le fond du stand, laisse l'avant totalement ouvert.
	makePart({
		Name = "HubShopCanopy",
		Size = Vector3.new(S.Width + 2, 1.1, S.Depth - 4),
		CFrame = localCF(base, Vector3.new(0, S.WallHeight + 0.55, -halfD + (S.Depth - 4) / 2)),
		Color = C.Panel,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	makePart({
		Name = "HubShopCanopyEdge",
		Size = Vector3.new(S.Width + 2.6, 0.42, S.Depth - 3.4),
		CFrame = localCF(base, Vector3.new(0, S.WallHeight - 0.1, -halfD + (S.Depth - 4) / 2)),
		Color = C.Shop,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})

	-- Enseigne SHOP au-dessus de l'auvent, face au centre du hub (+Z local).
	local signPart = makePart({
		Name = "HubShopSign",
		Size = S.SignSize,
		CFrame = localCF(base, Vector3.new(0, S.WallHeight + 3.2, -halfD + (S.Depth - 4) / 2)),
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local gui = newSurface(signPart, Enum.NormalId.Back, 26)
	local inner = panelBackdrop(gui, C.Shop)
	newLabel(inner, {
		Text = L10n.ShopSign,
		Size = UDim2.fromScale(0.9, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = C.Shop,
		Stroke = C.PanelDeep,
	})
end

-- Détail de comptoir SHOP (comptoirs + articles en étagère) : Parts natives nettes,
-- posées par-dessus le comptoir baked du mesh Tripo. Mêmes marges de recouvrement
-- que buildSellCounterDetail, réglées à l'œil pour ce mesh.
local function buildShopCounterDetail(parent: Folder)
	local S = H.Shop
	local base = HubLayout.GetShopBaseCFrame()
	local halfD = S.Depth / 2
	local overlapScale = 1.15
	local liftY = 0.05

	-- Comptoir en deux tronçons : une entrée centrale de 6 studs reste franche.
	local counterRun = (S.Width - 6) / 2
	for _, sign in ipairs({ -1, 1 }) do
		makePart({
			Name = "HubShopCounter" .. (if sign < 0 then "L" else "R"),
			Size = Vector3.new(counterRun, S.CounterHeight, 2.4) * Vector3.new(1, 1, overlapScale),
			CFrame = localCF(
				base,
				Vector3.new(sign * (3 + counterRun / 2), S.CounterHeight / 2 + liftY, halfD - 3)
			),
			Color = C.Panel,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
		makePart({
			Name = "HubShopCounterTop" .. (if sign < 0 then "L" else "R"),
			Size = Vector3.new(counterRun + 0.6, 0.45, 3) * Vector3.new(1, 1, overlapScale),
			CFrame = localCF(
				base,
				Vector3.new(sign * (3 + counterRun / 2), S.CounterHeight + 0.22 + liftY, halfD - 3)
			),
			Color = C.Shop,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			Parent = parent,
		})
	end

	-- Étagères de présentation adossées au fond (lecture « boutique » immédiate).
	for row = 1, 2 do
		makePart({
			Name = "HubShopShelf" .. tostring(row),
			Size = Vector3.new(S.Width - 4, 0.4, 2.2),
			CFrame = localCF(base, Vector3.new(0, 2.4 + (row - 1) * 2.8, -halfD + 1.9)),
			Color = C.Foundation,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
		for slot = -2, 2 do
			makePart({
				Name = ("HubShopGoods%d_%d"):format(row, slot + 3),
				Size = Vector3.new(1.5, 1.5, 1.5),
				CFrame = localCF(
					base,
					Vector3.new(slot * 3.4, 3.15 + (row - 1) * 2.8, -halfD + 1.9)
				),
				Color = if (slot + row) % 2 == 0 then C.Shop else C.Violet,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				CanCollide = false,
				CanQuery = false,
				Parent = parent,
			})
		end
	end
end

local function buildShopStand(parent: Folder)
	buildShopShell(parent)
	buildShopCounterDetail(parent)
end

--------------------------------------------------------------------
-- Bubble Transit : socle discret à l'arrière-droit
--------------------------------------------------------------------
local function buildTransitAlcove(parent: Folder)
	local center = HubLayout.GetTransitAlcoveCenter()
	makeDisc({
		Name = "HubTransitAlcove",
		Diameter = H.Transit.AlcoveDiameter,
		Height = H.Transit.AlcoveHeight,
		Center = center,
		Color = C.Foundation,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		Parent = parent,
	})
	makeDisc({
		Name = "HubTransitRing",
		Diameter = H.Transit.AlcoveDiameter + 1.2,
		Height = 0.2,
		Center = Vector3.new(center.X, H.DeckTopY + 0.1, center.Z),
		Color = C.Violet,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
		Parent = parent,
	})
end

--------------------------------------------------------------------
-- Anchors d'import : cible exacte de chaque module visuel
--------------------------------------------------------------------
local ASSET_KEY_BY_MODULE: { [string]: string } = {
	Deck = "Deck",
	SpawnMedallion = "SpawnMedallion",
	LoopPanel = "LoopPanel",
	SellStand = "SellStand",
	ShopStand = "ShopStand",
	TopBoard = "TopBoard",
	RulesBoard = "RulesBoard",
	TransitAlcove = "TransitAlcove",
	Stairs = "Stairs",
}

local function buildAnchors(parent: Folder)
	for _, spec in ipairs(HubLayout.GetModules()) do
		local anchor = makePart({
			Name = "Anchor_" .. spec.Name,
			Size = Vector3.new(1, 1, 1),
			CFrame = HubLayout.YawCFrame(spec.Center, spec.YawDegrees),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
		anchor:SetAttribute("TargetSize", spec.Size)
		anchor:SetAttribute("YawDegrees", spec.YawDegrees)
		anchor:SetAttribute("Kind", spec.Kind)
		anchor:SetAttribute("Circular", spec.Circular)
		local assetKey = ASSET_KEY_BY_MODULE[spec.Name]
		if assetKey then
			anchor:SetAttribute("AssetKey", assetKey)
			anchor:SetAttribute("AssetModelName", HubLayout.GetAssetModelName(assetKey))
			anchor:SetAttribute("UsingImported", not shouldBuild(assetKey))
		end
	end
end

--------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------
function CentralHubBuilder.IsEnabled(): boolean
	return H.Enabled == true
end

function CentralHubBuilder.Build(worldRoot: Instance): Folder
	local root = ensureFolder(worldRoot, ROOT_NAME)
	local structure = ensureFolder(root, STRUCTURE)
	local functional = ensureFolder(root, FUNCTION)
	local anchors = ensureFolder(root, ANCHORS)

	-- Structure et anchors sont intégralement générés : reconstruction franche.
	structure:ClearAllChildren()
	anchors:ClearAllChildren()

	local deckDecision = decideDeckImport()
	deckImportActive = deckDecision.Status == "imported" and fullHubActive
	deckIsComposite = fullHubActive

	if fullHubActive then
		-- Ordre : visuel → pas de prototype → purge collisions → sols finaux →
		-- purge Transit → trigger portail → spawns → fonctions dynamiques.
		mountFullHubSource()
		auditNearbyColliders(HubLayout.Center, 60)
		clearAllCollisionProxyFolders(functional)
		local _proxies, heights = buildFinalHubCollisionProxies(functional)
		buildHubLightingRig(functional)
		disableLegacyHubColliders(root, structure)
		purgeLegacyBubbleTransit()
		buildHubSellZone(functional, heights.SellTopY)
		buildHubShopPrompt(functional, heights.ShopTopY)
		ensureSpawn(functional)
		destroyLegacyBoardParts(root)
		buildFullHubSellValueBoard(structure)
		buildSellFunctional(functional, structure)
		-- Comptoirs nets par-dessus le mesh Tripo (texture IA basse densité de texel =
		-- flou en gros plan sur SELL/SHOP). Coque (murs/canopy/enseigne) volontairement
		-- pas reconstruite ici : le mesh la fournit déjà correctement vue de loin.
		buildSellCounterDetail(structure)
		if not H.Shop.UseStudioVisual then
			buildShopCounterDetail(structure)
		end
		buildAnchors(anchors)
		destroyLegacyBoardParts(root)
		buildHubArchIntegratedPanels(functional, heights.MainTopY)
		-- Après HubDisplays (Top5Face/RulesFace) : ancrage côté intérieur de l'arche bleue.
		buildBubbleTransitTrigger(functional, heights.MainTopY)
		disablePrototypeColliders(structure)
		softenStandCollisions(structure)
		applyDebugInteractionZones(functional)
		auditHubColliders(root)
	else
		logCompositeDebug(
			"12) FALLBACK prototype activé — génération Parts blanches/cyan",
			("reason=%s"):format(tostring(deckDecision.Status))
		)
		clearCompositeProxies(functional)
		buildFoundation(structure)
		buildDeck(structure)
		buildRailings(structure)
		if shouldBuild("DeckRim") then
			buildDeckRim(structure)
		end
		if shouldBuild("Stairs") then
			buildStairs(structure)
		end
		if shouldBuild("SpawnMedallion") then
			buildSpawnMedallion(structure)
		end
		if shouldBuild("LoopPanel") then
			buildLoopPanel(structure)
		end
		buildSidePlatform(structure, "HubSellPlatform", HubLayout.SellPlatform, C.Sell)
		buildSidePlatform(structure, "HubShopPlatform", HubLayout.ShopPlatform, C.Shop)
		if shouldBuild("SellStand") then
			buildSellStand(structure)
		end
		if shouldBuild("ShopStand") and not H.Shop.UseStudioVisual then
			buildShopStand(structure)
		end
		-- TOP 3 / RULES physiques : uniquement hors FullHub (et jamais si import actif).
		if shouldBuild("TopBoard") then
			buildTopBoard(structure)
		end
		if shouldBuild("RulesBoard") then
			buildRulesBoard(structure)
		end
		if shouldBuild("TransitAlcove") then
			buildTransitAlcove(structure)
		end
		-- Portail Bubble Transit également en fallback prototype (même repère HubLayout).
		purgeLegacyBubbleTransit()
		buildBubbleTransitTrigger(functional, H.DeckTopY)
		ensureSpawn(functional)
		buildSellFunctional(functional, structure)
		buildAnchors(anchors)
		applyDebugInteractionZones(functional)
	end

	return root
end

--------------------------------------------------------------------
-- Placement autoritatif sur MainHubFloor (unique pour spawn / retours)
--------------------------------------------------------------------
function CentralHubBuilder.GetMainHubFloor(): BasePart?
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild(ROOT_NAME)
	local functional = hub and hub:FindFirstChild(FUNCTION)
	local proxies = functional and functional:FindFirstChild(HUB_COLLISION_PROXIES)
	local floor = proxies and proxies:FindFirstChild("MainHubFloor")
	if floor and floor:IsA("BasePart") then
		return floor
	end
	return nil
end

function CentralHubBuilder.ComputeHubFloorRootY(humanoid: Humanoid, root: BasePart, floor: BasePart): number
	local floorTopY = floor.Position.Y + floor.Size.Y / 2
	return floorTopY + humanoid.HipHeight + root.Size.Y / 2 + 0.05
end

function CentralHubBuilder.PlaceCharacterOnHubFloor(
	character: Model,
	yawDegrees: number?,
	reason: string?
): boolean
	local floor = CentralHubBuilder.GetMainHubFloor()
	if not floor then
		warn("[HubSpawnFix] MainHubFloor introuvable — placement annulé")
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5) :: any
	end
	local rootInst = character:FindFirstChild("HumanoidRootPart")
	if not rootInst then
		rootInst = character:WaitForChild("HumanoidRootPart", 5)
	end
	if not (humanoid and humanoid:IsA("Humanoid") and rootInst and rootInst:IsA("BasePart")) then
		warn("[HubSpawnFix] Humanoid/HRP manquant — placement annulé")
		return false
	end
	local root = rootInst :: BasePart
	local yaw = if yawDegrees ~= nil then yawDegrees else 180
	local floorTopY = floor.Position.Y + floor.Size.Y / 2
	local finalRootY = CentralHubBuilder.ComputeHubFloorRootY(humanoid, root, floor)

	print("[HubSurfaceFix] Placement reason:", tostring(reason or "unspecified"))
	print("[HubSurfaceFix] FloorTopY:", floorTopY)
	print("[HubSurfaceFix] HipHeight:", humanoid.HipHeight)
	print("[HubSurfaceFix] FinalRootY:", finalRootY)

	root.CFrame = CFrame.new(floor.Position.X, finalRootY, floor.Position.Z)
		* CFrame.Angles(0, math.rad(yaw), 0)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

--------------------------------------------------------------------
-- SpawnLocation précoce (avant tout yield de EnsureWorld)
--------------------------------------------------------------------
function CentralHubBuilder.EnsureEarlySpawnLocation(worldRoot: Instance): BasePart
	local root = ensureFolder(worldRoot, ROOT_NAME)
	local functional = ensureFolder(root, FUNCTION)
	ensureSpawn(functional)
	return spawnLocation :: BasePart
end

--------------------------------------------------------------------
-- Accès
--------------------------------------------------------------------
function CentralHubBuilder.GetSpawnMarker(): BasePart?
	return spawnMarker
end

function CentralHubBuilder.GetSpawnLocation(): SpawnLocation?
	return spawnLocation
end

function CentralHubBuilder.GetSellZone(): BasePart?
	return sellZone
end

function CentralHubBuilder.GetLeaderboardBoard(): BasePart?
	return topBoard
end

function CentralHubBuilder.GetSellValueBoard(): BasePart?
	return sellValueBoard
end

return CentralHubBuilder
