-- Harnais hors Roblox : HubAssetContract + HubAssetContractTests.
-- Lancer : python tools\run_hub_asset_tests.py
--
-- Stub minimal d'Instance / CFrame / Enum suffisant pour Validate et Decide.
-- Aucun script de production n'est modifié ni exécuté.

--------------------------------------------------------------------
-- Vector3
--------------------------------------------------------------------
local v3 = {}

local function newVector3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, v3)
end

local v3methods = {
	Dot = function(a, b)
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z
	end,
	Cross = function(a, b)
		return newVector3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
	end,
}

v3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m < 1e-9 then
			return newVector3(0, 0, 0)
		end
		return newVector3(self.X / m, self.Y / m, self.Z / m)
	end
	return v3methods[key]
end
v3.__add = function(a, b) return newVector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
v3.__sub = function(a, b) return newVector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
v3.__unm = function(a) return newVector3(-a.X, -a.Y, -a.Z) end
v3.__mul = function(a, b)
	if type(a) == "number" then
		return newVector3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return newVector3(a.X * b, a.Y * b, a.Z * b)
	end
	return newVector3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
v3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
v3.__tostring = function(a) return ("(%.3f, %.3f, %.3f)"):format(a.X, a.Y, a.Z) end

Vector3 = {
	new = newVector3,
	zero = newVector3(0, 0, 0),
	one = newVector3(1, 1, 1),
	xAxis = newVector3(1, 0, 0),
	yAxis = newVector3(0, 1, 0),
	zAxis = newVector3(0, 0, 1),
}

--------------------------------------------------------------------
-- CFrame
--------------------------------------------------------------------
local cframe = {}

local function identityRotation()
	return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
end

local function rotateVector(r, v)
	return newVector3(
		r[1][1] * v.X + r[1][2] * v.Y + r[1][3] * v.Z,
		r[2][1] * v.X + r[2][2] * v.Y + r[2][3] * v.Z,
		r[3][1] * v.X + r[3][2] * v.Y + r[3][3] * v.Z
	)
end

local function matMul(a, b)
	local out = { {}, {}, {} }
	for i = 1, 3 do
		for j = 1, 3 do
			local sum = 0
			for k = 1, 3 do
				sum += a[i][k] * b[k][j]
			end
			out[i][j] = sum
		end
	end
	return out
end

local function newCF(pos, rot)
	return setmetatable({ _pos = pos, _rot = rot or identityRotation() }, cframe)
end

cframe.__index = function(self, key)
	if key == "Position" then
		return self._pos
	elseif key == "LookVector" then
		return rotateVector(self._rot, newVector3(0, 0, -1))
	elseif key == "RightVector" then
		return rotateVector(self._rot, newVector3(1, 0, 0))
	elseif key == "UpVector" then
		return rotateVector(self._rot, newVector3(0, 1, 0))
	end
	return cframe[key]
end

cframe.__mul = function(a, b)
	if getmetatable(b) == v3 then
		return a._pos + rotateVector(a._rot, b)
	end
	return newCF(a._pos + rotateVector(a._rot, b._pos), matMul(a._rot, b._rot))
end

cframe.Inverse = function(self)
	local r = self._rot
	local rt = {
		{ r[1][1], r[2][1], r[3][1] },
		{ r[1][2], r[2][2], r[3][2] },
		{ r[1][3], r[2][3], r[3][3] },
	}
	local p = self._pos
	local invP = newVector3(
		-(rt[1][1] * p.X + rt[1][2] * p.Y + rt[1][3] * p.Z),
		-(rt[2][1] * p.X + rt[2][2] * p.Y + rt[2][3] * p.Z),
		-(rt[3][1] * p.X + rt[3][2] * p.Y + rt[3][3] * p.Z)
	)
	return newCF(invP, rt)
end

CFrame = {
	identity = newCF(newVector3(0, 0, 0), identityRotation()),
	new = function(x, y, z)
		local position = if type(x) == "table" then x else newVector3(x, y, z)
		return newCF(position, identityRotation())
	end,
	Angles = function(rx, ry, rz)
		rx, ry, rz = rx or 0, ry or 0, rz or 0
		local cx, sx = math.cos(rx), math.sin(rx)
		local cy, sy = math.cos(ry), math.sin(ry)
		local cz, sz = math.cos(rz), math.sin(rz)
		local Rx = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
		local Ry = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
		local Rz = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
		return newCF(newVector3(0, 0, 0), matMul(Rx, matMul(Ry, Rz)))
	end,
	lookAt = function(from, to)
		local dir = (to - from).Unit
		local up = newVector3(0, 1, 0)
		local right = v3methods.Cross(up, -dir).Unit
		local realUp = v3methods.Cross(-dir, right)
		return newCF(from, {
			{ right.X, realUp.X, -dir.X },
			{ right.Y, realUp.Y, -dir.Y },
			{ right.Z, realUp.Z, -dir.Z },
		})
	end,
}

--------------------------------------------------------------------
-- typeof / Enum
--------------------------------------------------------------------
local enumItemMt = { __index = function(self, key)
	if key == "Name" then
		return rawget(self, "_name")
	end
	return nil
end }

