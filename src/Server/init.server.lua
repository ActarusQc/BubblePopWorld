--!strict
-- Point d'entrée serveur : ordre de démarrage explicite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
require(ReplicatedStorage:WaitForChild("Shared").Remotes) -- crée les remotes en premier

local services = {
	require(script.DataService),
	require(script.BackpackService),
	require(script.ZoneService),
	require(script.GlobalCounterService),
	require(script.ComboService),
	require(script.AmbianceService),
	require(script.BubbleService),
	require(script.ToolService),
	require(script.DropService),
	require(script.ChestService),
	require(script.ShopService),
	require(script.ItemShopBuilder),
	require(script.LeaderboardService),
	require(script.AdminService),
}

for _, service in ipairs(services) do
	local ok, err = pcall(service.Start)
	if not ok then warn("[BPW] échec du démarrage d'un service: " .. tostring(err)) end
end

-- Validations zones / musique (dev) — n'interrompt pas le serveur.
do
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local ok, tests = pcall(function()
		return require(Shared.ZoneAccessTests)
	end)
	if ok and tests and tests.Run then
		tests.Run()
	end
	local okMusic, musicTests = pcall(function()
		return require(Shared.MusicConfigTests)
	end)
	if okMusic and musicTests and musicTests.Run then
		musicTests.Run()
	end
	local okLb, lbTests = pcall(function()
		return require(Shared.LeaderboardTests)
	end)
	if okLb and lbTests and lbTests.Run then
		lbTests.Run()
	end
end

print("[Bubble Pop World] serveur prêt.")
