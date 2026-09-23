--!strict
-- Implantation de la zone Parc d'attractions, en miroir de la Summer Zone.

local AmusementParkConfig = {
	Id = "AmusementPark",
	DisplayName = "AMUSEMENT PARK",
	-- Accès libre pendant la construction et les tests de la zone.
	RequiredLevel = 1,
	Origin = Vector3.new(-258, 6, 0),
	Size = Vector3.new(200, 2, 168),
	BridgeWidth = 18,
	GeneratedFolderName = "GeneratedLayout",

	Placements = {
		-- La position choisie directement dans Studio est la source de vérité. Le
		-- service d'animation reconstruit ses nacelles autour de cette position.
		GrandeRoue = { Position = Vector3.new(-326, 14, 5), Yaw = 90, PreserveStudioTransform = true },
		Chapiteau = { Position = Vector3.new(-281, 6, 55), Yaw = 0, TargetHeight = 38, PreserveStudioTransform = true },
		-- La station reste volontairement loin de l'escalier public vers l'étage.
		-- Position contrôlée directement dans Studio; rails et escalier suivent ce modèle.
		StationEmbarquement = { Position = Vector3.new(-193, 6, 30), Yaw = 0, TargetHeight = 23, PreserveStudioTransform = true },
		EntreeParc = { Position = Vector3.new(-166, 6, 0), Yaw = -90, TargetHeight = 25 },
		KiosqueBonbons = { Position = Vector3.new(-190, 6, -29), Yaw = 180, TargetHeight = 19 },
		Carousel = { Position = Vector3.new(-238, 6, 58), Yaw = 0, TargetHeight = 25, PreserveStudioTransform = true },
		-- Kiosque Tripo du jeu de tir. Le modèle source doit s'appeler BubbleBlaster.
		BubbleBlaster = {
			Position = Vector3.new(-205, 6, -58),
			Yaw = 180,
			TargetHeight = 25,
			InteractionOffset = Vector3.new(0, 5.5, -10),
			PreserveStudioTransform = false,
		},
		-- Machine Roll-A-Ball. Le modèle Studio/Tripo `roll_a_ball` remplace le kiosque généré.
		-- La pose Studio est conservée ; seul le prompt de jeu est recalé sur le mesh.
		RollABall = {
			Position = Vector3.new(-175, 6, -58),
			Yaw = 180,
			TargetHeight = 18,
			InteractionOffset = Vector3.new(0, 4.5, 8),
			PreserveStudioTransform = true,
		},
		-- La façade regarde vers le centre du parc. Le modèle Tripo remplace les
		-- anciens blocs ElevatorTower/ElevatorGlass, tandis que les points de
		-- téléportation invisibles conservent la mécanique actuelle.
		-- Une fois importé et placé, le modèle Studio est la source de vérité. Les
		-- deux points de téléportation suivent automatiquement ses déplacements.
		Ascenceur = {
			Position = Vector3.new(-296.5, 6, 32),
			Yaw = 0,
			TargetHeight = 56,
			-- Les commandes se trouvent au centre de la cabine. Cela demeure fiable
			-- même si le modèle Tripo est tourné ou déplacé dans Studio.
			GroundInteractionOffset = Vector3.zero,
			HighInteractionOffset = Vector3.zero,
			PreserveStudioTransform = true,
		},
	},

	FerrisWheel = {
		BaseHeight = 64,
		WheelDiameter = 62,
		HubHeight = 58,
		GondolaCount = 8,
		GondolaHeight = 10,
		GondolaRadius = 33,
		HangerLength = 5,
		RotationSeconds = 42,
		UpdateRate = 30,
		-- Interaction sur le quai supérieur, directement devant les nacelles.
		BoardingPosition = Vector3.new(-320, 17, 5),
	},

	Coaster = {
		CarCount = 4,
		CarLength = 6.2,
		CarSpacing = 7.2,
		Speed = 20,
		StationDwell = 8,
		WagonYaw = 0,
		TrackMargin = -4,
		CornerRadius = 26,
		StationHalfLength = 16,
		CornerSamples = 10,
		StationLift = 18,
		TrackHeightOffset = 8,
		PlatformHeightOffset = 4,
		LoopRadius = 18,
		LoopSamples = 20,
		SmallLoopRadius = 0,
		HighRise = 28,
		LowDrop = 10,
		SAmplitude = 0,
		SSamples = 14,
		TrainCount = 3,
		WorldTour = {
			Clearance = 6,
			CorridorHalfZ = 16,
			CornerRadius = 22,
			ScenicHeight = 12,
		},
	},
}

return table.freeze(AmusementParkConfig)
