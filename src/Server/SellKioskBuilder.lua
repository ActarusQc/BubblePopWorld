--!strict
-- Branche le kiosque de vente Studio (Lobby.SellKiosk).
-- Ne construit PAS le visuel : pas de clonage mesh, pas d'assemblage, pas de scale/facing.
-- Responsabilités : détecter le modèle, SellZone, SurfaceGuis, bulles FX, exposer le pad.
-- BIND_VERSION: 2026-07-26-STUDIO-BIND

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").GameConfig)

local SellKioskBuilder = {}
local BIND_VERSION = "2026-07-26-STUDIO-BIND"

local CYAN = Color3.fromRGB(50, 220, 255)
local WHITE = Color3.fromRGB(245, 250, 255)

-- Noms acceptés (premier trouvé gagne), recherche récursive sous SellKiosk.
local NAME_ALIASES = {
	SellPad = { "SellPad", "SellPad_V2" },
	SellZone = { "SellZone" },
	BubbleFXAnchor = { "BubbleFXAnchor", "TankGlass", "BubbleTank" },
	ValueDisplay = { "ValueDisplaySurface", "ValueDisplayAnchor", "SellValueBoard", "FrontDisplayFrame_V2" },
	Terminal = { "TerminalSurface", "TerminalFrame_V2" },
	MainSign = { "MainSignSurface", "MainSign_V2" },
	Technical = { "Technical" },
}

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
local function markGenerated(inst: Instance)
	inst:SetAttribute("GeneratedByCode", true)
end

local function guiFaceFromConfig(name: string?): Enum.NormalId
	local key = string.lower(tostring(name or "Back"))
	if key == "front" then
		return Enum.NormalId.Front
	elseif key == "left" then
		return Enum.NormalId.Left
	elseif key == "right" then
		return Enum.NormalId.Right
	elseif key == "top" then
		return Enum.NormalId.Top
	elseif key == "bottom" then
		return Enum.NormalId.Bottom
	end
	return Enum.NormalId.Back
end

local function findByAliases(root: Instance, aliases: { string }): Instance?
	for _, name in ipairs(aliases) do
		local direct = root:FindFirstChild(name)
		if direct then
			return direct
		end
	end
	for _, name in ipairs(aliases) do
		local deep = root:FindFirstChild(name, true)
		if deep then
			return deep
		end
	end
	return nil
end

local function findBasePart(root: Instance, aliases: { string }): BasePart?
	local inst = findByAliases(root, aliases)
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		if inst.PrimaryPart then
			return inst.PrimaryPart
		end
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				return d
			end
		end
	end
	return nil
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	markGenerated(f)
	f.Parent = parent
	return f
end

local function makeSurfaceGui(host: BasePart, name: string, face: Enum.NormalId, pps: number): SurfaceGui
	local existing = host:FindFirstChild(name)
	if existing and existing:IsA("SurfaceGui") then
		existing.Enabled = true
		existing.Face = face
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.15
	gui.Brightness = 1.2
	markGenerated(gui)
	gui.Parent = host
	return gui
end

local function clearGeneratedGuiChildren(gui: SurfaceGui)
	for _, child in ipairs(gui:GetChildren()) do
		if child:GetAttribute("GeneratedByCode") == true then
			child:Destroy()
		end
	end
end

--------------------------------------------------------------------
-- SurfaceGuis
--------------------------------------------------------------------
local function wireMainSign(mesh: BasePart, face: Enum.NormalId)
	local gui = makeSurfaceGui(mesh, "MainSignGui", face, 40)
	clearGeneratedGuiChildren(gui)
	if gui:FindFirstChild("Line1") then
		return
	end
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	markGenerated(panel)
	panel.Parent = gui
	local line1 = Instance.new("TextLabel")
	line1.Name = "Line1"
	line1.Size = UDim2.new(1, -20, 0.55, 0)
	line1.Position = UDim2.new(0, 10, 0.08, 0)
	line1.BackgroundTransparency = 1
	line1.Text = "SELL YOUR BUBBLES"
	line1.TextColor3 = WHITE
	line1.Font = Enum.Font.GothamBold
	line1.TextScaled = true
	line1.TextStrokeTransparency = 0.45
	markGenerated(line1)
	line1.Parent = panel
	local line2 = Instance.new("TextLabel")
	line2.Name = "Line2"
	line2.Size = UDim2.new(1, -20, 0.3, 0)
	line2.Position = UDim2.new(0, 10, 0.62, 0)
	line2.BackgroundTransparency = 1
	line2.Text = "POP · FILL · CASH IN"
	line2.TextColor3 = CYAN
	line2.Font = Enum.Font.Gotham
	line2.TextScaled = true
	line2.TextStrokeTransparency = 0.45
	markGenerated(line2)
	line2.Parent = panel
