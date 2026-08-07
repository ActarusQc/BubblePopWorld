--!strict
-- Contrat d'import des assets du hub central « Concept 2 ».
--
-- Rôle : décrire de façon autoritative ce qu'un asset importé doit être (nom, hiérarchie,
-- attributs, pivot, orientation, taille, surfaces GUI, matériaux, budgets) et refuser tout
-- modèle non conforme SANS jamais casser le hub : en cas de refus, la géométrie prototype
-- (`PrototypeVisualFallback`) reste en place et un seul avertissement est émis.
--
-- Ce module est volontairement PUR :
--   * aucune dépendance à GameConfig / HubLayout : les cotes ci-dessous sont les cotes
--     APPROUVÉES pour les assets, pas les cotes actuelles du prototype. L'alignement des
--     ancres et des configurations est fait en Phase 8 du plan
--     (docs/superpowers/plans/2026-08-01-central-hub-concept2-asset-pack.md) ;
--   * aucun service Roblox appelé au chargement ;
--   * aucune écriture dans le monde : `Validate` et `Decide` sont en lecture seule.
--
-- Sources : docs/superpowers/specs/2026-08-01-central-hub-concept2-asset-pack-design.md
--           docs/superpowers/specs/renders/transform-validation.txt
--
-- Câblé par CentralHubBuilder pour le Deck (variante Composite Tripo incluse).

local HubAssetContract = {}

--------------------------------------------------------------------
-- Constantes de pipeline
--------------------------------------------------------------------
HubAssetContract.StudioDecorationRoot = "StudioDecoration"
HubAssetContract.VisualFolder = "CentralHubVisual"
HubAssetContract.ValidationCamerasFolder = "ValidationCameras"

-- Dossier runtime reconstruit à chaque démarrage : aucun asset ne doit y vivre.
HubAssetContract.RuntimeHubFolder = "CentralHub"

-- Attributs obligatoires sur le Model importé.
HubAssetContract.Attributes = {
	Marker = "BPW_HubAsset",
	Key = "BPW_HubAssetKey",
	Version = "BPW_AssetVersion",
	AuthoredSize = "BPW_AuthoredSize",
	AuthoredYaw = "BPW_AuthoredYaw",
	-- Optionnel : renseigné par le modeleur, contrôlé s'il est présent.
	TriangleCount = "BPW_TriangleCount",
	-- Variante d'authoring : "Composite" = mesh Tripo fusionné (Deck uniquement).
	Variant = "BPW_HubAssetVariant",
}

HubAssetContract.CompositeVariant = "Composite"

-- Marquage de la géométrie générée par le code (appliqué en P8.3).
HubAssetContract.PrototypeAttribute = "BPW_PrototypeVisualFallback"

-- Tolérances de validation.
HubAssetContract.Tolerance = {
	Size = 0.5, -- par axe, en studs
	Pivot = 0.25, -- distance à l'ancre, en studs
	Yaw = 1.0, -- en degrés
	FaceSize = 0.25, -- par axe des plans *Face
	FaceThickness = 0.2, -- épaisseur maximale d'un plan *Face
}

-- Budget mobile-first approuvé (plan, section « Budget mobile-first réparti »).
HubAssetContract.Budget = {
	TotalTriangles = 55000,
	MaxTrianglesPerMesh = 10000,
	MaxRealLights = 10,
	MaxTextureResolution = 1024,
}

-- Classes interdites dans un asset : le gameplay reste au code.
HubAssetContract.ForbiddenClasses = {
	"Script",
	"LocalScript",
	"ModuleScript",
	"SurfaceGui",
	"BillboardGui",
	"ProximityPrompt",
	"ClickDetector",
	"Humanoid",
}

