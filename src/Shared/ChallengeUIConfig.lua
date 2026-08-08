--!strict
-- Config UI Challenges (layout TV/PC/mobile). Aucun overlay de diagnostic visible.

local ChallengeUIConfig = {}

--------------------------------------------------------------------
-- Debug (toujours off en jeu — logs Studio uniquement si true)
--------------------------------------------------------------------
ChallengeUIConfig.ShowBuildTag = false
ChallengeUIConfig.DebugRuntime = false

--------------------------------------------------------------------
-- Marges télévision (safe area) — ConsoleDocked uniquement
--------------------------------------------------------------------
ChallengeUIConfig.ConsoleSafeMarginX = 36 -- 24–48
ChallengeUIConfig.ConsoleSafeMarginY = 24 -- 18–36
ChallengeUIConfig.ConsolePanelWidthRatio = 0.34
ChallengeUIConfig.ConsolePanelWidthMin = 520
ChallengeUIConfig.ConsolePanelWidthMax = 700

--------------------------------------------------------------------
-- Display
--------------------------------------------------------------------
ChallengeUIConfig.ScreenDisplayOrder = 40 -- au-dessus du HUD jeu
ChallengeUIConfig.PanelZIndex = 21
ChallengeUIConfig.RailZIndex = 25

return ChallengeUIConfig
