--!strict
-- Point d'entrée serveur : ordre de démarrage explicite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
require(ReplicatedStorage:WaitForChild("Shared").Remotes) -- crée les remotes en premier

local GameAnalyticsService = require(script.GameAnalyticsService)
local DataService = require(script.DataService)

local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Observateur Studio AVANT builders : qui écrit CFrame/Size sur l'ancre transit.
do
	local watchOk, watchErr = pcall(function()
		require(script.TransitAnchorWatch).Install()
	end)
	if not watchOk then
		warn("[TransitAnchorWatch] install failed:", tostring(watchErr))
	end
end

-- Preuve d'exécution du nouveau code (recherche cette ligne dans F5).
print("[RearHubManualCollision] CODE VERSION " .. require(Shared.RearHubManualRig).CODE_VERSION)

-- SpawnLocation AVANT les suites Studio / Start : CharacterAutoLoads reste true
-- (le désactiver casse Test/F5 : aucun Player injecté). Filet de sécurité ensuite.
do
	local OnboardingConfig = require(Shared.OnboardingConfig)
	if OnboardingConfig.EarlySpawnLocationBootstrap then
		local ok, err = pcall(function()
			require(script.ZoneService).EnsureEarlySpawnLocation()
			require(script.HubSpawnService).PrepareForPlay()
		end)
		if not ok then
			warn("[BPW] EnsureEarlySpawnLocation échoué: " .. tostring(err))
		end
	end
end

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
	-- Spawn manuel hub (avant teleports Zone / CharacterAdded rivaux).
	require(script.HubSpawnService),
	-- Après DataService / GameAnalyticsService, avant ZoneService (spawn première session).
	require(script.OnboardingService),
	require(script.BackpackService),
	require(script.ZoneService),
	require(script.TravelService),
	require(script.GlobalCounterService),
	require(script.ComboService),
	require(script.AmbianceService),
	require(script.BubbleService),
	require(script.ToolService),
	require(script.MiniEventService),
	require(script.ChallengeService),
	require(script.DropService),
	require(script.ChestService),
	require(script.ShopService),
	require(script.ItemShopBuilder),
	-- Ancrages tableaux hub avant services classements.
	require(script.HubDisplaysService),
	require(script.LeaderboardService),
	require(script.WeeklyBestService),
	require(script.LevelLeaderboardService),
	require(script.TutorialService),
	require(script.AdminService),
}

for _, service in ipairs(services) do
	local ok, err = pcall(service.Start)
	if not ok then warn("[BPW] échec du démarrage d'un service: " .. tostring(err)) end
end

-- Validations (dev) — hors analytics (déjà exécutées avant Start en Studio).
do
	runSuite("OnboardingConfigTests", function()
		return require(Shared.OnboardingConfigTests)
	end)
	runSuite("TutorialConfigTests", function()
		return require(Shared.TutorialConfigTests)
	end)
	runSuite("ZoneAccessTests", function()
		return require(Shared.ZoneAccessTests)
	end)
	runSuite("MusicConfigTests", function()
		return require(Shared.MusicConfigTests)
	end)
	runSuite("HudChromeTests", function()
		return require(Shared.HudChromeTests)
	end)
	runSuite("LeaderboardTests", function()
		return require(Shared.LeaderboardTests)
	end)
	runSuite("HubDisplaysLogicTests", function()
		return require(Shared.HubDisplaysLogicTests)
	end)
	runSuite("TransitAnchorLogicTests", function()
		return require(Shared.TransitAnchorLogicTests)
	end)
	runSuite("WeeklyBestLogicTests", function()
		return require(Shared.WeeklyBestLogicTests)
	end)
	runSuite("ChallengeBoardUtilTests", function()
		return require(Shared.ChallengeBoardUtilTests)
	end)
	runSuite("SummerZoneStringLightsTests", function()
		return require(Shared.SummerZoneStringLightsTests)
	end)
	runSuite("TravelConfigTests", function()
		return require(Shared.TravelConfigTests)
	end)
	runSuite("TravelLogicTests", function()
		return require(Shared.TravelLogicTests)
	end)
	runSuite("HubLayoutTests", function()
		return require(Shared.HubLayoutTests)
	end)
	runSuite("RearHubLogicTests", function()
		return require(Shared.RearHubLogicTests)
	end)
	runSuite("RearHubIdentityTests", function()
		return require(Shared.RearHubIdentityTests)
	end)
	runSuite("RearHubCollisionLogicTests", function()
		return require(Shared.RearHubCollisionLogicTests)
	end)
	runSuite("RearHubStudioInstallTests", function()
		return require(Shared.RearHubStudioInstallTests)
	end)
	runSuite("HubSpawnLogicTests", function()
		return require(Shared.HubSpawnLogicTests)
	end)
	runSuite("HubShopPromptLogicTests", function()
		return require(Shared.HubShopPromptLogicTests)
	end)
	runSuite("BubbleValueTests", function()
		return require(Shared.BubbleValueTests)
	end)
	runSuite("BubbleAppearanceTests", function()
		return require(Shared.BubbleAppearanceTests)
	end)
	runSuite("MiniEventLogicTests", function()
		return require(Shared.MiniEventLogicTests)
	end)
	runSuite("ChallengeLogicTests", function()
		return require(Shared.ChallengeLogicTests)
	end)
	runSuite("ChallengeUiLayoutTests", function()
		return require(Shared.ChallengeUiLayoutTests)
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
	runSuite("BackpackServiceTests", function()
		return require(script.BackpackServiceTests)
	end)
	runSuite("ChestServiceTests", function()
		return require(script.ChestServiceTests)
	end)
end

print("[Bubble Pop World] serveur prêt.")
