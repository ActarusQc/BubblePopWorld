--!strict
-- Configuration visuelle du fini « Pearlescent Toy ».
-- Rendu client-only, sans vraie lumière et sans Glass afin de garder un aspect stable
-- quand la caméra tourne. Le dôme serveur reste la bordure colorée; un large dôme
-- nacré translucide + un petit reflet fixe donnent le relief.

local ENABLED_ZONES: { [string]: boolean } = {
	ClassicZone = true,
	GameRoom = true,
	SummerZone = false,
}

local BubblePearlescentStyle = {
	Enabled = true,
	Zones = ENABLED_ZONES,

	ShellName = "BPW_PearlShell",
	GlintName = "BPW_PearlGlint",

	-- Large dôme intérieur : presque toute la bulle, pour éviter l'effet « rond blanc au centre ».
	ShellScaleXZ = 0.94,
	ShellScaleY = 0.97,
	ShellYOffset = 0.08,

	-- Mélange léger vers un blanc froid : la teinte originale reste bien visible.
	PearlTint = Color3.fromRGB(250, 248, 255),
	NormalWhiteMix = 0.34,
	SpecialWhiteMix = 0.20,

	-- Neon translucide = rendu stable et doux, sans shading caméra-dépendant.
	ShellMaterial = Enum.Material.Neon,
	NearTransparency = 0.30,
	FarTransparency = 0.62,

	-- Petit reflet « jouet » placé de façon fixe par rapport à la bulle.
	-- Comme il ne suit pas la caméra, il ne recrée pas l'ancien bug sombre/clair.
	GlintMaterial = Enum.Material.Neon,
	GlintColor = Color3.fromRGB(255, 255, 255),
	GlintTransparency = 0.22,
	GlintScale = Vector3.new(0.18, 0.10, 0.14),
	GlintOffsetFraction = Vector3.new(-0.14, 0.31, -0.13),

	-- LOD : deux petites Parts locales par bulle proche seulement.
	DesktopMaxDistance = 150,
	DesktopMaxActiveBubbles = 650,
	MobileMaxDistance = 100,
	MobileMaxActiveBubbles = 300,
	FadeStartRatio = 0.70,
	LodRefreshSeconds = 0.45,
	VisualRefreshSeconds = 0.10,
}

function BubblePearlescentStyle.IsZoneEnabled(zoneId: string): boolean
	return BubblePearlescentStyle.Enabled == true
		and BubblePearlescentStyle.Zones[zoneId] == true
end

function BubblePearlescentStyle.ResolveShellColor(baseColor: Color3, isSpecial: boolean): Color3
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

function BubblePearlescentStyle.ResolveGlintTransparency(distance: number, maxDistance: number): number
	local shellT = BubblePearlescentStyle.ResolveTransparency(distance, maxDistance)
	return math.clamp(BubblePearlescentStyle.GlintTransparency + shellT * 0.35, 0, 1)
end

return BubblePearlescentStyle
