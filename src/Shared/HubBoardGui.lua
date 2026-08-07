--!strict
-- SurfaceGui dual Face (Front+Back) pour tableaux hub Studio-owned.
-- Contenu indépendant des DataStores : Loading immédiat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local L10n = require(Shared.LocalizationStrings)
local LeaderboardUtil = require(Shared.LeaderboardUtil)
local HubDisplaysLogic = require(Shared.HubDisplaysLogic)
local HubDisplaysLayout = require(Shared.HubDisplaysLayout)

local HubBoardGui = {}

local TOP_N = HubDisplaysLogic.TOP_N
local STYLE_VERSION = 6
local FACES = { Enum.NormalId.Front, Enum.NormalId.Back }

export type ValueKind = "Coins" | "WeeklyBest" | "Levels"

export type Theme = {
	Accent: Color3,
	Bg: Color3,
	Header: Color3,
	Text: Color3,
	Muted: Color3,
	RowA: Color3,
	RowB: Color3,
	Gold: Color3,
	Silver: Color3,
	Bronze: Color3,
}

local function defaultTheme(spec: HubDisplaysLayout.AnchorSpec?): Theme
	local accent = if spec then spec.ThemeAccent else Color3.fromRGB(90, 170, 255)
	local bg = if spec then spec.ThemeBg else Color3.fromRGB(14, 22, 42)
	local header = if spec then spec.ThemeHeader else Color3.fromRGB(18, 30, 55)
	return {
		Accent = accent,
		Bg = bg,
		Header = header,
		Text = Color3.fromRGB(235, 242, 255),
		Muted = Color3.fromRGB(150, 170, 205),
		RowA = Color3.fromRGB(22, 34, 58),
		RowB = Color3.fromRGB(18, 28, 50),
		Gold = Color3.fromRGB(255, 205, 72),
		Silver = Color3.fromRGB(200, 210, 230),
		Bronze = Color3.fromRGB(210, 140, 70),
	}
end

local function rankColor(theme: Theme, rank: number): Color3
	if rank == 1 then
		return theme.Gold
	elseif rank == 2 then
		return theme.Silver
	elseif rank == 3 then
		return theme.Bronze
	end
	return theme.Accent
end

local function formatValue(kind: ValueKind, value: number): string
	if kind == "Levels" then
		return HubDisplaysLogic.FormatLevel(value)
	end
	return LeaderboardUtil.FormatCompact(value)
end

local function valueIcon(kind: ValueKind): string
	if kind == "Levels" then
		return "▲"
	elseif kind == "WeeklyBest" then
		return "★"
	end
	return "●"
end

local function faceSuffix(face: Enum.NormalId): string
	if face == Enum.NormalId.Back then
		return "_Back"
	end
	return "_Front"
end