end

local function wireValueDisplay(mesh: BasePart, face: Enum.NormalId)
	-- Alias HUD : SellValueBoard + SellValueGui + Label
	mesh.Name = "SellValueBoard"
	local gui = makeSurfaceGui(mesh, "SellValueGui", face, 55)
	clearGeneratedGuiChildren(gui)
	if gui:FindFirstChild("Label", true) then
		return
	end
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(8, 14, 36)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	markGenerated(panel)
	panel.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.Parent = panel
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.new(1, 0, 0.28, 0)
	caption.BackgroundTransparency = 1
	caption.Text = "Bag value:"
	caption.TextColor3 = WHITE
	caption.Font = Enum.Font.GothamBold
	caption.TextScaled = true
	markGenerated(caption)
	caption.Parent = panel
	local row = Instance.new("Frame")
	row.Name = "ValueRow"
	row.Size = UDim2.new(1, 0, 0.62, 0)
	row.Position = UDim2.new(0, 0, 0.34, 0)
	row.BackgroundTransparency = 1
	markGenerated(row)
	row.Parent = panel
	local amount = Instance.new("TextLabel")
	amount.Name = "Label"
	amount.Size = UDim2.new(0.62, 0, 1, 0)
	amount.BackgroundTransparency = 1
	amount.Text = "0"
	amount.TextColor3 = CYAN
	amount.Font = Enum.Font.GothamBold
	amount.TextScaled = true
	amount.TextXAlignment = Enum.TextXAlignment.Right
	markGenerated(amount)
	amount.Parent = row
	local unit = Instance.new("TextLabel")
	unit.Name = "Unit"
	unit.Size = UDim2.new(0.34, 0, 0.55, 0)
	unit.Position = UDim2.new(0.64, 0, 0.28, 0)
	unit.BackgroundTransparency = 1
	unit.Text = "coins"
	unit.TextColor3 = WHITE
	unit.Font = Enum.Font.Gotham
	unit.TextScaled = true
	unit.TextXAlignment = Enum.TextXAlignment.Left
	markGenerated(unit)
	unit.Parent = row
end

local function wireTerminal(mesh: BasePart, face: Enum.NormalId)
	local gui = makeSurfaceGui(mesh, "TerminalGui", face, 42)
	clearGeneratedGuiChildren(gui)
	if gui:FindFirstChild("T1") then
		return
	end
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(6, 12, 28)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	markGenerated(panel)
	panel.Parent = gui
	local t1 = Instance.new("TextLabel")
	t1.Name = "T1"
	t1.Size = UDim2.new(1, -12, 0.28, 0)
	t1.Position = UDim2.new(0, 6, 0.12, 0)
	t1.BackgroundTransparency = 1
	t1.Text = "TERMINAL"
	t1.TextColor3 = CYAN
	t1.Font = Enum.Font.GothamBold
	t1.TextScaled = true
	markGenerated(t1)
	t1.Parent = panel
	local t2 = Instance.new("TextLabel")
	t2.Name = "T2"
	t2.Size = UDim2.new(1, -12, 0.22, 0)
	t2.Position = UDim2.new(0, 6, 0.42, 0)
	t2.BackgroundTransparency = 1
	t2.Text = "Step on the pad"
	t2.TextColor3 = WHITE
	t2.Font = Enum.Font.Gotham
	t2.TextScaled = true
	markGenerated(t2)
	t2.Parent = panel
	local t3 = Instance.new("TextLabel")
	t3.Name = "T3"
	t3.Size = UDim2.new(1, -12, 0.22, 0)
	t3.Position = UDim2.new(0, 6, 0.66, 0)
	t3.BackgroundTransparency = 1
	t3.Text = "then SELL"
	t3.TextColor3 = WHITE
	t3.Font = Enum.Font.Gotham
	t3.TextScaled = true
	markGenerated(t3)
	t3.Parent = panel
end

