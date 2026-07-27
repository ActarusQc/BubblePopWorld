-- Plugin Studio local (optionnel).
-- Installation : copier ce fichier dans
--   %LOCALAPPDATA%\Roblox\Plugins\LobbyEditingPreview.lua
-- Puis redémarrer Studio. Boutons dans l'onglet Plugins.
-- Prérequis : Rojo connecté (modules dans ReplicatedStorage.Shared).

local toolbar = plugin:CreateToolbar("BubblePopWorld")

local lobbyCreateBtn = toolbar:CreateButton(
	"Lobby Preview",
	"Crée LobbyEditingPreview pour placer SellKiosk",
	"rbxassetid://6031094678"
)
local lobbyRemoveBtn = toolbar:CreateButton(
	"Clear Lobby Preview",
	"Supprime LobbyEditingPreview",
	"rbxassetid://6031094678"
)

local summerCreateBtn = toolbar:CreateButton(
	"Create/Refresh Summer Preview",
	"Crée SummerZonePreview (Edit) — ne touche pas SummerZoneDecor",
	"rbxassetid://6031097226"
)
local summerRemoveBtn = toolbar:CreateButton(
	"Remove Summer Preview",
	"Supprime SummerZonePreview — conserve SummerZoneDecor",
	"rbxassetid://6031097226"
)

local function getSharedModule(name)
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	if not shared then
		warn("[" .. name .. "] ReplicatedStorage.Shared introuvable — lance rojo serve + Connect.")
		return nil
	end
	local mod = shared:FindFirstChild(name)
	if not mod then
		warn("[" .. name .. "] Module manquant dans Shared.")
		return nil
	end
	return require(mod)
end

lobbyCreateBtn.Click:Connect(function()
	local M = getSharedModule("LobbyEditingPreview")
	if M then
		M.CreateLobbyEditingPreview()
	end
end)

lobbyRemoveBtn.Click:Connect(function()
	local M = getSharedModule("LobbyEditingPreview")
	if M then
		M.RemoveLobbyEditingPreview()
	end
end)

summerCreateBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneEditingPreview")
	if M then
		M.CreateSummerZonePreview()
	end
end)

summerRemoveBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneEditingPreview")
	if M then
		M.RemoveSummerZonePreview()
	end
end)
