--!strict
-- Modèles de présentation des articles de la boutique.
--
-- Purement visuel et 100 % local : ce module ne lit ni n'écrit le Workspace, ne
-- touche à aucun Remote et ignore complètement les prix, niveaux et états
-- d'achat. ShopUI l'utilise pour remplir le ViewportFrame du browse.
--
-- La géométrie est décrite par des specs pures (testables hors Roblox) ; la
-- construction d'Instances n'a lieu que dans Build().

local ShopViewportModels = {}

export type PreviewPart = {
	Name: string,
	Size: Vector3,
	Offset: Vector3,
	Rotation: Vector3?, -- degrés (X, Y, Z)
	Color: Color3,
	Material: string, -- "SmoothPlastic" | "Metal" | "Neon" | "Glass" | "Slate"
	Shape: string?, -- "Block" (défaut) | "Cylinder" | "Ball"
	Transparency: number?,
}

export type PreviewSpec = {
	Id: string,
	Accent: Color3,
	Parts: { PreviewPart },
}

export type Bounds = {
	Center: Vector3,
	Radius: number,
	Size: Vector3,
}

--------------------------------------------------------------------
-- Palette commune : un seul langage visuel pour tout le catalogue
--------------------------------------------------------------------

local C = {
	White = Color3.fromRGB(244, 249, 255),
	Cloud = Color3.fromRGB(206, 219, 236),
	Steel = Color3.fromRGB(158, 176, 199),
	Slate = Color3.fromRGB(86, 106, 136),
	-- Tons sombres relevés : les surfaces quasi noires disparaissaient dans le
	-- fond du ViewportFrame. L'identité (bleu profond, bois foncé) est conservée.
	SlateDark = Color3.fromRGB(62, 80, 110),
	Navy = Color3.fromRGB(50, 66, 96),
	Cyan = Color3.fromRGB(72, 214, 244),
	CyanDeep = Color3.fromRGB(28, 138, 190),
	Gold = Color3.fromRGB(255, 202, 74),
	GoldDeep = Color3.fromRGB(198, 138, 28),
	Emerald = Color3.fromRGB(72, 214, 148),
	EmeraldDeep = Color3.fromRGB(24, 138, 98),
	Violet = Color3.fromRGB(186, 116, 255),
	VioletDeep = Color3.fromRGB(116, 62, 190),
	Pink = Color3.fromRGB(255, 128, 202),
	Red = Color3.fromRGB(232, 84, 96),
	Wood = Color3.fromRGB(168, 122, 76),
	WoodDark = Color3.fromRGB(128, 92, 56),
}

ShopViewportModels.Palette = C

local CATEGORY_ACCENT: { [string]: Color3 } = {
	Skills = C.Cyan,
	Items = C.Gold,
	Cosmetics = C.Violet,
}

--------------------------------------------------------------------
-- Construction des specs
--------------------------------------------------------------------

local function part(
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: string?,
	options: { Rotation: Vector3?, Shape: string?, Transparency: number? }?
): PreviewPart
	local opts = options or {}
	return {
		Name = name,
		Size = size,
		Offset = offset,
		Rotation = opts.Rotation,
		Color = color,
		Material = material or "SmoothPlastic",
		Shape = opts.Shape,
		Transparency = opts.Transparency,
	}
end

local function disc(name: string, diameter: number, thickness: number, offset: Vector3, color: Color3, material: string?): PreviewPart
	-- Cylindre couché : l'axe local X devient vertical.
	return part(name, Vector3.new(thickness, diameter, diameter), offset, color, material, {
		Shape = "Cylinder",
		Rotation = Vector3.new(0, 0, 90),
	})
end

local function coinFace(name: string, diameter: number, thickness: number, offset: Vector3, color: Color3, material: string?): PreviewPart
	-- Cylindre face à la caméra : l'axe local X devient l'axe Z.
	return part(name, Vector3.new(thickness, diameter, diameter), offset, color, material, {
		Shape = "Cylinder",
		Rotation = Vector3.new(0, 90, 0),
	})
end

local function backpack(accent: Color3, deep: Color3, trim: Color3, glow: boolean): { PreviewPart }
	return {
		part("Body", Vector3.new(1.9, 2.1, 1.15), Vector3.new(0, 0, 0), accent, "SmoothPlastic"),
		part("Flap", Vector3.new(2.0, 0.95, 1.22), Vector3.new(0, 0.78, 0.04), deep, "SmoothPlastic"),
		part("Pocket", Vector3.new(1.2, 0.85, 0.5), Vector3.new(0, -0.55, 0.62), deep, "SmoothPlastic"),
		part("Buckle", Vector3.new(0.42, 0.34, 0.26), Vector3.new(0, 0.26, 0.72), trim, if glow then "Neon" else "Metal"),
		part("StrapLeft", Vector3.new(0.3, 1.9, 0.36), Vector3.new(-0.72, -0.15, -0.7), deep, "SmoothPlastic", {
			Rotation = Vector3.new(9, 0, 0),
		}),
		part("StrapRight", Vector3.new(0.3, 1.9, 0.36), Vector3.new(0.72, -0.15, -0.7), deep, "SmoothPlastic", {
			Rotation = Vector3.new(9, 0, 0),
		}),
		part("Handle", Vector3.new(0.72, 0.3, 0.26), Vector3.new(0, 1.3, -0.22), trim, "Metal"),
		part("TrimLine", Vector3.new(1.94, 0.16, 1.18), Vector3.new(0, -0.92, 0), trim, "Neon"),
	}
