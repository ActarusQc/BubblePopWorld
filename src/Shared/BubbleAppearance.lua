--!strict
-- Apparence bulles (serveur → répliqué sur les clients).
-- Zone principale : pastels + spéciales vives, SANS marqueurs ni pulse.
-- Summer Zone : palette orange Normal + couleurs/marqueurs spéciales legacy (inchangés).
-- AUCUNE vraie lumière (Point/Spot/SurfaceLight), Beam, particules ni post-FX Lighting.

local TweenService = game:GetService("TweenService")

local GameConfig = require(script.Parent.GameConfig)
local BubbleTypes = require(script.Parent.BubbleTypes)
local BubbleValue = require(script.Parent.BubbleValue)

local BubbleAppearance = {}

export type ResolvedStyle = {
	Color: Color3,
	Material: Enum.Material,
	Transparency: number,
	Reflectance: number,
	CastShadow: boolean,
	IsSpecial: boolean,
	RelativeMultiplier: number,
	VisualRank: number,
	BorderScale: number,
	BorderThickness: number,
	BorderTransparency: number,
	Symbol: string,
	SymbolScale: number,
	PulseBorder: boolean,
}

local DEFAULT_RESERVED_DIST = 0.38
local SPECIAL_FOLDER = "SpecialVisuals"
local LEGACY_CLEANUP = {
	"SpecialVisuals",
	"BubbleAura",
	"BubbleBeacon",
	"BubbleBonusGui",
	"BubbleSpecialLight",
	"SpecialLight",
	"BubbleSparkle",
	"BubbleHighlight",
	"SpecialHighlight",
	"BubbleReflection",
	"BubbleRing",
	"SpecialRing",
	"SpecialBeam",
	"BeaconColumn",
	"SparkHost",
	"SpecialShell",
	"BeamBase",
	"BeamTop",
	"SpecialBorder",
	"SpecialSymbol",
	"SymbolGui",
	"RarityMarker",
	"RarityPlaque",
	"BubbleMarker",
}

-- Symboles legacy (Summer uniquement).
local SYMBOL_BY_ID: { [string]: string } = {
	Rare = "★",
	Golden = "●",
	Diamond = "◆",
	Legendary = "✦",
}

local paletteCache: { [string]: { Color3 } } = {}
local maxRankCache: number? = nil

local function paletteKeyForZone(zoneId: string): string
	if zoneId == "ClassicZone" or zoneId == "GameRoom" then
		return "GameRoom"
	end
	return zoneId
end

local function isMainZone(zoneId: string): boolean
	local key = paletteKeyForZone(zoneId)
	return key == "GameRoom" or key == "ClassicZone"
end

local function isSummerZone(zoneId: string): boolean
	return paletteKeyForZone(zoneId) == "SummerZone"
end

local function normalizeCommonTints(common: any): { Color3 }?
	if common == nil then
		return nil
	end
	if typeof(common) == "Color3" then
		return { common :: Color3 }
	end
	if type(common) == "table" then
		local asTable = common :: { any }
		if asTable[1] ~= nil then
			return asTable :: { Color3 }
		end
		if type(asTable.R) == "number" then
			return { common :: Color3 }
		end
	end
	return nil
end

