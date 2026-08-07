--!strict
-- Métadonnées des 3 tableaux hub (PAS de placement runtime).
-- Géométrie = Studio-owned (plugin + ajustement manuel). Runtime = SurfaceGui uniquement.

local HubDisplaysLayout = {}

HubDisplaysLayout.FOLDER_NAME = "HubDisplays"
HubDisplaysLayout.PLATFORM_NAME = "TripoRearHubPlatform"
HubDisplaysLayout.REAR_FOLDER = "RearHub"
HubDisplaysLayout.DISPLAYS_VERSION = "HUB_DISPLAYS_V2_STUDIO"

HubDisplaysLayout.DEBUG_ATTR = "BPW_ShowLeaderboardAnchors"
HubDisplaysLayout.MANUAL_ATTR = "BPW_ManualPlacement"
HubDisplaysLayout.ROLE_ATTR = "BPW_LeaderboardRole"
HubDisplaysLayout.ANCHOR_TAG = "BPW_HubLeaderboardAnchor"
HubDisplaysLayout.MAX_DISTANCE_FROM_TRIPO = 30

export type BoardRole = "Coins" | "WeeklyBest" | "Levels"

export type AnchorSpec = {
	Name: string,
	Role: BoardRole,
	-- Size de création plugin seulement (jamais appliqué au runtime).
	DefaultCreateSize: Vector3,
	-- Offset local *uniquement* pour le plugin Create Missing (repère = Tripo:GetPivot()).
	PluginLocalOffset: Vector3,
	PluginLocalYawDegrees: number,
	ThemeAccent: Color3,
	ThemeBg: Color3,
	ThemeHeader: Color3,
	DebugColor: Color3,
	TitleKey: string,
	GuiName: string,
	Tag: string,
}

-- Offsets plugin : proches du mesh Tripo (repère GetPivot du Model TripoRearHubPlatform UNIQUEMENT).
-- Ajustement final = manuel Studio. Runtime n'utilise PAS ces valeurs.
-- NOTE Luau : on ne peut PAS écrire `Module.Field: Type = value` (parsée comme méthode `Field:{`).
local ANCHORS: { AnchorSpec } = {
	{
		Name = "LeftLeaderboardAnchor",
		Role = "Coins",
		DefaultCreateSize = Vector3.new(8, 9, 0.15),
		PluginLocalOffset = Vector3.new(-8, 4, 6),
		PluginLocalYawDegrees = -20,
		ThemeAccent = Color3.fromRGB(70, 170, 255),
		ThemeBg = Color3.fromRGB(10, 22, 48),
		ThemeHeader = Color3.fromRGB(18, 40, 78),
		DebugColor = Color3.fromRGB(220, 60, 50),
		TitleKey = "TopCoinCollectors",
		GuiName = "CoinsLeaderboardGui",
		Tag = "BPW_TopCoinsBoard",
	},
	{
		Name = "CenterLeaderboardAnchor",
		Role = "WeeklyBest",
		DefaultCreateSize = Vector3.new(9, 10, 0.15),
		PluginLocalOffset = Vector3.new(0, 4.5, 7),
		PluginLocalYawDegrees = 0,
		ThemeAccent = Color3.fromRGB(175, 120, 255),
		ThemeBg = Color3.fromRGB(24, 14, 42),
		ThemeHeader = Color3.fromRGB(48, 28, 72),
		DebugColor = Color3.fromRGB(255, 220, 60),
		TitleKey = "HubWeeklyBestTitle",
		GuiName = "WeeklyBestGui",
		Tag = "BPW_WeeklyBestScoreBoard",
	},
	{
		Name = "RightLeaderboardAnchor",
		Role = "Levels",
		DefaultCreateSize = Vector3.new(8, 9, 0.15),
		PluginLocalOffset = Vector3.new(8, 4, 6),
		PluginLocalYawDegrees = 20,
		ThemeAccent = Color3.fromRGB(90, 210, 120),
		ThemeBg = Color3.fromRGB(12, 32, 22),
		ThemeHeader = Color3.fromRGB(22, 52, 36),
		DebugColor = Color3.fromRGB(60, 220, 230),
		TitleKey = "HighestLevelsTitle",
		GuiName = "LevelsLeaderboardGui",
		Tag = "BPW_HighestLevelsBoard",
	},
}
HubDisplaysLayout.ANCHORS = ANCHORS

HubDisplaysLayout.LEGACY_BOARD_MODELS = {
	"TopCoinsBoard",
	"WeeklyBestScoreBoard",
	"ChallengesBoard",
}

function HubDisplaysLayout.SpecByName(name: string): AnchorSpec?
	for _, spec in ipairs(HubDisplaysLayout.ANCHORS) do
		if spec.Name == name then
			return spec
		end
	end
	return nil
end

function HubDisplaysLayout.SpecByRole(role: BoardRole): AnchorSpec?
	for _, spec in ipairs(HubDisplaysLayout.ANCHORS) do
		if spec.Role == role then
			return spec
		end
	end
	return nil
end

-- Plugin only — jamelais runtime.
function HubDisplaysLayout.PluginWorldCFrame(tripoPivot: CFrame, spec: AnchorSpec): CFrame
	return tripoPivot
		* CFrame.new(spec.PluginLocalOffset)
		* CFrame.Angles(0, math.rad(spec.PluginLocalYawDegrees), 0)
end

function HubDisplaysLayout.DistanceXZ(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function HubDisplaysLayout.IsAnchorTooFarFromTripo(anchorPos: Vector3, tripoPos: Vector3): boolean
	return HubDisplaysLayout.DistanceXZ(anchorPos, tripoPos) > HubDisplaysLayout.MAX_DISTANCE_FROM_TRIPO
end

function HubDisplaysLayout.DebugTransparency(): number
	return 0.35
end

function HubDisplaysLayout.RuntimeTransparency(): number
	return 1
end

return HubDisplaysLayout
