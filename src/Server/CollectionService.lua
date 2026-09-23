--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.CollectionConfig)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local CollectionService = {}

local function collectionFor(player: Player): any?
	local profile = DataService.Get(player)
	if not profile then return nil end
	if type(profile.Collection) ~= "table" then
		profile.Collection = { Version = Config.Version, Discovered = {}, FoundCounts = {}, TotalSpecialPops = 0, PopsSinceCollection = 0 }
	end
	if type(profile.Collection.Discovered) ~= "table" then profile.Collection.Discovered = {} end
	if type(profile.Collection.FoundCounts) ~= "table" then profile.Collection.FoundCounts = {} end
	for id, found in pairs(profile.Collection.Discovered) do
		if found == true and (tonumber(profile.Collection.FoundCounts[id]) or 0) < 1 then
			profile.Collection.FoundCounts[id] = 1
		end
	end
	profile.Collection.PopsSinceCollection = math.max(0, math.floor(tonumber(profile.Collection.PopsSinceCollection) or 0))
	return profile.Collection
end

local function discoveredCount(collection: any): number
	local count = 0
	for id, value in pairs(collection.Discovered) do
		if value == true and Config.ById[id] then count += 1 end
	end
	return count
end

local function chooseCollectible(collection: any, rarityId: string, random: Random): any?
	local pool = Config.ByRarity[rarityId]
	if not pool or #pool == 0 then return nil end
	local missing = {}
	for _, def in ipairs(pool) do
		if collection.Discovered[def.Id] ~= true then table.insert(missing, def) end
	end
	local settings = Config.PersonalDiscovery
	local forceMissing = discoveredCount(collection) < settings.GuaranteedNewDiscoveries
	local preferMissing = #missing > 0 and random:NextNumber() <= settings.UndiscoveredPreference
	local selectedPool = if #missing > 0 and (forceMissing or preferMissing) then missing else pool
	return selectedPool[random:NextInteger(1, #selectedPool)]
end

function CollectionService.RecordValidPops(player: Player, count: number, zoneId: string, random: Random): any?
	local collection = collectionFor(player)
	local rarityId = Config.RarityForZone(zoneId)
	if not collection or not rarityId or count <= 0 then return nil end
	collection.PopsSinceCollection += math.max(1, math.floor(count))
	local profile = DataService.Get(player)
	if profile then profile.__dirty = true end

	local found = discoveredCount(collection)
	local shouldSpawn = found == 0 and collection.PopsSinceCollection >= Config.PersonalDiscovery.FirstGuaranteePops
	if not shouldSpawn then
		local chance = Config.PersonalChance(collection.PopsSinceCollection)
		local batchChance = 1 - math.pow(1 - chance, math.max(1, math.floor(count)))
		shouldSpawn = chance > 0 and random:NextNumber() <= batchChance
	end
	if not shouldSpawn then return nil end
	return chooseCollectible(collection, rarityId, random)
end

function CollectionService.State(player: Player)
	local collection = collectionFor(player)
	if not collection then return nil end
	local discovered = {}
	local foundCounts = {}
	for id, value in pairs(collection.Discovered) do
		if value == true and Config.ById[id] then
			discovered[id] = true
			foundCounts[id] = math.max(1, math.floor(tonumber(collection.FoundCounts[id]) or 1))
		end
	end
	return { Version = Config.Version, Catalog = Config.PublicCatalog(), Discovered = discovered, FoundCounts = foundCounts, Total = #Config.Items }
end

function CollectionService.Push(player: Player)
	local state = CollectionService.State(player)
	if state then Remotes.Event("CollectionState"):FireClient(player, state) end
end

function CollectionService.Discover(player: Player, collectibleId: string): boolean
	local def = Config.ById[collectibleId]
	local collection = collectionFor(player)
	if not def or not collection then return false end
	collection.TotalSpecialPops = (tonumber(collection.TotalSpecialPops) or 0) + 1
	collection.PopsSinceCollection = 0
	collection.FoundCounts[collectibleId] = math.max(0, math.floor(tonumber(collection.FoundCounts[collectibleId]) or 0)) + 1
	local profile = DataService.Get(player)
	if profile then profile.__dirty = true end
	if collection.Discovered[collectibleId] == true then
		CollectionService.Push(player)
		return false
	end
	collection.Discovered[collectibleId] = true
	Remotes.Event("CollectionDiscovered"):FireClient(player, { Id = def.Id, Name = def.Name, Rarity = def.Rarity, ImageId = def.ImageId })
	CollectionService.Push(player)
	return true
end

function CollectionService.Start()
	Remotes.Event("CollectionRequestState").OnServerEvent:Connect(function(player) CollectionService.Push(player) end)
end

return CollectionService
