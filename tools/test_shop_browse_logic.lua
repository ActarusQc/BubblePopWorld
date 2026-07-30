-- Harnais de test hors Roblox pour ShopBrowseLogic.
-- Lancer : python tools\run_shop_browse_logic_tests.py

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

print("== ShopBrowseLogic (hors Roblox) ==")

local Tests = harnessRequire(moduleProxy.ShopBrowseLogicTests)
local ok = Tests.Run()

if ok then
	print("\nRESULTAT : OK")
else
	error("RESULTAT : ECHEC", 0)
end
