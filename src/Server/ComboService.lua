--!strict
-- Combo : enchaîner les rebonds sans pause augmente le multiplicateur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local ComboService = {}
local combos: { [Player]: { count: number, expires: number, mult: number } } = {}

function ComboService.Register(player: Player): number
	local now = os.clock()
	local c = combos[player]

	if not c or now > c.expires then
		c = { count = 0, expires = 0, mult = 1 }
		combos[player] = c
	end

	c.count += 1
	c.expires = now + Config.Combo.Window
	c.mult = math.min(
		Config.Combo.Max,
		1 + math.floor(c.count / Config.Combo.Step) * Config.Combo.Bonus
	)

	Remotes.Event("ComboUpdate"):FireClient(player, c.count, c.mult, Config.Combo.Window)
	return c.mult
end

function ComboService.Get(player: Player): number
	local c = combos[player]
	return if c and os.clock() <= c.expires then c.mult else 1
end

function ComboService.Start()
	Players.PlayerRemoving:Connect(function(p) combos[p] = nil end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = os.clock()
			for player, c in pairs(combos) do
				if now > c.expires then
					combos[player] = nil
					if player.Parent then
						Remotes.Event("ComboUpdate"):FireClient(player, 0, 1, Config.Combo.Window)
					end
				end
			end
		end
	end)
end

return ComboService
