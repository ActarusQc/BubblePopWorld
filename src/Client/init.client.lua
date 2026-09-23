--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")

local modules = {
	require(script.HubSpawnCamera),
	require(script.ElevatorCamera),
	require(script.FerrisRideCamera),
	require(script.HUD),
	require(script.PopController),
	require(script.PopEffects),
	require(script.ComboUI),
	require(script.JuiceController),
	require(script.ToolClient),
	require(script.ShopUI),
	require(script.InventoryUI),
	require(script.CollectionController),
	require(script.ZoneAmbiance),
	require(script.MusicController),
	require(script.SummerFireworks),
	require(script.TravelController),
	require(script.BubbleBlasterController),
	require(script.RollABallController),
	require(script.TentChestController),
	-- Challenge barre d'abord pour embarquer les mini-événements.
	require(script.ChallengeController),
	require(script.WorldChallengesBoardController),
	require(script.TopCoinsBoardController),
	require(script.MiniEventController),
	require(script.ColorRushBubbleEffects),
	require(script.TutorialController),
}

for _, m in ipairs(modules) do
	local ok, err = pcall(m.Start)
	if not ok then
		warn("[BPW client] " .. tostring(err))
	end
end
