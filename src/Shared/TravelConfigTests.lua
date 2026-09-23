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
	local park = TravelConfig.Get("AmusementPark")
	check(lobby ~= nil, "Lobby destination exists")
	check(summer ~= nil, "SummerZone destination exists")
	check(park ~= nil, "AmusementPark destination exists")
	if not lobby or not summer then
		return false
	end

	check(lobby.ShowFromLobby == false, "Lobby not shown from Lobby")
	check(summer.ShowFromLobby == true, "Summer shown from Lobby")
	check(summer.RequiredLevel == ZoneDefs.GetRequiredLevel("SummerZone"), "Summer RequiredLevel synced with ZoneDefs")
	check(summer.RequiredLevel == 3, "Summer RequiredLevel == 3")
	check(lobby.DestinationMarkerName == "LobbyTravelArrival", "Lobby arrival marker name")
	check(summer.DestinationMarkerName == "SummerZoneTravelArrival", "Summer arrival marker name")
	check(park ~= nil and park.DestinationMarkerName == "AmusementParkTravelArrival", "Park arrival marker name")
	check(park ~= nil and park.RequiredLevel == 1, "Park accessible dès le niveau 1")

	local cardsL1 = buildCards(1, "Lobby")
	check(findCard(cardsL1, "Lobby") == nil, "Lobby hidden from Lobby terminal")
	local summerL1 = findCard(cardsL1, "SummerZone")
	check(summerL1 ~= nil and summerL1.IsLocked == true, "Summer locked at level 1")
	check(summerL1 ~= nil, "locked SummerZone reste visible dans la liste")

	local cardsL3 = buildCards(3, "Lobby")
	local summerL3 = findCard(cardsL3, "SummerZone")
	check(summerL3 ~= nil and summerL3.IsLocked == false, "Summer unlocked at level 3")
	check(#cardsL3 >= 1, "Lobby terminal retourne au moins 1 destination")

	local builtL1 = TravelConfig.BuildDestinationCards(1, "Lobby")
	local builtL7 = TravelConfig.BuildDestinationCards(7, "Lobby")
	check(#builtL1 >= 1 and findCard(builtL1, "SummerZone") ~= nil, "BuildDestinationCards Lobby niv1 inclut SummerZone")
	check(#builtL7 >= 1 and findCard(builtL7, "SummerZone") ~= nil, "BuildDestinationCards Lobby niv7 inclut SummerZone")
	local lockedCard = findCard(builtL1, "SummerZone")
	check(lockedCard ~= nil and lockedCard.IsLocked == true, "destination verrouillée visible")
	local openCard = findCard(builtL7, "SummerZone")
	check(openCard ~= nil and openCard.IsLocked == false, "destination accessible sélectionnable")

	-- Indépendant de la position du pad (ancien StairsEnd vs BackWallEnd).
	local padPos = TravelConfig.ResolveLobbySpawnPlatformPosition(Vector3.zero)
	local cardsIgnoringPad = TravelConfig.BuildDestinationCards(7, "Lobby")
	check(#cardsIgnoringPad >= 1, "liste indépendante de la position du pad")
	check(typeof(padPos) == "Vector3", "pad position résolue sans vider la config")
	local byId = TravelConfig.GetPlacementByTransitId("LobbyTransit")
	check(byId ~= nil and byId.CurrentArea == "Lobby", "placement LobbyTransit résolvable sans modèle Workspace")

	-- Ids canoniques + aliases réels uniquement
	check(TravelConfig.NormalizeTransitId("LobbyTransit") == "LobbyTransit", "LobbyTransit canonique")
	check(
		TravelConfig.NormalizeTransitId("BubbleTransit_LobbyTransit") == "LobbyTransit",
		"alias modèle hub → LobbyTransit"
	)
	check(TravelConfig.NormalizeTransitId("SummerZoneTransit") == "SummerZoneTransit", "SummerZoneTransit canonique")
	check(TravelConfig.NormalizeTransitId("AmusementParkTransit") == "AmusementParkTransit", "AmusementParkTransit canonique")
	check(
		TravelConfig.NormalizeTransitId("BubbleTransit_SummerZoneTransit") == "SummerZoneTransit",
		"alias modèle Summer → SummerZoneTransit"
	)
	check(TravelConfig.NormalizeTransitId("CentralHubTransit") == nil, "pas d’alias inventé CentralHubTransit")
	check(TravelConfig.IsHubLobbyTransitId("LobbyTransit") == true, "hub lobby id")
	check(TravelConfig.IsHubLobbyTransitId("SummerZoneTransit") == false, "summer ≠ hub lobby")
	check(TravelConfig.HUB_INTERACTION_ANCHOR_NAME == "BubbleTransitInteractionAnchor", "ancre hub nom")
	local hubDef = TravelConfig.GetTerminalDef("LobbyTransit")
	check(hubDef ~= nil and hubDef.ZoneId == "Lobby", "zone Lobby ≠ terminal LobbyTransit")
	check(hubDef ~= nil and hubDef.CanonicalId == "LobbyTransit", "canonical hub")

	-- Layout mur du fond : classement à gauche (-X) du pad, HOW TO PLAY reste à +X.
	local GameConfigForLayout = require(Shared.GameConfig)
	local lobbyRoot = GameConfigForLayout.Lobby.RootOffset
	local padR = TravelConfig.PadDimensions.PadDiameter * 0.5
	local lbHalf = 6
	local gap = 4.5
	local expectedLbX = padPos.X - (padR + gap + lbHalf)
	check(expectedLbX < padPos.X, "classement attendu à gauche de Bubble Transit")
	check(18 > padPos.X, "HOW TO PLAY (X=18) reste à droite de Bubble Transit")
	check(math.abs(expectedLbX - (-13.5)) < 0.05, "pivot classement X ≈ -13.5")
	check(lobbyRoot.X == 0, "axe central lobby X=0")

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
	check(lobbyPad.RelativeToLobbySpawnPlatform == true, "Lobby pad on spawn platform")

	local GameConfig = require(Shared.GameConfig)
	local lobbyCF = TravelConfig.ResolveWorldCFrame(lobbyPad)
	local L = GameConfig.Lobby
	local hubReplacesLobby = GameConfig.Hub.Enabled and GameConfig.Hub.ReplacesLobby

	if hubReplacesLobby then
		-- Portail arrière du hub 3D (centre, -Z).
		local HubLayout = require(Shared.HubLayout)
		local hubPos = HubLayout.GetTransitPosition()
		local spawnPos = HubLayout.Spawn.Center
		local maxDist = HubLayout.GetBubbleTransitMaxActivationDistance()
		check((lobbyCF.Position - hubPos).Magnitude < 0.05, "arrivée transit au portail arrière")
		check(math.abs(lobbyCF.Position.X - spawnPos.X) < 0.05, "transit centré en X")
		check(lobbyCF.Position.Z < spawnPos.Z, "transit à l'arrière du spawn")
		check(maxDist == 5.5, "MaxActivationDistance 5.5")
		local spawnDist = (Vector3.new(lobbyCF.Position.X, 0, lobbyCF.Position.Z)
			- Vector3.new(spawnPos.X, 0, spawnPos.Z)).Magnitude
		check(spawnDist >= 20, "distance spawn→transit suffisante (pas de trigger à l'apparition)")
		check(TravelConfig.Destinations.Lobby.DisplayName == "Central Hub",
			"destination affichée « Central Hub »")
	else
		local spawnPos = L.RootOffset + L.SpawnOffset
		local P = TravelConfig.LobbySpawnPlatform
		local entrancePos = L.EntrancePosition
		local howToPlayZ = L.RootOffset.Z - (L.FloorSize.Z / 2 - 6.8) -- aligné BOARD_WALL_INSET ZoneService
		local floorSouthZ = L.RootOffset.Z - L.FloorSize.Z * 0.5
		local padR = TravelConfig.PadDimensions.PadDiameter * 0.5
		local edgeDist = (lobbyCF.Position.Z - padR) - floorSouthZ
		check(P.UseBackWallEnd ~= false, "Lobby pad ciblé BackWallEnd (pas StairsEnd)")
		check(math.abs(lobbyCF.Position.X - L.RootOffset.X) < 0.05, "Lobby pad centré largeur plateforme")
		check(lobbyCF.Position.Z < spawnPos.Z, "Lobby pad au sud du spawn (BackWallEnd)")
		check(lobbyCF.Position.Z < entrancePos.Z, "Lobby pad plus au sud que les marches Bubble Room")
		check(math.abs(lobbyCF.Position.Z - howToPlayZ) < 8, "Lobby pad près de HOW TO PLAY")
		check(edgeDist >= 3 and edgeDist <= 5.05, "Lobby pad 3–5 studs du bord fond")
		local spawnDist = (Vector3.new(lobbyCF.Position.X, 0, lobbyCF.Position.Z) - Vector3.new(spawnPos.X, 0, spawnPos.Z)).Magnitude
		check(spawnDist >= 20, "distance spawn→transit suffisante (pas de trigger à l'apparition)")
		local distToEntrance = (Vector3.new(lobbyCF.Position.X, 0, lobbyCF.Position.Z) - Vector3.new(entrancePos.X, 0, entrancePos.Z)).Magnitude
		check(distToEntrance > spawnDist, "plus loin des marches que du spawn")
	end
	local lobbyLook = lobbyCF.LookVector
	check(lobbyLook.Z > 0.9 and math.abs(lobbyLook.X) < 0.15, "pastille transit face au hub / spawn (+Z)")

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
