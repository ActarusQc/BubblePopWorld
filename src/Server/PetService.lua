--!strict
-- Clone et suit le pet ToutouChien aux pieds du joueur.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local PetFollowLogic = require(Shared.PetFollowLogic)
local ZoneDefs = require(Shared.ZoneDefs)
local DataService = require(script.Parent.DataService)

local PetService = {}
local PET_FOLDER_NAME = PetFollowLogic.FolderName
local TEMPLATE_FOLDER_NAME = "PetTemplates"
local FOLLOWER_PREFIX = "BPW_Pet_"
local PET_ID = "ToutouChien"
local PET_GROUP = PetFollowLogic.CollisionGroup

local template: Model? = nil
local followers: { [Player]: Model } = {}

local function ensurePetCollisionGroup()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PET_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(PET_GROUP, "Default", false)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(PET_GROUP, PET_GROUP, false)
	end)
	for _, t in ipairs(ZoneDefs.GetAccessThresholds()) do
		local accessName = ZoneDefs.GetAccessGroupName(t)
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(PET_GROUP, accessName, false)
		end)
	end
	for _, def in ipairs(ZoneDefs.GetGatedZones()) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(PET_GROUP, ZoneDefs.GateGroupName(def.Id), false)
		end)
	end
end

local function neutralizePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part:SetAttribute("BPWPetPart", true)
	pcall(function()
		part.CollisionGroup = PET_GROUP
	end)
end

local function stripControllers(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Humanoid")
			or descendant:IsA("Animator")
			or descendant:IsA("AnimationController")
			or descendant:IsA("ControllerManager")
		then
			descendant:Destroy()
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		end
	end
end

local function scaleModelToHeight(model: Model, targetHeight: number)
	local _, size = model:GetBoundingBox()
	if size.Y <= 0.05 then
		return
	end
	local factor = targetHeight / size.Y
	if math.abs(factor - 1) <= 0.08 then
		return
	end
	local scaled = pcall(function()
		model:ScaleTo(model:GetScale() * factor)
	end)
	_, size = model:GetBoundingBox()
	if scaled and math.abs(size.Y - targetHeight) <= 0.25 then
		return
	end
	local retry = targetHeight / math.max(size.Y, 0.05)
	local pivot = model:GetPivot()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local offset = pivot:PointToObjectSpace(descendant.Position)
			descendant.Size *= retry
			descendant.CFrame = pivot * CFrame.new(offset * retry)
		end
	end
end

local function petFolder(): Folder
	local folder = Workspace:FindFirstChild(PET_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = PET_FOLDER_NAME
	created.Parent = Workspace
	return created
end

local function stashTemplates(): Folder
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = TEMPLATE_FOLDER_NAME
	created.Parent = ReplicatedStorage
	return created
end

local function asModel(source: Instance): Model?
	if source:IsA("Model") then
		return source
	end
	if source:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = source.Name
		model.Parent = source.Parent
		source.Parent = model
		return model
	end
	if source:IsA("Folder") then
		local model = Instance.new("Model")
		model.Name = if source.Name ~= "" then source.Name else PET_ID
		model.Parent = source.Parent
		for _, child in ipairs(source:GetChildren()) do
			child.Parent = model
		end
		source:Destroy()
		return model
	end
	return nil
end

local function findNamed(root: Instance): Instance?
	local direct = root:FindFirstChild(PET_ID)
	if direct then
		return direct
	end
	return root:FindFirstChild(PET_ID, true)
end

local function captureTemplate(): Model?
	if template and template.Parent then
		return template
	end
	local stored = stashTemplates():FindFirstChild(PET_ID)
	if stored then
		local model = asModel(stored)
		if model then
			pcall(function()
				if math.abs(model:GetScale() - 1) > 0.01 then
					model:ScaleTo(1)
				end
			end)
			template = model
			return model
		end
	end
	local found = findNamed(Workspace) or findNamed(ReplicatedStorage) or findNamed(ServerStorage)
	if not found then
		warn("[PetService] modèle ToutouChien introuvable")
		return nil
	end
	local model = asModel(found)
	if not model then
		return nil
	end
	model.Archivable = true
	for _, descendant in ipairs(model:GetDescendants()) do
		descendant.Archivable = true
	end
	local clone = model:Clone()
	clone.Name = PET_ID
	clone.Parent = stashTemplates()
	template = clone
	stripControllers(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			neutralizePart(descendant)
		end
	end
	return template
end

local function prepareClone(model: Model)
	stripControllers(model)
	scaleModelToHeight(model, PetFollowLogic.TargetHeight)
	local boxCFrame, boxSize = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(boxCFrame.Position - Vector3.new(0, boxSize.Y * 0.5, 0))
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			neutralizePart(descendant)
		end
	end
end

local function destroyFollower(player: Player)
	local existing = followers[player]
	if existing then
		existing:Destroy()
		followers[player] = nil
	end
	local leftover = petFolder():FindFirstChild(FOLLOWER_PREFIX .. tostring(player.UserId))
	if leftover then
		leftover:Destroy()
	end
	local character = player.Character
	local onChar = character and character:FindFirstChild(FOLLOWER_PREFIX .. tostring(player.UserId))
	if onChar then
		onChar:Destroy()
	end
end

function PetService.Refresh(player: Player)
	destroyFollower(player)
	local profile = DataService.Get(player)
	local equipped = profile and profile.EquippedCosmetics and profile.EquippedCosmetics.Pet
	if equipped ~= PET_ID then
		return
	end
	local source = captureTemplate()
	if not source then
		return
	end
	local clone = source:Clone()
	clone.Name = FOLLOWER_PREFIX .. tostring(player.UserId)
	prepareClone(clone)
	clone.Parent = petFolder()
	followers[player] = clone
end

function PetService.GrantAndEquip(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if Config.ShopItems[PET_ID] == nil then
		return
	end
	if type(profile.OwnedItems) ~= "table" then
		profile.OwnedItems = {}
	end
	profile.OwnedItems[PET_ID] = true
	if type(profile.EquippedCosmetics) ~= "table" then
		profile.EquippedCosmetics = { Hat = "", Shirt = "", Pet = "" }
	end
	profile.EquippedCosmetics.Pet = PET_ID
	DataService.Push(player)
	PetService.Refresh(player)
end

function PetService.Start()
	ensurePetCollisionGroup()
	captureTemplate()
	RunService.Heartbeat:Connect(function()
		for player, model in pairs(followers) do
			if not model.Parent then
				followers[player] = nil
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
			if not root or not root:IsA("BasePart") or not humanoid then
				continue
			end
			local feetY = PetFollowLogic.FeetY(root.Position, humanoid.HipHeight, root.Size.Y)
			model:PivotTo(PetFollowLogic.FollowCFrame(root.CFrame, feetY, 0))
		end
	end)
	Players.PlayerRemoving:Connect(destroyFollower)
end

return PetService
