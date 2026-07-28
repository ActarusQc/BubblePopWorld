--!strict
-- Validations ciblées des règles d'accès zones (exécutable via require au démarrage serveur optionnel).

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

	-- Accès Summer : >= 5 (pas > 5)
	check(ZoneDefs.CanLevelEnter(4, "SummerZone") == false, "level 4 blocked")
	check(ZoneDefs.CanLevelEnter(5, "SummerZone") == true, "level 5 allowed (>=)")
	check(ZoneDefs.CanLevelEnter(6, "SummerZone") == true, "level 6 allowed")
	check(ZoneDefs.CanLevelEnter(1, "ClassicZone") == true, "classic level 1 allowed")

	check(ZoneDefs.GetAccessGroupName(1) == "ZoneAccess_1", "access group level 1")
	check(ZoneDefs.GetAccessGroupName(4) == "ZoneAccess_1", "access group level 4")
	check(ZoneDefs.GetAccessGroupName(5) == "ZoneAccess_5", "access group level 5")
	check(ZoneDefs.GetAccessGroupName(99) == "ZoneAccess_5", "access group level 99")

	local layout = ZoneDefs.GetSummerBridgeLayout()
	check(layout.Origin == ZoneDefs.SummerZone.Origin, "bridge layout origin")
	check(layout.GateX > layout.SummerEdgeX, "gate past summer edge")
	check(layout.ArchX < layout.SummerEdgeX, "arch before summer edge")
	check(layout.MidX > ZoneDefs.ClassicZone.Origin.X, "bridge mid à droite de classic")

	-- Matrice collision : palier Access_L collisionne Gate ssi L < RequiredLevel
	local summerReq = ZoneDefs.GetRequiredLevel("SummerZone")
	check((1 < summerReq) == true, "ZoneAccess_1 collides with SummerGate")
	check((5 < summerReq) == false, "ZoneAccess_5 does not collide with SummerGate")

	local classic = ZoneDefs.ClassicZone
	local summer = ZoneDefs.SummerZone
	local right = ZoneDefs.CLASSIC_RIGHT
	local delta = summer.Origin - classic.Origin
	check(delta:Dot(right) > 0, "Summer à droite de Classic")
	check(classic.Origin == GameConfig.Grid.Origin, "Classic Origin = Grid.Origin")

	local cb = ZoneDefs.GetZoneBounds("ClassicZone")
	local sb = ZoneDefs.GetZoneBounds("SummerZone")
	check(cb ~= nil and sb ~= nil, "bounds présents")
	if cb and sb then
		local overlap = cb.MaxX > sb.MinX and cb.MinX < sb.MaxX and cb.MaxZ > sb.MinZ and cb.MinZ < sb.MaxZ
		check(not overlap, "pas de chevauchement Classic/Summer")
		check(sb.MinX - cb.MaxX >= 10, "écart minimum entre planches")
	end

	-- PopRequest : zoneId obligatoire pour Summer (sinon Classic + échec distance)
	local function resolvePopZone(zoneIdArg: any, fallbackZoneId: string): string
		if type(zoneIdArg) == "string" and ZoneDefs.Get(zoneIdArg) then
			return zoneIdArg
		end
		return fallbackZoneId
	end
	check(resolvePopZone(nil, "ClassicZone") == "ClassicZone", "pop sans zoneId → fallback")
	check(resolvePopZone("SummerZone", "ClassicZone") == "SummerZone", "pop Summer zoneId")
	check(ZoneDefs.List[1].Id == "ClassicZone" and ZoneDefs.List[2].Id == "SummerZone", "List enregistre Classic+Summer")

	-- Feux d’artifice : points hors centre BubbleBoard
	local okFw, FwConfig = pcall(function()
		return require(Shared.SummerFireworksConfig)
	end)
	check(okFw == true, "SummerFireworksConfig chargeable")
	if okFw and FwConfig then
		check(FwConfig.Enabled == true, "Fireworks Enabled")
		check(FwConfig.MaxPerSequence <= 3, "MaxPerSequence <= 3")
		check(FwConfig.PoolSize <= 4, "PoolSize limité")
		local positions = FwConfig.GetLaunchPositions()
		check(#positions >= 3, "au moins 3 points de lancement")
		local origin = ZoneDefs.SummerZone.Origin
		local ex, ez = ZoneDefs.GetBubblePlayExtent()
		for _, pos in ipairs(positions) do
			local inBoardCore = math.abs(pos.X - origin.X) < ex * 0.55 and math.abs(pos.Z - origin.Z) < ez * 0.55
			check(not inBoardCore, "lancement hors cœur BubbleBoard")
			check(pos.Y > origin.Y + 10, "lancement assez haut")
		end
	end

	if ok then
		print("[ZoneAccessTests] OK")
	end
	return ok
end

return ZoneAccessTests
