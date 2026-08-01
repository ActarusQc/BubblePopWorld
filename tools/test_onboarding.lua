-- Harnais hors Roblox pour OnboardingConfig.
-- Lancer : python tools\run_onboarding_tests.py

warn = function(...)
	print("  WARN ", ...)
end

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
		error("require inattendu", 2)
	end
	if MODULE_CACHE[name] == nil then
		local loader = MODULE_LOADERS[name]
		if not loader then
			error("module non inliné : " .. tostring(name), 2)
		end
		MODULE_CACHE[name] = loader()
	end
	return MODULE_CACHE[name]
end
require = harnessRequire

game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return moduleProxy
		end
		return {}
	end,
}

--@MODULES@

print("== OnboardingConfig (hors Roblox) ==")
local Tests = harnessRequire(moduleProxy.OnboardingConfigTests)
local ok = Tests.Run()
if not ok then
	error("RESULTAT : ECHEC", 0)
end
print("\nRESULTAT : OK")
