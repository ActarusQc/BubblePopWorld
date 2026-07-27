--!strict
-- Sac à dos purement visuel (ne touche pas à la logique BackpackService).

local Players = game:GetService("Players")

local BackpackVisual = {}

local BAG_NAME = "BPW_Backpack"
local DISPLAY_NAME = "BagCountDisplay"
local COUNT_LABEL_NAME = "Count"

local COLOR_BG = Color3.fromRGB(8, 22, 65)
local COLOR_ACCENT = Color3.fromRGB(80, 230, 255)
local COLOR_NUMBER = Color3.fromRGB(245, 250, 255)
local COLOR_NEAR_FULL = Color3.fromRGB(255, 210, 90)
local COLOR_FULL = Color3.fromRGB(255, 110, 110)

local displayConnections: { [Model]: { RBXScriptConnection } } = {}

local function getTorso(character: Model): BasePart?
	local upper = character:FindFirstChild("UpperTorso")
	if upper and upper:IsA("BasePart") then
		return upper
	end
	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return nil
end

local function hasWings(character: Model): boolean
	return character:FindFirstChild("BPW_Wings") ~= nil
end

-- Offset local torso : plus bas / plus près du corps si ailes présentes
-- pour laisser les ailes au-dessus et à l'extérieur du sac.
local function bagOffset(character: Model): CFrame
	if hasWings(character) then
		return CFrame.new(0, -0.4, 0.42) * CFrame.Angles(math.rad(-6), 0, 0)
	end
	return CFrame.new(0, -0.12, 0.58) * CFrame.Angles(math.rad(-4), 0, 0)
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = false
	return p
end

local function clearDisplayConnections(character: Model)
	local list = displayConnections[character]
	if not list then
		return
	end
	for _, conn in list do
		conn:Disconnect()
	end
	displayConnections[character] = nil
end

local function numberColor(current: number, capacity: number): Color3
	if capacity <= 0 then
		return COLOR_NUMBER
	end
	if current >= capacity then
		return COLOR_FULL
	end
	if current / capacity >= 0.75 then
		return COLOR_NEAR_FULL
	end
	return COLOR_NUMBER
end

local function readBubbleCount(player: Player?): (number, number)
	if not player then
		return 0, 0
	end
	local currentRaw = player:GetAttribute("CurrentBubbles")
	local capacityRaw = player:GetAttribute("BackpackCapacity")
	local current = if typeof(currentRaw) == "number" then math.max(0, math.floor(currentRaw)) else 0
	local capacity = if typeof(capacityRaw) == "number" then math.max(0, math.floor(capacityRaw)) else 0
	return current, capacity
end

local function applyCount(label: TextLabel, current: number, capacity: number)
	local text = tostring(current)
	local color = numberColor(current, capacity)
	if label.Text ~= text then
		label.Text = text
	end
	if label.TextColor3 ~= color then
		label.TextColor3 = color
	end
end

local function createCountDisplay(folder: Folder, body: BasePart, player: Player?)
	-- Plaque sur la face arrière (+Z) : milieu-bas du sac pour rester sous la tête/épaules.
	-- BagBody = 1.15×1.35×0.7 → bas local ≈ -0.675 ; plaque centrée plus bas que le milieu.
	local plate = makePart(DISPLAY_NAME, Vector3.new(0.72, 0.38, 0.05), COLOR_BG, Enum.Material.SmoothPlastic)
	plate.CFrame = body.CFrame * CFrame.new(0, -0.45, 0.40)
	plate.Parent = folder
	weld(body, plate)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "CountGui"
	gui.Adornee = plate
	gui.Face = Enum.NormalId.Back -- +Z local = face arrière visible en 3e personne
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.MaxDistance = 80
	gui.Parent = plate

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = COLOR_BG
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_ACCENT
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = COUNT_LABEL_NAME
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = COLOR_NUMBER
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 10, 40)
	label.Text = "0"
	label.Parent = frame

	local current, capacity = readBubbleCount(player)
	applyCount(label, current, capacity)

	local character = folder.Parent
	if not player or not character or not character:IsA("Model") then
		return
	end

	local connections: { RBXScriptConnection } = {}
	local function refresh()
		if not label.Parent then
			return
		end
		local cur, cap = readBubbleCount(player)
		applyCount(label, cur, cap)
	end

	table.insert(connections, player:GetAttributeChangedSignal("CurrentBubbles"):Connect(refresh))
	table.insert(connections, player:GetAttributeChangedSignal("BackpackCapacity"):Connect(refresh))
	table.insert(connections, folder.Destroying:Connect(function()
		clearDisplayConnections(character)
	end))

	displayConnections[character] = connections
end

function BackpackVisual.Detach(character: Model)
	clearDisplayConnections(character)
	local existing = character:FindFirstChild(BAG_NAME)
	if existing then
		existing:Destroy()
	end
end

function BackpackVisual.Attach(character: Model)
	BackpackVisual.Detach(character)

	local torso = getTorso(character)
	if not torso then
		local waited = character:WaitForChild("UpperTorso", 3) or character:WaitForChild("Torso", 1)
		if waited and waited:IsA("BasePart") then
			torso = waited
		end
	end
	if not torso then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = BAG_NAME
	folder.Parent = character

	local offset = bagOffset(character)

	local body = makePart("BagBody", Vector3.new(1.15, 1.35, 0.7), Color3.fromRGB(55, 120, 210))
	body.CFrame = torso.CFrame * offset
	body.Parent = folder
	weld(torso, body)

	local lid = makePart("BagLid", Vector3.new(1.2, 0.28, 0.75), Color3.fromRGB(130, 90, 230), Enum.Material.SmoothPlastic)
	lid.CFrame = body.CFrame * CFrame.new(0, 0.7, 0)
	lid.Parent = folder
	weld(body, lid)

	local pocket = makePart("BagPocket", Vector3.new(0.85, 0.55, 0.25), Color3.fromRGB(80, 200, 255), Enum.Material.Neon)
	pocket.Transparency = 0.15
	pocket.CFrame = body.CFrame * CFrame.new(0, -0.15, -0.4)
	pocket.Parent = folder
	weld(body, pocket)

	-- Bulle décorative sur le rabat
	local bubble = makePart("BagBubble", Vector3.new(0.45, 0.45, 0.45), Color3.fromRGB(160, 230, 255), Enum.Material.Glass)
	bubble.Transparency = 0.35
	bubble.Shape = Enum.PartType.Ball
	bubble.CFrame = lid.CFrame * CFrame.new(0, 0.15, -0.2)
	bubble.Parent = folder
	weld(lid, bubble)

	local strapL = makePart("StrapL", Vector3.new(0.12, 0.9, 0.12), Color3.fromRGB(40, 60, 110))
	strapL.CFrame = body.CFrame * CFrame.new(-0.4, 0.35, 0.35)
	strapL.Parent = folder
	weld(body, strapL)

	local strapR = makePart("StrapR", Vector3.new(0.12, 0.9, 0.12), Color3.fromRGB(40, 60, 110))
	strapR.CFrame = body.CFrame * CFrame.new(0.4, 0.35, 0.35)
	strapR.Parent = folder
	weld(body, strapR)

	local player = Players:GetPlayerFromCharacter(character)
	createCountDisplay(folder, body, player)
end

-- Réattache avec le bon offset (après équipement / retrait des ailes).
function BackpackVisual.Refresh(character: Model)
	BackpackVisual.Attach(character)
end

return BackpackVisual
