--!strict
-- Configuration du décor d'horizon (océan / îlots / palmiers — pas de montagnes).
-- Valeurs tuning uniquement — aucune logique de gameplay.

local EnvironmentBackdropConfig = {}

-- Centre approximatif du plateau jouable (lobby + salle de bulles).
EnvironmentBackdropConfig.WorldCenter = Vector3.new(0, 0, -90)
EnvironmentBackdropConfig.SeaLevelY = -14
EnvironmentBackdropConfig.Seed = 20260803

-- Marge (studs) autour de l’emprise Summer Zone : aucun décor d’horizon ne doit
-- chevaucher cette zone (îlots / palmiers / etc.).
EnvironmentBackdropConfig.SummerExclusionPad = 12

-- Bande d'eau lointaine (anneau de plates-formes).
EnvironmentBackdropConfig.Ocean = {
	RadiusMin = 280,
	RadiusMax = 620,
	RingCount = 3,
	SegmentsPerRing = 16,
	Thickness = 6,
	Colors = {
		Color3.fromRGB(95, 175, 220),
		Color3.fromRGB(80, 160, 210),
		Color3.fromRGB(110, 185, 225),
	},
}

-- Petits îlots stylisés (sable + plateau).
EnvironmentBackdropConfig.Islands = {
	Count = 4,
	RadiusMin = 340,
	RadiusMax = 520,
	SizeMin = 28,
	SizeMax = 48,
	HeightMin = 4,
	HeightMax = 9,
	SandColors = {
		Color3.fromRGB(232, 210, 160),
		Color3.fromRGB(240, 220, 175),
		Color3.fromRGB(220, 200, 150),
	},
	GrassColors = {
		Color3.fromRGB(95, 190, 120),
		Color3.fromRGB(80, 175, 110),
		Color3.fromRGB(110, 200, 130),
	},
}

EnvironmentBackdropConfig.Palms = {
	PerIslandMin = 1,
	PerIslandMax = 3,
	TrunkColor = Color3.fromRGB(120, 85, 55),
	FrondColors = {
		Color3.fromRGB(55, 160, 90),
		Color3.fromRGB(45, 145, 80),
		Color3.fromRGB(70, 170, 100),
	},
}

-- Nuages plats, très clairs, loin au-dessus.
EnvironmentBackdropConfig.Clouds = {
	Count = 12,
	RadiusMin = 300,
	RadiusMax = 580,
	AltitudeMin = 90,
	AltitudeMax = 160,
	Colors = {
		Color3.fromRGB(245, 250, 255),
		Color3.fromRGB(235, 245, 255),
		Color3.fromRGB(250, 252, 255),
	},
}

-- Bulles décoratives flottantes lointaines (lisibilité zone de jeu prioritaire).
EnvironmentBackdropConfig.DecorBubbles = {
	Count = 6,
	RadiusMin = 360,
	RadiusMax = 560,
	AltitudeMin = 25,
	AltitudeMax = 70,
	SizeMin = 10,
	SizeMax = 22,
	Colors = {
		Color3.fromRGB(170, 225, 255),
		Color3.fromRGB(190, 235, 210),
		Color3.fromRGB(220, 200, 255),
		Color3.fromRGB(255, 210, 190),
	},
}

-- Atmosphère claire et légère (moins de contraste vue claire/sombre sur le plateau).
EnvironmentBackdropConfig.Atmosphere = {
	Density = 0.14,
	Offset = 0.12,
	Haze = 0.85,
	Glare = 0.04,
	Color = Color3.fromRGB(195, 220, 240),
	Decay = Color3.fromRGB(160, 195, 220),
	FogStart = 420,
	FogEnd = 2400,
}

EnvironmentBackdropConfig.Lighting = {
	-- Éclairage plat pour stabiliser le shading des SpecialMesh Sphères (bulles).
	-- Ambient bas + ColorShiftTop/Bottom distincts + Specular Scale = faces trop foncées
	-- selon l'angle joueur/soleil (même CastShadow false sur les décors / bulles).
	Brightness = 1.85,
	Ambient = Color3.fromRGB(155, 170, 190),
	OutdoorAmbientBlend = 0.45,
	OutdoorAmbientTint = Color3.fromRGB(190, 215, 235),
	EnvironmentDiffuseScale = 0.9,
	EnvironmentSpecularScale = 0, -- 0 = plus de highlights miroir directionnels sur le monde
	-- Identiques → pas de teinte haut/bas qui flippe avec l'orientation face.
	ColorShift_Top = Color3.fromRGB(255, 255, 255),
	ColorShift_Bottom = Color3.fromRGB(255, 255, 255),
}

return EnvironmentBackdropConfig