local function buildRoot(gui: SurfaceGui, t: Theme, title: string, subtitle: string?): (Frame, TextLabel)
	for _, c in ipairs(gui:GetChildren()) do
		c:Destroy()
	end
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = t.Bg
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = gui
	root:SetAttribute("BPW_HubBoardStyle", STYLE_VERSION)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = t.Accent
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.03, 0)
	pad.PaddingBottom = UDim.new(0.025, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.14)
	header.BackgroundColor3 = t.Header
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Parent = root
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 10)
	hc.Parent = header

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "Title"
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size = UDim2.fromScale(0.96, 0.62)
	titleLbl.Position = UDim2.fromScale(0.02, 0.05)
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextScaled = true
	titleLbl.TextColor3 = t.Accent
	titleLbl.Text = title
	titleLbl.AutoLocalize = false
	titleLbl.Parent = header

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(0.96, 0.28)
	sub.Position = UDim2.fromScale(0.02, 0.68)
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = t.Muted
	sub.Text = subtitle or ""
	sub.AutoLocalize = false
	sub.Parent = header

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.fromScale(1, 0.72)
	rows.Position = UDim2.fromScale(0, 0.16)
	rows.Parent = root

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.Padding = UDim.new(0.008, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rows

	for i = 1, TOP_N do
		local row = Instance.new("Frame")
		row.Name = ("Row%02d"):format(i)
		row.Size = UDim2.new(1, 0, 1 / TOP_N - 0.008, 0)
		row.BackgroundColor3 = if i % 2 == 0 then t.RowB else t.RowA
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Visible = false
		row.Parent = rows
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 6)
		rc.Parent = row

		local rank = Instance.new("TextLabel")
		rank.Name = "Rank"
		rank.BackgroundTransparency = 1
		rank.Size = UDim2.fromScale(0.12, 0.85)
		rank.Position = UDim2.fromScale(0.02, 0.075)
		rank.Font = Enum.Font.GothamBlack
		rank.TextScaled = true
		rank.TextColor3 = rankColor(t, i)
		rank.Text = "#" .. tostring(i)
		rank.AutoLocalize = false
		rank.Parent = row

		local player = Instance.new("TextLabel")
		player.Name = "Player"
		player.BackgroundTransparency = 1
		player.Size = UDim2.fromScale(0.48, 0.85)
		player.Position = UDim2.fromScale(0.15, 0.075)
		player.Font = Enum.Font.GothamMedium
		player.TextScaled = true
		player.TextColor3 = t.Text
		player.TextXAlignment = Enum.TextXAlignment.Left
		player.TextTruncate = Enum.TextTruncate.AtEnd
		player.Text = ""
		player.AutoLocalize = false
		player.Parent = row

		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromScale(0.08, 0.7)
		icon.Position = UDim2.fromScale(0.64, 0.15)
		icon.Font = Enum.Font.GothamBold
		icon.TextScaled = true
		icon.TextColor3 = t.Accent
		icon.Text = ""
		icon.AutoLocalize = false
		icon.Parent = row

		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.BackgroundTransparency = 1
		value.Size = UDim2.fromScale(0.24, 0.85)
		value.Position = UDim2.fromScale(0.74, 0.075)
		value.Font = Enum.Font.GothamBold
		value.TextScaled = true
		value.TextColor3 = t.Gold
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Text = ""
		value.AutoLocalize = false
		value.Parent = row
	end

	local status = Instance.new("TextLabel")
	status.Name = "StatusLabel"
	status.BackgroundTransparency = 1
	status.Size = UDim2.fromScale(1, 0.08)
	status.Position = UDim2.fromScale(0, 0.91)
	status.Font = Enum.Font.Gotham
	status.TextScaled = true
	status.TextColor3 = t.Muted
	status.Text = L10n.LoadingLeaderboard or "Loading..."
	status.AutoLocalize = false
	status.Parent = root

	return root, status
end

local function ensureOneFace(
	anchor: BasePart,
	guiName: string,
	face: Enum.NormalId,
	title: string,
	theme: Theme,
	subtitle: string?
): (SurfaceGui, Frame, TextLabel)
	local name = guiName .. faceSuffix(face)
	local existing = HubDisplaysLogic.SafeFindFirstChild(anchor, name)
	local gui = HubDisplaysLogic.AsSurfaceGui(existing)
	if not gui then
		if typeof(existing) == "Instance" then
			existing:Destroy()
		end
		gui = Instance.new("SurfaceGui")
		gui.Name = name
		gui.Parent = anchor
	end

	gui.Adornee = anchor
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 52
	gui.LightInfluence = 0
	gui.Brightness = 1.35
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ZOffset = 0.2
	gui.Enabled = true
	gui:SetAttribute("BPW_BoardFace", face.Name)

	local rootInst = HubDisplaysLogic.SafeFindFirstChild(gui, "Root")
	local root = HubDisplaysLogic.AsFrame(rootInst)
	local status: TextLabel
	if not root or root:GetAttribute("BPW_HubBoardStyle") ~= STYLE_VERSION then
		root, status = buildRoot(gui, theme, title, subtitle)
	else
		-- Le panneau physique fournit déjà sa couleur. Le Root UI ne doit jamais
		-- ajouter une couche colorée par-dessus le tableau.
		root.BackgroundTransparency = 1
		local st = root:FindFirstChild("StatusLabel")
		if st and st:IsA("TextLabel") then
			status = st
		else
			status = Instance.new("TextLabel")
			status.Name = "StatusLabel"
			status.BackgroundTransparency = 1
			status.Parent = root
		end
		status.BackgroundTransparency = 1
		local header = root:FindFirstChild("Header")
		if header and header:IsA("Frame") then
			header.BackgroundTransparency = 1
			local titleNode = header:FindFirstChild("Title")
			if titleNode and titleNode:IsA("TextLabel") then
				titleNode.Text = title
				titleNode.TextColor3 = theme.Accent
				titleNode.BackgroundTransparency = 1
			end
			if subtitle then
				local subNode = header:FindFirstChild("Subtitle")
				if subNode and subNode:IsA("TextLabel") then
					subNode.Text = subtitle
					subNode.BackgroundTransparency = 1
				end
			end
		end
	end
	return gui, root, status
