--!strict
-- Identifiants et réglages de la musique d’ambiance par zone.
-- Remplacer les trois IDs ci-dessous par de vrais rbxassetid une fois les assets prêts.

local MusicConfig = {}

-- Placeholders : remplacer facilement ici (et nulle part ailleurs).
MusicConfig.LOBBY_MUSIC_ID = "rbxassetid://0"
MusicConfig.MAIN_BUBBLE_ZONE_MUSIC_ID = "rbxassetid://0"
MusicConfig.SUMMER_ZONE_MUSIC_ID = "rbxassetid://0"

MusicConfig.MusicVolume = 0.25
MusicConfig.CrossfadeSeconds = 1.5
MusicConfig.AreaDebounceSeconds = 0.4

-- PlayerArea (ZoneService) → SoundId
MusicConfig.AreaToTrackId = {
	Lobby = MusicConfig.LOBBY_MUSIC_ID,
	GameRoom = MusicConfig.MAIN_BUBBLE_ZONE_MUSIC_ID,
	SummerZone = MusicConfig.SUMMER_ZONE_MUSIC_ID,
}

function MusicConfig.TrackIdForArea(area: string?): string
	if type(area) == "string" then
		local id = MusicConfig.AreaToTrackId[area]
		if type(id) == "string" and id ~= "" then
			return id
		end
	end
	return MusicConfig.LOBBY_MUSIC_ID
end

function MusicConfig.IsPlaceholderId(soundId: string): boolean
	return soundId == "" or soundId == "rbxassetid://0" or soundId == "rbxassetid://"
end

return MusicConfig
