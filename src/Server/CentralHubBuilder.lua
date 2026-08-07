--!strict
-- Hub central simplifié (Parts/Models modulaires).
-- Chaque module est un Model indépendant déplaçable dans Studio.
-- Fonctions branchées : spawn, SellZone, shop prompt, leaderboard face.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.GameConfig)
local HubLayout = require(Shared.HubLayout)
local L10n = require(Shared.LocalizationStrings)
local HubShopPromptLogic = require(Shared.HubShopPromptLogic)
local RearHubMigration = require(script.Parent.RearHubMigration)

local function tagBoard(part: BasePart, tag: string)
	part:SetAttribute(tag, true)
	pcall(function()
		CollectionService:AddTag(part, tag)
	end)
end

local CentralHubBuilder = {}

local H = Config.Hub
local C = H.Colors

local ROOT_NAME = "CentralHub"
local MODULES = "Modules"
local FUNCTION = "HubFunction"

local spawnMarker: BasePart? = nil
local spawnLocation: SpawnLocation? = nil
local sellZone: BasePart? = nil
local topBoard: BasePart? = nil
local sellValueBoard: BasePart? = nil
local mainHubFloor: BasePart? = nil

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
local GEN_BY = "CentralHubBuilder"

local function markGenerated(inst: Instance)
	inst:SetAttribute("BPW_GeneratedBy", GEN_BY)
	inst:SetAttribute("GeneratedByCode", true)
end

local function isProtectedTripo(inst: Instance): boolean
	if inst:GetAttribute("BPW_HubRole") == "RearHubPlatform" then
		return true
	end
	if inst:GetAttribute("BPW_TripoSource") == true then
		return true
	end
	if inst:GetAttribute("BPW_RearHubFolder") == true then
		return true
	end
	if CollectionService:HasTag(inst, "BPW_RearHubPlatform") then
		return true
	end
	local n = string.lower(inst.Name)
	if string.find(n, "3d stage arena", 1, true)
		or string.find(n, "stage arena prop", 1, true)
		or n == "triporearhubplatform"
		or n == "rearhub"
	then
		return true
	end
	if inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("MeshPart") then
				local mid = ""
				pcall(function()
					mid = (d :: MeshPart).MeshId
				end)
				if mid ~= "" then
					-- Contient de la géométrie importée : ne jamais ClearAllChildren
					if string.find(n, "hub", 1, true) or string.find(n, "tripo", 1, true) or string.find(n, "stage", 1, true) then
						return true
					end
				end
			end
		end
	end
	return false
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing and not isProtectedTripo(existing) then
		existing:Destroy()
	elseif existing then
		warn("[CentralHubBuilder] refuse de détruire folder protégé:", existing:GetFullName())
		local f = Instance.new("Folder")
		f.Name = name .. "_Code"
		markGenerated(f)
		f.Parent = parent
		return f
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	markGenerated(folder)
	folder.Parent = parent
	return folder
end

local function destroyGeneratedDescendants(container: Instance)
	local doomed: { Instance } = {}
	for _, child in ipairs(container:GetChildren()) do
		if isProtectedTripo(child) then
			continue
		end
		if child:GetAttribute("BPW_GeneratedBy") == GEN_BY
			or child:GetAttribute("GeneratedByCode") == true
			or child:GetAttribute("BPW_HubModule") == true
		then
			table.insert(doomed, child)
		end
	end
	for _, inst in ipairs(doomed) do
		inst:Destroy()
	end
end

-- Remplace ClearAllChildren : uniquement contenu généré par ce builder.
local function ensureModel(parent: Instance, name: string): Model
	local existing = parent:FindFirstChild(name)
	if existing and isProtectedTripo(existing) then
		error("[CentralHubBuilder] refuse d'écraser un modèle Tripo protégé: " .. existing:GetFullName())
	end
	if existing and existing:IsA("Model") then
		if existing:GetAttribute("BPW_GeneratedBy") == GEN_BY
			or existing:GetAttribute("GeneratedByCode") == true
			or existing:GetAttribute("BPW_HubModule") == true
		then
			destroyGeneratedDescendants(existing)
			-- Vider enfants générés restants (parts du modèle)
			local doomed = {}
			for _, c in ipairs(existing:GetChildren()) do
				if not isProtectedTripo(c) then
					table.insert(doomed, c)
				end
			end
			for _, c in ipairs(doomed) do
				c:Destroy()
			end
			return existing
		end
		-- Model non marqué : ne pas ClearAllChildren, détruire seulement si pure code name
		existing:Destroy()
	elseif existing then
		if not isProtectedTripo(existing) then
			existing:Destroy()
		end
	end
	local model = Instance.new("Model")
	model.Name = name
	markGenerated(model)
	model:SetAttribute("BPW_HubModule", true)
	model.Parent = parent
	return model
end

type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	Shape: Enum.PartType?,
	Parent: Instance?,
}

