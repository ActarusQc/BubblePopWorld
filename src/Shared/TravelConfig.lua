--!strict
-- Registre central Bubble Transit : destinations + pastilles (départ = arrivée).
-- RequiredLevel SummerZone = ZoneDefs (même source que la barrière).

local ZoneDefs = require(script.Parent.ZoneDefs)

export type DestinationDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	RequiredLevel: number,
	AreaName: string,
	DestinationMarkerName: string,
	SortOrder: number,
	ShowFromLobby: boolean,
	Enabled: boolean,
}

export type CapsulePlacement = {
	TransitId: string,
	CurrentArea: string,
	ArrivalMarkerName: string,
	-- Position monde absolue, relative au Gate, ou centre du pont Summer.
	Position: Vector3,
	YawDegrees: number,
	RelativeToSummerGate: boolean?,
	RelativeToSummerBridge: boolean?,
}

local TravelConfig = {}

TravelConfig.DEBUG_TRAVEL = false

TravelConfig.CooldownSeconds = 2
TravelConfig.TerminalProximityStuds = 5
-- Anti-réouverture menu après arrivée sur la même pastille.
TravelConfig.ArrivalSuppressSeconds = 2.5
TravelConfig.ClientReopenDelay = 2.5
TravelConfig.TravelAnimSeconds = 0.75
TravelConfig.TravelSoundId = ""

--------------------------------------------------------------------
-- Pastille ouverte (1 personnage, accessible 360°)
--------------------------------------------------------------------
TravelConfig.PadDimensions = {
	PadDiameter = 6,
	PadHeight = 0.4,
	TriggerSize = Vector3.new(5, 6, 5),
}

-- Alias compat tests / ancien nom.
TravelConfig.CapsuleDimensions = TravelConfig.PadDimensions

--------------------------------------------------------------------
-- Destinations
--------------------------------------------------------------------
TravelConfig.Destinations = {
	Lobby = {
		Id = "Lobby",
		DisplayName = "Lobby",
		Description = "Sell your bubbles and buy upgrades",
		RequiredLevel = 1,
		AreaName = "Lobby",
		DestinationMarkerName = "LobbyTravelArrival",
		SortOrder = 1,
		ShowFromLobby = false,
		Enabled = true,
	},
	SummerZone = {
		Id = "SummerZone",
		DisplayName = "Summer Zone",
		Description = "A sunny bubble-popping paradise",
		RequiredLevel = ZoneDefs.GetRequiredLevel("SummerZone"),
		AreaName = "SummerZone",
		DestinationMarkerName = "SummerZoneTravelArrival",
		SortOrder = 2,
		ShowFromLobby = true,
		Enabled = true,
	},
} :: { [string]: DestinationDef }

--------------------------------------------------------------------
-- Une pastille visible par zone (= départ + arrivée)
--------------------------------------------------------------------
TravelConfig.CapsulePlacements = {
	Lobby = {
		TransitId = "LobbyTransit",
		CurrentArea = "Lobby",
		ArrivalMarkerName = "LobbyTravelArrival",
		Position = Vector3.new(38, 0, -258),
		YawDegrees = -90, -- face kiosques / centre lobby
		RelativeToSummerGate = false,
	},
	SummerZone = {
		TransitId = "SummerZoneTransit",
		CurrentArea = "SummerZone",
		ArrivalMarkerName = "SummerZoneTravelArrival",
		-- Centre du pont, face +X (entrée Summer Zone).
		Position = Vector3.new(0, 0, 0),
		YawDegrees = -90,
		RelativeToSummerBridge = true,
	},
} :: { [string]: CapsulePlacement }

function TravelConfig.Get(destinationId: string): DestinationDef?
	return TravelConfig.Destinations[destinationId]
end

function TravelConfig.GetSortedDestinations(): { DestinationDef }
	local list: { DestinationDef } = {}
	for _, def in pairs(TravelConfig.Destinations) do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		if a.SortOrder == b.SortOrder then
			return a.Id < b.Id
		end
		return a.SortOrder < b.SortOrder
	end)
	return list
end

function TravelConfig.ResolveWorldCFrame(placement: CapsulePlacement): CFrame
	local pos = placement.Position
	if placement.RelativeToSummerBridge then
		local layout = ZoneDefs.GetSummerBridgeLayout()
		pos = Vector3.new(layout.MidX, layout.Y, layout.ArchZ) + placement.Position
	elseif placement.RelativeToSummerGate then
		local layout = ZoneDefs.GetSummerBridgeLayout()
		pos = Vector3.new(layout.GateX, layout.Y, layout.ArchZ) + placement.Position
	end
	return CFrame.new(pos) * CFrame.Angles(0, math.rad(placement.YawDegrees), 0)
end

return TravelConfig
