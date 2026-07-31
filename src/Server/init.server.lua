--!strict
-- Point d'entrée serveur : ordre de démarrage explicite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
require(ReplicatedStorage:WaitForChild("Shared").Remotes) -- crée les remotes en premier

local GameAnalyticsService = require(script.GameAnalyticsService)
local DataService = require(script.DataService)

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
	local okLights, lightsTests = pcall(function()
		return require(Shared.SummerZoneStringLightsTests)
	end)
	if okLights and lightsTests and lightsTests.Run then
		lightsTests.Run()
	end
	local okTravel, travelTests = pcall(function()
		return require(Shared.TravelConfigTests)
	end)
	if okTravel and travelTests and travelTests.Run then
		travelTests.Run()
	end
	local okBagValue, bagValueTests = pcall(function()
		return require(Shared.BubbleValueTests)
	end)
	if okBagValue and bagValueTests and bagValueTests.Run then
		bagValueTests.Run()
	end
	local okZoneGameplay, zoneGameplayTests = pcall(function()
		return require(Shared.ZoneGameplayTests)
	end)
	if okZoneGameplay and zoneGameplayTests and zoneGameplayTests.Run then
		zoneGameplayTests.Run()
	end
	local okDecorCfg, decorCfgTests = pcall(function()
		return require(Shared.SummerDecorConfigTests)
	end)
	if okDecorCfg and decorCfgTests and decorCfgTests.Run then
		decorCfgTests.Run()
	end
	local okDecorSec, decorSecTests = pcall(function()
		return require(Shared.SummerDecorSecurityTests)
	end)
	if okDecorSec and decorSecTests and decorSecTests.Run then
		decorSecTests.Run()
	end
	local okPropSplit, propSplitTests = pcall(function()
		return require(Shared.SummerDecorPropSplitTests)
	end)
	if okPropSplit and propSplitTests and propSplitTests.Run then
		propSplitTests.Run()
	end
	local okScene, sceneTests = pcall(function()
		return require(Shared.SummerDecorSceneClassifierTests)
	end)
	if okScene and sceneTests and sceneTests.Run then
		sceneTests.Run()
	end
	local okAnalyticsCfg, analyticsCfgTests = pcall(function()
		return require(Shared.AnalyticsConfigTests)
	end)
	if okAnalyticsCfg and analyticsCfgTests and analyticsCfgTests.Run then
		analyticsCfgTests.Run()
	end
	local okShopCatalog, shopCatalogTests = pcall(function()
		return require(Shared.ShopCatalogTests)
	end)
	if okShopCatalog and shopCatalogTests and shopCatalogTests.Run then
		shopCatalogTests.Run()
	end
	local okShopBrowse, shopBrowseTests = pcall(function()
		return require(Shared.ShopBrowseLogicTests)
	end)
	if okShopBrowse and shopBrowseTests and shopBrowseTests.Run then
		shopBrowseTests.Run()
	end
	local okShopLayout, shopLayoutTests = pcall(function()
		return require(Shared.ShopBrowseLayoutTests)
	end)
	if okShopLayout and shopLayoutTests and shopLayoutTests.Run then
		shopLayoutTests.Run()
	end
	local okShopViewport, shopViewportTests = pcall(function()
		return require(Shared.ShopViewportModelsTests)
	end)
	if okShopViewport and shopViewportTests and shopViewportTests.Run then
		shopViewportTests.Run()
	end
	local okItemShopVisual, itemShopVisualTests = pcall(function()
		return require(Shared.ItemShopVisualTests)
	end)
	if okItemShopVisual and itemShopVisualTests and itemShopVisualTests.Run then
		itemShopVisualTests.Run()
	end
	local okItemSpawn, itemSpawnTests = pcall(function()
		return require(Shared.ItemSpawnTests)
	end)
	if okItemSpawn and itemSpawnTests and itemSpawnTests.Run then
		itemSpawnTests.Run()
	end
	local okDsAnalytics, dsAnalyticsTests = pcall(function()
		return require(script.DataServiceAnalyticsTests)
	end)
	if okDsAnalytics and dsAnalyticsTests and dsAnalyticsTests.Run then
		dsAnalyticsTests.Run()
	end
	local okGas, gasTests = pcall(function()
		return require(script.GameAnalyticsServiceTests)
	end)
	if okGas and gasTests and gasTests.Run then
		gasTests.Run()
	end
	local okShopService, shopServiceTests = pcall(function()
		return require(script.ShopServiceTests)
	end)
	if okShopService and shopServiceTests and shopServiceTests.Run then
		shopServiceTests.Run()
	end
end

print("[Bubble Pop World] serveur prêt.")
