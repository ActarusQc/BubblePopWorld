--!strict
-- Garde-fous du contrat d'import des assets du hub central (Phase 1).
-- Vérifie qu'un asset mal nommé, mal dimensionné, mal orienté, contenant un script
-- ou une SurfaceGui, ou une collision non déclarée, est refusé — et que le fallback
-- prototype reste alors actif.
--
-- Exécution hors Roblox : python tools\run_hub_asset_tests.py
-- Exécution Studio (après câblage P8) : require(...).Run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubAssetContract = require(Shared:WaitForChild("HubAssetContract"))

local HubAssetContractTests = {}

--------------------------------------------------------------------
-- Helpers de construction de modèles factices
--------------------------------------------------------------------
local function material(name: string)
	return Enum.Material[name] or { Name = name }
end

local function makePart(name: string, size: Vector3, position: Vector3?, mat: string?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position or Vector3.zero)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = material(mat or "Metal")
	return part
end

local function makeFace(spec: any): BasePart
	-- Plan mince selon la normale monde : épaisseur sur l'axe dominant de la normale.
	-- FaceNormalOf renvoie RightVector / UpVector / LookVector selon l'axe le plus mince.
	local thickness = 0.05
	local n = spec.Normal
	local size: Vector3
	local cf: CFrame
	if math.abs(n.X) > 0.9 then
		size = Vector3.new(thickness, spec.Height, spec.Width)
		-- RightVector = ±X. Yaw 180 inverse Right.
		cf = if n.X > 0
			then CFrame.new(spec.Center)
			else CFrame.new(spec.Center) * CFrame.Angles(0, math.pi, 0)
	elseif math.abs(n.Y) > 0.9 then
		size = Vector3.new(spec.Width, thickness, spec.Height)
		cf = CFrame.new(spec.Center)
	else
		size = Vector3.new(spec.Width, spec.Height, thickness)
		-- LookVector = -Z par défaut ; yaw 180 → Look = +Z.
		cf = if n.Z > 0
			then CFrame.new(spec.Center) * CFrame.Angles(0, math.pi, 0)
			else CFrame.new(spec.Center)
	end
	local face = makePart(spec.Name, size, spec.Center, "SmoothPlastic")
	face.CFrame = cf
	return face
end

local function stampAttributes(model: Model, spec: any)
	local A = HubAssetContract.Attributes
	model:SetAttribute(A.Marker, true)
	model:SetAttribute(A.Key, spec.Key)
	model:SetAttribute(A.Version, 1)
	model:SetAttribute(A.AuthoredSize, spec.TargetSize)
	model:SetAttribute(A.AuthoredYaw, spec.YawDegrees)
	model:SetAttribute(A.TriangleCount, math.floor(spec.MaxTriangles * 0.8))
end

-- Construit un modèle conforme au contrat pour la clé donnée (prêt à être validé).
local function buildValidModel(key: string, parent: Instance?): Model
	local spec = HubAssetContract.GetModule(key)
	assert(spec, "module inconnu: " .. tostring(key))

	local model = Instance.new("Model")
	model.Name = spec.ModelName
	model.WorldPivot = CFrame.new(spec.Pivot)
	stampAttributes(model, spec)

	local worldSize = HubAssetContract.WorldExtents(spec.TargetSize, spec.YawDegrees)
	-- Un seul mesh « Base » (ou premier enfant) porte la bounding box cible.
	for index, childName in ipairs(spec.RequiredChildren) do
		local size = if index == 1
			then worldSize
			else Vector3.new(0.5, 0.5, 0.5)
		local part = makePart(childName, size, spec.Center)
		part.Parent = model
	end

	for _, face in ipairs(spec.RequiredFaces) do
		local facePart = makeFace(face)
		facePart.Parent = model
	end

	if parent then
		model.Parent = parent
	end
	return model
end

local function ensureVisualFolder(): Folder
	local workspaceService = game:GetService("Workspace")
	local decor = workspaceService:FindFirstChild(HubAssetContract.StudioDecorationRoot)
	if not decor then
		decor = Instance.new("Folder")
		decor.Name = HubAssetContract.StudioDecorationRoot
		decor.Parent = workspaceService
	end
	local visual = decor:FindFirstChild(HubAssetContract.VisualFolder)
	if not visual then
		visual = Instance.new("Folder")
		visual.Name = HubAssetContract.VisualFolder
		visual.Parent = decor
	end
	return visual :: Folder
