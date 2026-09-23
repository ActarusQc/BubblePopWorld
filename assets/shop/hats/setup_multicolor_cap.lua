-- À exécuter une seule fois dans la barre de commandes de Roblox Studio.
-- Le modèle Tripo original reste intact dans Workspace.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sourceModel = workspace:FindFirstChild("multicolor cap")
assert(sourceModel and sourceModel:IsA("Model"), "Le Model 'multicolor cap' doit être dans Workspace.")

local sourceMesh = sourceModel:FindFirstChildWhichIsA("MeshPart", true)
assert(sourceMesh, "Aucun MeshPart trouvé dans 'multicolor cap'.")

local shopAssets = ReplicatedStorage:FindFirstChild("ShopAssets")
if not shopAssets then
	shopAssets = Instance.new("Folder")
	shopAssets.Name = "ShopAssets"
	shopAssets.Parent = ReplicatedStorage
end

local hats = shopAssets:FindFirstChild("Hats")
if not hats then
	hats = Instance.new("Folder")
	hats.Name = "Hats"
	hats.Parent = shopAssets
end

local accessoryName = "MulticolorCapAccessory"
assert(not hats:FindFirstChild(accessoryName), accessoryName .. " existe déjà dans ReplicatedStorage/ShopAssets/Hats.")

local accessory = Instance.new("Accessory")
accessory.Name = accessoryName
accessory.AccessoryType = Enum.AccessoryType.Hat

local handle = sourceMesh:Clone()
handle.Name = "Handle"
handle.Anchored = false
handle.CanCollide = false
handle.CanTouch = false
handle.CanQuery = false
handle.Massless = true

-- Tripo importe ce modèle trop grand. Cette valeur donne une taille de départ
-- adaptée à une tête Roblox et pourra être affinée après le premier essai.
handle.Size = handle.Size * 0.48
local originalSize = handle:FindFirstChild("OriginalSize")
if originalSize and originalSize:IsA("Vector3Value") then
	originalSize.Value = handle.Size
end

-- Le point d'attache est placé dans l'ouverture, près du bas de la calotte.
local hatAttachment = Instance.new("Attachment")
hatAttachment.Name = "HatAttachment"
hatAttachment.Position = Vector3.new(0, -handle.Size.Y * 0.18, 0)
hatAttachment.Parent = handle

handle.Parent = accessory
accessory.Parent = hats

print("Créé : ReplicatedStorage/ShopAssets/Hats/" .. accessoryName)
print("Le modèle Tripo original a été conservé dans Workspace.")
