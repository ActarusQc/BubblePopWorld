--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = require(Shared.AmusementParkCollisionLogic)

local AmusementParkCollisionLogicTests = {}

function AmusementParkCollisionLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[AmusementParkCollisionLogicTests] FAIL:", msg)
			ok = false
		end
	end

	for _, name in ipairs({
		"EntreeParc",
		"StationEmbarquement",
		"GrandeRoue",
		"Ascenceur",
		"AscenseurCommun",
		"Carousel",
		"KiosqueBonbons",
		"BubbleBlaster",
		"RollABall",
	}) do
		check(Logic.ShouldMeshCollide(name) == true, name .. " doit être solide")
	end
	check(Logic.ShouldMeshCollide("Chapiteau") == false, "chapiteau: mesh visuel, collision proxy")
	check(Logic.ShouldMeshCollide("WagonModele") == false, "WagonModele reste non solide")

	check(Logic.NeedsProxyInteriorCollision("Chapiteau") == true, "chapiteau utilise des parois proxy")
	check(Logic.NeedsProxyInteriorCollision("GrandeRoue") == false, "grande roue sans parois proxy")
	check(math.abs(Logic.EntranceAngleFromLocalLook(Vector3.new(0, 0, -1)) + math.pi / 2) < 0.01, "porte face -Z")
	check(Logic.IsTentDoorwayAngle(-math.pi / 2, -math.pi / 2) == true, "axe de la porte ouvert")
	check(Logic.IsTentDoorwayAngle(0, -math.pi / 2) == false, "flanc du chapiteau fermé")
	check(Logic.IsTentDoorwayAngle(math.pi, -math.pi / 2) == false, "fond du chapiteau fermé")
	check(Logic.TentDoorwayHalfAngle() >= 0.8, "ouverture assez large pour les rideaux Tripo")
	check(
		Logic.ShouldHideTentDoorwayPart(Vector3.new(0, 5, -12), Vector3.new(8, 10, 2), Color3.new(0, 0, 0), 15, -math.pi / 2, 14) == true,
		"petit occluder sombre de porte masqué"
	)
	check(
		Logic.ShouldHideTentDoorwayPart(Vector3.new(0, 5, 0), Vector3.new(8, 10, 2), Color3.new(0, 0, 0), 15, -math.pi / 2, 14) == false,
		"centre du chapiteau conservé"
	)
	check(
		Logic.ShouldHideTentDoorwayPart(Vector3.new(12, 5, 0), Vector3.new(8, 10, 2), Color3.new(0, 0, 0), 15, -math.pi / 2, 14) == false,
		"flanc hors porte conservé"
	)
	check(
		Logic.ShouldHideTentDoorwayPart(Vector3.new(0, 5, -12), Vector3.new(40, 30, 40), Color3.new(0, 0, 0), 15, -math.pi / 2, 14) == false,
		"coque Tripo jamais masquée"
	)
	check(Logic.ShouldConcealTripoTentInterior() == false, "design Tripo conservé")
	check(Logic.NeedsInteriorDoubleSided("Chapiteau") == true, "chapiteau faces intérieures")
	check(Logic.NeedsInteriorDoubleSided("EntreeParc") == true, "entrée faces intérieures")
	check(Logic.NeedsInteriorDoubleSided("KiosqueBonbons") == false, "kiosque opaque")

	check(Logic.ShouldComputePreciseConvex(true, false) == true, "PreciseConvex au runtime")
	check(Logic.ShouldComputePreciseConvex(true, true) == false, "pas de PreciseConvex en aperçu Studio")
	check(Logic.ShouldComputePreciseConvex(false, false) == false, "pas de PreciseConvex si non solide")

	check(Logic.NeedsAnimatedCarouselClone(false) == false, "pas de clone, on anime l'original")
	check(Logic.NeedsAnimatedCarouselClone(true) == false, "clone interdit aussi si déjà présent")
	check(Logic.IsCarouselSourceClass("Folder") == true, "dossier Tripo accepté")
	check(Logic.IsCarouselSourceClass("Model") == true, "modèle Tripo accepté")
	check(Logic.IsCarouselSourceClass("MeshPart") == true, "MeshPart Tripo accepté")
	check(Logic.IsCarouselSourceClass("Script") == false, "script refusé")
	check(Logic.MatchesCarouselName("Carrousel") == true, "orthographe française")
	check(Logic.MatchesCarouselName("Caroussel") == true, "orthographe Studio")
	check(Logic.MatchesCarouselName("tripo-carousel-final") == true, "nom partiel")
	check(Logic.MatchesCarouselName("CarouselCollisionBody") == false, "hull exclu")
	check(Logic.MatchesCarouselName("Chapiteau") == false, "chapiteau n'est pas le manège")
	check(Logic.IsKnownNonCarouselAsset("RollABallKiosk") == true, "roll-a-ball exclu du scan")
	check(Logic.IsKnownNonCarouselAsset("roll_a_ball") == true, "modèle roll_a_ball exclu du scan")
	check(Logic.LooksLikeCarouselBounds(Vector3.new(32, 18, 32)) == true, "volume circulaire manège")
	check(Logic.LooksLikeCarouselBounds(Vector3.new(80, 40, 12)) == false, "bâtiment allongé exclu")
	check(Logic.IsKnownNonCarouselAsset("Chapiteau") == true, "chapiteau exclu du scan")
	check(Logic.IsKnownNonCarouselAsset("tripo-carousel-final") == false, "manège non exclu")
	check(Logic.ShouldArchiveCarouselSource(false) == false, "ne jamais archiver le manège visible")
	check(Logic.ShouldArchiveCarouselSource(true) == false, "ne jamais archiver en aperçu")
	check(Logic.CarouselCollisionFidelity() ~= Enum.CollisionFidelity.PreciseConvexDecomposition, "Hull pas PreciseConvex")
	check(Logic.CarouselHullDiameterScale() >= 1, "collision au moins aussi large que le mesh")

	check(Logic.PreferStudioCarouselOverGenerated() == true, "manège Studio prioritaire")
	check(Logic.IsGeneratedLayoutName("GeneratedLayout") == true, "dossier généré")
	check(Logic.IsGeneratedLayoutName("Caroussel") == false, "manège n'est pas le layout")
	check(Logic.FerrisBaseShouldCollide() == true, "base grande roue solide")
	check(Logic.FerrisSpinningWheelShouldCollide() == false, "roue animée non solide")

	if ok then
		print("[AmusementParkCollisionLogicTests] ALL PASS")
	else
		warn("[AmusementParkCollisionLogicTests] SOME FAILED")
	end
	return ok
end

return AmusementParkCollisionLogicTests
