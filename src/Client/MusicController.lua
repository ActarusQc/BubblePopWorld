--!strict
-- Musique d’ambiance locale par PlayerArea (client uniquement).
-- Ne touche pas aux SFX (PopEffects, boutique, outils).

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MusicConfig = require(Shared.MusicConfig)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local MusicController = {}

local GROUP_NAME = "BPW_Music"
local muted = false
local currentArea: string? = nil
local currentTrackKey: string? = nil
local activeSound: Sound? = nil
local fadingOutSound: Sound? = nil
local musicGroup: SoundGroup? = nil
local transitionToken = 0
local areaDebounceToken = 0
local warnedTracks: { [string]: boolean } = {}
local warnedIds: { [string]: boolean } = {}
local lastDiagKey: string? = nil
local started = false
local playGeneration = 0
local miniEventActive = false

local function ensureMusicGroup(): SoundGroup
	if musicGroup and musicGroup.Parent then
		return musicGroup
	end
	local existing = SoundService:FindFirstChild(GROUP_NAME)
	if existing and existing:IsA("SoundGroup") then
		musicGroup = existing
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = GROUP_NAME
	group.Volume = MusicConfig.MusicGroupVolume
	group.Parent = SoundService
	musicGroup = group
	return group
end

local function targetSoundVolume(): number
	return if muted then 0 else MusicConfig.MusicVolume
end

local function syncGroupVolume()
	local group = ensureMusicGroup()
	-- Le mute agit sur le Volume du Sound, pas sur le groupe (évite de couper d'autres sons).
	group.Volume = MusicConfig.MusicGroupVolume
end

local function warnTrackOnce(trackKey: string, message: string)
	if warnedTracks[trackKey] then
		return
	end
	warnedTracks[trackKey] = true
	warn(message)
end

local function warnIdOnce(soundId: string, message: string)
	if warnedIds[soundId] then
		return
	end
	warnedIds[soundId] = true
	warn("[MusicController]", message)
end

local function destroySound(sound: Sound?)
	if not sound then
		return
	end
	pcall(function()
		sound:Stop()
	end)
	if sound.Parent then
		sound:Destroy()
	end
end

local function emitDiagnostics(area: string, trackKey: string, soundId: string, playRequested: boolean)
	local diagKey = table.concat({
		area,
		trackKey,
		soundId,
		tostring(muted),
		tostring(playRequested),
	}, "|")
	if diagKey == lastDiagKey then
		return
	end
	lastDiagKey = diagKey

	local group = ensureMusicGroup()
	print("[MusicController] Area:", area)
	print("[MusicController] Track:", trackKey)
	print("[MusicController] SoundId:", soundId)
	print("[MusicController] Muted:", muted)
	print("[MusicController] Music group volume:", group.Volume)
	if playRequested then
		print("[MusicController] Play requested")
	end
end

local function createTrack(trackKey: string, soundId: string): Sound?
	if MusicConfig.IsPlaceholderId(soundId) then
		warnTrackOnce(trackKey, ("[MusicController] No valid music asset configured for track: %s"):format(trackKey))
		return nil
	end

	local group = ensureMusicGroup()
	local sound = Instance.new("Sound")
	sound.Name = "ZoneMusic_" .. trackKey
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = group
	-- Parent SoundService = non spatial (indépendant de la distance joueur)
	sound.Parent = SoundService

	local loaded = sound.IsLoaded
	if not loaded then
		local done = false
		local conn: RBXScriptConnection?
		conn = sound.Loaded:Connect(function()
			loaded = true
			done = true
			if conn then
				conn:Disconnect()
			end
		end)
		local deadline = os.clock() + 8
		while not done and os.clock() < deadline do
			if not sound.Parent then
				break
			end
			task.wait(0.1)
		end
		if conn then
			conn:Disconnect()
		end
	end

	if not sound.Parent then
		return nil
	end
	if not loaded then
		warnIdOnce(soundId, ("Piste inaccessible ou timeout de chargement: %s (track=%s)"):format(soundId, trackKey))
		destroySound(sound)
		return nil
	end

	return sound
end

local function fadeVolume(sound: Sound, volume: number, duration: number)
	TweenService:Create(sound, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		Volume = volume,
	}):Play()
