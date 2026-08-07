--!strict
-- Tests ancre transit Studio-owned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TransitAnchorLogic = require(Shared.TransitAnchorLogic)

local TransitAnchorLogicTests = {}

function TransitAnchorLogicTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[TransitAnchorLogicTests] FAIL:", msg)
		end
	end

	check(TransitAnchorLogic.NAME == "BubbleTransitInteractionAnchor", "nom")
	check(TransitAnchorLogic.FALLBACK_SIZE == Vector3.new(6, 5, 7), "fallback size")
	check(TransitAnchorLogic.FALLBACK_POSITION == Vector3.new(0, 8.5, 70.5), "fallback pos")
	check(TransitAnchorLogic.MustNeverWriteCFrameOrSizeWhenExists(true) == true, "never write if exists")
	check(TransitAnchorLogic.MustNeverWriteCFrameOrSizeWhenExists(false) == false, "can create if missing")
	check(TransitAnchorLogic.ShouldCreateFallback(false) == true, "create when missing")
	check(TransitAnchorLogic.ShouldCreateFallback(true) == false, "no create when exists")
	check(
		TransitAnchorLogic.MatchesFallbackPose(Vector3.new(6, 5, 7), Vector3.new(0, 8.5, 70.5)),
		"match fallback"
	)
	check(
		TransitAnchorLogic.IsLegacyPluginPose(Vector3.new(2, 4, 2), Vector3.new(0, 8, 19)) == true,
		"legacy pose match"
	)
	check(
		TransitAnchorLogic.IsLegacyPluginPose(Vector3.new(6, 5, 7), Vector3.new(0, 8.5, 70.5)) == false,
		"validated not legacy"
	)
	check(
		TransitAnchorLogic.ShouldMigrateLegacyPose(false, Vector3.new(2, 4, 2), Vector3.new(0, 8, 19)) == true,
		"should migrate legacy"
	)
	check(
		TransitAnchorLogic.ShouldMigrateLegacyPose(true, Vector3.new(2, 4, 2), Vector3.new(0, 8, 19)) == false,
		"never remigrate"
	)
	check(
		TransitAnchorLogic.ShouldMigrateLegacyPose(false, Vector3.new(6, 5, 7), Vector3.new(0, 8.5, 70.5)) == false,
		"no migrate validated"
	)
	check(
		TransitAnchorLogic.LEGACY_PLUGIN_POSITION == Vector3.new(0, 8, 19),
		"legacy pos constant"
	)
	check(TransitAnchorLogic.LEGACY_PLUGIN_SIZE == Vector3.new(2, 4, 2), "legacy size constant")

	if failed == 0 then
		print("[TransitAnchorLogicTests] ALL PASS")
		return true
	end
	warn("[TransitAnchorLogicTests] SOME FAILED:", failed)
	return false
end

return TransitAnchorLogicTests
