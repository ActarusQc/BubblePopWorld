--!strict
-- ItemShop fonctionnel — approche Studio-first.
--
-- L'apparence de la boutique vit dans Workspace.StudioDecoration.ItemShopVisual,
-- construite et modifiée à la main dans Studio. Ce builder ne génère JAMAIS de
-- décoration : uniquement les repères fonctionnels invisibles de Workspace.ItemShop
-- (prompts, CameraPoint_*, Display_*), plus une coque de secours minimale quand
-- le modèle visuel est absent.
--
-- Layout (Yaw 90°, local +Z = entrée vers le spawn) :
--   Fond (-Z) = Items | Gauche (-X) = Skills | Droite (+X) = Cosmetics

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local HubLayout = require(Shared.HubLayout)
local L10n = require(Shared.LocalizationStrings)
-- Le décor reste protégé. Seule exception : Shell.EnsureVisualModelPivot()
-- déplace le modèle entier lorsque le pivot de configuration change.
local Shell = require(Shared.ItemShopVisualShell)

local MODEL_NAME = "ItemShop"
local LEGACY_MODEL_NAME = "BubbleShop"
local WORLD_NAME = "BubblePopWorld"

local COLORS = {
	Cyan = Color3.fromRGB(42, 202, 232),
	Amber = Color3.fromRGB(245, 180, 42),
	Violet = Color3.fromRGB(184, 76, 232),
	White = Color3.fromRGB(245, 250, 255),
	Fallback = Color3.fromRGB(96, 100, 106),
}

type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Parent: Instance,
	Transparency: number?,
	CanCollide: boolean?,
	Shape: Enum.PartType?,
}

type CategoryId = "Skills" | "Items" | "Cosmetics"

type CategorySpec = {
	Id: CategoryId,
	PromptBrowseKey: string,
	ObjectTextKey: string,
	Accent: Color3,
	-- Centre du mur de la catégorie, en local (rempli au build).
	WallCenter: Vector3,
	-- Normale sortant du mur vers l'intérieur de la salle.
	Inward: Vector3,
}

local CATEGORIES: { CategorySpec } = {
	{
		Id = "Skills",
		PromptBrowseKey = "BrowseSkills",
		ObjectTextKey = "Skills",
		Accent = COLORS.Cyan,
		WallCenter = Vector3.new(0, 0, 0),
		Inward = Vector3.new(1, 0, 0),
	},
	{
		Id = "Items",
		PromptBrowseKey = "BrowseItems",
		ObjectTextKey = "Items",
		Accent = COLORS.Amber,
		WallCenter = Vector3.new(0, 0, 0),
		Inward = Vector3.new(0, 0, 1),
	},
	{
		Id = "Cosmetics",
		PromptBrowseKey = "BrowseCosmetics",
		ObjectTextKey = "Cosmetics",
		Accent = COLORS.Violet,
		WallCenter = Vector3.new(0, 0, 0),
		Inward = Vector3.new(-1, 0, 0),
	},
}

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------

