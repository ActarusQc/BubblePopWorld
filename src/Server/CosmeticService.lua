--!strict
-- Accessoires internes à l'expérience.
-- Les modèles portables sont créés dans Studio puis rangés dans
-- ReplicatedStorage/ShopAssets/Hats. Le serveur ne fabrique plus de chapeau de secours.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)

local CosmeticService = {}
local EQUIPPED_NAME = "BPW_EquippedHat"
local EQUIPPED_SHIRT_NAME = "BPW_EquippedShirt"
local HAIR_BACKUP_NAME = "BPW_HairBackup"
local SHIRT_BACKUP_NAME = "BPW_ShirtBackup"
local HAT_TEMPLATES = {
	Cap = "MulticolorCapAccessory",
	FrogHat = "FrogHatAccessory",
	WizardHat = "WizardHatAccessory",
	BlueJeweledCrown = "BlueJeweledCrownAccessory",
}
local SHIRT_TEMPLATES = {
	BlackNeonShirt = "BlackNeon", BlueBubbleShirt = "BlueBubble", CosmicDragonShirt = "CosmicDragonShirt",
	LavandeStarShirt = "LavandeStar", MintWavesShirt = "MintWaves", NavyBubbleShirt = "Navy_Bubble",
	OrangeSunsetShirt = "OrangeSunset", RedStripesShirt = "RedStripes", SkyBlueShirt = "SkyBlue",
	YellowSmileShirt = "YellowSmile",
}

local function isHairAccessory(instance: Instance): boolean
	if not instance:IsA("Accessory") then
		return false
	end
	if instance.AccessoryType == Enum.AccessoryType.Hair then
		return true
	end
	local handle = instance:FindFirstChild("Handle")
	return handle ~= nil and handle:FindFirstChild("HairAttachment") ~= nil
end

local function backupAndRemoveHair(player: Player, character: Model)
	local previous = player:FindFirstChild(HAIR_BACKUP_NAME)
	local backup: Folder
	local shouldClone = previous == nil
	if previous and previous:IsA("Folder") then
		backup = previous
	else
		backup = Instance.new("Folder")
		backup.Name = HAIR_BACKUP_NAME
		backup.Parent = player
	end
	for _, child in character:GetChildren() do
		if isHairAccessory(child) then
			if shouldClone then
				local clone = child:Clone()
				clone.Parent = backup
			end
			child:Destroy()
		end
	end
end

local function restoreHair(player: Player, character: Model)
	local backup = player:FindFirstChild(HAIR_BACKUP_NAME)
	if not backup then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, child in backup:GetChildren() do
			if child:IsA("Accessory") then
				humanoid:AddAccessory(child:Clone())
			end
		end
	end
	backup:Destroy()
end

local function findHatTemplate(name: string): Accessory?
	local shopAssets = ReplicatedStorage:FindFirstChild("ShopAssets")
	local hats = if shopAssets then shopAssets:FindFirstChild("Hats") else nil
	local template = if hats then hats:FindFirstChild(name) else nil
	if template and template:IsA("Accessory") and template:FindFirstChild("Handle") then
		return template
	end
	return nil
end

local function findShirtTemplate(name: string): Shirt?
	local shopAssets = ReplicatedStorage:FindFirstChild("ShopAssets")
	local shirts = if shopAssets then shopAssets:FindFirstChild("Shirts") else nil
	local template = if shirts then shirts:FindFirstChild(name, true) else nil
	return if template and template:IsA("Shirt") then template else nil
end

local function restoreOriginalShirt(player: Player, character: Model)
	local backup = player:FindFirstChild(SHIRT_BACKUP_NAME)
	if backup and backup:IsA("Shirt") then
		backup:Clone().Parent = character
		backup:Destroy()
	end
end

local function equipShirt(player: Player, character: Model, shopItemId: string)
	local def = Config.ShopItems[shopItemId]
	local templateName = if def and def.Kind == "Cosmetic" and def.Slot == "Shirt" then def.ModelName else SHIRT_TEMPLATES[shopItemId]
	if not templateName then return end
	local template = findShirtTemplate(templateName)
	if not template then
		warn(("[CosmeticService] Chandail manquant : ReplicatedStorage/ShopAssets/Shirts/%s"):format(templateName))
		return
	end
	local backup = player:FindFirstChild(SHIRT_BACKUP_NAME)
	for _, child in character:GetChildren() do
		if child:IsA("Shirt") then
			if not backup and child.Name ~= EQUIPPED_SHIRT_NAME then
				backup = child:Clone()
				backup.Name = SHIRT_BACKUP_NAME
				backup.Parent = player
			end
			child:Destroy()
		end
	end
	local shirt = template:Clone()
	shirt.Name = EQUIPPED_SHIRT_NAME
	shirt:SetAttribute("ShopItemId", shopItemId)
	shirt.Parent = character
end

local function equipHat(player: Player, character: Model, shopItemId: string)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local templateName = HAT_TEMPLATES[shopItemId]
	if not templateName then
		warn(("[CosmeticService] Chapeau inconnu : %s"):format(shopItemId))
		return
	end
	local template = findHatTemplate(templateName)
	if not template then
		warn(("[CosmeticService] Accessoire manquant : ReplicatedStorage/ShopAssets/Hats/%s"):format(templateName))
		return
	end
	backupAndRemoveHair(player, character)
	local accessory = template:Clone()
	accessory.Name = EQUIPPED_NAME
	accessory:SetAttribute("ShopItemId", shopItemId)
	humanoid:AddAccessory(accessory)
end

function CosmeticService.Refresh(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild(EQUIPPED_NAME)
	if old then old:Destroy() end
	local oldShirt = character:FindFirstChild(EQUIPPED_SHIRT_NAME)
	if oldShirt then oldShirt:Destroy() end
	local profile = DataService.Get(player)
	local hat = profile and profile.EquippedCosmetics and profile.EquippedCosmetics.Hat
	if type(hat) == "string" and HAT_TEMPLATES[hat] then
		equipHat(player, character, hat)
	else
		restoreHair(player, character)
	end
	local shirt = profile and profile.EquippedCosmetics and profile.EquippedCosmetics.Shirt
	local shirtDef = if type(shirt) == "string" then Config.ShopItems[shirt] else nil
	if type(shirt) == "string" and shirtDef and shirtDef.Kind == "Cosmetic" and shirtDef.Slot == "Shirt" then
		equipShirt(player, character, shirt)
	else
		restoreOriginalShirt(player, character)
	end
	PetService.Refresh(player)
end

function CosmeticService.Start()
	local function bind(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				for _ = 1, 50 do
					if DataService.Get(player) then
						break
					end
					task.wait(0.1)
				end
				CosmeticService.Refresh(player)
			end)
		end)
		if player.Character then
			task.defer(CosmeticService.Refresh, player)
		end
	end
	for _, player in Players:GetPlayers() do
		bind(player)
	end
	Players.PlayerAdded:Connect(bind)
end

return CosmeticService