end

local function headwearLogo(color: Color3): PreviewPart
	return part("Logo", Vector3.new(0.5, 0.5, 0.16), Vector3.new(0, 0.05, 0.96), color, "Neon", {
		Rotation = Vector3.new(0, 0, 45),
	})
end

local SPECS: { [string]: { Accent: Color3, Parts: { PreviewPart } } } = {}

-- Skills ------------------------------------------------------------

SPECS.Speed = {
	Accent = C.Cyan,
	Parts = {
		part("Sole", Vector3.new(2.3, 0.32, 0.98), Vector3.new(0.1, -0.78, 0), C.SlateDark, "SmoothPlastic"),
		part("SoleEdge", Vector3.new(2.3, 0.12, 1.02), Vector3.new(0.1, -0.58, 0), C.Cyan, "Neon"),
		part("Upper", Vector3.new(1.5, 0.9, 0.94), Vector3.new(-0.2, -0.18, 0), C.White, "SmoothPlastic"),
		part("Toe", Vector3.new(0.8, 0.58, 0.94), Vector3.new(0.82, -0.36, 0), C.Cloud, "SmoothPlastic"),
		part("Shaft", Vector3.new(1.0, 0.95, 0.9), Vector3.new(-0.58, 0.55, 0), C.CyanDeep, "SmoothPlastic"),
		part("Cuff", Vector3.new(1.06, 0.24, 0.96), Vector3.new(-0.58, 1.06, 0), C.Cyan, "Neon"),
		part("WingLeft", Vector3.new(0.95, 0.42, 0.14), Vector3.new(-1.15, 0.2, 0.46), C.Cyan, "Neon", {
			Rotation = Vector3.new(0, 0, 22),
		}),
		part("WingRight", Vector3.new(0.95, 0.42, 0.14), Vector3.new(-1.15, 0.2, -0.46), C.Cyan, "Neon", {
			Rotation = Vector3.new(0, 0, 22),
		}),
	},
}

SPECS.Jump = {
	Accent = C.Cyan,
	Parts = {
		part("Upper", Vector3.new(1.55, 1.0, 1.0), Vector3.new(-0.1, 0.62, 0), C.White, "SmoothPlastic"),
		part("Toe", Vector3.new(0.78, 0.62, 1.0), Vector3.new(0.78, 0.42, 0), C.Cloud, "SmoothPlastic"),
		part("Cuff", Vector3.new(1.4, 0.28, 1.06), Vector3.new(-0.1, 1.2, 0), C.Cyan, "Neon"),
		part("Sole", Vector3.new(2.2, 0.26, 1.04), Vector3.new(0.05, 0.02, 0), C.SlateDark, "SmoothPlastic"),
		disc("SpringTop", 1.25, 0.22, Vector3.new(0, -0.34, 0), C.Cyan, "Neon"),
		disc("SpringMid", 1.15, 0.2, Vector3.new(0, -0.74, 0), C.Steel, "Metal"),
		disc("SpringLow", 1.25, 0.22, Vector3.new(0, -1.14, 0), C.Cyan, "Neon"),
		part("Pad", Vector3.new(1.5, 0.28, 1.1), Vector3.new(0, -1.44, 0), C.SlateDark, "SmoothPlastic"),
	},
}

SPECS.Power = {
	Accent = C.Cyan,
	Parts = {
		part("Fist", Vector3.new(1.55, 1.35, 1.35), Vector3.new(0.05, 0.1, 0), C.CyanDeep, "SmoothPlastic"),
		part("Knuckles", Vector3.new(1.62, 0.42, 1.4), Vector3.new(0.08, 0.72, 0), C.White, "SmoothPlastic"),
		part("Thumb", Vector3.new(0.5, 0.5, 0.55), Vector3.new(0.62, 0.05, 0.66), C.CyanDeep, "SmoothPlastic"),
		part("Wrist", Vector3.new(1.0, 0.72, 1.15), Vector3.new(-0.92, -0.4, 0), C.Slate, "Metal"),
		part("Cuff", Vector3.new(0.3, 1.22, 1.3), Vector3.new(-1.35, -0.5, 0), C.Cyan, "Neon"),
		part("SparkUp", Vector3.new(0.22, 0.9, 0.22), Vector3.new(0.35, 1.35, 0), C.Cyan, "Neon"),
		part("SparkLeft", Vector3.new(0.22, 0.8, 0.22), Vector3.new(-0.4, 1.25, 0), C.Cyan, "Neon", {
			Rotation = Vector3.new(0, 0, 35),
		}),
		part("SparkRight", Vector3.new(0.22, 0.8, 0.22), Vector3.new(1.05, 1.1, 0), C.Cyan, "Neon", {
			Rotation = Vector3.new(0, 0, -35),
		}),
	},
}