local function makePart(props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.Name
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color
	part.Material = props.Material
	part.Transparency = props.Transparency or 0
	part.Shape = props.Shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = if props.CanCollide ~= nil then props.CanCollide else true
	part.CanTouch = false
	part.CanQuery = part.CanCollide
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.Parent
	return part
end

local function makeModel(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function localCF(base: CFrame, position: Vector3, rotation: CFrame?): CFrame
	local result = base * CFrame.new(position)
	if rotation then
		result *= rotation
	end
	return result
end

local function l10nText(key: string): string
	local value = (L10n :: any)[key]
	if type(value) == "string" then
		return value
	end
	return key
end

local function rotationFacingInward(inward: Vector3): CFrame
	if inward.X > 0.5 then
		return CFrame.Angles(0, -math.pi / 2, 0)
	elseif inward.X < -0.5 then
		return CFrame.Angles(0, math.pi / 2, 0)
	elseif inward.Z > 0.5 then
		return CFrame.identity
	end
	return CFrame.Angles(0, math.pi, 0)
end

local function resolveParent(): Instance
	return Workspace
end

-- StudioDecoration et tous ses descendants sont intouchables par le code.
local function isProtected(instance: Instance): boolean
	return Shell.IsProtectedInstance(instance)
end

local function destroyExisting(parent: Instance)
	local containers = { Workspace, parent }
	local world = Workspace:FindFirstChild(WORLD_NAME)
	if world then
		table.insert(containers, world)
		local lobby = world:FindFirstChild("Lobby")
		if lobby then
			table.insert(containers, lobby)
		end
	end
	for _, container in ipairs(containers) do
		if not isProtected(container) then
			for _, child in ipairs(container:GetChildren()) do
				local matches = child.Name == MODEL_NAME or child.Name == LEGACY_MODEL_NAME
				if matches and not isProtected(child) then
					child:Destroy()
				end
			end
		end
	end
end

--------------------------------------------------------------------
-- Repères fonctionnels (invisibles en Play)
--------------------------------------------------------------------

-- Position des trois murs : seule référence partagée entre prompts, caméras,
-- présentoirs fonctionnels et décor Studio.
local function computeWallCenters(width: number, depth: number, thickness: number)
	local halfW, halfD = width / 2, depth / 2
	for _, spec in ipairs(CATEGORIES) do
		if spec.Id == "Skills" then
			spec.WallCenter = Vector3.new(-halfW + thickness / 2, 0, 0)
		elseif spec.Id == "Items" then
			spec.WallCenter = Vector3.new(0, 0, -halfD + thickness / 2)
		else
			spec.WallCenter = Vector3.new(halfW - thickness / 2, 0, 0)
		end
	end
end

local function standCenterFor(spec: CategorySpec): Vector3
	return spec.WallCenter + spec.Inward * (if spec.Id == "Items" then 4.6 else 4.1)
end

local function createPivotAnchor(model: Model, baseCF: CFrame): Part
	return makePart({
		Name = "PivotAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = baseCF,
		Color = COLORS.White,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 1,
		Parent = model,
	})
end

local function createEntranceMarker(model: Model, baseCF: CFrame, depth: number, doorWidth: number): Part
	return makePart({
		Name = "Entrance",
		Size = Vector3.new(doorWidth, 0.08, 0.5),
		CFrame = localCF(baseCF, Vector3.new(0, 1.05, depth / 2)),
		Color = COLORS.Cyan,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 1,
		Parent = model,
	})
end

local function createPromptAnchor(
	model: Model,
	baseCF: CFrame,
	spec: CategorySpec,
	promptMaxDistance: number
): Part
	local anchor = makePart({
		Name = "PromptAnchor_" .. spec.Id,
		Size = Vector3.new(4, 5, 2),
		CFrame = localCF(
			baseCF,
			spec.WallCenter + spec.Inward * 2.2 + Vector3.new(0, 3.5, 0),
			rotationFacingInward(spec.Inward)
		),
		Color = spec.Accent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 1,
		Parent = model,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BrowsePrompt"
	prompt.ActionText = l10nText(spec.PromptBrowseKey)
	prompt.ObjectText = l10nText(spec.ObjectTextKey)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = promptMaxDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("BPW_ShopCategory", spec.Id)
	prompt.Parent = anchor

	return anchor
end

-- Cadrages validés en mobile portrait et PC 16:9 : ne pas modifier ces valeurs.
local function createCameraPoint(model: Model, baseCF: CFrame, spec: CategorySpec): Part
	local standCenter = standCenterFor(spec)
	local distance = if spec.Id == "Items" then 10 else 8.8
	local height = if spec.Id == "Items" then 5.7 else 5.4
	local position = standCenter + spec.Inward * distance + Vector3.new(0, height, 0)
	local worldPosition = baseCF:PointToWorldSpace(position)
	local worldTarget = baseCF:PointToWorldSpace(standCenter + Vector3.new(0, 3.3, 0))
	return makePart({
		Name = "CameraPoint_" .. spec.Id,
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = CFrame.lookAt(worldPosition, worldTarget),
		Color = COLORS.White,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 1,
		Parent = model,
	})
end

-- Display_* se réduit à sa cible de cadrage : ShopUI ne lit que PrimaryPart.Position.
local function createFunctionalDisplay(model: Model, baseCF: CFrame, spec: CategorySpec): Model
	local display = makeModel(model, "Display_" .. spec.Id)
	local standCenter = standCenterFor(spec)
	local anchor = makePart({
		Name = "FocusAnchor",
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = localCF(
			baseCF,
			Vector3.new(standCenter.X, 1.35, standCenter.Z),
			rotationFacingInward(spec.Inward)
		),
		Color = spec.Accent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 1,
		Parent = display,
	})
	display.PrimaryPart = anchor
	return display
end

--------------------------------------------------------------------
-- Coque de secours (uniquement si ItemShopVisual est absent)
--------------------------------------------------------------------

local MATERIALS: { [string]: Enum.Material } = {
	Slate = Enum.Material.Slate,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Neon = Enum.Material.Neon,
	Glass = Enum.Material.Glass,
}

local function addSignLabel(host: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Back -- +Z local : côté parvis
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = host

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -8, 1, -8)
	label.Position = UDim2.new(0, 4, 0, 4)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = COLORS.White
	label.Text = text
	label.Parent = gui
end

-- Plancher, murs, plafond, entrée ouverte, panneau SHOP. Rien de plus :
-- ce n'est qu'un filet de sécurité pour garder la boutique jouable.
local function createFallbackShell(model: Model, baseCF: CFrame)
	local shell = makeModel(model, "FallbackShell")
	for _, spec in ipairs(Shell.GetFallbackSpec()) do
		local part = makePart({
			Name = spec.Name,
			Size = spec.Size,
			CFrame = localCF(baseCF, spec.Offset),
			Color = COLORS.Fallback,
			Material = MATERIALS[spec.Material] or Enum.Material.SmoothPlastic,
			CanCollide = spec.CanCollide,
			Parent = shell,
		})
		if spec.Name == "SignBoard" then
			addSignLabel(part, Shell.GetSignText())
		end
	end
end

--------------------------------------------------------------------
-- Apparence de guide (mode Edit uniquement)
--------------------------------------------------------------------

local GUIDE_COLORS: { [string]: Color3 } = {
	Skills = COLORS.Cyan,
	Items = COLORS.Amber,
	Cosmetics = COLORS.Violet,
}

-- Rend les repères visibles et sélectionnables dans Studio.
-- En Play, Build() les recrée entièrement invisibles.
local function applyGuideAppearance(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local color = COLORS.White
			local ownName = descendant.Name
			local parentName = if descendant.Parent then descendant.Parent.Name else ""
			for id, accent in pairs(GUIDE_COLORS) do
				if string.find(ownName, id, 1, true) or string.find(parentName, id, 1, true) then
					color = accent
				end
			end
			descendant.Color = color
			descendant.Material = Enum.Material.Neon
			descendant.Transparency = 0.6
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

--------------------------------------------------------------------
-- Validation d'emprise (avertissements seulement)
--------------------------------------------------------------------

type Bounds2D = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

local function boundsFromLocalRect(baseCF: CFrame, minX: number, maxX: number, minZ: number, maxZ: number): Bounds2D
	local minWorldX, maxWorldX = math.huge, -math.huge
	local minWorldZ, maxWorldZ = math.huge, -math.huge
	for _, x in ipairs({ minX, maxX }) do
		for _, z in ipairs({ minZ, maxZ }) do
			local point = baseCF:PointToWorldSpace(Vector3.new(x, 0, z))
			minWorldX = math.min(minWorldX, point.X)
			maxWorldX = math.max(maxWorldX, point.X)
			minWorldZ = math.min(minWorldZ, point.Z)
			maxWorldZ = math.max(maxWorldZ, point.Z)
		end
	end
	return { MinX = minWorldX, MaxX = maxWorldX, MinZ = minWorldZ, MaxZ = maxWorldZ }
end

local function boundsDistance(a: Bounds2D, b: Bounds2D): number
	local gapX = math.max(b.MinX - a.MaxX, a.MinX - b.MaxX, 0)
	local gapZ = math.max(b.MinZ - a.MaxZ, a.MinZ - b.MaxZ, 0)
	return math.sqrt(gapX * gapX + gapZ * gapZ)
end

local function validateLayout(baseCF: CFrame, shopConfig: typeof(Config.Lobby.ItemShop))
	local width = shopConfig.Width
	local depth = shopConfig.Depth
	local side = shopConfig.ExteriorSideOverhang
	local forecourt = shopConfig.ForecourtDepth
	local envelope = boundsFromLocalRect(
		baseCF,
		-width / 2 - side,
		width / 2 + side,
		-depth / 2 - 0.5,
		depth / 2 + forecourt
	)

	local booth = Config.Lobby.SellBooth
	local boothOrigin = Config.Lobby.RootOffset + booth.OriginOffset
	local boothCF = CFrame.new(boothOrigin) * CFrame.Angles(0, math.rad(booth.YawDegrees), 0)
	-- Emprise réelle du kiosque : estrade au sol, plus large que l'auvent.
	local plaza = booth.PlazaSize
	local plazaOffset = booth.PlazaLocalOffset
	local sellBounds = boundsFromLocalRect(
		boothCF,
		plazaOffset.X - plaza.X / 2,
		plazaOffset.X + plaza.X / 2,
		plazaOffset.Z - plaza.Z / 2,
		plazaOffset.Z + plaza.Z / 2
	)
	local sellGap = boundsDistance(envelope, sellBounds)
	if sellGap < shopConfig.MinSellBoothClearance then
		warn(string.format(
			"[ItemShopBuilder] AVERTISSEMENT EMPRISE : seulement %.2f studs entre ItemShop et SellBooth (minimum %.2f). Génération maintenue.",
			sellGap,
			shopConfig.MinSellBoothClearance
		))
	end

	local entrancePos = Config.Lobby.EntrancePosition
	local entranceSize = Config.Lobby.EntranceSize
	local entranceBounds = {
		MinX = entrancePos.X - entranceSize.X / 2,
		MaxX = entrancePos.X + entranceSize.X / 2,
		MinZ = entrancePos.Z - entranceSize.Z / 2,
		MaxZ = entrancePos.Z + entranceSize.Z / 2,
	}
	if boundsDistance(envelope, entranceBounds) <= 0 then
		warn("[ItemShopBuilder] AVERTISSEMENT EMPRISE : le parvis chevauche GameEntrance. Génération maintenue.")
	end

	local forecourtBounds = boundsFromLocalRect(
		baseCF,
		-width / 2,
		width / 2,
		depth / 2,
		depth / 2 + forecourt
	)
	local approachHalfWidth = 8
	local approachBounds = {
		MinX = -approachHalfWidth,
		MaxX = approachHalfWidth,
		MinZ = entrancePos.Z - 4,
		MaxZ = Config.GameRoom.ExitPosition.Z,
	}
	if boundsDistance(forecourtBounds, approachBounds) <= 0 then
		warn("[ItemShopBuilder] AVERTISSEMENT EMPRISE : le parvis chevauche le chemin du lobby. Génération maintenue.")
	end

	local floorCenter = Config.Lobby.FloorCenter
	local floorSize = Config.Lobby.FloorSize
	local floorBounds = {
		MinX = floorCenter.X - floorSize.X / 2,
		MaxX = floorCenter.X + floorSize.X / 2,
		MinZ = floorCenter.Z - floorSize.Z / 2,
		MaxZ = floorCenter.Z + floorSize.Z / 2,
	}
	if envelope.MinX < floorBounds.MinX or envelope.MaxX > floorBounds.MaxX
		or envelope.MinZ < floorBounds.MinZ or envelope.MaxZ > floorBounds.MaxZ then
		warn("[ItemShopBuilder] AVERTISSEMENT EMPRISE : ItemShop dépasse le plancher du lobby. Génération maintenue.")
	end

	print(string.format(
		"[ItemShopBuilder] bounds X[%.2f, %.2f] Z[%.2f, %.2f] | passage central %.2f | GameEntrance %.2f | chemin %.2f studs",
		envelope.MinX,
		envelope.MaxX,
		envelope.MinZ,
		envelope.MaxZ,
		sellGap,
		boundsDistance(forecourtBounds, entranceBounds),
		boundsDistance(forecourtBounds, approachBounds)
	))
end

--------------------------------------------------------------------
-- Build
--------------------------------------------------------------------

local ItemShopBuilder = {}

-- Le hub central porte son propre stand ouvert : la boutique n'est plus un bâtiment
-- du lobby mais un kiosque posé sur la plateforme droite du hub.
local function useHubAnchor(): boolean
	return Config.Hub.Enabled == true and Config.Hub.ReplacesLobby == true
end

-- guideMode = true : construction Studio (Edit) des seuls repères, rendus visibles.
local function buildShopModel(position: Vector3?, guideMode: boolean): Model
	local parent = resolveParent()
	destroyExisting(parent)

	local hubMode = position == nil and useHubAnchor()
	local shopConfig = Config.Lobby.ItemShop
	local origin: Vector3
	local baseCF: CFrame
	if hubMode then
		origin = HubLayout.GetShopOrigin()
		baseCF = HubLayout.GetShopBaseCFrame()
	else
		origin = position or Config.Lobby.ItemShopPosition
		baseCF = CFrame.new(origin) * CFrame.Angles(0, math.rad(shopConfig.YawDegrees), 0)
	end

	if position == nil and not hubMode then
		Shell.EnsureVisualModelPivot()
	end

	local hubShop = Config.Hub.Shop
	local width = if hubMode then hubShop.Width else (shopConfig.Width or 32)
	local depth = if hubMode then hubShop.Depth else (shopConfig.Depth or 26)
	local doorWidth = if hubMode then 6 else (shopConfig.DoorWidth or 13)
	local thickness = if hubMode then hubShop.WallThickness else (shopConfig.WallThickness or 1)

	local mode
	if guideMode then
		mode = "FunctionalOnly"
	elseif hubMode then
		-- La coque du kiosque vient de CentralHubBuilder (ou d'un asset importé) :
		-- aucun bâtiment de secours ne doit apparaître sur le hub.
		mode = if hubShop.UseStudioVisual then "StudioVisual" else "FunctionalOnly"
	else
		mode = Shell.ResolveEffectiveMode(shopConfig.UseStudioVisual, Shell.IsVisualPresent())
	end
	if not guideMode and not hubMode and Shell.IsLegacyDecorRequested(shopConfig.UseStudioVisual) then
		warn(
			"[ItemShopBuilder] UseStudioVisual=false mais la décoration procédurale a été retirée. "
				.. "Comportement Studio-first appliqué."
		)
	end

	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	if not hubMode then
		validateLayout(baseCF, shopConfig)
	end
	computeWallCenters(width, depth, thickness)

	local promptDistance = if hubMode
		then hubShop.PromptMaxDistance
		else (shopConfig.PromptMaxDistance or 13)

	local pivotAnchor = createPivotAnchor(model, baseCF)
	createEntranceMarker(model, baseCF, depth, doorWidth)
	for _, spec in ipairs(CATEGORIES) do
		createFunctionalDisplay(model, baseCF, spec)
		createCameraPoint(model, baseCF, spec)
		-- Hub FullHub : un seul HubShopPrompt dans CentralHubBuilder (aile violette).
		if not hubMode then
			createPromptAnchor(model, baseCF, spec, promptDistance)
		end
	end

	if Shell.ShouldBuildFallbackShell(mode) then
		warn(Shell.MissingVisualMessage)
		createFallbackShell(model, baseCF)
	end

	if guideMode then
		applyGuideAppearance(model)
	end

	model.PrimaryPart = pivotAnchor
	model:SetAttribute("BPW_ItemShop", true)
	model:SetAttribute("BPW_BuildMode", mode)
	model:SetAttribute("BPW_HubKiosk", hubMode)
	model.Parent = parent

	-- Filet : le hub ne doit jamais exposer l'ancien bâtiment walk-in.
	if hubMode then
		local strayShell = model:FindFirstChild("FallbackShell")
		if strayShell then
			strayShell:Destroy()
		end
		local leftover = Shell.ListStrayShopVisualPaths()
		if #leftover > 0 then
			warn(("[ItemShopBuilder] Hub : ItemShopVisual encore visible (%s) — park ZoneService incomplet.")
				:format(table.concat(leftover, ", ")))
		end
	end

	print(string.format(
		"[ItemShopBuilder] mode=%s anchor=%s origin=%s parts=%d (aucune décoration générée)",
		mode,
		if hubMode then "CentralHub" else "Lobby",
		tostring(origin),
		#model:GetDescendants()
	))

	return model
end

function ItemShopBuilder.Build(position: Vector3?): Model
	return buildShopModel(position, false)
end

-- Bouton Studio « Align ItemShop Functional Guides ».
-- Reconstruit Workspace.ItemShop seul ; ne lit ni n'écrit jamais ItemShopVisual.
function ItemShopBuilder.BuildGuides(): Model?
	if RunService:IsRunning() then
		warn("[ItemShopBuilder] Align ItemShop Functional Guides : mode Edit uniquement (pas en Play).")
		return nil
	end
	local model = buildShopModel(nil, true)
	print("[ItemShopBuilder] Guides fonctionnels réalignés (décor visuel intact).")
	return model
end

function ItemShopBuilder.Start()
	ItemShopBuilder.Build()
end

return ItemShopBuilder
