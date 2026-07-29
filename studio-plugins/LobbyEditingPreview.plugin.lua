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

local lightsCreateBtn = toolbar:CreateButton(
	"Add Summer String Lights",
	"Place poteaux + guirlandes dans SummerZoneDecor (Edit) — remplace seulement les lumières générées",
	"rbxassetid://6031068421"
)
local lightsRefreshBtn = toolbar:CreateButton(
	"Refresh Summer String Lights",
	"Repose les poteaux au sol, corrige leur hauteur et rebâtit les guirlandes pendantes",
	"rbxassetid://6031068421"
)
local lightsRemoveBtn = toolbar:CreateButton(
	"Remove Summer String Lights",
	"Supprime uniquement LightPosts/StringLights générés — conserve le reste de SummerZoneDecor",
	"rbxassetid://6031068421"
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

lightsCreateBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneStringLights")
	if M then
		M.CreateSummerPerimeterLights()
	end
end)

lightsRefreshBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneStringLights")
	if M then
		M.RefreshSummerPerimeterLights()
	end
end)

lightsRemoveBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneStringLights")
	if M then
		M.RemoveSummerPerimeterLights()
	end
end)