SPECS.CoinMult = {
	Accent = C.Gold,
	Parts = {
		disc("StackBottom", 2.0, 0.26, Vector3.new(-0.05, -1.05, 0.05), C.GoldDeep, "Metal"),
		disc("StackMiddle", 1.94, 0.26, Vector3.new(0.12, -0.78, -0.08), C.Gold, "Metal"),
		disc("StackTop", 2.02, 0.26, Vector3.new(-0.02, -0.51, 0.06), C.GoldDeep, "Metal"),
		coinFace("HeroCoin", 2.5, 0.32, Vector3.new(0, 0.62, 0), C.Gold, "Metal"),
		coinFace("HeroRim", 2.16, 0.36, Vector3.new(0, 0.62, 0), C.GoldDeep, "Metal"),
		part("MarkA", Vector3.new(0.24, 1.15, 0.16), Vector3.new(0, 0.62, 0.24), C.White, "Neon", {
			Rotation = Vector3.new(0, 0, 45),
		}),
		part("MarkB", Vector3.new(0.24, 1.15, 0.16), Vector3.new(0, 0.62, 0.24), C.White, "Neon", {
			Rotation = Vector3.new(0, 0, -45),
		}),
	},
}

SPECS.Magnet = {
	Accent = C.Red,
	Parts = {
		part("ArmLeft", Vector3.new(0.72, 2.0, 0.95), Vector3.new(-0.76, 0.25, 0), C.Red, "SmoothPlastic"),
		part("ArmRight", Vector3.new(0.72, 2.0, 0.95), Vector3.new(0.76, 0.25, 0), C.Red, "SmoothPlastic"),
		part("Yoke", Vector3.new(2.24, 0.8, 0.95), Vector3.new(0, 1.25, 0), C.Red, "SmoothPlastic"),
		part("YokeShine", Vector3.new(2.24, 0.16, 0.99), Vector3.new(0, 1.5, 0), C.Pink, "Neon"),
		part("TipLeft", Vector3.new(0.74, 0.58, 0.97), Vector3.new(-0.76, -1.04, 0), C.Cloud, "Metal"),
		part("TipRight", Vector3.new(0.74, 0.58, 0.97), Vector3.new(0.76, -1.04, 0), C.Cloud, "Metal"),
		part("PullLeft", Vector3.new(0.5, 0.16, 0.5), Vector3.new(-0.76, -1.48, 0), C.Cyan, "Neon"),
		part("PullRight", Vector3.new(0.5, 0.16, 0.5), Vector3.new(0.76, -1.48, 0), C.Cyan, "Neon"),
	},
}

SPECS.Luck = {
	Accent = C.Emerald,
	Parts = {
		part("LeafTopLeft", Vector3.new(1.15, 1.15, 0.38), Vector3.new(-0.52, 0.62, 0), C.Emerald, "SmoothPlastic", {
			Shape = "Ball",
		}),
		part("LeafTopRight", Vector3.new(1.15, 1.15, 0.38), Vector3.new(0.52, 0.62, 0), C.Emerald, "SmoothPlastic", {
			Shape = "Ball",
		}),
		part("LeafLowLeft", Vector3.new(1.15, 1.15, 0.38), Vector3.new(-0.52, -0.42, 0), C.EmeraldDeep, "SmoothPlastic", {
			Shape = "Ball",
		}),
		part("LeafLowRight", Vector3.new(1.15, 1.15, 0.38), Vector3.new(0.52, -0.42, 0), C.EmeraldDeep, "SmoothPlastic", {
			Shape = "Ball",
		}),
		part("Heart", Vector3.new(0.42, 0.42, 0.44), Vector3.new(0, 0.1, 0.06), C.Gold, "Neon", {
			Shape = "Ball",
		}),
		part("Stem", Vector3.new(0.2, 1.0, 0.2), Vector3.new(0.14, -1.2, 0), C.EmeraldDeep, "SmoothPlastic", {
			Rotation = Vector3.new(0, 0, 14),
		}),
	},
}

SPECS.CapacityBoost = {
	Accent = C.Cyan,
	Parts = {
		part("Crate", Vector3.new(2.0, 1.7, 1.6), Vector3.new(0, -0.45, 0), C.Slate, "SmoothPlastic"),
		part("Lid", Vector3.new(2.12, 0.3, 1.7), Vector3.new(0, 0.55, 0), C.SlateDark, "SmoothPlastic"),
		part("BandX", Vector3.new(2.06, 0.2, 1.64), Vector3.new(0, -0.45, 0), C.Cyan, "Neon"),
		part("BandY", Vector3.new(0.24, 1.74, 1.64), Vector3.new(0, -0.45, 0), C.CyanDeep, "SmoothPlastic"),
		part("ArrowShaft", Vector3.new(0.42, 0.9, 0.3), Vector3.new(0, 1.28, 0.3), C.Cyan, "Neon"),
		part("ArrowHeadLeft", Vector3.new(0.62, 0.24, 0.3), Vector3.new(-0.27, 1.68, 0.3), C.Cyan, "Neon", {
			Rotation = Vector3.new(0, 0, 45),
		}),
		part("ArrowHeadRight", Vector3.new(0.62, 0.24, 0.3), Vector3.new(0.27, 1.68, 0.3), C.Cyan, "Neon", {
			Rotation = Vector3.new(0, 0, -45),
		}),
	},
}

-- Items ---------------------------------------------------------------

