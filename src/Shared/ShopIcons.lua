--!strict
-- Icônes boutique / vitrine : résolution extensible (glyph + couleur + Image optionnelle).

export type IconDef = {
	Glyph: string,
	Color: Color3,
	Image: string?,
}

local ShopIcons = {}

local DEFAULT: IconDef = {
	Glyph = "✦",
	Color = Color3.fromRGB(120, 200, 255),
	Image = nil,
}

-- Clés stables : ShowcaseItems + ShopItems. Extensible sans toucher à l'UI.
ShopIcons.ByKey = {
	Default = DEFAULT,
	Potion = {
		Glyph = "🧪",
		Color = Color3.fromRGB(170, 110, 255),
		Image = nil,
	},
	Wand = {
		Glyph = "🪄",
		Color = Color3.fromRGB(120, 200, 255),
		Image = nil,
	},
	Boost = {
		Glyph = "⚡",
		Color = Color3.fromRGB(255, 210, 70),
		Image = nil,
	},
	MegaBubble = {
		Glyph = "🫧",
		Color = Color3.fromRGB(80, 230, 255),
		Image = nil,
	},
	BackpackDefault = {
		Glyph = "🎒",
		Color = Color3.fromRGB(110, 150, 210),
		Image = nil,
	},
	BackpackGold = {
		Glyph = "🎒",
		Color = Color3.fromRGB(255, 195, 60),
		Image = nil,
	},
	BackpackEmerald = {
		Glyph = "🎒",
		Color = Color3.fromRGB(60, 220, 140),
		Image = nil,
	},
	BackpackNeon = {
		Glyph = "🎒",
		Color = Color3.fromRGB(90, 240, 255),
		Image = nil,
	},
} :: { [string]: IconDef }

function ShopIcons.Resolve(iconKey: string?): IconDef
	if type(iconKey) == "string" and iconKey ~= "" then
		local found = ShopIcons.ByKey[iconKey]
		if found then
			return found
		end
	end
	return DEFAULT
end

--- Crée un badge d'icône (ImageLabel si Image, sinon glyph coloré).
function ShopIcons.CreateBadge(parent: Instance, name: string, iconKey: string?, zIndex: number?): Frame
	local def = ShopIcons.Resolve(iconKey)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = def.Color
	frame.BackgroundTransparency = 0.72
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex or 7
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = def.Color
	stroke.Thickness = 1.5
	stroke.Transparency = 0.25
	stroke.Parent = frame

	local imageId = def.Image
	if type(imageId) == "string" and imageId ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "IconImage"
		image.BackgroundTransparency = 1
		image.Size = UDim2.new(1, -8, 1, -8)
		image.Position = UDim2.fromOffset(4, 4)
		image.Image = imageId
		image.ScaleType = Enum.ScaleType.Fit
		image.ZIndex = frame.ZIndex + 1
		image.Parent = frame
	else
		local glyph = Instance.new("TextLabel")
		glyph.Name = "IconGlyph"
		glyph.BackgroundTransparency = 1
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Font = Enum.Font.GothamBold
		glyph.Text = def.Glyph
		glyph.TextScaled = true
		glyph.TextColor3 = Color3.new(1, 1, 1)
		glyph.ZIndex = frame.ZIndex + 1
		glyph.Parent = frame

		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MinTextSize = 12
		constraint.MaxTextSize = 28
		constraint.Parent = glyph
	end

	return frame
end

return ShopIcons
