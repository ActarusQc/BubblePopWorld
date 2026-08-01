--!strict
-- Point d'entrée serveur : ordre de démarrage explicite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
require(ReplicatedStorage:WaitForChild("Shared").Remotes) -- crée les remotes en premier

local GameAnalyticsService = require(script.GameAnalyticsService)
local DataService = require(script.DataService)

local Shared = ReplicatedStorage:WaitForChild("Shared")

local function runSuite(label: string, loader: () -> any)
	local requireOk, testsOrErr = pcall(loader)
	if not requireOk then
		warn(string.format("[%s] FAIL: require error: %s", label, tostring(testsOrErr)))
		return
	end
	local tests = testsOrErr
	if type(tests) ~= "table" or type(tests.Run) ~= "function" then
		warn(string.format("[%s] FAIL: missing Run()", label))
		return
	end
	local runOk, runErr = pcall(tests.Run)
	if not runOk then
		warn(string.format("[%s] FAIL: suite error: %s", label, tostring(runErr)))
	end
end

-- Suites analytics destructives (FlushAllPlayers) avant toute session joueur réelle.
if RunService:IsStudio() then
	runSuite("AnalyticsConfigTests", function()
		return require(Shared.AnalyticsConfigTests)
	end)
	runSuite("DataServiceAnalyticsTests", function()
		return require(script.DataServiceAnalyticsTests)
	end)
	runSuite("GameAnalyticsServiceTests", function()
		return require(script.GameAnalyticsServiceTests)
	end)
end

-- Analytics avant DataService (InitPlayer / flush à la déconnexion).
do
	local ok, err = pcall(GameAnalyticsService.Start)
	if not ok then
		warn("[BPW] échec GameAnalyticsService: " .. tostring(err))
	end
end

local services = {
	DataService,
	require(script.BackpackService),
	require(script.ZoneService),
	require(script.TravelService),
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

-- Validations (dev) — hors analytics (déjà exécutées avant Start en Studio).
do
	runSuite("ZoneAccessTests", function()
		return require(Shared.ZoneAccessTests)
	end)
	runSuite("MusicConfigTests", function()
		return require(Shared.MusicConfigTests)
	end)
	runSuite("LeaderboardTests", function()
		return require(Shared.LeaderboardTests)
	end)
	runSuite("SummerZoneStringLightsTests", function()
		return require(Shared.SummerZoneStringLightsTests)
	end)
	runSuite("TravelConfigTests", function()
		return require(Shared.TravelConfigTests)
	end)
	runSuite("BubbleValueTests", function()
		return require(Shared.BubbleValueTests)
	end)
	runSuite("ZoneGameplayTests", function()
		return require(Shared.ZoneGameplayTests)
	end)
	runSuite("SummerDecorConfigTests", function()
		return require(Shared.SummerDecorConfigTests)
	end)
	runSuite("SummerDecorSecurityTests", function()
		return require(Shared.SummerDecorSecurityTests)
	end)
	runSuite("SummerDecorPropSplitTests", function()
		return require(Shared.SummerDecorPropSplitTests)
	end)
	runSuite("SummerDecorSceneClassifierTests", function()
		return require(Shared.SummerDecorSceneClassifierTests)
	end)
	runSuite("ShopCatalogTests", function()
		return require(Shared.ShopCatalogTests)
	end)
	runSuite("ShopBrowseLogicTests", function()
		return require(Shared.ShopBrowseLogicTests)
	end)
	runSuite("ShopBrowseLayoutTests", function()
		return require(Shared.ShopBrowseLayoutTests)
	end)
	runSuite("ShopViewportModelsTests", function()
		return require(Shared.ShopViewportModelsTests)
	end)
	runSuite("ItemShopVisualTests", function()
		return require(Shared.ItemShopVisualTests)
	end)
	runSuite("ItemSpawnTests", function()
		return require(Shared.ItemSpawnTests)
	end)
	runSuite("ShopServiceTests", function()
		return require(script.ShopServiceTests)
	end)
end

print("[Bubble Pop World] serveur prêt.")