SPECS.BackpackGold = { Accent = C.Gold, Parts = backpack(C.Gold, C.GoldDeep, C.White, false) }
SPECS.BackpackEmerald = { Accent = C.Emerald, Parts = backpack(C.Emerald, C.EmeraldDeep, C.White, false) }
SPECS.BackpackNeon = { Accent = C.Cyan, Parts = backpack(C.CyanDeep, C.Navy, C.Cyan, true) }

SPECS.Hammer = {
	Accent = C.Gold,
	Parts = {
		part("Handle", Vector3.new(0.36, 2.4, 0.36), Vector3.new(0, -0.45, 0), C.Wood, "SmoothPlastic"),
		part("Grip", Vector3.new(0.46, 0.95, 0.46), Vector3.new(0, -1.25, 0), C.WoodDark, "SmoothPlastic"),
		part("HeadMain", Vector3.new(1.95, 0.95, 0.95), Vector3.new(0, 1.02, 0), C.Steel, "Metal"),
		part("HeadFace", Vector3.new(0.42, 1.05, 1.05), Vector3.new(0.98, 1.02, 0), C.Gold, "Metal"),
		part("Claw", Vector3.new(0.52, 0.85, 0.6), Vector3.new(-0.96, 1.2, 0), C.Steel, "Metal", {
			Rotation = Vector3.new(0, 0, 32),
		}),
		part("Collar", Vector3.new(0.44, 0.24, 0.44), Vector3.new(0, 0.45, 0), C.Gold, "Neon"),
	},
}

SPECS.Pin = {
	Accent = C.Red,
	Parts = {
		disc("Head", 1.7, 0.4, Vector3.new(0, 0.78, 0), C.Red, "SmoothPlastic"),
		disc("HeadTop", 1.2, 0.3, Vector3.new(0, 1.06, 0), C.Pink, "SmoothPlastic"),
		part("Shaft", Vector3.new(0.3, 1.4, 0.3), Vector3.new(0, -0.15, 0), C.Steel, "Metal"),
		part("Point", Vector3.new(0.24, 0.5, 0.24), Vector3.new(0, -1.02, 0), C.Cloud, "Metal"),
		part("Tip", Vector3.new(0.12, 0.34, 0.12), Vector3.new(0, -1.4, 0), C.White, "Neon"),
	},
}

SPECS.MultiPopTool = {
	Accent = C.Cyan,
	Parts = {
		part("Handle", Vector3.new(0.36, 1.7, 0.36), Vector3.new(-0.52, -0.85, 0), C.SlateDark, "SmoothPlastic", {
			Rotation = Vector3.new(0, 0, 12),
		}),
		part("Head", Vector3.new(1.1, 0.52, 0.62), Vector3.new(-0.18, 0.12, 0), C.Steel, "Metal"),
		part("Emitter", Vector3.new(0.32, 0.34, 0.66), Vector3.new(0.42, 0.14, 0), C.Cyan, "Neon"),
		part("BubbleBig", Vector3.new(1.05, 1.05, 1.05), Vector3.new(0.72, 0.86, 0.1), C.Cyan, "Neon", {
			Shape = "Ball",
			Transparency = 0.35,
		}),
		part("BubbleMid", Vector3.new(0.72, 0.72, 0.72), Vector3.new(-0.2, 1.22, -0.24), C.White, "Neon", {
			Shape = "Ball",
			Transparency = 0.4,
		}),
		part("BubbleSmall", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0.32, 1.55, 0.3), C.Cyan, "Neon", {
			Shape = "Ball",
			Transparency = 0.4,
		}),
	},
}

SPECS.SpecialTool = {
	Accent = C.Gold,
	Parts = {
		part("Handle", Vector3.new(0.36, 1.8, 0.36), Vector3.new(0, -0.95, 0), C.SlateDark, "SmoothPlastic"),
		part("Collar", Vector3.new(0.5, 0.24, 0.5), Vector3.new(0, -0.05, 0), C.Gold, "Metal"),
		part("StarA", Vector3.new(2.0, 0.58, 0.4), Vector3.new(0, 0.72, 0), C.Gold, "Metal"),
		part("StarB", Vector3.new(2.0, 0.58, 0.4), Vector3.new(0, 0.72, 0), C.Gold, "Metal", {
			Rotation = Vector3.new(0, 0, 60),
		}),
		part("StarC", Vector3.new(2.0, 0.58, 0.4), Vector3.new(0, 0.72, 0), C.Gold, "Metal", {
			Rotation = Vector3.new(0, 0, 120),
		}),
		part("Core", Vector3.new(0.62, 0.62, 0.52), Vector3.new(0, 0.72, 0.12), C.White, "Neon", {
			Shape = "Ball",
		}),
	},
}

-- Cosmetics -----------------------------------------------------------

