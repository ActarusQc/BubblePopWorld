--!strict
-- Configuration du décor d'horizon (montagnes / collines / arbres / atmosphère).
-- Valeurs tuning uniquement — aucune logique de gameplay.

local EnvironmentBackdropConfig = {}

-- Centre approximatif du plateau jouable (lobby + salle de bulles).
EnvironmentBackdropConfig.WorldCenter = Vector3.new(0, 0, -90)
EnvironmentBackdropConfig.GroundY = -10
EnvironmentBackdropConfig.Seed = 20260727

-- Marge (studs) autour de l’emprise Summer Zone : aucun décor d’horizon ne doit
-- chevaucher cette zone (montagnes vertes Foothills / collines GroundBand / etc.).
-- L’horizon lointain hors emprise reste généré normalement.
EnvironmentBackdropConfig.SummerExclusionPad = 12

EnvironmentBackdropConfig.Foothills = {
	RadiusMin = 220,
	RadiusMax = 320,
	Count = 18,
	HeightMin = 35,
	HeightMax = 75,
	WidthMin = 48,
	WidthMax = 95,
	DepthMin = 28,
	DepthMax = 55,
	-- Filet seed 20260727 (exclusion géométrique = source de vérité).
	SkipIndices = { 1, 2, 3 },
	Colors = {
		Color3.fromRGB(42, 78, 72),
		Color3.fromRGB(38, 70, 78),
		Color3.fromRGB(48, 86, 70),
		Color3.fromRGB(36, 64, 68),
	},
}

EnvironmentBackdropConfig.MainMountains = {
	RadiusMin = 330,
	RadiusMax = 480,
	Count = 20,
	HeightMin = 90,
	HeightMax = 180,
	WidthMin = 70,
	WidthMax = 140,
	DepthMin = 40,
	DepthMax = 80,
	SkipIndices = { 1, 2, 3 },
	Colors = {
		Color3.fromRGB(58, 72, 92),
		Color3.fromRGB(48, 60, 78),
		Color3.fromRGB(66, 78, 96),
		Color3.fromRGB(72, 82, 98),
		Color3.fromRGB(52, 64, 82),
	},
}

EnvironmentBackdropConfig.FarPeaks = {
	RadiusMin = 480,
	RadiusMax = 650,
	Count = 16,
	HeightMin = 140,
	HeightMax = 240,
	WidthMin = 90,
	WidthMax = 170,
	DepthMin = 45,
	DepthMax = 90,
	SnowCapChance = 0.42,
	SkipIndices = { 2 },
	Colors = {
		Color3.fromRGB(78, 92, 112),
		Color3.fromRGB(88, 100, 118),
		Color3.fromRGB(70, 84, 104),
		Color3.fromRGB(94, 106, 122),
	},
	SnowColor = Color3.fromRGB(230, 236, 242),
}

EnvironmentBackdropConfig.GroundBand = {
	RadiusMin = 150,
	RadiusMax = 300,
	SegmentCount = 14,
	Thickness = 8,
	WidthMin = 70,
	WidthMax = 120,
	HillCount = 12,
	HillHeightMin = 8,
	HillHeightMax = 22,
	RockCount = 16,
	-- Indices seed 20260727 qui chevauchent Summer (filet + exclusion géométrique).
	SkipSegmentIndices = { 1, 2, 3 },
	SkipHillIndices = { 1, 2 },
	SkipRockIndices = { 1, 2, 3 },
	Colors = {
		Color3.fromRGB(34, 72, 68),
		Color3.fromRGB(40, 80, 72),
		Color3.fromRGB(32, 64, 70),
		Color3.fromRGB(46, 78, 64),
	},
	BaseColors = {
		Color3.fromRGB(30, 58, 64),
		Color3.fromRGB(28, 52, 60),
		Color3.fromRGB(36, 62, 58),
	},
	RockColors = {
		Color3.fromRGB(55, 68, 78),
		Color3.fromRGB(48, 58, 70),
		Color3.fromRGB(62, 74, 84),
	},
}

EnvironmentBackdropConfig.Trees = {
	ClusterCount = 10,
	TreesPerClusterMin = 2,
	TreesPerClusterMax = 5,
	RadiusMin = 180,
	RadiusMax = 280,
	SkipClusterIndices = { 1, 2 },
	TrunkColor = Color3.fromRGB(62, 44, 32),
	FoliageColors = {
		Color3.fromRGB(28, 78, 52),
		Color3.fromRGB(24, 70, 48),
		Color3.fromRGB(34, 86, 58),
		Color3.fromRGB(22, 64, 50),
	},
}

-- Atmosphère douce : profondeur sans laver le lobby / les kiosques.
EnvironmentBackdropConfig.Atmosphere = {
	Density = 0.22,
	Offset = 0.16,
	Haze = 1.35,
	Glare = 0.08,
	Color = Color3.fromRGB(175, 198, 220),
	Decay = Color3.fromRGB(120, 145, 175),
	FogStart = 380,
	FogEnd = 2200,
}

EnvironmentBackdropConfig.Lighting = {
	-- Ajustements légers uniquement (identité visuelle conservée).
	Brightness = 2.0,
	Ambient = Color3.fromRGB(70, 78, 95),
	OutdoorAmbientBlend = 0.35, -- mélange worldDef.Sky → bleu-gris horizon
	OutdoorAmbientTint = Color3.fromRGB(150, 185, 215),
	EnvironmentDiffuseScale = 0.48,
	EnvironmentSpecularScale = 0.22,
	ColorShift_Top = Color3.fromRGB(215, 230, 245),
	ColorShift_Bottom = Color3.fromRGB(140, 170, 195),
}

return EnvironmentBackdropConfig
