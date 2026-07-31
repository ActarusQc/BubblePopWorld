--!strict
-- Tests hors Roblox de la disposition responsive du browse.
-- Lancer : python tools\run_shop_layout_tests.py

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Layout = require(Shared.ShopBrowseLayout)

local ShopBrowseLayoutTests = {}

local function size(x: number, y: number)
	return { X = x, Y = y }
end

-- Zone réellement disponible : le ScreenGui perd l'inset supérieur (~36 px).
local INSET = 36
local SCREENS = {
	{ Name = "1280x720", Viewport = size(1280, 720), Container = size(1280, 720 - INSET) },
	{ Name = "1920x1080", Viewport = size(1920, 1080), Container = size(1920, 1080 - INSET) },
	{ Name = "2560x1440", Viewport = size(2560, 1440), Container = size(2560, 1440 - INSET) },
	{ Name = "3840x2160", Viewport = size(3840, 2160), Container = size(3840, 2160 - INSET) },
}

function ShopBrowseLayoutTests.Run(): boolean
	local failures = 0
	local checks = 0

	local function check(condition: boolean, label: string)
		checks += 1
		if not condition then
			failures += 1
			print("[ShopBrowseLayout] FAIL: " .. label)
		end
	end

	----------------------------------------------------------------
	-- 1) Choix du mode
	----------------------------------------------------------------

	check(Layout.ResolveMode("Gamepad", size(1920, 1080)) == "Console", "manette + grand écran → Console")
	check(Layout.ResolveMode("Gamepad", size(1280, 720)) == "Console", "manette + 720p → Console")
	check(Layout.ResolveMode("Gamepad", size(3840, 2160)) == "Console", "manette + 4K → Console")
	check(Layout.ResolveMode("KeyboardAndMouse", size(1920, 1080)) == "Desktop", "clavier/souris → Desktop")
	check(Layout.ResolveMode("KeyboardAndMouse", size(3840, 2160)) == "Desktop", "clavier/souris 4K → Desktop")
	check(Layout.ResolveMode("Touch", size(1920, 1080)) == "Mobile", "tactile → Mobile")
	check(Layout.ResolveMode("Touch", size(900, 400)) == "Mobile", "tactile petit écran → Mobile")

	-- Manette sur petit écran : on reste en Desktop, pas de ten-foot UI.
	check(Layout.ResolveMode("Gamepad", size(1024, 600)) == "Desktop", "manette + petit écran → Desktop")
	check(Layout.ResolveMode("Gamepad", size(1280, 600)) == "Desktop", "manette + écran bas → Desktop")
	check(Layout.ResolveMode("Gamepad", size(1100, 720)) == "Desktop", "manette + écran étroit → Desktop")

	-- Client sans PreferredInput : repli sur TouchEnabled, comportement actuel.
	check(Layout.ResolveMode(nil, size(1920, 1080), true) == "Mobile", "repli tactile sans PreferredInput")
	check(Layout.ResolveMode(nil, size(1920, 1080), false) == "Desktop", "repli desktop sans PreferredInput")

	----------------------------------------------------------------
	-- 2) Desktop et Mobile : valeurs validées, strictement figées
	----------------------------------------------------------------

	local desktop = Layout.Resolve("Desktop", size(1920, 1044))
	local mobile = Layout.Resolve("Mobile", size(750, 1334))

	check(desktop.Mode == "Desktop" and mobile.Mode == "Mobile", "modes renvoyés correctement")
	check(desktop.Scale == 1 and mobile.Scale == 1, "aucune mise à l'échelle hors console")

	local expected = {
		{ desktop.Panel.WidthScale, 0.9, "panneau largeur 0.9" },
		{ desktop.Panel.HeightOffset, 190, "panneau hauteur 190" },
		{ desktop.Panel.YOffset, -22, "panneau marge basse 22" },
		{ desktop.Panel.MinSize.X, 300, "panneau MinSize.X 300" },
		{ desktop.Panel.MinSize.Y, 190, "panneau MinSize.Y 190" },
		{ desktop.Panel.MaxSize.X, 640, "panneau MaxSize.X 640" },
		{ desktop.Panel.MaxSize.Y, 220, "panneau MaxSize.Y 220" },
		{ desktop.Panel.Corner, 18, "panneau coin 18" },
		{ desktop.Header.Height, 30, "header hauteur 30" },
		{ desktop.Header.TitleSize, 20, "titre 20" },
		{ desktop.Header.CounterSize, 14, "compteur 14" },
		{ desktop.Header.CoinsSize, 16, "coins 16" },
		{ desktop.Header.CloseSize, 40, "fermeture 40" },
		{ desktop.Header.CloseTextSize, 18, "texte fermeture 18" },
		{ desktop.Body.OffsetY, 46, "corps y 46" },
		{ desktop.Body.HeightOffset, -84, "corps hauteur -84" },
		{ desktop.Body.ContentLeft, 68, "contenu x 68" },
		{ desktop.Body.ContentWidthOffset, -144, "contenu largeur -144" },
		{ desktop.Arrow.Size, 56, "flèches 56" },
		{ desktop.Arrow.TextSize, 26, "texte flèches 26" },
		{ desktop.Preview.Width, 116, "preview 116" },
		{ desktop.Preview.Height, 116, "preview hauteur 116" },
		{ desktop.Preview.Inset, 3, "marge preview 3" },
		{ desktop.Text.InsetX, 132, "texte x 132" },
		{ desktop.Text.NameSize, 18, "nom 18" },
		{ desktop.Text.DescSize, 13, "description 13" },
		{ desktop.Text.PriceSize, 14, "prix 14" },
		{ desktop.Text.PriceYScale, 1, "prix ancré en bas" },
		{ desktop.Action.Width, 168, "bouton 168" },
		{ desktop.Action.Height, 40, "bouton hauteur 40" },
		{ desktop.Action.TextSize, 15, "texte bouton 15" },
		{ desktop.Action.AnchorX, 1, "bouton ancré à droite" },
		{ desktop.Action.YOffset, 4, "bouton décalage 4" },
	}
	for _, entry in ipairs(expected) do
		check(entry[1] == entry[2], "Desktop inchangé : " .. tostring(entry[3]))
	end

	-- Mobile partage exactement la disposition validée du Desktop.
	local function sameShape(a: any, b: any, path: string)
		for key, value in pairs(a) do
			if key ~= "Mode" then
				if type(value) == "table" then
					sameShape(value, b[key], path .. "." .. tostring(key))
				else
					check(b[key] == value, "Mobile identique à Desktop : " .. path .. "." .. tostring(key))
				end
			end
		end
	end
	sameShape(desktop, mobile, "layout")

	-- La taille d'écran ne change rien hors console.
	local desktopSmall = Layout.Resolve("Desktop", size(800, 600))
	local desktopHuge = Layout.Resolve("Desktop", size(3840, 2124))
	check(desktopSmall.Panel.HeightOffset == desktopHuge.Panel.HeightOffset, "Desktop indépendant de l'écran")
	check(desktopSmall.Text.NameSize == desktopHuge.Text.NameSize, "texte Desktop indépendant de l'écran")

	----------------------------------------------------------------
	-- 3) Console : proportions, lisibilité, absence de débordement
	----------------------------------------------------------------

	local desktopPanel1080 = Layout.MeasurePanel(desktop, size(1920, 1044))

	for _, screen in ipairs(SCREENS) do
		local layout = Layout.Resolve("Console", screen.Container)
		local panel = Layout.MeasurePanel(layout, screen.Container)
		local label = screen.Name

		check(layout.Mode == "Console", "mode console : " .. label)

		-- Le panneau tient dans l'écran avec une marge de sécurité téléviseur.
		check(panel.X <= screen.Container.X * 0.92, "largeur dans la zone sûre : " .. label)
		check(panel.Y <= screen.Container.Y * 0.55, "hauteur raisonnable : " .. label)
		local bottom = screen.Container.Y * layout.Panel.YScale
		check(screen.Container.Y - bottom >= screen.Container.Y * 0.06, "marge basse ≥ 6% : " .. label)
		check(bottom - panel.Y >= 0, "panneau entièrement visible : " .. label)

		-- Nettement plus grand que le panneau Desktop.
		check(panel.X >= desktopPanel1080.X * 1.4, "panneau console plus large que Desktop : " .. label)
		check(panel.Y >= desktopPanel1080.Y * 1.3, "panneau console plus haut que Desktop : " .. label)

		-- Preview nettement plus grande, et proportionnée.
		local previewArea = layout.Preview.Width * layout.Preview.Height
		local desktopArea = desktop.Preview.Width * desktop.Preview.Height
		check(previewArea >= desktopArea * 3.5, "preview console très agrandie : " .. label)
		check(layout.Preview.Width >= 240, "preview assez large : " .. label)
		check(layout.Preview.Height >= 200, "preview assez haute : " .. label)
		check(layout.Preview.Width >= layout.Preview.Height * 0.8, "preview pas écrasée : " .. label)

		-- Planchers de lisibilité sur téléviseur.
		check(layout.Text.NameSize >= 28, ("nom ≥ 28 (%d) : %s"):format(layout.Text.NameSize, label))
		check(layout.Text.DescSize >= 20, ("description ≥ 20 (%d) : %s"):format(layout.Text.DescSize, label))
		check(layout.Text.PriceSize >= 24, ("prix ≥ 24 (%d) : %s"):format(layout.Text.PriceSize, label))
		check(layout.Header.CounterSize >= 20, "compteur lisible : " .. label)
		check(layout.Header.CoinsSize >= 22, "solde lisible : " .. label)
		check(layout.Text.PriceSize > layout.Text.DescSize, "prix plus visible que la description : " .. label)

		-- Cibles tactiles / manette.
		check(layout.Arrow.Size >= 68, ("flèches ≥ 68 (%d) : %s"):format(layout.Arrow.Size, label))
		check(layout.Header.CloseSize >= 60, ("fermeture ≥ 60 (%d) : %s"):format(layout.Header.CloseSize, label))
		check(layout.Action.Width >= 210, ("bouton ≥ 210 de large (%d) : %s"):format(layout.Action.Width, label))
		check(layout.Action.Height >= 60, ("bouton ≥ 60 de haut (%d) : %s"):format(layout.Action.Height, label))
		check(layout.Action.TextSize >= 24, "texte du bouton lisible : " .. label)

		-- Tout plus grand que le Desktop, jamais l'inverse.
		check(layout.Arrow.Size > desktop.Arrow.Size, "flèches plus grandes qu'en Desktop : " .. label)
		check(layout.Action.Height > desktop.Action.Height, "bouton plus grand qu'en Desktop : " .. label)
		check(layout.Header.CloseSize > desktop.Header.CloseSize, "fermeture plus grande qu'en Desktop : " .. label)

		-- Aucun débordement vertical dans le panneau.
		local bodyBottom = layout.Body.OffsetY + layout.Body.HeightOffset
		check(bodyBottom <= panel.Y, ("corps dans le panneau (%d ≤ %d) : %s"):format(bodyBottom, panel.Y, label))
		check(layout.Header.OffsetY + layout.Header.Height <= layout.Body.OffsetY, "header au-dessus du corps : " .. label)
		local textBottom = layout.Text.PriceYOffset + layout.Text.PriceHeight
		check(textBottom <= layout.Body.HeightOffset, "colonne texte dans le corps : " .. label)
		local actionTop = panel.Y - layout.Action.YOffset * -1 - layout.Action.Height
		check(actionTop >= layout.Body.OffsetY + textBottom, "bouton sous la colonne texte : " .. label)
		check(layout.Preview.Height <= layout.Body.HeightOffset, "preview dans le corps : " .. label)

		-- Aucun débordement horizontal.
		local bodyWidth = panel.X - layout.Body.InsetX * 2
		local contentWidth = bodyWidth + layout.Body.ContentWidthOffset
		check(contentWidth > 0, "contenu de largeur positive : " .. label)
		local textWidth = contentWidth - layout.Text.InsetX
		check(textWidth >= 320, ("colonne texte exploitable (%d) : %s"):format(textWidth, label))
		check(layout.Body.ContentLeft >= layout.Arrow.Size, "contenu après la flèche gauche : " .. label)
		check(
			layout.Action.XOffset + layout.Action.Width <= panel.X - layout.Body.InsetX,
			"bouton principal dans le panneau : " .. label
		)
		check(
			layout.Header.CoinsInset > layout.Header.CloseSize,
			"solde jamais sous le bouton de fermeture : " .. label
		)
	end

	----------------------------------------------------------------
	-- 4) Mise à l'échelle : ni minuscule en 4K, ni géante en 720p
	----------------------------------------------------------------

	local console720 = Layout.Resolve("Console", size(1280, 684))
	local console1080 = Layout.Resolve("Console", size(1920, 1044))
	local console4k = Layout.Resolve("Console", size(3840, 2124))

	check(console1080.Scale > console720.Scale, "échelle croissante 720p → 1080p")
	check(console4k.Scale > console1080.Scale, "échelle croissante 1080p → 4K")
	check(console4k.Scale >= console1080.Scale * 1.8, "4K reste proportionnel")
	check(console4k.Text.NameSize >= console1080.Text.NameSize * 1.8, "texte 4K proportionnel")
	check(console720.Scale >= 0.82, "720p ne rétrécit pas sous le plancher lisible")

	-- Cibles visées à 1920×1080.
	check(console1080.Preview.Width >= 260 and console1080.Preview.Width <= 340, "preview 260-340 à 1080p")
	check(console1080.Preview.Height >= 240 and console1080.Preview.Height <= 310, "preview 240-310 à 1080p")
	check(console1080.Text.NameSize >= 30 and console1080.Text.NameSize <= 38, "nom 30-38 à 1080p")
	check(console1080.Text.DescSize >= 22 and console1080.Text.DescSize <= 28, "description 22-28 à 1080p")
	check(console1080.Text.PriceSize >= 26 and console1080.Text.PriceSize <= 34, "prix 26-34 à 1080p")
	check(console1080.Header.CounterSize >= 22 and console1080.Header.CounterSize <= 28, "compteur 22-28 à 1080p")
	check(console1080.Header.CoinsSize >= 24 and console1080.Header.CoinsSize <= 32, "solde 24-32 à 1080p")
	check(console1080.Arrow.Size >= 82, "flèches ≥ 82 à 1080p")
	check(console1080.Header.CloseSize >= 72, "fermeture ≥ 72 à 1080p")
	check(console1080.Action.Width >= 260 and console1080.Action.Height >= 72, "bouton 260×72 à 1080p")
	check(
		console1080.Action.TextSize >= 26 and console1080.Action.TextSize <= 34,
		"texte du bouton 26-34 à 1080p"
	)

	local panel1080 = Layout.MeasurePanel(console1080, size(1920, 1044))
	check(panel1080.X / 1920 >= 0.68 and panel1080.X / 1920 <= 0.74, "largeur 68-74% à 1080p")
	check(panel1080.Y / 1080 >= 0.28 and panel1080.Y / 1080 <= 0.36, "hauteur ~30-36% à 1080p")

	for _, screen in ipairs(SCREENS) do
		local layout = Layout.Resolve("Console", screen.Container)
		local panel = Layout.MeasurePanel(layout, screen.Container)
		print(
			("[ShopBrowseLayout] Console %s : panneau %dx%d, preview %dx%d, nom %d, desc %d, prix %d, flèches %d, bouton %dx%d, fermeture %d"):format(
				screen.Name,
				panel.X,
				panel.Y,
				layout.Preview.Width,
				layout.Preview.Height,
				layout.Text.NameSize,
				layout.Text.DescSize,
				layout.Text.PriceSize,
				layout.Arrow.Size,
				layout.Action.Width,
				layout.Action.Height,
				layout.Header.CloseSize
			)
		)
	end

	----------------------------------------------------------------
	-- 5) ShopUI : câblage du layout, aucune reconstruction de preview
	----------------------------------------------------------------

	-- Source injectée par le harnais hors Roblox ; absente en jeu.
	local source: string? = (getfenv() :: any).SHOPUI_SOURCE
	check(source ~= nil, "source de ShopUI injectée par le harnais")
	if source then
		local text = source :: string

		local function contains(needle: string): boolean
			return string.find(text, needle, 1, true) ~= nil
		end

		check(contains("local function applyResponsiveBrowseLayout("), "applyResponsiveBrowseLayout présent")
		check(contains("ShopBrowseLayout.ResolveMode"), "mode résolu par le module")
		check(contains("UserInputService"), "détection via UserInputService")
		check(contains("PreferredInput"), "PreferredInput utilisé")
		check(not contains("IsTenFootInterface"), "IsTenFootInterface non utilisé")
		check(contains('GetPropertyChangedSignal("AbsoluteSize")'), "réaction au redimensionnement")
		check(contains('GetPropertyChangedSignal("CurrentCamera")'), "réaction au changement de caméra")
		check(contains('GetPropertyChangedSignal("ViewportSize")'), "réaction au viewport")
		check(contains("GamepadConnected"), "réaction au branchement manette")
		check(contains("GamepadDisconnected"), "réaction au débranchement manette")
		check(contains("layoutPending"), "anti-rafale des changements de layout")

		-- Le corps de applyResponsiveBrowseLayout ne doit toucher ni au modèle
		-- 3D, ni à la logique d'achat.
		local body = string.match(text, "local function applyResponsiveBrowseLayout%b()(.-)\n\tend\n")
		check(body ~= nil, "corps de applyResponsiveBrowseLayout isolé")
		if body then
			for _, forbidden in ipairs({
				"ShopViewportModels.Build",
				"BuildBackdrop",
				"updatePresentation",
				"clearPreview",
				"refreshPresentation",
				"presentedKey",
				"InvokeServer",
				"exitBrowse",
			}) do
				check(
					string.find(body, forbidden, 1, true) == nil,
					"changement de layout sans effet de bord : " .. forbidden
				)
			end
		end

		-- Navigation manette fermée sur le panneau.
		for _, needed in ipairs({
			"leftBtn.NextSelectionRight = actionBtn",
			"actionBtn.NextSelectionLeft = leftBtn",
			"actionBtn.NextSelectionRight = rightBtn",
			"actionBtn.NextSelectionUp = closeBtn",
			"closeBtn.NextSelectionDown = actionBtn",
			"leftBtn.NextSelectionLeft = leftBtn",
			"rightBtn.NextSelectionRight = rightBtn",
		}) do
			check(contains(needed), "navigation manette : " .. needed)
		end
		check(contains("SelectionGained"), "retour visuel de sélection")
		check(contains("Enum.KeyCode.ButtonL1"), "raccourci manette précédent")
		check(contains("Enum.KeyCode.ButtonR1"), "raccourci manette suivant")

		-- Aucun log de diagnostic résiduel.
		check(not contains("print("), "aucun log de debug dans ShopUI")
	end

	print(("[ShopBrowseLayout] %d vérifications, %d échecs"):format(checks, failures))

	return failures == 0
end

return ShopBrowseLayoutTests
