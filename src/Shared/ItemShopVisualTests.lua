--!strict
-- Tests purs pour ItemShopVisualShell : trois états de build, pivot commun,
-- coque initiale éditable, entrée dégagée, attributs obligatoires.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Shell = require(Shared.ItemShopVisualShell)

local ItemShopVisualTests = {}

local function findPart(parts: { any }, name: string): any
	for _, part in ipairs(parts) do
		if part.Name == name then
			return part
		end
	end
	return nil
end

function ItemShopVisualTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[ItemShopVisualTests] FAIL:", msg)
		end
	end

	local shop = Config.Lobby.ItemShop

	-- 1) Trois états de UseStudioVisual.
	check(Shell.ResolveBuildMode(false, false) == "Legacy", "false + absent -> Legacy")
	check(Shell.ResolveBuildMode(false, true) == "Legacy", "false + présent -> Legacy")
	check(Shell.ResolveBuildMode(nil, true) == "Legacy", "nil -> Legacy")
	check(Shell.ResolveBuildMode(true, true) == "FunctionalOnly", "true + présent -> FunctionalOnly")
	check(Shell.ResolveBuildMode(true, false) == "FunctionalWithFallback", "true + absent -> FunctionalWithFallback")
	check(Shell.ResolveBuildMode(true, nil) == "FunctionalWithFallback", "true + inconnu -> FunctionalWithFallback")

	check(Shell.ShouldBuildLegacyDecor("Legacy") == true, "Legacy garde le décor procédural")
	check(Shell.ShouldBuildLegacyDecor("FunctionalOnly") == false, "FunctionalOnly sans décor procédural")
	check(Shell.ShouldBuildLegacyDecor("FunctionalWithFallback") == false, "Fallback sans décor procédural")
	check(Shell.ShouldBuildFallbackShell("Legacy") == false, "Legacy ne crée jamais FallbackShell")
	check(Shell.ShouldBuildFallbackShell("FunctionalOnly") == false, "Visual présent : aucun FallbackShell")
	check(Shell.ShouldBuildFallbackShell("FunctionalWithFallback") == true, "Visual absent : FallbackShell")

	-- 2) Étape 2 : Studio-first activé, aucune décoration procédurale possible.
	check(shop.UseStudioVisual == true, "UseStudioVisual = true")
	check(
		Shell.ResolveEffectiveMode(shop.UseStudioVisual, true) == "FunctionalOnly",
		"config actuelle + visuel présent -> guides seuls"
	)
	check(
		Shell.ResolveEffectiveMode(shop.UseStudioVisual, false) == "FunctionalWithFallback",
		"config actuelle sans visuel -> fallback"
	)
	check(
		Shell.ShouldBuildLegacyDecor(Shell.ResolveEffectiveMode(shop.UseStudioVisual, true)) == false,
		"aucun décor procédural avec la config actuelle"
	)

	-- Le décor procédural ayant été retiré, false ne doit plus laisser de salle vide.
	check(Shell.ResolveEffectiveMode(false, true) == "FunctionalOnly", "false + visuel -> guides seuls")
	check(Shell.ResolveEffectiveMode(false, false) == "FunctionalWithFallback", "false sans visuel -> fallback")
	check(Shell.IsLegacyDecorRequested(false) == true, "false signale une demande de décor retiré")
	check(Shell.IsLegacyDecorRequested(true) == false, "true ne demande aucun décor retiré")

	-- 3) Messages exacts.
	check(
		Shell.MissingVisualMessage == "[ItemShopBuilder] ItemShopVisual missing. Using functional fallback shell.",
		"message fallback exact"
	)
	check(
		Shell.AlreadyExistsMessage == "ItemShopVisual already exists. No changes were made.",
		"message anti-écrasement exact"
	)

	-- 4) Nommage : jamais "ItemShop" (ShopUI cherche ce nom récursivement).
	check(Shell.GetVisualModelName() == "ItemShopVisual", "modèle nommé ItemShopVisual")
	check(Shell.GetVisualModelName() ~= "ItemShop", "modèle jamais nommé ItemShop")
	check(Shell.GetStudioDecorationRootName() == "StudioDecoration", "racine StudioDecoration")

	-- 5) Pivot commun fonctionnel / visuel.
	local pivot = Shell.GetPivotPosition()
	check(pivot.X == 34, "pivot X = 34")
	check(pivot.Y == 0, "pivot Y = 0")
	check(pivot.Z == -230, "pivot Z = -230")
	check(Shell.GetPivotYaw() == 270, "pivot yaw = 270")

	-- 6) Sections de la hiérarchie artistique.
	local sections = Shell.GetSections()
	check(#sections == 5, "5 sections")
	for _, name in ipairs({ "Structure", "Exterior", "Interior", "Displays", "Lighting" }) do
		check(table.find(sections, name) ~= nil, "section " .. name)
	end

	-- 7) Coque initiale réellement utilisable.
	local parts = Shell.GetShellSpec()
	for _, name in ipairs({
		"Floor",
		"LeftWall",
		"BackWall",
		"RightWall",
		"Ceiling",
		"FacadePillarLeft",
		"FacadePillarRight",
		"FacadeLintel",
	}) do
		check(findPart(parts, name) ~= nil, "coque contient " .. name)
	end

	local floor = findPart(parts, "Floor")
	check(floor.Size.X == shop.Width, "plancher = largeur configurée")
	check(floor.Size.Z == shop.Depth, "plancher = profondeur configurée")
	check(floor.CanCollide == true, "plancher collisionnable")

	local leftWall = findPart(parts, "LeftWall")
	check(leftWall.Size.Y == shop.Height - 1, "mur du plancher au plafond")
	check(leftWall.CanCollide == true, "mur gauche collisionnable")
	check(findPart(parts, "RightWall").CanCollide == true, "mur droit collisionnable")
	check(findPart(parts, "BackWall").CanCollide == true, "mur arrière collisionnable")

	local lintel = findPart(parts, "FacadeLintel")
	check(lintel.Size.X == shop.DoorWidth, "linteau de la largeur de l'entrée")

	-- 8) Entrée : 13 studs, totalement ouverte et traversable.
	local opening = Shell.GetEntranceOpening()
	check(opening.Width == 13, "ouverture de 13 studs")
	check(opening.MaxX - opening.MinX == 13, "largeur libre = 13 studs")
	check(opening.Z == shop.Depth / 2, "ouverture sur la façade avant")
	local pillarLeft = findPart(parts, "FacadePillarLeft")
	check(
		pillarLeft.Offset.X + pillarLeft.Size.X / 2 <= opening.MinX,
		"pilier gauche hors de l'ouverture"
	)
	local blocking = 0
	for _, part in ipairs(parts) do
		if Shell.BlocksEntrance(part) then
			blocking += 1
			warn("[ItemShopVisualTests] bloque l'entrée:", part.Name)
		end
	end
	check(blocking == 0, "aucun élément collisionnable dans l'ouverture")

	-- 9) Collisions : seuls plancher, murs et façade portent la collision.
	for _, part in ipairs(parts) do
		if part.Section ~= "Structure" then
			check(part.CanCollide == false, "décoration non collisionnable: " .. part.Name)
		end
	end
	check(findPart(parts, "Ceiling").CanCollide == false, "plafond non collisionnable")

	-- 9b) FallbackShell : plancher, murs, plafond, entrée ouverte, panneau SHOP.
	local fallback = Shell.GetFallbackSpec()
	for _, name in ipairs({
		"Floor",
		"LeftWall",
		"BackWall",
		"RightWall",
		"Ceiling",
		"FacadePillarLeft",
		"FacadePillarRight",
		"FacadeLintel",
		"SignBoard",
	}) do
		check(findPart(fallback, name) ~= nil, "fallback contient " .. name)
	end
	check(#fallback == 9, "fallback strictement minimal (9 pièces)")
	check(findPart(fallback, "SkillsPodium") == nil, "fallback sans socle décoratif")
	check(findPart(fallback, "CeilingLightHost") == nil, "fallback sans éclairage décoratif")
	local fallbackBlocking = 0
	for _, part in ipairs(fallback) do
		if Shell.BlocksEntrance(part) then
			fallbackBlocking += 1
		end
	end
	check(fallbackBlocking == 0, "entrée du fallback entièrement ouverte")
	check(Shell.GetSignText() == "SHOP", "panneau SHOP du fallback")

	-- 10) Socles alignés sur les FocusAnchor du modèle fonctionnel.
	local centers = Shell.GetDisplayCenters()
	local halfW, halfD = shop.Width / 2, shop.Depth / 2
	local t = shop.WallThickness / 2
	check(centers.Skills.X == -halfW + t + 4.1, "centre Skills aligné")
	check(centers.Skills.Z == 0, "centre Skills sur l'axe")
	check(centers.Items.Z == -halfD + t + 4.6, "centre Items aligné")
	check(centers.Items.X == 0, "centre Items sur l'axe")
	check(centers.Cosmetics.X == halfW - t - 4.1, "centre Cosmetics aligné")
	for _, id in ipairs({ "Skills", "Items", "Cosmetics" }) do
		local podium = findPart(parts, id .. "Podium")
		check(podium ~= nil, "socle " .. id)
		if podium then
			check(podium.Offset.X == centers[id].X, "socle " .. id .. " aligné en X")
			check(podium.Offset.Z == centers[id].Z, "socle " .. id .. " aligné en Z")
			check(podium.Offset.Y == 1.35, "socle " .. id .. " à la hauteur du FocusAnchor")
		end
	end

	-- 11) Attributs obligatoires sur ItemShopVisual.
	local attrs = Shell.GetAttributeSpec()
	check(attrs.ManualDecor == true, "attribut ManualDecor")
	check(attrs.BPW_ItemShopVisual == true, "attribut BPW_ItemShopVisual")
	check(attrs.BPW_PivotYaw == 270, "attribut BPW_PivotYaw")
	check(attrs.BPW_ShellVersion == 1, "attribut BPW_ShellVersion")
	check(attrs.BPW_PivotPosition ~= nil, "attribut BPW_PivotPosition")
	check(attrs.BPW_PivotPosition.X == 34, "BPW_PivotPosition = pivot de configuration")
	check(attrs.BPW_PivotPosition.Z == -230, "BPW_PivotPosition Z = -230")

	-- 12) Façade extérieure : brouillon Studio éditable.
	check(Shell.GetExteriorDraftName() == "ExteriorDraft_v1", "brouillon nommé ExteriorDraft_v1")
	check(
		Shell.ExteriorAlreadyExistsMessage == "ExteriorDraft_v1 already exists. No changes were made.",
		"message anti-écrasement de la façade"
	)

	local draft = Shell.GetExteriorDraftSpec()

	-- Hiérarchie imposée.
	local groups: { [string]: number } = {}
	local paths: { [string]: boolean } = {}
	for _, part in ipairs(draft) do
		local root = string.match(part.Path, "^[^/]+") or part.Path
		groups[root] = (groups[root] or 0) + 1
		paths[part.Path] = true
	end
	for _, name in ipairs({
		"FacadeStructure",
		"ShopSign",
		"SkillsWindow",
		"CosmeticsWindow",
		"EntranceDecor",
		"ExteriorLighting",
	}) do
		check(groups[name] ~= nil, "groupe " .. name)
	end
	for _, path in ipairs({
		"FacadeStructure/LeftColumn",
		"FacadeStructure/RightColumn",
		"FacadeStructure/UpperBand",
		"FacadeStructure/EntranceFrame",
		"FacadeStructure/ArchitecturalTrims",
		"ShopSign/CyanTrim",
		"ShopSign/BagIcon",
		"SkillsWindow/Frame",
		"SkillsWindow/AccentLighting",
		"SkillsWindow/SkillSymbol",
		"CosmeticsWindow/Frame",
		"CosmeticsWindow/AccentLighting",
		"CosmeticsWindow/CosmeticSymbol",
		"EntranceDecor/LeftPost",
		"EntranceDecor/RightPost",
	}) do
		check(paths[path] == true, "sous-groupe " .. path)
	end
	for _, name in ipairs({ "BackPlate", "OuterFrame", "InnerPanel", "TextSurface" }) do
		check(findPart(draft, name) ~= nil, "enseigne : " .. name)
	end
	for _, name in ipairs({ "InteriorBox", "Glass", "Pedestal", "LabelPlate" }) do
		check(findPart(draft, name) ~= nil, "vitrine : " .. name)
	end
	for _, name in ipairs({ "Forecourt", "Threshold", "ThresholdGlow" }) do
		check(findPart(draft, name) ~= nil, "parvis : " .. name)
	end

	-- Budget de performance.
	check(#draft >= 60 and #draft <= 100, "60 à 100 Parts (" .. #draft .. ")")
	local lights, surfaces, glass, neon = 0, 0, 0, 0
	for _, part in ipairs(draft) do
		if part.Light then
			lights += 1
		end
		if part.Text then
			surfaces += 1
		end
		if part.Material == "Glass" then
			glass += 1
		end
		if part.Material == "Neon" then
			neon += 1
			local thinnest = math.min(part.Size.X, math.min(part.Size.Y, part.Size.Z))
			check(thinnest <= 0.4, "accent Neon fin : " .. part.Name)
		end
	end
	print(string.format(
		"[ItemShopVisualTests] façade : %d Parts, %d lumières, %d SurfaceGui",
		#draft,
		lights,
		surfaces
	))
	check(lights <= 4, "au plus 4 vraies lumières (" .. lights .. ")")
	check(lights >= 3, "éclairage suffisant (" .. lights .. ")")
	check(surfaces <= 3, "au plus 3 SurfaceGui (" .. surfaces .. ")")
	check(glass == 2, "une seule vitre par vitrine (" .. glass .. ")")
	check(neon > 0, "accents Neon présents")

	-- Entrée : couloir de 13 studs libre sur 6 studs de parvis.
	local intruders = 0
	for _, part in ipairs(draft) do
		if Shell.IntrudesEntranceCorridor(part) then
			intruders += 1
			warn("[ItemShopVisualTests] empiète sur l'entrée:", part.Name)
		end
	end
	check(intruders == 0, "aucun élément dans le couloir d'entrée")

	-- Emprise : rien au-delà du débord latéral autorisé ni du parvis.
	local sideLimit = shop.Width / 2 + shop.ExteriorSideOverhang
	local frontLimit = shop.Depth / 2 + shop.ForecourtDepth
	for _, part in ipairs(draft) do
		local spanX, spanY = part.Size.X, part.Size.Y
		if part.Rotation and part.Rotation.Z ~= 0 then
			local angle = math.rad(math.abs(part.Rotation.Z))
			spanX = part.Size.X * math.cos(angle) + part.Size.Y * math.sin(angle)
			spanY = part.Size.X * math.sin(angle) + part.Size.Y * math.cos(angle)
		end
		local reach = math.abs(part.Offset.X) + spanX / 2
		check(reach <= sideLimit + 0.001, "dans l'emprise latérale : " .. part.Name)
		check(part.Offset.Z + part.Size.Z / 2 <= frontLimit + 0.001, "dans le parvis : " .. part.Name)
		check(part.Offset.Y - spanY / 2 >= 0.5, "au-dessus du sol : " .. part.Name)
	end

	-- Collisions : structure porteuse seulement, décor traversable.
	local collidable: { [string]: boolean } = {}
	for _, part in ipairs(draft) do
		if part.CanCollide then
			collidable[part.Name] = true
			check(
				part.Offset.Y - part.Size.Y / 2 >= 0.5,
				"pièce collisionnable posée au sol : " .. part.Name
			)
		end
	end
	check(collidable.Forecourt == true, "parvis collisionnable")
	check(collidable.Threshold ~= true, "seuil non collisionnant")
	check(collidable.Glass ~= true, "vitre non collisionnante")
	check(collidable.BackPlate ~= true, "enseigne non collisionnante")
	check(collidable.OuterPilasterShaft == true, "pilastre extérieur collisionnable")
	check(collidable.Jamb ~= true, "montants nommés Jamb<Left|Right>")
	check(collidable.JambLeft == true and collidable.JambRight == true, "montants collisionnables")

	-- Symétrie gauche / droite.
	local leftCount, rightCount = 0, 0
	for _, part in ipairs(draft) do
		if part.Offset.X < -0.01 then
			leftCount += 1
		elseif part.Offset.X > 0.01 then
			rightCount += 1
		end
	end
	check(leftCount == rightCount, "façade symétrique (" .. leftCount .. "/" .. rightCount .. ")")

	-- Le brouillon vit sous Exterior, jamais dans Workspace.ItemShop.
	check(Shell.GetExteriorFolderName() == "Exterior", "brouillon rangé sous Exterior")

	-- 13) Polish v1 : retouches ciblées, sans reconstruction.
	check(Shell.ExteriorPolishVersion == 1, "version de polish = 1")
	check(
		Shell.ExteriorMissingMessage == "ExteriorDraft_v1 not found. No changes were made.",
		"message brouillon absent"
	)
	check(
		Shell.ExteriorPolishAppliedMessage
			== "Exterior polish version 1 is already applied. No changes were made.",
		"message polish déjà appliqué"
	)

	local polish = Shell.GetExteriorPolishSpec()
	check(polish.Version == 1, "spec de polish versionnée")

	-- Toute retouche doit viser une pièce réellement présente dans le brouillon.
	local unknown = 0
	for _, update in ipairs(polish.Updates) do
		if not Shell.HasDraftPart(update.Path, update.Name) then
			unknown += 1
			warn("[ItemShopVisualTests] retouche sans cible:", update.Path .. "/" .. update.Name)
		end
	end
	check(unknown == 0, "chaque retouche vise une pièce existante")

	-- Aucun ajout ne doit entrer en conflit avec une pièce existante.
	local collisions = 0
	for _, addition in ipairs(polish.Additions) do
		if Shell.HasDraftPart(addition.Path, addition.Name) then
			collisions += 1
			warn("[ItemShopVisualTests] ajout en doublon:", addition.Path .. "/" .. addition.Name)
		end
		check(addition.CanCollide == false, "ajout non collisionnable : " .. addition.Name)
	end
	check(collisions == 0, "aucun ajout ne remplace une pièce existante")
	check(
		#polish.Additions >= 15 and #polish.Additions <= 25,
		"15 à 25 Parts ajoutées (" .. #polish.Additions .. ")"
	)

	local polished = Shell.GetPolishedExteriorSpec()
	local polishedLights, polishedSurfaces, polishedGlass = 0, 0, 0
	for _, part in ipairs(polished) do
		if part.Light then
			polishedLights += 1
		end
		if part.Text then
			polishedSurfaces += 1
		end
		if part.Material == "Glass" then
			polishedGlass += 1
		end
		if part.Material == "Neon" then
			local thinnest = math.min(part.Size.X, math.min(part.Size.Y, part.Size.Z))
			check(thinnest <= 0.4, "accent Neon fin après polish : " .. part.Name)
		end
	end
	print(string.format(
		"[ItemShopVisualTests] façade polie : %d Parts (%d modifiées, %d ajoutées), %d lumières",
		#polished,
		#polish.Updates,
		#polish.Additions,
		polishedLights
	))
	check(#polished == #draft + #polish.Additions, "le polish n'ajoute que les nouvelles Parts")
	check(#polished <= 110, "budget total tenu (" .. #polished .. ")")
	check(polishedLights <= 4, "toujours au plus 4 lumières (" .. polishedLights .. ")")
	check(polishedSurfaces == 3, "toujours 3 SurfaceGui")
	check(polishedGlass == 2, "toujours une vitre par vitrine")

	-- L'entrée reste entièrement dégagée après polish.
	local polishedIntruders = 0
	for _, part in ipairs(polished) do
		if Shell.IntrudesEntranceCorridor(part) then
			polishedIntruders += 1
			warn("[ItemShopVisualTests] polish empiète sur l'entrée:", part.Name)
		end
	end
	check(polishedIntruders == 0, "entrée libre après polish")

	-- Emprise, sol et collisions inchangés après polish.
	local polishedCollidable: { [string]: boolean } = {}
	for _, part in ipairs(polished) do
		local spanX, spanY = part.Size.X, part.Size.Y
		if part.Rotation and part.Rotation.Z ~= 0 then
			local angle = math.rad(math.abs(part.Rotation.Z))
			spanX = part.Size.X * math.cos(angle) + part.Size.Y * math.sin(angle)
			spanY = part.Size.X * math.sin(angle) + part.Size.Y * math.cos(angle)
		end
		check(
			math.abs(part.Offset.X) + spanX / 2 <= sideLimit + 0.001,
			"emprise latérale après polish : " .. part.Name
		)
		check(
			part.Offset.Z + part.Size.Z / 2 <= frontLimit + 0.001,
			"parvis après polish : " .. part.Name
		)
		check(part.Offset.Y - spanY / 2 >= 0.5, "au-dessus du sol après polish : " .. part.Name)
		if part.CanCollide then
			polishedCollidable[part.Name] = true
		end
	end
	check(polishedCollidable.Glass ~= true, "vitre toujours traversante")
	check(polishedCollidable.Threshold ~= true, "seuil toujours traversant")
	check(polishedCollidable.Forecourt == true, "parvis toujours collisionnable")
	check(polishedCollidable.JambLeft == true and polishedCollidable.JambRight == true, "montants inchangés")

	-- L'enseigne grandit sans dépasser la largeur du bâtiment.
	local basePlate = findPart(draft, "BackPlate")
	local newPlate = findPart(polished, "BackPlate")
	check(newPlate.Size.X >= basePlate.Size.X * 1.2, "enseigne 20 % plus large au moins")
	check(newPlate.Size.X <= basePlate.Size.X * 1.3, "enseigne pas plus de 30 % plus large")
	check(newPlate.Size.Y >= basePlate.Size.Y * 1.15, "enseigne 15 % plus haute au moins")
	check(newPlate.Size.Y <= basePlate.Size.Y * 1.25, "enseigne pas plus de 25 % plus haute")
	check(newPlate.Size.X <= shop.Width, "enseigne contenue dans la largeur du bâtiment")
	check(newPlate.Offset.X == 0, "enseigne centrée")
	check(newPlate.Offset.Y < basePlate.Offset.Y, "enseigne descendue vers la corniche")
	check(
		newPlate.Offset.Y - newPlate.Size.Y / 2 < basePlate.Offset.Y - basePlate.Size.Y / 2,
		"moins de vide entre l'entrée et l'enseigne"
	)
	local baseText = findPart(draft, "TextSurface")
	local newText = findPart(polished, "TextSurface")
	check(
		newText.Size.X > baseText.Size.X and newText.Size.Y > baseText.Size.Y,
		"texte SHOP plus grand"
	)

	-- Vitrines : ouverture plus large, produits plus gros, fond plus clair.
	local baseGlass = findPart(draft, "Glass")
	local newGlass = findPart(polished, "Glass")
	check(newGlass.Size.X > baseGlass.Size.X, "vitrine plus large")
	check(newGlass.Size.Y > baseGlass.Size.Y, "vitrine plus haute")
	check(
		newGlass.Transparency ~= nil and newGlass.Transparency > 0.4 and newGlass.Transparency < 0.8,
		"vitre toujours légèrement transparente"
	)
	local baseFrame = findPart(draft, "FrameTop")
	local newFrame = findPart(polished, "FrameTop")
	check(newFrame.Size.Y < baseFrame.Size.Y, "cadre de vitrine plus fin")
	for _, symbol in ipairs({ "BoltUpper", "CapCrown" }) do
		local before, after = findPart(draft, symbol), findPart(polished, symbol)
		local ratio = (after.Size.X * after.Size.Y) / (before.Size.X * before.Size.Y)
		check(ratio >= 1.25 and ratio <= 2.2, symbol .. " agrandi de 25 % au moins")
	end
	check(findPart(polished, "OutlineTop") ~= nil, "contour d'accent ajouté aux vitrines")
	check(findPart(polished, "PedestalGlow") ~= nil, "podium éclairé")

	-- Entrée plus accueillante, sans rien poser dans le passage.
	for _, name in ipairs({
		"EntranceSoffit",
		"RevealPanelLeft",
		"RevealPanelRight",
		"EntranceFloorGlow",
		"GoldTrimLeft",
		"GoldTrimRight",
	}) do
		check(findPart(polished, name) ~= nil, "entrée : " .. name)
	end

	-- Les accents dorés s'épaississent sans devenir des surfaces.
	local baseGold = findPart(draft, "CorniceGoldTrim")
	local newGold = findPart(polished, "CorniceGoldTrim")
	check(newGold.Size.Y > baseGold.Size.Y, "ligne dorée sous corniche plus épaisse")
	check(newGold.Size.Y <= 0.4, "ligne dorée toujours fine")
	check(findPart(polished, "OuterGoldBand") ~= nil, "accents dorés près des colonnes")

	-- Les couches adjacentes ne partagent plus la même couleur.
	local function sameColor(a: any, b: any): boolean
		return a.Color.R == b.Color.R and a.Color.G == b.Color.G and a.Color.B == b.Color.B
	end
	for _, pair in ipairs({
		{ "BandLower", "BandMain" },
		{ "BandMain", "BandInset" },
		{ "BandMain", "Cornice" },
		{ "OuterPilasterShaft", "OuterPilasterCap" },
		{ "InteriorBox", "FrameTop" },
		{ "BackPlate", "OuterFrame" },
		{ "OuterFrame", "InnerPanel" },
	}) do
		check(
			not sameColor(findPart(polished, pair[1]), findPart(polished, pair[2])),
			"contraste " .. pair[1] .. " / " .. pair[2]
		)
	end

	-- 14) Intérieur : aménagement artistique Studio-first.
	check(Shell.GetInteriorDraftName() == "InteriorDraft_v1", "brouillon nommé InteriorDraft_v1")
	check(Shell.GetInteriorFolderName() == "Interior", "intérieur rangé sous Interior")
	check(
		Shell.InteriorAlreadyExistsMessage == "InteriorDraft_v1 already exists. No changes were made.",
		"message anti-écrasement de l'intérieur"
	)

	local interior = Shell.GetInteriorDraftSpec()

	local interiorGroups: { [string]: number } = {}
	local interiorPaths: { [string]: boolean } = {}
	for _, part in ipairs(interior) do
		local root = string.match(part.Path, "^[^/]+") or part.Path
		interiorGroups[root] = (interiorGroups[root] or 0) + 1
		interiorPaths[part.Path] = true
		check(part.Script == nil, "aucun script dans la spec : " .. part.Name)
	end
	for _, name in ipairs({
		"Floor",
		"Ceiling",
		"EntryTransition",
		"SkillsSection",
		"ItemsSection",
		"CosmeticsSection",
		"CentralDecor",
		"InteriorLighting",
	}) do
		check(interiorGroups[name] ~= nil, "groupe intérieur " .. name)
	end
	for _, group in ipairs({ "SkillsSection", "ItemsSection", "CosmeticsSection" }) do
		for _, child in ipairs({
			"WallPanels",
			"Header",
			"MainDisplayBackdrop",
			"LeftSecondaryDisplay",
			"RightSecondaryDisplay",
			"AccentLights",
			"MainPodium",
		}) do
			check(interiorPaths[group .. "/" .. child] == true, "sous-groupe " .. group .. "/" .. child)
		end
	end
	check(interiorPaths["SkillsSection/SkillSymbols"] == true, "symboles Skills")
	check(interiorPaths["ItemsSection/ItemSymbols"] == true, "symboles Items")
	check(interiorPaths["ItemsSection/CentralArch"] == true, "arche centrale Items")
	check(interiorPaths["CosmeticsSection/CosmeticSymbols"] == true, "symboles Cosmetics")

	-- Budget.
	local interiorLights, interiorSurfaces, interiorTitles = 0, 0, {}
	for _, part in ipairs(interior) do
		if part.Light then
			interiorLights += 1
		end
		if part.Text then
			interiorSurfaces += 1
			interiorTitles[part.Text] = true
		end
		if part.Material == "Neon" then
			local thinnest = math.min(part.Size.X, math.min(part.Size.Y, part.Size.Z))
			check(thinnest <= 0.4, "accent Neon fin : " .. part.Name)
		end
	end
	print(string.format(
		"[ItemShopVisualTests] intérieur : %d Parts, %d lumières, %d SurfaceGui",
		#interior,
		interiorLights,
		interiorSurfaces
	))
	check(#interior >= 100 and #interior <= 160, "100 à 160 Parts (" .. #interior .. ")")
	check(interiorLights >= 6 and interiorLights <= 8, "6 à 8 lumières (" .. interiorLights .. ")")
	check(interiorSurfaces >= 3 and interiorSurfaces <= 6, "3 à 6 SurfaceGui (" .. interiorSurfaces .. ")")
	for _, title in ipairs({ "SKILLS", "ITEMS", "COSMETICS" }) do
		check(interiorTitles[title] == true, "titre " .. title)
	end

	-- Couloir central libre, de l'entrée jusqu'au socle ITEMS.
	local corridor = Shell.GetInteriorCorridor()
	check(corridor.MaxX - corridor.MinX == shop.DoorWidth, "couloir large de 13 studs")
	local corridorIntruders = 0
	for _, part in ipairs(interior) do
		if Shell.OverlapsZone(part, corridor) then
			corridorIntruders += 1
			warn("[ItemShopVisualTests] obstacle dans le couloir:", part.Name)
		end
		if Shell.IntrudesEntranceCorridor(part) then
			corridorIntruders += 1
			warn("[ItemShopVisualTests] obstacle devant l'entrée:", part.Name)
		end
	end
	check(corridorIntruders == 0, "couloir central et entrée dégagés")

	-- Rien entre la caméra et le présentoir, ni au-dessus du cadrage.
	local rays = Shell.GetCameraRays()
	check(#rays == 3, "trois axes de caméra")
	local blockedRays = 0
	for _, ray in ipairs(rays) do
		for _, part in ipairs(interior) do
			if Shell.SegmentHitsPart(ray.From, ray.To, part) then
				blockedRays += 1
				warn("[ItemShopVisualTests] " .. ray.Id .. " masqué par:", part.Name)
			end
		end
	end
	check(blockedRays == 0, "aucun obstacle sur les axes caméra → présentoir")

	-- Les rayons partent bien des cadrages validés de ItemShopBuilder.
	local skillsRay = rays[1]
	check(skillsRay.Id == "Skills", "premier axe : Skills")
	check(skillsRay.From.X == centers.Skills.X + 8.8, "caméra Skills à 8,8 studs")
	check(skillsRay.From.Y == 5.4, "caméra Skills à 5,4 studs de haut")
	check(skillsRay.Target.Y == 3.3, "cible Skills à 3,3 studs")

	-- Podiums centrés sur les FocusAnchor, sans les déplacer.
	for _, entry in ipairs({
		{ Group = "SkillsSection", Id = "Skills" },
		{ Group = "ItemsSection", Id = "Items" },
		{ Group = "CosmeticsSection", Id = "Cosmetics" },
	}) do
		local base = nil
		for _, part in ipairs(interior) do
			if part.Path == entry.Group .. "/MainPodium" and part.Name == "PodiumBase" then
				base = part
			end
		end
		check(base ~= nil, "socle principal " .. entry.Id)
		if base then
			check(base.Offset.X == centers[entry.Id].X, "socle " .. entry.Id .. " aligné en X")
			check(base.Offset.Z == centers[entry.Id].Z, "socle " .. entry.Id .. " aligné en Z")
			-- Recouvre le socle simple de la coque initiale (largeur 4,6 / 5,4).
			local shellPodium = findPart(parts, entry.Id .. "Podium")
			check(base.Size.X > shellPodium.Size.X, "socle " .. entry.Id .. " recouvre celui de la coque")
			local top = base.Offset.Y + base.Size.Y / 2
			check(top >= shellPodium.Offset.Y + shellPodium.Size.Y / 2, "socle " .. entry.Id .. " plus haut")
		end
	end

	-- Sol plat et collisions cohérentes.
	local interiorCollidable = {}
	for _, part in ipairs(interior) do
		local bounds = Shell.GetPartBounds(part)
		if string.match(part.Path, "^Floor") then
			check(bounds.MaxY <= 1.3, "sol plat : " .. part.Name)
		end
		if part.CanCollide then
			table.insert(interiorCollidable, part)
		end
		check(bounds.MinY >= 0.9, "rien sous le plancher : " .. part.Name)
		check(bounds.MaxY <= 15.0, "rien au-dessus du plafond : " .. part.Name)
		check(math.abs(bounds.MinX) <= shop.Width / 2, "dans les murs (X) : " .. part.Name)
		check(math.abs(bounds.MaxX) <= shop.Width / 2, "dans les murs (X) : " .. part.Name)
		check(math.abs(bounds.MinZ) <= shop.Depth / 2, "dans les murs (Z) : " .. part.Name)
		check(math.abs(bounds.MaxZ) <= shop.Depth / 2, "dans les murs (Z) : " .. part.Name)
	end
	check(#interiorCollidable >= 1, "au moins le sol est collisionnable")
	for _, part in ipairs(interiorCollidable) do
		check(
			part.Name == "FloorBase" or string.match(part.Path, "Bench") ~= nil,
			"collision limitée au sol et aux banquettes : " .. part.Name
		)
	end

	-- Aucun élément collisionnable près des trois prompts.
	local promptAnchors = {
		Skills = Vector3.new(-shop.Width / 2 + shop.WallThickness / 2 + 2.2, 3.5, 0),
		Items = Vector3.new(0, 3.5, -shop.Depth / 2 + shop.WallThickness / 2 + 2.2),
		Cosmetics = Vector3.new(shop.Width / 2 - shop.WallThickness / 2 - 2.2, 3.5, 0),
	}
	for id, anchor in pairs(promptAnchors) do
		for _, part in ipairs(interiorCollidable) do
			local dx = part.Offset.X - anchor.X
			local dz = part.Offset.Z - anchor.Z
			if part.Name ~= "FloorBase" then
				check(
					math.sqrt(dx * dx + dz * dz) >= 6,
					"prompt " .. id .. " dégagé de " .. part.Name
				)
			end
		end
	end

	-- Symétrie raisonnable entre Skills et Cosmetics.
	local skillsCount, cosmeticsCount = 0, 0
	for _, part in ipairs(interior) do
		if string.match(part.Path, "^SkillsSection") then
			skillsCount += 1
			check(part.Offset.X < 0, "élément Skills à gauche : " .. part.Name)
		elseif string.match(part.Path, "^CosmeticsSection") then
			cosmeticsCount += 1
			check(part.Offset.X > 0, "élément Cosmetics à droite : " .. part.Name)
		end
	end
	check(skillsCount == cosmeticsCount, "sections latérales symétriques (" .. skillsCount .. "/" .. cosmeticsCount .. ")")

	if failed == 0 then
		print("[ItemShopVisualTests] OK")
		return true
	end
	return false
end

return ItemShopVisualTests
