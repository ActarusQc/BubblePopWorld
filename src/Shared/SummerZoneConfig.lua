--!strict
-- Source unique des dimensions et marges géométriques de la Summer Zone.

local SummerZoneConfig = {
	-- X = profondeur depuis l'entrée ; Z = largeur de façade.
	-- ZoneWidth élargi pour 16 rangées de bulles (+4 vs compact 12) tout en gardant SideDecorMargin.
	ZoneWidth = 132,
	ZoneDepth = 180,
	SideDecorMargin = 16,
	EntranceDecorMargin = 14,
	RearDecorMargin = 24,
	-- 0 : utiliser toute la largeur disponible (16 rangées) ; ne pas toucher à la profondeur X.
	BubbleRowReduction = 0,
	LightPerimeterSpacing = 30,
	EntryCenterOffset = 0,
}

return SummerZoneConfig
