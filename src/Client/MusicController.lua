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

local FOLDER_NAME = "BPW_ZoneMusic"
local muted = false
local currentArea: string? = nil
local currentTrackId: string? = nil
local activeSound: Sound? = nil
local fadingOutSound: Sound? = nil
local transitionToken = 0
local areaDebounceToken = 0
local warnedIds: { [string]: boolean } = {}
local started = false

local function musicFolder(): Folder
	local existing = SoundService:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = SoundService
	return folder
end

local function targetVolume(): number
	return if muted then 0 else MusicConfig.MusicVolume
end

local function warnOnce(soundId: string, message: string)
	if warnedIds[soundId] then
		return
	end
	warnedIds[soundId] = true
	warn("[MusicController]", message, soundId)
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

local function createTrack(soundId: string): Sound?
	if MusicConfig.IsPlaceholderId(soundId) then
		warnOnce(soundId, "ID audio placeholder — musique ignorée:")
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "ZoneMusic"
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = 0
	-- Parent SoundService = non spatial (indépendant de la distance joueur)
	sound.Parent = musicFolder()

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
		warnOnce(soundId, "Piste inaccessible ou timeout de chargement:")
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
			-- Transition plus récente : détruire seulement si ce son n'est plus actif
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

local function playTrack(trackId: string, immediate: boolean?)
	if currentTrackId == trackId and activeSound and activeSound.Parent then
		fadeVolume(activeSound, targetVolume(), if immediate then 0.25 else 0.45)
		return
	end

	-- Mute : mémoriser la piste, fondu de l'ancienne, pas de nouvelle lecture audible
	if muted then
		if currentTrackId == trackId then
			return
		end
		transitionToken += 1
		local token = transitionToken
		beginFadeOutActive(token)
		currentTrackId = trackId
		return
	end

	transitionToken += 1
	local token = transitionToken
	beginFadeOutActive(token)

	local newSound = createTrack(trackId)
	if token ~= transitionToken then
		destroySound(newSound)
		return
	end
	if not newSound then
		currentTrackId = nil
		return
	end

	currentTrackId = trackId
	activeSound = newSound

	local playOk = pcall(function()
		newSound:Play()
	end)
	if not playOk then
		warnOnce(trackId, "Échec lecture musique:")
		destroySound(newSound)
		if activeSound == newSound then
			activeSound = nil
			currentTrackId = nil
		end
		return
	end

	local vol = targetVolume()
	if immediate then
		newSound.Volume = vol
	else
		fadeVolume(newSound, vol, MusicConfig.CrossfadeSeconds)
	end
end

local function applyArea(area: any, immediate: boolean?)
	local areaName = if type(area) == "string" and area ~= "" then area else "Lobby"
	currentArea = areaName
	playTrack(MusicConfig.TrackIdForArea(areaName), immediate)
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

	if muted then
		if activeSound and activeSound.Parent then
			fadeVolume(activeSound, 0, 0.45)
		end
	else
		local area = currentArea or player:GetAttribute("PlayerArea")
		local wantId = MusicConfig.TrackIdForArea(if type(area) == "string" then area else "Lobby")
		if activeSound and activeSound.Parent and currentTrackId == wantId then
			fadeVolume(activeSound, MusicConfig.MusicVolume, 0.45)
		else
			currentTrackId = nil
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
	-- Appliquer sans re-persister (évite boucle remote)
	MusicController.SetMuted(nextMuted, false)
end

function MusicController.Start()
	if started then
		return
	end
	started = true
	musicFolder()

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

	task.defer(function()
		task.wait(0.1)
		applyArea(player:GetAttribute("PlayerArea"), true)
	end)

	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function(stats)
		if type(stats) == "table" and type(stats.MusicMuted) == "boolean" then
			MusicController.ApplyMutedFromServer(stats.MusicMuted)
		end
	end)
end

return MusicController
