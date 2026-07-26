--!strict
-- Sac à dos purement visuel (ne touche pas à la logique BackpackService).

local BackpackVisual = {}

local BAG_NAME = "BPW_Backpack"

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

function BackpackVisual.Detach(character: Model)
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
end

-- Réattache avec le bon offset (après équipement / retrait des ailes).
function BackpackVisual.Refresh(character: Model)
	BackpackVisual.Attach(character)
end

return BackpackVisual
