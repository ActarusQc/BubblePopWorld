--!strict
-- Autorité serveur Bubble Transit : liste destinations + déplacement sécurisé.
-- Distance mesurée contre le terminal de session (celui qui a ouvert le menu),
-- jamais contre l’ancre hub seul si le joueur part d’une autre zone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local TravelConfig = require(Shared.TravelConfig)
local TravelLogic = require(Shared.TravelLogic)
local ZoneDefs = require(Shared.ZoneDefs)
local GameConfig = require(Shared.GameConfig)
local HubLayout = require(Shared.HubLayout)

local DataService = require(script.Parent.DataService)
local ZoneService = require(script.Parent.ZoneService)
local BubbleTransitBuilder = require(script.Parent.BubbleTransitBuilder)
local CentralHubBuilder = require(script.Parent.CentralHubBuilder)

local TravelService = {}

-- Session d’ouverture menu : terminal validé serveur (TTL court).
local SESSION_TTL_SECONDS = 25

type TerminalSession = {
	terminalId: string, -- toujours canonique
	openedAt: number,
}

local activeTerminalSessions: { [Player]: TerminalSession } = {}

local function withAnalytics(fn: (any) -> ())
	pcall(function()
		local GameAnalyticsService = require(script.Parent.GameAnalyticsService)
		fn(GameAnalyticsService)
	end)
end

export type DestinationCard = {
	Id: string,
	DisplayName: string,
	Description: string,
	RequiredLevel: number,
	IsCurrent: boolean,
	IsLocked: boolean,
	IsLobby: boolean,
	SortOrder: number,
}

local traveling: { [Player]: boolean } = {}
local lastTravelAt: { [Player]: number } = {}
local travelSuppressedUntil: { [Player]: number } = {}

local function debugLog(...: any)
	if not TravelConfig.DEBUG_TRAVEL then
		return
	end
	print("[TravelDebug]", ...)
end

local function sessionAge(session: TerminalSession?): number
	if not session then
		return -1
	end
	return os.clock() - session.openedAt
end

local function logSession(
	action: string,
	player: Player,
	terminalId: string?,
	reason: string?,
	age: number?
)
	print(string.format(
		"[BubbleTransit SESSION]\nAction=%s\nPlayer=%s\nTerminalId=%s\nAge=%.3f\nReason=%s",
		action,
		player.Name,
		terminalId or "nil",
		age or -1,
		reason or ""
	))
end

local function clearSession(player: Player, reason: string?)
	local existing = activeTerminalSessions[player]
	if existing then
		logSession("DELETE", player, existing.terminalId, reason or "clear", sessionAge(existing))
	end
	activeTerminalSessions[player] = nil
end

local function normalizeArea(area: string): string
	if area == "GameRoom" or area == "ClassicZone" then
		return "GameRoom"
	end
	return area
end

function TravelService.GetDestinationsForPlayer(player: Player, currentArea: string): { DestinationCard }
	local level = DataService.GetPlayerLevel(player)
	local area = normalizeArea(currentArea)
	return TravelConfig.BuildDestinationCards(level, area) :: { DestinationCard }
end

local function resolveAreaForTransit(transitId: string, terminal: Model?): string
	if terminal then
		local areaAttr = terminal:GetAttribute("CurrentArea")
		if type(areaAttr) == "string" and areaAttr ~= "" then
			return normalizeArea(areaAttr)
		end
	end
	local def = TravelConfig.GetTerminalDef(transitId)
	if def then
		return normalizeArea(def.ZoneId)
	end
	local placement = TravelConfig.GetPlacementByTransitId(transitId)
	if placement and type(placement.CurrentArea) == "string" then
		return normalizeArea(placement.CurrentArea)
	end
	return "Lobby"
end

