-- Harnais hors Roblox pour ShopService.
-- Lancer : python tools\run_shop_service_tests.py

local v3 = {}
local function newVector3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, v3)
end
v3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	end
	return nil
end
v3.__add = function(a, b) return newVector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
v3.__sub = function(a, b) return newVector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
v3.__mul = function(a, b)
	if type(a) == "number" then return newVector3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return newVector3(a.X * b, a.Y * b, a.Z * b) end
	return newVector3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

Vector3 = { new = newVector3, zero = newVector3(0, 0, 0), one = newVector3(1, 1, 1) }

local cframe = {}
cframe.__index = cframe
cframe.__mul = function(a, b)
	if getmetatable(b) == v3 then return a.Position + b end
	return CFrame.new(a.Position + b.Position)
end
CFrame = {
	new = function(x, y, z)
		local position = if type(x) == "table" then x else newVector3(x, y, z)
		return setmetatable({ Position = position, LookVector = newVector3(0, 0, -1) }, cframe)
	end,
	Angles = function() return CFrame.new(0, 0, 0) end,
}
CFrame.identity = CFrame.new(0, 0, 0)

Color3 = {
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
	fromRGB = function(r, g, b)
		return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }
	end,
}
Enum = setmetatable({}, {
	__index = function()
		return setmetatable({}, { __index = function() return {} end })
	end,
})
warn = function(...) print("  WARN ", ...) end

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
	if not name then error("require inattendu", 2) end
	if MODULE_CACHE[name] == nil then
		local loader = MODULE_LOADERS[name]
		if not loader then error("module non inliné : " .. tostring(name), 2) end
		MODULE_CACHE[name] = loader()
	end
	return MODULE_CACHE[name]
end
require = harnessRequire
game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then return moduleProxy end
		return {}
	end,
}

local callbacks = {}
local events = {}
local counters = {
	Get = 0,
	Push = 0,
	ApplyCharacterStats = 0,
	NotifyCoinsChanged = 0,
	Announce = 0,
	Refresh = 0,
}
local profile = {
	Coins = 0,
	Upgrades = { Speed = 0, Jump = 0, Power = 0, CoinMult = 0 },
	OwnedItems = {},
	EquippedBackpack = "",
	BackpackCapacity = 25,
	CurrentBubbles = 0,
}
local function resetCounters()
	for key in pairs(counters) do counters[key] = 0 end
end

MODULE_CACHE.Remotes = {
	Func = function(name)
		if not callbacks[name] then callbacks[name] = {} end
		return callbacks[name]
	end,
	Event = function(name)
		if not events[name] then
			events[name] = {
				FireClient = function()
					if name == "Announce" then counters.Announce += 1 end
				end,
			}
		end
		return events[name]
	end,
}
MODULE_CACHE.DataService = {
	Get = function()
		counters.Get += 1
		return profile
	end,
	Push = function() counters.Push += 1 end,
	ApplyCharacterStats = function() counters.ApplyCharacterStats += 1 end,
	NotifyCoinsChanged = function() counters.NotifyCoinsChanged += 1 end,
}
MODULE_CACHE.BackpackVisual = {
	Refresh = function() counters.Refresh += 1 end,
}

--@MODULES@

print("== ShopService (hors Roblox) ==")
local ShopService = harnessRequire(moduleProxy.ShopService)
ShopService.Start()

local invokeCallbacks = {}
for name, remote in pairs(callbacks) do
	invokeCallbacks[name] = function(player, argument)
		return remote.OnServerInvoke(player, argument)
	end
end

local Tests = harnessRequire(moduleProxy.ShopServiceTests)
local ok = Tests.Run({
	Callbacks = invokeCallbacks,
	Profile = profile,
	Counters = counters,
	ResetCounters = resetCounters,
})
if not ok then error("RESULTAT : ECHEC", 0) end
print("\nRESULTAT : OK")
