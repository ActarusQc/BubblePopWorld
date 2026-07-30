-- Harnais de test hors Roblox pour ShopCatalog.
-- Lancer : python tools\run_shop_catalog_tests.py

--------------------------------------------------------------------
-- Stubs des types Roblox utilisés par GameConfig
--------------------------------------------------------------------

local v3 = {}

local function newVector3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, v3)
end

local v3methods = {}

function v3methods.Lerp(a, b, t)
	return newVector3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end

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
v3.__mul = function(a, b)
	if type(a) == "number" then
		return newVector3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return newVector3(a.X * b, a.Y * b, a.Z * b)
	end
	return newVector3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
v3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end

Vector3 = {
	new = newVector3,
	zero = newVector3(0, 0, 0),
	one = newVector3(1, 1, 1),
}

local cframe = {}
cframe.__index = cframe
cframe.__mul = function(a, b)
	if getmetatable(b) == v3 then
		return a.Position + b
	end
	return CFrame.new(a.Position + b.Position)
end

CFrame = {
	new = function(x, y, z)
		local position = if type(x) == "table" then x else newVector3(x, y, z)
		return setmetatable({ Position = position, LookVector = newVector3(0, 0, -1) }, cframe)
	end,
	Angles = function() return CFrame.new(0, 0, 0) end,
	identity = nil,
}
CFrame.identity = CFrame.new(0, 0, 0)

Color3 = {
	new = function(r, g, b)
		return { R = r or 0, G = g or 0, B = b or 0 }
	end,
	fromRGB = function(r, g, b)
		return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }
	end,
}

Enum = setmetatable({}, {
	__index = function()
		return setmetatable({}, { __index = function() return {} end })
	end,
})

warn = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end
	print("  " .. table.concat(parts, " "))
end

--------------------------------------------------------------------
-- Registre de modules : remplace le require() sandboxé du CLI Luau
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

game = {
	GetService = function(_, serviceName)
		if serviceName == "ReplicatedStorage" then
			return moduleProxy
		end
		return setmetatable({}, { __index = function() return function() end end })
	end,
}

--@MODULES@

--------------------------------------------------------------------
-- Exécution
--------------------------------------------------------------------

print("== ShopCatalog (hors Roblox) ==")

local Tests = harnessRequire(moduleProxy.ShopCatalogTests)
local ok = Tests.Run()

if ok then
	print("\nRESULTAT : OK")
else
	error("RESULTAT : ECHEC", 0)
end
