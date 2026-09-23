-- À exécuter en mode édition dans la barre de commandes de Roblox Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local sourceModel = workspace:FindFirstChild("frog_hat")
assert(sourceModel and sourceModel:IsA("Model"), "Le Model 'frog_hat' doit être dans Workspace.")
local sourceMesh = sourceModel:FindFirstChildWhichIsA("MeshPart", true)
assert(sourceMesh, "Aucun MeshPart trouvé dans 'frog_hat'.")

local shopAssets = ReplicatedStorage:FindFirstChild("ShopAssets") or Instance.new("Folder")
shopAssets.Name = "ShopAssets"
shopAssets.Parent = ReplicatedStorage
local hats = shopAssets:FindFirstChild("Hats") or Instance.new("Folder")
hats.Name = "Hats"
hats.Parent = shopAssets
assert(not hats:FindFirstChild("FrogHatAccessory"), "FrogHatAccessory existe déjà.")

local accessory = Instance.new("Accessory")
accessory.Name = "FrogHatAccessory"
accessory.AccessoryType = Enum.AccessoryType.Hat
accessory:SetAttribute("ShopItemId", "frog_hat")
accessory:SetAttribute("FitVersion", 1)

local handle = sourceMesh:Clone()
handle.Name = "Handle"
handle.Anchored = false
handle.CanCollide = false
handle.CanTouch = false
handle.CanQuery = false
handle.Massless = true

-- Normalisation automatique : le plus grand axe horizontal atteint 1,9 stud.
local horizontalSize = math.max(handle.Size.X, handle.Size.Z)
assert(horizontalSize > 0, "Dimensions invalides pour frog_hat.")
handle.Size *= 1.9 / horizontalSize
local originalSize = handle:FindFirstChild("OriginalSize")
if originalSize and originalSize:IsA("Vector3Value") then
	originalSize.Value = handle.Size
end

local attachment = Instance.new("Attachment")
attachment.Name = "HatAttachment"
attachment.Position = Vector3.new(0, -handle.Size.Y * 0.18, 0)
attachment.Parent = handle
handle.Parent = accessory
accessory.Parent = hats

local sourceFolder = ServerStorage:FindFirstChild("HatSourceModels") or Instance.new("Folder")
sourceFolder.Name = "HatSourceModels"
sourceFolder.Parent = ServerStorage
sourceModel.Parent = sourceFolder

print("FrogHatAccessory créé :", handle.Size)
print("frog_hat archivé dans ServerStorage/HatSourceModels")
