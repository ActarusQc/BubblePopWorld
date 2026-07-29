--!strict
-- Fabrique les Tools, valide les activations et applique les patrons d'éclatement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local ZoneDefs = require(Shared.ZoneDefs)
local ToolDefs = require(Shared.ToolDefs)
local Remotes = require(Shared.Remotes)
local L10n = require(Shared.LocalizationStrings)

local BubbleService = require(script.Parent.BubbleService)
local DataService = require(script.Parent.DataService)
local ToolModels = require(script.Parent.ToolModels)
local BackpackVisual = require(script.Parent.BackpackVisual)

local ToolService = {}
local cooldowns: { [Player]: { [string]: number } } = {}

local function gridStep(v: Vector3): (number, number)
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 0.05 then
		return 0, -1
	end
	flat = flat.Unit
	if math.abs(flat.X) >= math.abs(flat.Z) then
		return if flat.X >= 0 then 1 else -1, 0
	end
	return 0, if flat.Z >= 0 then 1 else -1
end

local function findWingToggle(player: Player): Tool?
	local function scan(container: Instance?): Tool?
		if not container then return nil end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("ToolId") == "Ailes" then
				return child
			end
		end
		return nil
	end
	return scan(player:FindFirstChildOfClass("Backpack")) or scan(player.Character)
end

local function ensureWingToggleTool(player: Player): Tool?
	local existing = findWingToggle(player)
	if existing then return existing end

	local def = ToolDefs.List.Ailes
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.ToolTip = "RT / click: equip or unequip the wings"
	tool:SetAttribute("ToolId", "Ailes")
	tool:SetAttribute("Permanent", true)
	tool:SetAttribute("Consumable", false)
	tool:SetAttribute("SelfCentered", true)
	tool:SetAttribute("WingCells", def.WingCells or 5)
	tool:SetAttribute("SupportsMobileAction", def.SupportsMobileAction == true)
	tool:SetAttribute("RequiresTarget", false)
	tool:SetAttribute("MobileActionLabel", def.MobileActionLabel or "USE")
	tool:SetAttribute("IconGlyph", def.IconGlyph or "🪽")
	tool:SetAttribute("Cooldown", def.Cooldown or 0)
	ToolModels.Apply(tool, "Ailes", def)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		tool.Parent = backpack
	end
	return tool
end

local function setWingsEquipped(player: Player, equipped: boolean)
	player:SetAttribute("HasWings", equipped)
	local char = player.Character
	if not char then return end
	if equipped then
		ToolModels.AttachWings(char)
	else
		ToolModels.DetachWings(char)
	end
	BackpackVisual.Refresh(char)
end

local function toggleWings(player: Player)
	if player:GetAttribute("OwnsWings") ~= true then return end
	local equipped = player:GetAttribute("HasWings") == true
	setWingsEquipped(player, not equipped)
	if not equipped then
		Remotes.Event("Announce"):FireClient(player, L10n.WingsOn, "item")
	else
		Remotes.Event("Announce"):FireClient(player, L10n.WingsOff, "item")
	end
end

local function grantWings(player: Player)
	if player:GetAttribute("OwnsWings") == true then
		ensureWingToggleTool(player)
		Remotes.Event("Announce"):FireClient(player, L10n.AlreadyOwnWings, "item")
		return
	end

	player:SetAttribute("OwnsWings", true)
	setWingsEquipped(player, true)
	ensureWingToggleTool(player)
	Remotes.Event("Announce"):FireClient(
		player,
		L10n.WingsUnlocked,
		"item"
	)
end

function ToolService.CreateTool(id: string): Tool?
	local def = ToolDefs.List[id]
	if not def then return nil end
	if id == "Ailes" then
		-- Créé via ensureWingToggleTool
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.ToolTip = def.Desc
	tool:SetAttribute("ToolId", id)
	tool:SetAttribute("Cooldown", def.Cooldown)
	tool:SetAttribute("Range", def.Range)
	tool:SetAttribute("SelfCentered", def.SelfCentered == true)
	tool:SetAttribute("Consumable", def.Consumable == true)
	tool:SetAttribute("Permanent", def.Permanent == true)
	tool:SetAttribute("WingCells", def.WingCells or 0)
	tool:SetAttribute("SupportsMobileAction", def.SupportsMobileAction == true)
	tool:SetAttribute("RequiresTarget", def.RequiresTarget == true)
	tool:SetAttribute("MobileActionLabel", def.MobileActionLabel or "USE")
	tool:SetAttribute("IconGlyph", def.IconGlyph or "✦")
	if type(def.IconImage) == "string" then
		tool:SetAttribute("IconImage", def.IconImage)
	end

	ToolModels.Apply(tool, id, def)
	return tool
end

function ToolService.Give(player: Player, id: string)
	local def = ToolDefs.List[id]
	if not def then return end

	if id == "Ailes" then
		grantWings(player)
		return
	end

	local tool = ToolService.CreateTool(id)
	if not tool then return end
	tool.Parent = player:FindFirstChildOfClass("Backpack")

	Remotes.Event("Announce"):FireClient(
		player,
		("Item: %s (1 use) — equip it, then RT / click"):format(def.Name),
		"item"
	)

	if def.Announce then
		Remotes.Event("Announce"):FireAllClients(
			("%s found the mythic item %s!"):format(player.DisplayName, def.Name), "legendary")
		local profile = DataService.Get(player)
		if profile then profile.MythicsFound += 1 end
	end
end