-- Matériaux autorisés (noms d'Enum.Material). Le reste est refusé : la palette graphite
-- interdit explicitement Plastic / SmoothPlastic sur les grands volumes.
HubAssetContract.AllowedMaterials = {
	Metal = true,
	Concrete = true,
	Slate = true,
	Granite = true,
	Marble = true,
	Wood = true,
	WoodPlanks = true,
	Neon = true,
	Glass = true,
	ForceField = true,
	Fabric = true,
	SmoothPlastic = true, -- toléré uniquement sur les plans *Face et les petits props
}

--------------------------------------------------------------------
-- Types
--------------------------------------------------------------------
export type FaceSpec = {
	Name: string,
	Width: number,
	Height: number,
	Center: Vector3,
	Normal: Vector3,
}

export type ModuleSpec = {
	Key: string,
	ModelName: string,
	LegacyModelName: string?,
	Priority: number,
	Format: string,
	TargetSize: Vector3,
	Center: Vector3,
	YawDegrees: number,
	Pivot: Vector3,
	Circular: boolean,
	RequiredChildren: { string },
	RequiredFaces: { FaceSpec },
	MaxTriangles: number,
	RealLights: number,
	CastShadow: boolean,
	CollidableChildren: { string },
	Notes: string,
}

export type Issue = {
	Code: string,
	Message: string,
}

export type Result = {
	Key: string,
	ModelName: string,
	Valid: boolean,
	Issues: { Issue },
}

export type Decision = {
	Key: string,
	Status: string, -- "imported" | "missing" | "disabled" | "invalid"
	BuildPrototype: boolean,
	Message: string?,
	Result: Result?,
}

--------------------------------------------------------------------
-- Modules
--
-- Center / Pivot / TargetSize : cotes APPROUVÉES (spec §3, plan « Transformations monde »).
-- LegacyModelName : nom encore présent dans GameConfig.Hub.Assets, renommé en P8.1.
--------------------------------------------------------------------
local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Deck composite Tripo : la source Studio est le visuel runtime (pas de clone).
-- RuntimeYawDegrees : correction Y unique (ouverture / panneaux).
HubAssetContract.CompositeDeck = {
	TargetSize = v3(84, 14, 60),
	BottomY = 4.5,
	YawDegrees = 0,
	RuntimeYawDegrees = 180,
	RuntimeYawAttribute = "BPW_CompositeRuntimeYaw",
	RequiredChild = "Visual",
	RequiredChildClass = "MeshPart",
	MaxTriangles = 200000,
}

export type CompositeVisualSnapshot = {
	Parent: Instance?,
	CFrame: CFrame,
	Size: Vector3,
	PivotOffset: CFrame,
	Transparency: number,
	TextureID: string,
}

function HubAssetContract.SnapshotCompositeVisual(model: Model): CompositeVisualSnapshot?
	local visual = model:FindFirstChild("Visual")
	if not visual or not visual:IsA("MeshPart") then
		return nil
	end
	local mesh = visual :: MeshPart
	local textureId = ""
	pcall(function()
		textureId = (mesh :: any).TextureID or ""
	end)
	return {
		Parent = model.Parent,
		CFrame = mesh.CFrame,
		Size = mesh.Size,
		PivotOffset = mesh.PivotOffset,
		Transparency = mesh.Transparency,
		TextureID = textureId,
	}
end

function HubAssetContract.AssertCompositeVisualUnchanged(
	model: Model,
	before: CompositeVisualSnapshot
): (boolean, string?)
	local after = HubAssetContract.SnapshotCompositeVisual(model)
	if not after then
		return false, "Visual MeshPart manquant après build"
	end
	if after.Parent ~= before.Parent then
		return false, "Parent modifié"
	end
	if (after.CFrame.Position - before.CFrame.Position).Magnitude > 1e-6
		or math.abs(after.CFrame.LookVector:Dot(before.CFrame.LookVector) - 1) > 1e-6
		or math.abs(after.CFrame.UpVector:Dot(before.CFrame.UpVector) - 1) > 1e-6
	then
		return false, "Visual.CFrame modifié"
	end
	if (after.Size - before.Size).Magnitude > 1e-6 then
		return false, "Visual.Size modifié"
	end
	if (after.PivotOffset.Position - before.PivotOffset.Position).Magnitude > 1e-6
		or math.abs(after.PivotOffset.LookVector:Dot(before.PivotOffset.LookVector) - 1) > 1e-6
	then
		return false, "Visual.PivotOffset modifié"
	end
	if math.abs(after.Transparency - before.Transparency) > 1e-6 then
		return false, "Visual.Transparency modifié"
	end
	if after.TextureID ~= before.TextureID then
		return false, "Visual.TextureID modifié"
	end
	return true, nil
end

-- Rotation Y runtime unique (idempotente via attribut). Pas de pitch/roll.
function HubAssetContract.ApplyCompositeRuntimeYaw(model: Model): boolean
	local cd = HubAssetContract.CompositeDeck
	local attr = cd.RuntimeYawAttribute
	local target = cd.RuntimeYawDegrees
	if model:GetAttribute(attr) == target then
		return false
	end
	local ok, packed = pcall(function()
		local cf, size = model:GetBoundingBox()
		return { cf, size }
	end)
	local origin = Vector3.zero
	if ok and type(packed) == "table" and typeof(packed[1]) == "CFrame" then
		local p = (packed[1] :: CFrame).Position
		origin = Vector3.new(p.X, 0, p.Z)
	end
	local R = CFrame.new(origin) * CFrame.Angles(0, math.rad(target), 0) * CFrame.new(-origin)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			part.CFrame = R * part.CFrame
		end
	end
	model:SetAttribute(attr, target)
	return true
end

-- Props collision / ombre uniquement — jamais de transparence / taille hors yaw runtime.
function HubAssetContract.PrepareCompositeStudioSource(model: Model)
	HubAssetContract.ApplyImportedRuntimeProps(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			(descendant :: BasePart).CastShadow = false
		end
	end
end

-- Ancien HubDeckShell : masqué s’il coexiste avec HubDeckShell_New.
function HubAssetContract.HideLegacyCompositeDeck(visualFolder: Instance?, activeModel: Model)
	if not visualFolder then
		return
	end
	for _, child in ipairs(visualFolder:GetChildren()) do
		if child:IsA("Model") and child ~= activeModel then
			local name = child.Name
			if name == "HubDeckShell" or name == "HubDeck" then
				for _, descendant in ipairs(child:GetDescendants()) do
					if descendant:IsA("BasePart") then
						local part = descendant :: BasePart
						part.Transparency = 1
						part.CanCollide = false
						part.CanTouch = false
						part.CanQuery = false
						part.CastShadow = false
					end
				end
			end
		end
	end
end

-- Normales des surfaces lisibles, exprimées en MONDE (non ambiguës).
-- La convention d'authoring « -Z = face avant du module » reste à confirmer en Studio au
-- premier import (P2.12) : en cas de doute, ces normales monde font foi.
local TOWARD_SPAWN = v3(0, 0, 1) -- panneaux arrière, boucle, transit : lisibles vers +Z
local TOWARD_CENTER_FROM_LEFT = v3(1, 0, 0) -- aile SELL (-X) : lisible vers +X
local TOWARD_CENTER_FROM_RIGHT = v3(-1, 0, 0) -- aile SHOP (+X) : lisible vers -X

local MODULES: { ModuleSpec } = {
	{
		Key = "Deck",
		ModelName = "HubDeckShell_New",
		LegacyModelName = "HubDeckShell",
		Priority = 1,
		Format = "FBX",
		-- Bbox totale incluant les ailes surélevées (sommet Y=13.20).
		-- Pivot d'import distinct du centre bbox : Anchor_Deck à Y=8.25.
		TargetSize = v3(84, 8.7, 60),
		Center = v3(0, 8.85, 0),
		YawDegrees = 0,
		Pivot = v3(0, 8.25, 0),
		Circular = false,
		RequiredChildren = { "Base", "Moulding", "Wings", "NeonTrim" },
		RequiredFaces = {},
		MaxTriangles = 13000,
		RealLights = 0,
		CastShadow = true,
		CollidableChildren = {},
		Notes = "Jupe 4.50→8.20, socle 8.20→10.00, dalle 10.00→12.00, nez en surplomb 0.6. "
			.. "Ailes Sell/Shop 24×1.2×22 à Y=12.00→13.20 avec marches 2×0.6. "
			.. "Pivot (0, 8.25, 0) ≠ centre bbox (0, 8.85, 0). Ouverture frontale 28 studs libre.",
	},
	{
		Key = "SellStand",
		ModelName = "HubSellStandShell",
		LegacyModelName = "HubSellStand",
		Priority = 2,
		Format = "FBX",
		TargetSize = v3(18, 14, 22),
		Center = v3(-33, 20.2, 0),
		YawDegrees = 90,
		Pivot = v3(-30, 13.2, 0),
		Circular = false,
		RequiredChildren = { "Frame", "Interior", "Counter", "NeonTrim" },
		RequiredFaces = {
			{
				Name = "SellSignFace",
				Width = 13,
				Height = 3,
				Center = v3(-24.8, 25, 0),
				Normal = TOWARD_CENTER_FROM_LEFT,
			},
			{
				-- Panneau « valeur du sac » : fond de l'alcôve (local z = -7.2).
				Name = "SellValueFace",
				Width = 7,
				Height = 3,
				Center = v3(-37.2, 19, 0),
				Normal = TOWARD_CENTER_FROM_LEFT,
			},
		},
		MaxTriangles = 8000,
		RealLights = 2,
		CastShadow = true,
		CollidableChildren = { "Counter" },
		Notes = "Volume de vente 11 x 8 x 12 en (-23.6, 16.8, 0) totalement vide.",
	},
	{
		Key = "ShopStand",
		ModelName = "HubShopStandShell",
		LegacyModelName = "HubShopStand",
		Priority = 3,
		Format = "FBX",
		TargetSize = v3(18, 14, 22),
		Center = v3(33, 20.2, 0),
		YawDegrees = 270,
		Pivot = v3(30, 13.2, 0),
		Circular = false,
		RequiredChildren = { "Frame", "Interior", "Counter", "NeonTrim" },
		RequiredFaces = {
			{
				Name = "ShopSignFace",
				Width = 13,
				Height = 3,
				Center = v3(24.8, 25.4, 0),
				Normal = TOWARD_CENTER_FROM_RIGHT,
			},
			-- Vitrines : fond de l'alcôve (local z = -7.5), étalées sur Z.
			{
				Name = "DisplaySkillsFace",
				Width = 3.4,
				Height = 4,
				Center = v3(37.5, 17.8, -6),
				Normal = TOWARD_CENTER_FROM_RIGHT,
			},
			{
				Name = "DisplayItemsFace",
				Width = 3.4,
				Height = 4,
				Center = v3(37.5, 17.8, 0),
				Normal = TOWARD_CENTER_FROM_RIGHT,
			},
			{
				Name = "DisplayCosmeticsFace",
				Width = 3.4,
				Height = 4,
				Center = v3(37.5, 17.8, 6),
				Normal = TOWARD_CENTER_FROM_RIGHT,
			},
		},
		MaxTriangles = 8000,
		RealLights = 2,
		CastShadow = true,
		CollidableChildren = {},
		Notes = "Passage central de 6 studs libre sur toute la profondeur. Symétrie stricte "
			.. "avec HubSellStandShell.",
	},
	{
		Key = "LoopPanel",
		ModelName = "HubLoopPanelFrame",
		LegacyModelName = "HubLoopPanel",
		Priority = 4,
		Format = "FBX",
		TargetSize = v3(34, 9.5, 2),
		Center = v3(0, 18.25, -4),
		YawDegrees = 180,
		Pivot = v3(0, 13.5, -4),
		Circular = false,
		RequiredChildren = { "Frame", "NeonEdge" },
		RequiredFaces = {
			{ Name = "LoopPanelFace", Width = 30, Height = 7, Center = v3(0, 18.25, -3), Normal = TOWARD_SPAWN },
		},
		MaxTriangles = 2500,
		RealLights = 0,
		CastShadow = true,
		CollidableChildren = {},
		Notes = "Socle mouluré 36 x 1.5 x 4 (12.00 → 13.50). Aucun texte gravé ni texturé.",
	},
	{
		Key = "TopBoard",
		ModelName = "HubTop3BoardFrame",
		LegacyModelName = "HubTopBoard",
		Priority = 5,
		Format = "FBX",
		TargetSize = v3(20, 15.5, 2),
		Center = v3(-19, 28.25, -23),
		YawDegrees = 180,
		Pivot = v3(-19, 20.5, -23),
		Circular = false,
		RequiredChildren = { "Frame", "Base", "TrophyIcon" },
		RequiredFaces = {
			{ Name = "Top3Face", Width = 17, Height = 11.5, Center = v3(-19, 27.5, -22), Normal = TOWARD_SPAWN },
		},
		MaxTriangles = 2500,
		RealLights = 1,
		CastShadow = true,
		CollidableChildren = {},
		Notes = "Socle 20 x 3 x 4 plus jambes jusqu'à 12.00. Sommet arrondi (arc r=10). "
			.. "LeaderboardService cible Top3Face, repli GlobalLeaderboardBoard.",
	},
	{
		Key = "RulesBoard",
		ModelName = "HubRulesBoardFrame",
		LegacyModelName = "HubRulesBoard",
		Priority = 6,
		Format = "FBX",
		TargetSize = v3(20, 15.5, 2),
		Center = v3(19, 28.25, -23),
		YawDegrees = 180,
		Pivot = v3(19, 20.5, -23),
		Circular = false,
		RequiredChildren = { "Frame", "Base", "ClipboardIcon" },
		RequiredFaces = {
			{ Name = "RulesFace", Width = 17, Height = 11.5, Center = v3(19, 27.5, -22), Normal = TOWARD_SPAWN },
		},
		MaxTriangles = 2500,
		RealLights = 1,
		CastShadow = true,
		CollidableChildren = {},
		Notes = "Miroir du TOP 3, accent ambre. Modèle séparé : jamais fusionné avec le TOP 3.",
	},
	{
		Key = "Stairs",
		ModelName = "HubFrontStairs",
		LegacyModelName = "HubStairs",
		Priority = 7,
		Format = "FBX",
		TargetSize = v3(26, 4.65, 20.8),
		Center = v3(0, 9.675, 40.9),
		YawDegrees = 0,
		Pivot = v3(0, 12, 30.5),
		Circular = false,
		RequiredChildren = { "Steps", "Landing", "NeonNosing" },
		RequiredFaces = {},
		MaxTriangles = 4000,
		RealLights = 2,
		CastShadow = true,
		CollidableChildren = {},
		Notes = "Dessus du palier à 7.35, arête avant à 51.30 (contact exact avec la première "
			.. "bulle vivante). Dessous du palier porté par la jupe du deck.",
	},
	{
		Key = "TransitAlcove",
		ModelName = "HubTransitShell",
		LegacyModelName = "HubTransitAlcove",
		Priority = 8,
		Format = "FBX",
		TargetSize = v3(10, 11, 10),
		Center = v3(34, 17.5, -19),
		YawDegrees = 180,
		Pivot = v3(34, 12, -19),
		Circular = false,
		RequiredChildren = { "Arch", "Base", "PortalNeon", "Sign" },
		RequiredFaces = {
			{
				Name = "TransitSignFace",
				Width = 6,
				Height = 1.6,
				Center = v3(34, 21.4, -14.2),
				Normal = TOWARD_SPAWN,
			},
		},
		MaxTriangles = 3500,
		RealLights = 1,
		CastShadow = true,
		CollidableChildren = {},
		Notes = "Cylindre Ø6 x 8 en (34, 12.6, -19) laissé libre pour la pastille "
			.. "fonctionnelle, qui devient invisible. Hauteur secondaire assumée.",
	},
	{
		Key = "Railings",
		ModelName = "HubRailingsAndPosts",
		LegacyModelName = nil,
		Priority = 9,
		Format = "FBX",
		TargetSize = v3(84, 4.2, 60),
		Center = v3(0, 14.1, 0),
		YawDegrees = 0,
		Pivot = v3(0, 12, 0),
		Circular = false,
		RequiredChildren = { "Segments", "Posts", "NeonCaps" },
		RequiredFaces = {},
		MaxTriangles = 4000,
		RealLights = 0,
		CastShadow = false,
		CollidableChildren = {},
		Notes = "Ancre Anchor_Railings à créer en P8.2. Capuchons Neon sans source lumineuse. "
			.. "Ouverture frontale de 28 studs jamais fermée.",
	},
	{
		Key = "SpawnMedallion",
		ModelName = "HubSpawnMedallion",
		LegacyModelName = "HubSpawnMedallion",
		Priority = 10,
		Format = "FBX",
		TargetSize = v3(18, 0.9, 18),
		Center = v3(0, 12.45, 8),
		YawDegrees = 0,
		Pivot = v3(0, 12, 8),
		Circular = true,
		RequiredChildren = { "Ring", "Star", "NeonCore" },
		RequiredFaces = {},
		MaxTriangles = 1500,
		RealLights = 1,
		CastShadow = false,
		CollidableChildren = {},
		Notes = "Relief total ≤ 0.9 : ne doit jamais faire trébucher. Volume 12 x 5 x 12 "
			.. "au-dessus totalement libre (apparition des personnages).",
	},
	{
		Key = "LightFixtures",
		ModelName = "HubLightFixtures",
		LegacyModelName = nil,
		Priority = 11,
		Format = "OBJ",
		TargetSize = v3(84, 12, 60),
		Center = v3(0, 18, 0),
		YawDegrees = 0,
		Pivot = v3(0, 12, 0),
		Circular = false,
		RequiredChildren = {
			"PostLanterns",
			"CanopySpots",
			"BoardSpots",
			"DeckBollards",
			"MedallionGlow",
			"PortalGlow",
		},
		RequiredFaces = {},
		MaxTriangles = 1500,
		-- RealLights = 0 dans le total ValidateAll (le budget de 10 est déjà porté par
		-- Sell/Shop/panneaux/escalier/transit/médaillon). Validate autorise quand même
		-- jusqu'à Budget.MaxRealLights ici, car ce modèle les héberge physiquement.
		RealLights = 0,
		CastShadow = false,
		CollidableChildren = {},
		Notes = "Héberge physiquement les 10 vraies sources du hub (budget porté par les "
			.. "modules fonctionnels dans ValidateAll). Tout le reste est Neon ou émissif. "
			.. "Shadows = false en profil mobile.",
	},
	{
		Key = "DecorProps",
		ModelName = "HubDecorProps",
		LegacyModelName = nil,
		Priority = 12,
		Format = "OBJ",
		TargetSize = v3(84, 12, 60),
		Center = v3(0, 18, 0),
		YawDegrees = 0,
		Pivot = v3(0, 12, 0),
		Circular = false,
		RequiredChildren = {
			"SellCrates",
			"SellBills",
			"ShopGoods",
			"ShopBasket",
			"DeckPlants",
			"FloorChevrons",
		},
		RequiredFaces = {},
		MaxTriangles = 4000,
		RealLights = 0,
		CastShadow = false,
		CollidableChildren = {},
		Notes = "Un fichier OBJ par prop, pivot en base, ≤ 900 triangles chacun. Jamais un "
			.. "seul bloc de décoration. Zones interdites : volume de vente, passage Shop, "
			.. "1.5 autour de chaque PromptAnchor, volume de spawn.",
	},
}

local BY_KEY: { [string]: ModuleSpec } = {}
local BY_MODEL_NAME: { [string]: ModuleSpec } = {}
for _, spec in ipairs(MODULES) do
	BY_KEY[spec.Key] = spec
	BY_MODEL_NAME[spec.ModelName] = spec
	if spec.LegacyModelName then
		BY_MODEL_NAME[spec.LegacyModelName] = spec
	end
end

function HubAssetContract.GetModules(): { ModuleSpec }
	return MODULES
end

function HubAssetContract.GetModule(key: string): ModuleSpec?
	return BY_KEY[key]
end

function HubAssetContract.GetModuleByModelName(name: string): ModuleSpec?
	return BY_MODEL_NAME[name]
end

function HubAssetContract.GetVisualPath(): string
	return ("Workspace.%s.%s"):format(
		HubAssetContract.StudioDecorationRoot,
		HubAssetContract.VisualFolder
	)
end

function HubAssetContract.IsCompositeVariant(model: Instance?): boolean
	if not model then
		return false
	end
	return model:GetAttribute(HubAssetContract.Attributes.Variant)
		== HubAssetContract.CompositeVariant
end

function HubAssetContract.GetEffectiveTargetSize(model: Instance?, spec: ModuleSpec): Vector3
	if spec.Key == "Deck" and HubAssetContract.IsCompositeVariant(model) then
		return HubAssetContract.CompositeDeck.TargetSize
	end
	return spec.TargetSize
end

-- Yaw monde horizontal dérivé du LookVector (ignore pitch).
function HubAssetContract.FlatYawRadians(cf: CFrame): number
	local look = cf.LookVector
	local x, z = look.X, look.Z
	if x * x + z * z < 1e-8 then
		return math.atan2(-cf.RightVector.Z, cf.RightVector.X)
	end
	return math.atan2(-x, -z)
end

-- Force pitch/roll = 0 sur chaque BasePart, en conservant le yaw
-- (ex. Visual Studio tourné de 180° sur Y pour l'ouverture frontale).
-- Met à jour WorldPivot sans déplacer les Parts (pas de PivotTo ici).
function HubAssetContract.FlattenImportedOrientation(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			local yaw = HubAssetContract.FlatYawRadians(part.CFrame)
			part.CFrame = CFrame.new(part.CFrame.Position) * CFrame.Angles(0, yaw, 0)
			part.Anchored = true
		end
	end
	local ok, packed = pcall(function()
		local cf, size = model:GetBoundingBox()
		return { cf, size }
	end)
	if ok and type(packed) == "table" and typeof(packed[1]) == "CFrame" then
		local bbCF = packed[1] :: CFrame
		local yaw = HubAssetContract.FlatYawRadians(bbCF)
		pcall(function()
			model.WorldPivot = CFrame.new(bbCF.Position) * CFrame.Angles(0, yaw, 0)
		end)
	end
end

-- Pose un Model par sa bounding box réelle (pas le pivot Tripo) :
-- centre XZ = (0, 0), bas Y = bottomY, pitch/roll = 0, yaw préservé
-- (+ offset yawDegrees). Échelle uniforme vers targetSize.
function HubAssetContract.PlaceModelByBoundingBox(
	model: Model,
	targetSize: Vector3,
	bottomY: number,
	yawDegrees: number
)
	local function readBoundingBox(): (CFrame?, Vector3?)
		local ok, packed = pcall(function()
			local cf, size = model:GetBoundingBox()
			return { cf, size }
		end)
		if ok and type(packed) == "table" and typeof(packed[1]) == "CFrame" and typeof(packed[2]) == "Vector3" then
			return packed[1], packed[2]
		end
		local extentsOk, extents = pcall(function()
			return model:GetExtentsSize()
		end)
		if not extentsOk or typeof(extents) ~= "Vector3" then
			return nil, nil
		end
		local pivotOk, pivot = pcall(function()
			return model:GetPivot()
		end)
		return if pivotOk and pivot then pivot else CFrame.new(), extents
	end

	local function scaleToTarget(bbSize: Vector3)
		local sx = targetSize.X / math.max(bbSize.X, 1e-6)
		local sy = targetSize.Y / math.max(bbSize.Y, 1e-6)
		local sz = targetSize.Z / math.max(bbSize.Z, 1e-6)
		local scale = (sx * sy * sz) ^ (1 / 3)
		if math.abs(scale - 1) > 1e-4 then
			local scaleOk, currentScale = pcall(function()
				return model:GetScale()
			end)
			if scaleOk and type(currentScale) == "number" then
				pcall(function()
					model:ScaleTo(currentScale * scale)
				end)
			end
		end
	end

	-- 0) Aplatir d'abord les Parts (retire pitch/roll FBX du MeshPart Visual).
	HubAssetContract.FlattenImportedOrientation(model)

	local bbCF, bbSize = readBoundingBox()
	if not bbCF or not bbSize then
		return
	end
	scaleToTarget(bbSize)

	-- 1) Re-aplatir après scale, puis positionner.
	HubAssetContract.FlattenImportedOrientation(model)
	bbCF, bbSize = readBoundingBox()
	if not bbCF or not bbSize then
		return
	end

	local pivotOk, pivot = pcall(function()
		return model:GetPivot()
	end)
	if not pivotOk or not pivot then
		return
	end

	local preservedYaw = HubAssetContract.FlatYawRadians(bbCF)
	local desiredCenter = Vector3.new(0, bottomY + bbSize.Y * 0.5, 0)
	local finalYaw = preservedYaw + math.rad(yawDegrees or 0)
	local desiredCF = CFrame.new(desiredCenter) * CFrame.Angles(0, finalYaw, 0)
	local levelBB = CFrame.new(bbCF.Position) * CFrame.Angles(0, preservedYaw, 0)
	local placeTransform = desiredCF * levelBB:Inverse()
	pcall(function()
		model:PivotTo(placeTransform * pivot)
	end)

	-- 2) Garantie finale : aucune Part / pivot avec pitch ou roll.
	HubAssetContract.FlattenImportedOrientation(model)
	bbCF, bbSize = readBoundingBox()
	if not bbCF or not bbSize then
		return
	end
	pivotOk, pivot = pcall(function()
		return model:GetPivot()
	end)
	if not pivotOk or not pivot then
		return
	end
	desiredCenter = Vector3.new(0, bottomY + bbSize.Y * 0.5, 0)
	local delta = desiredCenter - bbCF.Position
	if delta.Magnitude > 1e-4 then
		pcall(function()
			model:PivotTo(CFrame.new(delta) * pivot)
		end)
		HubAssetContract.FlattenImportedOrientation(model)
	end
end

function HubAssetContract.ApplyImportedRuntimeProps(model: Instance)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end
	if model:IsA("BasePart") then
		local part = model :: BasePart
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end
end

-- Source StudioDecoration : jamais un sol jouable (reste en place, invisible en Play).
function HubAssetContract.NeutralizeStudioSource(model: Instance)
	HubAssetContract.ApplyImportedRuntimeProps(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			part.Transparency = 1
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
		end
	end
end

--------------------------------------------------------------------
-- Outils internes
--------------------------------------------------------------------
local function issue(list: { Issue }, code: string, message: string)
	table.insert(list, { Code = code, Message = message })
end

local function isForbidden(className: string): boolean
	for _, forbidden in ipairs(HubAssetContract.ForbiddenClasses) do
		if className == forbidden then
			return true
		end
	end
	return false
end

local function contains(list: { string }, value: string): boolean
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end
	return false
end

-- Taille attendue après application du yaw : le contrat exprime TargetSize dans le repère
-- monde, mais un module tourné de 90 ou 270 degrés échange X et Z côté bounding box locale.
function HubAssetContract.WorldExtents(size: Vector3, yawDegrees: number): Vector3
	local yaw = math.abs(yawDegrees % 180)
	if yaw > 45 and yaw < 135 then
		return Vector3.new(size.Z, size.Y, size.X)
	end
	return size
end

local function nearlyEqual(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance + 1e-9
end

-- Normale monde d'un plan : direction de son axe le plus mince.
function HubAssetContract.FaceNormalOf(part: BasePart): Vector3?
	local ok, normal = pcall(function()
		local size = part.Size
		local cf = part.CFrame
		if size.X <= size.Y and size.X <= size.Z then
			return cf.RightVector
		elseif size.Y <= size.X and size.Y <= size.Z then
			return cf.UpVector
		end
		return cf.LookVector
	end)
	if ok and typeof(normal) == "Vector3" then
		return normal
	end
	return nil
end

local function yawDelta(a: number, b: number): number
	local delta = math.abs((a - b) % 360)
	if delta > 180 then
		delta = 360 - delta
	end
	return delta
end

--------------------------------------------------------------------
-- Validation d'un Model importé
--------------------------------------------------------------------
function HubAssetContract.Validate(model: Instance?, expectedKey: string?): Result
	local spec: ModuleSpec? = nil
	if expectedKey then
		spec = BY_KEY[expectedKey]
	elseif model then
		spec = BY_MODEL_NAME[model.Name]
	end

	local issues: { Issue } = {}
	local key = if spec then spec.Key else tostring(expectedKey)
	local modelName = if spec then spec.ModelName else (if model then model.Name else "?")

	if not spec then
		issue(issues, "unknown_module",
			("aucun module du contrat ne correspond (clé=%s, nom=%s)"):format(
				tostring(expectedKey), if model then model.Name else "nil"))
		return { Key = key, ModelName = modelName, Valid = false, Issues = issues }
	end

	if not model then
		issue(issues, "missing_model", ("%s absent de %s"):format(
			spec.ModelName, HubAssetContract.GetVisualPath()))
		return { Key = key, ModelName = modelName, Valid = false, Issues = issues }
	end

	-- 1) Classe et nom exacts.
	if not model:IsA("Model") then
		issue(issues, "bad_class",
			("%s doit être un Model (trouvé %s)"):format(spec.ModelName, model.ClassName))
	end
	if model.Name ~= spec.ModelName then
		issue(issues, "bad_name",
			("nom « %s » attendu, trouvé « %s »"):format(spec.ModelName, model.Name))
	end

	-- 2) Emplacement : jamais sous le dossier runtime reconstruit à chaque démarrage.
	local ancestor: Instance? = model.Parent
	local underRuntime, underVisual = false, false
	while ancestor do
		if ancestor.Name == HubAssetContract.RuntimeHubFolder then
			underRuntime = true
		elseif ancestor.Name == HubAssetContract.VisualFolder then
			underVisual = true
		end
		ancestor = ancestor.Parent
	end
	if underRuntime then
		issue(issues, "bad_parent",
			("%s ne doit jamais vivre sous %s (dossier reconstruit à chaque démarrage)")
				:format(spec.ModelName, HubAssetContract.RuntimeHubFolder))
	end
	if model.Parent ~= nil and not underVisual then
		issue(issues, "bad_parent",
			("%s doit être placé sous %s"):format(spec.ModelName, HubAssetContract.GetVisualPath()))
	end

	-- 3) Attributs obligatoires.
	local A = HubAssetContract.Attributes
	if model:GetAttribute(A.Marker) ~= true then
		issue(issues, "missing_attribute", ("attribut %s = true manquant"):format(A.Marker))
	end
	local isComposite = HubAssetContract.IsCompositeVariant(model)
	if isComposite and spec.Key ~= "Deck" then
		issue(issues, "bad_variant",
			("variante Composite réservée à HubDeckShell (module %s)"):format(spec.Key))
	end

	local attrKey = model:GetAttribute(A.Key)
	-- Composite : clé contrat, ModelName actuel, ou LegacyModelName (HubDeckShell).
	local keyOk = attrKey == spec.Key or attrKey == spec.ModelName
		or (spec.LegacyModelName ~= nil and attrKey == spec.LegacyModelName)
	if not keyOk then
		issue(issues, "bad_attribute",
			("attribut %s attendu « %s » / « %s » / legacy, trouvé « %s »")
				:format(A.Key, spec.Key, spec.ModelName, tostring(attrKey)))
	end
	local version = model:GetAttribute(A.Version)
	if type(version) ~= "number" or version < 1 then
		issue(issues, "bad_attribute",
			("attribut %s doit être un entier ≥ 1 (trouvé %s)"):format(A.Version, tostring(version)))
	end
	local authoredSize = model:GetAttribute(A.AuthoredSize)
	if typeof(authoredSize) ~= "Vector3" then
		issue(issues, "bad_attribute",
			("attribut %s doit être un Vector3 (trouvé %s)"):format(A.AuthoredSize, typeof(authoredSize)))
	end
	local authoredYaw = model:GetAttribute(A.AuthoredYaw)
	local expectedYaw = if isComposite
		then HubAssetContract.CompositeDeck.YawDegrees
		else spec.YawDegrees
	if type(authoredYaw) ~= "number" then
		issue(issues, "bad_attribute",
			("attribut %s doit être un nombre (trouvé %s)"):format(A.AuthoredYaw, tostring(authoredYaw)))
	elseif yawDelta(authoredYaw, expectedYaw) > HubAssetContract.Tolerance.Yaw then
		issue(issues, "bad_yaw",
			("yaw %d° attendu, déclaré %s° (écart %.1f°)"):format(
				expectedYaw, tostring(authoredYaw), yawDelta(authoredYaw, expectedYaw)))
	end

	-- 4) Bounding box dans la tolérance, exprimée dans le repère monde.
	local targetSize = HubAssetContract.GetEffectiveTargetSize(model, spec)
	local expectedWorld = HubAssetContract.WorldExtents(targetSize, expectedYaw)
	if typeof(authoredSize) == "Vector3" then
		local tol = HubAssetContract.Tolerance.Size
		if not (nearlyEqual(authoredSize.X, targetSize.X, tol)
			and nearlyEqual(authoredSize.Y, targetSize.Y, tol)
			and nearlyEqual(authoredSize.Z, targetSize.Z, tol)) then
			issue(issues, "bad_attribute",
				("attribut %s = %.2f x %.2f x %.2f, attendu %.2f x %.2f x %.2f")
					:format(A.AuthoredSize, authoredSize.X, authoredSize.Y, authoredSize.Z,
						targetSize.X, targetSize.Y, targetSize.Z))
		end
	end
	local ok, extents = pcall(function()
		return model:GetExtentsSize()
	end)
	if ok and typeof(extents) == "Vector3" then
		local tol = HubAssetContract.Tolerance.Size
		if not (nearlyEqual(extents.X, expectedWorld.X, tol)
			and nearlyEqual(extents.Y, expectedWorld.Y, tol)
			and nearlyEqual(extents.Z, expectedWorld.Z, tol)) then
			issue(issues, "bad_size",
				("taille %.2f x %.2f x %.2f attendue (± %.2f), mesurée %.2f x %.2f x %.2f")
					:format(expectedWorld.X, expectedWorld.Y, expectedWorld.Z, tol,
						extents.X, extents.Y, extents.Z))
		end
	else
		issue(issues, "no_extents", ("impossible de mesurer %s"):format(spec.ModelName))
	end

	-- 5) Pivot aligné sur l'ancre (ignoré pour Composite : pivot Tripo non fiable).
	if not isComposite then
		local pivotOk, pivot = pcall(function()
			return model:GetPivot()
		end)
		if pivotOk and pivot then
			local p = pivot.Position
			local delta = (p - spec.Pivot).Magnitude
			if delta > HubAssetContract.Tolerance.Pivot then
				issue(issues, "bad_pivot",
					("pivot attendu (%.2f, %.2f, %.2f), trouvé (%.2f, %.2f, %.2f) — écart %.2f studs")
						:format(spec.Pivot.X, spec.Pivot.Y, spec.Pivot.Z, p.X, p.Y, p.Z, delta))
			end
		else
			issue(issues, "no_pivot", ("impossible de lire le pivot de %s"):format(spec.ModelName))
		end
	end

	-- 6) Enfants requis.
	local visualChild: Instance? = nil
	if isComposite then
		local childName = HubAssetContract.CompositeDeck.RequiredChild
		local childClass = HubAssetContract.CompositeDeck.RequiredChildClass
		visualChild = model:FindFirstChild(childName)
		if not visualChild then
			issue(issues, "missing_child",
				("enfant « %s » manquant dans %s"):format(childName, spec.ModelName))
		elseif not visualChild:IsA(childClass) then
			issue(issues, "bad_child",
				("enfant « %s » doit être un %s (trouvé %s)")
					:format(childName, childClass, visualChild.ClassName))
		end
	else
		for _, childName in ipairs(spec.RequiredChildren) do
			if not model:FindFirstChild(childName) then
				issue(issues, "missing_child",
					("enfant « %s » manquant dans %s"):format(childName, spec.ModelName))
			end
		end
	end

	-- 7) Surfaces GUI : plans nus, plats, aux bonnes cotes (sauf Composite fusionné).
	if not isComposite then
		for _, face in ipairs(spec.RequiredFaces) do
			local instance = model:FindFirstChild(face.Name, true)
			if not instance then
				issue(issues, "missing_face",
					("surface « %s » manquante (plan %.1f x %.1f pour SurfaceGui)")
						:format(face.Name, face.Width, face.Height))
			elseif not instance:IsA("BasePart") then
				issue(issues, "bad_face",
					("surface « %s » doit être une BasePart (trouvé %s)"):format(face.Name, instance.ClassName))
			else
				local part = instance :: BasePart
				local size = part.Size
				local axes = { size.X, size.Y, size.Z }
				table.sort(axes)
				if axes[1] > HubAssetContract.Tolerance.FaceThickness then
					issue(issues, "bad_face",
						("surface « %s » doit être plate (épaisseur ≤ %.2f, trouvé %.2f)")
							:format(face.Name, HubAssetContract.Tolerance.FaceThickness, axes[1]))
				end
				local tol = HubAssetContract.Tolerance.FaceSize
				local matched = (nearlyEqual(axes[2], math.min(face.Width, face.Height), tol)
					and nearlyEqual(axes[3], math.max(face.Width, face.Height), tol))
				if not matched then
					issue(issues, "bad_face",
						("surface « %s » attendue %.1f x %.1f (± %.2f), mesurée %.2f x %.2f")
							:format(face.Name, face.Width, face.Height, tol, axes[2], axes[3]))
				end
				if part:FindFirstChildWhichIsA("SurfaceGui") then
					issue(issues, "gui_in_asset",
						("surface « %s » ne doit contenir aucun SurfaceGui : le code le monte")
							:format(face.Name))
				end
				local centerDelta = (part.Position - face.Center).Magnitude
				if centerDelta > 1 then
					issue(issues, "bad_face",
						("surface « %s » attendue en (%.1f, %.1f, %.1f), trouvée à %.2f studs")
							:format(face.Name, face.Center.X, face.Center.Y, face.Center.Z, centerDelta))
				end
				local normal = HubAssetContract.FaceNormalOf(part)
				if normal and math.abs(normal:Dot(face.Normal)) < 0.99 then
					issue(issues, "bad_face_normal",
						("surface « %s » doit être normale à (%.0f, %.0f, %.0f)")
							:format(face.Name, face.Normal.X, face.Normal.Y, face.Normal.Z))
				end
			end
		end
	end

	-- 8) Contenu interdit, collisions non déclarées, ancrage, matériaux, lumières.
	local realLights = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if isForbidden(descendant.ClassName) then
			issue(issues, "forbidden_class",
				("%s interdit dans un asset (%s)"):format(descendant.ClassName, descendant.Name))
		end
		if descendant:IsA("Light") then
			realLights += 1
		end
		if isComposite and descendant:GetAttribute(A.Marker) == true then
			issue(issues, "nested_asset",
				("asset imbriqué interdit sous Composite (%s)"):format(descendant.Name))
		end
		if isComposite and descendant.ClassName == "SurfaceAppearance" then
			if not visualChild or not descendant:IsDescendantOf(visualChild) then
				issue(issues, "bad_surface_appearance",
					("SurfaceAppearance doit vivre sous Visual (%s)"):format(descendant.Name))
			end
		end
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			if part.Anchored ~= true then
				issue(issues, "not_anchored", ("%s doit être Anchored"):format(part.Name))
			end
			if not isComposite
				and part.CanCollide == true
				and not contains(spec.CollidableChildren, part.Name) then
				issue(issues, "undeclared_collision",
					("%s a CanCollide = true sans être déclaré dans le contrat"):format(part.Name))
			end
			if not isComposite then
				local material = part.Material
				local materialName = if typeof(material) == "EnumItem" then material.Name else tostring(material)
				if not HubAssetContract.AllowedMaterials[materialName] then
					issue(issues, "bad_material",
						("matériau %s non autorisé sur %s"):format(materialName, part.Name))
				end
			end
		end
	end
	-- LightFixtures héberge les sources : son plafond est le budget global, pas RealLights=0.
	local lightCap = if spec.Key == "LightFixtures"
		then HubAssetContract.Budget.MaxRealLights
		else spec.RealLights
	if realLights > lightCap then
		issue(issues, "too_many_lights",
			("%d source(s) lumineuse(s) pour un budget de %d"):format(realLights, lightCap))
	end

	-- 9) Budget triangles, si le modeleur l'a renseigné.
	local triangles = model:GetAttribute(A.TriangleCount)
	local maxTriangles = if isComposite
		then HubAssetContract.CompositeDeck.MaxTriangles
		else spec.MaxTriangles
	local meshCount = if isComposite then 1 else #spec.RequiredChildren
	if type(triangles) == "number" then
		if triangles > maxTriangles then
			issue(issues, "over_budget",
				("%d triangles déclarés pour un budget de %d"):format(triangles, maxTriangles))
		end
		if not isComposite
			and triangles > HubAssetContract.Budget.MaxTrianglesPerMesh * meshCount then
			issue(issues, "over_budget",
				("%d triangles dépassent la limite dure de %d par mesh"):format(
					triangles, HubAssetContract.Budget.MaxTrianglesPerMesh))
		end
	end

	return {
		Key = spec.Key,
		ModelName = spec.ModelName,
		Valid = #issues == 0,
		Issues = issues,
	}
