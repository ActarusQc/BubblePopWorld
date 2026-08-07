--!strict
-- Layout & helpers chrome HUD (panneau stats + colonne d'actions).
-- Pure data / fonctions : testable hors Studio sans Instances GUI.

local HudChrome = {}

HudChrome.SCREEN_NAME = "BPW_HUD"
HudChrome.STATS_PANEL_NAME = "StatsPanel"
HudChrome.ACTION_COLUMN_NAME = "ActionButtons"
HudChrome.INVENTORY_BUTTON_NAME = "InventoryButton"
HudChrome.CHALLENGES_BUTTON_NAME = "ChallengesButton"
HudChrome.MUSIC_BUTTON_NAME = "MusicMuteButton"

-- Ordre vertical obligatoire de la colonne droite.
HudChrome.ACTION_ORDER = {
	HudChrome.INVENTORY_BUTTON_NAME,
	HudChrome.CHALLENGES_BUTTON_NAME,
	HudChrome.MUSIC_BUTTON_NAME,
} :: { string }

-- Desktop cible (px) — colonne étroite (3e passe, coupe zone vide à droite).
HudChrome.DESKTOP_PANEL_WIDTH = 216
HudChrome.DESKTOP_PANEL_HEIGHT = 124
HudChrome.DESKTOP_PANEL_PAD = 8
HudChrome.DESKTOP_PANEL_TOP = 10
HudChrome.DESKTOP_PANEL_LEFT = 12
HudChrome.DESKTOP_PANEL_CORNER = 10
HudChrome.DESKTOP_PANEL_STROKE = 1
HudChrome.DESKTOP_PANEL_STROKE_TRANSPARENCY = 0.3
HudChrome.DESKTOP_PANEL_BG_TRANSPARENCY = 0.2
HudChrome.ROW_GAP = 2
HudChrome.BAR_HEIGHT = 3
HudChrome.SECTION_GAP = 4
HudChrome.SHOW_COINS_LABEL = false

-- Typographie desktop (px).
HudChrome.FONT_COINS = 19
HudChrome.FONT_COINS_UNIT = 0 -- libellé "coins" retiré
HudChrome.FONT_BACKPACK = 12
HudChrome.FONT_LEVEL = 11
HudChrome.FONT_STATUS = 10

-- Ordre de lecture demandé : Coins → Backpack → Level/XP → Status
HudChrome.STATS_ORDER = { "Coins", "Backpack", "LevelXp", "Status" } :: { string }

HudChrome.ACTION_BUTTON_SIZE = 64
HudChrome.ACTION_BUTTON_GAP = 12
HudChrome.ACTION_COLUMN_RIGHT = 14
HudChrome.ACTION_COLUMN_TOP = 12

-- Barre Challenges permanente (bord droit) — rail vertical à GAUCHE du panneau.
HudChrome.CHALLENGES_DOCK_NAME = "ChallengesDock"
HudChrome.CHALLENGES_PANEL_NAME = "ChallengesPanel"
HudChrome.CHALLENGES_BAR_WIDTH_DESKTOP = 348
HudChrome.CHALLENGES_BAR_WIDTH_MIN = 330
HudChrome.CHALLENGES_BAR_WIDTH_MAX = 365
-- Rétrocompat : largeur « étroit » historique (préférer GetChallengeLayoutMode).
HudChrome.CHALLENGES_MOBILE_BREAKPOINT = 700
-- Seuils centralisés — ne pas disperser ces valeurs ailleurs.
HudChrome.CHALLENGES_DESKTOP_WIDTH_THRESHOLD = 900
-- Côté court < 700 = téléphone / petit appareil (prioritaire sur console).
HudChrome.CHALLENGES_PHONE_SHORTEST_SIDE = 700
HudChrome.CHALLENGES_MOBILE_PORTRAIT_WIDTH_RATIO = 0.92
HudChrome.CHALLENGES_MOBILE_PORTRAIT_MAX_WIDTH = 430
HudChrome.CHALLENGES_MOBILE_LANDSCAPE_WIDTH_RATIO = 0.62
HudChrome.CHALLENGES_MOBILE_LANDSCAPE_MAX_WIDTH = 430
HudChrome.CHALLENGES_MOBILE_OPEN_BTN_SIZE = 48
HudChrome.CHALLENGES_MOBILE_OPEN_BTN_GLYPH = 24
HudChrome.CHALLENGES_MOBILE_OPEN_BTN_EDGE = 8
HudChrome.CHALLENGES_MOBILE_OPEN_BTN_TOP = 8
HudChrome.CHALLENGES_MOBILE_DRAWER_TWEEN = 0.24
HudChrome.CHALLENGES_MOBILE_BACKDROP_TRANSPARENCY = 0.62
HudChrome.CHALLENGES_STUDIO_DEBUG = true -- logs runtime Studio (désactivés hors Studio)
HudChrome.CHALLENGES_MOBILE_HEADER_HEIGHT = 40
HudChrome.CHALLENGES_MOBILE_TABS_HEIGHT = 40
HudChrome.CHALLENGES_MOBILE_CARD_PADDING = 11
HudChrome.CHALLENGES_MOBILE_CARD_GAP = 8
HudChrome.CHALLENGES_MOBILE_CLAIM_HEIGHT = 44
HudChrome.CHALLENGES_BOTTOM_MARGIN = 2
-- Modes de disposition (DesktopDocked | MobileDrawer | ConsoleDocked)
HudChrome.LAYOUT_DESKTOP_DOCKED = "DesktopDocked"
HudChrome.LAYOUT_MOBILE_DRAWER = "MobileDrawer"
HudChrome.LAYOUT_CONSOLE_DOCKED = "ConsoleDocked"
-- Rail d’icônes vertical collé à gauche du panneau (pas au-dessus) — dock permanent.
HudChrome.CHALLENGES_ICON_SIZE = 44 -- zone cliquable
HudChrome.CHALLENGES_ICON_SIZE_MOBILE = 44
HudChrome.CHALLENGES_ICON_GLYPH_SIZE = 22 -- glyphe interne
HudChrome.CHALLENGES_ICON_GAP = 6
HudChrome.CHALLENGES_RAIL_PANEL_GAP = 4 -- espace entre rail et panneau
HudChrome.CHALLENGES_RAIL_WIDTH = 48 -- largeur du rail (bouton + marge)
HudChrome.DOCKED_ACTIONS_ATTR = "BPW_DockedActions"

-- Largeur totale dock = rail + gap + panneau
function HudChrome.ChallengesDockWidth(panelW: number?, railW: number?, gap: number?): number
	local p = panelW or HudChrome.CHALLENGES_BAR_WIDTH_DESKTOP
	local r = railW or HudChrome.CHALLENGES_RAIL_WIDTH
	local g = gap or HudChrome.CHALLENGES_RAIL_PANEL_GAP
	return r + g + p
end

-- Hauteur du rail (3 boutons empilés + 2 gaps).
function HudChrome.ChallengesRailHeight(btnSize: number?, gap: number?): number
	local btn = btnSize or HudChrome.CHALLENGES_ICON_SIZE
	local g = gap or HudChrome.CHALLENGES_ICON_GAP
	return btn * 3 + g * 2
end

export type ChallengeLayoutOptions = {
	touchEnabled: boolean?,
	gamepadEnabled: boolean?,
	keyboardEnabled: boolean?,
	mouseEnabled: boolean?,
	preferredInput: string?, -- "Gamepad" | "Touch" | "KeyboardAndMouse" | nil
}

-- Matrice plateformes (pure / testable).
-- PRIORITÉ 1 : tactile étroit / téléphone → toujours MobileDrawer (même manette branchée).
-- PRIORITÉ 2 : grand écran non tactile + manette principale → ConsoleDocked.
-- PRIORITÉ 3 : DesktopDocked.
-- Jamais : GamepadEnabled seul = console. Jamais PreferredInput Gamepad sur tactile étroit.
function HudChrome.ResolveLayoutMode(
	viewportWidth: number,
	viewportHeight: number,
	options: ChallengeLayoutOptions?
): string
	local opts = options or {}
	local touchEnabled = opts.touchEnabled == true
	local gamepadEnabled = opts.gamepadEnabled == true
	local keyboardEnabled = opts.keyboardEnabled == true
	local mouseEnabled = opts.mouseEnabled == true
	local preferredInput = opts.preferredInput

	local w = math.max(1, math.floor(viewportWidth))
	local h = math.max(1, math.floor(viewportHeight))
	local isPortrait = h > w
	local isNarrow = w < HudChrome.CHALLENGES_DESKTOP_WIDTH_THRESHOLD
	local isPhoneSized = math.min(w, h) < (HudChrome.CHALLENGES_PHONE_SHORTEST_SIDE or 700)

	-- PRIORITÉ 1a : téléphone / tablette tactile (manette Bluetooth ignorée).
	if touchEnabled and (isPhoneSized or isPortrait or isNarrow) then
		return HudChrome.LAYOUT_MOBILE_DRAWER
	end

	-- PRIORITÉ 1b : form factor téléphone (Studio emulator TouchEnabled=false).
	if isPhoneSized or (isNarrow and isPortrait) then
		return HudChrome.LAYOUT_MOBILE_DRAWER
	end

	-- PRIORITÉ 2 : console TV uniquement (grand paysage, non tactile, manette primaire).
	-- PreferredInput Gamepad compte ; GamepadEnabled seul est insuffisant.
	-- PreferredInput KeyboardAndMouse force Desktop même si manette branchée.
	local isLargeLandscape = w >= HudChrome.CHALLENGES_DESKTOP_WIDTH_THRESHOLD and w > h
	if not touchEnabled and isLargeLandscape then
		if preferredInput == "Gamepad" then
			return HudChrome.LAYOUT_CONSOLE_DOCKED
		end
		if preferredInput == "KeyboardAndMouse" then
			return HudChrome.LAYOUT_DESKTOP_DOCKED
		end
		-- preferred inconnu / nil (clients anciens) : Xbox typique = manette sans clavier/souris.
		if preferredInput == nil and gamepadEnabled and not keyboardEnabled and not mouseEnabled then
			return HudChrome.LAYOUT_CONSOLE_DOCKED
		end
	end

	-- PRIORITÉ 3 : bureau / défaut.
	return HudChrome.LAYOUT_DESKTOP_DOCKED
end

-- Rétrocompat : signature (w, h, touchEnabled) sans options manette.
function HudChrome.GetChallengeLayoutMode(
	viewportWidth: number,
	viewportHeight: number,
	touchEnabled: boolean
): string
	return HudChrome.ResolveLayoutMode(viewportWidth, viewportHeight, {
		touchEnabled = touchEnabled,
		gamepadEnabled = false,
		keyboardEnabled = false,
		mouseEnabled = false,
		preferredInput = nil,
	})
end

-- Visibilité logique du panneau (drawer mobile vs dock permanent).
function HudChrome.IsPanelContentShown(mode: string, mobileDrawerState: string): boolean
	if mode == HudChrome.LAYOUT_MOBILE_DRAWER then
		return mobileDrawerState == "Open" or mobileDrawerState == "Opening"
	end
	-- DesktopDocked / ConsoleDocked : toujours « permanent » (pas d’état drawer).
	return true
end

function HudChrome.IsDesktopDockedMode(mode: string): boolean
	return mode == HudChrome.LAYOUT_DESKTOP_DOCKED
end

function HudChrome.IsMobileDrawerMode(mode: string): boolean
	return mode == HudChrome.LAYOUT_MOBILE_DRAWER
end

function HudChrome.IsConsoleDockedMode(mode: string): boolean
	return mode == HudChrome.LAYOUT_CONSOLE_DOCKED
end

-- Barre permanente visible (PC ou console TV).
function HudChrome.IsPermanentDockedMode(mode: string): boolean
	return mode == HudChrome.LAYOUT_DESKTOP_DOCKED or mode == HudChrome.LAYOUT_CONSOLE_DOCKED
end

-- Largeur panneau console (ratio viewport, clamp TV).
function HudChrome.ConsolePanelWidth(viewportWidth: number, ratio: number?, minW: number?, maxW: number?): number
	local w = math.max(1, math.floor(viewportWidth))
	local r = ratio or 0.23
	local lo = minW or 330
	local hi = maxW or 430
	return math.clamp(math.floor(w * r), lo, hi)
end

function HudChrome.ConsoleSafeMargins(marginX: number?, marginY: number?): (number, number)
	local mx = math.clamp(math.floor(marginX or 36), 24, 48)
	local my = math.clamp(math.floor(marginY or 24), 18, 36)
	return mx, my
end

-- Position panneau console (AnchorPoint 1,0) — hors offset mobile fermé.
function HudChrome.ConsoleDockPosition(safeMarginX: number, safeMarginY: number): UDim2
	return UDim2.new(1, -safeMarginX, 0, safeMarginY)
end

function HudChrome.ConsoleDockSize(dockWidth: number, safeMarginY: number): UDim2
	return UDim2.new(0, dockWidth, 1, -(safeMarginY * 2))
end

-- Largeur tiroir mobile (portrait 92% max 430 ; paysage 62% max 430).
function HudChrome.MobileDrawerPanelWidth(viewportWidth: number, viewportHeight: number): number
	local w = math.max(1, math.floor(viewportWidth))
	local h = math.max(1, math.floor(viewportHeight))
	local landscape = w > h
	if landscape then
		return math.clamp(
			math.floor(w * HudChrome.CHALLENGES_MOBILE_LANDSCAPE_WIDTH_RATIO + 0.5),
			220,
			HudChrome.CHALLENGES_MOBILE_LANDSCAPE_MAX_WIDTH
		)
	end
	return math.clamp(
		math.floor(w * HudChrome.CHALLENGES_MOBILE_PORTRAIT_WIDTH_RATIO + 0.5),
		260,
		HudChrome.CHALLENGES_MOBILE_PORTRAIT_MAX_WIDTH
	)
end

-- Positions mobile : AnchorPoint =(1,0) ; Offset X = +width ferme hors écran.
function HudChrome.MobileDrawerOpenPosition(topInset: number?): UDim2
	return UDim2.new(1, 0, 0, topInset or 0)
end

function HudChrome.MobileDrawerClosedPosition(panelWidth: number, topInset: number?): UDim2
	return UDim2.new(1, math.max(1, math.floor(panelWidth)) + 8, 0, topInset or 0)
end

-- Assertion pure : panneau hors viewport si absX >= vw (AnchorPoint 1,0).
function HudChrome.IsPanelOffScreenRight(absoluteX: number, viewportWidth: number): boolean
	return absoluteX >= viewportWidth - 0.5
end

-- True si largeur utilisable suggère un form factor mobile (sans touch ; tests rétrocompat).
function HudChrome.IsMobileChallengesLayout(viewportWidth: number, guiInsetLeft: number?): boolean
	local usable = viewportWidth - (guiInsetLeft or 0)
	return usable < HudChrome.CHALLENGES_DESKTOP_WIDTH_THRESHOLD
end

-- Ancrage dock : collé bord droit, plein haut (pas d'offset toolbar).
function HudChrome.IsChallengesRightDocked(anchorX: number, posScaleX: number, posOffsetX: number): boolean
	return anchorX == 1 and posScaleX == 1 and posOffsetX == 0
end

-- Vérifie qu'aucune barre n'est placée AU-DESSUS du panneau (espace supérieur fictif).
function HudChrome.HasTopToolbarReserve(reservedTopPx: number): boolean
	return reservedTopPx > 8
end

function HudChrome.ChallengesBarWidthDesktop(): number
	local w = HudChrome.CHALLENGES_BAR_WIDTH_DESKTOP
	return math.clamp(w, HudChrome.CHALLENGES_BAR_WIDTH_MIN, HudChrome.CHALLENGES_BAR_WIDTH_MAX)
end

-- Rétrocompat (anciens tests toolbar horizontale) — mappe vers rail vertical.
function HudChrome.ChallengesToolbarWidth(btnSize: number?, gap: number?): number
	return HudChrome.ChallengesRailHeight(btnSize, gap) -- unused; prefer ChallengesRailHeight
end

function HudChrome.ChallengesPanelTopOffset(_toolbarH: number?, _gap: number?): number
	-- Plus de toolbar au-dessus : panneau pleine hauteur dès le top safe.
	return 0
end

-- Aucune carte compacte centrale ne doit exister (noms historiques interdits).
HudChrome.FORBIDDEN_TRACKER_NAMES = {
	"TrackedCard",
	"CardCollapsed",
	"PinnedChallenge",
	"TrackedChallenge",
	"CompactChallenge",
	"ChallengeTracker",
} :: { string }

function HudChrome.IsForbiddenTrackerName(name: string): boolean
	for _, n in ipairs(HudChrome.FORBIDDEN_TRACKER_NAMES) do
		if n == name then
			return true
		end
	end
	return false
end

HudChrome.BG = Color3.fromRGB(10, 14, 24)
HudChrome.BG_BUTTON = Color3.fromRGB(14, 18, 30)
HudChrome.ACCENT = Color3.fromRGB(90, 220, 255)
HudChrome.COIN_YELLOW = Color3.fromRGB(255, 210, 70)
HudChrome.COIN_UNIT = Color3.fromRGB(210, 175, 70)
HudChrome.TEXT_SECONDARY = Color3.fromRGB(210, 220, 235)
HudChrome.TEXT_MUTED = Color3.fromRGB(150, 175, 195)
HudChrome.BAR_TRACK = Color3.fromRGB(26, 32, 46)

HudChrome.CHALLENGES_LOG = "[ChallengesUI] Challenges panel not implemented yet"

-- Icônes : glyphes blancs (pas d'asset externe / InsertService).
HudChrome.ICON_INVENTORY = "🎒"
HudChrome.ICON_CHALLENGES = "📋"
HudChrome.ICON_MUSIC = "♪"
HudChrome.ICON_MUSIC_MUTED = "♪/"

function HudChrome.Comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

function HudChrome.FormatLevelLine(levelWord: string, level: number): string
	return ("%s %s"):format(levelWord, tostring(level))
end

function HudChrome.FormatXpLine(current: number, required: number?): string
	if required == nil then
		return "MAX"
	end
	return ("%s / %s"):format(HudChrome.Comma(current), HudChrome.Comma(required))
end

function HudChrome.FormatBackpackLine(backpackWord: string, current: number, capacity: number): string
	return ("%s %s / %s"):format(backpackWord, HudChrome.Comma(current), HudChrome.Comma(capacity))
end

function HudChrome.XpRatio(sold: number, levelStart: number, nextAt: number?): number
	if nextAt == nil then
		return 1
	end
	local span = nextAt - levelStart
	if span <= 0 then
		return 1
	end
	return math.clamp((sold - levelStart) / span, 0, 1)
end

function HudChrome.BackpackRatio(current: number, capacity: number): number
	if capacity <= 0 then
		return 0
	end
	return math.clamp(current / capacity, 0, 1)
end

function HudChrome.ActionLayoutOrder(buttonName: string): number?
	for i, name in ipairs(HudChrome.ACTION_ORDER) do
		if name == buttonName then
			return i
		end
	end
	return nil
end

function HudChrome.IsDailyLabel(text: string): boolean
	local upper = string.upper(text)
	return string.find(upper, "DAILY", 1, true) ~= nil
end

-- Point d'entrée Challenges : aucune donnée joueur, un seul log max.
function HudChrome.CreateOpenChallenges(logFn: ((string) -> ())?): () -> ()
	local logged = false
	local logger = logFn or print
	return function()
		if logged then
			return
		end
		logged = true
		logger(HudChrome.CHALLENGES_LOG)
	end
end

export type PanelMetrics = {
	Width: number,
	Height: number,
	Area: number,
}

function HudChrome.DesktopPanelMetrics(): PanelMetrics
	local w = HudChrome.DESKTOP_PANEL_WIDTH
	local h = HudChrome.DESKTOP_PANEL_HEIGHT
	return {
		Width = w,
		Height = h,
		Area = w * h,
	}
end

-- True si le panneau desktop reste dans les fourchettes colonne compacte (3e passe).
function HudChrome.ValidateDesktopPanelSize(width: number, height: number): boolean
	return width >= 200
		and width <= 240
		and height >= 110
		and height <= 140
end

function HudChrome.ValidateTypography(): boolean
	return HudChrome.FONT_COINS >= 18
		and HudChrome.FONT_COINS <= 22
		and HudChrome.FONT_BACKPACK >= 11
		and HudChrome.FONT_BACKPACK <= 13
		and HudChrome.FONT_LEVEL >= 10
		and HudChrome.FONT_LEVEL <= 12
		and HudChrome.FONT_STATUS >= 9
		and HudChrome.FONT_STATUS <= 11
		and HudChrome.FONT_COINS > HudChrome.FONT_BACKPACK
		and HudChrome.FONT_BACKPACK >= HudChrome.FONT_LEVEL
		and HudChrome.FONT_LEVEL >= HudChrome.FONT_STATUS
		and HudChrome.BAR_HEIGHT <= 4
		and HudChrome.SHOW_COINS_LABEL == false
end

-- Bounds approximatifs pour une résolution (ignore inset Roblox — offset additionnel à appliquer côté client).
function HudChrome.ColumnFitsViewport(
	viewportWidth: number,
	viewportHeight: number,
	guiInsetTop: number,
	guiInsetLeft: number
): boolean
	local btn = HudChrome.ACTION_BUTTON_SIZE
	local gap = HudChrome.ACTION_BUTTON_GAP
	local count = #HudChrome.ACTION_ORDER
	local colH = btn * count + gap * (count - 1)
	local colW = btn
	local right = HudChrome.ACTION_COLUMN_RIGHT
	local top = HudChrome.ACTION_COLUMN_TOP + guiInsetTop
	local leftEdge = viewportWidth - right - colW
	local bottomEdge = top + colH
	return leftEdge >= guiInsetLeft
		and bottomEdge <= viewportHeight
		and colW >= 44 -- tactile minimal
		and btn >= 44
end

function HudChrome.StatsPanelFitsViewport(
	viewportWidth: number,
	viewportHeight: number,
	guiInsetTop: number,
	guiInsetLeft: number
): boolean
	local w = HudChrome.DESKTOP_PANEL_WIDTH
	local h = HudChrome.DESKTOP_PANEL_HEIGHT
	local x = guiInsetLeft + HudChrome.DESKTOP_PANEL_LEFT
	local y = guiInsetTop + HudChrome.DESKTOP_PANEL_TOP
	return x + w <= viewportWidth and y + h <= viewportHeight and h >= 100
end

-- Helpers géométrie console testables (pure)
function HudChrome.ExpectedConsoleDockBounds(
	viewportWidth: number,
	viewportHeight: number,
	safeMarginX: number?,
	safeMarginY: number?,
	panelWidthRatio: number?,
	panelMin: number?,
	panelMax: number?
): { left: number, top: number, right: number, bottom: number, dockWidth: number, panelWidth: number }
	local mx, my = HudChrome.ConsoleSafeMargins(safeMarginX, safeMarginY)
	local panelW = HudChrome.ConsolePanelWidth(viewportWidth, panelWidthRatio, panelMin, panelMax)
	local railW = HudChrome.CHALLENGES_RAIL_WIDTH or 48
	local gap = HudChrome.CHALLENGES_RAIL_PANEL_GAP or 4
	local dockW = HudChrome.ChallengesDockWidth(panelW, railW, gap)
	local right = viewportWidth - mx
	local left = right - dockW
	local top = my
	local bottom = viewportHeight - my
	return {
		left = left,
		top = top,
		right = right,
		bottom = bottom,
		dockWidth = dockW,
		panelWidth = panelW,
	}
end

function HudChrome.IsConsoleGeometryValid(
	panelVisible: boolean,
	absX: number,
	absY: number,
	absW: number,
	absH: number,
	viewportWidth: number,
	viewportHeight: number
): boolean
	if panelVisible ~= true then
		return false
	end
	if absW <= 250 or absH <= 200 then
		return false
	end
	local pad = 4
	if absX < -pad or absY < -pad then
		return false
	end
	if absX + absW > viewportWidth + pad then
		return false
	end
	if absY + absH > viewportHeight + pad then
		return false
	end
	return true
end

return HudChrome