--------------------------------------------------------------------
-- Bulles animées (autour de BubbleFXAnchor uniquement)
--------------------------------------------------------------------
local function startTankAnims(fxFolder: Folder, anchorCF: CFrame, radius: number, height: number, count: number)
	for _, child in ipairs(fxFolder:GetChildren()) do
		if child:GetAttribute("GeneratedByCode") == true then
			child:Destroy()
		end
	end

	for i = 1, count do
		local bubble = Instance.new("Part")
		bubble.Name = "TankBubble_" .. tostring(i)
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.new(0.55, 0.55, 0.55) * (0.7 + math.random() * 0.7)
		bubble.Material = Enum.Material.Glass
		bubble.Color = CYAN
		bubble.Transparency = 0.18
		bubble.Anchored = true
		bubble.CanCollide = false
		bubble.CanTouch = false
		bubble.CanQuery = false
		bubble.CastShadow = false
		markGenerated(bubble)
		bubble.Parent = fxFolder

		task.spawn(function()
			local phase = (i - 1) / count
			while bubble.Parent do
				local x = math.noise(i * 1.6, phase * 2.5, 0.1) * radius * 0.75
				local z = math.noise(0.4, i * 2.0, phase * 2.5) * radius * 0.75
				local duration = 2.6 + math.random() * 2.4
				local driftX = (math.random() - 0.5) * radius * 0.25
				local driftZ = (math.random() - 0.5) * radius * 0.25
				bubble.CFrame = anchorCF * CFrame.new(x, -height * 0.35, z)
				local tw = TweenService:Create(
					bubble,
					TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{
						CFrame = anchorCF * CFrame.new(x + driftX, height * 0.35, z + driftZ),
						Transparency = 0.48,
					}
				)
				tw:Play()
				tw.Completed:Wait()
				phase += 0.2
				task.wait(0.05)
			end
		end)
	end
end

--------------------------------------------------------------------
-- SellZone
--------------------------------------------------------------------
local function ensureSellZone(kiosk: Model, pad: BasePart?): BasePart
	local existing = findBasePart(kiosk, NAME_ALIASES.SellZone)
	if existing then
		existing.Transparency = 1
		existing.CanCollide = false
		existing.CanTouch = false
		existing.CanQuery = true
		existing.Anchored = true
		return existing
	end

	local technical = findByAliases(kiosk, NAME_ALIASES.Technical)
	local parent: Instance = kiosk
	if technical and (technical:IsA("Folder") or technical:IsA("Model")) then
		parent = technical
	else
		parent = ensureFolder(kiosk, "Technical")
	end

	local zone = Instance.new("Part")
	zone.Name = "SellZone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = true
	zone.Transparency = 1
	zone.Size = Config.Lobby.SellZoneSize
	if pad then
		zone.CFrame = pad.CFrame + Vector3.new(0, zone.Size.Y * 0.35, 0)
	else
		zone.CFrame = kiosk:GetPivot()
	end
	markGenerated(zone)
	zone.Parent = parent
	print("[SellKioskBuilder] SellZone créée (absente du modèle Studio)")
	return zone
end

--------------------------------------------------------------------
-- API publique
--------------------------------------------------------------------
function SellKioskBuilder.FindKiosk(lobby: Instance): Model?
	local direct = lobby:FindFirstChild("SellKiosk")
	if direct and direct:IsA("Model") then
		return direct
	end
	local deep = lobby:FindFirstChild("SellKiosk", true)
	if deep and deep:IsA("Model") then
		return deep
	end
	return nil
end

-- Compat : ZoneService peut encore appeler Build — délègue au bind Studio.
function SellKioskBuilder.Build(lobby: Folder, _root: Vector3): Model?
	return SellKioskBuilder.Bind(lobby)
end