local function makePart(props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or C.Deck
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	p:SetAttribute("GeneratedByCode", true)
	p:SetAttribute("BPW_GeneratedBy", GEN_BY)
	p.Parent = props.Parent
	return p
end

-- Cylindre Roblox : axe le long de X. diameter sur XZ, height sur Y.
local function makeDisc(props: {
	Name: string,
	Diameter: number,
	Height: number,
	Center: Vector3,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	Parent: Instance?,
}): Part
	return makePart({
		Name = props.Name,
		Size = Vector3.new(props.Height, props.Diameter, props.Diameter),
		CFrame = CFrame.new(props.Center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = props.Color,
		Material = props.Material,
		Transparency = props.Transparency,
		CanCollide = props.CanCollide,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
		Parent = props.Parent,
	})
end

local function makeWedge(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Parent: Instance?,
}): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = props.Name
	w.Anchored = true
	w.Size = props.Size
	w.CFrame = props.CFrame
	w.Color = props.Color or C.Deck
	w.Material = props.Material or Enum.Material.SmoothPlastic
	w.CanCollide = true
	w.CanTouch = false
	w.CastShadow = false
	w:SetAttribute("GeneratedByCode", true)
	w:SetAttribute("BPW_GeneratedBy", GEN_BY)
	w.Parent = props.Parent
	return w
end

local function localCF(base: CFrame, offset: Vector3, extraYaw: number?): CFrame
	local cf = base * CFrame.new(offset)
	if extraYaw then
		cf = cf * CFrame.Angles(0, math.rad(extraYaw), 0)
	end
	return cf
end

local function setPrimary(model: Model, part: BasePart)
	model.PrimaryPart = part
	model.WorldPivot = part.CFrame
end

local function weldToPrimary(model: Model, primary: BasePart)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= primary then
			d.Anchored = true
		end
	end
end

--------------------------------------------------------------------
-- SurfaceGui helpers
--------------------------------------------------------------------
local function newSurface(part: BasePart, face: Enum.NormalId, pixelsPerStud: number?, name: string?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name or "HubGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 24
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ZOffset = 0.05
	gui.Parent = part
	return gui
end

local function newFrame(parent: Instance, size: UDim2, position: UDim2, color: Color3, corner: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, corner)
		c.Parent = f
	end
	return f
end

local function newLabel(parent: Instance, props: {
	Text: string,
	Size: UDim2,
	Position: UDim2,
	Color: Color3?,
	Stroke: Color3?,
	Font: Enum.Font?,
	Align: Enum.TextXAlignment?,
	Dynamic: boolean?,
}): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = props.Size
	t.Position = props.Position
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Text = props.Text
	t.TextColor3 = props.Color or C.White
	t.Font = props.Font or Enum.Font.GothamBold
	t.TextScaled = true
	t.TextXAlignment = props.Align or Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Parent = parent
	if props.Stroke then
		local s = Instance.new("UIStroke")
		s.Color = props.Stroke
		s.Thickness = 1.5
		s.Parent = t
	end
	if not props.Dynamic then
		local c = Instance.new("UITextSizeConstraint")
		c.MinTextSize = 10
		c.MaxTextSize = 72
		c.Parent = t
	end
	return t
end

local function panelBackdrop(gui: SurfaceGui, accent: Color3): Frame
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = C.PanelDeep
	root.BorderSizePixel = 0
	root.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.04, 0)
	pad.PaddingBottom = UDim.new(0.04, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = root
	local header = newFrame(root, UDim2.fromScale(0.96, 0.12), UDim2.fromScale(0.5, 0.08), accent, 8)
	header.Name = "HeaderStripe"
	header.ZIndex = 0
	return root
end

--------------------------------------------------------------------
-- Modules visuels
--------------------------------------------------------------------
local function buildHubPlatform(modules: Folder)
	local model = ensureModel(modules, "HubPlatform")
	local cx, cz = HubLayout.Center.X, HubLayout.Center.Z
	local topY = H.DeckTopY
	local diameter = math.min(H.DeckHalfX, H.DeckHalfZ) * 2 - 4
	local thickness = H.DeckThickness

	local deck = makeDisc({
		Name = "Deck",
		Diameter = diameter,
		Height = thickness,
		Center = Vector3.new(cx, topY - thickness / 2, cz),
		Color = C.Deck,
		Material = Enum.Material.Slate,
		Parent = model,
	})
	makeDisc({
		Name = "DeckRing",
		Diameter = diameter + 3,
		Height = 0.45,
		Center = Vector3.new(cx, topY - 0.15, cz),
		Color = C.DeckInlay,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})
	makeDisc({
		Name = "Plinth",
		Diameter = diameter - 6,
		Height = 2.2,
		Center = Vector3.new(cx, topY - thickness - 1.1, cz),
		Color = C.Foundation,
		Material = Enum.Material.Slate,
		Parent = model,
	})
	local foundationHeight = math.max(2, topY - thickness - 2.2 - (Config.Grid.Origin.Y - 1))
	makeDisc({
		Name = "Foundation",
		Diameter = diameter - 10,
		Height = foundationHeight,
		Center = Vector3.new(cx, topY - thickness - 2.2 - foundationHeight / 2, cz),
		Color = C.FoundationDeep,
		Material = Enum.Material.Slate,
		Parent = model,
	})
	-- Sol fonctionnel (spawn / retours travel).
	local floor = makePart({
		Name = "MainHubFloor",
		Size = Vector3.new(diameter * 0.72, 1, diameter * 0.72),
		CFrame = CFrame.new(cx, topY - 0.5, cz),
		Color = C.Deck,
		Transparency = 1,
		CanCollide = true,
		CanQuery = true,
		Parent = model,
	})
	mainHubFloor = floor
	setPrimary(model, deck)
	weldToPrimary(model, deck)
	return model
end

local function buildFrontStairs(modules: Folder)
	local model = ensureModel(modules, "FrontStairs")
	local primary: BasePart? = nil
	for _, step in ipairs(HubLayout.GetStairSteps()) do
		local p = makePart({
			Name = "Step" .. tostring(step.Index),
			Size = step.Size,
			CFrame = CFrame.new(step.Center),
			Color = C.Foundation,
			Material = Enum.Material.Slate,
			Parent = model,
		})
		if not primary then
			primary = p
		end
	end
	local landSize, landCenter = HubLayout.GetLanding()
	local landing = makePart({
		Name = "Landing",
		Size = landSize,
		CFrame = CFrame.new(landCenter),
		Color = C.Deck,
		Material = Enum.Material.Slate,
		Parent = model,
	})
	if not primary then
		primary = landing
	end
	setPrimary(model, primary :: BasePart)
	weldToPrimary(model, primary :: BasePart)
end

local function buildSpawnArea(modules: Folder)
	local model = ensureModel(modules, "SpawnArea")
	local center = HubLayout.Spawn.Center
	local pad = makeDisc({
		Name = "SpawnPad",
		Diameter = H.Spawn.PadDiameter,
		Height = H.Spawn.PadHeight,
		Center = Vector3.new(center.X, H.DeckTopY + H.Spawn.PadHeight / 2, center.Z),
		Color = C.Trim,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = model,
	})
	makeDisc({
		Name = "SpawnRing",
		Diameter = H.Spawn.PadDiameter + 2.5,
		Height = 0.22,
		Center = Vector3.new(center.X, H.DeckTopY + 0.12, center.Z),
		Color = C.Loop,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		Parent = model,
	})
	makeDisc({
		Name = "SpawnCore",
		Diameter = 4,
		Height = 0.2,
		Center = Vector3.new(center.X, H.DeckTopY + 0.2, center.Z),
		Color = C.White,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		CanCollide = false,
		Parent = model,
	})
	setPrimary(model, pad)
	weldToPrimary(model, pad)
end

local function buildBoardsBackdrop(modules: Folder)
	local model = ensureModel(modules, "BoardsBackdropPlatform")
	local z = HubLayout.TopBoard.Center.Z + 2
	local y = H.DeckTopY + 0.35
	local deck = makePart({
		Name = "BackdropDeck",
		Size = Vector3.new(H.Boards.OffsetX * 2 + H.Boards.Size.X + 6, 0.7, 8),
		CFrame = CFrame.new(HubLayout.Center.X, y, z),
		Color = C.Foundation,
		Material = Enum.Material.Slate,
		Parent = model,
	})
	makePart({
		Name = "BackdropTrim",
		Size = Vector3.new(H.Boards.OffsetX * 2 + H.Boards.Size.X + 7, 0.25, 8.6),
		CFrame = CFrame.new(HubLayout.Center.X, y + 0.4, z),
		Color = C.Wood,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})
	setPrimary(model, deck)
	weldToPrimary(model, deck)
end

local function buildBoardModel(
	modules: Folder,
	modelName: string,
	displayName: string,
	spec: any,
	accent: Color3,
	setupGui: (BasePart, Color3) -> ()
): BasePart
	local model = ensureModel(modules, modelName)
	local cf = HubLayout.YawCFrame(spec.Center, spec.YawDegrees)
	local board = makePart({
		Name = displayName,
		Size = spec.Size,
		CFrame = cf,
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	board.CastShadow = false
	makePart({
		Name = "Frame",
		Size = Vector3.new(spec.Size.X + 1.2, spec.Size.Y + 1.2, 0.4),
		CFrame = cf * CFrame.new(0, 0, 0.15),
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = model,
	})
	local legH = math.max(0.5, spec.BottomY - H.DeckTopY)
	for _, sign in ipairs({ -1, 1 }) do
		makePart({
			Name = if sign < 0 then "LegL" else "LegR",
			Size = Vector3.new(1.2, legH, 1.2),
			CFrame = CFrame.new(
				spec.Center.X + sign * (spec.Size.X / 2 - 1.2),
				H.DeckTopY + legH / 2,
				spec.Center.Z
			),
			Color = C.WoodDark,
			Material = Enum.Material.Wood,
			Parent = model,
		})
	end
	-- Header plaque
	makePart({
		Name = "HeaderBar",
		Size = Vector3.new(spec.Size.X + 0.4, 1.6, 0.55),
		CFrame = cf * CFrame.new(0, spec.Size.Y / 2 - 0.2, -0.1),
		Color = accent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})
	setupGui(board, accent)
	setPrimary(model, board)
	weldToPrimary(model, board)
	return board
end

local function buildTopCoinsBoard(modules: Folder)
	local board = buildBoardModel(
		modules,
		"TopCoinsBoard",
		"GlobalLeaderboardBoard",
		HubLayout.TopBoard,
		C.Gold,
		function(display: BasePart, accent: Color3)
			display:SetAttribute("BPW_HubLeaderboard", true)
			display:SetAttribute("BPW_TopCoinsBoard", true)
			display:SetAttribute("BPW_Rows", H.Leaderboard.Rows or 5)
			display:SetAttribute("BPW_GuiFace", if HubLayout.FrontSign < 0 then "Front" else "Back")
			tagBoard(display, "BPW_TopCoinsBoard")
			local face = if HubLayout.FrontSign < 0 then Enum.NormalId.Front else Enum.NormalId.Back
			local gui = newSurface(display, face, 40, "GlobalLeaderboardGui")
			local inner = panelBackdrop(gui, accent)
			newLabel(inner, {
				Text = L10n.HubTopTitle,
				Size = UDim2.fromScale(0.9, 0.12),
				Position = UDim2.fromScale(0.5, 0.08),
				Color = C.Gold,
				Stroke = C.PanelDeep,
			})
			newLabel(inner, {
				Text = L10n.LoadingLeaderboard or "Loading...",
				Size = UDim2.fromScale(0.86, 0.2),
				Position = UDim2.fromScale(0.5, 0.5),
				Color = C.White,
				Font = Enum.Font.Gotham,
			}).Name = "Placeholder"
		end
	)
	topBoard = board
end

local function buildWeeklyBestBoard(modules: Folder)
	buildBoardModel(
		modules,
		"WeeklyBestScoreBoard",
		"WeeklyBestDisplay",
		HubLayout.WeeklyBoard,
		C.Violet,
		function(display: BasePart, accent: Color3)
			display:SetAttribute("BPW_WeeklyBestBoard", true)
			display:SetAttribute("BPW_WeeklyBestScoreBoard", true)
			display:SetAttribute("BPW_GuiFace", if HubLayout.FrontSign < 0 then "Front" else "Back")
			tagBoard(display, "BPW_WeeklyBestScoreBoard")
			local face = if HubLayout.FrontSign < 0 then Enum.NormalId.Front else Enum.NormalId.Back
			local gui = newSurface(display, face, 22, "WeeklyBestGui")
			local inner = panelBackdrop(gui, accent)
			newLabel(inner, {
				Text = L10n.HubWeeklyBestTitle,
				Size = UDim2.fromScale(0.9, 0.12),
				Position = UDim2.fromScale(0.5, 0.08),
				Color = C.Gold,
				Stroke = C.PanelDeep,
			})
			for i = 1, 5 do
				local row = newFrame(
					inner,
					UDim2.fromScale(0.9, 0.12),
					UDim2.fromScale(0.5, 0.24 + (i - 1) * 0.14),
					Color3.fromRGB(30, 38, 58),
					8
				)
				row.Name = "Row" .. tostring(i)
				row.Visible = false
				newLabel(row, {
					Text = "#" .. tostring(i),
					Size = UDim2.fromScale(0.14, 0.7),
					Position = UDim2.fromScale(0.1, 0.5),
					Color = accent,
					Dynamic = true,
				}).Name = "Rank"
				newLabel(row, {
					Text = "",
					Size = UDim2.fromScale(0.45, 0.65),
					Position = UDim2.fromScale(0.42, 0.5),
					Color = C.White,
					Font = Enum.Font.Gotham,
					Align = Enum.TextXAlignment.Left,
				}).Name = "Player"
				newLabel(row, {
					Text = "",
					Size = UDim2.fromScale(0.28, 0.65),
					Position = UDim2.fromScale(0.82, 0.5),
					Color = C.Gold,
					Font = Enum.Font.GothamBold,
					Align = Enum.TextXAlignment.Right,
				}).Name = "Score"
			end
			newLabel(inner, {
				Text = L10n.LoadingLeaderboard or "Loading...",
				Size = UDim2.fromScale(0.9, 0.08),
				Position = UDim2.fromScale(0.5, 0.94),
				Color = Color3.fromRGB(160, 175, 200),
				Font = Enum.Font.Gotham,
			}).Name = "StatusLabel"
		end
	)
end

local function buildChallengesBoard(modules: Folder)
	buildBoardModel(
		modules,
		"ChallengesBoard",
		"ChallengesDisplay",
		HubLayout.ChallengesBoard,
		Color3.fromRGB(80, 190, 110),
		function(display: BasePart, accent: Color3)
			display:SetAttribute("BPW_ChallengesBoard", true)
			tagBoard(display, "BPW_ChallengesBoard")
			local face = if HubLayout.FrontSign < 0 then Enum.NormalId.Front else Enum.NormalId.Back
			local gui = newSurface(display, face, 22, "ChallengesBoardGui")
			local inner = panelBackdrop(gui, accent)
			newLabel(inner, {
				Text = L10n.HubChallengesTitle,
				Size = UDim2.fromScale(0.9, 0.11),
				Position = UDim2.fromScale(0.5, 0.08),
				Color = accent,
				Stroke = C.PanelDeep,
			})
			-- Daily section
			newLabel(inner, {
				Text = L10n.HubDailyChallenge,
				Size = UDim2.fromScale(0.88, 0.08),
				Position = UDim2.fromScale(0.5, 0.2),
				Color = C.White,
				Font = Enum.Font.GothamBold,
				Align = Enum.TextXAlignment.Left,
			})
			for i = 1, 2 do
				local row = newFrame(
					inner,
					UDim2.fromScale(0.9, 0.12),
					UDim2.fromScale(0.5, 0.3 + (i - 1) * 0.13),
					Color3.fromRGB(30, 38, 58),
					8
				)
				row.Name = "Daily" .. tostring(i)
				newLabel(row, {
					Text = "",
					Size = UDim2.fromScale(0.12, 0.7),
					Position = UDim2.fromScale(0.1, 0.5),
					Color = accent,
					Dynamic = true,
				}).Name = "Status"
				newLabel(row, {
					Text = if i == 1 then (L10n.LoadingLeaderboard or "Loading...") else "",
					Size = UDim2.fromScale(0.72, 0.6),
					Position = UDim2.fromScale(0.55, 0.5),
					Color = C.White,
					Font = Enum.Font.Gotham,
					Align = Enum.TextXAlignment.Left,
				}).Name = "Title"
			end
			-- Weekly section
			newLabel(inner, {
				Text = L10n.HubWeeklyChallenge,
				Size = UDim2.fromScale(0.88, 0.08),
				Position = UDim2.fromScale(0.5, 0.58),
				Color = C.White,
				Font = Enum.Font.GothamBold,
				Align = Enum.TextXAlignment.Left,
			})
			for i = 1, 3 do
				local row = newFrame(
					inner,
					UDim2.fromScale(0.9, 0.1),
					UDim2.fromScale(0.5, 0.68 + (i - 1) * 0.1),
					Color3.fromRGB(30, 38, 58),
					8
				)
				row.Name = "Weekly" .. tostring(i)
				newLabel(row, {
					Text = "",
					Size = UDim2.fromScale(0.12, 0.7),
					Position = UDim2.fromScale(0.1, 0.5),
					Color = C.Gold,
					Dynamic = true,
				}).Name = "Status"
				newLabel(row, {
					Text = "",
					Size = UDim2.fromScale(0.72, 0.6),
					Position = UDim2.fromScale(0.55, 0.5),
					Color = C.White,
					Font = Enum.Font.Gotham,
					Align = Enum.TextXAlignment.Left,
				}).Name = "Title"
			end
		end
	)
end

local function buildKiosk(
	modules: Folder,
	modelName: string,
	base: CFrame,
	accent: Color3,
	signText: string,
	tagline: string
)
	local model = ensureModel(modules, modelName)
	local width, depth, height = 14, 10, 8

	local floor = makePart({
		Name = "Base",
		Size = Vector3.new(width + 2, 0.6, depth + 2),
		CFrame = localCF(base, Vector3.new(0, 0.3, 0)),
		Color = C.Foundation,
		Material = Enum.Material.Slate,
		Parent = model,
	})
	makePart({
		Name = "BackWall",
		Size = Vector3.new(width, height, 0.8),
		CFrame = localCF(base, Vector3.new(0, height / 2, -depth / 2 + 0.4)),
		Color = C.Panel,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	for _, sign in ipairs({ -1, 1 }) do
		makePart({
			Name = if sign < 0 then "SideL" else "SideR",
			Size = Vector3.new(0.7, height * 0.85, depth * 0.55),
			CFrame = localCF(base, Vector3.new(sign * (width / 2 - 0.35), height * 0.42, -depth * 0.18)),
			Color = C.Panel,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	-- Toit simple (2 wedges)
	makeWedge({
		Name = "RoofL",
		Size = Vector3.new(width / 2 + 0.6, 2.2, depth + 1),
		CFrame = localCF(base, Vector3.new(-width / 4, height + 1.1, -0.5))
			* CFrame.Angles(0, math.rad(90), 0),
		Color = accent,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	makeWedge({
		Name = "RoofR",
		Size = Vector3.new(width / 2 + 0.6, 2.2, depth + 1),
		CFrame = localCF(base, Vector3.new(width / 4, height + 1.1, -0.5))
			* CFrame.Angles(0, math.rad(-90), 0),
		Color = accent,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	-- Auvent
	makePart({
		Name = "Awning",
		Size = Vector3.new(width + 1, 0.45, 3.5),
		CFrame = localCF(base, Vector3.new(0, height * 0.72, depth / 2 - 1.2)),
		Color = accent,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})
	makePart({
		Name = "AwningStripes",
		Size = Vector3.new(width + 1.2, 0.2, 3.7),
		CFrame = localCF(base, Vector3.new(0, height * 0.68, depth / 2 - 1.2)),
		Color = C.White,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
		CanCollide = false,
		Parent = model,
	})
	-- Comptoir
	makePart({
		Name = "Counter",
		Size = Vector3.new(width - 2, 3.2, 2.4),
		CFrame = localCF(base, Vector3.new(0, 1.6, depth / 2 - 2)),
		Color = C.Wood,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	makePart({
		Name = "CounterTop",
		Size = Vector3.new(width - 1.4, 0.35, 2.8),
		CFrame = localCF(base, Vector3.new(0, 3.35, depth / 2 - 2)),
		Color = C.WoodDark,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	-- Enseigne
	local signPart = makePart({
		Name = "Sign",
		Size = Vector3.new(10, 3, 0.55),
		CFrame = localCF(base, Vector3.new(0, height + 3.6, -0.5)),
		Color = C.PanelDeep,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local signGui = newSurface(signPart, Enum.NormalId.Front, 28)
	local signRoot = panelBackdrop(signGui, accent)
	newLabel(signRoot, {
		Text = signText,
		Size = UDim2.fromScale(0.9, 0.65),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = accent,
		Stroke = C.PanelDeep,
	})
	-- Pancarte sol
	local ground = makePart({
		Name = "GroundSign",
		Size = Vector3.new(6, 0.2, 3),
		CFrame = localCF(base, Vector3.new(0, 0.15, depth / 2 + 2.5)),
		Color = C.WoodDark,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = model,
	})
	local gGui = newSurface(ground, Enum.NormalId.Top, 20)
	newLabel(gGui, {
		Text = tagline,
		Size = UDim2.fromScale(0.92, 0.75),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = C.White,
		Stroke = C.PanelDeep,
		Font = Enum.Font.GothamBold,
	})
	-- Lampes latérales attachées
	for _, sign in ipairs({ -1, 1 }) do
		makePart({
			Name = if sign < 0 then "LampPostL" else "LampPostR",
			Size = Vector3.new(0.45, 5, 0.45),
			CFrame = localCF(base, Vector3.new(sign * (width / 2 + 0.8), 2.5, depth / 2 - 1)),
			Color = C.WoodDark,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = model,
		})
		makePart({
			Name = if sign < 0 then "LampL" else "LampR",
			Size = Vector3.new(1.1, 1.1, 1.1),
			CFrame = localCF(base, Vector3.new(sign * (width / 2 + 0.8), 5.2, depth / 2 - 1)),
			Color = C.Gold,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
			Parent = model,
		})
	end

	setPrimary(model, floor)
	weldToPrimary(model, floor)
end

local function buildShopBuilding(modules: Folder)
	buildKiosk(
		modules,
		"ShopBuilding",
		HubLayout.GetShopBaseCFrame(),
		C.Shop,
		L10n.ShopSign,
		L10n.ShopTagline
	)
end

local function buildSellBuilding(modules: Folder)
	buildKiosk(
		modules,
		"SellBuilding",
		HubLayout.GetSellBaseCFrame(),
		C.Sell,
		L10n.SellSign or "SELL",
		L10n.SellTagline
	)
	-- Value board (hook Backpack / sell display)
	local model = modules:FindFirstChild("SellBuilding")
	if model and model:IsA("Model") then
		local base = HubLayout.GetSellBaseCFrame()
		local board = makePart({
			Name = "SellValueBoard",
			Size = H.Sell.ValueBoardSize,
			CFrame = localCF(base, Vector3.new(0, 6.2, 2.5)),
			Color = C.PanelDeep,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = model,
		})
		board:SetAttribute("BPW_SellValueBoard", true)
		sellValueBoard = board
		local gui = newSurface(board, Enum.NormalId.Front, 24, "SellValueGui")
		local inner = panelBackdrop(gui, C.Sell)
		newLabel(inner, {
			Text = L10n.SellYourBubbles or "SELL",
			Size = UDim2.fromScale(0.9, 0.28),
			Position = UDim2.fromScale(0.5, 0.28),
			Color = C.Sell,
			Stroke = C.PanelDeep,
		})
		newLabel(inner, {
			Text = "0",
			Size = UDim2.fromScale(0.85, 0.4),
			Position = UDim2.fromScale(0.5, 0.68),
			Color = C.Gold,
			Stroke = C.PanelDeep,
		}).Name = "ValueLabel"
	end
end

local function buildDecorLamps(modules: Folder)
	local model = ensureModel(modules, "Decor_Lamps")
	local cx, cz = HubLayout.Center.X, HubLayout.Center.Z
	local r = math.min(H.DeckHalfX, H.DeckHalfZ) - 4
	local spots = {
		Vector3.new(cx - r * 0.55, H.DeckTopY, cz + r * 0.35),
		Vector3.new(cx + r * 0.55, H.DeckTopY, cz + r * 0.35),
		Vector3.new(cx - r * 0.7, H.DeckTopY, cz - r * 0.15),
		Vector3.new(cx + r * 0.7, H.DeckTopY, cz - r * 0.15),
		Vector3.new(cx - 8, H.DeckTopY, HubLayout.GetStairsEndZ() + 2),
		Vector3.new(cx + 8, H.DeckTopY, HubLayout.GetStairsEndZ() + 2),
	}
	local primary: BasePart? = nil
	for i, pos in ipairs(spots) do
		local post = makePart({
			Name = "LampPost" .. tostring(i),
			Size = Vector3.new(0.5, 6, 0.5),
			CFrame = CFrame.new(pos.X, pos.Y + 3, pos.Z),
			Color = C.WoodDark,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = model,
		})
		makePart({
			Name = "Lamp" .. tostring(i),
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(pos.X, pos.Y + 6.3, pos.Z),
			Color = C.Gold,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			CanCollide = false,
			Parent = model,
		})
		if not primary then
			primary = post
		end
	end
	if primary then
		setPrimary(model, primary)
		weldToPrimary(model, primary)
	end
end

local function buildDecorPlants(modules: Folder)
	local model = ensureModel(modules, "Decor_Plants")
	local cx, cz = HubLayout.Center.X, HubLayout.Center.Z
	local spots = {
		{ X = cx - 28, Z = cz + 8, H = 9 },
		{ X = cx + 28, Z = cz + 8, H = 10 },
		{ X = cx - 26, Z = cz - 12, H = 8 },
		{ X = cx + 26, Z = cz - 12, H = 8 },
		{ X = cx - 14, Z = cz + 20, H = 6 },
		{ X = cx + 14, Z = cz + 20, H = 6 },
		{ X = cx - 32, Z = cz, H = 5 },
		{ X = cx + 32, Z = cz, H = 5 },
	}
	local primary: BasePart? = nil
	for i, s in ipairs(spots) do
		local trunk = makePart({
			Name = "Trunk" .. tostring(i),
			Size = Vector3.new(0.9, s.H * 0.35, 0.9),
			CFrame = CFrame.new(s.X, H.DeckTopY * 0.35 + s.H * 0.15, s.Z),
			Color = C.WoodDark,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = model,
		})
		makeDisc({
			Name = "Foliage" .. tostring(i),
			Diameter = 4 + (i % 3),
			Height = s.H * 0.65,
			Center = Vector3.new(s.X, H.DeckTopY * 0.2 + s.H * 0.55, s.Z),
			Color = if i % 2 == 0 then C.Plant else C.PlantDark,
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
		if not primary then
			primary = trunk
		end
	end
	-- Petits buissons
	for i = 1, 6 do
		local ang = (i / 6) * math.pi * 2
		local px = cx + math.cos(ang) * 22
		local pz = cz + math.sin(ang) * 16
		makeDisc({
			Name = "Bush" .. tostring(i),
			Diameter = 3.2,
			Height = 2.2,
			Center = Vector3.new(px, H.DeckTopY + 1.1, pz),
			Color = C.Plant,
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
	end
	if primary then
		setPrimary(model, primary)
		weldToPrimary(model, primary)
	end
end

local function buildDecorRailings(modules: Folder)
	local model = ensureModel(modules, "Decor_Railings")
	local primary: BasePart? = nil
	-- Barrières le long de l'avant (hors ouverture escalier)
	local openHalf = HubLayout.GetFrontOpeningHalfWidth()
	local frontZ = HubLayout.Center.Z + math.min(H.DeckHalfX, H.DeckHalfZ) - 3
	for _, sign in ipairs({ -1, 1 }) do
		local midX = HubLayout.Center.X + sign * (openHalf + 6)
		local rail = makePart({
			Name = if sign < 0 then "RailFrontL" else "RailFrontR",
			Size = Vector3.new(10, 0.35, 0.35),
			CFrame = CFrame.new(midX, H.DeckTopY + 2.2, frontZ),
			Color = C.Wood,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = model,
		})
		for post = -1, 1 do
			makePart({
				Name = ("PostFront_%d_%d"):format(sign, post),
				Size = Vector3.new(0.45, 2.6, 0.45),
				CFrame = CFrame.new(midX + post * 4, H.DeckTopY + 1.3, frontZ),
				Color = C.WoodDark,
				Material = Enum.Material.Wood,
				CanCollide = false,
				Parent = model,
			})
		end
		if not primary then
			primary = rail
		end
	end
	-- Côtés légers
	for _, sign in ipairs({ -1, 1 }) do
		local x = HubLayout.Center.X + sign * (math.min(H.DeckHalfX, H.DeckHalfZ) - 2)
		makePart({
			Name = if sign < 0 then "RailSideL" else "RailSideR",
			Size = Vector3.new(0.35, 0.35, 16),
			CFrame = CFrame.new(x, H.DeckTopY + 2.2, HubLayout.Center.Z),
			Color = C.Wood,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = model,
		})
	end
	if primary then
		setPrimary(model, primary)
		weldToPrimary(model, primary)
	end
end

--------------------------------------------------------------------
-- Fonctionnel (spawn, sell, shop)
--------------------------------------------------------------------
local function stripSpawnVisuals(root: Instance)
	for _, child in ipairs(root:GetDescendants()) do
		if child:IsA("Decal")
			or child:IsA("Texture")
			or child:IsA("SurfaceGui")
			or child:IsA("BillboardGui")
			or child:IsA("SelectionBox")
		then
			child:Destroy()
		end
	end
end

local function isManualHubSpawn(sl: SpawnLocation): boolean
	return sl:GetAttribute("BPW_ManualPlacement") == true
		or sl:GetAttribute("BPW_SpawnManualInitialized") == true
end

local function ensureSpawn(functional: Folder)
	local hubRoot = functional.Parent
	-- Source de vérité Studio : CentralHub.HubSpawnLocation (manuel)
	local rootSpawn = hubRoot and hubRoot:FindFirstChild("HubSpawnLocation")
	if rootSpawn and rootSpawn:IsA("SpawnLocation") and isManualHubSpawn(rootSpawn) then
		local sl = rootSpawn :: SpawnLocation
		local preserved = sl.CFrame
		sl.Anchored = true
		sl.CanCollide = false
		sl.CanQuery = false
		sl.CanTouch = false
		sl.CastShadow = false
		sl.Transparency = 1
		sl.Neutral = true
		sl.Duration = 0
		sl.AllowTeamChangeOnTouch = false
		sl.Enabled = true
		sl:SetAttribute("BPW_ManualPlacement", true)
		sl:SetAttribute("BPW_Role", "HubSpawnLocation")
		-- Ne jamais écraser CFrame manuel (ex-ligne: HubLayout.GetSpawnCFrame)
		sl.CFrame = preserved
		stripSpawnVisuals(sl)
		local nest = functional:FindFirstChild("HubSpawnLocation")
		if nest and nest:IsA("SpawnLocation") and nest ~= sl then
			nest.Enabled = false
			nest:SetAttribute("BPW_DisabledAsCompetingHubSpawn", true)
		end
		spawnLocation = sl
		local marker = functional:FindFirstChild("HubSpawnMarker")
		if marker and marker:IsA("BasePart") then
			spawnMarker = marker
		end
		return
	end

	local marker = functional:FindFirstChild("HubSpawnMarker")
	if not (marker and marker:IsA("BasePart")) then
		if marker then
			marker:Destroy()
		end
		marker = makePart({
			Name = "HubSpawnMarker",
			Size = Vector3.new(4, 1, 4),
			CFrame = HubLayout.GetSpawnCFrame(),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = functional,
		})
	else
		if not (rootSpawn and rootSpawn:IsA("SpawnLocation") and isManualHubSpawn(rootSpawn)) then
			(marker :: BasePart).CFrame = HubLayout.GetSpawnCFrame()
		end
	end
	spawnMarker = marker :: BasePart

	local loc = functional:FindFirstChild("HubSpawnLocation")
	if not (loc and loc:IsA("SpawnLocation")) then
		if loc then
			loc:Destroy()
		end
		if rootSpawn and rootSpawn:IsA("SpawnLocation") then
			loc = rootSpawn
		else
			local fresh = Instance.new("SpawnLocation")
			fresh.Name = "HubSpawnLocation"
			fresh.Parent = hubRoot or functional
			loc = fresh
		end
	end
	local sl = loc :: SpawnLocation
	local manual = isManualHubSpawn(sl)
	local preserved = sl.CFrame
	sl.Anchored = true
	sl.CanCollide = false
	sl.CanQuery = false
	sl.CanTouch = false
	sl.CastShadow = false
	sl.Transparency = 1
	sl.Material = Enum.Material.SmoothPlastic
	if not manual then
		sl.Size = Vector3.new(12, 1, 12)
	end
	sl.Neutral = true
	sl.Duration = 0
	sl.AllowTeamChangeOnTouch = false
	sl.Enabled = true
	if manual then
		sl.CFrame = preserved
		sl:SetAttribute("BPW_ManualPlacement", true)
		sl:SetAttribute("BPW_Role", "HubSpawnLocation")
	else
		sl.CFrame = HubLayout.GetSpawnCFrame()
		sl:SetAttribute("GeneratedByCode", true)
	end
	stripSpawnVisuals(sl)
	if sl:GetAttribute("BPW_SpawnVisualHidden") ~= true then
		pcall(function()
			sl.ChildAdded:Connect(function(child)
				if child:IsA("Decal")
					or child:IsA("Texture")
					or child:IsA("SurfaceGui")
					or child:IsA("BillboardGui")
					or child:IsA("SelectionBox")
				then
					task.defer(function()
						if child.Parent then
							child:Destroy()
						end
					end)
				end
			end)
		end)
		sl:SetAttribute("BPW_SpawnVisualHidden", true)
	end
	spawnLocation = sl
end

local function buildSellFunctional(functional: Folder)
	local S = H.Sell
	local base = HubLayout.GetSellBaseCFrame()
	local zone = functional:FindFirstChild("SellZone") or functional:FindFirstChild("HubSellZone")
	if not (zone and zone:IsA("BasePart")) then
		if zone then
			zone:Destroy()
		end
		zone = makePart({
			Name = "SellZone",
			Size = S.ZoneSize,
			CFrame = HubLayout.GetSellZoneCFrame(),
			Transparency = 1,
			CanCollide = false,
			CanQuery = true,
			Parent = functional,
		})
	else
		local z = zone :: BasePart
		z.Name = "SellZone"
		z.Size = S.ZoneSize
		z.CFrame = HubLayout.GetSellZoneCFrame()
		z.Transparency = 1
		z.CanCollide = false
	end
	for _, child in ipairs((zone :: Instance):GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
	sellZone = zone :: BasePart

	-- Pad vente transparent (repère)
	makePart({
		Name = "HubSellPad",
		Size = S.PadSize,
		CFrame = localCF(base, S.PadLocalOffset),
		Color = C.Sell,
		Material = Enum.Material.Neon,
		Transparency = 0.65,
		CanCollide = false,
		CanQuery = false,
		Parent = functional,
	})
end

local function buildHubShopPrompt(functional: Folder)
	-- STUDIO-OWNED : ne jamais Destroy / repositionner HubShopPrompt s'il existe.
	local defaults = HubShopPromptLogic.DefaultPromptConfig(H.Shop.PromptMaxDistance or 13)
	defaults.ActionText = L10n.OpenShop or defaults.ActionText
	defaults.ObjectText = L10n.ShopSign or defaults.ObjectText

	HubShopPromptLogic.Ensure(functional, function(parent: Folder): BasePart
		local base = HubLayout.GetShopBaseCFrame()
		local shopTopY = HubLayout.ShopPlatform.TopY
		local localPos = Vector3.new(0, 3.2, 5.5)
		local flat = base * CFrame.new(localPos.X, 0, localPos.Z)
		local anchor = makePart({
			Name = "HubShopPrompt",
			Size = Vector3.new(4, 5, 2),
			CFrame = CFrame.new(flat.Position.X, shopTopY + localPos.Y, flat.Position.Z)
				* CFrame.Angles(0, math.rad(H.Shop.YawDegrees), 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor:SetAttribute("GeneratedByCode", true)
		return anchor
	end, defaults)
end

--- Exposé pour tests / tooling : même chemin que Build pour le prompt SHOP.
function CentralHubBuilder.EnsureHubShopPrompt(functional: Folder): BasePart?
	buildHubShopPrompt(functional)
	local p = functional:FindFirstChild("HubShopPrompt")
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

--------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------
function CentralHubBuilder.IsEnabled(): boolean
	return H.Enabled == true
end

local function countPartsMesh(inst: Instance): number
	local n = 0
	if not inst:IsA("Model") then
		return 0
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("MeshPart") then
			n += 1
		end
	end
	return n
end

function CentralHubBuilder.Build(worldRoot: Instance): Folder
	local root = ensureFolder(worldRoot, ROOT_NAME)
	local modules = ensureFolder(root, MODULES)
	local functional = ensureFolder(root, FUNCTION)

	for _, name in ipairs({
		"HubStructure",
		"HubAnchors",
		"CompositeCollisionProxies",
		"HubCollisionProxies",
		"HubLightingRig",
		"FullHubCollisionProxies",
	}) do
		local old = root:FindFirstChild(name)
		if old and (old:GetAttribute("BPW_GeneratedBy") == GEN_BY or old:GetAttribute("GeneratedByCode") == true) then
			print("[CentralHub] removed legacy:", name)
			old:Destroy()
		end
	end

	-- JAMAIS ClearAllChildren : destruction structurelle des seuls objets BPW_GeneratedBy.
	destroyGeneratedDescendants(modules)
	RearHubMigration.ClearGeneratedModules(modules)

	local useRear = HubLayout.IsRearPlacement()
	local tripoResult = nil
	local hasTripo = false
	if useRear then
		tripoResult = RearHubMigration.Apply(root, modules)
		hasTripo = tripoResult ~= nil and tripoResult.Ok == true and tripoResult.Model ~= nil
	end

	local function skipFallback(name: string)
		print("[CentralHubBuilder] skipped fallback visual because real Tripo model is active: " .. name)
	end

	-- RearOfGrid : aucun fallback visuel Parts (ne masque plus le FATAL).
	local allowVisualFallback = not useRear

	if not allowVisualFallback then
		skipFallback("HubPlatform")
		skipFallback("FrontStairs")
		skipFallback("SpawnArea")
		skipFallback("BoardsBackdropPlatform")
		skipFallback("Decor_*")
		if not hasTripo then
			print("[CentralHubBuilder] FATAL state: RearOfGrid without real Tripo — no circular hub Parts")
		end
	else
		buildHubPlatform(modules)
		buildFrontStairs(modules)
		buildSpawnArea(modules)
		buildBoardsBackdrop(modules)
		buildDecorLamps(modules)
		buildDecorPlants(modules)
		buildDecorRailings(modules)
		buildShopBuilding(modules)
		buildSellBuilding(modules)
	end

	-- Tripo rear : tableaux = SurfaceGui sur ancrages HubDisplays, pas modèles flottants.
	if hasTripo or useRear then
		-- Supprime d'éventuels anciennes générations de panneaux.
		for _, name in ipairs({ "TopCoinsBoard", "WeeklyBestScoreBoard", "ChallengesBoard" }) do
			local legacy = modules:FindFirstChild(name)
			if legacy and legacy:GetAttribute("BPW_GeneratedBy") == GEN_BY then
				legacy:Destroy()
			end
		end
		pcall(function()
			require(script.Parent.HubDisplaysService).BindExistingAnchors()
		end)
	else
		buildTopCoinsBoard(modules)
		buildWeeklyBestBoard(modules)
		buildChallengesBoard(modules)
	end
	buildSellFunctional(functional)
	buildHubShopPrompt(functional)
	ensureSpawn(functional)

	if hasTripo then
		buildShopBuilding(modules)
		buildSellBuilding(modules)
	elseif not useRear then
		buildShopBuilding(modules)
		buildSellBuilding(modules)
	end

	if not mainHubFloor and useRear then
		mainHubFloor = CentralHubBuilder.GetMainHubFloor()
	end
	if hasTripo then
			RearHubMigration.PlaceSafeHubSpawn(functional)
			local HubSpawnService = require(script.Parent.HubSpawnService)
			-- RespawnLocation natif seulement (aucune reconstruction de collisions)
			HubSpawnService.PrepareForPlay()
		end

	if useRear then
		print("[RearHubMigration] spawn moved")
		print("[RearHubMigration] boards reconnected")
		print("[RearHubMigration] shop reconnected")
		print("[RearHubMigration] sell reconnected")
	end
	if mainHubFloor then
		local existing = functional:FindFirstChild("MainHubFloor")
		if existing and existing:GetAttribute("BPW_GeneratedBy") == GEN_BY then
			existing:Destroy()
		end
		local proxy = makePart({
			Name = "MainHubFloor",
			Size = mainHubFloor.Size,
			CFrame = mainHubFloor.CFrame,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = functional,
		})
		proxy:SetAttribute("BPW_MainHubFloorProxy", true)
	end

	task.defer(function()
		pcall(function()
			require(script.Parent.LeaderboardService).ForceRefresh()
		end)
		pcall(function()
			require(script.Parent.WeeklyBestService).ForceRefresh()
		end)
	end)
	task.delay(3, function()
		pcall(function()
			require(script.Parent.LeaderboardService).ForceRefresh()
		end)
		pcall(function()
			require(script.Parent.WeeklyBestService).ForceRefresh()
		end)
	end)
	task.delay(5, function()
		pcall(function()
			RearHubMigration.RunRuntimeAudit()
		end)
	end)

	return root
end

function CentralHubBuilder.GetMainHubFloor(): BasePart?
	if mainHubFloor and mainHubFloor.Parent then
		return mainHubFloor
	end
	local world = workspace:FindFirstChild("BubblePopWorld")
	local hub = world and world:FindFirstChild(ROOT_NAME)
	local modules2 = hub and hub:FindFirstChild(MODULES)
	local rearHub = modules2 and modules2:FindFirstChild("RearHub")
	-- Collision réelle : ManualCollisionRig (MANUAL_RIG_V1)
	local rig = rearHub and rearHub:FindFirstChild("ManualCollisionRig")
	if rig then
		for _, name in ipairs({ "UpperDeckFloor", "LowerDeckFloor" }) do
			local p = rig:FindFirstChild(name)
			if p and p:IsA("BasePart") and (p :: BasePart).CanCollide then
				return p :: BasePart
			end
		end
	end
	local modules = hub and hub:FindFirstChild(MODULES)
	local platform = modules and modules:FindFirstChild("HubPlatform")
	local floor = platform and platform:FindFirstChild("MainHubFloor")
	if floor and floor:IsA("BasePart") then
		return floor
	end
	local functional = hub and hub:FindFirstChild(FUNCTION)
	local proxy = functional and functional:FindFirstChild("MainHubFloor")
	if proxy and proxy:IsA("BasePart") then
		return proxy
	end
	-- Prefer HubSpawnLocation XZ via spawn
	local sl = functional and functional:FindFirstChild("HubSpawnLocation")
	if sl and sl:IsA("BasePart") then
		return sl
	end
	return nil
end

function CentralHubBuilder.ComputeHubFloorRootY(humanoid: Humanoid, root: BasePart, floor: BasePart): number
	local floorTopY = floor.Position.Y + floor.Size.Y / 2
	return floorTopY + humanoid.HipHeight + root.Size.Y / 2 + 0.05
end

function CentralHubBuilder.PlaceCharacterOnHubFloor(
	character: Model,
	_yawDegrees: number?,
	reason: string?
): boolean
	-- Plus de CFrame HRP depuis SpawnLocation. Retours hub = LoadCharacter + RespawnLocation.
	local HubSpawnService = require(script.Parent.HubSpawnService)
	local player = game:GetService("Players"):GetPlayerFromCharacter(character)
	if not player then
		return false
	end
	if reason == "CharacterAdded" or reason == "OnboardingSnap" or reason == "post-collisions" then
		-- Interdit : spawn natif Roblox uniquement
		return true
	end
	-- Fall / transit intentionnel
	return HubSpawnService.ReloadCharacterAtHubSpawn(player)
end

function CentralHubBuilder.EnsureEarlySpawnLocation(worldRoot: Instance): BasePart
	local root = ensureFolder(worldRoot, ROOT_NAME)
	local HubSpawnService = require(script.Parent.HubSpawnService)
	local manual = root:FindFirstChild("HubSpawnLocation")
	if manual and manual:IsA("SpawnLocation") then
		local cf = manual.CFrame
		HubSpawnService.TagManualSpawn(manual :: SpawnLocation)
		manual.CFrame = cf
		spawnLocation = manual :: SpawnLocation
		HubSpawnService.PrepareForPlay()
		return manual
	end
	local functional = ensureFolder(root, FUNCTION)
	ensureSpawn(functional)
	return spawnLocation :: BasePart
end

function CentralHubBuilder.GetSpawnMarker(): BasePart?
	return spawnMarker
end

function CentralHubBuilder.GetSpawnLocation(): SpawnLocation?
	return spawnLocation
end

function CentralHubBuilder.GetSellZone(): BasePart?
	return sellZone
end

function CentralHubBuilder.GetLeaderboardBoard(): BasePart?
	return topBoard
end

function CentralHubBuilder.GetSellValueBoard(): BasePart?
	return sellValueBoard
end

return CentralHubBuilder