local function enumItem(name)
	return setmetatable({ _name = name, Name = name }, {
		__index = function(self, key)
			if key == "Name" then
				return self._name
			end
			return nil
		end,
	})
end

local materialNames = {
	"Metal", "Concrete", "Slate", "Granite", "Marble", "Wood", "WoodPlanks",
	"Neon", "Glass", "ForceField", "Fabric", "SmoothPlastic", "Plastic",
}

local materialEnum = {}
for _, name in ipairs(materialNames) do
	materialEnum[name] = enumItem(name)
end

Enum = {
	Material = materialEnum,
}

typeof = function(value)
	local t = type(value)
	if t == "table" then
		local mt = getmetatable(value)
		if mt == v3 then
			return "Vector3"
		elseif mt == cframe then
			return "CFrame"
		elseif type(value.Name) == "string" and materialEnum[value.Name] == value then
			return "EnumItem"
		elseif value._name and materialEnum[value._name] then
			return "EnumItem"
		end
	end
	return t
end

--------------------------------------------------------------------
-- Instance stubs
--------------------------------------------------------------------
local instanceMethods = {}

local CLASS_PARENTS = {
	Part = { "BasePart", "PVInstance", "Instance" },
	MeshPart = { "BasePart", "PVInstance", "Instance" },
	WedgePart = { "BasePart", "PVInstance", "Instance" },
	Model = { "PVInstance", "Instance" },
	Folder = { "Instance" },
	Workspace = { "Instance" },
	Script = { "LuaSourceContainer", "Instance" },
	LocalScript = { "LuaSourceContainer", "Instance" },
	ModuleScript = { "LuaSourceContainer", "Instance" },
	SurfaceGui = { "LayerCollector", "Instance" },
	BillboardGui = { "LayerCollector", "Instance" },
	SurfaceAppearance = { "Instance" },
	ProximityPrompt = { "Instance" },
	ClickDetector = { "Instance" },
	PointLight = { "Light", "Instance" },
	SpotLight = { "Light", "Instance" },
	Humanoid = { "Instance" },
}

local instanceMt = {
	__index = function(self, key)
		local props = rawget(self, "_props")
		local value = props[key]
		if value ~= nil then
			return value
		end
		if key == "Position" and props.CFrame then
			return props.CFrame.Position
		end
		return instanceMethods[key]
	end,
	__newindex = function(self, key, value)
		local props = rawget(self, "_props")
		if key == "Parent" then
			local old = props.Parent
			if old then
				local siblings = rawget(old, "_children")
				for index, child in ipairs(siblings) do
					if child == self then
						table.remove(siblings, index)
						break
					end
				end
			end
			props.Parent = value
			if value then
				table.insert(rawget(value, "_children"), self)
			end
		elseif key == "CFrame" then
			props.CFrame = value
			if value then
				props.Position = value.Position
			end
		else
			props[key] = value
		end
	end,
}

function instanceMethods:GetChildren()
	local copy = {}
	for _, child in ipairs(rawget(self, "_children")) do
		table.insert(copy, child)
	end
	return copy
end

function instanceMethods:GetDescendants()
	local out = {}
	for _, child in ipairs(rawget(self, "_children")) do
		table.insert(out, child)
		for _, nested in ipairs(child:GetDescendants()) do
			table.insert(out, nested)
		end
	end
	return out
end

function instanceMethods:FindFirstChild(name, recursive)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(rawget(self, "_children")) do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function instanceMethods:FindFirstChildWhichIsA(className)
	for _, child in ipairs(rawget(self, "_children")) do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end

function instanceMethods:IsA(className)
	if self.ClassName == className then
		return true
	end
	for _, parent in ipairs(CLASS_PARENTS[self.ClassName] or {}) do
		if parent == className then
			return true
		end
	end
	return false
end

function instanceMethods:SetAttribute(name, value)
	rawget(self, "_attributes")[name] = value
end

function instanceMethods:GetAttribute(name)
	return rawget(self, "_attributes")[name]
end

function instanceMethods:Destroy()
	for _, child in ipairs(self:GetChildren()) do
		child:Destroy()
	end
	self.Parent = nil
	rawget(self, "_props").Destroyed = true
end

function instanceMethods:GetPivot()
	return self.WorldPivot or CFrame.identity
end

function instanceMethods:IsDescendantOf(target)
	local parent = self.Parent
	while parent do
		if parent == target then
			return true
		end
		parent = parent.Parent
	end
	return false
end

function instanceMethods:GetScale()
	return rawget(self, "_props").Scale or 1
end

function instanceMethods:ScaleTo(newScale)
	local old = self:GetScale()
	local factor = newScale / math.max(old, 1e-9)
	rawget(self, "_props").Scale = newScale
	local pivot = self:GetPivot().Position
	local function scalePart(part)
		local pos = part.CFrame.Position
		local rel = pos - pivot
		part.Size = part.Size * factor
		part.CFrame = CFrame.new(pivot + rel * factor)
	end
	if self:IsA("BasePart") then
		scalePart(self)
	end
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			scalePart(d)
		end
	end
end

