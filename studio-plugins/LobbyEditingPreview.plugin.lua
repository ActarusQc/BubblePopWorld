-- Plugin Studio local (optionnel).
-- Installation : copier ce fichier dans
--   %LOCALAPPDATA%\Roblox\Plugins\LobbyEditingPreview.lua
-- Puis redémarrer Studio. Boutons dans l'onglet Plugins.
-- Prérequis : Rojo connecté (GameConfig dans ReplicatedStorage.Shared).

local toolbar = plugin:CreateToolbar("BubblePopWorld")
local createBtn = toolbar:CreateButton(
	"Lobby Preview",
	"Crée LobbyEditingPreview pour placer SellKiosk",
	"rbxassetid://6031094678"
)
local removeBtn = toolbar:CreateButton(
	"Clear Preview",
	"Supprime LobbyEditingPreview",
	"rbxassetid://6031094678"
)

local function getModule()
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	if not shared then
		warn("[LobbyEditingPreview] ReplicatedStorage.Shared introuvable — lance rojo serve + Connect.")
		return nil
	end
	local mod = shared:FindFirstChild("LobbyEditingPreview")
	if not mod then
		warn("[LobbyEditingPreview] Module LobbyEditingPreview manquant.")
		return nil
	end
	return require(mod)
end

createBtn.Click:Connect(function()
	local M = getModule()
	if M then
		M.CreateLobbyEditingPreview()
	end
end)

removeBtn.Click:Connect(function()
	local M = getModule()
	if M then
		M.RemoveLobbyEditingPreview()
	end
end)
