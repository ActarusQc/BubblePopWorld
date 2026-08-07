--!strict
-- Tests layout barre Challenges (ancrage droite, largeurs, trackers interdits).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudChrome = require(Shared.HudChrome)

local ChallengeUiLayoutTests = {}

function ChallengeUiLayoutTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[ChallengeUiLayoutTests] FAIL:", msg)
			ok = false
		end
	end

	check(HudChrome.IsChallengesRightDocked(1, 1, 0), "dock X ancré à droite")
	check(not HudChrome.IsChallengesRightDocked(0.5, 0.5, 0), "refus ancre centre")
	check(not HudChrome.IsChallengesRightDocked(1, 1, -12 - 80), "refus offset gauche type ancien panel")

	local w = HudChrome.ChallengesBarWidthDesktop()
	check(w >= HudChrome.CHALLENGES_BAR_WIDTH_MIN, "width >= min")
	check(w <= HudChrome.CHALLENGES_BAR_WIDTH_MAX, "width <= max")

	check(HudChrome.IsMobileChallengesLayout(360, 0), "téléphone étroit")
	check(not HudChrome.IsMobileChallengesLayout(1280, 0), "tablette/PC large")

	-- Détection mode DesktopDocked / MobileDrawer / ConsoleDocked
	local D = HudChrome.LAYOUT_DESKTOP_DOCKED
	local M = HudChrome.LAYOUT_MOBILE_DRAWER
	local C = HudChrome.LAYOUT_CONSOLE_DOCKED
	check(HudChrome.GetChallengeLayoutMode(1920, 1080, false) == D, "desktop large → DesktopDocked")
	check(HudChrome.GetChallengeLayoutMode(1920, 1080, true) == D, "grand tactile large → DesktopDocked")
	check(HudChrome.GetChallengeLayoutMode(1280, 720, false) == D, "PC large sans manette → DesktopDocked")
	check(HudChrome.GetChallengeLayoutMode(1366, 768, false) == D, "laptop → DesktopDocked")
	check(HudChrome.GetChallengeLayoutMode(375, 812, true) == M, "téléphone portrait → MobileDrawer")
	check(HudChrome.GetChallengeLayoutMode(375, 812, false) == M, "portrait étroit SANS touch → MobileDrawer (émulateur Studio)")
	check(HudChrome.GetChallengeLayoutMode(630, 1536, false) == M, "capture 630×1536 sans touch → MobileDrawer")
	check(HudChrome.GetChallengeLayoutMode(812, 375, true) == M, "téléphone paysage étroit → MobileDrawer")
	check(HudChrome.GetChallengeLayoutMode(812, 375, false) == M, "phone paysage SANS touch → MobileDrawer")
	check(HudChrome.GetChallengeLayoutMode(700, 400, true) == M, "petit tactile → MobileDrawer")
	check(HudChrome.GetChallengeLayoutMode(1024, 768, true) == D, "grande tablette paysage → DesktopDocked")
	check(HudChrome.GetChallengeLayoutMode(800, 600, false) == M, "côté court <700 (Studio) → MobileDrawer")
	check(HudChrome.GetChallengeLayoutMode(1280, 720, false) == D, "720p non-phone → DesktopDocked")
	check(
		HudChrome.ResolveLayoutMode(1920, 1080, {
			touchEnabled = false,
			gamepadEnabled = true,
			keyboardEnabled = false,
			mouseEnabled = false,
			preferredInput = nil,
		}) == C,
		"Xbox sans PreferredInput (manette seule) → ConsoleDocked"
	)
	check(
		HudChrome.ResolveLayoutMode(1920, 1080, {
			touchEnabled = false,
			gamepadEnabled = true,
			keyboardEnabled = true,
			mouseEnabled = true,
			preferredInput = nil,
		}) == D,
		"PC manette branchée sans PreferredInput → DesktopDocked"
	)

	-- ResolveLayoutMode — matrice plateformes obligatoire
	local layoutCases = {
		{
			name = "Phone portrait touch",
			w = 630,
			h = 1536,
			opts = {
				touchEnabled = true,
				gamepadEnabled = false,
				keyboardEnabled = false,
				mouseEnabled = false,
				preferredInput = "Touch",
			},
			expected = M,
		},
		{
			name = "Phone portrait with Bluetooth gamepad",
			w = 630,
			h = 1536,
			opts = {
				touchEnabled = true,
				gamepadEnabled = true,
				keyboardEnabled = false,
				mouseEnabled = false,
				preferredInput = "Gamepad",
			},
			expected = M,
		},
		{
			name = "Phone landscape touch",
			w = 844,
			h = 390,
			opts = {
				touchEnabled = true,
				gamepadEnabled = false,
				keyboardEnabled = false,
				mouseEnabled = false,
				preferredInput = "Touch",
			},
			expected = M,
		},
		{
			name = "Xbox television",
			w = 1920,
			h = 1080,
			opts = {
				touchEnabled = false,
				gamepadEnabled = true,
				keyboardEnabled = false,
				mouseEnabled = false,
				preferredInput = "Gamepad",
			},
			expected = C,
		},
		{
			name = "Desktop keyboard mouse",
			w = 1920,
			h = 1080,
			opts = {
				touchEnabled = false,
				gamepadEnabled = true,
				keyboardEnabled = true,
				mouseEnabled = true,
				preferredInput = "KeyboardAndMouse",
			},
			expected = D,
		},
		{
			name = "Desktop gamepad preferred only (non-touch large)",
			w = 1920,
			h = 1080,
			opts = {
				touchEnabled = false,
				gamepadEnabled = true,
				keyboardEnabled = true,
				mouseEnabled = true,
				preferredInput = "Gamepad",
			},
			expected = C,
		},
		{
			name = "Phone gamepad preferred still mobile",
			w = 390,
			h = 844,
			opts = {
				touchEnabled = true,
				gamepadEnabled = true,
				preferredInput = "Gamepad",
			},
			expected = M,
		},
	}
	for _, case in ipairs(layoutCases) do
		local got = HudChrome.ResolveLayoutMode(case.w, case.h, case.opts)
		check(got == case.expected, case.name .. " → " .. case.expected .. " (got " .. tostring(got) .. ")")
	end

	-- Isolation logique panneau / drawer
	check(HudChrome.IsPanelContentShown(M, "Closed") == false, "mobile closed hidden")
	check(HudChrome.IsPanelContentShown(M, "Open") == true, "mobile open shown")
	check(HudChrome.IsPanelContentShown(D, "Closed") == true, "desktop permanent despite Closed string")
	check(HudChrome.IsPanelContentShown(C, "Closed") == true, "console permanent")

	-- ConsoleDocked 1920×1080 gamepad : panneau toujours logiquement affiché
	check(HudChrome.IsPermanentDockedMode(C), "ConsoleDocked permanent")
	check(HudChrome.IsConsoleDockedMode(C), "IsConsoleDockedMode")
	check(not HudChrome.IsMobileDrawerMode(C), "Console n'est pas MobileDrawer")
	check(not HudChrome.IsMobileDrawerMode(D), "Desktop n'est pas MobileDrawer")

	-- Anti-régression : modules de diagnostic absents
	local okBI = pcall(function()
		return require(Shared.BuildInfo)
	end)
	check(not okBI, "module BuildInfo retiré")
	local cfg = require(Shared.ChallengeUIConfig) :: any
	check(cfg.ShowBuildTag == false, "ShowBuildTag off")
	check(cfg.DebugRuntime == false, "DebugRuntime off")

	-- Géométrie console 1920×1080
	local bounds = HudChrome.ExpectedConsoleDockBounds(1920, 1080, 36, 24)
	check(bounds.panelWidth >= 330 and bounds.panelWidth <= 430, "panel console largeur")
	check(bounds.left >= 0, "dock console left >= 0")
	check(bounds.right <= 1920, "dock console right <= vw")
	check(bounds.top >= 0, "dock console top >= 0")
	check(bounds.bottom <= 1080, "dock console bottom <= vh")
	check(bounds.dockWidth > 250, "dock width > 250")
	check(
		HudChrome.IsConsoleGeometryValid(true, bounds.left + 48, bounds.top, bounds.panelWidth, bounds.bottom - bounds.top, 1920, 1080),
		"géométrie console valide simulée"
	)
	check(not HudChrome.IsConsoleGeometryValid(false, 100, 100, 300, 600, 1920, 1080), "visible=false invalide")
	check(not HudChrome.IsConsoleGeometryValid(true, 2000, 0, 300, 600, 1920, 1080), "hors viewport X")

	-- Géométrie console
	local cw = HudChrome.ConsolePanelWidth(1920)
	check(cw >= 330 and cw <= 430, "largeur console 330–430")
	check(cw == math.clamp(math.floor(1920 * 0.23), 330, 430), "formule largeur console 0.23")
	local mx, my = HudChrome.ConsoleSafeMargins(36, 24)
	check(mx >= 24 and mx <= 48, "safe margin X")
	check(my >= 18 and my <= 36, "safe margin Y")
	local cpos = HudChrome.ConsoleDockPosition(mx, my)
	check(cpos.X.Scale == 1 and cpos.X.Offset == -mx, "position console ancrée droite + marge")
	check(cpos.Y.Offset == my, "position console top safe")
	local csize = HudChrome.ConsoleDockSize(400, my)
	check(csize.Y.Offset == -(my * 2), "hauteur console -2*marge")
	check(not HudChrome.IsPanelOffScreenRight(1920 - mx - cw, 1920), "panneau console dans le viewport")

	check(HudChrome.IsPanelOffScreenRight(630, 630), "assertion hors écran X>=vw")
	check(not HudChrome.IsPanelOffScreenRight(200, 630), "encore visible si absX < vw")
	local closedOff = HudChrome.MobileDrawerPanelWidth(630, 1536) + 8
	check(closedOff > 630 * 0.5, "offset fermé dépasse largement le bord")
	-- Position fermée mobile hors viewport 630
	local closedPos = HudChrome.MobileDrawerClosedPosition(closedOff - 8, 0)
	check(closedPos.X.Offset >= 630 * 0.5, "offset fermé grand")

	-- Formules largeur tiroir
	local portW = HudChrome.MobileDrawerPanelWidth(390, 844)
	check(portW <= 430, "portrait max 430")
	check(portW <= math.floor(390 * 0.92 + 0.5) + 1, "portrait ~92%")
	check(portW >= math.floor(390 * 0.90), "portrait >= ~90%")
	local landW = HudChrome.MobileDrawerPanelWidth(812, 375)
	check(landW <= 430, "paysage max 430")
	check(landW <= math.floor(812 * 0.68) + 1, "paysage <= ~68%")
	check(landW == math.min(math.floor(812 * 0.62 + 0.5), 430), "paysage = ratio ou plafond")
	check(landW >= 220, "paysage min utilisable")
	check(HudChrome.CHALLENGES_DESKTOP_WIDTH_THRESHOLD == 900, "seuil desktop 900")
	check(HudChrome.CHALLENGES_MOBILE_OPEN_BTN_SIZE >= 46 and HudChrome.CHALLENGES_MOBILE_OPEN_BTN_SIZE <= 52, "bouton mobile tactile")
	check(HudChrome.CHALLENGES_MOBILE_CLAIM_HEIGHT >= 42, "claim touch target")

	-- Barre mobile : 3 boutons non superposés (positions empilées)
	local btnS = 48
	local gapS = 8
	local topS = 8
	local yInv = topS
	local yCh = topS + btnS + gapS
	local yMu = topS + 2 * (btnS + gapS)
	check(yInv ~= yCh, "Inventory et Challenges Y distincts")
	check(yCh ~= yMu, "Challenges et Music Y distincts")
	local function overlap(aY: number, bY: number, h: number): boolean
		return aY < bY + h and aY + h > bY
	end
	check(not overlap(yInv, yCh, btnS), "pas de chevauchement Inv/Challenges")
	check(not overlap(yCh, yMu, btnS), "pas de chevauchement Challenges/Music")
	check(not overlap(yInv, yMu, btnS), "pas de chevauchement Inv/Music")
	-- Position fermée absolue attendue : absX >= vw
	local vw = 628
	local mw = HudChrome.MobileDrawerPanelWidth(vw, 1536)
	check(mw == math.min(math.floor(vw * 0.92), 430), "628 portrait width formula")
	check(HudChrome.IsPanelOffScreenRight(vw + 8, vw), "fermé hors écran")

	-- Unicité sémantique : un seul panneau named ChallengesPanel
	check(HudChrome.CHALLENGES_PANEL_NAME == "ChallengesPanel", "nom panneau stable")
	check(HudChrome.CHALLENGES_DOCK_NAME == "ChallengesDock", "nom dock stable")

	for _, bad in ipairs(HudChrome.FORBIDDEN_TRACKER_NAMES) do
		check(HudChrome.IsForbiddenTrackerName(bad), "interdit: " .. bad)
	end

	-- Rail vertical à gauche du panneau (pas de toolbar supérieure) — desktop
	local icon = HudChrome.CHALLENGES_ICON_SIZE
	local panelW = HudChrome.ChallengesBarWidthDesktop()
	local railH = HudChrome.ChallengesRailHeight()
	local railW = HudChrome.CHALLENGES_RAIL_WIDTH
	check(railW < panelW, "rail plus étroit que panneau")
	check(railH == icon * 3 + HudChrome.CHALLENGES_ICON_GAP * 2, "hauteur rail exacte")
	check(icon <= 48, "boutons rail max 48px")
	check(HudChrome.CHALLENGES_ICON_GLYPH_SIZE <= 24, "glyphe compact")
	check(HudChrome.ChallengesPanelTopOffset() == 0, "panneau pleine hauteur (offset 0)")
	check(not HudChrome.HasTopToolbarReserve(HudChrome.ChallengesPanelTopOffset()), "aucune réserve haut")
	check(HudChrome.ChallengesDockWidth(panelW) == railW + HudChrome.CHALLENGES_RAIL_PANEL_GAP + panelW, "dock = rail + gap + panel")
	-- Hauteur récupérée vs ancienne colonne 64×3 : panneau peut occuper 100% hauteur utile
	local heightGain = HudChrome.ACTION_BUTTON_SIZE * 3 + HudChrome.ACTION_BUTTON_GAP * 2
	check(heightGain >= 100, "ancienne colonne libérée pour la liste Challenges")

	if ok then
		print("[ChallengeUiLayoutTests] OK")
	end
	return ok
end

return ChallengeUiLayoutTests
