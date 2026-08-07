--!strict
-- Logique pure Bubble Transit (gates onboarding, validation voyage, anti-double bind).
-- Sans Instances : testable hors Studio ; le serveur garde l'autorité PivotTo.

local TravelConfig = require(script.Parent.TravelConfig)

local TravelLogic = {}

export type GateResult = {
	Allowed: boolean,
	FirstSaleCompleted: boolean,
	BlockedByOnboarding: boolean,
}

export type TravelDecision = {
	Ok: boolean,
	Code: string,
	Message: string,
	DestinationId: string?,
	RequiresPivot: boolean,
}

local MANUAL_SOURCES: { [string]: boolean } = {
	ProximityPrompt = true,
	ProximityPromptService = true,
}

function TravelLogic.IsManualInteractionSource(source: string): boolean
	return MANUAL_SOURCES[source] == true
end

function TravelLogic.ResolveTransitGate(soldAttr: any, objective: any): GateResult
	local firstSaleCompleted = type(soldAttr) == "number" and soldAttr > 0
	local blockedByOnboarding = objective == "Pop" or objective == "Sell"
	local allowed = firstSaleCompleted or not blockedByOnboarding
	return {
		Allowed = allowed,
		FirstSaleCompleted = firstSaleCompleted,
		BlockedByOnboarding = blockedByOnboarding,
	}
end

-- Auto-open (zone / spatial) bloqué avant première vente ; prompt manuel toujours permis.
function TravelLogic.ShouldOpenFromInteraction(
	source: string,
	soldAttr: any,
	objective: any,
	menuOpen: boolean,
	travelling: boolean
): boolean
	if menuOpen or travelling then
		return false
	end
	if TravelLogic.IsManualInteractionSource(source) then
		return true
	end
	return TravelLogic.ResolveTransitGate(soldAttr, objective).Allowed
end

-- Inscription unique d'un portail (id stable = FullName ou TransitId).
function TravelLogic.TryRegisterPortal(registered: { [string]: boolean }, portalKey: string): boolean
	if portalKey == "" then
		return false
	end
	if registered[portalKey] == true then
		return false
	end
	registered[portalKey] = true
	return true
end

function TravelLogic.ListNotEmpty(destinations: { any }): boolean
	return type(destinations) == "table" and #destinations > 0
end

function TravelLogic.EvaluateTravelRequest(args: {
	DestinationId: any,
	TransitId: any,
	PlayerLevel: number,
	TerminalFound: boolean,
	NearTerminal: boolean,
	CurrentArea: string,
	MarkerFound: boolean,
	HasCharacter: boolean,
	HasHumanoidRootPart: boolean,
}): TravelDecision
	if typeof(args.DestinationId) ~= "string" or args.DestinationId == "" then
		return {
			Ok = false,
			Code = "DESTINATION_NOT_FOUND",
			Message = "Travel is temporarily unavailable",
			DestinationId = nil,
			RequiresPivot = false,
		}
	end
	if typeof(args.TransitId) ~= "string" or args.TransitId == "" then
		return {
			Ok = false,
			Code = "TOO_FAR_FROM_TERMINAL",
			Message = "Move onto the Bubble Transit pad",
			DestinationId = nil,
			RequiresPivot = false,
		}
	end
	if not args.HasCharacter or not args.HasHumanoidRootPart then
		return {
			Ok = false,
			Code = "CHARACTER_NOT_READY",
			Message = "Travel is temporarily unavailable",
			DestinationId = args.DestinationId,
			RequiresPivot = false,
		}
	end

	local dest = TravelConfig.Get(args.DestinationId)
	if not dest or not dest.Enabled then
		return {
			Ok = false,
			Code = "DESTINATION_NOT_FOUND",
			Message = "Travel is temporarily unavailable",
			DestinationId = args.DestinationId,
			RequiresPivot = false,
		}
	end

	if not args.TerminalFound then
		return {
			Ok = false,
			Code = "TOO_FAR_FROM_TERMINAL",
			Message = "Move onto the Bubble Transit pad",
			DestinationId = dest.Id,
			RequiresPivot = false,
		}
	end
	if not args.NearTerminal then
		return {
			Ok = false,
			Code = "TOO_FAR_FROM_TERMINAL",
			Message = "Move onto the Bubble Transit pad",
			DestinationId = dest.Id,
			RequiresPivot = false,
		}
	end

	local area = args.CurrentArea
	if area == "GameRoom" or area == "ClassicZone" then
		area = "GameRoom"
	end
	if dest.AreaName == area then
		return {
			Ok = false,
			Code = "ALREADY_THERE",
			Message = "You are already here",
			DestinationId = dest.Id,
			RequiresPivot = false,
		}
	end

	if args.PlayerLevel < dest.RequiredLevel then
		return {
			Ok = false,
			Code = "DESTINATION_LOCKED",
			Message = string.format("Reach Level %d to unlock %s", dest.RequiredLevel, dest.DisplayName),
			DestinationId = dest.Id,
			RequiresPivot = false,
		}
	end

	if not args.MarkerFound then
		return {
			Ok = false,
			Code = "ARRIVAL_MARKER_MISSING",
			Message = "Travel is temporarily unavailable",
			DestinationId = dest.Id,
			RequiresPivot = false,
		}
	end

	return {
		Ok = true,
		Code = "OK",
		Message = "Travel complete",
		DestinationId = dest.Id,
		RequiresPivot = true,
	}
