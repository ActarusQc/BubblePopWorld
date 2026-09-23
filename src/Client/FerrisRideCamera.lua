--!strict
-- Caméra extérieure pendant la grande roue : la cabine reste visible et le parc aussi.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FerrisRideCamera = {}

local RIDE_MIN_ZOOM = 32
local RIDE_MAX_ZOOM = 52
local RIDE_CAMERA_OFFSET = Vector3.new(0, 8, 0)
local DEFAULT_MIN_ZOOM = 6
local DEFAULT_MAX_ZOOM = 18

local player = Players.LocalPlayer
local riding = false

local function isFerrisSeat(value: Instance?): boolean
	return value ~= nil and value:IsA("Seat") and value:GetAttribute("FerrisWheelSeat") == true
end

local function currentSeat(humanoid: Humanoid): Instance?
	local occupantSeat = humanoid.SeatPart
	if occupantSeat then
		return occupantSeat
	end
	return nil
end

local function applyRideCamera(humanoid: Humanoid)
	riding = true
	player.CameraMinZoomDistance = RIDE_MIN_ZOOM
	player.CameraMaxZoomDistance = RIDE_MAX_ZOOM
	player.CameraMode = Enum.CameraMode.Classic
	humanoid.CameraOffset = RIDE_CAMERA_OFFSET
end

local function restoreCamera(humanoid: Humanoid?)
	riding = false
	player.CameraMinZoomDistance = DEFAULT_MIN_ZOOM
	player.CameraMaxZoomDistance = DEFAULT_MAX_ZOOM
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end
end

local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Seated:Connect(function(active: boolean, seat: BasePart?)
		if active and isFerrisSeat(seat) then
			applyRideCamera(humanoid)
		else
			restoreCamera(humanoid)
		end
	end)
	if isFerrisSeat(currentSeat(humanoid)) then
		applyRideCamera(humanoid)
	end
end

function FerrisRideCamera.Start()
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		restoreCamera(nil)
		bindCharacter(character)
	end)
	RunService.Heartbeat:Connect(function()
		if not riding then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
		if not humanoid or not isFerrisSeat(currentSeat(humanoid)) then
			restoreCamera(humanoid)
			return
		end
		player.CameraMinZoomDistance = RIDE_MIN_ZOOM
		player.CameraMaxZoomDistance = RIDE_MAX_ZOOM
		humanoid.CameraOffset = RIDE_CAMERA_OFFSET
	end)
end

return FerrisRideCamera