end

local function scheduleDestroyAfterFade(sound: Sound, token: number)
	task.delay(MusicConfig.CrossfadeSeconds + 0.05, function()
		if token ~= transitionToken then
			if sound ~= activeSound then
				destroySound(sound)
			end
			return
		end
		if fadingOutSound == sound then
			fadingOutSound = nil
		end
		if sound ~= activeSound then
			destroySound(sound)
		end
	end)
end

local function beginFadeOutActive(token: number)
	if fadingOutSound and fadingOutSound ~= activeSound then
		destroySound(fadingOutSound)
		fadingOutSound = nil
	end

	local old = activeSound
	activeSound = nil
	if old then
		fadingOutSound = old
		fadeVolume(old, 0, MusicConfig.CrossfadeSeconds)
		scheduleDestroyAfterFade(old, token)
	end
end

local function playTrack(trackKey: string, immediate: boolean?)
	local soundId = MusicConfig.SoundIdForTrackKey(trackKey)
	local area = currentArea or "Lobby"
	syncGroupVolume()

	if currentTrackKey == trackKey and activeSound and activeSound.Parent then
		emitDiagnostics(area, trackKey, soundId, false)
		fadeVolume(activeSound, targetSoundVolume(), if immediate then 0.25 else 0.45)
		return
	end

	-- Mute : mémoriser la piste, fondu de l'ancienne, pas de nouvelle lecture audible
	if muted then
		emitDiagnostics(area, trackKey, soundId, false)
		if currentTrackKey == trackKey then
			return
		end
		transitionToken += 1
		local token = transitionToken
		beginFadeOutActive(token)
		currentTrackKey = trackKey
		return
	end

	if MusicConfig.IsPlaceholderId(soundId) then
		emitDiagnostics(area, trackKey, soundId, false)
		warnTrackOnce(trackKey, ("[MusicController] No valid music asset configured for track: %s"):format(trackKey))
		transitionToken += 1
		beginFadeOutActive(transitionToken)
		currentTrackKey = trackKey
		return
	end

	transitionToken += 1
	local token = transitionToken
	beginFadeOutActive(token)

	local newSound = createTrack(trackKey, soundId)
	if token ~= transitionToken then
		destroySound(newSound)
		return
	end
	if not newSound then
		currentTrackKey = trackKey
		emitDiagnostics(area, trackKey, soundId, false)
		return
	end

	currentTrackKey = trackKey
	activeSound = newSound
	emitDiagnostics(area, trackKey, soundId, true)

	playGeneration += 1
	local gen = playGeneration
	local playOk, playErr = pcall(function()
		newSound:Play()
	end)
	if not playOk then
		warnIdOnce(soundId, ("Échec Sound:Play() pour %s: %s"):format(soundId, tostring(playErr)))
		destroySound(newSound)
		if activeSound == newSound then
			activeSound = nil
		end
		return
	end

	-- Si le moteur refuse la lecture (permissions), IsPlaying peut rester false après un court délai
	task.delay(0.5, function()
		if gen ~= playGeneration then
			return
		end
		if activeSound ~= newSound or not newSound.Parent then
			return
		end
		if not newSound.IsPlaying and not muted then
			warnIdOnce(soundId, ("Sound non joué après Play() — permissions / asset invalide? %s (track=%s)"):format(soundId, trackKey))
		end
	end)

	local vol = targetSoundVolume()
	if immediate then
		newSound.Volume = vol
	else
		fadeVolume(newSound, vol, MusicConfig.CrossfadeSeconds)
	end
end

local function desiredTrackKey(area: string?): string
	-- Le parc possède une identité musicale permanente. Un mini-défi ne doit pas
	-- remplacer cette piste pendant que le joueur visite les attractions.
	if area == "AmusementPark" then
		return MusicConfig.TrackKeyForArea(area)
	end
	if miniEventActive then
		return "challenge"
	end
	return MusicConfig.TrackKeyForArea(area)
