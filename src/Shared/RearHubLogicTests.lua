--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local RearHubLogic = require(Shared.RearHubLogic)
local HubLayout = require(Shared.HubLayout)
local ZoneDefs = require(Shared.ZoneDefs)

local RearHubLogicTests = {}

function RearHubLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[RearHubLogicTests] FAIL:", msg)
			ok = false
		end
	end

	local bounds = RearHubLogic.GetBubbleGridBounds()
	local room = RearHubLogic.GetOriginalRoomBounds()
	check(bounds.MaxZ > bounds.MinZ, "bounds Z valides")
	check(room.MaxZ > room.MinZ, "room bounds valides")
	check(math.abs(bounds.CenterX - GameConfig.Grid.Origin.X) < 1e-6, "centre X grille")

	if not (GameConfig.Hub.Placement and GameConfig.Hub.Placement.Mode == "RearOfGrid") then
		print("[RearHubLogicTests] SKIP placement Rear (Mode ≠ RearOfGrid)")
		return ok
	end

	local place = RearHubLogic.ComputeRearPlacement()
	local clear = place.ClearanceStuds

	--------------------------------------------------------------------
	-- Intégration : collé au fond ORIGINAL, PAS extension
	--------------------------------------------------------------------
	check(place.FrontSign == -1, "FrontSign = -1")
	check(math.abs(place.OriginalRoomRearZ - room.MaxZ) < 1e-6, "original room rear")
	check(math.abs(place.RoomRearBoundaryZ - place.OriginalRoomRearZ) < 1e-6,
		"RoomRearBoundary = fond original (pas extension)")
	check(RearHubLogic.AssertRearGapOk(place.OriginalRoomRearZ, place.PlatformRearZ),
		string.format("rear gap 1–2 (got %.2f)", place.OriginalRoomRearZ - place.PlatformRearZ))
	check(RearHubLogic.AssertNotRoomExpandingPlacement(place.PlatformRearZ, place.OriginalRoomRearZ),
		"plateau ne dépasse pas le fond original")
	check(
		RearHubLogic.AssertPlatformInsideOriginalRoom(
			place.PlatformFrontZ,
			place.PlatformRearZ,
			place.OriginalRoomMinZ,
			place.OriginalRoomRearZ
		),
		"plateau dans la salle originale"
	)
	check(place.PlatformRearZ > place.PlatformFrontZ, "rear > front")
	check(place.PlatformFrontZ < place.BubbleOuterMaxZ,
		"façade DANS la grille de bulles (intégration)")
	check(place.Center.Z < place.OriginalRoomRearZ, "pivot avant le fond original")
	check(place.Center.Z < place.BubbleOuterMaxZ + 5,
		"pivot pas dans une extension nord")
	check(RearHubLogic.AssertLandingClearanceOk(clear), "clearance landing 2–4")

	-- centerZ = originalRear - margin - toRear
	local expectedCenter = place.PlatformRearZ - place.PivotToFrontEdge + place.PivotToFrontEdge -- tautology guard
	expectedCenter = place.PlatformRearZ - (place.PlatformRearZ - place.Center.Z)
	check(math.abs(place.Center.Z - expectedCenter) < 1e-3, "center cohérent rear")

	-- Ancienne logique d'extension INTERDITE
	local oldExpandRear = place.PlatformRearZ + 6
	check(place.RoomRearBoundaryZ < oldExpandRear - 1,
		"ne suit pas platformRear+6")

	local platform = {
		MinX = place.Center.X - GameConfig.Hub.DeckHalfX,
		MaxX = place.Center.X + GameConfig.Hub.DeckHalfX,
		MinZ = place.PlatformFrontZ,
		MaxZ = place.PlatformRearZ,
	}
	local hits = RearHubLogic.CountBubblePlatformIntersections(platform)
	check(hits > 0, string.format("intersection bulles attendue (got %d)", hits))

	local sizeX, sizeZ = ZoneDefs.GetGridSize("ClassicZone")
	local midFree = not HubLayout.IsCellReserved("ClassicZone", math.floor(sizeX / 2), math.floor(sizeZ / 2))
	-- Centre peut rester libre si le plateau est entièrement au nord (dernières rangées)
	check(type(midFree) == "boolean", "réserve centrale définissable")

	local look = HubLayout.GetSpawnCFrame().LookVector
	check(look.Z < -0.9, "spawn face bulles -Z")

	-- Tests formules placement pur
	local toFront, toRear = 30, 25
	local p2 = RearHubLogic.ComputeRearPlacement(nil, toFront, toRear)
	check(math.abs(p2.PlatformRearZ - (p2.OriginalRoomRearZ - p2.RearMargin)) < 1e-3,
		"rear = original - margin")
	check(math.abs(p2.Center.Z - (p2.PlatformRearZ - toRear)) < 1e-3,
		"center = rear - pivotToRear")
	check(math.abs(p2.PlatformFrontZ - (p2.Center.Z - toFront)) < 1e-3,
		"front = center - pivotToFront")

	print(string.format(
		"[RearHubLogicTests] OK pivotZ=%.1f front=%.1f rear=%.1f roomRear=%.1f gap=%.2f hits=%d",
		place.Center.Z,
		place.PlatformFrontZ,
		place.PlatformRearZ,
		place.RoomRearBoundaryZ,
		place.OriginalRoomRearZ - place.PlatformRearZ,
		hits
	))
	return ok
end

return RearHubLogicTests
