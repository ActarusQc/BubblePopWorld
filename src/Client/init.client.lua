--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")

local modules = {
	require(script.HUD),
	require(script.PopController),
	require(script.PopEffects),
	require(script.ComboUI),
	require(script.JuiceController),
	require(script.ToolClient),
	require(script.ShopUI),
}

for _, m in ipairs(modules) do
	local ok, err = pcall(m.Start)
	if not ok then warn("[BPW client] " .. tostring(err)) end
end
