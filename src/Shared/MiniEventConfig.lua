--!strict
-- Configuration centralisée des mini-événements temporaires.
-- Toutes les valeurs d'équilibrage doivent vivre ici (pas de magic numbers ailleurs).

local RunService = game:GetService("RunService")

local MiniEventConfig = {}

--------------------------------------------------------------------
-- Activation
--------------------------------------------------------------------
MiniEventConfig.Enabled = true
MiniEventConfig.MinPlayers = 1
-- Zones à bulles participantes (ids ZoneDefs).
MiniEventConfig.ParticipatingZones = { "ClassicZone", "SummerZone" }
-- Multiplicateur de poids pour l'événement vedette du jour (ChallengeService).
-- 2 = apparaît plus souvent sans exclure les autres (jamais forcé chaque cycle).
MiniEventConfig.FeaturedEventWeightMultiplier = 2

--------------------------------------------------------------------
-- Timing (secondes)
--------------------------------------------------------------------
MiniEventConfig.CountdownSeconds = 10
MiniEventConfig.FirstEventDelaySeconds = 180 -- ~3 min
MiniEventConfig.MinIntervalSeconds = 240 -- 4 min
MiniEventConfig.MaxIntervalSeconds = 420 -- 7 min
MiniEventConfig.EndedBannerSeconds = 4
MiniEventConfig.CleanupSeconds = 1
-- Throttle push progression perso (Golden / Color / Giant).
MiniEventConfig.ProgressBroadcastMinInterval = 0.3

--------------------------------------------------------------------
-- Studio / tests accélérés (uniquement si RunService:IsStudio())
--------------------------------------------------------------------
MiniEventConfig.Studio = {
	Enabled = true,
	CountdownSeconds = 3,
	DurationScale = 0.5, -- multiplie les durées actives
	MinIntervalSeconds = 15,
	MaxIntervalSeconds = 25,
	FirstEventDelaySeconds = 8,
	GiantBaseHits = 8,
	GiantHitsPerPlayer = 4,
}

--------------------------------------------------------------------
-- Événements
--------------------------------------------------------------------
MiniEventConfig.Events = {
	GoldenWave = {
		Enabled = true,
		DurationSeconds = 45,
		-- Proportion des bulles normales vivantes transformées au démarrage.
		InitialTransformRatio = 0.18,
		-- Chance qu’une normale régénérée devienne dorée pendant l’événement.
		RegenGoldenChance = 0.22,
		SellMultiplier = 5,
		Color = Color3.fromRGB(255, 196, 48),
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0,
		Transparency = 0.08,
	},
	ColorRush = {
		Enabled = true,
		DurationSeconds = 60,
		SellMultiplier = 3,
		-- Distance RGB (0–1) pour matcher la couleur cible.
		ColorMatchDistance = 0.18,
		MarkTransparency = 0.45,
	},
	GiantBubble = {
		-- Désactivé : gros dôme Glass cyan (~52 studs) sombre la grille selon l'angle caméra.
		-- Code de spawn conservé pour référence / ForceStart Studio uniquement si re-Enabled.
		Enabled = false,
		DurationSeconds = 75,
		BaseHits = 30,
		HitsPerPlayer = 15,
		Scale = 6.5, -- SpecialMesh scale vs bubble size (N.B. Size 8 * 6.5 ≈ 52 studs)
		HeightOffset = 4.5,
		MaxInteractRange = 22,
		HitCooldown = 0.35,
		-- Points de contribution par outil (Jump = saut / PopRequest).
		ContributionByTool = {
			Jump = 1,
			Epingle = 2,
			Marteau = 3,
			Bombe = 3,
			MegaRouleau = 4,
			Laser = 3,
			Singularite = 5,
		},
		MinimumContribution = 3,
		-- Récompense : XP gelée dans le projet → bonus de vente uniquement.
		BaseSellBonus = 40,
		SellBonusPerHit = 8,
		CompletionBonus = 120,
		-- Progression network throttle.
		ProgressBroadcastMinInterval = 0.35,
		AnalyticsMilestones = { 0.25, 0.5, 0.75, 1.0 },
	},
}

