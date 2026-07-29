--!strict
-- Validations géométrie / constantes guirlandes Summer Zone (sans InsertService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneDefs = require(Shared.ZoneDefs)
local SummerZoneStringLights = require(Shared.SummerZoneStringLights)

local SummerZoneStringLightsTests = {}

function SummerZoneStringLightsTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[SummerZoneStringLightsTests] FAIL:", msg)
			ok = false
		end
	end

	check(SummerZoneStringLights.POST_ASSET_ID == 18953379883, "post asset id")
	check(SummerZoneStringLights.STRING_ASSET_ID == 93169410099587, "string asset id")
	check(SummerZoneStringLights.POST_TARGET_HEIGHT >= 9 and SummerZoneStringLights.POST_TARGET_HEIGHT <= 12, "post height 9–12")
	check(
		SummerZoneStringLights.LIGHT_ATTACH_ABOVE_GROUND >= 7
			and SummerZoneStringLights.LIGHT_ATTACH_ABOVE_GROUND <= 9,
		"bulb height 7–9"
	)
	check(SummerZoneStringLights.POST_SPACING >= 20 and SummerZoneStringLights.POST_SPACING <= 40, "spacing raisonnable")

	local layout = ZoneDefs.GetSummerBridgeLayout()
	local points = SummerZoneStringLights.ComputePerimeterPoints(layout)
	check(#points >= 8, "au moins 8 poteaux potentiels")
	check(#points <= 36, "pas plus de 36 poteaux (mobile)")

	local boardO = layout.BoardOrigin
	local insideBoard = 0
	local inEntrance = 0
	local halfEntrance = (layout.ArchGap or 18) / 2 + 10
	for _, p in ipairs(points) do
		if math.abs(p.Position.X - boardO.X) <= layout.BoardEx
			and math.abs(p.Position.Z - boardO.Z) <= layout.BoardEz
		then
			insideBoard += 1
		end
		local nearWest = p.Position.X <= layout.ZoneOrigin.X - layout.Ex + 5 + 12
		if nearWest and math.abs(p.Position.Z - layout.ArchZ) <= halfEntrance then
			inEntrance += 1
		end
	end
	check(insideBoard == 0, "aucun poteau sur le BubbleBoard")
	check(inEntrance == 0, "aucun poteau dans le gap d'entrée")

	if ok then
		print(string.format(
			"[SummerZoneStringLightsTests] OK — %d points périmètre (espacement %d)",
			#points,
			SummerZoneStringLights.POST_SPACING
		))
	end
	return ok
end

return SummerZoneStringLightsTests