SPECS.Cap = {
	Accent = C.Violet,
	Parts = {
		part("Crown", Vector3.new(2.05, 1.5, 1.95), Vector3.new(0, 0.12, 0), C.Violet, "SmoothPlastic", {
			Shape = "Ball",
		}),
		part("Band", Vector3.new(2.1, 0.34, 2.0), Vector3.new(0, -0.48, 0), C.VioletDeep, "SmoothPlastic"),
		part("Brim", Vector3.new(1.85, 0.24, 1.5), Vector3.new(0, -0.5, 1.05), C.VioletDeep, "SmoothPlastic", {
			Rotation = Vector3.new(-9, 0, 0),
		}),
		part("Button", Vector3.new(0.34, 0.34, 0.34), Vector3.new(0, 0.88, 0), C.Pink, "Neon", {
			Shape = "Ball",
		}),
		headwearLogo(C.Pink),
	},
}

SPECS.Hat = {
	Accent = C.Violet,
	Parts = {
		disc("Brim", 2.85, 0.24, Vector3.new(0, -0.78, 0), C.Navy, "SmoothPlastic"),
		disc("BrimEdge", 2.95, 0.1, Vector3.new(0, -0.9, 0), C.Violet, "Neon"),
		disc("Crown", 1.75, 1.7, Vector3.new(0, 0.2, 0), C.SlateDark, "SmoothPlastic"),
		disc("Band", 1.82, 0.42, Vector3.new(0, -0.42, 0), C.Violet, "SmoothPlastic"),
		disc("Top", 1.78, 0.16, Vector3.new(0, 1.06, 0), C.Slate, "SmoothPlastic"),
		part("Feather", Vector3.new(0.16, 1.1, 0.4), Vector3.new(0.72, 0.15, 0.55), C.Pink, "Neon", {
			Rotation = Vector3.new(0, 0, -18),
		}),
	},
}

SPECS.Vest = {
	Accent = C.Violet,
	Parts = {
		part("BackPanel", Vector3.new(1.95, 2.1, 0.36), Vector3.new(0, 0, -0.36), C.VioletDeep, "SmoothPlastic"),
		part("FrontLeft", Vector3.new(0.78, 2.0, 0.32), Vector3.new(-0.56, -0.05, 0.36), C.Violet, "SmoothPlastic"),
		part("FrontRight", Vector3.new(0.78, 2.0, 0.32), Vector3.new(0.56, -0.05, 0.36), C.Violet, "SmoothPlastic"),
		part("ShoulderLeft", Vector3.new(0.52, 0.42, 1.04), Vector3.new(-0.72, 1.06, 0), C.VioletDeep, "SmoothPlastic"),
		part("ShoulderRight", Vector3.new(0.52, 0.42, 1.04), Vector3.new(0.72, 1.06, 0), C.VioletDeep, "SmoothPlastic"),
		part("Collar", Vector3.new(1.5, 0.36, 0.95), Vector3.new(0, 1.12, 0), C.Pink, "SmoothPlastic"),
		part("Zipper", Vector3.new(0.16, 2.0, 0.14), Vector3.new(0, -0.05, 0.54), C.Pink, "Neon"),
		part("Pocket", Vector3.new(0.6, 0.46, 0.16), Vector3.new(-0.56, -0.6, 0.54), C.VioletDeep, "SmoothPlastic"),
	},
}

SPECS.Shirt = {
	Accent = C.Pink,
	Parts = {
		part("Torso", Vector3.new(1.85, 1.95, 0.62), Vector3.new(0, -0.12, 0), C.White, "SmoothPlastic"),
		part("SleeveLeft", Vector3.new(0.78, 0.62, 0.68), Vector3.new(-1.2, 0.66, 0), C.Cloud, "SmoothPlastic", {
			Rotation = Vector3.new(0, 0, 20),
		}),
		part("SleeveRight", Vector3.new(0.78, 0.62, 0.68), Vector3.new(1.2, 0.66, 0), C.Cloud, "SmoothPlastic", {
			Rotation = Vector3.new(0, 0, -20),
		}),
		part("Collar", Vector3.new(0.88, 0.3, 0.66), Vector3.new(0, 0.96, 0.02), C.Violet, "SmoothPlastic"),
		part("Hem", Vector3.new(1.88, 0.22, 0.66), Vector3.new(0, -1.0, 0), C.Violet, "Neon"),
		part("Graphic", Vector3.new(0.92, 0.92, 0.14), Vector3.new(0, -0.05, 0.34), C.Pink, "Neon", {
			Rotation = Vector3.new(0, 0, 45),
		}),
	},
}

SPECS.Accessory = {
	Accent = C.Violet,
	Parts = {
		part("ChainLeft", Vector3.new(0.16, 1.7, 0.16), Vector3.new(-0.5, 0.75, 0), C.Cloud, "Metal", {
			Rotation = Vector3.new(0, 0, 22),
		}),
		part("ChainRight", Vector3.new(0.16, 1.7, 0.16), Vector3.new(0.5, 0.75, 0), C.Cloud, "Metal", {
			Rotation = Vector3.new(0, 0, -22),
		}),
		part("Clasp", Vector3.new(0.44, 0.3, 0.3), Vector3.new(0, 1.5, 0), C.Steel, "Metal"),
		part("Gem", Vector3.new(1.25, 1.25, 0.45), Vector3.new(0, -0.42, 0), C.Violet, "Glass", {
			Rotation = Vector3.new(0, 0, 45),
			Transparency = 0.2,
		}),
		part("GemCore", Vector3.new(0.62, 0.62, 0.5), Vector3.new(0, -0.42, 0.2), C.Pink, "Neon", {
			Rotation = Vector3.new(0, 0, 45),
		}),
	},
}