end

export type DualBoard = {
	Front: SurfaceGui,
	Back: SurfaceGui,
	Roots: { Frame },
	Statuses: { TextLabel },
}

--- 2 SurfaceGui (Front + Back). N'altère jamais la géométrie de l'ancrage.
function HubBoardGui.EnsureDualBoard(
	anchor: BasePart,
	baseGuiName: string,
	title: string,
	theme: Theme?,
	subtitle: string?
): DualBoard
	local t = theme or defaultTheme(nil)
	-- Nettoie anciens GUI mono-face / LocalTopCoinsGui qui bloquent l'affichage.
	for _, child in ipairs(anchor:GetChildren()) do
		if child:IsA("SurfaceGui") then
			local n = child.Name
			local isOurs = string.sub(n, 1, #baseGuiName) == baseGuiName
				and (string.find(n, "_Front", 1, true) or string.find(n, "_Back", 1, true))
			if not isOurs then
				-- Legacy : disable, ne détruit pas (sécurité).
				if n == baseGuiName or n == "LocalTopCoinsGui" or n == "GlobalLeaderboardGui" then
					child.Enabled = false
				end
			end
		end
	end

	local dual: DualBoard = {
		Front = nil :: any,
		Back = nil :: any,
		Roots = {},
		Statuses = {},
	}
	for _, face in ipairs(FACES) do
		local gui, root, status = ensureOneFace(anchor, baseGuiName, face, title, t, subtitle)
		if face == Enum.NormalId.Front then
			dual.Front = gui
		else
			dual.Back = gui
		end
		table.insert(dual.Roots, root)
		table.insert(dual.Statuses, status)
	end
	return dual
end

-- Compat : renvoie la face Front.
function HubBoardGui.EnsureSurfaceGui(
	anchor: BasePart,
	guiName: string,
	title: string,
	theme: Theme?,
	subtitle: string?
): (SurfaceGui, Frame, TextLabel)
	local dual = HubBoardGui.EnsureDualBoard(anchor, guiName, title, theme, subtitle)
	return dual.Front, dual.Roots[1], dual.Statuses[1]
end

function HubBoardGui.PaintRoot(
	root: Frame,
	statusLabel: TextLabel,
	entries: { LeaderboardUtil.BoardEntry }?,
	mode: "loading" | "empty" | "ready" | "unavailable",
	kind: ValueKind,
	emptyText: string?,
	unavailableText: string?,
	theme: Theme?
): number
	local t = theme or defaultTheme(nil)
	local emptyMsg = emptyText or L10n.NoRankingsYet or "No rankings yet"
	local unavailMsg = unavailableText or L10n.LeaderboardUnavailable or "Leaderboard unavailable"
	local rowsRendered = 0

	if mode == "loading" then
		statusLabel.Text = L10n.LoadingLeaderboard or "Loading..."
	elseif mode == "empty" then
		statusLabel.Text = emptyMsg
	elseif mode == "unavailable" then
		statusLabel.Text = unavailMsg
	else
		statusLabel.Text = ""
	end
	statusLabel.TextColor3 = t.Muted
	statusLabel.Visible = true

	local rows = HubDisplaysLogic.AsFrame(HubDisplaysLogic.SafeFindFirstChild(root, "Rows"))
	if not rows then
		return 0
	end

	-- Le seul fond du tableau doit être la surface physique déjà colorée.
	root.BackgroundTransparency = 1
	statusLabel.BackgroundTransparency = 1

	local headerFrame = HubDisplaysLogic.AsFrame(HubDisplaysLogic.SafeFindFirstChild(root, "Header"))
	if headerFrame then
		headerFrame.BackgroundTransparency = 1
	end

	for i = 1, TOP_N do
		local row = HubDisplaysLogic.AsFrame(HubDisplaysLogic.SafeFindFirstChild(rows, ("Row%02d"):format(i)))
		if not row then
			continue
		end
		-- Layout only : jamais de rectangle derrière le texte (refresh inclus).
		row.BackgroundTransparency = 1
		local entry = if entries then entries[i] else nil
		local rank = row:FindFirstChild("Rank")
		local player = row:FindFirstChild("Player")
		local value = row:FindFirstChild("Value")
		local icon = row:FindFirstChild("Icon")

		if rank and rank:IsA("TextLabel") then
			rank.BackgroundTransparency = 1
		end
		if player and player:IsA("TextLabel") then
			player.BackgroundTransparency = 1
		end
		if value and value:IsA("TextLabel") then
			value.BackgroundTransparency = 1
		end
		if icon and icon:IsA("TextLabel") then
			icon.BackgroundTransparency = 1
		end

		if entry then
			row.Visible = true
			rowsRendered += 1
			if rank and rank:IsA("TextLabel") then
				rank.Text = "#" .. tostring(entry.Rank or i)
				rank.TextColor3 = rankColor(t, entry.Rank or i)
			end
			if player and player:IsA("TextLabel") then
				player.Text = HubDisplaysLogic.TruncateName(tostring(entry.Name or "?"), 16)
			end
			if value and value:IsA("TextLabel") then
				value.Text = formatValue(kind, entry.Value)
				value.TextColor3 = if (entry.Rank or i) <= 3 then rankColor(t, entry.Rank or i) else t.Gold
			end
			if icon and icon:IsA("TextLabel") then
				icon.Text = valueIcon(kind)
				icon.TextColor3 = t.Accent
			end
		elseif mode == "empty" and i == 1 then
			row.Visible = true
			if rank and rank:IsA("TextLabel") then
				rank.Text = ""
			end
			if player and player:IsA("TextLabel") then
				player.Text = emptyMsg
				player.TextColor3 = t.Muted
			end
			if value and value:IsA("TextLabel") then
				value.Text = ""
			end
			if icon and icon:IsA("TextLabel") then
				icon.Text = ""
			end
		elseif mode == "loading" and i == 1 then
			-- Ligne placeholder Loading visible
			row.Visible = true
			if rank and rank:IsA("TextLabel") then
				rank.Text = ""
			end
			if player and player:IsA("TextLabel") then
				player.Text = L10n.LoadingLeaderboard or "Loading..."
				player.TextColor3 = t.Muted
			end
			if value and value:IsA("TextLabel") then
				value.Text = ""
			end
			if icon and icon:IsA("TextLabel") then
				icon.Text = ""
			end
		else
			row.Visible = false
		end
	end
	return rowsRendered
end

--- Peint les deux faces d'un ancrage.
function HubBoardGui.PaintAnchor(
	anchor: BasePart,
	baseGuiName: string,
	title: string,
	entries: { LeaderboardUtil.BoardEntry }?,
	mode: "loading" | "empty" | "ready" | "unavailable",
	kind: ValueKind,
	theme: Theme?,
	subtitle: string?,
	emptyText: string?,
	unavailableText: string?
): number
	local t = theme or defaultTheme(nil)
	local dual = HubBoardGui.EnsureDualBoard(anchor, baseGuiName, title, t, subtitle)
	local rendered = 0
	for i, root in ipairs(dual.Roots) do
		local st = dual.Statuses[i]
		rendered = HubBoardGui.PaintRoot(root, st, entries, mode, kind, emptyText, unavailableText, t)
	end
	return rendered
end

-- Compat single-root API
function HubBoardGui.Paint(
	root: Frame,
	statusLabel: TextLabel,
	entries: { LeaderboardUtil.BoardEntry }?,
	mode: "loading" | "empty" | "ready" | "unavailable",
	kind: ValueKind,
	emptyText: string?,
	unavailableText: string?,
	theme: Theme?
)
	HubBoardGui.PaintRoot(root, statusLabel, entries, mode, kind, emptyText, unavailableText, theme)
end

function HubBoardGui.ThemeFromSpec(spec: HubDisplaysLayout.AnchorSpec): Theme
	return defaultTheme(spec)
end

function HubBoardGui.CountBoardSurfaceGuis(anchor: BasePart, baseGuiName: string): number
	local n = 0
	for _, c in ipairs(anchor:GetChildren()) do
		if c:IsA("SurfaceGui") then
			local name = c.Name
			if name == baseGuiName .. "_Front" or name == baseGuiName .. "_Back" then
				n += 1
			end
		end
	end
	return n
end

return HubBoardGui
