--!strict
-- Validations géométrie / constantes guirlandes Summer Zone (sans InsertService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneDefs = require(Shared.ZoneDefs)
local GameConfig = require(Shared.GameConfig)
local Lights = require(Shared.SummerZoneStringLights)

local SummerZoneStringLightsTests = {}

function SummerZoneStringLightsTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[SummerZoneStringLightsTests] FAIL:", msg)
			ok = false
		end
	end

	check(Lights.POST_ASSET_ID == 18953379883, "post asset id")
	check(Lights.STRING_ASSET_ID == 93169410099587, "string asset id")
	check(type(Lights.CanGenerateLights) == "function", "CanGenerateLights")
	check(Lights.CanGenerateLights() == false, "lights blocked when ApprovedAssetIds empty / cache missing")
	check(type(Lights.GetApprovedTemplate) == "function", "GetApprovedTemplate")
	check(Lights.GetApprovedTemplate(18953379883) == nil, "no marketplace fallback for posts")
	check(Lights.POST_TARGET_HEIGHT >= 9 and Lights.POST_TARGET_HEIGHT <= 12, "hauteur poteau 9–12")
	check(Lights.STRING_LOWEST_TARGET >= 7 and Lights.STRING_LOWEST_TARGET <= 9, "point bas ampoules 7–9")
	check(Lights.STRING_LOWEST_MIN >= 7, "plancher ampoules >= 7 (au-dessus des têtes)")
	check(Lights.POST_SPACING >= 20 and Lights.POST_SPACING <= 40, "espacement raisonnable")
	check(Lights.POST_SPACING == 30, "espacement centralisé = 30")
	check(type(Lights.RebuildSummerPerimeterLights) == "function", "alias RebuildSummerPerimeterLights")
	check(type(Lights.RefreshSummerPerimeterLights) == "function", "RefreshSummerPerimeterLights")
	check(type(Lights.CreateSummerPerimeterLights) == "function", "CreateSummerPerimeterLights")
	check(type(Lights.RemoveSummerPerimeterLights) == "function", "RemoveSummerPerimeterLights")
	check(Lights.GENERATOR_ID == "SummerZoneStringLights", "GeneratedBy id")

	local layout = ZoneDefs.GetSummerBridgeLayout()
	check(layout.Ex == 90 and layout.Ez == 66, "périmètre compact 180x132")
	check(layout.ZoneDepth == 180 and layout.ZoneWidth == 132, "lumières suivent ZoneDepth/ZoneWidth")

	-- Sol : dessus du ZoneFloor construit par ZoneBuilder, pas layout.Y.
	local groundY = Lights.GetGroundY(layout)
	local expectedGround = layout.Y - GameConfig.Grid.BubbleSize.Y * 0.35
	check(math.abs(groundY - expectedGround) < 1e-6, "sol = dessus du ZoneFloor")
	check(groundY < layout.Y, "sol sous le plan des bulles")

	-- Attache et courbe.
	local attachY = groundY + Lights.POST_TARGET_HEIGHT - Lights.POST_GROUND_SINK - Lights.STRING_ATTACH_BELOW_TOP
	check(attachY - groundY >= 9, "attache près du sommet du poteau (>= 9 studs)")
	local sag = Lights.ComputeSagDepth(attachY, groundY)
	check(sag > 0, "profondeur de courbe positive")
	check(attachY - sag >= groundY + Lights.STRING_LOWEST_MIN - 1e-6, "point bas au-dessus des têtes")

	local a = Vector3.new(0, attachY, 0)
	local b = Vector3.new(Lights.POST_SPACING, attachY, 0)
	local factor = Lights.MaxNodeSagFactor(Lights.STRING_CHAIN_PIECES)
	check(factor > 0 and factor <= 1, "facteur de noeud dans ]0,1]")
	local nodes = Lights.ComputeSagNodes(a, b, sag / factor, Lights.STRING_CHAIN_PIECES)
	check(#nodes == Lights.STRING_CHAIN_PIECES + 1, "nombre de noeuds de courbe")
	check(math.abs(nodes[1].Y - attachY) < 1e-6, "noeud de départ au point d'attache")
	check(math.abs(nodes[#nodes].Y - attachY) < 1e-6, "noeud d'arrivée au point d'attache")

	local lowest = math.huge
	for _, n in ipairs(nodes) do
		lowest = math.min(lowest, n.Y)
		check(n.Y <= attachY + 1e-6, "aucun noeud au-dessus des attaches (pas d'arche inversée)")
	end
	check(lowest < attachY, "milieu de guirlande plus bas que les extrémités")
	check(lowest >= groundY + Lights.STRING_LOWEST_MIN - 1e-6, "point le plus bas >= 7 studs du sol")
	check(math.abs((attachY - lowest) - sag) < 1e-6, "noeud le plus bas exactement à la profondeur voulue")
	check(lowest - groundY >= 7 and lowest - groundY <= 9, "point bas dans la fenêtre 7–9 studs")

	-- Symétrie de la courbe.
	local mid = math.floor(#nodes / 2)
	if #nodes % 2 == 1 and mid >= 1 then
		check(math.abs(nodes[mid].Y - nodes[#nodes - mid + 1].Y) < 1e-6, "courbe symétrique")
	end

	-- Périmètre : rien sur le board ni dans l'entrée.
	local points = Lights.ComputePerimeterPoints(layout)
	check(#points >= 8, "au moins 8 poteaux potentiels")
	check(#points <= 36, "pas plus de 36 poteaux (mobile)")

	local boardO = layout.BoardOrigin
	local zoneO = layout.ZoneOrigin
	local insideBoard = 0
	local inEntrance = 0
	local outsideZone = 0
	local halfEntrance = (layout.ArchGap or 18) / 2 + 10
	for _, p in ipairs(points) do
		check(math.abs(p.Position.Y - groundY) < 1e-6, "point de périmètre au niveau du sol")
		if math.abs(p.Position.X - boardO.X) <= layout.BoardEx
			and math.abs(p.Position.Z - boardO.Z) <= layout.BoardEz
		then
			insideBoard += 1
		end
		local nearWest = p.Position.X <= zoneO.X - layout.Ex + 5 + 12
		if nearWest and math.abs(p.Position.Z - layout.ArchZ) <= halfEntrance then
			inEntrance += 1
		end
		-- Doit longer la vraie zone (pas l'ancien contour 240×240).
		if math.abs(p.Position.X - zoneO.X) > layout.Ex + 1
			or math.abs(p.Position.Z - zoneO.Z) > layout.Ez + 1
		then
			outsideZone += 1
		end
	end
	check(insideBoard == 0, "aucun poteau sur le BubbleBoard")
	check(inEntrance == 0, "aucun poteau dans le gap d'entrée")
	check(outsideZone == 0, "aucun poteau hors emprise Summer actuelle")

	-- Contour attendu : compteurs et emprise dérivés du layout courant.
	check(type(Lights.DescribePerimeter) == "function", "DescribePerimeter exposé")
	local desc = Lights.DescribePerimeter(layout)
	check(desc.PostCount == #points, "DescribePerimeter aligné sur ComputePerimeterPoints")
	check(desc.ZoneDepth == layout.ZoneDepth and desc.ZoneWidth == layout.ZoneWidth, "description = dimensions actuelles")
	check(math.abs(desc.MinX - (zoneO.X - layout.Ex + 5)) < 1e-6, "bord contour X min suit Ex")
	check(math.abs(desc.MaxX - (zoneO.X + layout.Ex - 5)) < 1e-6, "bord contour X max suit Ex")
	check(math.abs(desc.MinZ - (zoneO.Z - layout.Ez + 5)) < 1e-6, "bord contour Z min suit Ez")
	check(math.abs(desc.MaxZ - (zoneO.Z + layout.Ez - 5)) < 1e-6, "bord contour Z max suit Ez")

	-- Boucle fermée : un span par arête, sauf celui qui enjambe l'entrée (trop long).
	check(desc.StringCount == desc.PostCount - 1, "exactement un span omis (l'entrée reste dégagée)")
	check(desc.StringCount >= 8, "assez de guirlandes pour ceinturer la zone")
	check(desc.EntranceGapWidth >= layout.ArchGap, "vide d'entrée au moins aussi large que l'arche")

	-- Géométrie pure : relancer ne change rien (pas de dérive ni de doublon au recalcul).
	local again = Lights.DescribePerimeter(layout)
	check(again.PostCount == desc.PostCount and again.StringCount == desc.StringCount, "recalcul idempotent")

	-- Aucun span ne traverse l'entrée.
	local crossingEntrance = 0
	for i = 1, #points do
		local p1 = points[i].Position
		local p2 = points[if i < #points then i + 1 else 1].Position
		local dist = (p2 - p1).Magnitude
		if dist <= Lights.POST_SPACING * 1.65 and dist >= 4 then
			local midpoint = p1:Lerp(p2, 0.5)
			local nearWest = midpoint.X <= zoneO.X - layout.Ex + 5 + 12
			if nearWest and math.abs(midpoint.Z - layout.ArchZ) <= halfEntrance then
				crossingEntrance += 1
			end
		end
	end
	check(crossingEntrance == 0, "aucune guirlande au-dessus de l'accès principal")

	if ok then
		print(string.format(
			"[SummerZoneStringLightsTests] OK — %d poteaux / %d guirlandes | zone %dx%d | contour X[%.0f..%.0f] Z[%.0f..%.0f]"
				.. " | sol %.2f | attache +%.1f | point bas +%.1f | vide entrée %.0f",
			desc.PostCount,
			desc.StringCount,
			layout.ZoneDepth,
			layout.ZoneWidth,
			desc.MinX,
			desc.MaxX,
			desc.MinZ,
			desc.MaxZ,
			groundY,
			attachY - groundY,
			lowest - groundY,
			desc.EntranceGapWidth
		))
		print("[SummerZoneStringLightsTests] Ordre Studio: 1) Create/Refresh Summer Preview  2) Refresh Summer String Lights")
	end
	return ok
end

return SummerZoneStringLightsTests
