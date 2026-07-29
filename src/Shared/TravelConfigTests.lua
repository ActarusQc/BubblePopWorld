--!strict
-- Validations Bubble Transit (pastilles ouvertes, pont Summer, niveau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TravelConfig = require(Shared.TravelConfig)
local ZoneDefs = require(Shared.ZoneDefs)

local TravelConfigTests = {}

local function buildCards(playerLevel: number, currentArea: string): { any }
	local cards = {}
	for _, def in ipairs(TravelConfig.GetSortedDestinations()) do
		if not def.Enabled then
			continue
		end
		if currentArea == "Lobby" and not def.ShowFromLobby then
			continue
		end
		table.insert(cards, {
			Id = def.Id,
			RequiredLevel = def.RequiredLevel,
			IsCurrent = def.AreaName == currentArea,
			IsLocked = playerLevel < def.RequiredLevel,
			ShowFromLobby = def.ShowFromLobby,
		})
	end
	return cards
end

local function findCard(cards: { any }, id: string): any?
	for _, c in ipairs(cards) do
		if c.Id == id then
			return c
		end
	end
	return nil
end

function TravelConfigTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[TravelConfigTests] FAIL:", msg)
			ok = false
		end
	end

	local lobby = TravelConfig.Get("Lobby")
	local summer = TravelConfig.Get("SummerZone")
	check(lobby ~= nil, "Lobby destination exists")
	check(summer ~= nil, "SummerZone destination exists")
	if not lobby or not summer then
		return false
	end

	check(lobby.ShowFromLobby == false, "Lobby not shown from Lobby")
	check(summer.ShowFromLobby == true, "Summer shown from Lobby")
	check(summer.RequiredLevel == ZoneDefs.GetRequiredLevel("SummerZone"), "Summer RequiredLevel synced with ZoneDefs")
	check(summer.RequiredLevel == 5, "Summer RequiredLevel == 5")
	check(lobby.DestinationMarkerName == "LobbyTravelArrival", "Lobby arrival marker name")
	check(summer.DestinationMarkerName == "SummerZoneTravelArrival", "Summer arrival marker name")

	local cardsL1 = buildCards(1, "Lobby")
	check(findCard(cardsL1, "Lobby") == nil, "Lobby hidden from Lobby terminal")
	local summerL1 = findCard(cardsL1, "SummerZone")
	check(summerL1 ~= nil and summerL1.IsLocked == true, "Summer locked at level 1")

	local cardsL5 = buildCards(5, "Lobby")
	local summerL5 = findCard(cardsL5, "SummerZone")
	check(summerL5 ~= nil and summerL5.IsLocked == false, "Summer unlocked at level 5")

	local cardsFromSummer = buildCards(5, "SummerZone")
	check(findCard(cardsFromSummer, "Lobby") ~= nil, "Lobby available from Summer")
	local summerHere = findCard(cardsFromSummer, "SummerZone")
	check(summerHere ~= nil and summerHere.IsCurrent == true, "Summer marked current")

	local lobbyPad = TravelConfig.CapsulePlacements.Lobby
	local summerPad = TravelConfig.CapsulePlacements.SummerZone
	check(lobbyPad ~= nil and summerPad ~= nil, "pad placements present")
	check(lobbyPad.ArrivalMarkerName == "LobbyTravelArrival", "Lobby arrival on same pad")
	check(summerPad.ArrivalMarkerName == "SummerZoneTravelArrival", "Summer arrival on same pad")
	check(summerPad.RelativeToSummerBridge == true, "Summer pad on bridge")

	local bridgeCF = TravelConfig.ResolveWorldCFrame(summerPad)
	local layout = ZoneDefs.GetSummerBridgeLayout()
	check(math.abs(bridgeCF.Position.X - layout.MidX) < 0.05, "Summer pad at MidX")
	check(math.abs(bridgeCF.Position.Z - layout.ArchZ) < 0.05, "Summer pad at ArchZ")
	check(math.abs(bridgeCF.Position.Z) < 0.05, "Summer pad centré sur Z = 0")
	check(math.abs(layout.ZoneOrigin.Z - layout.ArchZ) < 0.05, "arche centrée sur la zone")
	check(math.abs(layout.SummerEdgeX - 168) < 0.05, "pont rejoint le bord Summer conservé")
	check(bridgeCF.Position.X < layout.GateX, "Summer pad before Gate")
	local look = bridgeCF.LookVector
	check(look.X > 0.9 and math.abs(look.Z) < 0.15, "Summer pad faces +X")

	local dims = TravelConfig.PadDimensions
	check(dims.PadDiameter == 6, "PadDiameter 6")
	check(dims.PadHeight == 0.4, "PadHeight 0.4")
	check(dims.TriggerSize == Vector3.new(5, 6, 5), "TransitTrigger 5x6x5")
	check(TravelConfig.ArrivalSuppressSeconds == 2.5, "arrival suppress 2.5s")

	check(TravelConfig.TravelSoundId == "" or string.find(TravelConfig.TravelSoundId, "rbxasset") ~= nil, "TravelSoundId empty or valid")

	if ok then
		print("[TravelConfigTests] OK")
	end
	return ok
end

return TravelConfigTests