-- Branche le modèle Studio. Ne génère aucun mesh / assemblage visuel.
function SellKioskBuilder.Bind(lobby: Folder): Model?
	print(("[SellKioskBuilder] BIND_VERSION=%s (Studio-only, no mesh assembly)"):format(BIND_VERSION))

	local kiosk = SellKioskBuilder.FindKiosk(lobby)
	if not kiosk then
		warn("[SellKioskBuilder] SellKiosk introuvable — place un Model manuel dans Lobby.SellKiosk (Studio).")
		return nil
	end

	if kiosk:GetAttribute("GeneratedByCode") == true then
		warn("[SellKioskBuilder] SellKiosk marqué GeneratedByCode — attendu : modèle Studio manuel (sans cet attribut).")
	end

	local cfg = Config.Lobby.SellKiosk
	local pad = findBasePart(kiosk, NAME_ALIASES.SellPad)
	if pad then
		print(("[SellKioskBuilder] SellPad: %s"):format(pad:GetFullName()))
	else
		warn("[SellKioskBuilder] SellPad manquant — SellZone utilisera le pivot du kiosque.")
	end

	local sellZone = ensureSellZone(kiosk, pad)

	local valuePart = findBasePart(kiosk, NAME_ALIASES.ValueDisplay)
	if valuePart then
		wireValueDisplay(valuePart, guiFaceFromConfig(cfg.ValueDisplayGuiFace or cfg.FrontDisplayGuiFace))
		print(("[SellKioskBuilder] ValueDisplay: %s"):format(valuePart:GetFullName()))
	else
		warn("[SellKioskBuilder] ValueDisplaySurface / SellValueBoard manquant — HUD kiosque inactif.")
	end

	local signPart = findBasePart(kiosk, NAME_ALIASES.MainSign)
	if signPart then
		wireMainSign(signPart, guiFaceFromConfig(cfg.MainSignGuiFace))
	end

	local termPart = findBasePart(kiosk, NAME_ALIASES.Terminal)
	if termPart then
		wireTerminal(termPart, guiFaceFromConfig(cfg.TerminalGuiFace))
	end

	local technical = findByAliases(kiosk, NAME_ALIASES.Technical)
	local techParent: Instance
	if technical and (technical:IsA("Folder") or technical:IsA("Model")) then
		techParent = technical
	else
		techParent = ensureFolder(kiosk, "Technical")
	end
	local fxFolder = ensureFolder(techParent, "BubbleFX")

	local anchor = findBasePart(kiosk, NAME_ALIASES.BubbleFXAnchor)
	local booth = Config.Lobby.SellBooth
	local bubbleCount = if typeof(booth.TankBubbleCount) == "number" then booth.TankBubbleCount else 10
	if anchor then
		local radius = math.clamp(math.min(anchor.Size.X, anchor.Size.Z) * 0.28, 0.8, 3.5)
		local height = math.clamp(anchor.Size.Y * 0.55, 1.2, 4.5)
		startTankAnims(fxFolder, anchor.CFrame, radius, height, bubbleCount)
		print(("[SellKioskBuilder] BubbleFX autour de %s"):format(anchor:GetFullName()))
	else
		warn("[SellKioskBuilder] BubbleFXAnchor / TankGlass manquant — pas d'anim bulles.")
	end

	kiosk:SetAttribute("BPW_StudioBound", true)
	kiosk:SetAttribute("BPW_HasSellZone", sellZone ~= nil)
	print(("[SellKioskBuilder] Bind OK: %s"):format(kiosk:GetFullName()))
	return kiosk
end

function SellKioskBuilder.GetSellZone(lobby: Folder): BasePart?
	local kiosk = SellKioskBuilder.FindKiosk(lobby)
	if kiosk then
		local zone = findBasePart(kiosk, NAME_ALIASES.SellZone)
		if zone then
			return zone
		end
	end
	local lobbyZone = lobby:FindFirstChild("SellZone")
	if lobbyZone and lobbyZone:IsA("BasePart") then
		return lobbyZone
	end
	return nil
end

-- Anciennes APIs mesh : no-op (ne plus consolider / park / assembler).
function SellKioskBuilder.ConsolidateMeshLibrary(_worldRoot: Instance, _canonicalLobby: Folder): Instance?
	return nil
end

function SellKioskBuilder.ParkImportedAssets(_lobby: Folder)
end

function SellKioskBuilder.GetBaseCF(root: Vector3, _lobby: Folder?): CFrame
	local booth = Config.Lobby.SellBooth
	local yaw = if typeof(booth.YawDegrees) == "number" then booth.YawDegrees else 0
	return CFrame.new(root + booth.OriginOffset) * CFrame.Angles(0, math.rad(yaw), 0)
end

function SellKioskBuilder.GetPadWorldCFrame(root: Vector3, lobby: Folder?): CFrame
	if lobby then
		local kiosk = SellKioskBuilder.FindKiosk(lobby)
		if kiosk then
			local pad = findBasePart(kiosk, NAME_ALIASES.SellPad)
			if pad then
				return pad.CFrame
			end
			local zone = findBasePart(kiosk, NAME_ALIASES.SellZone)
			if zone then
				return zone.CFrame
			end
			return kiosk:GetPivot()
		end
	end
	local booth = Config.Lobby.SellBooth
	return SellKioskBuilder.GetBaseCF(root, lobby) * CFrame.new(booth.PadLocalOffset)
end

return SellKioskBuilder