function instanceMethods:PivotTo(cf)
	local current = self:GetPivot()
	local transform = cf * current:Inverse()
	local function movePart(part)
		part.CFrame = transform * part.CFrame
	end
	if self:IsA("BasePart") then
		movePart(self)
	end
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			movePart(d)
		end
	end
	self.WorldPivot = cf
end

function instanceMethods:Clone()
	local copy = Instance.new(self.ClassName)
	copy.Name = self.Name
	for key, value in pairs(rawget(self, "_props")) do
		if key ~= "Parent" and key ~= "ClassName" then
			rawget(copy, "_props")[key] = value
		end
	end
	for key, value in pairs(rawget(self, "_attributes")) do
		copy:SetAttribute(key, value)
	end
	for _, child in ipairs(self:GetChildren()) do
		local childCopy = child:Clone()
		childCopy.Parent = copy
	end
	return copy
end

-- AABB monde de tous les BasePart descendants (approximation de Model:GetExtentsSize).
function instanceMethods:GetExtentsSize()
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false
	local function consider(part)
		if not part:IsA("BasePart") then
			return
		end
		found = true
		local pos = part.CFrame.Position
		local half = part.Size * 0.5
		minX = math.min(minX, pos.X - half.X)
		minY = math.min(minY, pos.Y - half.Y)
		minZ = math.min(minZ, pos.Z - half.Z)
		maxX = math.max(maxX, pos.X + half.X)
		maxY = math.max(maxY, pos.Y + half.Y)
		maxZ = math.max(maxZ, pos.Z + half.Z)
	end
	if self:IsA("BasePart") then
		consider(self)
	end
	for _, d in ipairs(self:GetDescendants()) do
		consider(d)
	end
	if not found then
		return Vector3.zero
	end
	return newVector3(maxX - minX, maxY - minY, maxZ - minZ)
end

function instanceMethods:GetBoundingBox()
	local size = self:GetExtentsSize()
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false
	local function consider(part)
		if not part:IsA("BasePart") then
			return
		end
		found = true
		local pos = part.CFrame.Position
		local half = part.Size * 0.5
		minX = math.min(minX, pos.X - half.X)
		minY = math.min(minY, pos.Y - half.Y)
		minZ = math.min(minZ, pos.Z - half.Z)
		maxX = math.max(maxX, pos.X + half.X)
		maxY = math.max(maxY, pos.Y + half.Y)
		maxZ = math.max(maxZ, pos.Z + half.Z)
	end
	if self:IsA("BasePart") then
		consider(self)
	end
	for _, d in ipairs(self:GetDescendants()) do
		consider(d)
	end
	if not found then
		return CFrame.identity, Vector3.zero
	end
	local center = newVector3((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
	return CFrame.new(center), size
end

Instance = {
	new = function(className)
		local props = {
			ClassName = className,
			Name = className,
			Parent = nil,
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Size = newVector3(1, 1, 1),
			CFrame = CFrame.identity,
			Position = newVector3(0, 0, 0),
			Material = materialEnum.Metal,
			WorldPivot = CFrame.identity,
			Scale = 1,
		}
		return setmetatable({
			_props = props,
			_children = {},
			_attributes = {},
		}, instanceMt)
	end,
}

local workspaceRoot = Instance.new("Workspace")
workspaceRoot.Name = "Workspace"
workspace = workspaceRoot

--------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------
local MODULE_LOADERS = {}
local MODULE_CACHE = {}
local MODULE_TOKENS = {}

local moduleProxy
moduleProxy = setmetatable({}, {
	__index = function(_, key)
		if key == "WaitForChild" or key == "FindFirstChild" then
			return function(_, name)
				if name == "Shared" or name == "ReplicatedStorage" then
					return moduleProxy
				end
				return moduleProxy[name]
			end
		end
		local token = MODULE_TOKENS[key]
		if not token then
			token = { __moduleName = key }
			MODULE_TOKENS[key] = token
		end
		return token
	end,
})

script = { Parent = moduleProxy, Name = "harness" }

local function harnessRequire(target)
	local name = if type(target) == "table" then target.__moduleName else nil
	if not name then
		error("require() inattendu dans le harnais", 2)
	end
	if MODULE_CACHE[name] == nil then
		local loader = MODULE_LOADERS[name]
		if not loader then
			error("module non inliné dans le harnais : " .. tostring(name), 2)
		end
		MODULE_CACHE[name] = loader()
	end
	return MODULE_CACHE[name]
end
require = harnessRequire

local warnings = {}
warn = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end
	table.insert(warnings, table.concat(parts, " "))
	print("  WARN  " .. table.concat(parts, " "))
end

game = {
	GetService = function(_, serviceName)
		if serviceName == "ReplicatedStorage" then
			return moduleProxy
		elseif serviceName == "Workspace" then
			return workspaceRoot
		end
		return setmetatable({}, { __index = function() return function() end end })
	end,
}

--@MODULES@

--------------------------------------------------------------------
-- Exécution
--------------------------------------------------------------------
local Tests = harnessRequire(moduleProxy.HubAssetContractTests)
local ok = Tests.Run()
if not ok then
	error("HubAssetContractTests a échoué", 0)
end
