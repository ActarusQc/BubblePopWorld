--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RearHubStudioInstall = require(Shared.RearHubStudioInstall)
local RearHubIdentity = require(Shared.RearHubIdentity)
local RearHubLogic = require(Shared.RearHubLogic)
local RearHubCollisionLogic = require(Shared.RearHubCollisionLogic)

local RearHubStudioInstallTests = {}

function RearHubStudioInstallTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			warn("[RearHubStudioInstallTests] FAIL:", msg)
			ok = false
		end
	end

	check(RearHubIdentity.IsExactSourceName("3d stage arena prop"), "exact name")
	check(type(RearHubStudioInstall.GetBakedHub) == "function", "GetBakedHub")
	check(type(RearHubStudioInstall.IsValidBakedHub) == "function", "IsValidBakedHub")
	check(type(RearHubStudioInstall.RunFullInstall) == "function", "RunFullInstall")
	check(type(RearHubStudioInstall.CollectMetricsFromBaked) == "function", "CollectMetricsFromBaked")
	check(type(RearHubStudioInstall.ArchiveSource) == "function", "ArchiveSource")

	local ManualRig = require(Shared.RearHubManualRig)
	check(type(ManualRig.EnsureRig) == "function", "EnsureRig")
	check(type(ManualRig.SetCollidersVisible) == "function", "SetCollidersVisible")
	check(type(ManualRig.ValidateRuntime) == "function", "ValidateRuntime")
	check(ManualRig.GetRuntimeRepositionCount() == 0, "runtime never repositions")
	check(RearHubCollisionLogic.ShouldPreserveManualAnchorCFrame(true) == true, "preserve manual")
	check(RearHubCollisionLogic.ShouldPreserveManualAnchorCFrame(false) == false, "no preserve")
	check(RearHubCollisionLogic.ShouldPreserveManualSpawnCFrame(true, false) == true, "preserve spawn manual attr")
	check(RearHubCollisionLogic.ShouldPreserveManualSpawnCFrame(false, true) == true, "preserve spawn initialized")
	check(RearHubCollisionLogic.ShouldPreserveManualSpawnCFrame(false, false) == false, "no preserve gen spawn")

	local room = RearHubLogic.GetOriginalRoomBounds()
	check(room.MaxZ > room.MinZ, "room bounds")

	local baked = RearHubStudioInstall.GetBakedHub()
	if baked then
		check(baked.Name == "TripoRearHubPlatform", "baked name")
		if RearHubStudioInstall.IsValidBakedHub(baked) then
			check(baked:GetAttribute("BPW_BakedStudioHub") == true, "baked attr")
			check(baked:GetAttribute("BPW_SourceValidated") == true, "validated")
			local m = RearHubStudioInstall.CollectMetricsFromBaked(baked)
			check(m ~= nil, "metrics from baked")
			if m then
				check(m.RearZ <= room.MaxZ + 0.1, "baked rear inside original room")
				check(m.FrontZ < m.RearZ, "front < rear")
			end
		end
	else
		print("[RearHubStudioInstallTests] SKIP baked hub (run Studio plugin once)")
	end

	local place = RearHubLogic.ComputeRearPlacement()
	check(math.abs(place.RoomRearBoundaryZ - place.OriginalRoomRearZ) < 1e-6, "no room expansion")
	check(place.PlatformRearZ <= place.OriginalRoomRearZ, "platform rear inside")

	if ok then
		print("[RearHubStudioInstallTests] ALL PASS")
	else
		warn("[RearHubStudioInstallTests] SOME FAILED")
	end
	return ok
end

return RearHubStudioInstallTests
