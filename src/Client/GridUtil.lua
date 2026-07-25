--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared").GameConfig)
local G = Config.Grid

local GridUtil = {}

function GridUtil.CellToWorld(x: number, z: number): Vector3
	return G.Origin + Vector3.new((x - G.SizeX / 2) * G.Spacing, 0, (z - G.SizeZ / 2) * G.Spacing)
end

return GridUtil
