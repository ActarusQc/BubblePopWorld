--!strict
-- Identifiants et réglages de la musique d’ambiance par zone.
-- Remplacer les trois IDs ci-dessous par de vrais rbxassetid une fois les assets prêts.

local MusicConfig = {}

-- Remplacer les IDs ici. rbxassetid://0 = pas encore configuré (pas de lecture).
MusicConfig.LOBBY_MUSIC_ID = "rbxassetid://132319769870114"
MusicConfig.MAIN_BUBBLE_ZONE_MUSIC_ID = "rbxassetid://132358134818032"
MusicConfig.SUMMER_ZONE_MUSIC_ID = "rbxassetid://1841668957"

MusicConfig.MusicVolume = 0.25
MusicConfig.CrossfadeSeconds = 1.5
MusicConfig.AreaDebounceSeconds = 0.4
MusicConfig.MusicGroupVolume = 1

-- Clés logiques de piste (diagnostics / sélection)
MusicConfig.AreaToTrackKey = {
	Lobby = "lobby",
	GameRoom = "main",
	SummerZone = "summer",
}

-- PlayerArea (ZoneService) → SoundId
MusicConfig.AreaToTrackId = {
	Lobby = MusicConfig.LOBBY_MUSIC_ID,
	GameRoom = MusicConfig.MAIN_BUBBLE_ZONE_MUSIC_ID,
	SummerZone = MusicConfig.SUMMER_ZONE_MUSIC_ID,
}

MusicConfig.TrackKeyToSoundId = {
	lobby = MusicConfig.LOBBY_MUSIC_ID,
	main = MusicConfig.MAIN_BUBBLE_ZONE_MUSIC_ID,
	summer = MusicConfig.SUMMER_ZONE_MUSIC_ID,
}

function MusicConfig.TrackKeyForArea(area: string?): string
	if type(area) == "string" then
		local key = MusicConfig.AreaToTrackKey[area]
		if type(key) == "string" and key ~= "" then
			return key
		end
	end
	return "lobby"
end

function MusicConfig.TrackIdForArea(area: string?): string
	local key = MusicConfig.TrackKeyForArea(area)
	local id = MusicConfig.TrackKeyToSoundId[key]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return MusicConfig.LOBBY_MUSIC_ID
end

function MusicConfig.SoundIdForTrackKey(trackKey: string): string
	local id = MusicConfig.TrackKeyToSoundId[trackKey]
	if type(id) == "string" and id ~= "" then
		return id
	end
	return MusicConfig.LOBBY_MUSIC_ID
end

function MusicConfig.IsPlaceholderId(soundId: string): boolean
	if soundId == "" or soundId == "rbxassetid://" then
		return true
	end
	-- rbxassetid://0 et variantes numériques nulles
	local numeric = string.match(soundId, "^rbxassetid://(%d+)$")
	if numeric and tonumber(numeric) == 0 then
		return true
	end
	return false
end

return MusicConfig
