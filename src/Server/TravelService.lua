--!strict
-- Autorité serveur Bubble Transit : liste destinations + déplacement sécurisé.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local TravelConfig = require(Shared.TravelConfig)
local ZoneDefs = require(Shared.ZoneDefs)
local GameConfig = require(Shared.GameConfig)

local DataService = require(script.Parent.DataService)
local ZoneService = require(script.Parent.ZoneService)
local BubbleTransitBuilder = require(script.Parent.BubbleTransitBuilder)

local TravelService = {}

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

local function normalizeArea(area: string): string
	-- GameRoom / Classic restent hors Bubble Transit (planche attachée au lobby).
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
	local placement = TravelConfig.GetPlacementByTransitId(transitId)
	if placement and type(placement.CurrentArea) == "string" then
		return normalizeArea(placement.CurrentArea)
	end
	return "Lobby"
end

local function sendList(player: Player, transitId: string, currentArea: string)
	local area = normalizeArea(currentArea)
	local cards = TravelService.GetDestinationsForPlayer(player, area)
	-- Tableau dense explicite : évite toute ambiguïté de sérialisation RemoteEvent.
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

local function playerNearTerminal(player: Player, terminal: Model): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return false
	end
	local trigger = BubbleTransitBuilder.GetTrigger(terminal)
	if trigger then
		-- Même test OBB que le client (+ marge) — la sphère excluait parfois les coins.
		return pointInPart(hrp.Position, trigger, 1.5)
	end
	local anchor = terminal.PrimaryPart
	if not anchor then
		return false
	end
	return (hrp.Position - anchor.Position).Magnitude <= TravelConfig.TerminalProximityStuds
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

function TravelService.RequestTravel(player: Player, destinationId: unknown, transitId: unknown)
	if typeof(destinationId) ~= "string" or destinationId == "" then
		fireResult(player, false, "DESTINATION_NOT_FOUND", "Travel is temporarily unavailable")
		return
	end
	if typeof(transitId) ~= "string" or transitId == "" then
		fireResult(player, false, "TOO_FAR_FROM_TERMINAL", "Move onto the Bubble Transit pad")
		return
	end

	debugLog("Request", "player=" .. player.Name, "destination=" .. destinationId, "transit=" .. transitId)

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

	local char, hrp = characterReady(player)
	if not char or not hrp then
		fireResult(player, false, "CHARACTER_NOT_READY", "Travel is temporarily unavailable")
		return
	end

	local dest = TravelConfig.Get(destinationId)
	if not dest or not dest.Enabled then
		fireResult(player, false, "DESTINATION_NOT_FOUND", "Travel is temporarily unavailable")
		debugLog("Denied", "player=" .. player.Name, "reason=DESTINATION_NOT_FOUND")
		return
	end

	local terminal = BubbleTransitBuilder.FindTerminalByTransitId(transitId)
	if not terminal then
		fireResult(player, false, "TOO_FAR_FROM_TERMINAL", "Move onto the Bubble Transit pad")
		return
	end

	if not playerNearTerminal(player, terminal) then
		fireResult(player, false, "TOO_FAR_FROM_TERMINAL", "Move onto the Bubble Transit pad")
		debugLog("Denied", "player=" .. player.Name, "reason=TOO_FAR_FROM_TERMINAL")
		return
	end

	local currentArea = terminal:GetAttribute("CurrentArea")
	if type(currentArea) ~= "string" then
		currentArea = ZoneService.GetPlayerZone(player)
	end
	currentArea = normalizeArea(currentArea :: string)

	if dest.AreaName == currentArea then
		fireResult(player, false, "ALREADY_THERE", "You are already here")
		debugLog("Denied", "player=" .. player.Name, "reason=ALREADY_THERE")
		return
	end

	local level = DataService.GetPlayerLevel(player)
	if level < dest.RequiredLevel then
		fireResult(
			player,
			false,
			"DESTINATION_LOCKED",
			string.format("Reach Level %d to unlock %s", dest.RequiredLevel, dest.DisplayName)
		)
		debugLog(
			"Denied",
			"player=" .. player.Name,
			"reason=DESTINATION_LOCKED",
			"level=" .. tostring(level),
			"required=" .. tostring(dest.RequiredLevel)
		)
		return
	end

	local marker = BubbleTransitBuilder.FindArrivalMarker(dest.DestinationMarkerName)
	if not marker then
		fireResult(player, false, "ARRIVAL_MARKER_MISSING", "Travel is temporarily unavailable")
		debugLog("Denied", "player=" .. player.Name, "reason=ARRIVAL_MARKER_MISSING")
		return
	end

	traveling[player] = true
	local landedArea = dest.AreaName
	local okPivot, err = pcall(function()
		local targetCFrame = marker.CFrame * CFrame.new(0, 3, 0)
		char:PivotTo(targetCFrame)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		-- Zone réelle d'atterrissage (pont Summer = GameRoom, pas l'intérieur).
		landedArea = resolveAreaFromPosition(hrp.Position)
		player:SetAttribute("PlayerArea", landedArea)
	end)
	traveling[player] = false

	if not okPivot then
		warn("[TravelService] PivotTo failed:", err)
		fireResult(player, false, "CHARACTER_NOT_READY", "Travel is temporarily unavailable")
		return
	end

	lastTravelAt[player] = os.clock()
	travelSuppressedUntil[player] = os.clock() + TravelConfig.ArrivalSuppressSeconds
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
		-- La liste ne dépend PAS de la position du pad. Toujours répondre pour
		-- éviter un panneau vide si le check de proximité échoue après un déplacement.
		local terminal = BubbleTransitBuilder.FindTerminalByTransitId(transitId)
		local area = resolveAreaForTransit(transitId, terminal)
		debugLog(
			"Opened",
			"terminal=" .. transitId,
			"player=" .. player.Name,
			"area=" .. area,
			"near=" .. tostring(terminal ~= nil and playerNearTerminal(player, terminal))
		)
		sendList(player, transitId, area)
	end)

	Remotes.Event("RequestTravel").OnServerEvent:Connect(function(player: Player, destinationId: unknown, transitId: unknown)
		-- Ignore tout autre argument client (niveau, CFrame, etc.).
		TravelService.RequestTravel(player, destinationId, transitId)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		traveling[player] = nil
		lastTravelAt[player] = nil
		travelSuppressedUntil[player] = nil
	end)

	if RunService:IsStudio() and TravelConfig.DEBUG_TRAVEL then
		print("[TravelDebug] TravelService ready")
	end
end

return TravelService