end

local function clearFolder(folder: Folder)
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

local function hasCode(result: any, code: string): boolean
	for _, issue in ipairs(result.Issues) do
		if issue.Code == code then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------
-- Suite
--------------------------------------------------------------------
function HubAssetContractTests.Run(): boolean
	local ok = true
	local passed = 0
	local failed = 0

	local function check(cond: boolean, msg: string)
		if cond then
			passed += 1
		else
			failed += 1
			ok = false
			warn("[HubAssetContractTests] FAIL:", msg)
		end
	end

	print("== HubAssetContract (Phase 1) ==")
	HubAssetContract.ResetWarnings()

	--------------------------------------------------------------------
	print("\n1. Contrat : 12 modules, budgets, attributs, chemins")
	--------------------------------------------------------------------
	local modules = HubAssetContract.GetModules()
	check(#modules == 12, ("12 modules attendus, trouvé %d"):format(#modules))

	local expectedNames = {
		HubDeckShell_New = true,
		HubDeckShell = true,
		HubSellStandShell = true,
		HubShopStandShell = true,
		HubLoopPanelFrame = true,
		HubTop3BoardFrame = true,
		HubRulesBoardFrame = true,
		HubFrontStairs = true,
		HubTransitShell = true,
		HubRailingsAndPosts = true,
		HubSpawnMedallion = true,
		HubLightFixtures = true,
		HubDecorProps = true,
	}
	local totalTriangles = 0
	local totalLights = 0
	for _, spec in ipairs(modules) do
		check(expectedNames[spec.ModelName] == true, ("module %s listé"):format(spec.ModelName))
		check(HubAssetContract.GetModule(spec.Key) == spec, ("GetModule(%s)"):format(spec.Key))
		check(HubAssetContract.GetModuleByModelName(spec.ModelName) == spec,
			("GetModuleByModelName(%s)"):format(spec.ModelName))
		check(spec.MaxTriangles <= HubAssetContract.Budget.MaxTrianglesPerMesh
			or #spec.RequiredChildren > 1,
			("%s budget mesh"):format(spec.Key))
		check(spec.MaxTriangles > 0, ("%s MaxTriangles > 0"):format(spec.Key))
		check(#spec.RequiredChildren > 0, ("%s RequiredChildren non vide"):format(spec.Key))
		check(typeof(spec.TargetSize) == "Vector3", ("%s TargetSize"):format(spec.Key))
		check(typeof(spec.Center) == "Vector3", ("%s Center"):format(spec.Key))
		check(typeof(spec.Pivot) == "Vector3", ("%s Pivot"):format(spec.Key))
		totalTriangles += spec.MaxTriangles
		totalLights += spec.RealLights
	end
	check(totalTriangles == HubAssetContract.Budget.TotalTriangles,
		("budget total %d == %d"):format(totalTriangles, HubAssetContract.Budget.TotalTriangles))
	check(totalLights == HubAssetContract.Budget.MaxRealLights,
		("budget lumières %d == %d"):format(totalLights, HubAssetContract.Budget.MaxRealLights))

	local A = HubAssetContract.Attributes
	check(A.Marker == "BPW_HubAsset", "attribut Marker")
	check(A.Key == "BPW_HubAssetKey", "attribut Key")
	check(A.Version == "BPW_AssetVersion", "attribut Version")
	check(A.AuthoredSize == "BPW_AuthoredSize", "attribut AuthoredSize")
	check(A.AuthoredYaw == "BPW_AuthoredYaw", "attribut AuthoredYaw")
	check(HubAssetContract.PrototypeAttribute == "BPW_PrototypeVisualFallback", "fallback attr")
	check(HubAssetContract.GetVisualPath() == "Workspace.StudioDecoration.CentralHubVisual",
		"chemin visuel")

	-- Deck : bbox 84×8.7×60, pivot décentré (ailes surélevées à Y=13.20).
	local deckSpec = HubAssetContract.GetModule("Deck")
	assert(deckSpec)
	check(deckSpec.TargetSize == Vector3.new(84, 8.7, 60), "Deck TargetSize 84×8.7×60")
	check(deckSpec.Center == Vector3.new(0, 8.85, 0), "Deck WorldCenter (0, 8.85, 0)")
	check(deckSpec.Pivot == Vector3.new(0, 8.25, 0), "Deck Pivot (0, 8.25, 0)")
	check(math.abs(deckSpec.Center.Y - deckSpec.Pivot.Y - 0.6) < 1e-6,
		"Deck : centre bbox 0.6 au-dessus du pivot (ailes +1.2 / 2)")
	check(deckSpec.Pivot.Y ~= deckSpec.Center.Y, "Deck : pivot ≠ centre bbox")

	-- Surfaces GUI obligatoires pour les modules interactifs.
	local faces = {
		SellStand = { "SellSignFace", "SellValueFace" },
		ShopStand = { "ShopSignFace", "DisplaySkillsFace", "DisplayItemsFace", "DisplayCosmeticsFace" },
		LoopPanel = { "LoopPanelFace" },
		TopBoard = { "Top3Face" },
		RulesBoard = { "RulesFace" },
		TransitAlcove = { "TransitSignFace" },
	}
	for key, names in pairs(faces) do
		local spec = HubAssetContract.GetModule(key)
		assert(spec)
		check(#spec.RequiredFaces == #names, ("%s : %d faces"):format(key, #names))
		for i, name in ipairs(names) do
			check(spec.RequiredFaces[i].Name == name, ("%s face %s"):format(key, name))
		end
	end

	--------------------------------------------------------------------
	print("\n2. Modèle valide : accepté")
	--------------------------------------------------------------------
	local visual = ensureVisualFolder()
	clearFolder(visual)

	local deck = buildValidModel("Deck", visual)
	local valid = HubAssetContract.Validate(deck, "Deck")
	check(valid.Valid == true, "HubDeckShell_New valide")
	check(#valid.Issues == 0, "HubDeckShell_New sans issues")

	local loop = buildValidModel("LoopPanel", visual)
	local loopValid = HubAssetContract.Validate(loop, "LoopPanel")
	check(loopValid.Valid == true, "HubLoopPanelFrame valide (yaw 180 + face)")

	local sell = buildValidModel("SellStand", visual)
	local sellValid = HubAssetContract.Validate(sell, "SellStand")
	check(sellValid.Valid == true, "HubSellStandShell valide (yaw 90 + faces)")

	--------------------------------------------------------------------
	print("\n3. Nom incorrect")
	--------------------------------------------------------------------
	deck.Name = "HubDeck" -- LegacyModelName, plus le nom contractuel
	local badName = HubAssetContract.Validate(deck, "Deck")
	check(badName.Valid == false, "nom legacy refusé")
	check(hasCode(badName, "bad_name"), "code bad_name")
	deck.Name = "HubDeckShell_New"

	--------------------------------------------------------------------
	print("\n4. Bounding box hors tolérance")
	--------------------------------------------------------------------
	local base = deck:FindFirstChild("Base") :: BasePart
	local originalSize = base.Size
	base.Size = Vector3.new(originalSize.X + 3, originalSize.Y, originalSize.Z)
	local badSize = HubAssetContract.Validate(deck, "Deck")
	check(badSize.Valid == false, "taille hors tolérance refusée")
	check(hasCode(badSize, "bad_size"), "code bad_size")
	base.Size = originalSize

	--------------------------------------------------------------------
	print("\n5. Yaw inversé (0° au lieu de 180°)")
	--------------------------------------------------------------------
	loop:SetAttribute(A.AuthoredYaw, 0)
	local badYaw = HubAssetContract.Validate(loop, "LoopPanel")
	check(badYaw.Valid == false, "yaw 0° refusé pour panneau 180°")
	check(hasCode(badYaw, "bad_yaw"), "code bad_yaw")
	loop:SetAttribute(A.AuthoredYaw, 180)

	--------------------------------------------------------------------
	print("\n6. Pivot décalé")
	--------------------------------------------------------------------
	local goodPivot = deck.WorldPivot
	deck.WorldPivot = CFrame.new(Vector3.new(5, 8.25, 0))
	local badPivot = HubAssetContract.Validate(deck, "Deck")
	check(badPivot.Valid == false, "pivot décalé refusé")
	check(hasCode(badPivot, "bad_pivot"), "code bad_pivot")
	deck.WorldPivot = goodPivot

	--------------------------------------------------------------------
	print("\n7. Surface *Face manquante")
	--------------------------------------------------------------------
	local face = loop:FindFirstChild("LoopPanelFace")
	assert(face)
	face.Parent = nil
	local badFace = HubAssetContract.Validate(loop, "LoopPanel")
	check(badFace.Valid == false, "face manquante refusée")
	check(hasCode(badFace, "missing_face"), "code missing_face")
	face.Parent = loop

	--------------------------------------------------------------------
	print("\n8. Script interdit présent")
	--------------------------------------------------------------------
	local script = Instance.new("Script")
	script.Name = "Evil"
	script.Parent = deck
	local badScript = HubAssetContract.Validate(deck, "Deck")
	check(badScript.Valid == false, "Script refusé")
	check(hasCode(badScript, "forbidden_class"), "code forbidden_class (Script)")
	script:Destroy()

	local localScript = Instance.new("LocalScript")
	localScript.Name = "EvilLocal"
	localScript.Parent = deck
	local badLocal = HubAssetContract.Validate(deck, "Deck")
	check(badLocal.Valid == false, "LocalScript refusé")
	check(hasCode(badLocal, "forbidden_class"), "code forbidden_class (LocalScript)")
	localScript:Destroy()

	--------------------------------------------------------------------
	print("\n9. SurfaceGui livré dans le mesh")
	--------------------------------------------------------------------
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PrematureGui"
	gui.Parent = face
	local badGui = HubAssetContract.Validate(loop, "LoopPanel")
	check(badGui.Valid == false, "SurfaceGui dans l'asset refusé")
	check(hasCode(badGui, "gui_in_asset") or hasCode(badGui, "forbidden_class"),
		"code gui_in_asset ou forbidden_class")
	gui:Destroy()

	--------------------------------------------------------------------
	print("\n10. Collision non déclarée")
	--------------------------------------------------------------------
	local moulding = deck:FindFirstChild("Moulding") :: BasePart
	moulding.CanCollide = true
	local badCollide = HubAssetContract.Validate(deck, "Deck")
	check(badCollide.Valid == false, "CanCollide non déclaré refusé")
	check(hasCode(badCollide, "undeclared_collision"), "code undeclared_collision")
	moulding.CanCollide = false

	-- Counter du Sell est déclaré collidable : doit passer.
	local counter = sell:FindFirstChild("Counter") :: BasePart
	counter.CanCollide = true
	local sellCollide = HubAssetContract.Validate(sell, "SellStand")
	check(sellCollide.Valid == true, "Counter déclaré CanCollide accepté")
	counter.CanCollide = false

	--------------------------------------------------------------------
	print("\n11. Décision : absent / disabled / valide / invalide")
	--------------------------------------------------------------------
	clearFolder(visual)
	HubAssetContract.ResetWarnings()

	local missing = HubAssetContract.Decide("Deck", visual, true)
	check(missing.Status == "missing", "absent → missing")
	check(missing.BuildPrototype == true, "absent → BuildPrototype")
	check(missing.Message == nil, "absent → silence (pas d'avertissement)")

	local disabled = HubAssetContract.Decide("Deck", visual, false)
	check(disabled.Status == "disabled", "UseImported=false → disabled")
	check(disabled.BuildPrototype == true, "disabled → BuildPrototype")
	check(type(disabled.Message) == "string", "disabled → message info")

	local good = buildValidModel("Deck", visual)
	local imported = HubAssetContract.Decide("Deck", visual, true)
	check(imported.Status == "imported", "valide → imported")
	check(imported.BuildPrototype == false, "valide → pas de prototype")
	check(imported.Message == nil, "valide → silence")

	-- Garder le nom contractuel : un renommage ferait « missing », pas « invalid ».
	good:SetAttribute(A.AuthoredYaw, 90)
	local invalid = HubAssetContract.Decide("Deck", visual, true)
	check(invalid.Status == "invalid", "invalide → invalid")
	check(invalid.BuildPrototype == true, "invalide → PROTOTYPE CONSERVÉ")
	check(type(invalid.Message) == "string"
		and string.find(invalid.Message, "[HubAssetContract]", 1, true) ~= nil
		and string.find(invalid.Message, "refus", 1, true) ~= nil,
		"invalide → message [HubAssetContract] … refusé")
	good:SetAttribute(A.AuthoredYaw, 0)

	-- ReportOnce : un seul avertissement pour la même raison.
	HubAssetContract.ResetWarnings()
	local first = HubAssetContract.ReportOnce(invalid)
	local second = HubAssetContract.ReportOnce(invalid)
	check(first == true, "ReportOnce émet la première fois")
	check(second == false, "ReportOnce silencieux la seconde fois")

	--------------------------------------------------------------------
	print("\n12. Module absent / double import (stray)")
	--------------------------------------------------------------------
	clearFolder(visual)
	local unknown = HubAssetContract.Validate(nil, "DoesNotExist")
	check(unknown.Valid == false, "clé inconnue refusée")
	check(hasCode(unknown, "unknown_module"), "code unknown_module")

	buildValidModel("Deck", visual)
	local dupe = buildValidModel("Deck", nil)
	dupe.Name = "HubDeckShell1"
	dupe.Parent = visual
	local stray = HubAssetContract.FindStrayModels(visual)
	check(#stray == 1 and stray[1] == "HubDeckShell1", "double import détecté (HubDeckShell1)")

	local summary = HubAssetContract.ValidateAll(visual, { Deck = true })
	check(summary.Present == 1, "ValidateAll Present")
	check(summary.Imported == 1, "ValidateAll Imported")
	check(summary.Valid == false, "ValidateAll invalide à cause du stray")
	check(#summary.Stray == 1, "ValidateAll Stray")

	--------------------------------------------------------------------
	print("\n13. Marquage PrototypeVisualFallback")
	--------------------------------------------------------------------
	local proto = makePart("HubDeckSlab", Vector3.new(10, 1, 10), Vector3.zero)
	check(HubAssetContract.IsPrototypeVisual(proto) == false, "pas encore marqué")
	HubAssetContract.MarkPrototypeVisual(proto)
	check(HubAssetContract.IsPrototypeVisual(proto) == true, "marqué BPW_PrototypeVisualFallback")
	proto:Destroy()

	--------------------------------------------------------------------
	print("\n14. Comparaison ancre prototype vs cotes approuvées (écarts Phase 0)")
	--------------------------------------------------------------------
	local anchor = makePart("Anchor_Deck", Vector3.new(1, 1, 1), Vector3.new(0, 11, 0))
	anchor:SetAttribute("TargetSize", Vector3.new(84, 2, 60))
	anchor:SetAttribute("YawDegrees", 0)
	local cmp = HubAssetContract.CompareWithAnchor("Deck", anchor)
	check(cmp ~= nil, "CompareWithAnchor retourne un résultat")
	if cmp then
		check(cmp.Matches == false, "Deck : ancre prototype ≠ cote approuvée (attendu)")
		-- Approuvé 8.7 − prototype 2.0 = +6.7
		check(math.abs(cmp.SizeDelta.Y - 6.7) < 1e-6, "Deck SizeDelta.Y = +6.7")
	end
	anchor:Destroy()

	--------------------------------------------------------------------
	print("\n15. Revue : fiches de modélisation dérivables (P1.7)")
	--------------------------------------------------------------------
	for _, spec in ipairs(modules) do
		check(spec.Format == "FBX" or spec.Format == "OBJ",
			("%s Format"):format(spec.Key))
		check(spec.Notes ~= "", ("%s Notes non vides"):format(spec.Key))
		check(spec.Priority >= 1 and spec.Priority <= 12,
			("%s Priority"):format(spec.Key))
		-- Chaque enfant requis est un nom non vide utilisable en Blender/Roblox.
		for _, childName in ipairs(spec.RequiredChildren) do
			check(type(childName) == "string" and #childName > 0,
				("%s enfant nommé"):format(spec.Key))
		end
		for _, faceSpec in ipairs(spec.RequiredFaces) do
			check(faceSpec.Width > 0 and faceSpec.Height > 0,
				("%s face %s dimensions"):format(spec.Key, faceSpec.Name))
			check(faceSpec.Normal.Magnitude > 0.99,
				("%s face %s normale unitaire"):format(spec.Key, faceSpec.Name))
		end
	end

	-- Symétrie Sell / Shop (critère bloquant Phase 4).
	local sellSpec = HubAssetContract.GetModule("SellStand")
	local shopSpec = HubAssetContract.GetModule("ShopStand")
	assert(sellSpec and shopSpec)
	check(sellSpec.TargetSize == shopSpec.TargetSize, "Sell/Shop TargetSize identiques")
	check(sellSpec.MaxTriangles == shopSpec.MaxTriangles, "Sell/Shop budget identiques")
	check(math.abs(sellSpec.Center.X + shopSpec.Center.X) < 1e-6, "Sell/Shop symétriques en X")
	check(sellSpec.Center.Y == shopSpec.Center.Y, "Sell/Shop même hauteur")

	--------------------------------------------------------------------
	print("\n16. Variante Composite Tripo (HubDeckShell_New)")
	--------------------------------------------------------------------
	clearFolder(visual)
	local compositeSize = HubAssetContract.CompositeDeck.TargetSize
	check(compositeSize == Vector3.new(84, 14, 60), "Composite TargetSize 84×14×60")
	check(HubAssetContract.CompositeDeck.BottomY == 4.5, "Composite BottomY = 4.5")
	check(HubAssetContract.CompositeDeck.YawDegrees == 0, "Composite AuthoredYaw contrat = 0")
	check(HubAssetContract.CompositeDeck.RuntimeYawDegrees == 180, "Composite RuntimeYaw = 180")
	check(A.Variant == "BPW_HubAssetVariant", "attribut Variant")
	check(deckSpec.ModelName == "HubDeckShell_New", "Deck ModelName HubDeckShell_New")
	check(deckSpec.LegacyModelName == "HubDeckShell", "Deck LegacyModelName HubDeckShell")

	local function buildCompositeDeck(parent: Instance?): Model
		local model = Instance.new("Model")
		model.Name = "HubDeckShell_New"
		model.WorldPivot = CFrame.new(Vector3.new(12, 3, -7))
		model:SetAttribute(A.Marker, true)
		model:SetAttribute(A.Key, "HubDeckShell_New")
		model:SetAttribute(A.Version, 1)
		model:SetAttribute(A.AuthoredSize, compositeSize)
		model:SetAttribute(A.AuthoredYaw, HubAssetContract.CompositeDeck.YawDegrees)
		model:SetAttribute(A.Variant, HubAssetContract.CompositeVariant)
		local visualPart = Instance.new("MeshPart")
		visualPart.Name = "Visual"
		visualPart.Size = compositeSize
		-- Pose Studio autoritative — yaw runtime ensuite ; Prepare ne doit pas altérer.
		visualPart.CFrame = CFrame.new(Vector3.new(5, 20, 5))
			* CFrame.Angles(math.rad(18), math.rad(40), math.rad(-12))
		visualPart.PivotOffset = CFrame.Angles(math.rad(15), 0, 0)
		visualPart.Transparency = 0
		visualPart.Anchored = true
		visualPart.CanCollide = true -- doit devenir false (collision seule)
		visualPart.Material = material("Metal")
		visualPart.Parent = model
		local appearance = Instance.new("SurfaceAppearance")
		appearance.Name = "SurfaceAppearance"
		appearance.Parent = visualPart
		if parent then
			model.Parent = parent
		end
		return model
	end

	local composite = buildCompositeDeck(visual)
	check(HubAssetContract.IsCompositeVariant(composite) == true, "IsCompositeVariant")
	check(HubAssetContract.GetEffectiveTargetSize(composite, deckSpec) == compositeSize,
		"GetEffectiveTargetSize Composite")
	local compositeValid = HubAssetContract.Validate(composite, "Deck")
	check(compositeValid.Valid == true, "Composite valide (Visual + SurfaceAppearance)")
	check(#compositeValid.Issues == 0, "Composite sans issues")

	-- Le contrat standard (Base/Moulding/…) reste exigé sans variante.
	local standard = buildValidModel("Deck", nil)
	standard.Parent = nil
	local stillStandard = HubAssetContract.Validate(standard, "Deck")
	check(stillStandard.Valid == true, "contrat standard non Composite inchangé")
	standard:Destroy()

	-- Script interdit.
	local evil = Instance.new("Script")
	evil.Name = "No"
	evil.Parent = composite
	local badCompositeScript = HubAssetContract.Validate(composite, "Deck")
	check(badCompositeScript.Valid == false, "Composite + Script refusé")
	check(hasCode(badCompositeScript, "forbidden_class"), "Composite forbidden_class")
	evil:Destroy()

	-- Visual manquant / mauvaise classe.
	local visualPart = composite:FindFirstChild("Visual")
	assert(visualPart and visualPart:IsA("MeshPart"))
	visualPart.Name = "NotVisual"
	local missingVisual = HubAssetContract.Validate(composite, "Deck")
	check(missingVisual.Valid == false and hasCode(missingVisual, "missing_child"),
		"Composite sans Visual refusé")
	visualPart.Name = "Visual"
	local partInstead = Instance.new("Part")
	partInstead.Name = "Visual"
	partInstead.Size = compositeSize
	partInstead.CFrame = visualPart.CFrame
	partInstead.Anchored = true
	partInstead.Parent = composite
	visualPart.Parent = nil
	local badClass = HubAssetContract.Validate(composite, "Deck")
	check(badClass.Valid == false and hasCode(badClass, "bad_child"),
		"Composite Visual non-MeshPart refusé")
	partInstead:Destroy()
	visualPart.Parent = composite

	-- Taille hors tolérance.
	visualPart.Size = Vector3.new(90, 14, 60)
	composite:SetAttribute(A.AuthoredSize, Vector3.new(90, 14, 60))
	local badCompositeSize = HubAssetContract.Validate(composite, "Deck")
	check(badCompositeSize.Valid == false and hasCode(badCompositeSize, "bad_size"),
		"Composite taille 90×14×60 refusée")
	visualPart.Size = compositeSize
	composite:SetAttribute(A.AuthoredSize, compositeSize)

	--------------------------------------------------------------------
	-- Yaw runtime 180° (idempotent) puis Prepare sans altérer la pose
	--------------------------------------------------------------------
	local yawAttr = HubAssetContract.CompositeDeck.RuntimeYawAttribute
	local lookBefore = visualPart.CFrame.LookVector
	local yaw1 = HubAssetContract.ApplyCompositeRuntimeYaw(composite)
	check(yaw1 == true, "premier ApplyCompositeRuntimeYaw applique 180°")
	check(composite:GetAttribute(yawAttr) == 180, "attribut RuntimeYaw = 180")
	check(math.abs(visualPart.CFrame.LookVector:Dot(lookBefore) + 1) < 1e-3
		or (visualPart.CFrame.LookVector - lookBefore).Magnitude > 0.1,
		"LookVector modifié par yaw Y (pas identité)")
	local yaw2 = HubAssetContract.ApplyCompositeRuntimeYaw(composite)
	check(yaw2 == false, "second ApplyCompositeRuntimeYaw no-op")

	local before = HubAssetContract.SnapshotCompositeVisual(composite)
	assert(before)
	HubAssetContract.PrepareCompositeStudioSource(composite)
	local okUnchanged, reason = HubAssetContract.AssertCompositeVisualUnchanged(composite, before)
	check(okUnchanged == true, "Prepare ne modifie pas CFrame/Size/PivotOffset/Transparency (" .. tostring(reason) .. ")")
	check(visualPart.CanCollide == false, "Visual non collisionnable après Prepare")
	check(visualPart.CastShadow == false, "Visual CastShadow off (hub moins sombre)")
	check(visualPart.Transparency == 0, "Visual reste visible (Transparency inchangée)")
	check(composite.Parent == visual, "Parent reste CentralHubVisual")
	check(composite:FindFirstChild("Visual") == visualPart, "aucun clone de Visual")
	HubAssetContract.PrepareCompositeStudioSource(composite)
	local ok2, reason2 = HubAssetContract.AssertCompositeVisualUnchanged(composite, before)
	check(ok2 == true, "deux Prepare → source inchangée (" .. tostring(reason2) .. ")")

	-- Legacy HubDeckShell coexistant : masqué, New reste visible.
	local legacy = Instance.new("Model")
	legacy.Name = "HubDeckShell"
	legacy.Parent = visual
	local legacyMesh = Instance.new("MeshPart")
	legacyMesh.Name = "Visual"
	legacyMesh.Size = Vector3.new(10, 2, 10)
	legacyMesh.Transparency = 0
	legacyMesh.Anchored = true
	legacyMesh.CanCollide = true
	legacyMesh.Parent = legacy
	HubAssetContract.HideLegacyCompositeDeck(visual, composite)
	check(legacyMesh.Transparency == 1, "legacy HubDeckShell masqué")
	check(legacyMesh.CanCollide == false, "legacy non collisionnable")
	check(visualPart.Transparency == 0, "HubDeckShell_New reste visible")

	local decision = HubAssetContract.Decide("Deck", visual, true)
	check(decision.Status == "imported" and decision.BuildPrototype == false,
		"Composite valide → imported, pas de prototype")

	clearFolder(visual)

	print(("\n%d réussis, %d échoués"):format(passed, failed))
	if ok then
		print("RESULTAT : OK")
	else
		print("RESULTAT : ECHEC")
	end
	return ok
end

return HubAssetContractTests