end

--------------------------------------------------------------------
-- Doublons et modèles parasites dans le dossier visuel
--------------------------------------------------------------------
function HubAssetContract.FindStrayModels(folder: Instance?): { string }
	local stray: { string } = {}
	if not folder then
		return stray
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child.Name == HubAssetContract.ValidationCamerasFolder then
			continue
		end
		if BY_MODEL_NAME[child.Name] then
			continue
		end
		-- Un import répété produit « HubDeckShell », « HubDeckShell1 »… : à refuser.
		for name in pairs(BY_MODEL_NAME) do
			if #child.Name > #name and child.Name:sub(1, #name) == name then
				table.insert(stray, child.Name)
				break
			end
		end
	end
	return stray
end

--------------------------------------------------------------------
-- Comparaison avec une ancre réelle (utilisée en Phase 8)
--------------------------------------------------------------------
export type AnchorComparison = {
	Key: string,
	Matches: boolean,
	SizeDelta: Vector3,
	CenterDelta: Vector3,
	YawDelta: number,
}

function HubAssetContract.CompareWithAnchor(key: string, anchor: Instance?): AnchorComparison?
	local spec = BY_KEY[key]
	if not spec or not anchor or not anchor:IsA("BasePart") then
		return nil
	end
	local part = anchor :: BasePart
	local anchorSize = part:GetAttribute("TargetSize")
	local anchorYaw = part:GetAttribute("YawDegrees")
	if typeof(anchorSize) ~= "Vector3" or type(anchorYaw) ~= "number" then
		return nil
	end
	local sizeDelta = spec.TargetSize - anchorSize
	local centerDelta = spec.Center - part.CFrame.Position
	local yaw = yawDelta(spec.YawDegrees, anchorYaw)
	local matches = math.abs(sizeDelta.X) <= HubAssetContract.Tolerance.Size
		and math.abs(sizeDelta.Y) <= HubAssetContract.Tolerance.Size
		and math.abs(sizeDelta.Z) <= HubAssetContract.Tolerance.Size
		and centerDelta.Magnitude <= HubAssetContract.Tolerance.Pivot
		and yaw <= HubAssetContract.Tolerance.Yaw
	return {
		Key = key,
		Matches = matches,
		SizeDelta = sizeDelta,
		CenterDelta = centerDelta,
		YawDelta = yaw,
	}
