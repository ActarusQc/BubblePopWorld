--!strict
-- Configuration visuelle du fini « Pearlescent Toy ».
-- Le rendu est client-only : aucune lumière réelle, aucune collision et aucune
-- modification de la logique de pop / récompense. Le coeur clair est un dôme
-- Neon local, superposé au dôme serveur pour garder un rendu stable selon la caméra.

local BubblePearlescentStyle = {
	Enabled = true,

	-- Première passe : zone principale uniquement. Summer garde son identité orange.
	Zones = {
		ClassicZone = true,
		GameRoom = true,
		SummerZone = false,
	},

	CoreName = "BPW_PearlCore",

	-- Géométrie du petit dôme clair qui émerge du centre de la bulle.
	CoreScaleXZ = 0.78,
	CoreScaleY = 0.90,
	CoreYOffset = 0.23,

	-- Mélange avec un blanc légèrement froid = effet nacré / jouet.
	PearlTint = Color3.fromRGB(250, 248, 255),
	NormalWhiteMix = 0.58,
	SpecialWhiteMix = 0.34,

	-- Le coeur reste Neon pour ne pas réintroduire le shading caméra-dépendant.
	CoreMaterial = Enum.Material.Neon,
	NearTransparency = 0.16,
	FarTransparency = 0.56,

	-- LOD : on garde l'effet complet près du joueur, et on évite de doubler
	-- toutes les Parts du plateau sur mobile.
	DesktopMaxDistance = 150,
	DesktopMaxActiveCores = 900,
	MobileMaxDistance = 105,
	MobileMaxActiveCores = 450,
	FadeStartRatio = 0.68,
	LodRefreshSeconds = 0.45,
	VisualRefreshSeconds = 0.10,
}

function BubblePearlescentStyle.IsZoneEnabled(zoneId: string): boolean
	return BubblePearlescentStyle.Enabled == true
		and BubblePearlescentStyle.Zones[zoneId] == true
end

function BubblePearlescentStyle.ResolveCoreColor(baseColor: Color3, isSpecial: boolean): Color3
	local mix = if isSpecial
		then BubblePearlescentStyle.SpecialWhiteMix
		else BubblePearlescentStyle.NormalWhiteMix
	return baseColor:Lerp(BubblePearlescentStyle.PearlTint, mix)
end

function BubblePearlescentStyle.ResolveTransparency(distance: number, maxDistance: number): number
	local start = maxDistance * BubblePearlescentStyle.FadeStartRatio
	if distance <= start then
		return BubblePearlescentStyle.NearTransparency
	end
	if distance >= maxDistance then
		return 1
	end
	local alpha = (distance - start) / math.max(0.001, maxDistance - start)
	return BubblePearlescentStyle.NearTransparency
		+ (BubblePearlescentStyle.FarTransparency - BubblePearlescentStyle.NearTransparency) * alpha
end

return BubblePearlescentStyle
