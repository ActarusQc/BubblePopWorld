--!strict
-- Service serveur des mini-événements (machine d'états autoritaire).
-- Idle → Countdown → Active → Cleanup → Cooldown → Idle

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MiniEventConfig = require(Shared.MiniEventConfig)
local MiniEventLogic = require(Shared.MiniEventLogic)
local BubbleAppearance = require(Shared.BubbleAppearance)
local BubbleTypes = require(Shared.BubbleTypes)
local Remotes = require(Shared.Remotes)
local ZoneDefs = require(Shared.ZoneDefs)
local L10n = require(Shared.LocalizationStrings)

local DataService = require(script.Parent.DataService)
local BubbleService = require(script.Parent.BubbleService)

local MiniEventService = {}

local rng = Random.new()
local started = false
local schedulerToken = 0
local phaseGeneration = 0

local machineState = MiniEventLogic.STATES.Idle
local currentEventType: string? = nil
local lastEventType: string? = nil
local phaseEndsAt = 0.0
local phaseStartedAt = 0.0
local activeServerClockStart = 0.0
local activeServerClockEnd = 0.0

-- Objectif / progression session
local targetColor: Color3? = nil
local giantParts: { [string]: BasePart } = {}
local giantRequired = 0
local giantProgress = 0
local giantContrib: { [number]: number } = {} -- userId → hits
local giantHitCooldown: { [number]: number } = {}
local giantCompleted = false
local giantFailed = false
local rewardedUserIds: { [number]: boolean } = {}
local analyticsMilestonesSent: { [number]: boolean } = {}
local eventParticipants: { [number]: boolean } = {}
local lastProgressBroadcast = 0.0
local forcedTesting = false
-- Progression / bonus perso (Golden Wave, Color Rush) — autoritaire serveur.
local sessionStats: { [number]: { progress: number, bonusCoins: number } } = {}
local lastPlayerProgressAt: { [number]: number } = {}

local eventFolder: Folder? = nil

local function nowServer(): number
	return Workspace:GetServerTimeNow()
end

local function log(msg: string)
	print("[MiniEventService] " .. msg)
end

local function softGas(method: string, ...)
	local args = table.pack(...)
	pcall(function()
		local GAS = require(script.Parent.GameAnalyticsService)
		local fn = (GAS :: any)[method]
		if type(fn) == "function" then
			fn(table.unpack(args, 1, args.n))
		end
	end)
end

local function isBubbleArea(area: any): boolean
	return area == "GameRoom" or area == "SummerZone" or area == "ClassicZone"
end

local function countPlayersInBubbleZones(): number
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local area = p:GetAttribute("PlayerArea")
		if isBubbleArea(area) then
			n += 1
		end
	end
	return n
end

local function playersInZone(zoneId: string): number
	local n = 0
	local areaNeed = if zoneId == "SummerZone" then "SummerZone" else "GameRoom"
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("PlayerArea") == areaNeed or p:GetAttribute("PlayerArea") == zoneId then
			n += 1
		end
	end
	return n
end

local function activeZoneIdsWithPlayers(): { string }
	local ids = {}
	for _, zoneId in ipairs(MiniEventConfig.ParticipatingZones) do
		if BubbleService.GetBoard(zoneId) and playersInZone(zoneId) > 0 then
			table.insert(ids, zoneId)
		end
	end
	-- fallback : toutes les planches participantes existantes si personne (Studio force)
	if #ids == 0 and forcedTesting then
		for _, zoneId in ipairs(MiniEventConfig.ParticipatingZones) do
			if BubbleService.GetBoard(zoneId) then
				table.insert(ids, zoneId)
			end
		end
	end
	return ids
end

local function allParticipatingBoards(): { string }
	local ids = {}
	for _, zoneId in ipairs(MiniEventConfig.ParticipatingZones) do
		if BubbleService.GetBoard(zoneId) then
			table.insert(ids, zoneId)
		end
	end
	return ids
end

local function ensureFolder(): Folder
	if eventFolder and eventFolder.Parent then
		return eventFolder
	end
	local existing = Workspace:FindFirstChild("MiniEvents")
	if existing and existing:IsA("Folder") then
		eventFolder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "MiniEvents"
	f.Parent = Workspace
	eventFolder = f
	return f
end

local function fireStateTo(player: Player?, payload: any)
	local ok, err = pcall(function()
		if player then
			Remotes.Event("MiniEventState"):FireClient(player, payload)
		else
			Remotes.Event("MiniEventState"):FireAllClients(payload)
		end
	end)
	if not ok then
		warn("[MiniEventService] Fire MiniEventState: " .. tostring(err))
	end
end

local function getSessionStats(userId: number): { progress: number, bonusCoins: number }
	local s = sessionStats[userId]
	if not s then
		s = { progress = 0, bonusCoins = 0 }
		sessionStats[userId] = s
	end
	return s
end

local function clearSessionStats()
	sessionStats = {}
	lastPlayerProgressAt = {}
end

local function displayNameFor(eventType: string): string
	if eventType == "GoldenWave" then
		return L10n.MiniEventGoldenWave
	elseif eventType == "ColorRush" then
		return L10n.MiniEventColorRush
	elseif eventType == "GiantBubble" then
		return L10n.MiniEventGiantBubble
	end
	return eventType
end

local function objectiveTextFor(eventType: string): string
	if eventType == "GoldenWave" then
		return L10n.MiniEventGoldenWaveObjective
	elseif eventType == "ColorRush" then
		return L10n.MiniEventColorRushObjective
	elseif eventType == "GiantBubble" then
		return L10n.MiniEventGiantBubbleObjective
	end
	return ""
end

local function buildProgressFor(player: Player?): any?
	if currentEventType == "GiantBubble" then
		local personal = 0
		if player then
			personal = giantContrib[player.UserId] or 0
		end
		return {
			current = giantProgress,
			required = giantRequired,
			personal = personal,
			completed = giantCompleted,
			failed = giantFailed,
		}
	end
	if currentEventType == "GoldenWave" or currentEventType == "ColorRush" then
		local stats = if player then getSessionStats(player.UserId) else { progress = 0, bonusCoins = 0 }
		return {
			current = stats.progress,
			personal = stats.progress,
			bonusCoins = stats.bonusCoins,
		}
	end
	return nil
end

local function buildObjective(): any?
	if currentEventType == "GoldenWave" then
		return {
			multiplier = MiniEventConfig.Events.GoldenWave.SellMultiplier,
		}
	elseif currentEventType == "ColorRush" and targetColor then
		return {
			multiplier = MiniEventConfig.Events.ColorRush.SellMultiplier,
			targetColor = MiniEventLogic.SerializeColor(targetColor),
			colorName = MiniEventConfig.ColorLabel(targetColor),
		}
	elseif currentEventType == "GiantBubble" then
		return {
			required = giantRequired,
		}
	end
	return nil
end

local function buildUiFields(player: Player?, state: string, outcome: string?, rewardHint: any?): any
	local et = currentEventType or ""
	local stats = if player then getSessionStats(player.UserId) else { progress = 0, bonusCoins = 0 }
	local progressCurrent: number? = nil
	local progressTarget: number? = nil
	local bonusCoins = stats.bonusCoins

	if et == "GiantBubble" then
		progressCurrent = giantProgress
		progressTarget = giantRequired
		if state == "Ended" and rewardHint and type(rewardHint.sellBonus) == "number" then
			bonusCoins = math.max(0, math.floor(rewardHint.sellBonus))
		elseif player then
			bonusCoins = 0
		end
	else
		progressCurrent = stats.progress
		progressTarget = nil
		if state == "Ended" and rewardHint and type(rewardHint.bonusCoins) == "number" then
			bonusCoins = math.max(0, math.floor(rewardHint.bonusCoins))
		end
	end

	local completed: boolean? = nil
	if state == "Ended" then
		if MiniEventLogic.HasPassCondition(et) then
			completed = outcome == "Complete"
		else
			completed = nil
		end
	end

	return {
		displayName = displayNameFor(et),
		objectiveText = objectiveTextFor(et),
		progressCurrent = progressCurrent,
		progressTarget = progressTarget,
		bonusCoins = bonusCoins,
		hasPassCondition = MiniEventLogic.HasPassCondition(et),
		completed = completed,
	}
end

local function makePayload(
	state: string,
	outcome: string?,
	rewardHint: any?,
	player: Player?
): { [string]: any }
	local et = currentEventType :: string
	local payload = MiniEventLogic.BuildNetworkPayload(
		state,
		et,
		activeServerClockStart,
		activeServerClockEnd,
		allParticipatingBoards(),
		buildObjective(),
		buildProgressFor(player),
		outcome,
		rewardHint
	)
	return MiniEventLogic.EnrichPayloadForUi(payload, buildUiFields(player, state, outcome, rewardHint))
end

local function broadcast(state: string, outcome: string?, rewardHint: any?, player: Player?)
	if not currentEventType then
		return
	end
	-- Golden / Color / Giant Active : payload perso (progress + bonus)
	if state == "Active" and player == nil then
		for _, p in ipairs(Players:GetPlayers()) do
			fireStateTo(p, makePayload(state, outcome, rewardHint, p))
		end
		return
	end
	if state == "Ended" and player == nil then
		for _, p in ipairs(Players:GetPlayers()) do
			local hint = rewardHint
			if currentEventType ~= "GiantBubble" then
				local stats = getSessionStats(p.UserId)
				hint = {
					bonusCoins = stats.bonusCoins,
					progress = stats.progress,
				}
			end
			fireStateTo(p, makePayload(state, outcome, hint, p))
		end
		return
	end
	fireStateTo(player, makePayload(state, outcome, rewardHint, player))
end

local function maybeBroadcastPlayerProgress(player: Player)
	-- Un push par pop événement (pas chaque frame).
	broadcast("Active", nil, nil, player)
end

local function clearEventAttributes(cell: any)
	if not cell or not cell.part then
		return
	end
	local part = cell.part :: BasePart
	part:SetAttribute("EventVariant", nil)
	part:SetAttribute("EventMark", nil)
	cell.eventVariant = nil
	-- restaurer via pipeline d'apparence existant
	if cell.def and cell.alive then
		BubbleAppearance.ApplyToPart(part, cell.zoneId, cell.def.Id, cell.tintIndex or 1, true)
	elseif cell.def then
		BubbleAppearance.ApplyToPart(part, cell.zoneId, cell.def.Id, cell.tintIndex or 1, false)
	end
end

local function applyGoldenLook(cell: any)
	local cfg = MiniEventConfig.Events.GoldenWave
	local part = cell.part :: BasePart
	local zoneId = cell.zoneId or "ClassicZone"
	local main = zoneId == "ClassicZone" or zoneId == "GameRoom"
	cell.eventVariant = "GoldenWave"
	part:SetAttribute("EventVariant", "GoldenWave")
	-- Zone principale : rester en Neon pour ne pas réintroduire le shading caméra.
	part.Color = if main then Color3.fromRGB(200, 155, 25) else cfg.Color
	part.Material = if main then Enum.Material.Neon else cfg.Material
	part.Reflectance = 0
	part.Transparency = if main then 0 else cfg.Transparency
	part.CastShadow = false
end

local function applyColorRushMark(cell: any)
	local part = cell.part :: BasePart
	part:SetAttribute("EventMark", "ColorRush")
	-- Anneau discret (Highlight limité — UIStroke equivalent via SelectionBox léger)
	local existing = part:FindFirstChild("EventMarkRing")
	if existing then
		return
	end
	local ring = Instance.new("SelectionBox")
	ring.Name = "EventMarkRing"
	ring.Adornee = part
	ring.Color3 = targetColor or Color3.fromRGB(255, 255, 255)
	ring.LineThickness = 0.04
	ring.Transparency = MiniEventConfig.Events.ColorRush.MarkTransparency
	ring.Parent = part
end

local function removeColorRushMark(cell: any)
	if not cell or not cell.part then
		return
	end
	cell.part:SetAttribute("EventMark", nil)
	local ring = cell.part:FindFirstChild("EventMarkRing")
	if ring then
		ring:Destroy()
	end
end

local function forEachCell(callback: (any, string) -> ())
	for _, zoneId in ipairs(allParticipatingBoards()) do
		local board = BubbleService.GetBoard(zoneId)
		if board then
			for x = 1, board.sizeX do
				local col = board.grid[x]
				if col then
					for z = 1, board.sizeZ do
						local cell = col[z]
						if cell then
							callback(cell, zoneId)
						end
					end
				end
			end
		end
	end
end

local function reservedColors(): { Color3 }
	local out = {}
	for _, def in ipairs(BubbleTypes.List) do
		if def.Id ~= "Normal" and def.Color then
			table.insert(out, def.Color)
		end
	end
	return out
end

local function cellColor(cell: any): Color3?
	if not cell or not cell.def or cell.def.Id ~= "Normal" then
		return nil
	end
	return BubbleAppearance.ResolveNormalColor(cell.zoneId, cell.tintIndex or 1)
end

local function startGoldenWave()
	local ratio = MiniEventConfig.Events.GoldenWave.InitialTransformRatio
	local eligible = {}
	forEachCell(function(cell, _zoneId)
		if MiniEventLogic.IsNormalEligibleForGolden(
			cell.def and cell.def.Id,
			cell.alive == true,
			cell.eventVariant
		) then
			table.insert(eligible, cell)
		end
	end)
	local picks = MiniEventLogic.SelectTransformIndices(#eligible, ratio, rng)
	for _, idx in ipairs(picks) do
		applyGoldenLook(eligible[idx])
	end
	log(("GoldenWave: %d / %d bulles transformées"):format(#picks, #eligible))
end

local function startColorRush()
	local observed = {}
	forEachCell(function(cell, _zoneId)
		if cell.alive and cell.def and cell.def.Id == "Normal" then
			local c = cellColor(cell)
			if c then
				table.insert(observed, c)
			end
		end
	end)
	targetColor = MiniEventLogic.PickTargetColor(observed, reservedColors(), 0.3, rng)
	if not targetColor then
		-- fallback palette GameRoom
		local palette = BubbleAppearance.GetNormalPalette("ClassicZone")
		if #palette > 0 then
			targetColor = palette[1]
		else
			targetColor = Color3.fromRGB(30, 95, 255)
		end
	end
	local matchDist = MiniEventConfig.Events.ColorRush.ColorMatchDistance
	forEachCell(function(cell, _zoneId)
		if cell.alive and cell.def and cell.def.Id == "Normal" then
			local c = cellColor(cell)
			if c and targetColor and MiniEventLogic.ColorsMatch(c, targetColor, matchDist) then
				applyColorRushMark(cell)
			end
		end
	end)
	log("ColorRush cible=" .. MiniEventConfig.ColorLabel(targetColor))
end

local function destroyGiants()
	for zoneId, part in pairs(giantParts) do
		if part and part.Parent then
			part:Destroy()
		end
		giantParts[zoneId] = nil
	end
	local folder = eventFolder
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child.Name:match("^GiantBubble_") then
				child:Destroy()
			end
		end
	end
end

local function spawnGiantInZone(zoneId: string)
	local board = BubbleService.GetBoard(zoneId)
	if not board then
		return
	end
	local cx = math.clamp(math.floor(board.sizeX / 2), 1, board.sizeX)
	local cz = math.clamp(math.floor(board.sizeZ / 2), 1, board.sizeZ)
	-- Chercher une cellule non réservée proche du centre
	local bestX, bestZ = cx, cz
	local found = false
	for radius = 0, 8 do
		for dx = -radius, radius do
			for dz = -radius, radius do
				local x, z = cx + dx, cz + dz
				if board.grid[x] and board.grid[x][z] then
					bestX, bestZ = x, z
					found = true
					break
				end
			end
			if found then
				break
			end
		end
		if found then
			break
		end
	end
	local world = BubbleService.CellToWorld(bestX, bestZ, zoneId)
	local gcfg = MiniEventConfig.Events.GiantBubble
	local part = Instance.new("Part")
	part.Name = "GiantBubble_" .. zoneId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = true
	part.CastShadow = false
-- Giant glass sombre la grille ; coller le look matte zone principale.
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(255, 210, 80)
	part.Transparency = 0.05
	part.Reflectance = 0
	part.Size = Vector3.new(8, 8, 8)
	part.CFrame = CFrame.new(world + Vector3.new(0, gcfg.HeightOffset, 0))
	part:SetAttribute("MiniEventGiant", true)
	part:SetAttribute("ZoneId", zoneId)
	part:SetAttribute("Hits", 0)
	part:SetAttribute("Required", giantRequired)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	-- Scale réduit si jamais re-activé (évite dôme plein écran).
	local visualScale = math.min(gcfg.Scale or 2, 2.2)
	mesh.Scale = Vector3.new(visualScale, visualScale, visualScale)
	mesh.Parent = part
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GiantLabel"
	billboard.Size = UDim2.fromOffset(120, 36)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 80
	billboard.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "GIANT"
	label.TextColor3 = Color3.fromRGB(255, 240, 180)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = billboard
	part.Parent = ensureFolder()
	giantParts[zoneId] = part
end

local function startGiantBubble()
	if MiniEventConfig.IsEventEnabled("GiantBubble") ~= true then
		log("GiantBubble désactivé — aucun spawn")
		return
	end
	giantProgress = 0
	giantContrib = {}
	giantHitCooldown = {}
	giantCompleted = false
	giantFailed = false
	rewardedUserIds = {}
	analyticsMilestonesSent = {}
	local playersAtStart = math.max(1, #Players:GetPlayers())
	local base, per = MiniEventConfig.GetGiantHits(playersAtStart)
	giantRequired = MiniEventLogic.ComputeRequiredHits(base, per, playersAtStart)
	destroyGiants()
	local zones = activeZoneIdsWithPlayers()
	if #zones == 0 then
		zones = allParticipatingBoards()
	end
	for _, zoneId in ipairs(zones) do
		if playersInZone(zoneId) > 0 or forcedTesting then
			spawnGiantInZone(zoneId)
		end
	end
	log(("GiantBubble required=%d zones=%d"):format(giantRequired, #zones))
end

local function grantRewards(succeeded: boolean)
	if not succeeded then
		return
	end
	local g = MiniEventConfig.Events.GiantBubble
	for _, player in ipairs(Players:GetPlayers()) do
		local uid = player.UserId
		if rewardedUserIds[uid] then
			continue
		end
		local contrib = giantContrib[uid] or 0
		local bonus = MiniEventLogic.ComputeSellBonus(
			contrib,
			giantRequired,
			g.MinimumContribution,
			g.BaseSellBonus,
			g.SellBonusPerHit,
			g.CompletionBonus,
			true
		)
		if bonus <= 0 then
			continue
		end
		local d = DataService.Get(player)
		if not d then
			continue
		end
		d.PendingSellBonus = math.max(0, math.floor(tonumber(d.PendingSellBonus) or 0)) + bonus
		d.__dirty = true
		rewardedUserIds[uid] = true
		DataService.Push(player)
		softGas("OnMiniEventRewardGranted", player, {
			eventType = "GiantBubble",
			playerContribution = contrib,
			rewardValue = bonus,
			completed = true,
		})
		broadcast("Ended", "Complete", { sellBonus = bonus }, player)
		pcall(function()
			Remotes.Event("Announce"):FireClient(
				player,
				L10n.MiniEventSellBonusFmt:format(bonus),
				"mini_event"
			)
		end)
	end
end

local function cleanupActiveVisuals()
	forEachCell(function(cell, _zoneId)
		if cell.eventVariant == "GoldenWave" or cell.part and cell.part:GetAttribute("EventVariant") == "GoldenWave" then
			clearEventAttributes(cell)
		end
		removeColorRushMark(cell)
	end)
	destroyGiants()
	targetColor = nil
	giantProgress = 0
	giantRequired = 0
	giantContrib = {}
	giantHitCooldown = {}
	giantCompleted = false
	giantFailed = false
	clearSessionStats()
end

local function setState(newState: string): boolean
	if not MiniEventLogic.CanTransition(machineState, newState) and machineState ~= newState then
		-- Autoriser Idle forcé depuis Cleanup/testing
		if not (newState == MiniEventLogic.STATES.Idle) then
			warn(("[MiniEventService] transition refusée %s → %s"):format(machineState, newState))
			return false
		end
	end
	machineState = newState
	return true
end

local function endActive(succeeded: boolean)
	if machineState ~= MiniEventLogic.STATES.Active and machineState ~= MiniEventLogic.STATES.Countdown then
		return
	end
	phaseGeneration += 1
	local gen = phaseGeneration
	local eventType = currentEventType
	setState(MiniEventLogic.STATES.Cleanup)

	if eventType == "GiantBubble" then
		if succeeded then
			giantCompleted = true
			grantRewards(true)
			softGas("OnMiniEventCompleted", nil, {
				eventType = eventType,
				duration = nowServer() - activeServerClockStart,
				participantCount = 0,
				requiredProgress = giantRequired,
				completed = true,
			})
			for _, p in ipairs(Players:GetPlayers()) do
				local contrib = giantContrib[p.UserId] or 0
				if contrib > 0 then
					pcall(function()
						local CS = require(script.Parent.ChallengeService)
						CS.OnMiniEventCompleted(p, eventType)
						CS.OnGiantCompleted(p)
					end)
				end
				if not rewardedUserIds[p.UserId] then
					broadcast("Ended", "Complete", nil, p)
				end
			end
		else
			giantFailed = true
			softGas("OnMiniEventFailed", nil, {
				eventType = eventType,
				completed = false,
				requiredProgress = giantRequired,
			})
			broadcast("Ended", "Failed", nil, nil)
		end
	else
		broadcast("Ended", "Complete", nil, nil)
		softGas("OnMiniEventCompleted", nil, {
			eventType = eventType,
			duration = MiniEventConfig.GetDuration(eventType or ""),
			completed = true,
		})
		for _, p in ipairs(Players:GetPlayers()) do
			pcall(function()
				require(script.Parent.ChallengeService).OnMiniEventCompleted(p, eventType or "")
			end)
		end
	end

	cleanupActiveVisuals()
	lastEventType = eventType
	currentEventType = nil
	forcedTesting = false

	task.delay(MiniEventConfig.EndedBannerSeconds, function()
		if gen ~= phaseGeneration then
			return
		end
		setState(MiniEventLogic.STATES.Cooldown)
		local lo, hi = MiniEventConfig.GetIntervalRange()
		local waitTime = MiniEventLogic.RandomInterval(lo, hi, rng)
		phaseEndsAt = os.clock() + waitTime
		task.delay(waitTime, function()
			if gen ~= phaseGeneration then
				return
			end
			setState(MiniEventLogic.STATES.Idle)
			machineState = MiniEventLogic.STATES.Idle
		end)
	end)
end

local function beginActive(gen: number)
	if gen ~= phaseGeneration then
		return
	end
	if not setState(MiniEventLogic.STATES.Active) then
		-- forcer si countdown ok
		machineState = MiniEventLogic.STATES.Active
	end
	local eventType = currentEventType
	if not eventType then
		return
	end

	eventParticipants = {}
	clearSessionStats()

	local duration = MiniEventConfig.GetDuration(eventType)
	activeServerClockStart = nowServer()
	activeServerClockEnd = activeServerClockStart + duration
	phaseStartedAt = os.clock()
	phaseEndsAt = phaseStartedAt + duration

	if eventType == "GoldenWave" then
		startGoldenWave()
	elseif eventType == "ColorRush" then
		startColorRush()
	elseif eventType == "GiantBubble" then
		if MiniEventConfig.IsEventEnabled("GiantBubble") then
			startGiantBubble()
		else
			log("Active sans GiantBubble (désactivé)")
		end
	end

	broadcast("Active", nil, nil, nil)
	softGas("OnMiniEventStarted", nil, {
		eventType = eventType,
		duration = duration,
		zoneId = table.concat(allParticipatingBoards(), ","),
	})

	task.delay(duration, function()
		if gen ~= phaseGeneration then
			return
		end
		if machineState ~= MiniEventLogic.STATES.Active then
			return
		end
		local success = false
		if eventType == "GiantBubble" then
			success = giantCompleted
		else
			success = true
		end
		endActive(success)
	end)
end

local function beginCountdown(eventType: string)
	if machineState ~= MiniEventLogic.STATES.Idle and not forcedTesting then
		return false
	end
	if machineState == MiniEventLogic.STATES.Active or machineState == MiniEventLogic.STATES.Countdown then
		return false
	end

	phaseGeneration += 1
	local gen = phaseGeneration
	machineState = MiniEventLogic.STATES.Countdown
	currentEventType = eventType

	local countdown = MiniEventConfig.GetCountdownSeconds()
	local duration = MiniEventConfig.GetDuration(eventType)
	activeServerClockStart = nowServer() + countdown
	activeServerClockEnd = activeServerClockStart + duration
	phaseEndsAt = os.clock() + countdown

	-- Pré-calc objective pour ColorRush / Giant
	if eventType == "GoldenWave" then
		-- rien
	elseif eventType == "ColorRush" then
		-- estimer couleur pendant countdown pour HUD
		local observed = {}
		forEachCell(function(cell, _z)
			if cell.alive and cell.def and cell.def.Id == "Normal" then
				local c = cellColor(cell)
				if c then
					table.insert(observed, c)
				end
			end
		end)
		targetColor = MiniEventLogic.PickTargetColor(observed, reservedColors(), 0.3, rng)
	elseif eventType == "GiantBubble" then
		local playersAtStart = math.max(1, #Players:GetPlayers())
		local base, per = MiniEventConfig.GetGiantHits(playersAtStart)
		giantRequired = MiniEventLogic.ComputeRequiredHits(base, per, playersAtStart)
	end

	broadcast("Countdown", nil, nil, nil)
	softGas("OnMiniEventCountdownStarted", nil, {
		eventType = eventType,
		duration = countdown,
	})

	task.delay(countdown, function()
		if gen ~= phaseGeneration then
			return
		end
		if #Players:GetPlayers() == 0 then
			cleanupActiveVisuals()
			currentEventType = nil
			machineState = MiniEventLogic.STATES.Idle
			return
		end
		beginActive(gen)
	end)
	return true
end

local function tryScheduleNext(isFirst: boolean)
	if not MiniEventConfig.Enabled and not forcedTesting then
		return
	end
	schedulerToken += 1
	local token = schedulerToken
	local delaySec = if isFirst
		then MiniEventConfig.GetFirstDelay()
		else select(1, MiniEventConfig.GetIntervalRange())

	if not isFirst then
		local lo, hi = MiniEventConfig.GetIntervalRange()
		delaySec = MiniEventLogic.RandomInterval(lo, hi, rng)
	end

	task.delay(delaySec, function()
		if token ~= schedulerToken then
			return
		end
		if machineState ~= MiniEventLogic.STATES.Idle then
			tryScheduleNext(false)
			return
		end
		local inZones = countPlayersInBubbleZones()
		if not MiniEventLogic.CanStartScheduler(
			MiniEventConfig.Enabled,
			#Players:GetPlayers(),
			MiniEventConfig.MinPlayers,
			math.max(inZones, if forcedTesting then 1 else 0)
		) then
			tryScheduleNext(false)
			return
		end
		local featured: string? = nil
		local featMult: number? = MiniEventConfig.FeaturedEventWeightMultiplier
		pcall(function()
			local ChallengeService = require(script.Parent.ChallengeService)
			if ChallengeService.GetFeaturedEventType then
				featured = ChallengeService.GetFeaturedEventType()
			end
		end)
		local pick = MiniEventLogic.PickNextEvent(
			MiniEventConfig.ListEnabledEvents(),
			lastEventType,
			rng,
			featured,
			featMult
		)
		if not pick then
			tryScheduleNext(false)
			return
		end
		beginCountdown(pick)
		-- re-schedule after event ends via Cooldown idle; watch loop handles
		task.spawn(function()
			while token == schedulerToken do
				task.wait(2)
				if machineState == MiniEventLogic.STATES.Idle and token == schedulerToken then
					-- schedule following cooldown path already sets idle after delay
					-- only re-arm if idle for a bit without schedule
					tryScheduleNext(false)
					break
				end
			end
		end)
	end)
end

--------------------------------------------------------------------
-- API publique (hooks bulles / outils)
--------------------------------------------------------------------
function MiniEventService.GetPopSellMultiplier(cell: any): number
	if machineState ~= MiniEventLogic.STATES.Active or not currentEventType then
		return 1
	end
	local rarityId = cell and cell.def and cell.def.Id
	local variant = cell and (cell.eventVariant or (cell.part and cell.part:GetAttribute("EventVariant")))
	local colorMatch = false
	if currentEventType == "ColorRush" and targetColor and rarityId == "Normal" then
		local c = cellColor(cell)
		if c then
			colorMatch = MiniEventLogic.ColorsMatch(
				c,
				targetColor,
				MiniEventConfig.Events.ColorRush.ColorMatchDistance
			)
		end
	end
	return MiniEventLogic.GetPopSellMultiplier(
		currentEventType,
		true,
		rarityId,
		if type(variant) == "string" then variant else nil,
		colorMatch
	)
end

function MiniEventService.OnBubbleReady(cell: any)
	if machineState ~= MiniEventLogic.STATES.Active or not cell then
		return
	end
	if currentEventType == "GoldenWave" then
		if MiniEventLogic.IsNormalEligibleForGolden(
			cell.def and cell.def.Id,
			cell.alive == true,
			cell.eventVariant
		) then
			if MiniEventLogic.ShouldBecomeGoldenOnRegen(
				MiniEventConfig.Events.GoldenWave.RegenGoldenChance,
				rng
			) then
				applyGoldenLook(cell)
			end
		end
	elseif currentEventType == "ColorRush" and targetColor then
		if cell.alive and cell.def and cell.def.Id == "Normal" then
			local c = cellColor(cell)
			if c and MiniEventLogic.ColorsMatch(
				c,
				targetColor,
				MiniEventConfig.Events.ColorRush.ColorMatchDistance
			) then
				applyColorRushMark(cell)
			end
		end
	end
end

function MiniEventService.GetPopChallengeTags(cell: any): { isGoldenWave: boolean, isColorRushMatch: boolean }
	local isGolden = false
	local isColor = false
	if not cell then
		return { isGoldenWave = false, isColorRushMatch = false }
	end
	local variant = cell.eventVariant or (cell.part and cell.part:GetAttribute("EventVariant"))
	if variant == "GoldenWave" then
		isGolden = true
	end
	if machineState == MiniEventLogic.STATES.Active and currentEventType == "ColorRush" and targetColor then
		local rarityId = cell.def and cell.def.Id
		if rarityId == "Normal" then
			local c = cellColor(cell)
			if c then
				isColor = MiniEventLogic.ColorsMatch(
					c,
					targetColor,
					MiniEventConfig.Events.ColorRush.ColorMatchDistance
				)
			end
		end
	end
	return { isGoldenWave = isGolden, isColorRushMatch = isColor }
end

function MiniEventService.OnBubblePopped(player: Player, cell: any, eventBonusCoins: number?)
	-- Tags AVANT clear des attributs cellule.
	local tags = MiniEventService.GetPopChallengeTags(cell)
	local bonus = math.max(0, math.floor(tonumber(eventBonusCoins) or 0))

	-- Participation GoldenWave / ColorRush : premier pop valide pendant l'événement.
	if machineState == MiniEventLogic.STATES.Active and currentEventType then
		local et = currentEventType
		if et == "GoldenWave" or et == "ColorRush" then
			local uid = player.UserId
			if not eventParticipants[uid] then
				eventParticipants[uid] = true
				softGas("OnMiniEventParticipationStarted", player, {
					eventType = et,
				})
				pcall(function()
					require(script.Parent.ChallengeService).OnMiniEventJoined(player, et)
				end)
			end

			local counts = (et == "GoldenWave" and tags.isGoldenWave == true)
				or (et == "ColorRush" and tags.isColorRushMatch == true)
			if counts then
				local stats = getSessionStats(uid)
				stats.progress += 1
				stats.bonusCoins += bonus
				maybeBroadcastPlayerProgress(player)
			end
		end
	end
	if cell then
		cell.eventVariant = nil
		if cell.part then
			cell.part:SetAttribute("EventVariant", nil)
			local ring = cell.part:FindFirstChild("EventMarkRing")
			if ring then
				ring:Destroy()
			end
		end
	end
end

function MiniEventService.TryGiantHit(player: Player, position: Vector3, toolId: string?): boolean
	if machineState ~= MiniEventLogic.STATES.Active or currentEventType ~= "GiantBubble" then
		return false
	end
	if giantCompleted or giantFailed then
		return false
	end
	local d = DataService.Get(player)
	if not d then
		return false
	end
	local now = os.clock()
	local cd = MiniEventConfig.Events.GiantBubble.HitCooldown
	if (giantHitCooldown[player.UserId] or 0) > now then
		return false
	end

	local maxRange = MiniEventConfig.Events.GiantBubble.MaxInteractRange
	local targetPart: BasePart? = nil
	local best = maxRange + 1
	for _zoneId, part in pairs(giantParts) do
		if part and part.Parent then
			local dist = (Vector3.new(part.Position.X, 0, part.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
			if dist < best then
				best = dist
				targetPart = part
			end
		end
	end
	if not targetPart or best > maxRange then
		return false
	end

	-- zone unlock
	local zoneId = targetPart:GetAttribute("ZoneId")
	if type(zoneId) == "string" and ZoneDefs.Get(zoneId) then
		if not ZoneDefs.CanLevelEnter(DataService.GetPlayerLevel(player), zoneId) then
			return false
		end
	end

	local pts = MiniEventLogic.ContributionForTool(toolId)
	giantHitCooldown[player.UserId] = now + cd
	giantContrib[player.UserId] = (giantContrib[player.UserId] or 0) + pts
	giantProgress = math.min(giantRequired, giantProgress + pts)
	targetPart:SetAttribute("Hits", giantProgress)

	local mesh = targetPart:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		local ratio = 1 - (giantProgress / math.max(1, giantRequired)) * 0.35
		local base = MiniEventConfig.Events.GiantBubble.Scale
		mesh.Scale = Vector3.new(base * ratio, base * ratio, base * ratio)
	end

	local prevRatio = (giantProgress - pts) / math.max(1, giantRequired)
	local newRatio = giantProgress / math.max(1, giantRequired)
	for _, m in ipairs(MiniEventLogic.CrossedMilestones(prevRatio, newRatio, MiniEventConfig.Events.GiantBubble.AnalyticsMilestones)) do
		if not analyticsMilestonesSent[m] then
			analyticsMilestonesSent[m] = true
			softGas("OnMiniEventProgress", player, {
				eventType = "GiantBubble",
				playerContribution = giantContrib[player.UserId],
				requiredProgress = giantRequired,
				completed = m >= 1,
				value = m,
			})
		end
	end

	if now - lastProgressBroadcast >= MiniEventConfig.Events.GiantBubble.ProgressBroadcastMinInterval then
		lastProgressBroadcast = now
		broadcast("Active", nil, nil, nil)
	else
		broadcast("Active", nil, nil, player)
	end

	if giantContrib[player.UserId] == pts then
		softGas("OnMiniEventParticipationStarted", player, {
			eventType = "GiantBubble",
			playerContribution = pts,
		})
		pcall(function()
			require(script.Parent.ChallengeService).OnMiniEventJoined(player, "GiantBubble")
		end)
	end
	pcall(function()
		require(script.Parent.ChallengeService).OnGiantHit(player, pts)
	end)

	if giantProgress >= giantRequired and not giantCompleted then
		giantCompleted = true
		-- pop visual
		for _, part in pairs(giantParts) do
			if part and part.Parent then
				part.Transparency = 1
				part.CanQuery = false
			end
		end
		endActive(true)
	end
	return true
end

function MiniEventService.GetState(): string
	return machineState
end

function MiniEventService.GetCurrentEventType(): string?
	return currentEventType
end

function MiniEventService.ForceStartForTesting(eventType: string): boolean
	if not RunService:IsStudio() then
		warn("[MiniEventService] ForceStartForTesting réservé à Studio")
		return false
	end
	if not MiniEventLogic.IsValidEventType(eventType) then
		warn("[MiniEventService] type inconnu: " .. tostring(eventType))
		return false
	end
	if eventType == "GiantBubble" and MiniEventConfig.IsEventEnabled("GiantBubble") ~= true then
		warn("[MiniEventService] GiantBubble désactivé — pas de dôme cyan")
		return false
	end
	if machineState == MiniEventLogic.STATES.Active or machineState == MiniEventLogic.STATES.Countdown then
		MiniEventService.ForceStopForTesting()
		task.wait(0.1)
	end
	forcedTesting = true
	machineState = MiniEventLogic.STATES.Idle
	return beginCountdown(eventType)
end

function MiniEventService.ForceStopForTesting()
	if not RunService:IsStudio() then
		return
	end
	phaseGeneration += 1
	local et = currentEventType
	if et then
		broadcast("Ended", "Failed", nil, nil)
	end
	cleanupActiveVisuals()
	currentEventType = nil
	forcedTesting = false
	machineState = MiniEventLogic.STATES.Idle
end

function MiniEventService.Start()
	if started then
		return
	end
	started = true

	-- Purge dômes GiantBubble persistants (sessions précédentes / leftover Workspace).
	destroyGiants()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") and (inst.Name:match("^GiantBubble_") or inst:GetAttribute("MiniEventGiant") == true) then
			inst:Destroy()
		end
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			if currentEventType and (machineState == MiniEventLogic.STATES.Countdown or machineState == MiniEventLogic.STATES.Active) then
				local stateNet = if machineState == MiniEventLogic.STATES.Countdown then "Countdown" else "Active"
				broadcast(stateNet, nil, nil, player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		giantHitCooldown[player.UserId] = nil
		if #Players:GetPlayers() <= 1 and (machineState == MiniEventLogic.STATES.Active or machineState == MiniEventLogic.STATES.Countdown) then
			-- le joueur qui part est encore dans la liste parfois : différer
			task.defer(function()
				if #Players:GetPlayers() == 0 then
					phaseGeneration += 1
					cleanupActiveVisuals()
					currentEventType = nil
					machineState = MiniEventLogic.STATES.Idle
					log("arrêt : aucun joueur restant")
				end
			end)
		end
	end)

	if MiniEventConfig.Enabled then
		task.defer(function()
			task.wait(2) -- laisser zones / boards se monter
			tryScheduleNext(true)
		end)
	end

	if RunService:IsStudio() then
		(_G :: any).MiniEventForceStart = function(eventType: string)
			return MiniEventService.ForceStartForTesting(eventType)
		end
		(_G :: any).MiniEventForceStop = function()
			MiniEventService.ForceStopForTesting()
		end
		log("Studio: _G.MiniEventForceStart(\"GoldenWave\"|\"ColorRush\"|\"GiantBubble\")")
	end

	log("démarré Enabled=" .. tostring(MiniEventConfig.Enabled))
end

return MiniEventService
