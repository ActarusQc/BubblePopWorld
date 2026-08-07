--!strict
-- Cas Bubble Transit : portail, menu, destinations, validation serveur, onboarding.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TravelLogic = require(Shared.TravelLogic)
local TravelConfig = require(Shared.TravelConfig)
local HubLayout = require(Shared.HubLayout)
local GameConfig = require(Shared.GameConfig)

local TravelLogicTests = {}

function TravelLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[TravelLogicTests] FAIL:", msg)
			ok = false
		end
	end

	-- Portail enregistré une seule fois
	local reg: { [string]: boolean } = {}
	check(TravelLogic.TryRegisterPortal(reg, "LobbyTransit") == true, "premier register portal OK")
	check(TravelLogic.TryRegisterPortal(reg, "LobbyTransit") == false, "second register portal rejeté")
	check(TravelLogic.TryRegisterPortal(reg, "SummerZoneTransit") == true, "autre portail distinct OK")

	-- Interaction ouvre le menu (post-vente, spatial/auto)
	check(
		TravelLogic.ShouldOpenFromInteraction("Spatial", 1, "Travel", false, false) == true,
		"spatial + vente faite → menu"
	)
	check(
		TravelLogic.ShouldOpenFromInteraction("Heartbeat", 5, nil, false, false) == true,
		"heartbeat niveau OK + sans onboarding → menu"
	)
	check(
		TravelLogic.ShouldOpenFromInteraction("ProximityPrompt", 0, "Pop", false, false) == true,
		"prompt manuel ouvre même pendant onboarding"
	)

	-- Liste destinations non vide
	local cardsL1 = TravelConfig.BuildDestinationCards(1, "Lobby")
	check(TravelLogic.ListNotEmpty(cardsL1), "liste destinations Lobby non vide")
	local hasSummer = false
	for _, c in ipairs(cardsL1) do
		if c.Id == "SummerZone" then
			hasSummer = true
			check(c.IsLocked == true, "Summer verrouillée visible niv1")
		end
	end
	check(hasSummer, "SummerZone présente dans la liste")

	-- Destination connue acceptée / inconnue refusée
	local accept = TravelLogic.EvaluateTravelRequest({
		DestinationId = "SummerZone",
		TransitId = "LobbyTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "Lobby",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(accept.Ok == true and accept.RequiresPivot == true, "destination connue acceptée")

	local unknown = TravelLogic.EvaluateTravelRequest({
		DestinationId = "MoonZone",
		TransitId = "LobbyTransit",
		PlayerLevel = 99,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "Lobby",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(unknown.Ok == false and unknown.Code == "DESTINATION_NOT_FOUND", "destination inconnue refusée")

	-- Verrouillée refusée
	local locked = TravelLogic.EvaluateTravelRequest({
		DestinationId = "SummerZone",
		TransitId = "LobbyTransit",
		PlayerLevel = 1,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "Lobby",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(locked.Ok == false and locked.Code == "DESTINATION_LOCKED", "destination verrouillée refusée")

	-- Déverrouillée → pivot
	local unlock = TravelLogic.EvaluateTravelRequest({
		DestinationId = "SummerZone",
		TransitId = "LobbyTransit",
		PlayerLevel = 5,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "Lobby",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(unlock.Ok == true and unlock.Code == "OK", "destination déverrouillée téléporte (pivot)")

	-- Marqueur absent
	local noMarker = TravelLogic.EvaluateTravelRequest({
		DestinationId = "SummerZone",
		TransitId = "LobbyTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "Lobby",
		MarkerFound = false,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(noMarker.Ok == false and noMarker.Code == "ARRIVAL_MARKER_MISSING", "marqueur absent erreur contrôlée")

	-- Sans HRP
	local noHrp = TravelLogic.EvaluateTravelRequest({
		DestinationId = "SummerZone",
		TransitId = "LobbyTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "Lobby",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = false,
	})
	check(noHrp.Ok == false and noHrp.Code == "CHARACTER_NOT_READY", "HRP absent géré")

	-- Respawn ≠ double register
	local reg2: { [string]: boolean } = {}
	TravelLogic.TryRegisterPortal(reg2, "path/A")
	check(TravelLogic.TryRegisterPortal(reg2, "path/A") == false, "respawn ne double pas le bind")

	-- Onboarding avant première vente
	check(
		TravelLogic.ShouldOpenFromInteraction("Spatial", 0, "Pop", false, false) == false,
		"auto-open bloqué avant première vente (Pop)"
	)
	check(
		TravelLogic.ShouldOpenFromInteraction("Touched", 0, "Sell", false, false) == false,
		"auto-open bloqué avant première vente (Sell)"
	)
	-- Après première vente
	check(
		TravelLogic.ShouldOpenFromInteraction("Spatial", 3, "Travel", false, false) == true,
		"après première vente spatial OK"
	)
	check(
		TravelLogic.ShouldOpenFromInteraction("Heartbeat", 1, "Upgrade", false, false) == true,
		"après vente + objective hors Pop/Sell OK"
	)

	-- Plateformes partagent la validation serveur
	check(TravelLogic.UsesSharedServerValidation("PC") == true, "PC même serveur")
	check(TravelLogic.UsesSharedServerValidation("Mobile") == true, "Mobile même serveur")
	check(TravelLogic.UsesSharedServerValidation("Xbox") == true, "Xbox même serveur")

	-- Sessions terminal (Summer ≠ hub)
	check(
		TravelLogic.IsTerminalSessionFresh(10, 20, 25) == true,
		"session fraîche dans TTL"
	)
	check(
		TravelLogic.IsTerminalSessionFresh(10, 50, 25) == false,
		"session expirée hors TTL"
	)
	check(
		TravelLogic.SessionTerminalMatches("SummerZoneTransit", "SummerZoneTransit") == true,
		"session terminal match"
	)
	check(
		TravelLogic.SessionTerminalMatches("SummerZoneTransit", "LobbyTransit") == false,
		"session refuse un autre terminal (pas l'ancre hub seule)"
	)
	check(
		TravelLogic.SessionTerminalMatches("LobbyTransit", "LobbyTransit") == true,
		"session hub ok"
	)
	check(
		TravelLogic.SessionTerminalMatches("LobbyTransit", "BubbleTransit_LobbyTransit") == true,
		"alias hub normalisé match session"
	)
	check(
		TravelLogic.SessionTerminalMatches("BubbleTransit_LobbyTransit", "LobbyTransit") == true,
		"session alias → client canonique"
	)
	check(
		TravelLogic.SessionTerminalMatches("LobbyTransit", "GhostTransit") == false,
		"alias inconnu → mismatch clair"
	)

	-- Session manquante / expirée (helpers purs)
	check(
		TravelLogic.IsTerminalSessionFresh(0, 30, 25) == false,
		"session expirée > TTL"
	)
	check(
		TravelLogic.IsTerminalSessionFresh(10, 20, 25) == true,
		"session active dans TTL"
	)

	-- TEST A : LobbyTransit + destination SummerZone => succès (arrivée Summer)
	local hubToSummerNear = TravelLogic.EvaluateTravelRequest({
		DestinationId = "SummerZone",
		TransitId = "LobbyTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "Lobby",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(hubToSummerNear.Ok == true, "TEST A LobbyTransit → SummerZone accepté")
	local summerPolicy = TravelLogic.ResolveArrivalMarkerPolicy(
		"SummerZone",
		"SummerZoneTravelArrival",
		true,
		true
	)
	check(summerPolicy.Kind == "NamedPadMarker", "TEST A Summer = NamedPadMarker")
	check(summerPolicy.LookupName == "SummerZoneTravelArrival", "TEST A Summer lookup")
	check(summerPolicy.AllowRecursiveFallback == true, "TEST A Summer fallback pads OK")

	-- TEST B : SummerZoneTransit + destination Lobby => succès + marker hub actuel
	local summerToLobby = TravelLogic.EvaluateTravelRequest({
		DestinationId = "Lobby",
		TransitId = "SummerZoneTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "SummerZone",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(summerToLobby.Ok == true, "TEST B SummerZone → Lobby accepté près du pad Summer")
	local lobbyPolicy = TravelLogic.ResolveArrivalMarkerPolicy(
		"Lobby",
		"LobbyTravelArrival",
		true,
		true
	)
	check(lobbyPolicy.Kind == "HubSpawnLocation", "TEST B Lobby = HubSpawnLocation")
	check(lobbyPolicy.LookupName == "HubSpawnLocation", "TEST B Lobby lookup HubSpawnLocation")
	check(
		lobbyPolicy.ExpectedPath == "Workspace.BubblePopWorld.CentralHub.HubSpawnLocation",
		"TEST B path canonique HubSpawnLocation"
	)
	check(lobbyPolicy.AllowRecursiveFallback == false, "TEST B pas de recherche récursive")
	check(lobbyPolicy.FailClosed == true, "TEST B fail closed")
	check(
		TravelLogic.AcceptsCanonicalHubSpawn(true, "HubSpawnLocation", "CentralHub") == true,
		"TEST B HubSpawnLocation sous CentralHub accepté"
	)
	check(
		TravelLogic.AcceptsCanonicalHubSpawn(true, "BubbleTransitInteractionAnchor", "CentralHub") == false,
		"TEST B ancre interaction refusée comme arrivée"
	)
	check(
		TravelLogic.IsForbiddenLobbyArrivalName("BubbleTransitInteractionAnchor") == true,
		"TEST B BubbleTransitInteractionAnchor interdit"
	)

	-- TEST C : SummerZoneTransit trop loin => rejet distance
	local summerFar = TravelLogic.EvaluateTravelRequest({
		DestinationId = "Lobby",
		TransitId = "SummerZoneTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = false,
		CurrentArea = "SummerZone",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(summerFar.Ok == false and summerFar.Code == "TOO_FAR_FROM_TERMINAL",
		"TEST C Summer loin du pad Summer → refusé")

	local hubFar = TravelLogic.EvaluateTravelRequest({
		DestinationId = "SummerZone",
		TransitId = "LobbyTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = false,
		CurrentArea = "Lobby",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(hubFar.Ok == false and hubFar.Code == "TOO_FAR_FROM_TERMINAL",
		"Hub loin → Summer refusé")

	-- TEST D : session terminal différente du terminal demandé => rejet
	check(
		TravelLogic.SessionTerminalMatches("SummerZoneTransit", "LobbyTransit") == false,
		"TEST D session Summer ≠ LobbyTransit"
	)
	local unknownTerminal = TravelLogic.EvaluateTravelRequest({
		DestinationId = "Lobby",
		TransitId = "GhostTransit",
		PlayerLevel = 10,
		TerminalFound = false,
		NearTerminal = false,
		CurrentArea = "SummerZone",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(unknownTerminal.Ok == false and unknownTerminal.Code == "TOO_FAR_FROM_TERMINAL",
		"TEST D terminal inconnu / mismatch refusé")

	-- TEST E : marker Lobby absent => erreur explicite, fail closed
	local noLobbyMarker = TravelLogic.EvaluateTravelRequest({
		DestinationId = "Lobby",
		TransitId = "SummerZoneTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "SummerZone",
		MarkerFound = false,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(
		noLobbyMarker.Ok == false and noLobbyMarker.Code == "ARRIVAL_MARKER_MISSING",
		"TEST E Lobby marker absent → ARRIVAL_MARKER_MISSING"
	)
	check(
		TravelLogic.AcceptsCanonicalHubSpawn(false, nil, nil) == false,
		"TEST E spawn manquant → refus"
	)
	check(
		TravelLogic.AcceptsCanonicalHubSpawn(true, "LobbyTravelArrival", "HubFunction") == false,
		"TEST E ancien LobbyTravelArrival sous HubFunction non canonique"
	)

	local alreadyThere = TravelLogic.EvaluateTravelRequest({
		DestinationId = "SummerZone",
		TransitId = "SummerZoneTransit",
		PlayerLevel = 10,
		TerminalFound = true,
		NearTerminal = true,
		CurrentArea = "SummerZone",
		MarkerFound = true,
		HasCharacter = true,
		HasHumanoidRootPart = true,
	})
	check(alreadyThere.Ok == false and alreadyThere.Code == "ALREADY_THERE",
		"HERE / destination actuelle → pas de téléport")

	-- Sans hub : Lobby garde l’ancien marqueur de pastille
	local legacyLobby = TravelLogic.ResolveArrivalMarkerPolicy(
		"Lobby",
		"LobbyTravelArrival",
		false,
		false
	)
	check(legacyLobby.Kind == "NamedPadMarker", "Lobby legacy = NamedPadMarker")
	check(legacyLobby.LookupName == "LobbyTravelArrival", "Lobby legacy lookup")

	-- Ancrage explicite : MaxActivation + placement layout fallback (pas FullHubBBox)
	if GameConfig.Hub.Enabled and GameConfig.Hub.ReplacesLobby then
		local maxDist = HubLayout.GetBubbleTransitMaxActivationDistance()
		check(maxDist == 5.5, "MaxActivationDistance 5.5")
		local t = HubLayout.GetBubbleTransitTriggerCFrame().Position
		check(t.Z < HubLayout.Center.Z, "fallback trigger côté portail arrière")
	end

	-- Menu déjà ouvert → pas de double ouverture
	check(
		TravelLogic.ShouldOpenFromInteraction("ProximityPrompt", 10, nil, true, false) == false,
		"menu déjà ouvert ignore nouvelle interaction"
	)

	if ok then
		print("[TravelLogicTests] OK")
	end
	return ok
end

return TravelLogicTests
