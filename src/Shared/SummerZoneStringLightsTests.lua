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
	check(Lights.POST_TARGET_HEIGHT >= 9 and Lights.POST_TARGET_HEIGHT <= 12, "hauteur poteau 9–12")
	check(Lights.STRING_LOWEST_TARGET >= 7 and Lights.STRING_LOWEST_TARGET <= 9, "point bas ampoules 7–9")
	check(Lights.STRING_LOWEST_MIN >= 7, "plancher ampoules >= 7 (au-dessus des têtes)")
	check(Lights.POST_SPACING >= 20 and Lights.POST_SPACING <= 40, "espacement raisonnable")
	check(Lights.POST_SPACING == 30, "espacement centralisé = 30")

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

	if ok then
		print(string.format(
			"[SummerZoneStringLightsTests] OK — %d points périmètre | sol %.2f | attache +%.1f | point bas +%.1f",
			#points,
			groundY,
			attachY - groundY,
			lowest - groundY
		))
	end
	return ok
end

return SummerZoneStringLightsTests