--------------------------------------------------------------------
-- Repli élégant par famille : jamais de forme abstraite nue
--------------------------------------------------------------------

local function fallbackParts(accent: Color3, deep: Color3, shape: string?): { PreviewPart }
	return {
		part("Core", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 0.1, 0), accent, "SmoothPlastic", {
			Shape = shape,
			Rotation = if shape == nil then Vector3.new(0, 30, 0) else nil,
		}),
		part("Halo", Vector3.new(2.3, 0.18, 2.3), Vector3.new(0, -0.75, 0), accent, "Neon"),
		part("Plinth", Vector3.new(1.8, 0.35, 1.8), Vector3.new(0, -1.0, 0), deep, "Metal"),
		part("Spark", Vector3.new(0.34, 0.34, 0.34), Vector3.new(0, 1.15, 0), C.White, "Neon", {
			Shape = "Ball",
		}),
	}
end

local FALLBACKS: { [string]: { Accent: Color3, Parts: { PreviewPart } } } = {
	Skill = { Accent = C.Cyan, Parts = fallbackParts(C.Cyan, C.CyanDeep, "Ball") },
	Item = { Accent = C.Gold, Parts = fallbackParts(C.Gold, C.GoldDeep, nil) },
	Cosmetic = { Accent = C.Violet, Parts = fallbackParts(C.Violet, C.VioletDeep, "Ball") },
	Tool = { Accent = C.Steel, Parts = fallbackParts(C.Steel, C.Slate, nil) },
}

local TYPE_TO_FALLBACK: { [string]: string } = {
	Upgrade = "Skill",
	Backpack = "Item",
	Cosmetic = "Cosmetic",
	Tool = "Tool",
}

local CATEGORY_TO_FALLBACK: { [string]: string } = {
	Skills = "Skill",
	Items = "Item",
	Cosmetics = "Cosmetic",
}

--------------------------------------------------------------------
-- API de lecture (pure)
--------------------------------------------------------------------

function ShopViewportModels.HasDedicatedSpec(id: string?): boolean
	return id ~= nil and SPECS[id] ~= nil
end

function ShopViewportModels.GetFallbackKey(itemType: string?, category: string?): string
	return TYPE_TO_FALLBACK[itemType or ""] or CATEGORY_TO_FALLBACK[category or ""] or "Item"
end

function ShopViewportModels.GetSpec(id: string?, itemType: string?, category: string?): PreviewSpec
	local entry = if id then SPECS[id] else nil
	local key = id
	if not entry then
		key = ShopViewportModels.GetFallbackKey(itemType, category)
		entry = FALLBACKS[key]
	end
	return {
		Id = key or "Item",
		Accent = entry.Accent,
		Parts = entry.Parts,
	}
end

function ShopViewportModels.GetCategoryAccent(category: string?): Color3
	return CATEGORY_ACCENT[category or ""] or C.Cyan
end

--------------------------------------------------------------------
-- Fond, éclairage et arrière-plan du ViewportFrame
--------------------------------------------------------------------

export type Background = { Top: Color3, Bottom: Color3 }

-- Dégradé du cadre décoratif placé DERRIÈRE le ViewportFrame. Un UIGradient
-- enfant d'un ViewportFrame multiplie l'image 3D rendue, pas seulement le fond :
-- il doit rester sur un Frame séparé.
local BACKGROUND: { [string]: Background } = {
	Skills = { Top = Color3.fromRGB(38, 58, 82), Bottom = Color3.fromRGB(20, 32, 50) },
	Items = { Top = Color3.fromRGB(52, 55, 72), Bottom = Color3.fromRGB(28, 31, 45) },
	Cosmetics = { Top = Color3.fromRGB(48, 50, 82), Bottom = Color3.fromRGB(26, 28, 49) },
	Default = { Top = Color3.fromRGB(44, 54, 76), Bottom = Color3.fromRGB(24, 31, 46) },
}

-- Fond uni du ViewportFrame lui-même : bleu-gris clair teinté catégorie. Le
-- laisser transparent assombrirait le rendu et ajouterait un contour noir.
local VIEWPORT_BACKGROUND: { [string]: Color3 } = {
	Skills = Color3.fromRGB(52, 72, 96),
	Items = Color3.fromRGB(68, 66, 78),
	Cosmetics = Color3.fromRGB(62, 62, 92),
	Default = Color3.fromRGB(58, 68, 92),
}

export type Lighting = {
	Ambient: Color3,
	LightColor: Color3,
	LightDirection: Vector3,
}

-- Un ViewportFrame n'accepte qu'une seule lumière directionnelle. Elle vient de
-- l'avant-haut-droite (direction constante, validée au diagnostic) ; le
-- remplissage latéral et le débouchage des ombres passent par l'ambiante.
local KEY_LIGHT_DIRECTION = Vector3.new(-1, -1, -1)

