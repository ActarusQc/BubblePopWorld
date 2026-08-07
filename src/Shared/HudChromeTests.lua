--!strict
-- Tests purs HudChrome (layout HUD, boutons d'action, Challenges stub).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudChrome = require(Shared.HudChrome)
local L10n = require(Shared.LocalizationStrings)

local HudChromeTests = {}

function HudChromeTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[HudChromeTests] FAIL:", msg)
		end
	end

	-- 1) Identité d'un seul HUD / noms stables
	check(HudChrome.SCREEN_NAME == "BPW_HUD", "screen name BPW_HUD")
	check(HudChrome.STATS_PANEL_NAME == "StatsPanel", "stats panel name")
	check(HudChrome.ACTION_COLUMN_NAME == "ActionButtons", "action column name")

	-- 2) Mise en forme Coins / Level / XP / Backpack
	check(HudChrome.Comma(8141) == "8 141", "coins format espaces")
	check(HudChrome.FormatLevelLine(L10n.Level, 4) == "Level 4", "level line")
	check(HudChrome.FormatXpLine(652, 900) == "652 / 900", "xp line")
	check(HudChrome.FormatXpLine(100, nil) == "MAX", "xp max")
	check(
		HudChrome.FormatBackpackLine(L10n.Backpack, 0, 25) == "Backpack: 0 / 25",
		"backpack line"
	)
	check(math.abs(HudChrome.XpRatio(652, 0, 900) - 652 / 900) < 1e-6, "xp ratio")
	check(HudChrome.BackpackRatio(0, 25) == 0, "backpack empty ratio")
	check(HudChrome.BackpackRatio(25, 25) == 1, "backpack full ratio")

	-- 3) Inventory order + no permanent Inventory on icon chrome
	check(HudChrome.ACTION_ORDER[1] == "InventoryButton", "order[1] Inventory")
	check(HudChrome.ICON_INVENTORY ~= "Inventory", "icon n'est pas le mot Inventory")

	-- 4–7) Challenges présent, pas de DAILY, entrypoint sans spam
	check(HudChrome.ACTION_ORDER[2] == "ChallengesButton", "order[2] Challenges")
	check(L10n.Challenges == "Challenges", "label Challenges localisé")
	check(not HudChrome.IsDailyLabel(L10n.Challenges), "pas de DAILY dans Challenges")
	check(not HudChrome.IsDailyLabel(HudChrome.ICON_CHALLENGES), "icône sans DAILY")

	local logs = {}
	local open = HudChrome.CreateOpenChallenges(function(msg: string)
		table.insert(logs, msg)
	end)
	open()
	open()
	open()
	check(#logs == 1, "OpenChallenges log unique")
	check(logs[1] == HudChrome.CHALLENGES_LOG, "message Challenges stub")

	-- 8–9) Music + ordre vertical
	check(HudChrome.ACTION_ORDER[3] == "MusicMuteButton", "order[3] Music")
	check(HudChrome.ActionLayoutOrder("InventoryButton") == 1, "layout Inventory=1")
	check(HudChrome.ActionLayoutOrder("ChallengesButton") == 2, "layout Challenges=2")
	check(HudChrome.ActionLayoutOrder("MusicMuteButton") == 3, "layout Music=3")
	check(#HudChrome.ACTION_ORDER == 3, "exactement 3 boutons d'action")

	-- 10) Accessibilité manette : boutons ≥ 44 px
	check(HudChrome.ACTION_BUTTON_SIZE >= 44, "taille bouton tactile/manette")
	check(HudChrome.ACTION_BUTTON_GAP >= 10 and HudChrome.ACTION_BUTTON_GAP <= 14, "gap 10–14")

	-- 11) Colonne étroite 3e passe + typo + viewport
	local m = HudChrome.DesktopPanelMetrics()
	check(HudChrome.ValidateDesktopPanelSize(m.Width, m.Height), "panneau desktop 200–240 × 110–140")
	check(m.Width == 216 and m.Height == 124, "216×124 desktop")
	check(m.Area < 272 * 128, "plus étroit que la passe 2 (272×128)")
	check(HudChrome.SHOW_COINS_LABEL == false, "mot coins retiré")
	check(HudChrome.STATS_ORDER[1] == "Coins", "ordre: Coins")
	check(HudChrome.STATS_ORDER[2] == "Backpack", "ordre: Backpack")
	check(HudChrome.STATS_ORDER[3] == "LevelXp", "ordre: Level/XP")
	check(HudChrome.STATS_ORDER[4] == "Status", "ordre: Status")
	check(HudChrome.ValidateTypography(), "typographie hiérarchisée")
	check(HudChrome.FONT_COINS == 19, "coins 19px")
	check(HudChrome.FONT_BACKPACK == 12, "backpack 12px")
	check(HudChrome.FONT_LEVEL == 11, "level/xp 11px")
	check(HudChrome.FONT_STATUS == 10, "status 10px")
	check(HudChrome.BAR_HEIGHT == 3, "barres 3px")
	check(HudChrome.DESKTOP_PANEL_STROKE <= 1, "contour fin")

	-- Barre Challenges : rail vertical gauche + panneau pleine hauteur collé à droite
	check(HudChrome.CHALLENGES_BAR_WIDTH_DESKTOP >= 330 and HudChrome.CHALLENGES_BAR_WIDTH_DESKTOP <= 365, "largeur panneau Challenges")
	check(HudChrome.ChallengesBarWidthDesktop() == 348, "largeur desktop 348")
	check(HudChrome.IsChallengesRightDocked(1, 1, 0) == true, "dock droite ancré")
	check(HudChrome.IsChallengesRightDocked(0, 0.5, 0) == false, "pas de centre")
	check(HudChrome.IsChallengesRightDocked(1, 1, -80) == false, "pas d'offset négatif flottant")
	check(HudChrome.IsMobileChallengesLayout(375, 0) == true, "mobile 375")
	check(HudChrome.IsMobileChallengesLayout(1920, 0) == false, "desktop 1920")
	check(HudChrome.GetChallengeLayoutMode(375, 812, true) == HudChrome.LAYOUT_MOBILE_DRAWER, "mode mobile drawer")
	check(HudChrome.GetChallengeLayoutMode(1920, 1080, false) == HudChrome.LAYOUT_DESKTOP_DOCKED, "mode desktop docked")
	check(
		HudChrome.ResolveLayoutMode(1920, 1080, {
			touchEnabled = false,
			gamepadEnabled = true,
			preferredInput = "Gamepad",
		}) == HudChrome.LAYOUT_CONSOLE_DOCKED,
		"mode console docked Xbox"
	)
	check(
		HudChrome.ResolveLayoutMode(630, 1536, {
			touchEnabled = true,
			gamepadEnabled = true,
			preferredInput = "Gamepad",
		}) == HudChrome.LAYOUT_MOBILE_DRAWER,
		"phone + gamepad reste MobileDrawer"
	)
	check(HudChrome.MobileDrawerPanelWidth(390, 844) <= 430, "largeur portrait plafonnée")
	check(HudChrome.IsForbiddenTrackerName("TrackedCard") == true, "TrackedCard interdit")
	check(HudChrome.IsForbiddenTrackerName("ChallengesPanel") == false, "panel autorisé")
	check(HudChrome.CHALLENGES_ICON_SIZE >= 42 and HudChrome.CHALLENGES_ICON_SIZE <= 46, "boutons rail 42–46")
	check(HudChrome.CHALLENGES_ICON_SIZE < HudChrome.ACTION_BUTTON_SIZE, "icônes challenges < legacy 64")
	check(HudChrome.CHALLENGES_ICON_GAP >= 5 and HudChrome.CHALLENGES_ICON_GAP <= 7, "gap vertical rail 5–7")
	check(HudChrome.CHALLENGES_RAIL_WIDTH >= 44 and HudChrome.CHALLENGES_RAIL_WIDTH <= 52, "largeur rail")
	check(HudChrome.CHALLENGES_ICON_GLYPH_SIZE >= 21 and HudChrome.CHALLENGES_ICON_GLYPH_SIZE <= 25, "glyphe 21–25")
	check(HudChrome.ChallengesRailHeight() == 44 * 3 + 6 * 2, "hauteur rail 3×btn + 2×gap")
	check(HudChrome.ChallengesPanelTopOffset() == 0, "aucune réserve toolbar au-dessus")
	check(not HudChrome.HasTopToolbarReserve(0), "pas de bande vide supérieure")
	check(HudChrome.ChallengesDockWidth(348) == 48 + 4 + 348, "largeur dock = rail+gap+panel")

	local targets = {
		{ 1920, 1080, 36, 0 },
		{ 1366, 768, 36, 0 },
		{ 1680, 1050, 36, 0 }, -- 16:10
		{ 812, 375, 24, 0 }, -- mobile paysage
		{ 375, 812, 24, 0 }, -- mobile portrait
		{ 1920, 1080, 36, 0 }, -- Xbox/TV (safe via inset)
	}
	for _, t in ipairs(targets) do
		local vw, vh, top, left = t[1], t[2], t[3], t[4]
		check(
			HudChrome.StatsPanelFitsViewport(vw, vh, top, left),
			("stats fit %dx%d"):format(vw, vh)
		)
		check(
			HudChrome.ColumnFitsViewport(vw, vh, top, left),
			("column fit %dx%d"):format(vw, vh)
		)
	end

	if failed == 0 then
		print("[HudChromeTests] OK")
		return true
	end
	return false
end

return HudChromeTests
