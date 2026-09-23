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
-- Un quart de l'ecran laisse le jeu visible tout en gardant les objectifs lisibles sur TV.
ChallengeUIConfig.ConsolePanelWidthRatio = 0.25
ChallengeUIConfig.ConsolePanelWidthMin = 440
ChallengeUIConfig.ConsolePanelWidthMax = 520

--------------------------------------------------------------------
-- Display
--------------------------------------------------------------------
ChallengeUIConfig.ScreenDisplayOrder = 40 -- au-dessus du HUD jeu
ChallengeUIConfig.PanelZIndex = 21
ChallengeUIConfig.RailZIndex = 25

return ChallengeUIConfig