--------------------------------------------------------------------
-- Noms lisibles des teintes (accessibilité Color Rush)
--------------------------------------------------------------------
MiniEventConfig.ColorLabels = {
	{ Color = Color3.fromRGB(30, 95, 255), Name = "Blue" },
	{ Color = Color3.fromRGB(0, 210, 220), Name = "Cyan" },
	{ Color = Color3.fromRGB(40, 220, 110), Name = "Green" },
	{ Color = Color3.fromRGB(160, 255, 50), Name = "Lime" },
	{ Color = Color3.fromRGB(255, 70, 140), Name = "Pink" },
	{ Color = Color3.fromRGB(90, 70, 255), Name = "Indigo" },
	{ Color = Color3.fromRGB(255, 90, 90), Name = "Coral" },
	{ Color = Color3.fromRGB(255, 145, 35), Name = "Sunset" },
}

--------------------------------------------------------------------
-- Sons (ids Roblox stock — remplacables)
--------------------------------------------------------------------
MiniEventConfig.Sounds = {
	Countdown = "rbxassetid://9114221308",
	Start = "rbxassetid://9114224468",
	Progress = "rbxassetid://9113884125",
	Success = "rbxassetid://9114224773",
	Fail = "rbxassetid://9113894196",
	Reward = "rbxassetid://9114226949",
	Volume = 0.35,
}

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
function MiniEventConfig.IsStudioFast(): boolean
	return RunService:IsStudio() and MiniEventConfig.Studio.Enabled == true
end

function MiniEventConfig.GetCountdownSeconds(): number
	if MiniEventConfig.IsStudioFast() then
		return MiniEventConfig.Studio.CountdownSeconds
	end
	return MiniEventConfig.CountdownSeconds
end

function MiniEventConfig.GetDuration(eventType: string): number
	local def = MiniEventConfig.Events[eventType]
	if not def then
		return 30
	end
	local duration = def.DurationSeconds
	if MiniEventConfig.IsStudioFast() then
		duration = duration * MiniEventConfig.Studio.DurationScale
	end
	return duration
end

function MiniEventConfig.GetIntervalRange(): (number, number)
	if MiniEventConfig.IsStudioFast() then
		return MiniEventConfig.Studio.MinIntervalSeconds, MiniEventConfig.Studio.MaxIntervalSeconds
	end
	return MiniEventConfig.MinIntervalSeconds, MiniEventConfig.MaxIntervalSeconds
end

function MiniEventConfig.GetFirstDelay(): number
	if MiniEventConfig.IsStudioFast() then
		return MiniEventConfig.Studio.FirstEventDelaySeconds
	end
	return MiniEventConfig.FirstEventDelaySeconds
end

function MiniEventConfig.GetGiantHits(basePlayers: number): (number, number)
	local g = MiniEventConfig.Events.GiantBubble
	local base = g.BaseHits
	local per = g.HitsPerPlayer
	if MiniEventConfig.IsStudioFast() then
		base = MiniEventConfig.Studio.GiantBaseHits
		per = MiniEventConfig.Studio.GiantHitsPerPlayer
	end
	return base, per
end

function MiniEventConfig.IsEventEnabled(eventType: string): boolean
	local def = MiniEventConfig.Events[eventType]
	return def ~= nil and def.Enabled == true
end

function MiniEventConfig.ListEnabledEvents(): { string }
	local out = {}
	for id, def in pairs(MiniEventConfig.Events) do
		if def.Enabled == true then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

function MiniEventConfig.IsParticipatingZone(zoneId: string): boolean
	for _, id in ipairs(MiniEventConfig.ParticipatingZones) do
		if id == zoneId then
			return true
		end
	end
	return false
end

function MiniEventConfig.ColorLabel(color: Color3): string
	local bestName = "Color"
	local bestDist = math.huge
	for _, entry in ipairs(MiniEventConfig.ColorLabels) do
		local dr = color.R - entry.Color.R
		local dg = color.G - entry.Color.G
		local db = color.B - entry.Color.B
		local dist = math.sqrt(dr * dr + dg * dg + db * db)
		if dist < bestDist then
			bestDist = dist
			bestName = entry.Name
		end
	end
	return bestName
end

return MiniEventConfig
