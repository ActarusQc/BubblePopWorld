--!strict
-- Registre central Bubble Transit : destinations + pastilles (départ = arrivée).
-- RequiredLevel SummerZone = ZoneDefs (même source que la barrière).

local ZoneDefs = require(script.Parent.ZoneDefs)
local GameConfig = require(script.Parent.GameConfig)

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
	-- Position monde absolue, ou offset si RelativeTo* est true.
	Position: Vector3,
	YawDegrees: number,
	RelativeToSummerGate: boolean?,
	RelativeToSummerBridge: boolean?,
	-- Bout nord de LobbyPath (plateforme spawn), centré largeur, marge bord.
	RelativeToLobbySpawnPlatform: boolean?,
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
-- Plateforme spawn : StairsEnd = nord (+Z, marches Bubble Room) ;
-- BackWallEnd = sud (-Z, HOW TO PLAY). La pastille lobby utilise BackWallEnd uniquement.
TravelConfig.LobbySpawnPlatform = {
	PathLocalOffset = Vector3.new(0, 0.15, 10),
	PathSize = Vector3.new(16, 1.5, 56),
	EdgeMarginStuds = 4, -- 3–5 studs du bord sud
	-- true = BackWallEnd (HOW TO PLAY) ; false serait StairsEnd (interdit).
	UseBackWallEnd = true,
}

TravelConfig.CapsulePlacements = {
	Lobby = {
		TransitId = "LobbyTransit",
		CurrentArea = "Lobby",
		ArrivalMarkerName = "LobbyTravelArrival",
		-- Offset additionnel sur BackWallEnd (centré largeur).
		Position = Vector3.new(0, 0, 0),
		-- Face le joueur qui arrive depuis le spawn (LookVector = +Z).
		YawDegrees = 180,
		RelativeToLobbySpawnPlatform = true,
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

function TravelConfig.GetPlacementByTransitId(transitId: string): CapsulePlacement?
	for _, placement in pairs(TravelConfig.CapsulePlacements) do
		if placement.TransitId == transitId then
			return placement
		end
	end
	return nil
end

export type DestinationCardDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	RequiredLevel: number,
	IsCurrent: boolean,
	IsLocked: boolean,
	IsLobby: boolean,
	SortOrder: number,
}

-- Liste UI : dépend du niveau + CurrentArea du terminal, jamais de la position du pad.
function TravelConfig.BuildDestinationCards(playerLevel: number, currentArea: string): { DestinationCardDef }
	local area = currentArea
	if area == "GameRoom" or area == "ClassicZone" then
		area = "GameRoom"
	end
	local cards: { DestinationCardDef } = {}
	for _, def in ipairs(TravelConfig.GetSortedDestinations()) do
		if not def.Enabled then
			continue
		end
		if area == "Lobby" and not def.ShowFromLobby then
			continue
		end
		table.insert(cards, {
			Id = def.Id,
			DisplayName = def.DisplayName,
			Description = def.Description,
			RequiredLevel = def.RequiredLevel,
			IsCurrent = def.AreaName == area,
			IsLocked = playerLevel < def.RequiredLevel,
			IsLobby = def.Id == "Lobby",
			SortOrder = def.SortOrder,
		})
	end
	return cards
end

-- BackWallEnd : bord sud du plancher (près HOW TO PLAY), jamais StairsEnd / marches.
function TravelConfig.ResolveLobbySpawnPlatformPosition(offset: Vector3?): Vector3
	local L = GameConfig.Lobby
	local P = TravelConfig.LobbySpawnPlatform
	local root = L.RootOffset
	local padRadius = TravelConfig.PadDimensions.PadDiameter * 0.5
	local margin = P.EdgeMarginStuds

	local floorSouthZ = root.Z - L.FloorSize.Z * 0.5
	local floorNorthZ = root.Z + L.FloorSize.Z * 0.5
	local z: number
	if P.UseBackWallEnd ~= false then
		-- Sud = mur du fond / HOW TO PLAY.
		z = floorSouthZ + margin + padRadius
	else
		-- StairsEnd (nord) — non utilisé pour le lobby.
		z = floorNorthZ - margin - padRadius
	end

	local pos = Vector3.new(root.X, root.Y, z)
	if offset then
		pos = pos + offset
	end
	return pos
end

function TravelConfig.ResolveWorldCFrame(placement: CapsulePlacement): CFrame
	local pos = placement.Position
	if placement.RelativeToSummerBridge then
		local layout = ZoneDefs.GetSummerBridgeLayout()
		pos = Vector3.new(layout.MidX, layout.Y, layout.ArchZ) + placement.Position
	elseif placement.RelativeToSummerGate then
		local layout = ZoneDefs.GetSummerBridgeLayout()
		pos = Vector3.new(layout.GateX, layout.Y, layout.ArchZ) + placement.Position
	elseif placement.RelativeToLobbySpawnPlatform then
		pos = TravelConfig.ResolveLobbySpawnPlatformPosition(placement.Position)
	end
	return CFrame.new(pos) * CFrame.Angles(0, math.rad(placement.YawDegrees), 0)
end

return TravelConfig
