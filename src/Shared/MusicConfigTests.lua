--!strict
-- Tests purs pour MusicConfig (mapping zones / placeholders).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MusicConfig = require(Shared.MusicConfig)

local MusicConfigTests = {}

function MusicConfigTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[MusicConfigTests] FAIL:", msg)
		end
	end

	check(MusicConfig.MusicVolume == 0.25, "MusicVolume == 0.25")
	check(MusicConfig.CrossfadeSeconds == 1.5, "CrossfadeSeconds == 1.5")
	check(MusicConfig.TrackKeyForArea("Lobby") == "lobby", "Lobby key")
	check(MusicConfig.TrackKeyForArea("GameRoom") == "main", "GameRoom key")
	check(MusicConfig.TrackKeyForArea("SummerZone") == "summer", "SummerZone key")
	check(MusicConfig.TrackKeyForArea(nil) == "lobby", "nil → lobby key")
	check(MusicConfig.TrackIdForArea("Lobby") == MusicConfig.LOBBY_MUSIC_ID, "Lobby track")
	check(MusicConfig.TrackIdForArea("GameRoom") == MusicConfig.MAIN_BUBBLE_ZONE_MUSIC_ID, "GameRoom track")
	check(MusicConfig.TrackIdForArea("SummerZone") == MusicConfig.SUMMER_ZONE_MUSIC_ID, "SummerZone track")
	check(MusicConfig.TrackIdForArea(nil) == MusicConfig.LOBBY_MUSIC_ID, "nil → Lobby")
	check(MusicConfig.TrackIdForArea("Unknown") == MusicConfig.LOBBY_MUSIC_ID, "inconnu → Lobby")
	check(MusicConfig.IsPlaceholderId("rbxassetid://0") == true, "placeholder 0")
	check(MusicConfig.IsPlaceholderId("rbxassetid://123") == false, "real id not placeholder")
	check(MusicConfig.MusicGroupVolume > 0, "MusicGroupVolume > 0")

	if failed == 0 then
		print("[MusicConfigTests] OK")
		return true
	end
	return false
end

return MusicConfigTests