local LIGHTING: { [string]: Lighting } = {
	Skills = {
		Ambient = Color3.fromRGB(205, 215, 230),
		LightColor = Color3.fromRGB(255, 250, 242),
		LightDirection = KEY_LIGHT_DIRECTION,
	},
	Items = {
		Ambient = Color3.fromRGB(212, 210, 222),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = KEY_LIGHT_DIRECTION,
	},
	Cosmetics = {
		Ambient = Color3.fromRGB(208, 208, 230),
		LightColor = Color3.fromRGB(255, 250, 246),
		LightDirection = KEY_LIGHT_DIRECTION,
	},
	Default = {
		Ambient = Color3.fromRGB(205, 215, 230),
		LightColor = Color3.fromRGB(255, 250, 242),
		LightDirection = KEY_LIGHT_DIRECTION,
	},
}

function ShopViewportModels.GetBackground(category: string?): Background
	return BACKGROUND[category or ""] or BACKGROUND.Default
end

function ShopViewportModels.GetViewportBackground(category: string?): Color3
	return VIEWPORT_BACKGROUND[category or ""] or VIEWPORT_BACKGROUND.Default
end

function ShopViewportModels.GetLighting(category: string?): Lighting
	return LIGHTING[category or ""] or LIGHTING.Default
end

export type BackdropPart = {
	Name: string,
	Placement: string, -- "Behind" (disque face caméra) | "Ground" (disque au sol)
	Diameter: number,
	Thickness: number,
	Offset: number, -- recul derrière l'objet, ou hauteur sous l'objet
	Color: Color3,
	Material: string,
	Transparency: number,
}

local SOCLE_COLOR = Color3.fromRGB(70, 88, 118)

function ShopViewportModels.GetIds(): { string }
	local ids = {}
	for id in pairs(SPECS) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function ShopViewportModels.GetFallbackKeys(): { string }
	local keys = {}
	for key in pairs(FALLBACKS) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Demi-encombrement d'une boîte tournée, pour un cadrage jamais coupé.
local function rotatedHalfExtents(size: Vector3, rotation: Vector3?): Vector3
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	if not rotation then
		return Vector3.new(hx, hy, hz)
	end
	local rx, ry, rz = math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local m = {
		{ cy * cz, -cy * sz, sy },
		{ sx * sy * cz + cx * sz, -sx * sy * sz + cx * cz, -sx * cy },
		{ -cx * sy * cz + sx * sz, cx * sy * sz + sx * cz, cx * cy },
	}
	return Vector3.new(
		math.abs(m[1][1]) * hx + math.abs(m[1][2]) * hy + math.abs(m[1][3]) * hz,
		math.abs(m[2][1]) * hx + math.abs(m[2][2]) * hy + math.abs(m[2][3]) * hz,
		math.abs(m[3][1]) * hx + math.abs(m[3][2]) * hy + math.abs(m[3][3]) * hz
	)
end

ShopViewportModels.RotatedHalfExtents = rotatedHalfExtents

-- Boîte englobante d'une spec, puis rayon de la sphère qui la contient : la
-- preview tourne sur elle-même, le cadrage doit tenir sous tous les angles.
function ShopViewportModels.GetBounds(spec: PreviewSpec): Bounds
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, entry in ipairs(spec.Parts) do
		local half = rotatedHalfExtents(entry.Size, entry.Rotation)
		minX = math.min(minX, entry.Offset.X - half.X)
		maxX = math.max(maxX, entry.Offset.X + half.X)
		minY = math.min(minY, entry.Offset.Y - half.Y)
		maxY = math.max(maxY, entry.Offset.Y + half.Y)
		minZ = math.min(minZ, entry.Offset.Z - half.Z)
		maxZ = math.max(maxZ, entry.Offset.Z + half.Z)
	end
	local center = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	-- Rayon horizontal maximal (rotation autour de Y) combiné à la demi-hauteur.
	local halfDiagonal = math.sqrt(size.X * size.X + size.Z * size.Z) / 2
	local radius = math.sqrt(halfDiagonal * halfDiagonal + (size.Y / 2) * (size.Y / 2))
	return { Center = center, Radius = radius, Size = size }
end

-- Distance caméra : la sphère englobante remplit le cadre avec une marge fixe.
function ShopViewportModels.GetCameraDistance(radius: number, fieldOfView: number): number
	local halfFov = math.rad(math.max(fieldOfView, 10) / 2)
	return (radius / math.sin(halfFov)) * 1.12
end

ShopViewportModels.CameraYaw = -26
ShopViewportModels.CameraPitch = 16

