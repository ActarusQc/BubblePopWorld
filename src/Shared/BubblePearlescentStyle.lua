--!strict
-- Configuration visuelle du fini Â« Pearlescent Toy Â».
-- Rendu client-only : la Part serveur garde toute la physique/gameplay, mais elle est
-- masquÃ©e localement prÃ¨s du joueur et remplacÃ©e par 3 couches simples :
--   1) un disque/rim nacrÃ©;
--   2) un dÃ´me colorÃ© plus haut et plus doux;
--   3) un petit reflet blanc fixe.
-- Aucun Glass, aucune vraie lumiÃ¨re, aucun post-FX : rendu stable quand la camÃ©ra tourne.

local ENABLED_ZONES: { [string]: boolean } = {
	ClassicZone = true,
	GameRoom = true,
	SummerZone = false,
}

local BubblePearlescentStyle = {
	Enabled = false,
	Zones = ENABLED_ZONES,

	RimName = "BPW_PearlRim",
	DomeName = "BPW_PearlDome",
	GlintName = "BPW_PearlGlint",

	-- Rim visible sous le dÃ´me : donne la bordure claire de la maquette.
	RimDiameterScale = 0.94,
	RimThickness = 0.16,
	RimYOffset = -0.60,
	RimWhiteMix = 0.52,
	RimTransparency = 0.04,
	RimMaterial = Enum.Material.Neon,

	-- DÃ´me principal : plus Ã©troit mais plus haut que l'ancienne bulle plate.
	DomeScaleXZ = 0.86,
	DomeScaleY = 1.30,
	DomeYOffset = 0.20,
	PearlTint = Color3.fromRGB(250, 248, 255),
	NormalWhiteMix = 0.28,
	SpecialWhiteMix = 0.12,
	DomeMaterial = Enum.Material.Neon,
	NearTransparency = 0.12,
	FarTransparency = 0.48,

	-- Petit reflet Â« jouet Â» fixe. Il ne suit pas la camÃ©ra, donc pas d'effet sombre/clair.
	GlintMaterial = Enum.Material.Neon,
	GlintColor = Color3.fromRGB(255, 255, 255),
	GlintTransparency = 0.16,
	GlintScale = Vector3.new(0.13, 0.07, 0.11),
	GlintOffsetFraction = Vector3.new(-0.18, 0.38, -0.16),

	-- LOD : 3 petites Parts locales par bulle proche seulement.
	DesktopMaxDistance = 155,
	DesktopMaxActiveBubbles = 550,
	MobileMaxDistance = 100,
	MobileMaxActiveBubbles = 260,
	FadeStartRatio = 0.72,
	LodRefreshSeconds = 0.45,
	VisualRefreshSeconds = 0.10,
}

function BubblePearlescentStyle.IsZoneEnabled(zoneId: string): boolean
	return BubblePearlescentStyle.Enabled == true
		and BubblePearlescentStyle.Zones[zoneId] == true
end

function BubblePearlescentStyle.ResolveDomeColor(baseColor: Color3, isSpecial: boolean): Color3
	local mix = if isSpecial
		then BubblePearlescentStyle.SpecialWhiteMix
		else BubblePearlescentStyle.NormalWhiteMix
	return baseColor:Lerp(BubblePearlescentStyle.PearlTint, mix)
end

function BubblePearlescentStyle.ResolveRimColor(baseColor: Color3): Color3
	return baseColor:Lerp(BubblePearlescentStyle.PearlTint, BubblePearlescentStyle.RimWhiteMix)
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

function BubblePearlescentStyle.ResolveGlintTransparency(distance: number, maxDistance: number): number
	local domeT = BubblePearlescentStyle.ResolveTransparency(distance, maxDistance)
	return math.clamp(BubblePearlescentStyle.GlintTransparency + domeT * 0.28, 0, 1)
end

return BubblePearlescentStyle
