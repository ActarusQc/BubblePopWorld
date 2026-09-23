-- À exécuter UNE FOIS en mode édition dans la barre de commandes de Roblox Studio.
-- Sources attendues dans Workspace : wizard_hat et blue_jeweled_crown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local shopAssets = ReplicatedStorage:FindFirstChild("ShopAssets") or Instance.new("Folder")
shopAssets.Name = "ShopAssets"
shopAssets.Parent = ReplicatedStorage

local hats = shopAssets:FindFirstChild("Hats") or Instance.new("Folder")
hats.Name = "Hats"
hats.Parent = shopAssets

local sourceFolder = ServerStorage:FindFirstChild("HatSourceModels") or Instance.new("Folder")
sourceFolder.Name = "HatSourceModels"
sourceFolder.Parent = ServerStorage

local definitions = {
	{
		SourceName = "wizard_hat",
		AccessoryName = "WizardHatAccessory",
		ShopItemId = "WizardHat",
		TargetWidth = 2.05,
		AttachmentHeightRatio = -0.42,
	},
	{
		SourceName = "blue_jeweled_crown",
		AccessoryName = "BlueJeweledCrownAccessory",
		ShopItemId = "BlueJeweledCrown",
		TargetWidth = 1.85,
		AttachmentHeightRatio = -0.34,
	},
}

local function findSource(name)
	return workspace:FindFirstChild(name) or sourceFolder:FindFirstChild(name)
end

local function install(def)
	local source = findSource(def.SourceName)
	assert(source, ("Le modèle '%s' est introuvable dans Workspace."):format(def.SourceName))
	local sourceMesh = if source:IsA("MeshPart") then source else source:FindFirstChildWhichIsA("MeshPart", true)
	assert(sourceMesh, ("Aucun MeshPart trouvé dans '%s'."):format(def.SourceName))

	local old = hats:FindFirstChild(def.AccessoryName)
	if old then old:Destroy() end

	local accessory = Instance.new("Accessory")
	accessory.Name = def.AccessoryName
	accessory.AccessoryType = Enum.AccessoryType.Hat
	accessory:SetAttribute("ShopItemId", def.ShopItemId)
	accessory:SetAttribute("FitVersion", 1)

	local handle = sourceMesh:Clone()
	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	for _, child in handle:GetDescendants() do
		if child:IsA("Attachment") or child:IsA("Weld") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	local horizontalSize = math.max(handle.Size.X, handle.Size.Z)
	assert(horizontalSize > 0, ("Dimensions invalides pour '%s'."):format(def.SourceName))
	handle.Size *= def.TargetWidth / horizontalSize
	local originalSize = handle:FindFirstChild("OriginalSize")
	if originalSize and originalSize:IsA("Vector3Value") then originalSize.Value = handle.Size end

	local attachment = Instance.new("Attachment")
	attachment.Name = "HatAttachment"
	attachment.Position = Vector3.new(0, handle.Size.Y * def.AttachmentHeightRatio, 0)
	attachment.Parent = handle
	handle.Parent = accessory
	accessory.Parent = hats

	if source.Parent ~= sourceFolder then source.Parent = sourceFolder end
	print(("Créé : ReplicatedStorage/ShopAssets/Hats/%s | taille %s"):format(def.AccessoryName, tostring(handle.Size)))
end

for _, def in definitions do install(def) end
print("Wizard Hat et Blue Jeweled Crown sont prêts pour la boutique.")