local function colorEq(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 1e-4
		and math.abs(a.G - b.G) < 1e-4
		and math.abs(a.B - b.B) < 1e-4
end

local function presentation()
	return GameConfig.Bubble.SpecialPresentation or {}
end

function BubbleAppearance.ColorDistance(a: Color3, b: Color3): number
	local dr = a.R - b.R
	local dg = a.G - b.G
	local db = a.B - b.B
	return math.sqrt(dr * dr + dg * dg + db * db)
end

function BubbleAppearance.IsSpecialRarity(rarityId: string): boolean
	return rarityId ~= "Normal" and BubbleTypes.ById[rarityId] ~= nil
end

function BubbleAppearance.GetRelativeValueMultiplier(rarityId: string): number
	local normalValue = BubbleValue.GetBaseBubbleValue("Normal")
	if normalValue <= 0 then
		return 1
	end
	return BubbleValue.GetBaseBubbleValue(rarityId) / normalValue
end

function BubbleAppearance.GetRelativeBagMultiplier(rarityId: string, zoneId: string): number
	local normalValue = BubbleValue.GetBubbleBagValue("Normal", zoneId)
	if normalValue <= 0 then
		return 1
	end
	return BubbleValue.GetBubbleBagValue(rarityId, zoneId) / normalValue
end

function BubbleAppearance.FormatPopRewardText(rarityId: string, zoneId: string?): string?
	if not BubbleAppearance.IsSpecialRarity(rarityId) then
		return nil
	end
	local bagValue = BubbleValue.GetBubbleBagValue(rarityId, zoneId)
	local whole = math.floor(bagValue + 0.5)
	if whole <= 0 then
		return nil
	end
	return "+" .. tostring(whole)
end

function BubbleAppearance.GetVisualRank(rarityId: string): number
	if not BubbleAppearance.IsSpecialRarity(rarityId) then
		return 0
	end
	local selfValue = BubbleValue.GetBaseBubbleValue(rarityId)
	local rank = 1
	for _, def in ipairs(BubbleTypes.List) do
		if def.Id ~= "Normal" then
			local v = BubbleValue.GetBaseBubbleValue(def.Id)
			if v < selfValue - 1e-9 then
				rank += 1
			elseif math.abs(v - selfValue) < 1e-9 and def.Id < rarityId then
				rank += 1
			end
		end
	end
	return rank
end

function BubbleAppearance.GetMaxSpecialRank(): number
	if maxRankCache then
		return maxRankCache
	end
	local maxRank = 0
	for _, def in ipairs(BubbleTypes.List) do
		if def.Id ~= "Normal" then
			maxRank = math.max(maxRank, BubbleAppearance.GetVisualRank(def.Id))
		end
	end
	maxRankCache = math.max(maxRank, 1)
	return maxRankCache
end

function BubbleAppearance.GetSpecialColor(rarityId: string, zoneId: string?): Color3
	local key = paletteKeyForZone(zoneId or "ClassicZone")
	local map: any
	if key == "SummerZone" then
		map = GameConfig.Bubble.SummerZoneSpecialColors
	else
		map = GameConfig.Bubble.MainZoneSpecialColors
	end
	if type(map) == "table" then
		local c = (map :: { [string]: Color3 })[rarityId]
		if typeof(c) == "Color3" then
			return c
		end
	end
	local def = BubbleTypes.ById[rarityId]
	if def and typeof(def.Color) == "Color3" then
		return def.Color
	end
	return GameConfig.Bubble.Appearance.BaseColor
end

function BubbleAppearance.GetReservedSpecialColors(): { Color3 }
	local reserved: { Color3 } = {}
	for _, def in ipairs(BubbleTypes.List) do
		if def.Id ~= "Normal" then
			table.insert(reserved, BubbleAppearance.GetSpecialColor(def.Id, "ClassicZone"))
		end
	end
	return reserved
end

function BubbleAppearance.IsReservedSpecialColor(color: Color3, minDistance: number?): boolean
	local threshold = minDistance or (GameConfig.Bubble.ReservedColorMinDistance or DEFAULT_RESERVED_DIST)
	for _, reserved in ipairs(BubbleAppearance.GetReservedSpecialColors()) do
		if BubbleAppearance.ColorDistance(color, reserved) < threshold then
			return true
		end
	end
	return false
end

function BubbleAppearance.FilterNormalPalette(candidates: { Color3 }, minDistance: number?): { Color3 }
	local filtered: { Color3 } = {}
	for _, color in ipairs(candidates) do
		if not BubbleAppearance.IsReservedSpecialColor(color, minDistance) then
			table.insert(filtered, color)
		end
	end
	if #filtered == 0 then
		return candidates
	end
	return filtered
end

function BubbleAppearance.GetNormalPalette(zoneId: string): { Color3 }
	local key = paletteKeyForZone(zoneId)
	local cached = paletteCache[key]
	if cached then
		return cached
	end

	local A = GameConfig.Bubble.Appearance
	local palettes = GameConfig.ZoneBubblePalettes
	local palette = palettes and palettes[key]
	local fromPalette = palette and normalizeCommonTints(palette.Common)

	local candidates: { Color3 }
	if key == "GameRoom" then
		local main = GameConfig.Bubble.MainZoneNormalColors
		if type(main) == "table" and #(main :: { Color3 }) > 0 then
			-- Palette autoritaire zone principale : ne pas filtrer (sinon pastels Neon
			-- trop proches des spéciales sous ReservedColorMinDistance).
			candidates = main :: { Color3 }
			paletteCache[key] = candidates
			return candidates
		else
			candidates = fromPalette or A.TintVariants
		end
	else
		candidates = fromPalette or A.TintVariants
	end

	local result: { Color3 }
	if key == "GameRoom" and #candidates > 1 then
		result = BubbleAppearance.FilterNormalPalette(candidates)
	else
		result = candidates
	end

	paletteCache[key] = result
	return result
end

function BubbleAppearance.ClearPaletteCache()
	table.clear(paletteCache)
	maxRankCache = nil
end

function BubbleAppearance.ResolveNormalColor(zoneId: string, tintIndex: number): Color3
	local palette = BubbleAppearance.GetNormalPalette(zoneId)
	local n = #palette
	if n <= 0 then
		return GameConfig.Bubble.Appearance.BaseColor
	end
	local idx = ((math.floor(tintIndex) - 1) % n) + 1
	return palette[idx]
end

function BubbleAppearance.IsNormalPaletteColor(zoneId: string, color: Color3): boolean
	for _, c in ipairs(BubbleAppearance.GetNormalPalette(zoneId)) do
		if BubbleAppearance.ColorDistance(c, color) < 1e-4 then
			return true
		end
	end
	return false
end

function BubbleAppearance.GetSymbolForRarity(rarityId: string, zoneId: string?): string?
	if not BubbleAppearance.IsSpecialRarity(rarityId) then
		return nil
	end
	if zoneId and isSummerZone(zoneId) then
		return SYMBOL_BY_ID[rarityId] or "★"
	end
	return nil
end

function BubbleAppearance.Resolve(zoneId: string, rarityId: string, tintIndex: number): ResolvedStyle
	local A = GameConfig.Bubble.Appearance
	local P = presentation()
	local def = BubbleTypes.ById[rarityId] or BubbleTypes.ById.Normal
	local isSpecial = BubbleAppearance.IsSpecialRarity(def.Id)
	local relative = if isSpecial then BubbleAppearance.GetRelativeValueMultiplier(def.Id) else 1
	local rank = BubbleAppearance.GetVisualRank(def.Id)
	local summer = isSummerZone(zoneId)
	local main = isMainZone(zoneId)

	if not isSpecial then
		if summer then
			return {
				Color = BubbleAppearance.ResolveNormalColor(zoneId, tintIndex),
				Material = Enum.Material.Glass,
				Transparency = 0.35,
				Reflectance = 0.05,
				CastShadow = A.CastShadow,
				IsSpecial = false,
				RelativeMultiplier = 1,
				VisualRank = 0,
				BorderScale = 1,
				BorderThickness = 0,
				BorderTransparency = 1,
				Symbol = "",
				SymbolScale = 0,
				PulseBorder = false,
			}
		end
		-- Zone principale : Neon opaque (shading non caméra-dépendant).
		return {
			Color = BubbleAppearance.ResolveNormalColor(zoneId, tintIndex),
			Material = Enum.Material.Neon,
			Transparency = 0,
			Reflectance = 0,
			CastShadow = false,
			IsSpecial = false,
			RelativeMultiplier = 1,
			VisualRank = 0,
			BorderScale = 1,
			BorderThickness = 0,
			BorderTransparency = 1,
			Symbol = "",
			SymbolScale = 0,
			PulseBorder = false,
		}
	end

	local styles = if summer then GameConfig.Bubble.SummerSpecialStyles else GameConfig.Bubble.SpecialStyles
	local special = styles and styles[def.Id]
	local color = BubbleAppearance.GetSpecialColor(def.Id, zoneId)
	local useMarkers = summer

	if main then
		return {
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0,
			Reflectance = 0,
			CastShadow = false,
			IsSpecial = true,
			RelativeMultiplier = relative,
			VisualRank = rank,
			BorderScale = 1,
			BorderThickness = 0,
			BorderTransparency = 1,
			Symbol = "",
			SymbolScale = 0,
			PulseBorder = false,
		}
	end

	return {
		Color = color,
		Material = if special and special.Material then special.Material else Enum.Material.SmoothPlastic,
		Transparency = if special and special.Transparency ~= nil then special.Transparency else 0.12,
		Reflectance = if special and special.Reflectance ~= nil then special.Reflectance else 0.3,
		CastShadow = A.CastShadow,
		IsSpecial = true,
		RelativeMultiplier = relative,
		VisualRank = rank,
		BorderScale = if useMarkers then (P.BorderScaleBase or 1.1) + (P.BorderScalePerRank or 0.02) * (rank - 1) else 1,
		BorderThickness = if useMarkers then (P.BorderThicknessBase or 0.22) + (P.BorderThicknessPerRank or 0.04) * (rank - 1) else 0,
		BorderTransparency = if useMarkers then (P.BorderTransparencyBase or 0.28) - (P.BorderTransparencyStep or 0.04) * (rank - 1) else 1,
		Symbol = if useMarkers then (SYMBOL_BY_ID[def.Id] or "★") else "",
		SymbolScale = if useMarkers then (P.SymbolScaleBase or 1.15) + (P.SymbolScalePerRank or 0.08) * (rank - 1) else 0,
		PulseBorder = useMarkers and (P.EnableBorderPulse == true) and rank >= (P.PulseMinRank or 3),
	}
end

function BubbleAppearance.PickTintIndex(
	paletteSize: number,
	neighborTintIndices: { number },
	rng: Random
): number
	if paletteSize <= 1 then
		return 1
	end

	local forbidden: { [number]: boolean } = {}
	local forbiddenCount = 0
	for _, idx in ipairs(neighborTintIndices) do
		local n = ((math.floor(idx) - 1) % paletteSize) + 1
		if not forbidden[n] then
			forbidden[n] = true
			forbiddenCount += 1
		end
	end

	if forbiddenCount >= paletteSize then
		return rng:NextInteger(1, paletteSize)
	end

	local allowed: { number } = table.create(paletteSize - forbiddenCount)
	for i = 1, paletteSize do
		if not forbidden[i] then
			table.insert(allowed, i)
		end
	end
	return allowed[rng:NextInteger(1, #allowed)]
end

function BubbleAppearance.ColorsAreDistinct(palette: { Color3 }, minDistance: number?): boolean
	local threshold = minDistance or 0.12
	if #palette < 2 then
		return false
	end
	for i = 1, #palette - 1 do
		for j = i + 1, #palette do
			if BubbleAppearance.ColorDistance(palette[i], palette[j]) < threshold then
				return false
			end
		end
	end
	return true
end

local function isMarkerName(name: string): boolean
	local lower = string.lower(name)
	return string.find(lower, "marker", 1, true) ~= nil
		or string.find(lower, "plaque", 1, true) ~= nil
		or string.find(lower, "symbol", 1, true) ~= nil
		or string.find(lower, "border", 1, true) ~= nil
		or string.find(lower, "rarity", 1, true) ~= nil
		or string.find(lower, "special", 1, true) ~= nil
		or string.find(lower, "beacon", 1, true) ~= nil
		or string.find(lower, "highlight", 1, true) ~= nil
end

local function stripRealLights(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d:Destroy()
		elseif d:IsA("Beam") then
			d:Destroy()
		elseif d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
end

function BubbleAppearance.ClearSpecialVisuals(bubble: BasePart)
	for _, name in ipairs(LEGACY_CLEANUP) do
		local child = bubble:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end

	for _, child in ipairs(bubble:GetChildren()) do
		-- ColorRush MiniEvent : conserver le marqueur temporaire
		if child.Name ~= "EventMarkRing" then
			if child:IsA("SurfaceAppearance")
				or child:IsA("BillboardGui")
				or child:IsA("SurfaceGui")
				or child:IsA("Highlight")
				or child:IsA("SelectionBox")
				or child:IsA("BoxHandleAdornment")
				or child:IsA("SphereHandleAdornment")
				or child:IsA("CylinderHandleAdornment")
				or child:IsA("LineHandleAdornment")
				or child:IsA("ConeHandleAdornment")
			then
				child:Destroy()
			elseif child:IsA("Decal") or child:IsA("Texture") then
				child:Destroy()
			elseif child:IsA("PointLight") or child:IsA("SpotLight") or child:IsA("SurfaceLight") then
				child:Destroy()
			elseif child:IsA("Beam") or child:IsA("ParticleEmitter") then
				child:Destroy()
			elseif child:IsA("Attachment") and (
				child.Name == "BeamBase"
					or child.Name == "BeamTop"
					or child:GetAttribute("SpecialMarker") == true
					or isMarkerName(child.Name)
			) then
				child:Destroy()
			elseif child:IsA("BasePart") and (
				isMarkerName(child.Name)
					or child.Name == SPECIAL_FOLDER
					or child:GetAttribute("SpecialMarker") == true
			) then
				child:Destroy()
			elseif child:IsA("Folder") and isMarkerName(child.Name) then
				child:Destroy()
			end
		end
	end

	for _, d in ipairs(bubble:GetDescendants()) do
		if d.Name ~= "EventMarkRing" then
			if d:IsA("BillboardGui")
				or d:IsA("SurfaceGui")
				or d:IsA("Highlight")
				or d:IsA("SelectionBox")
				or d:IsA("PointLight")
				or d:IsA("SpotLight")
				or d:IsA("SurfaceLight")
				or d:IsA("Beam")
				or d:IsA("ParticleEmitter")
			then
				d:Destroy()
			end
		end
	end
	stripRealLights(bubble)
end

function BubbleAppearance.ApplySpecialBubbleMarker(
	bubbleVisual: BasePart,
	bubbleData: { Id: string, ZoneId: string?, Value: number? },
	_zoneConfig: any?
): { BorderCreated: boolean, SymbolCreated: boolean, Style: ResolvedStyle }
	local rarityId = bubbleData.Id
	local zoneId = bubbleData.ZoneId or "ClassicZone"
	local style = BubbleAppearance.Resolve(zoneId, rarityId, 1)

	BubbleAppearance.ClearSpecialVisuals(bubbleVisual)

	if not isSummerZone(zoneId) or not style.IsSpecial then
		return { BorderCreated = false, SymbolCreated = false, Style = style }
	end

	local folder = Instance.new("Folder")
	folder.Name = SPECIAL_FOLDER
	folder.Parent = bubbleVisual

	local color = style.Color
	local midY = 0

	local diam = math.max(bubbleVisual.Size.X, bubbleVisual.Size.Z) * style.BorderScale
	local border = Instance.new("Part")
	border.Name = "SpecialBorder"
	border.Anchored = true
	border.CanCollide = false
	border.CanQuery = false
	border.CanTouch = false
	border.CastShadow = false
	border.Material = Enum.Material.Neon
	border.Color = color
	border.Transparency = math.clamp(style.BorderTransparency, 0.12, 0.55)
	border.Size = Vector3.new(style.BorderThickness, diam, diam)
	border.CFrame = bubbleVisual.CFrame * CFrame.new(0, midY, 0) * CFrame.Angles(0, 0, math.rad(90))
	border.Parent = folder

	local borderMesh = Instance.new("SpecialMesh")
	borderMesh.MeshType = Enum.MeshType.Cylinder
	borderMesh.Scale = Vector3.new(1, 1, 1)
	borderMesh.Parent = border

	local topY = bubbleVisual.Size.Y * 0.42
	local symSize = style.SymbolScale
	local disc = Instance.new("Part")
	disc.Name = "SpecialSymbol"
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.SmoothPlastic
	disc.Color = color
	disc.Transparency = 0.05
	disc.Size = Vector3.new(symSize, 0.12, symSize)
	disc.CFrame = bubbleVisual.CFrame * CFrame.new(0, topY, 0)
	disc.Parent = folder

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SymbolGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.Parent = disc

	local label = Instance.new("TextLabel")
	label.Name = "Glyph"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = style.Symbol
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.25
	label.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui

	if style.PulseBorder then
		local bright = math.clamp(border.Transparency - 0.1, 0.08, 0.45)
		local dim = math.clamp(border.Transparency + 0.12, 0.2, 0.65)
		border.Transparency = dim
		TweenService:Create(
			border,
			TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = bright }
		):Play()
	end

	stripRealLights(folder)

	return {
		BorderCreated = true,
		SymbolCreated = true,
		Style = style,
	}
end

local function applyMeshScale(bubble: BasePart, style: ResolvedStyle, zoneId: string)
	local mesh = bubble:FindFirstChildOfClass("SpecialMesh")
	if not mesh then
		return
	end
	local base = GameConfig.Bubble.MeshScale
	if style.IsSpecial and isSummerZone(zoneId) then
		local boost = 1 + math.min(0.08, 0.02 * style.VisualRank)
		mesh.Scale = base * boost
	else
		mesh.Scale = base
	end
end

function BubbleAppearance.ApplyToPart(
	bubble: BasePart,
	zoneId: string,
	rarityId: string,
	tintIndex: number,
	alive: boolean
)
	return BubbleAppearance.ApplyBubbleVisual(bubble, rarityId, zoneId, tintIndex, alive)
end

-- Autorité unique du rendu bulle (création / respawn / recycle / pop).
function BubbleAppearance.ApplyBubbleVisual(
	bubble: BasePart,
	rarityId: string,
	zoneId: string,
	tintIndex: number,
	alive: boolean
)
	BubbleAppearance.ClearSpecialVisuals(bubble)

	local def = BubbleTypes.ById[rarityId] or BubbleTypes.ById.Normal
	local finalId = def.Id
	local isSpecial = BubbleAppearance.IsSpecialRarity(finalId)
	local baseValue = BubbleValue.GetBaseBubbleValue(finalId)
	local bagValue = BubbleValue.GetBubbleBagValue(finalId, zoneId)
	local main = isMainZone(zoneId)

	local style = BubbleAppearance.Resolve(zoneId, finalId, if isSpecial then 1 else tintIndex)
	if isSpecial then
		local forcedColor = BubbleAppearance.GetSpecialColor(finalId, zoneId)
		if not colorEq(style.Color, forcedColor) then
			style.Color = forcedColor
		end
	end

	-- Zone principale = toujours Neon (émissif). Jamais SmoothPlastic / Glass ici.
	local material = if main then Enum.Material.Neon else style.Material

	bubble.Material = material
	bubble.Color = style.Color
	bubble.Reflectance = if main then 0 else style.Reflectance
	bubble.CastShadow = if main then false else style.CastShadow
	if alive then
		bubble.Transparency = if main then 0 else style.Transparency
	else
		bubble.Transparency = 1
	end

	local mesh = bubble:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh:IsA("SpecialMesh") then
		(mesh :: SpecialMesh).VertexColor = Vector3.new(1, 1, 1)
	end

	bubble:SetAttribute("Rarity", finalId)
	bubble:SetAttribute("TintIndex", if isSpecial then 0 else tintIndex)
	bubble:SetAttribute("IsSpecial", isSpecial)
	bubble:SetAttribute("BaseValue", baseValue)
	bubble:SetAttribute("BagValue", bagValue)
	bubble:SetAttribute("RelativeMultiplier", style.RelativeMultiplier)
	bubble:SetAttribute("BonusLabel", nil)
	bubble:SetAttribute("VisualMode", if main then "EmissiveNeonStable" else "LegacyLit")

	applyMeshScale(bubble, style, zoneId)

	if not isSpecial or not alive or not isSummerZone(zoneId) then
		for _, name in ipairs(LEGACY_CLEANUP) do
			local child = bubble:FindFirstChild(name)
			if child then
				child:Destroy()
			end
		end
		stripRealLights(bubble)
		return style
	end

	BubbleAppearance.ApplySpecialBubbleMarker(bubble, {
		Id = finalId,
		ZoneId = zoneId,
		Value = baseValue,
	}, nil)
	stripRealLights(bubble)

	return style
end

function BubbleAppearance.IsMainZoneStableVisual(bubble: BasePart, alive: boolean?): boolean
	if bubble.Material ~= Enum.Material.Neon then
		return false
	end
	if bubble.Reflectance ~= 0 then
		return false
	end
	if bubble.CastShadow ~= false then
		return false
	end
	local expectAlive = if alive == nil then true else alive
	if expectAlive then
		if bubble.Transparency ~= 0 then
			return false
		end
	end
	if BubbleAppearance.HasRealLights(bubble) or BubbleAppearance.HasBeam(bubble) then
		return false
	end
	if bubble:FindFirstChildOfClass("SurfaceAppearance") then
		return false
	end
	if bubble:FindFirstChildOfClass("Highlight") then
		return false
	end
	for _, child in ipairs(bubble:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") then
			if child.Name ~= "EventMarkRing" then
				return false
			end
		end
	end
	return true
end

function BubbleAppearance.IsAllowedMainZoneNormalColor(color: Color3): boolean
	local palette = GameConfig.Bubble.MainZoneNormalColors
	if type(palette) ~= "table" then
		return false
	end
	for _, c in ipairs(palette :: { Color3 }) do
		if colorEq(c, color) then
			return true
		end
	end
	return false
end

function BubbleAppearance.IsAllowedMainZoneSpecialColor(color: Color3): boolean
	local map = GameConfig.Bubble.MainZoneSpecialColors
	if type(map) ~= "table" then
		return false
	end
	for _, c in pairs(map :: { [string]: Color3 }) do
		if colorEq(c, color) then
			return true
		end
	end
	return false
end

function BubbleAppearance.HasSpecialBorder(bubble: BasePart): boolean
	local folder = bubble:FindFirstChild(SPECIAL_FOLDER)
	return folder ~= nil and folder:FindFirstChild("SpecialBorder") ~= nil
end

function BubbleAppearance.HasSpecialSymbol(bubble: BasePart): boolean
	local folder = bubble:FindFirstChild(SPECIAL_FOLDER)
	return folder ~= nil and folder:FindFirstChild("SpecialSymbol") ~= nil
end

function BubbleAppearance.HasRarityMarker(bubble: BasePart): boolean
	if BubbleAppearance.HasSpecialBorder(bubble) or BubbleAppearance.HasSpecialSymbol(bubble) then
		return true
	end
	for _, d in ipairs(bubble:GetDescendants()) do
		if d:IsA("BillboardGui")
			or d:IsA("SurfaceGui")
			or d:IsA("Highlight")
			or d:IsA("SelectionBox")
			or d:IsA("BoxHandleAdornment")
			or d:IsA("SphereHandleAdornment")
			or d:IsA("CylinderHandleAdornment")
		then
			return true
		end
		if d:IsA("BasePart") and isMarkerName(d.Name) then
			return true
		end
	end
	for _, child in ipairs(bubble:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") then
			return true
		end
		if child.Name == SPECIAL_FOLDER then
			return true
		end
	end
	return false
end

function BubbleAppearance.HasRealLights(bubble: BasePart): boolean
	for _, d in ipairs(bubble:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			return true
		end
	end
	return false
end

function BubbleAppearance.HasBeam(bubble: BasePart): boolean
	for _, d in ipairs(bubble:GetDescendants()) do
		if d:IsA("Beam") or d.Name == "BeaconColumn" or d.Name == "SpecialBeam" then
			return true
		end
	end
	return false
end

function BubbleAppearance.CountLightsIn(root: Instance): number
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			n += 1
		end
	end
	return n
end

return BubbleAppearance
