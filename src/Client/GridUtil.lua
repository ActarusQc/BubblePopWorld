--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneDefs = require(Shared.ZoneDefs)

local GridUtil = {}

function GridUtil.CellToWorld(x: number, z: number, zoneId: string?): Vector3
	return ZoneDefs.CellToWorld(x, z, zoneId)
end

return GridUtil
