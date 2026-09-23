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
	check(ZoneDefs.GetRequiredLevel("SummerZone") == 3, "Summer RequiredLevel")
	check(ZoneDefs.GetRewardMultiplier("SummerZone") == 1, "Summer RewardMultiplier == 1")
	check(ZoneDefs.GetRewardMultiplier("ClassicZone") == 1, "Classic RewardMultiplier == 1")

	check(ZoneDefs.CanLevelEnter(2, "SummerZone") == false, "level 2 blocked")
	check(ZoneDefs.CanLevelEnter(3, "SummerZone") == true, "level 3 allowed (>=)")
	check(ZoneDefs.CanLevelEnter(6, "SummerZone") == true, "level 6 allowed")
	check(ZoneDefs.CanLevelEnter(1, "ClassicZone") == true, "classic level 1 allowed")

	check(ZoneDefs.GetAccessGroupName(1) == "ZoneAccess_1", "access group level 1")
	check(ZoneDefs.GetAccessGroupName(2) == "ZoneAccess_1", "access group level 2")
	check(ZoneDefs.GetAccessGroupName(3) == "ZoneAccess_3", "access group level 3")
	check(ZoneDefs.GetAccessGroupName(99) == "ZoneAccess_3", "access group level 99")

	local layout = ZoneDefs.GetSummerBridgeLayout()
	local L = ZoneDefs.SummerLayout
	check(layout.ZoneOrigin == ZoneDefs.SummerZone.ZoneOrigin, "bridge ZoneOrigin")
	check(layout.BoardOrigin == ZoneDefs.SummerZone.Origin, "bridge BoardOrigin")
	check(layout.GateX > layout.SummerEdgeX, "gate past summer edge")
	check(layout.ArchX < layout.SummerEdgeX, "arch before summer edge")
	check(layout.MidX > ZoneDefs.ClassicZone.Origin.X, "bridge mid à droite de classic")
	check(math.abs(layout.SummerEdgeX - 168) < 1e-6, "bord entrée Summer X = 168")
	check(math.abs(layout.ArchZ) < 1e-6, "entrée Summer centrée Z = 0")
	check(layout.ZoneWidth == 132 and layout.ZoneDepth == 180, "layout Summer largeur 132 / profondeur 180")
	check(layout.ZoneOrigin == Vector3.new(258, 6, 0), "centre Summer = (258, 6, 0)")

	local summerReq = ZoneDefs.GetRequiredLevel("SummerZone")
	check((1 < summerReq) == true, "ZoneAccess_1 collides with SummerGate")
	check((3 < summerReq) == false, "ZoneAccess_3 does not collide with SummerGate")

	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local right = ZoneDefs.CLASSIC_RIGHT
	local delta = summer.ZoneOrigin - classic.Origin
	check(delta:Dot(right) > 0, "Summer à droite de Classic")
	check(classic.Origin == GameConfig.Grid.Origin, "Classic Origin = Grid.Origin")

	-- Classic board inchangé
	check(classic.SizeX == GameConfig.Grid.SizeX and classic.SizeZ == GameConfig.Grid.SizeZ, "Classic 40x40")

	-- Summer compacte : profondeur X inchangée (180) ; largeur Z élargie pour +4 rangées.
	check(L.ZoneDepth == 180, "profondeur Summer X = 180")
	check(L.ZoneWidth == 132, "largeur Summer Z = 132")
	check(L.ZoneDepth == GameConfig.Grid.SizeX * GameConfig.Grid.Spacing * 0.75, "profondeur réduite de 25 %")
	check(summer.SizeX == L.BubbleColumns and summer.SizeZ == L.BubbleRows, "Size = Rows/Cols")
	check(summer.SizeX < classic.SizeX, "Summer board plus petit (colonnes)")
	check(summer.SizeZ < classic.SizeZ, "Summer board plus petit (rangées)")
	check(L.BubbleRows == 16, "BubbleRows = 12 + 4")
	check(L.BubbleColumns == 23, "BubbleColumns inchangé (longueur)")

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
		check(L.BubbleColumns == 23, "BubbleColumns = 23")
		check(L.BubbleRows == 16, "BubbleRows = 16")
		-- BubbleBoardWidth = emprise X (longueur) ; BubbleBoardDepth = emprise Z (largeur façade).
		check(math.abs(L.BubbleBoardWidth - 141.4) < 0.05, "BubbleBoard longueur X = 141.4 inchangée")
		check(math.abs(L.BubbleBoardDepth - 99.4) < 0.05, "BubbleBoard largeur Z = 99.4 (+4 rangées)")
		check(math.abs(summer.Origin.Z - sb.Origin.Z) < 1e-6, "BubbleBoard centré sur Z")
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
	check(ZoneDefs.List[3].Id == "AmusementPark", "List AmusementPark")
	check(ZoneDefs.GetRequiredLevel("AmusementPark") == 1, "Parc accessible sans verrou de niveau")
	local highRow = nil
	for z = 1, ZoneDefs.AmusementPark.SizeZ do
		if ZoneDefs.GetAmusementParkRegionName(z) == "High" then
			highRow = z
			break
		end
	end
	local parkGround = ZoneDefs.CellToWorld(1, 1, "AmusementPark")
	local parkHigh = ZoneDefs.CellToWorld(1, highRow or 1, "AmusementPark")
	check(highRow ~= nil, "rangée High présente dans la grille du parc")
	check(parkHigh.Y > parkGround.Y + 15, "Bulles du parc réparties sur plusieurs étages")

	local flat = CFrame.new()
	local wideCols, wideRows = ZoneDefs.GetAmusementParkRegionCapacity(flat, Vector3.new(46, 0.4, 30), 16, 5)
	local thinCols, _thinRows = ZoneDefs.GetAmusementParkRegionCapacity(flat, Vector3.new(12, 0.4, 30), 16, 5)
	-- Région redimensionnée avec Z mince : après rotation 90° (Y horizontal), le plan se remplit.
	local tipped = CFrame.Angles(math.rad(90), 0, 0)
	local tippedCols, tippedRows = ZoneDefs.GetAmusementParkRegionCapacity(tipped, Vector3.new(46, 30, 0.4), 16, 5)
	check(wideCols >= thinCols, "région plus large → plus de colonnes")
	check(thinCols < 16, "région étroite n'active pas les 16 colonnes")
	check(wideRows >= 2, "High standard a plusieurs rangées")
	check(tippedRows >= 2, "axes horizontaux détectés après redimensionnement")
	check(tippedCols >= 2, "plusieurs colonnes sur le plan basculé")
	local spacing = GameConfig.Grid.Spacing
	local pad = math.max(GameConfig.Grid.BubbleSize.X, GameConfig.Grid.BubbleSize.Z)
	check((thinCols - 1) * spacing <= 12 - pad + 1e-6, "pas de compression colonnes")
	check(thinCols >= 1, "High étroit garde au moins une colonne jouable")

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
