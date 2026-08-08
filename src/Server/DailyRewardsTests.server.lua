--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if RunService:IsStudio() then
	local ok, err = pcall(function()
		local tests = require(ReplicatedStorage:WaitForChild("Shared").DailyRewardsLogicTests)
		tests.Run()
	end)
	if not ok then
		warn("[DailyRewardsLogicTests] FAIL: " .. tostring(err))
	end
end
