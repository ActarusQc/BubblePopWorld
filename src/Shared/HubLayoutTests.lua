--!strict
-- Validations géométriques du hub central (Concept 2).
-- Vérifie ce qu'un œil ne peut pas garantir : symétrie, pavage exact de l'octogone,
-- absence de chevauchement, ouverture frontale libre, jonction escalier ↔ bulles,
-- et cohérence des cellules de bulles réservées.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local HubLayout = require(Shared.HubLayout)
local ZoneDefs = require(Shared.ZoneDefs)
local RearHubLogic = require(Shared.RearHubLogic)

local HubLayoutTests = {}

local H = GameConfig.Hub
local G = GameConfig.Grid

type Footprint = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

-- HubLayout.GetModules expose déjà des tailles alignées sur les axes monde.
local function footprintOf(center: Vector3, size: Vector3): Footprint
	return {
		MinX = center.X - size.X / 2,
		MaxX = center.X + size.X / 2,
		MinZ = center.Z - size.Z / 2,
		MaxZ = center.Z + size.Z / 2,
	}
end

local function overlaps(a: Footprint, b: Footprint): boolean
	return a.MinX < b.MaxX and b.MinX < a.MaxX and a.MinZ < b.MaxZ and b.MinZ < a.MaxZ
end

local function cornersInsideDeck(center: Vector3, size: Vector3): boolean
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			if not HubLayout.IsInsideDeckFootprint(center.X + sx * size.X / 2, center.Z + sz * size.Z / 2) then
				return false
			end
		end
	end
	return true
end

-- Emprise circulaire : 8 directions, jamais les coins d'un carré.
local function discInsideDeck(center: Vector3, diameter: number): boolean
	local r = diameter / 2
	local diag = r * math.sqrt(2) / 2
	local offsets = {
		Vector3.new(r, 0, 0),
		Vector3.new(-r, 0, 0),
		Vector3.new(0, 0, r),
		Vector3.new(0, 0, -r),
		Vector3.new(diag, 0, diag),
		Vector3.new(diag, 0, -diag),
		Vector3.new(-diag, 0, diag),
		Vector3.new(-diag, 0, -diag),
	}
	for _, offset in ipairs(offsets) do
		if not HubLayout.IsInsideDeckFootprint(center.X + offset.X, center.Z + offset.Z) then
			return false
		end
	end
	return true
end

function HubLayoutTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[HubLayoutTests] FAIL:", msg)
			ok = false
		end
	end

	if not H.Enabled then
		print("[HubLayoutTests] SKIP (Hub.Enabled = false)")
		return true
	end

	local rear = HubLayout.IsRearPlacement and HubLayout.IsRearPlacement()

	--------------------------------------------------------------------
	-- Ancrage et hauteurs
	--------------------------------------------------------------------
	if rear then
		local room = RearHubLogic.GetOriginalRoomBounds()
		check(HubLayout.Center.X == G.Origin.X and HubLayout.Center.Z > G.Origin.Z,
			"hub RearOfGrid : même X, Z au nord du centre")
		check(HubLayout.Center.Z < room.MaxZ,
			"hub pivot dans la salle originale (pas d'extension)")
		check(HubLayout.FrontSign == -1, "FrontSign rear = -1")
		local stairsFront = HubLayout.GetStairsRect().MinZ
		check(stairsFront < room.MaxZ, "escalier dans la salle originale")
		check(stairsFront > room.MinZ, "escalier pas hors salle sud")
	else
		check(HubLayout.Center.X == G.Origin.X and HubLayout.Center.Z == G.Origin.Z,
			"le hub est centré sur l'origine de la planche")
	end
	local bubbleTopY = G.Origin.Y + G.BubbleSize.Y / 2
	check(HubLayout.Deck.TopY > bubbleTopY,
		"le deck domine le sommet des bulles")
	check(HubLayout.Deck.TopY - bubbleTopY <= 8,
		"le deck reste légèrement surélevé (pas une tour)")

	--------------------------------------------------------------------
	-- Symétrie exacte gauche / droite
	--------------------------------------------------------------------
	local sell = HubLayout.SellPlatform
	local shop = HubLayout.ShopPlatform
	local hubX = HubLayout.Center.X
	local hubZ = HubLayout.Center.Z
	check(math.abs((sell.Center.X - hubX) + (shop.Center.X - hubX)) < 1e-6,
		"plateformes SELL / SHOP symétriques en X")
	check(sell.Center.Z == shop.Center.Z and sell.Center.Y == shop.Center.Y,
		"plateformes SELL / SHOP alignées")
	check(sell.Size == shop.Size, "plateformes SELL / SHOP de même taille")
	check(sell.Center.X > hubX, "SELL à +X relative hub")
	check(shop.Center.X < hubX, "SHOP à -X relative hub")

	local top = HubLayout.TopBoard
	local rules = HubLayout.RulesBoard
	check(math.abs((top.Center.X - hubX) + (rules.Center.X - hubX)) < 1e-6,
		"panneaux TOP 3 / RULES symétriques")
	check(top.Center.Z == rules.Center.Z and top.Center.Y == rules.Center.Y,
		"panneaux TOP 3 / RULES alignés")
	check(top.Center.X < hubX, "TOP 3 à gauche")
	if rear then
		check(top.Center.Z > hubZ and rules.Center.Z > hubZ,
			"panneaux derrière le plateau (arrière +Z / fond)")
	else
		check(top.Center.Z < hubZ and rules.Center.Z < hubZ,
			"panneaux à l'arrière (-Z)")
	end
	check(top.BottomY > HubLayout.Deck.TopY, "panneaux surélevés au-dessus du deck")

	--------------------------------------------------------------------
	-- Spawn face aux bulles
	--------------------------------------------------------------------
	check(math.abs(HubLayout.Spawn.Center.X - hubX) < 1e-6, "spawn centré en X")
	if rear then
		check(HubLayout.Spawn.Center.Z < hubZ, "spawn vers l'avant du deck (bulles)")
		local spawnLook = HubLayout.GetSpawnCFrame().LookVector
		check(spawnLook.Z < -0.9 and math.abs(spawnLook.X) < 0.15,
			"le joueur apparaît face aux bulles (-Z)")
	else
		check(HubLayout.Spawn.Center.Z > hubZ, "spawn vers l'avant du deck")
		local spawnLook = HubLayout.GetSpawnCFrame().LookVector
		check(spawnLook.Z > 0.9 and math.abs(spawnLook.X) < 0.1,
			"le joueur apparaît face aux bulles (+Z)")
	end
	check(HubLayout.SellPlatform.Center.X > hubX, "SELL +X")
	check(HubLayout.ShopPlatform.Center.X < hubX, "SHOP -X")

	--------------------------------------------------------------------
	-- Pavage exact de l'octogone (3 bandes + 4 plaques de coin)
	--------------------------------------------------------------------
	local slabs = HubLayout.GetDeckSlabs()
	check(#slabs == 7, "deck = 3 bandes + 4 chanfreins")
	local area = 0
	local wedgeCount = 0
	for _, slab in ipairs(slabs) do
		if slab.IsWedge then
			wedgeCount += 1
			-- WedgePart posé à plat : plaque triangulaire (Size.Y × Size.Z / 2).
			area += slab.Size.Y * slab.Size.Z / 2
			check(math.abs(slab.Size.X - HubLayout.Deck.Thickness) < 1e-6,
				"épaisseur de la plaque de coin " .. slab.Name)
		else
			area += slab.Size.X * slab.Size.Z
			check(math.abs(slab.Size.Y - HubLayout.Deck.Thickness) < 1e-6,
				"épaisseur de la bande " .. slab.Name)
		end
		check(math.abs(slab.Center.Y - (HubLayout.Deck.TopY - HubLayout.Deck.Thickness / 2)) < 1e-6,
			"dalle " .. slab.Name .. " au niveau du deck")
	end
	check(wedgeCount == 4, "4 plaques de coin")
	local expectedArea = H.DeckHalfX * 2 * H.DeckHalfZ * 2 - 4 * (H.DeckChamfer * H.DeckChamfer / 2)
	check(math.abs(area - expectedArea) < 0.01,
		string.format("surface du deck = octogone (%.1f attendu, %.1f obtenu)", expectedArea, area))

	local plinth = HubLayout.GetPlinthSlabs()
	check(#plinth == 7, "socle intermédiaire également octogonal")
	local foundationSize, foundationCenter = HubLayout.GetFoundation()
	local playFloorTopY = G.Origin.Y - G.BubbleSize.Y * 0.35
	check(foundationCenter.Y - foundationSize.Y / 2 < playFloorTopY,
		"la fondation descend jusqu'au plancher de jeu (aucun hub flottant)")
	check(foundationSize.X < H.DeckHalfX * 2 and foundationSize.Z < H.DeckHalfZ * 2,
		"la fondation est rentrée sous le deck (silhouette étagée)")

	--------------------------------------------------------------------
	-- Garde-corps : périmètre fermé sauf l'ouverture frontale
	--------------------------------------------------------------------
	local rails = HubLayout.GetRailings()
	check(#rails == 9, "9 segments de garde-corps (2 avant + arrière + 2 côtés + 4 coins)")
	local openingHalf = HubLayout.GetFrontOpeningHalfWidth()
	local frontZ = HubLayout.FrontWorldZ(hubZ, H.DeckHalfZ)
	for _, rail in ipairs(rails) do
		local isFrontRow = math.abs(rail.Center.Z - HubLayout.FrontWorldZ(hubZ, H.DeckHalfZ - H.RailingThickness / 2)) < 0.05
		if isFrontRow then
			local innerEdge = math.abs(rail.Center.X - hubX) - rail.Size.X / 2
			check(innerEdge >= openingHalf - 0.01,
				"aucun garde-corps devant l'ouverture : " .. rail.Name)
		end
		check(rail.Size.Y == H.RailingHeight, "hauteur de garde-corps constante : " .. rail.Name)
	end
	check(openingHalf * 2 >= H.Stairs.Width,
		"l'ouverture est au moins aussi large que l'escalier")

	--------------------------------------------------------------------
	-- Escalier : descente régulière et jonction propre avec les bulles
	--------------------------------------------------------------------
	local steps = HubLayout.GetStairSteps()
	check(#steps == H.Stairs.StepCount, "nombre de marches conforme à la config")
	local previousTop = HubLayout.Deck.TopY
	local previousZ = HubLayout.FrontWorldZ(hubZ, H.DeckHalfZ)
	for _, step in ipairs(steps) do
		check(step.TopY < previousTop, "marche " .. step.Index .. " descend")
		check(math.abs((previousTop - step.TopY) - H.Stairs.StepRise) < 1e-6,
			"marche " .. step.Index .. " : hauteur régulière")
		check(step.TopY - (step.Center.Y - step.Size.Y / 2) > H.Stairs.StepRise,
			"marche " .. step.Index .. " : épaisseur suffisante (aucun trou)")
		if rear then
			check(step.Center.Z < previousZ, "marche " .. step.Index .. " avance vers -Z (bulles)")
		else
			check(step.Center.Z > previousZ, "marche " .. step.Index .. " avance vers +Z")
		end
		previousTop = step.TopY
		previousZ = step.Center.Z
	end
	check(H.Stairs.StepRise <= 2, "marche franchissable à pied")

	-- Le joueur marche sur les dômes : la descente doit finir à leur sommet.
	local bubbleWalkY = bubbleTopY + 0.35
	local stairsBottom = HubLayout.GetStairsBottomY()
	check(math.abs(stairsBottom - bubbleWalkY) <= 0.4,
		string.format("bas de l'escalier au niveau des bulles (%.2f vs %.2f)", stairsBottom, bubbleWalkY))

	--------------------------------------------------------------------
	-- Corridor frontal libre : rien ne masque l'aire de jeu
	--------------------------------------------------------------------
	local stairsRect = HubLayout.GetStairsRect()
	local corridor: Footprint = {
		MinX = stairsRect.MinX,
		MaxX = stairsRect.MaxX,
		MinZ = math.min(HubLayout.Spawn.Center.Z, stairsRect.MinZ),
		MaxZ = math.max(HubLayout.Spawn.Center.Z, stairsRect.MaxZ),
	}
	for _, spec in ipairs(HubLayout.GetModules()) do
		if spec.Kind == "Sign" then
			check(not overlaps(footprintOf(spec.Center, spec.Size), corridor),
				spec.Name .. " ne bouche pas la vue vers les bulles")
		end
	end

	--------------------------------------------------------------------
	-- Modules : dans l'emprise et sans collision entre eux
	--------------------------------------------------------------------
	local outsideDeckAllowed = {
		Stairs = true,
		StairsLanding = true,
	}
	local exclusiveModules = {
		"SpawnMedallion",
		"LoopPanel",
		"SellStand",
		"ShopStand",
		"TopBoard",
		"RulesBoard",
		"TransitAlcove",
	}
	local byName: { [string]: any } = {}
	for _, spec in ipairs(HubLayout.GetModules()) do
		byName[spec.Name] = spec
		if not outsideDeckAllowed[spec.Name] and spec.Name ~= "Deck" then
			if spec.Circular then
				check(discInsideDeck(spec.Center, spec.Size.X),
					spec.Name .. " (disque) tient dans l'emprise du deck")
			else
				check(cornersInsideDeck(spec.Center, spec.Size),
					spec.Name .. " tient dans l'emprise du deck")
			end
		end
	end
	for i = 1, #exclusiveModules do
		for j = i + 1, #exclusiveModules do
			local a = byName[exclusiveModules[i]]
			local b = byName[exclusiveModules[j]]
			if a and b then
				check(not overlaps(footprintOf(a.Center, a.Size), footprintOf(b.Center, b.Size)),
					exclusiveModules[i] .. " et " .. exclusiveModules[j] .. " ne se chevauchent pas")
			end
		end
	end

	--------------------------------------------------------------------
	-- Accessibilité : tout est à quelques secondes du spawn
	--------------------------------------------------------------------
	local function flatDistance(a: Vector3, b: Vector3): number
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end
	local spawnPos = HubLayout.Spawn.Center
	local sellZoneCF = HubLayout.GetSellZoneCFrame()
	local shopOrigin = HubLayout.GetShopOrigin()
	check(flatDistance(spawnPos, sellZoneCF.Position) <= 45, "SELL atteignable en quelques secondes")
	check(flatDistance(spawnPos, shopOrigin) <= 45, "SHOP atteignable en quelques secondes")
	local bubbleApproachZ = if rear then stairsRect.MinZ else stairsRect.MaxZ
	check(flatDistance(spawnPos, Vector3.new(spawnPos.X, 0, bubbleApproachZ)) <= 50,
		"les premières bulles sont à moins de 10 secondes")

	-- La zone de vente doit contenir le torse d'un joueur debout sur la plateforme.
	local standingY = HubLayout.SellPlatform.TopY + 3
	local zoneHalfY = H.Sell.ZoneSize.Y / 2
	check(standingY >= sellZoneCF.Position.Y - zoneHalfY and standingY <= sellZoneCF.Position.Y + zoneHalfY,
		"SellZone couvre la hauteur du torse (vente automatique)")

	--------------------------------------------------------------------
	-- Bubble Transit : portail arrière du hub 3D
	--------------------------------------------------------------------
	local transitPos = HubLayout.GetTransitPosition()
	local maxDist = HubLayout.GetBubbleTransitMaxActivationDistance()
	check(flatDistance(spawnPos, transitPos) >= 25,
		"portail transit assez loin du spawn (aucun menu à l'apparition)")
	if rear then
		check(math.abs(transitPos.X - hubX) < 0.05 and transitPos.Z > hubZ,
			"transit au centre arrière (fond +Z)")
	else
		check(math.abs(transitPos.X - hubX) < 0.05 and transitPos.Z < hubZ,
			"transit au centre arrière")
	end
	check(maxDist == 5.5, "MaxActivationDistance 5.5")
	check(discInsideDeck(transitPos, 6),
		"zone transit sur le deck")
	local triggerCF = HubLayout.GetBubbleTransitTriggerCFrame()
	if rear then
		check(triggerCF.Position.Z > HubLayout.Center.Z, "fallback trigger côté arrière layout")
	else
		check(triggerCF.Position.Z < HubLayout.Center.Z, "fallback trigger côté arrière layout")
	end
	check(math.abs(triggerCF.Position.X - HubLayout.Center.X) < 0.05, "fallback trigger centré X")


	--------------------------------------------------------------------
	-- Cellules de bulles réservées
	--------------------------------------------------------------------
	local sizeX, sizeZ = ZoneDefs.GetGridSize("ClassicZone")
	local totalCells = sizeX * sizeZ
	local reserved = HubLayout.CountReservedCells("ClassicZone")
	local reserved = HubLayout.CountReservedCells("ClassicZone")
	local halfB = math.max(G.BubbleSize.X, G.BubbleSize.Z) / 2
	local maxCenterZ = G.Origin.Z + (sizeZ - sizeZ / 2) * G.Spacing
	-- RearOfGrid intégré : emprise dans dernières rangées (intersection bulles attendue).
	if rear then
		local place = RearHubLogic.ComputeRearPlacement()
		check(reserved > 0, "rear intégré : cellules sous plateau réservées")
		check(
			HubLayout.GetPlatformFrontZ() < place.BubbleOuterMaxZ + 1,
			"façade escaliers DANS / collée à la grille (pas hors extension)"
		)
		check(place.PlatformRearZ <= place.OriginalRoomRearZ + 0.05, "rear plateau <= fond original")
	end
	check(reserved / totalCells < 0.35,
		string.format("le hub consomme moins de 35 %% de la planche (%d / %d)", reserved, totalCells))
	if not rear then
		check(reserved > 0, "des cellules sont réservées sous le hub")
	end
	if rear then
		check(not HubLayout.IsCellReserved("ClassicZone", math.floor(sizeX / 2), math.floor(sizeZ / 2)),
			"la cellule centrale est jouable (plateau au fond)")
	else
		check(HubLayout.IsCellReserved("ClassicZone", math.floor(sizeX / 2), math.floor(sizeZ / 2)),
			"la cellule centrale est réservée")
	end
	check(not HubLayout.IsCellReserved("ClassicZone", 1, 1),
		"les coins de la planche restent jouables")
	check(not HubLayout.IsCellReserved("SummerZone", 1, 1),
		"la Summer Zone n'est jamais impactée")

	-- Aucune bulle ne doit traverser la structure ni l'escalier. Le palier est traité
	-- à part : il dépasse volontairement la zone réservée pour rejoindre les bulles.
	for _, spec in ipairs(HubLayout.GetModules()) do
		if spec.Name ~= "StairsLanding" then
			if not rear then
				check(HubLayout.IsWorldPointReserved(spec.Center.X, spec.Center.Z),
					spec.Name .. " repose sur une emprise réservée")
			end
		end
	end

	-- Jonction palier ↔ bulles.
	local firstLiveZ = HubLayout.GetFirstLiveBubbleEdgeZ()
	local landingSize, landingCenter = HubLayout.GetLanding()
	if rear then
		check(stairsRect.MinZ - firstLiveZ <= 4.5 and stairsRect.MinZ - firstLiveZ >= -1,
			"dégagement bulles → escaliers ≤ ~4 (intégré)")
	else
		check(firstLiveZ > stairsRect.MaxZ, "une rangée de bulles subsiste devant l'escalier")
		local landingFrontZ = landingCenter.Z + landingSize.Z / 2
		check(math.abs(landingFrontZ - firstLiveZ) < 0.5,
			string.format("palier au contact des bulles (%.2f vs %.2f)", landingFrontZ, firstLiveZ))
	end
	check(landingSize.Z >= H.Stairs.LandingDepth - 0.01,
		"le palier respecte la profondeur minimale de config")
	check(math.abs(landingCenter.Y + landingSize.Y / 2 - HubLayout.GetStairsBottomY()) < 1e-6,
		"palier au niveau de la dernière marche")

	local landingRect: Footprint = {
		MinX = landingCenter.X - landingSize.X / 2,
		MaxX = landingCenter.X + landingSize.X / 2,
		MinZ = landingCenter.Z - landingSize.Z / 2,
		MaxZ = landingCenter.Z + landingSize.Z / 2,
	}
	local intruders = 0
	for x = 1, sizeX do
		for z = 1, sizeZ do
			if not HubLayout.IsCellReserved("ClassicZone", x, z) then
				local pos = ZoneDefs.CellToWorld(x, z, "ClassicZone")
				local bubble: Footprint = {
					MinX = pos.X - G.BubbleSize.X / 2,
					MaxX = pos.X + G.BubbleSize.X / 2,
					MinZ = pos.Z - G.BubbleSize.Z / 2,
					MaxZ = pos.Z + G.BubbleSize.Z / 2,
				}
				if overlaps(bubble, landingRect) then
					intruders += 1
				end
			end
		end
	end
	check(intruders == 0,
		string.format("le palier ne traverse aucune bulle vivante (%d)", intruders))

	--------------------------------------------------------------------
	-- Pipeline assets importés
	--------------------------------------------------------------------
	check(HubLayout.ShouldBuildCodeVisual("SellStand", false) == true,
		"sans asset importé, le code construit la forme")
	check(HubLayout.ShouldBuildCodeVisual("Inexistant", true) == true,
		"clé d'asset inconnue → construction par code")
	for key, spec in pairs(H.Assets) do
		check(type(spec.ModelName) == "string" and spec.ModelName ~= "",
			"asset " .. key .. " : nom de modèle défini")
		check(HubLayout.GetAssetModelName(key) == spec.ModelName,
			"asset " .. key .. " : nom résolu")
	end

	--------------------------------------------------------------------
	-- Proxies de collision FinalHub
	--------------------------------------------------------------------
	local proxies = HubLayout.GetFinalHubCollisionProxies()
	check(#proxies == 4, "4 sols FinalHub")
	local byProxy: { [string]: any } = {}
	for _, p in ipairs(proxies) do
		byProxy[p.Name] = p
	end
	check(byProxy.MainHubFloor ~= nil, "MainHubFloor présent")
	check(byProxy.MainHubFloor.Size == Vector3.new(58, 1, 42), "MainHubFloor size")
	check(
		math.abs(byProxy.MainHubFloor.Center.X - hubX) < 1e-6
			and math.abs(byProxy.MainHubFloor.Center.Z - hubZ) < 1e-6,
		"MainHubFloor center suivi du hub"
	)
	check(math.abs(byProxy.MainHubFloor.TopY - 12) < 1e-6, "MainHubFloor top Y = 12")
	check(byProxy.SellFloor ~= nil and math.abs(byProxy.SellFloor.TopY - 13.2) < 1e-6,
		"SellFloor top Y = 13.2")
	check(math.abs(byProxy.SellFloor.Center.X - (hubX + 27)) < 1e-6, "SellFloor center (+X)")
	check(byProxy.ShopFloor ~= nil and math.abs(byProxy.ShopFloor.TopY - 13.2) < 1e-6,
		"ShopFloor top Y = 13.2")
	check(math.abs(byProxy.ShopFloor.Center.X - (hubX - 27)) < 1e-6, "ShopFloor center (-X)")
	check(byProxy.TransitFloor ~= nil and math.abs(byProxy.TransitFloor.TopY - 12) < 1e-6,
		"TransitFloor top Y = 12")
	check(
		math.abs(byProxy.TransitFloor.Center.Z - (hubZ + (-19) * HubLayout.FrontSign)) < 1e-6,
		"TransitFloor center suivi FrontSign"
	)
	local corridor = HubLayout.GetCirculationCorridor()
	check(corridor.MaxX - corridor.MinX >= 6, "corridor largeur ≥ 6")
	check(H.DebugCollisionProxies == false, "DebugCollisionProxies off par défaut")

	if ok then
		print(string.format(
			"[HubLayoutTests] OK (deck %.0f×%.0f, %d cellules réservées sur %d)",
			H.DeckHalfX * 2,
			H.DeckHalfZ * 2,
			reserved,
			totalCells
		))
	end
	return ok
end

return HubLayoutTests