end

--------------------------------------------------------------------
-- Décision : asset importé ou prototype de secours
--
-- Contrats de comportement (plan, P1.4) :
--   asset absent               → prototype, aucun avertissement ;
--   UseImported = false        → prototype, information seulement ;
--   asset présent et valide    → prototype non généré ;
--   asset présent et invalide  → PROTOTYPE CONSERVÉ + un seul avertissement explicite.
--------------------------------------------------------------------
local warned: { [string]: boolean } = {}

function HubAssetContract.ResetWarnings()
	warned = {}
end

function HubAssetContract.Decide(key: string, folder: Instance?, useImported: boolean): Decision
	local spec = BY_KEY[key]
	if not spec then
		return {
			Key = key,
			Status = "invalid",
			BuildPrototype = true,
			Message = ("[HubAssetContract] clé inconnue : %s"):format(tostring(key)),
		}
	end

	local model = if folder then folder:FindFirstChild(spec.ModelName) else nil

	if not useImported then
		return {
			Key = key,
			Status = "disabled",
			BuildPrototype = true,
			Message = ("[HubAssetContract] %s : UseImported = false, prototype conservé.")
				:format(spec.ModelName),
		}
	end

	if not model then
		return {
			Key = key,
			Status = "missing",
			BuildPrototype = true,
			Message = nil, -- asset absent : silence total
		}
	end

	local result = HubAssetContract.Validate(model, key)
	if result.Valid then
		return {
			Key = key,
			Status = "imported",
			BuildPrototype = false,
			Message = nil,
			Result = result,
		}
	end

	local reasons: { string } = {}
	for _, entry in ipairs(result.Issues) do
		table.insert(reasons, entry.Message)
	end
	local message = ("[HubAssetContract] %s refusé : %s"):format(
		spec.ModelName, table.concat(reasons, " | "))

	return {
		Key = key,
		Status = "invalid",
		BuildPrototype = true,
		Message = message,
		Result = result,
	}