-- Halo derrière l'objet et socle sous l'objet : la silhouette se détache du
-- fond sans toucher au cadrage. Les diamètres sont bornés pour que rien ne
-- sorte du cadre calculé par GetCameraDistance().
function ShopViewportModels.GetBackdropSpec(category: string?, bounds: Bounds, fieldOfView: number): { BackdropPart }
	local accent = ShopViewportModels.GetCategoryAccent(category)
	local distance = ShopViewportModels.GetCameraDistance(bounds.Radius, fieldOfView)
	local halfFov = math.rad(math.max(fieldOfView, 10) / 2)
	local halfDiagonal = math.sqrt(bounds.Size.X * bounds.Size.X + bounds.Size.Z * bounds.Size.Z) / 2

	local function behindLimit(offset: number): number
		return (distance + offset) * math.tan(halfFov)
	end

	local haloOffset = bounds.Radius * 1.25
	local coreOffset = bounds.Radius * 1.05
	local haloRadius = math.min(bounds.Radius * 1.18, behindLimit(haloOffset) * 0.95)
	local coreRadius = math.min(bounds.Radius * 0.78, behindLimit(coreOffset) * 0.7)

	local groundOffset = bounds.Size.Y / 2 + 0.2
	local groundLimit = math.sqrt(math.max(bounds.Radius * bounds.Radius - groundOffset * groundOffset, 0.09))
	local socleRadius = math.min(halfDiagonal * 0.92, groundLimit * 0.84)
	local ringRadius = math.min(halfDiagonal * 1.05 + 0.22, groundLimit * 0.99)

	return {
		{
			Name = "Halo",
			Placement = "Behind",
			Diameter = haloRadius * 2,
			Thickness = 0.12,
			Offset = haloOffset,
			Color = accent,
			Material = "Neon",
			Transparency = 0.78,
		},
		{
			Name = "HaloCore",
			Placement = "Behind",
			Diameter = coreRadius * 2,
			Thickness = 0.12,
			Offset = coreOffset,
			Color = accent,
			Material = "Neon",
			Transparency = 0.62,
		},
		{
			Name = "Socle",
			Placement = "Ground",
			Diameter = socleRadius * 2,
			Thickness = 0.22,
			Offset = groundOffset,
			Color = SOCLE_COLOR,
			Material = "SmoothPlastic",
			Transparency = 0.1,
		},
		{
			Name = "SocleRing",
			Placement = "Ground",
			Diameter = ringRadius * 2,
			Thickness = 0.1,
			Offset = groundOffset + 0.06,
			Color = accent,
			Material = "Neon",
			Transparency = 0.5,
		},
	}
end

-- Direction unitaire objet → caméra, partagée par le cadrage et le halo.
function ShopViewportModels.GetCameraDirection(): Vector3
	local yaw = math.rad(ShopViewportModels.CameraYaw)
	local pitch = math.rad(ShopViewportModels.CameraPitch)
	return Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
end

--------------------------------------------------------------------
-- Construction (côté client uniquement, jamais dans le Workspace)
--------------------------------------------------------------------

-- Construit le modèle de preview recentré sur l'origine. Le Model n'est parenté
-- à rien : l'appelant le place dans son ViewportFrame.
function ShopViewportModels.Build(id: string?, itemType: string?, category: string?): (Model, Bounds)
	local spec = ShopViewportModels.GetSpec(id, itemType, category)
	local bounds = ShopViewportModels.GetBounds(spec)

	local model = Instance.new("Model")
	model.Name = "Preview_" .. spec.Id

	for _, entry in ipairs(spec.Parts) do
		local instance = Instance.new("Part")
		instance.Name = entry.Name
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.CastShadow = false
		instance.Size = entry.Size
		instance.Color = entry.Color
		instance.Material = (Enum.Material :: any)[entry.Material] or Enum.Material.SmoothPlastic
		instance.Transparency = entry.Transparency or 0
		if entry.Shape then
			instance.Shape = (Enum.PartType :: any)[entry.Shape] or Enum.PartType.Block
		end
		local cf = CFrame.new(entry.Offset - bounds.Center)
		if entry.Rotation then
			cf = cf
				* CFrame.Angles(
					math.rad(entry.Rotation.X),
					math.rad(entry.Rotation.Y),
					math.rad(entry.Rotation.Z)
				)
		end
		instance.CFrame = cf
		instance.Parent = model
	end

	model.WorldPivot = CFrame.new()
	return model, bounds
end

-- Cadrage : trois-quarts légèrement plongeant, objet centré et jamais coupé.
function ShopViewportModels.GetCameraCFrame(bounds: Bounds, fieldOfView: number): CFrame
	local distance = ShopViewportModels.GetCameraDistance(bounds.Radius, fieldOfView)
	return CFrame.lookAt(ShopViewportModels.GetCameraDirection() * distance, Vector3.new())
end

-- Halo et socle : Model séparé de la preview, il ne tourne pas avec l'objet.
function ShopViewportModels.BuildBackdrop(category: string?, bounds: Bounds, fieldOfView: number): Model
	local cameraDirection = ShopViewportModels.GetCameraDirection()
	local model = Instance.new("Model")
	model.Name = "PreviewBackdrop"

	for _, entry in ipairs(ShopViewportModels.GetBackdropSpec(category, bounds, fieldOfView)) do
		local instance = Instance.new("Part")
		instance.Name = entry.Name
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
		instance.CastShadow = false
		instance.Shape = Enum.PartType.Cylinder
		instance.Size = Vector3.new(entry.Thickness, entry.Diameter, entry.Diameter)
		instance.Color = entry.Color
		instance.Material = (Enum.Material :: any)[entry.Material] or Enum.Material.SmoothPlastic
		instance.Transparency = entry.Transparency

		if entry.Placement == "Behind" then
			local position = cameraDirection * -entry.Offset
			instance.CFrame = CFrame.lookAt(position, position + cameraDirection)
				* CFrame.Angles(0, math.pi / 2, 0)
		else
			instance.CFrame = CFrame.new(0, -entry.Offset, 0) * CFrame.Angles(0, 0, math.pi / 2)
		end

		instance.Parent = model
	end

	return model
end

return ShopViewportModels