end

-- PC / Mobile / Xbox : même validation serveur, seules les sources d'UI différent.
function TravelLogic.UsesSharedServerValidation(_platform: string): boolean
	return true
end

-- Session menu : TTL + correspondance terminal demandé.
function TravelLogic.IsTerminalSessionFresh(openedAt: number, now: number, ttlSeconds: number): boolean
	if type(openedAt) ~= "number" or type(now) ~= "number" or type(ttlSeconds) ~= "number" then
		return false
	end
	return (now - openedAt) <= ttlSeconds and (now - openedAt) >= 0
end

function TravelLogic.SessionTerminalMatches(sessionTerminalId: string, requestTerminalId: string): boolean
	if type(sessionTerminalId) ~= "string" or type(requestTerminalId) ~= "string" then
		return false
	end
	if sessionTerminalId == "" or requestTerminalId == "" then
		return false
	end
	-- Égalité stricte d’abord (chemin chaud).
	if sessionTerminalId == requestTerminalId then
		return true
	end
	-- Alias reconnus → même id canonique (ex. BubbleTransit_LobbyTransit ↔ LobbyTransit).
	local sessionCanon = TravelConfig.NormalizeTransitId(sessionTerminalId)
	local requestCanon = TravelConfig.NormalizeTransitId(requestTerminalId)
	return sessionCanon ~= nil and sessionCanon == requestCanon
end

--------------------------------------------------------------------
-- Résolution point d’arrivée (policy pure — sans Instances Workspace)
--------------------------------------------------------------------

export type ArrivalMarkerPolicy = {
	Kind: string, -- "HubSpawnLocation" | "NamedPadMarker"
	LookupName: string,
	ExpectedPath: string,
	AllowRecursiveFallback: boolean,
	FailClosed: boolean,
}

-- Ancre d’interaction hub : jamais un point d’arrivée spawn.
function TravelLogic.IsForbiddenLobbyArrivalName(name: string): boolean
	return name == "BubbleTransitInteractionAnchor"
		or name == "PortalWalkSurface"
		or name == "PortalPad"
end

-- Destination Lobby + hub actif → HubSpawnLocation direct sous CentralHub.
-- SummerZone et autres → marqueur nommé sur la pastille (comportement inchangé).
function TravelLogic.ResolveArrivalMarkerPolicy(
	destinationId: string,
	destinationMarkerName: string,
	hubEnabled: boolean,
	replacesLobby: boolean
): ArrivalMarkerPolicy
	if destinationId == "Lobby" and hubEnabled == true and replacesLobby == true then
		return {
			Kind = "HubSpawnLocation",
			LookupName = "HubSpawnLocation",
			ExpectedPath = "Workspace.BubblePopWorld.CentralHub.HubSpawnLocation",
			AllowRecursiveFallback = false,
			FailClosed = true,
		}
	end
	return {
		Kind = "NamedPadMarker",
		LookupName = destinationMarkerName,
		ExpectedPath = "GameZones.TravelTerminals",
		AllowRecursiveFallback = true,
		FailClosed = false,
	}
end

-- Acceptation déterministe : enfant direct CentralHub nommé HubSpawnLocation uniquement.
function TravelLogic.AcceptsCanonicalHubSpawn(
	found: boolean,
	instanceName: string?,
	parentName: string?
): boolean
	if not found then
		return false
	end
	if type(instanceName) ~= "string" or type(parentName) ~= "string" then
		return false
	end
	if TravelLogic.IsForbiddenLobbyArrivalName(instanceName) then
		return false
	end
	return instanceName == "HubSpawnLocation" and parentName == "CentralHub"
end

return TravelLogic