end

-- Émet l'avertissement d'une décision au plus une fois par module et par raison.
function HubAssetContract.ReportOnce(decision: Decision): boolean
	if not decision.Message then
		return false
	end
	local signature = decision.Key .. "|" .. decision.Status .. "|" .. decision.Message
	if warned[signature] then
		return false
	end
	warned[signature] = true
	if decision.Status == "invalid" then
		warn(decision.Message)
	else
		print(decision.Message)
	end
	return true
end

--------------------------------------------------------------------
-- Validation globale du pack
--------------------------------------------------------------------
export type PackSummary = {
	Valid: boolean,
	Present: number,
	Imported: number,
	Invalid: number,
	RealLights: number,
	Triangles: number,
	Stray: { string },
	Results: { Result },
}

function HubAssetContract.ValidateAll(folder: Instance?, flags: { [string]: boolean }?): PackSummary
	local summary: PackSummary = {
		Valid = true,
		Present = 0,
		Imported = 0,
		Invalid = 0,
		RealLights = 0,
		Triangles = 0,
		Stray = HubAssetContract.FindStrayModels(folder),
		Results = {},
	}

	for _, spec in ipairs(MODULES) do
		local model = if folder then folder:FindFirstChild(spec.ModelName) else nil
		if model then
			summary.Present += 1
			local useImported = if flags then flags[spec.Key] ~= false else true
			local decision = HubAssetContract.Decide(spec.Key, folder, useImported)
			if decision.Result then
				table.insert(summary.Results, decision.Result)
			end
			if decision.Status == "imported" then
				summary.Imported += 1
				summary.RealLights += spec.RealLights
				local triangles = model:GetAttribute(HubAssetContract.Attributes.TriangleCount)
				if type(triangles) == "number" then
					summary.Triangles += triangles
				end
			elseif decision.Status == "invalid" then
				summary.Invalid += 1
				summary.Valid = false
			end
		end
	end

	if #summary.Stray > 0 then
		summary.Valid = false
	end
	if summary.RealLights > HubAssetContract.Budget.MaxRealLights then
		summary.Valid = false
	end
	if summary.Triangles > HubAssetContract.Budget.TotalTriangles then
		summary.Valid = false
	end

	return summary
end

--------------------------------------------------------------------
-- Marquage du fallback prototype (appliqué par CentralHubBuilder en P8.3)
--------------------------------------------------------------------
function HubAssetContract.MarkPrototypeVisual(instance: Instance)
	instance:SetAttribute(HubAssetContract.PrototypeAttribute, true)
end

function HubAssetContract.IsPrototypeVisual(instance: Instance): boolean
	return instance:GetAttribute(HubAssetContract.PrototypeAttribute) == true
end

return HubAssetContract
