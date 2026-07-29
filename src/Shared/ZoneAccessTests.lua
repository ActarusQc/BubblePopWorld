--!strict
-- Validations ciblées des règles d'accès zones + planches multi-zones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneDefs = require(Shared.ZoneDefs)
local GameConfig = require(Shared.GameConfig)

local ZoneAccessTests = {}

function ZoneAccessTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[ZoneAccessTests] FAIL:", msg)
			ok = false
		end
	end

	check(ZoneDefs.GetRequiredLevel("ClassicZone") == 1, "Classic RequiredLevel")
	check(ZoneDefs.GetRequiredLevel("SummerZone") == 5, "Summer RequiredLevel")
	check(ZoneDefs.GetRewardMultiplier("SummerZone") == 1, "Summer RewardMultiplier == 1")
	check(ZoneDefs.GetRewardMultiplier("ClassicZone") == 1, "Classic RewardMultiplier == 1")

	check(ZoneDefs.CanLevelEnter(4, "SummerZone") == false, "level 4 blocked")
	check(ZoneDefs.CanLevelEnter(5, "SummerZone") == true, "level 5 allowed (>=)")
	check(ZoneDefs.CanLevelEnter(6, "SummerZone") == true, "level 6 allowed")
	check(ZoneDefs.CanLevelEnter(1, "ClassicZone") == true, "classic level 1 allowed")

	check(ZoneDefs.GetAccessGroupName(1) == "ZoneAccess_1", "access group level 1")
	check(ZoneDefs.GetAccessGroupName(4) == "ZoneAccess_1", "access group level 4")
	check(ZoneDefs.GetAccessGroupName(5) == "ZoneAccess_5", "access group level 5")
	check(ZoneDefs.GetAccessGroupName(99) == "ZoneAccess_5", "access group level 99")

	local layout = ZoneDefs.GetSummerBridgeLayout()
	local L = ZoneDefs.SummerLayout
	check(layout.ZoneOrigin == ZoneDefs.SummerZone.ZoneOrigin, "bridge ZoneOrigin")
	check(layout.BoardOrigin == ZoneDefs.SummerZone.Origin, "bridge BoardOrigin")
	check(layout.GateX > layout.SummerEdgeX, "gate past summer edge")
	check(layout.ArchX < layout.SummerEdgeX, "arch before summer edge")
	check(layout.MidX > ZoneDefs.ClassicZone.Origin.X, "bridge mid à droite de classic")

	local summerReq = ZoneDefs.GetRequiredLevel("SummerZone")
	check((1 < summerReq) == true, "ZoneAccess_1 collides with SummerGate")
	check((5 < summerReq) == false, "ZoneAccess_5 does not collide with SummerGate")

	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local right = ZoneDefs.CLASSIC_RIGHT
	local delta = summer.ZoneOrigin - classic.Origin
	check(delta:Dot(right) > 0, "Summer à droite de Classic")
	check(classic.Origin == GameConfig.Grid.Origin, "Classic Origin = Grid.Origin")

	-- Classic board inchangé
	check(classic.SizeX == GameConfig.Grid.SizeX and classic.SizeZ == GameConfig.Grid.SizeZ, "Classic 40x40")

	-- Summer : board réduit, zone extérieure inchangée
	check(L.OuterWidth == GameConfig.Grid.SizeX * GameConfig.Grid.Spacing, "outer width inchangée")
	check(L.OuterDepth == GameConfig.Grid.SizeZ * GameConfig.Grid.Spacing, "outer depth inchangée")
	check(summer.SizeX == L.BubbleColumns and summer.SizeZ == L.BubbleRows, "Size = Rows/Cols")
	check(summer.SizeX < classic.SizeX, "Summer board plus petit (colonnes)")
	check(summer.SizeZ < classic.SizeZ, "Summer board plus petit (rangées)")

	local cb = ZoneDefs.GetZoneBounds("ClassicZone")
	local sb = ZoneDefs.GetZoneBounds("SummerZone")
	local bb = ZoneDefs.GetBoardBounds("SummerZone")
	check(cb ~= nil and sb ~= nil and bb ~= nil, "bounds présents")
	if cb and sb and bb then
		local overlap = cb.MaxX > sb.MinX and cb.MinX < sb.MaxX and cb.MaxZ > sb.MinZ and cb.MinZ < sb.MaxZ
		check(not overlap, "pas de chevauchement Classic/Summer")
		check(sb.MinX - cb.MaxX >= 10, "écart minimum entre planches")

		local entrance = bb.MinX - sb.MinX
		local rear = sb.MaxX - bb.MaxX
		local sideS = bb.MinZ - sb.MinZ
		local sideN = sb.MaxZ - bb.MaxZ
		check(entrance >= L.EntranceDecorMargin - 0.05, "marge entrée >= 14")
		check(rear >= L.RearDecorMargin - 0.05, "marge fond >= 24")
		check(sideS >= L.SideDecorMargin - 0.05, "marge sud >= 16")
		check(sideN >= L.SideDecorMargin - 0.05, "marge nord >= 16")
		check(rear > entrance, "fond plus large que entrée")
		check(L.SideDecorMargin == 16, "SideDecorMargin = 16")
		check(L.EntranceDecorMargin == 14, "EntranceDecorMargin = 14")
		check(L.RearDecorMargin == 24, "RearDecorMargin = 24")
		check(L.BubbleSpacing == GameConfig.Grid.Spacing, "BubbleSpacing = Grid.Spacing")
		check(L.BubbleColumns == 33, "BubbleColumns = 33")
		check(L.BubbleRows == 34, "BubbleRows = 34")
	end

	local function resolvePopZone(zoneIdArg: any, fallbackZoneId: string): string
		if type(zoneIdArg) == "string" and ZoneDefs.Get(zoneIdArg) then
			return zoneIdArg
		end
		return fallbackZoneId
	end
	check(resolvePopZone(nil, "ClassicZone") == "ClassicZone", "pop sans zoneId → fallback")
	check(resolvePopZone("SummerZone", "ClassicZone") == "SummerZone", "pop Summer zoneId")
	check(ZoneDefs.List[1].Id == "ClassicZone" and ZoneDefs.List[2].Id == "SummerZone", "List Classic+Summer")

	local okFw, FwConfig = pcall(function()
		return require(Shared.SummerFireworksConfig)
	end)
	check(okFw == true, "SummerFireworksConfig chargeable")
	if okFw and FwConfig then
		local positions = FwConfig.GetLaunchPositions()
		check(#positions >= 3, "au moins 3 points de lancement")
		local boardO = summer.Origin
		local boardEx, boardEz = ZoneDefs.GetBubblePlayExtent("SummerZone")
		for _, pos in ipairs(positions) do
			local inBoardCore = math.abs(pos.X - boardO.X) < boardEx * 0.55
				and math.abs(pos.Z - boardO.Z) < boardEz * 0.55
			check(not inBoardCore, "lancement hors cœur BubbleBoard")
		end
	end

	if ok then
		print("[ZoneAccessTests] OK")
	end
	return ok
end

return ZoneAccessTests
