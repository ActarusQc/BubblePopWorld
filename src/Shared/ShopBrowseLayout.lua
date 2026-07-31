--!strict
-- Disposition responsive du panneau de browse de la boutique.
--
-- Module purement descriptif : il ne crée aucune Instance, ne lit pas le
-- Workspace et ne connaît ni les prix, ni les états de bouton, ni les remotes.
-- ShopUI construit l'interface une seule fois puis applique les valeurs
-- renvoyées ici à chaque changement d'entrée ou de taille d'écran.
--
-- Trois dispositions indépendantes : Mobile et Desktop conservent exactement les
-- valeurs validées (elles sont identiques aujourd'hui) ; Console est une
-- ten-foot UI dimensionnée pour un téléviseur 16:9.

local ShopBrowseLayout = {}

export type Size = { X: number, Y: number }

export type PanelSpec = {
	WidthScale: number,
	WidthOffset: number,
	HeightScale: number,
	HeightOffset: number,
	XScale: number,
	XOffset: number,
	YScale: number,
	YOffset: number,
	MinSize: Size,
	MaxSize: Size,
	Corner: number,
}

export type HeaderSpec = {
	InsetX: number,
	OffsetY: number,
	Height: number,
	TitleSize: number,
	TitleWidthScale: number,
	CounterSize: number,
	CounterXScale: number,
	CounterWidthScale: number,
	CoinsSize: number,
	CoinsXScale: number,
	CoinsWidthScale: number,
	CoinsInset: number,
	CloseSize: number,
	CloseTextSize: number,
	CloseOffsetY: number,
	CloseCorner: number,
}

export type BodySpec = {
	InsetX: number,
	OffsetY: number,
	HeightScale: number,
	HeightOffset: number,
	ContentLeft: number,
	ContentWidthOffset: number,
}

export type ArrowSpec = {
	Size: number,
	TextSize: number,
	Corner: number,
}

export type PreviewSpec = {
	Width: number,
	Height: number,
	Inset: number,
	Corner: number,
	InnerCorner: number,
}

export type TextSpec = {
	InsetX: number,
	NameSize: number,
	NameHeight: number,
	DescSize: number,
	DescHeight: number,
	DescOffsetY: number,
	PriceSize: number,
	PriceHeight: number,
	PriceWidthScale: number,
	PriceYScale: number,
	PriceYOffset: number,
}

export type ActionSpec = {
	AnchorX: number,
	AnchorY: number,
	XScale: number,
	XOffset: number,
	YScale: number,
	YOffset: number,
	Width: number,
	Height: number,
	TextSize: number,
	Corner: number,
}

export type Layout = {
	Mode: string,
	Scale: number,
	Panel: PanelSpec,
	Header: HeaderSpec,
	Body: BodySpec,
	Arrow: ArrowSpec,
	Preview: PreviewSpec,
	Text: TextSpec,
	Action: ActionSpec,
}

ShopBrowseLayout.Modes = { Mobile = "Mobile", Desktop = "Desktop", Console = "Console" }

-- Une manette sur un petit écran reste en Desktop : la ten-foot UI n'a de sens
-- qu'à distance, sur un grand écran.
ShopBrowseLayout.MinConsoleWidth = 1200
ShopBrowseLayout.MinConsoleHeight = 650

-- Hauteur du panneau console obtenue sur un écran 1920×1080, inset compris.
-- Toutes les valeurs console sont exprimées dans ce repère puis multipliées
-- par l'échelle réellement obtenue.
local CONSOLE_REFERENCE_HEIGHT = 344

local function round(value: number): number
	return math.floor(value + 0.5)
end

--------------------------------------------------------------------
-- Choix du mode
--------------------------------------------------------------------

function ShopBrowseLayout.IsLargeScreen(viewportSize: Size): boolean
	return viewportSize.X >= ShopBrowseLayout.MinConsoleWidth
		and viewportSize.Y >= ShopBrowseLayout.MinConsoleHeight
end

-- preferredInput : nom de Enum.PreferredInput ("Gamepad", "Touch",
-- "KeyboardAndMouse") ou nil si le client est trop ancien pour l'exposer.
function ShopBrowseLayout.ResolveMode(preferredInput: string?, viewportSize: Size, touchEnabled: boolean?): string
	if preferredInput == "Gamepad" and ShopBrowseLayout.IsLargeScreen(viewportSize) then
		return ShopBrowseLayout.Modes.Console
	end
	if preferredInput == "Touch" then
		return ShopBrowseLayout.Modes.Mobile
	end
	if preferredInput == nil and touchEnabled == true then
		return ShopBrowseLayout.Modes.Mobile
	end
	return ShopBrowseLayout.Modes.Desktop
end

--------------------------------------------------------------------
-- Disposition classique (Mobile et Desktop) — valeurs validées, figées
--------------------------------------------------------------------

local function classicLayout(mode: string): Layout
	return {
		Mode = mode,
		Scale = 1,
		Panel = {
			WidthScale = 0.9,
			WidthOffset = 0,
			HeightScale = 0,
			HeightOffset = 190,
			XScale = 0.5,
			XOffset = 0,
			YScale = 1,
			YOffset = -22,
			MinSize = { X = 300, Y = 190 },
			MaxSize = { X = 640, Y = 220 },
			Corner = 18,
		},
		Header = {
			InsetX = 12,
			OffsetY = 10,
			Height = 30,
			TitleSize = 20,
			TitleWidthScale = 0.5,
			CounterSize = 14,
			CounterXScale = 0.5,
			CounterWidthScale = 0.2,
			CoinsSize = 16,
			CoinsXScale = 0.7,
			CoinsWidthScale = 0.3,
			CoinsInset = 44,
			CloseSize = 40,
			CloseTextSize = 18,
			CloseOffsetY = -4,
			CloseCorner = 10,
		},
		Body = {
			InsetX = 12,
			OffsetY = 46,
			HeightScale = 1,
			HeightOffset = -84,
			ContentLeft = 68,
			ContentWidthOffset = -144,
		},
		Arrow = {
			Size = 56,
			TextSize = 26,
			Corner = 14,
		},
		Preview = {
			Width = 116,
			Height = 116,
			Inset = 3,
			Corner = 14,
			InnerCorner = 12,
		},
		Text = {
			InsetX = 132,
			NameSize = 18,
			NameHeight = 26,
			DescSize = 13,
			DescHeight = 40,
			DescOffsetY = 28,
			PriceSize = 14,
			PriceHeight = 20,
			PriceWidthScale = 0.55,
			PriceYScale = 1,
			PriceYOffset = -20,
		},
		Action = {
			AnchorX = 1,
			AnchorY = 1,
			XScale = 1,
			XOffset = 0,
			YScale = 1,
			YOffset = 4,
			Width = 168,
			Height = 40,
			TextSize = 15,
			Corner = 10,
		},
	}
end

--------------------------------------------------------------------
-- Disposition console (ten-foot UI)
--------------------------------------------------------------------

-- containerSize : taille réelle du conteneur de l'interface (AbsoluteSize du
-- ScreenGui), qui tient déjà compte de l'inset supérieur.
local function consoleLayout(containerSize: Size): Layout
	local minSize = { X = 900, Y = 300 }
	local maxSize = { X = 2900, Y = 760 }

	local height = math.clamp(containerSize.Y * 0.33, minSize.Y, maxSize.Y)
	-- L'échelle suit la hauteur réellement obtenue après contraintes, donc les
	-- valeurs internes ne débordent jamais du panneau.
	local scale = height / CONSOLE_REFERENCE_HEIGHT

	local function px(reference: number): number
		return round(reference * scale)
	end

	local headerHeight = px(44)
	local headerOffsetY = px(16)
	local bodyOffsetY = px(68)
	local bodyBottom = px(20)
	local bodyHeight = round(height) - bodyOffsetY - bodyBottom
	local bodyInsetX = px(24)
	local arrowSize = px(82)
	local arrowGap = px(22)
	local contentLeft = arrowSize + arrowGap
	local previewWidth = px(300)
	local previewGap = px(24)
	local closeSize = px(72)

	return {
		Mode = ShopBrowseLayout.Modes.Console,
		Scale = scale,
		Panel = {
			WidthScale = 0.72,
			WidthOffset = 0,
			HeightScale = 0.33,
			HeightOffset = 0,
			XScale = 0.5,
			XOffset = 0,
			YScale = 0.93,
			YOffset = 0,
			MinSize = minSize,
			MaxSize = maxSize,
			Corner = px(24),
		},
		Header = {
			InsetX = bodyInsetX,
			OffsetY = headerOffsetY,
			Height = headerHeight,
			TitleSize = px(34),
			TitleWidthScale = 0.42,
			CounterSize = px(24),
			CounterXScale = 0.44,
			CounterWidthScale = 0.2,
			CoinsSize = px(28),
			CoinsXScale = 0.64,
			CoinsWidthScale = 0.36,
			CoinsInset = closeSize + px(18),
			CloseSize = closeSize,
			CloseTextSize = px(30),
			CloseOffsetY = round((headerHeight - closeSize) / 2),
			CloseCorner = px(16),
		},
		Body = {
			InsetX = bodyInsetX,
			OffsetY = bodyOffsetY,
			HeightScale = 0,
			HeightOffset = bodyHeight,
			ContentLeft = contentLeft,
			ContentWidthOffset = -(contentLeft + arrowSize + px(26)),
		},
		Arrow = {
			Size = arrowSize,
			TextSize = px(40),
			Corner = px(20),
		},
		Preview = {
			Width = previewWidth,
			Height = bodyHeight,
			Inset = px(4),
			Corner = px(20),
			InnerCorner = px(16),
		},
		Text = {
			InsetX = previewWidth + previewGap,
			NameSize = px(34),
			NameHeight = px(44),
			DescSize = px(24),
			DescHeight = px(80),
			DescOffsetY = px(52),
			PriceSize = px(30),
			PriceHeight = px(40),
			PriceWidthScale = 0.7,
			PriceYScale = 0,
			PriceYOffset = px(138),
		},
		Action = {
			AnchorX = 0,
			AnchorY = 1,
			XScale = 0,
			XOffset = bodyInsetX + contentLeft + previewWidth + previewGap,
			YScale = 1,
			YOffset = -bodyBottom,
			Width = px(260),
			Height = px(72),
			TextSize = px(30),
			Corner = px(16),
		},
	}
end

function ShopBrowseLayout.Resolve(mode: string, containerSize: Size): Layout
	if mode == ShopBrowseLayout.Modes.Console then
		return consoleLayout(containerSize)
	end
	return classicLayout(if mode == ShopBrowseLayout.Modes.Mobile then mode else ShopBrowseLayout.Modes.Desktop)
end

-- Encombrement réel du panneau, utile aux tests de débordement.
function ShopBrowseLayout.MeasurePanel(layout: Layout, containerSize: Size): Size
	local panel = layout.Panel
	return {
		X = math.clamp(
			containerSize.X * panel.WidthScale + panel.WidthOffset,
			panel.MinSize.X,
			math.max(panel.MaxSize.X, panel.MinSize.X)
		),
		Y = math.clamp(
			containerSize.Y * panel.HeightScale + panel.HeightOffset,
			panel.MinSize.Y,
			math.max(panel.MaxSize.Y, panel.MinSize.Y)
		),
	}
end

return ShopBrowseLayout