end

local function applyArea(area: any, immediate: boolean?)
	local areaName = if type(area) == "string" and area ~= "" then area else "Lobby"
	currentArea = areaName
	playTrack(desiredTrackKey(areaName), immediate)
end

function MusicController.IsMuted(): boolean
	return muted
end

function MusicController.GetCurrentArea(): string?
	return currentArea
end

function MusicController.SetMuted(nextMuted: boolean, persist: boolean?)
	if muted == nextMuted then
		return
	end
	muted = nextMuted
	syncGroupVolume()
	lastDiagKey = nil -- forcer un log d'état mute

	if muted then
		if activeSound and activeSound.Parent then
			fadeVolume(activeSound, 0, 0.45)
		end
		local area = currentArea or "Lobby"
		local trackKey = currentTrackKey or MusicConfig.TrackKeyForArea(area)
		emitDiagnostics(area, trackKey, MusicConfig.SoundIdForTrackKey(trackKey), false)
	else
		local area = currentArea or player:GetAttribute("PlayerArea")
		local trackKey = desiredTrackKey(if type(area) == "string" then area else "Lobby")
		if activeSound and activeSound.Parent and currentTrackKey == trackKey then
			emitDiagnostics(if type(area) == "string" then area else "Lobby", trackKey, MusicConfig.SoundIdForTrackKey(trackKey), true)
			fadeVolume(activeSound, MusicConfig.MusicVolume, 0.45)
			if not activeSound.IsPlaying then
				pcall(function()
					activeSound:Play()
				end)
			end
		else
			currentTrackKey = nil
			applyArea(area, true)
		end
	end

	if persist ~= false then
		task.spawn(function()
			pcall(function()
				Remotes.Event("SetMusicMuted"):FireServer(muted)
			end)
		end)
	end
end

function MusicController.ApplyMutedFromServer(nextMuted: boolean)
	if type(nextMuted) ~= "boolean" then
		return
	end
	if muted == nextMuted then
		return
	end
	MusicController.SetMuted(nextMuted, false)
end

function MusicController.Start()
	if started then
		print("[MusicController] Start() ignored (already started)")
		return
	end
	started = true
	ensureMusicGroup()
	print("[MusicController] Start() once")

	player:GetAttributeChangedSignal("PlayerArea"):Connect(function()
		areaDebounceToken += 1
		local token = areaDebounceToken
		local area = player:GetAttribute("PlayerArea")
		task.delay(MusicConfig.AreaDebounceSeconds, function()
			if token ~= areaDebounceToken then
				return
			end
			applyArea(area, false)
		end)
	end)

	-- Attendre un bref instant que PlayerArea / StatsUpdate initial puissent arriver
	task.defer(function()
		task.wait(0.15)
		local area = player:GetAttribute("PlayerArea")
		print("[MusicController] Initial PlayerArea:", tostring(area))
		applyArea(area, true)
	end)

	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function(stats)
		if type(stats) ~= "table" or type(stats.MusicMuted) ~= "boolean" then
			return
		end
		local wasMuted = muted
		MusicController.ApplyMutedFromServer(stats.MusicMuted)
		-- StatsUpdate tardif avec MusicMuted=false alors qu'aucune piste n'a démarré
		if wasMuted == false and stats.MusicMuted == false then
			if (not activeSound or not activeSound.Parent) and not MusicConfig.IsPlaceholderId(MusicConfig.TrackIdForArea(currentArea)) then
				currentTrackKey = nil
				applyArea(currentArea or player:GetAttribute("PlayerArea"), true)
			end
		elseif wasMuted == true and stats.MusicMuted == false then
			-- unmute via serveur déjà géré dans SetMuted
		end
	end)

	Remotes.Event("MiniEventState").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.state) ~= "string" then
			return
		end
		local shouldChallenge = payload.state == "Active"
		if shouldChallenge == miniEventActive then
			return
		end
		miniEventActive = shouldChallenge
		currentTrackKey = nil
		applyArea(player:GetAttribute("PlayerArea") or currentArea, false)
	end)
end

return MusicController
