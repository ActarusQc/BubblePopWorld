--!strict
-- Réglages feux d’artifice Summer Zone (ambiance décorative uniquement).
-- Ajuster ici : fréquence, couleurs, hauteur, intensité, activation.

local ZoneDefs = require(script.Parent.ZoneDefs)

local SummerFireworksConfig = {}

-- Master switch
SummerFireworksConfig.Enabled = true

-- Son optionnel (désactivé par défaut — activer + ID valide si besoin)
SummerFireworksConfig.SoundEnabled = false
SummerFireworksConfig.SoundId = "rbxassetid://0"
SummerFireworksConfig.SoundVolume = 0.12
SummerFireworksConfig.SoundMaxDistance = 120

-- Fréquence (secondes entre séquences)
SummerFireworksConfig.IntervalMin = 8
SummerFireworksConfig.IntervalMax = 15
SummerFireworksConfig.MaxPerSequence = 3
SummerFireworksConfig.StaggerSeconds = 0.4

-- Mobile / qualité basse
SummerFireworksConfig.LiteIntervalMin = 12
SummerFireworksConfig.LiteIntervalMax = 18
SummerFireworksConfig.LiteMaxPerSequence = 1
SummerFireworksConfig.LiteEmitScale = 0.55

-- Hauteur au-dessus du sol de zone (studs)
SummerFireworksConfig.BurstHeightMin = 28
SummerFireworksConfig.BurstHeightMax = 42
-- Recul hors BubbleBoard (studs au-delà de l’emprise jeu)
SummerFireworksConfig.EdgeOffset = 14

-- Particules (desktop)
SummerFireworksConfig.EmitCount = 28
SummerFireworksConfig.Lifetime = NumberRange.new(0.55, 1.05)
SummerFireworksConfig.Speed = NumberRange.new(10, 22)
SummerFireworksConfig.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.9),
	NumberSequenceKeypoint.new(0.35, 0.55),
	NumberSequenceKeypoint.new(1, 0),
})

-- Pool : jamais plus d’émetteurs que ça
SummerFireworksConfig.PoolSize = 3

SummerFireworksConfig.Colors = {
	Color3.fromRGB(255, 110, 180), -- rose
	Color3.fromRGB(80, 180, 255), -- bleu
	Color3.fromRGB(255, 220, 70), -- jaune
	Color3.fromRGB(90, 230, 120), -- vert
	Color3.fromRGB(190, 110, 255), -- violet
	Color3.fromRGB(255, 150, 90), -- orange été
}

-- Points de lancement (monde) : hors centre BubbleBoard — bords / arche / fond.
function SummerFireworksConfig.GetLaunchPositions(): { Vector3 }
	local layout = ZoneDefs.GetSummerBridgeLayout()
	local o = layout.Origin
	local ex, ez = layout.Ex, layout.Ez
	local edge = SummerFireworksConfig.EdgeOffset
	local yBase = layout.Y
	local h = (SummerFireworksConfig.BurstHeightMin + SummerFireworksConfig.BurstHeightMax) * 0.5

	return {
		-- Fond est (arrière-plan)
		Vector3.new(o.X + ex + edge, yBase + h, o.Z),
		Vector3.new(o.X + ex + edge * 0.85, yBase + h + 4, o.Z + ez * 0.55),
		Vector3.new(o.X + ex + edge * 0.85, yBase + h + 4, o.Z - ez * 0.55),
		-- Nord / sud derrière les murs
		Vector3.new(o.X + ex * 0.35, yBase + h + 2, o.Z + ez + edge),
		Vector3.new(o.X + ex * 0.35, yBase + h + 2, o.Z - ez - edge),
		-- Près de l’arche (hors plateau, côtés)
		Vector3.new(layout.ArchX - 2, yBase + h + 6, o.Z + layout.ArchGap * 0.5 + 10),
		Vector3.new(layout.ArchX - 2, yBase + h + 6, o.Z - layout.ArchGap * 0.5 - 10),
	}
end

return SummerFireworksConfig
