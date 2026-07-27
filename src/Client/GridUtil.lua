--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ZoneDefs = require(Shared.ZoneDefs)
local G = Config.Grid

local GridUtil = {}

function GridUtil.CellToWorld(x: number, z: number, zoneId: string?): Vector3
	local id = zoneId or "ClassicZone"
	local def = ZoneDefs.Get(id)
	local origin = if def then def.Origin else G.Origin
	return origin + Vector3.new((x - G.SizeX / 2) * G.Spacing, 0, (z - G.SizeZ / 2) * G.Spacing)
end

return GridUtil