local function resolveCells(def, cx: number, cz: number, direction: Vector3, zoneId: string)
	local cells = {}
	if def.Shape == "Single" then
		table.insert(cells, { cx, cz })

	elseif def.Shape == "Cross" then
		local fx, fz = gridStep(direction)
		local right = Vector3.new(-direction.Z, 0, direction.X)
		local rx, rz = gridStep(right)
		table.insert(cells, { cx + fx, cz + fz })
		table.insert(cells, { cx - fx, cz - fz })
		table.insert(cells, { cx + rx, cz + rz })
		table.insert(cells, { cx - rx, cz - rz })

	elseif def.Shape == "Around" then
		local r = def.Radius
		for dx = -r, r do
			for dz = -r, r do
				if dx ~= 0 or dz ~= 0 then
					table.insert(cells, { cx + dx, cz + dz })
				end
			end
		end

	elseif def.Shape == "Square" then
		for dx = -def.Radius, def.Radius do
			for dz = -def.Radius, def.Radius do
				table.insert(cells, { cx + dx, cz + dz })
			end
		end

	elseif def.Shape == "Disc" then
		local r = def.Radius
		for dx = -r, r do
			for dz = -r, r do
				if dx * dx + dz * dz <= r * r then
					table.insert(cells, { cx + dx, cz + dz })
				end
			end
		end

	elseif def.Shape == "FullRow" then
		local _, sizeZ = ZoneDefs.GetGridSize(zoneId)
		for z = 1, sizeZ do
			for dx = -def.Radius + 1, def.Radius - 1 do
				table.insert(cells, { cx + dx, z })
			end
		end

	elseif def.Shape == "Line" then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, 1) end
		flat = flat.Unit
		local stepX = if math.abs(flat.X) > math.abs(flat.Z) then (if flat.X > 0 then 1 else -1) else 0
		local stepZ = if stepX == 0 then (if flat.Z > 0 then 1 else -1) else 0
		for i = 0, def.Radius do
			table.insert(cells, { cx + stepX * i, cz + stepZ * i })
		end
	end
	return cells
end

local function onActivate(player: Player, _toolName: any, targetPos: any)
	if typeof(targetPos) ~= "Vector3" then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not root or not tool then return end

	local id = tool:GetAttribute("ToolId")
	if type(id) ~= "string" then return end
	local def = ToolDefs.List[id]
	if not def then return end

	-- Ailes : bascule mettre / retirer (dans le dos)
	if id == "Ailes" then
		toggleWings(player)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack and tool.Parent == char then
			tool.Parent = backpack -- libère la main
		end
		return
	end

	local now = os.clock()
	cooldowns[player] = cooldowns[player] or {}
	if (cooldowns[player][id] or 0) > now then return end

	local selfCentered = def.SelfCentered == true
	local origin = if selfCentered then root.Position else targetPos
	if not selfCentered and (root.Position - targetPos).Magnitude > def.Range + 10 then
		return
	end

	local cx, cz, zoneId = BubbleService.WorldToCell(origin)
	if def.Shape == "Single" and not BubbleService.IsAlive(cx, cz, zoneId) then
		return
	end

	local direction = if selfCentered
		then root.CFrame.LookVector
		else (targetPos - root.Position)

	local cells = resolveCells(def, cx, cz, direction, zoneId)
	-- Annoter chaque cellule avec la zone sous le joueur
	local zoned: { { any } } = {}
	for _, c in ipairs(cells) do
		table.insert(zoned, { c[1], c[2], zoneId })
	end
	local count = BubbleService.PopCells(player, zoned, def.Multiplier, zoneId)
	if count <= 0 then return end

	cooldowns[player][id] = now + def.Cooldown

	if def.Consumable ~= false and tool.Parent then
		tool:Destroy()
	end
end

function ToolService.Start()
	Remotes.Event("ToolActivate").OnServerEvent:Connect(onActivate)
	Players.PlayerRemoving:Connect(function(p)
		cooldowns[p] = nil
		p:SetAttribute("HasWings", nil)
		p:SetAttribute("OwnsWings", nil)
	end)

	local function onCharacter(player: Player, char: Model)
		BackpackVisual.Attach(char)
		if player:GetAttribute("OwnsWings") == true then
			ensureWingToggleTool(player)
			if player:GetAttribute("HasWings") == true then
				ToolModels.AttachWings(char)
				BackpackVisual.Refresh(char)
			else
				ToolModels.DetachWings(char)
			end
		end
	end

	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function(char)
			task.defer(onCharacter, player, char)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end

	local function convertLegacy(player: Player)
		-- Ancien Tool Ailes sans OwnsWings → ownership + équipé
		local found = findWingToggle(player) ~= nil
		if player:GetAttribute("HasWings") == true and player:GetAttribute("OwnsWings") ~= true then
			player:SetAttribute("OwnsWings", true)
			found = true
		end
		if found or player:GetAttribute("OwnsWings") == true then
			player:SetAttribute("OwnsWings", true)
			if player:GetAttribute("HasWings") == nil then
				player:SetAttribute("HasWings", true)
			end
			ensureWingToggleTool(player)
			if player.Character and player:GetAttribute("HasWings") == true then
				ToolModels.AttachWings(player.Character)
				BackpackVisual.Refresh(player.Character)
			end
		end
	end

	Players.PlayerAdded:Connect(function(p)
		watchCharacter(p)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		watchCharacter(p)
		convertLegacy(p)
	end
end

return ToolService