local function sendList(player: Player, transitId: string, currentArea: string)
	local area = normalizeArea(currentArea)
	local cards = TravelService.GetDestinationsForPlayer(player, area)
	local destinations = table.create(#cards)
	for i, card in ipairs(cards) do
		destinations[i] = {
			Id = card.Id,
			DisplayName = card.DisplayName,
			Description = card.Description,
			RequiredLevel = card.RequiredLevel,
			IsCurrent = card.IsCurrent == true,
			IsLocked = card.IsLocked == true,
			IsLobby = card.IsLobby == true,
			SortOrder = card.SortOrder,
		}
	end
	Remotes.Event("DestinationListUpdated"):FireClient(player, {
		TransitId = transitId,
		CurrentArea = area,
		PlayerLevel = DataService.GetPlayerLevel(player),
		Destinations = destinations,
	})

	withAnalytics(function(GAS)
		GAS.OnOpenedBubbleTransit(player)
		for _, card in ipairs(cards) do
			if card.Id == "SummerZone" and card.IsLocked == true then
				GAS.OnSawSummerZoneRequirement(player)
				break
			end
		end
	end)
end

local function fireResult(player: Player, ok: boolean, code: string, message: string, extra: { [string]: any }?)
	local payload: { [string]: any } = {
		Ok = ok,
		Code = code,
		Message = message,
	}
	if extra then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	Remotes.Event("TravelResult"):FireClient(player, payload)
end

local function resolveAreaFromPosition(pos: Vector3): string
	if pos.Z < GameConfig.World.AreaSplitZ then
		return "Lobby"
	end
	local summerBounds = ZoneDefs.GetZoneBounds("SummerZone")
	if summerBounds then
		local margin = 12
		if pos.X >= summerBounds.MinX - margin
			and pos.X <= summerBounds.MaxX + margin
			and pos.Z >= summerBounds.MinZ - margin
			and pos.Z <= summerBounds.MaxZ + margin then
			return "SummerZone"
		end
	end
	return "GameRoom"
end

local function pointInPart(point: Vector3, part: BasePart, inflate: number?): boolean
	local pad = inflate or 0
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5 + Vector3.new(pad, pad, pad)
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function getPlayerHrp(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- Position de validation = point réel d’interaction (Attachment du prompt si présent).
local function getTriggerValidationPosition(trigger: BasePart): Vector3
	local att = trigger:FindFirstChild("PromptAttachment")
	if att and att:IsA("Attachment") then
		return att.WorldPosition
	end
	local prompt = trigger:FindFirstChild("BubbleTransitPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		local parent = prompt.Parent
		if parent and parent:IsA("Attachment") then
			return parent.WorldPosition
		end
	end
	return trigger.Position
end

local function resolveTriggerForTerminalId(transitId: string, terminal: Model?): (BasePart?, string)
	if TravelConfig.IsHubLobbyTransitId(transitId) then
		local hub = BubbleTransitBuilder.GetInteractionAnchorForTransitId(transitId)
		if hub then
			return hub, BubbleTransitBuilder.GetTriggerPath(hub)
		end
	end
	if terminal then
		local t = BubbleTransitBuilder.GetTrigger(terminal)
		if t then
			return t, BubbleTransitBuilder.GetTriggerPath(t)
		end
	end
	local viaId = BubbleTransitBuilder.GetInteractionAnchorForTransitId(transitId)
	if viaId then
		return viaId, BubbleTransitBuilder.GetTriggerPath(viaId)
	end
	return nil, "nil"
end

local function playerNearTrigger(
	player: Player,
	transitId: string,
	trigger: BasePart
): (boolean, number, number)
	local hrp = getPlayerHrp(player)
	if not hrp then
		return false, -1, TravelConfig.TerminalProximityStuds
	end
	local pos = getTriggerValidationPosition(trigger)
	local dist = (hrp.Position - pos).Magnitude
	local maxHalf = math.max(trigger.Size.X, trigger.Size.Y, trigger.Size.Z) * 0.5
	-- Hub / ancre compacte : aligné sur MaxActivationDistance du ProximityPrompt (+ buffer léger).
	if TravelConfig.IsHubLobbyTransitId(transitId) or maxHalf <= 3 then
		local activation = HubLayout.GetBubbleTransitMaxActivationDistance()
		local limit = math.max(TravelConfig.TerminalProximityStuds + 1.5, activation + 1)
		return dist <= limit, dist, limit
	end
	local inside = pointInPart(hrp.Position, trigger, 1.5)
	local limit = math.max(TravelConfig.TerminalProximityStuds, maxHalf + 1.5)
	return inside, dist, limit
end

local function playerNearTerminal(
	player: Player,
	terminal: Model?,
	transitId: string
): (boolean, number?, number?, BasePart?, string)
	local trigger, path = resolveTriggerForTerminalId(transitId, terminal)
	if not trigger then
		return false, nil, TravelConfig.TerminalProximityStuds, nil, path
	end
	local near, dist, limit = playerNearTrigger(player, transitId, trigger)
	return near, dist, limit, trigger, path
end

local function characterReady(player: Player): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not (hrp and hrp:IsA("BasePart")) then
		return nil, nil, nil
	end
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return char, hrp, humanoid
end

local function beginTerminalSession(player: Player, transitId: string, reason: string)
	local prev = activeTerminalSessions[player]
	if prev and prev.terminalId == transitId then
		prev.openedAt = os.clock()
		logSession("READ", player, transitId, reason .. "|refresh", 0)
		return
	end
	activeTerminalSessions[player] = {
		terminalId = transitId,
		openedAt = os.clock(),
	}
	logSession("CREATE", player, transitId, reason, 0)
	print(string.format(
		"[BubbleTransit] Menu opened terminal=%s player=%s",
		transitId,
		player.Name
	))
end

local function resolveSessionForTravel(
	player: Player,
	requestedTransitId: string
): (TerminalSession?, string?)
	local session = activeTerminalSessions[player]
	if not session then
		logSession("READ", player, requestedTransitId, "SESSION_MISSING", -1)
		return nil, "SESSION_MISSING"
	end
	local now = os.clock()
	local age = now - session.openedAt
	logSession("READ", player, session.terminalId, "travel-check", age)
	if not TravelLogic.IsTerminalSessionFresh(session.openedAt, now, SESSION_TTL_SECONDS) then
		logSession("EXPIRE", player, session.terminalId, "SESSION_EXPIRED", age)
		clearSession(player, "SESSION_EXPIRED")
		return nil, "SESSION_EXPIRED"
	end
	if not TravelLogic.SessionTerminalMatches(session.terminalId, requestedTransitId) then
		logSession(
			"READ",
			player,
			session.terminalId,
			"SESSION_TERMINAL_MISMATCH|client=" .. requestedTransitId,
			age
		)
		return nil, "SESSION_TERMINAL_MISMATCH"
	end
	local canon = TravelConfig.NormalizeTransitId(session.terminalId) or session.terminalId
	if session.terminalId ~= canon then
		session.terminalId = canon
	end
	return session, nil
end

function TravelService.RequestTravel(player: Player, destinationId: unknown, transitId: unknown)
	local destLabel = if typeof(destinationId) == "string" then destinationId else "?"
	local clientTerminalRaw = if typeof(transitId) == "string" then transitId else "?"
	local clientCanon = if typeof(transitId) == "string"
		then (TravelConfig.NormalizeTransitId(transitId) or transitId)
		else nil
	local existingSession = activeTerminalSessions[player]

	print(string.format(
		"[BubbleTransit] Destination selected destination=%s terminal=%s",
		destLabel,
		clientTerminalRaw
	))
	debugLog("Request", "player=" .. player.Name, "destination=" .. destLabel, "transit=" .. clientTerminalRaw)

	if traveling[player] then
		fireResult(player, false, "TRAVEL_COOLDOWN", "Travel is temporarily unavailable")
		return
	end

	local last = lastTravelAt[player]
	if last and (os.clock() - last) < TravelConfig.CooldownSeconds then
		fireResult(player, false, "TRAVEL_COOLDOWN", "Travel is temporarily unavailable")
		debugLog("Denied", "player=" .. player.Name, "reason=TRAVEL_COOLDOWN")
		return
	end

	if typeof(transitId) ~= "string" or transitId == "" then
		print(string.format(
			"[BubbleTransit TRACE REJECT]\nReason=INVALID_TRANSIT_ID\nClientTerminalId=%s\nSessionTerminalId=%s\nResolvedTerminalId=nil\nTriggerPath=nil\nDistance=n/a\nMaximumDistance=n/a",
			clientTerminalRaw,
			if existingSession then existingSession.terminalId else "nil"
		))
		fireResult(player, false, "TOO_FAR_FROM_TERMINAL", "Move onto the Bubble Transit pad")
		return
	end

	if not clientCanon or TravelConfig.GetTerminalDef(clientCanon) == nil then
		print(string.format(
			"[BubbleTransit TRACE REJECT]\nReason=UNKNOWN_TERMINAL\nClientTerminalId=%s\nSessionTerminalId=%s\nResolvedTerminalId=nil\nTriggerPath=nil\nDistance=n/a\nMaximumDistance=n/a",
			clientTerminalRaw,
			if existingSession then existingSession.terminalId else "nil"
		))
		fireResult(player, false, "TOO_FAR_FROM_TERMINAL", "Move onto the Bubble Transit pad", {
			TerminalId = transitId,
			SessionCode = "UNKNOWN_TERMINAL",
		})
		return
	end

	local session, sessionFail = resolveSessionForTravel(player, clientCanon)
	if not session then
		local code = sessionFail or "SESSION_MISSING"
		print(string.format(
			"[BubbleTransit TRACE REJECT]\nReason=%s\nClientTerminalId=%s\nSessionTerminalId=%s\nResolvedTerminalId=%s\nTriggerPath=nil\nDistance=n/a\nMaximumDistance=n/a",
			code,
			clientTerminalRaw,
			"nil",
			clientCanon
		))
		print(string.format(
			"[BubbleTransit] Destination rejected reason=%s terminal=%s",
			code,
			clientCanon
		))
		local fireCode = if code == "SESSION_TERMINAL_MISMATCH"
			then "TERMINAL_SESSION_MISMATCH"
			else "TOO_FAR_FROM_TERMINAL"
		fireResult(player, false, fireCode, "Move onto the Bubble Transit pad", {
			TerminalId = clientCanon,
			SessionCode = code,
		})
		return
	end

	local resolvedId = session.terminalId
	local char, hrp = characterReady(player)
	local terminal = BubbleTransitBuilder.FindTerminalByTransitId(resolvedId)
	local near = false
	local dist: number? = nil
	local maxDist: number? = TravelConfig.TerminalProximityStuds
	local anchorPart: BasePart? = nil
	local triggerPath = "nil"

	near, dist, maxDist, anchorPart, triggerPath = playerNearTerminal(player, terminal, resolvedId)

	local terminalFound = terminal ~= nil
		or (TravelConfig.IsHubLobbyTransitId(resolvedId)
			and BubbleTransitBuilder.GetInteractionAnchorForTransitId(resolvedId) ~= nil)

	print(string.format(
		"[BubbleTransit TRACE REQUEST]\nPlayer=%s\nDestinationId=%s\nClientTerminalId=%s\nSessionTerminalId=%s\nResolvedTerminalId=%s\nTriggerPath=%s\nDistance=%s\nSessionAge=%.3f",
		player.Name,
		destLabel,
		clientTerminalRaw,
		session.terminalId,
		resolvedId,
		triggerPath,
		if dist ~= nil then string.format("%.2f", dist) else "n/a",
		sessionAge(session)
	))

	if anchorPart and dist ~= nil and maxDist ~= nil then
		print(string.format(
			"[BubbleTransit] Distance validation terminal=%s distance=%.2f max=%.2f path=%s",
			resolvedId,
			dist,
			maxDist,
			triggerPath
		))
	end

	local currentArea = "Lobby"
	if terminal then
		local areaAttr = terminal:GetAttribute("CurrentArea")
		if type(areaAttr) == "string" then
			currentArea = areaAttr
		else
			currentArea = ZoneService.GetPlayerZone(player)
		end
	else
		currentArea = resolveAreaForTransit(resolvedId, nil)
	end
	currentArea = normalizeArea(currentArea)

	local destPreview = if typeof(destinationId) == "string" then TravelConfig.Get(destinationId) else nil
	local arrivalPolicy = if destPreview
		then TravelLogic.ResolveArrivalMarkerPolicy(
			destPreview.Id,
			destPreview.DestinationMarkerName,
			GameConfig.Hub.Enabled == true,
			GameConfig.Hub.ReplacesLobby == true
		)
		else nil
	local marker = if destPreview
		then BubbleTransitBuilder.FindArrivalMarker(destPreview.DestinationMarkerName, destPreview.Id)
		else nil

	local decision = TravelLogic.EvaluateTravelRequest({
		DestinationId = destinationId,
		TransitId = resolvedId,
		PlayerLevel = DataService.GetPlayerLevel(player),
		TerminalFound = terminalFound,
		NearTerminal = near == true,
		CurrentArea = currentArea,
		MarkerFound = marker ~= nil,
		HasCharacter = char ~= nil,
		HasHumanoidRootPart = hrp ~= nil,
	})

	if not decision.Ok then
		if decision.Code == "DESTINATION_LOCKED" then
			print("[BubbleTransit] Destination rejected: level required")
			if decision.DestinationId == "SummerZone" then
				withAnalytics(function(GAS)
					GAS.OnSawSummerZoneRequirement(player)
				end)
			end
		elseif decision.Code == "ARRIVAL_MARKER_MISSING" then
			local expectedPath = if arrivalPolicy
				then arrivalPolicy.ExpectedPath
				else "GameZones.TravelTerminals or Workspace.BubblePopWorld.CentralHub.HubSpawnLocation"
			warn("[BubbleTransit] Arrival point missing: " .. tostring(decision.DestinationId)
				.. " marker path=" .. expectedPath)
		elseif decision.Code == "DESTINATION_NOT_FOUND" then
			print("[BubbleTransit] Destination rejected: unknown id=" .. tostring(destinationId))
		elseif decision.Code == "CHARACTER_NOT_READY" then
			print("[BubbleTransit] Character not ready (missing HumanoidRootPart?) player=" .. player.Name)
		elseif decision.Code == "TOO_FAR_FROM_TERMINAL" then
			print(string.format(
				"[BubbleTransit TRACE REJECT]\nReason=TOO_FAR_FROM_TERMINAL\nClientTerminalId=%s\nSessionTerminalId=%s\nResolvedTerminalId=%s\nTriggerPath=%s\nDistance=%s\nMaximumDistance=%s",
				clientTerminalRaw,
				session.terminalId,
				resolvedId,
				triggerPath,
				if dist ~= nil then string.format("%.2f", dist) else "n/a",
				if maxDist ~= nil then string.format("%.2f", maxDist) else "n/a"
			))
			print(string.format(
				"[BubbleTransit] Destination rejected reason=TOO_FAR_FROM_TERMINAL terminal=%s distance=%s",
				resolvedId,
				if dist ~= nil then string.format("%.2f", dist) else "n/a"
			))
		elseif decision.Code == "ALREADY_THERE" then
			print("[BubbleTransit] Destination rejected reason=ALREADY_THERE (HERE) — no teleport")
			clearSession(player, "ALREADY_THERE")
		end
		fireResult(player, false, decision.Code, decision.Message, {
			DestinationId = decision.DestinationId,
			TerminalId = resolvedId,
		})
		debugLog("Denied", "player=" .. player.Name, "reason=" .. decision.Code)
		return
	end

	local dest = TravelConfig.Get(decision.DestinationId :: string)
	if not dest or not char or not hrp or not marker then
		fireResult(player, false, "CHARACTER_NOT_READY", "Travel is temporarily unavailable")
		return
	end

	print(string.format(
		"[BubbleTransit] Arrival resolved destination=%s path=%s",
		dest.Id,
		marker:GetFullName()
	))

	local isSummerDest = dest.Id == "SummerZone" or dest.AreaName == "SummerZone"
	if isSummerDest then
		withAnalytics(function(GAS)
			GAS.OnSelectedSummerZone(player)
		end)
	end

	traveling[player] = true
	local landedArea = dest.AreaName
	local okPivot, err = pcall(function()
		local hubReturn = dest.Id == "Lobby"
			and GameConfig.Hub.Enabled
			and GameConfig.Hub.ReplacesLobby
		if hubReturn then
			RunService.Heartbeat:Wait()
			local HubSpawnService = require(script.Parent.HubSpawnService)
			assert(HubSpawnService.ReloadCharacterAtHubSpawn(player), "hub respawn failed")
			landedArea = "GameRoom"
			player:SetAttribute("PlayerArea", landedArea)
		else
			local targetCFrame = marker.CFrame * CFrame.new(0, 3, 0)
			char:PivotTo(targetCFrame)
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			landedArea = if dest.Id == "AmusementPark"
				then "AmusementPark"
				else resolveAreaFromPosition(hrp.Position)
			player:SetAttribute("PlayerArea", landedArea)
		end
	end)
	traveling[player] = false

	if not okPivot then
		warn("[TravelService] PivotTo failed:", err)
		fireResult(player, false, "CHARACTER_NOT_READY", "Travel is temporarily unavailable")
		return
	end

	if isSummerDest then
		withAnalytics(function(GAS)
			GAS.OnArrivedAtSummerBridge(player)
		end)
	end

	lastTravelAt[player] = os.clock()
	travelSuppressedUntil[player] = os.clock() + TravelConfig.ArrivalSuppressSeconds
	print(string.format(
		"[BubbleTransit] Teleport success %s -> %s",
		resolvedId,
		dest.Id
	))
	clearSession(player, "TELEPORT_SUCCESS")
	debugLog("Success", "player=" .. player.Name, "from=" .. currentArea, "to=" .. dest.Id, "area=" .. landedArea)
	fireResult(player, true, "OK", "Travel complete", {
		DestinationId = dest.Id,
		AreaName = landedArea,
		SuppressSeconds = TravelConfig.ArrivalSuppressSeconds,
	})
end

function TravelService.Start()
	BubbleTransitBuilder.EnsureTerminals()

	Remotes.Event("RequestDestinationList").OnServerEvent:Connect(function(player: Player, transitId: unknown)
		if typeof(transitId) ~= "string" or transitId == "" then
			return
		end
		local suppressUntil = travelSuppressedUntil[player]
		if suppressUntil and os.clock() < suppressUntil then
			return
		end

		local requestedRaw = transitId
		local resolvedId = TravelConfig.NormalizeTransitId(transitId)
		if not resolvedId then
			warn("[BubbleTransit] Menu open rejected: unknown terminal=" .. transitId)
			return
		end

		local terminal = BubbleTransitBuilder.FindTerminalByTransitId(resolvedId)
		local hubOk = TravelConfig.IsHubLobbyTransitId(resolvedId)
			and BubbleTransitBuilder.GetInteractionAnchorForTransitId(resolvedId) ~= nil
		if not terminal and not hubOk then
			warn("[BubbleTransit] Menu open rejected: unknown terminal=" .. transitId
				.. " resolved=" .. resolvedId)
			return
		end

		local near, dist, maxDist, trigger, triggerPath = playerNearTerminal(player, terminal, resolvedId)
		local hrp = getPlayerHrp(player)

		print(string.format(
			"[BubbleTransit TRACE]\nPlayer=%s\nRequestedTerminalId=%s\nResolvedTerminalId=%s\nSessionTerminalId=%s\nTriggerPath=%s\nTriggerPosition=%s\nPlayerPosition=%s\nDistance=%s",
			player.Name,
			requestedRaw,
			resolvedId,
			if activeTerminalSessions[player] then activeTerminalSessions[player].terminalId else "nil",
			triggerPath or "nil",
			if trigger then tostring(getTriggerValidationPosition(trigger)) else "nil",
			if hrp then tostring(hrp.Position) else "nil",
			if dist ~= nil then string.format("%.2f", dist) else "n/a"
		))

		-- Session liée au terminal authentifié qui ouvre le menu (TTL 25s).
		-- Distance stricte uniquement sur RequestTravel (même ResolvedTerminalId, pas de fallback hub).
		beginTerminalSession(
			player,
			resolvedId,
			if near then "RequestDestinationList|near" else "RequestDestinationList|authenticated"
		)
		if not near then
			print(string.format(
				"[BubbleTransit] Menu open far terminal=%s distance=%s max=%s (session kept; travel still requires near)",
				resolvedId,
				if dist ~= nil then string.format("%.2f", dist) else "n/a",
				if maxDist ~= nil then string.format("%.2f", maxDist) else "n/a"
			))
		end

		local area = resolveAreaForTransit(resolvedId, terminal)
		debugLog(
			"Opened",
			"terminal=" .. resolvedId,
			"player=" .. player.Name,
			"area=" .. area,
			"near=" .. tostring(near)
		)
		sendList(player, resolvedId, area)
	end)

	Remotes.Event("RequestTravel").OnServerEvent:Connect(function(player: Player, destinationId: unknown, transitId: unknown)
		TravelService.RequestTravel(player, destinationId, transitId)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		traveling[player] = nil
		lastTravelAt[player] = nil
		travelSuppressedUntil[player] = nil
		clearSession(player, "PlayerRemoving")
	end)

	if RunService:IsStudio() and TravelConfig.DEBUG_TRAVEL then
		print("[TravelDebug] TravelService ready")
	end
end

return TravelService
