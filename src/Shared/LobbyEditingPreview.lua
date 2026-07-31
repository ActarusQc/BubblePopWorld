--!strict
-- Prévisualisation lobby pour édition Studio (placement manuel de SellKiosk).
-- Jamais utilisée en Play : ZoneService appelle RemoveLobbyEditingPreview au démarrage.
-- Usage barre de commande Studio (Edit, Rojo connecté) :
--   require(game.ReplicatedStorage.Shared.LobbyEditingPreview).CreateLobbyEditingPreview()

local LobbyEditingPreview = {}

local PREVIEW_NAME = "LobbyEditingPreview"
local WORLD_NAME = "BubblePopWorld"
local MARKER_TRANSPARENCY = 0.5

local function getConfig()
	return require(script.Parent.GameConfig)
end

local function ghostPart(props: {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
}): Part
	local p = Instance.new("Part")
	p.Name = props.Name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = if props.Transparency ~= nil then props.Transparency else MARKER_TRANSPARENCY
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("LobbyEditingPreview", true)
	return p
end

local function ensureWorldRoot(): Folder
	local existing = workspace:FindFirstChild(WORLD_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		-- Ne pas écraser un Model Studio : créer le Folder sibling si besoin.
		warn("[LobbyEditingPreview] BubblePopWorld existe déjà (" .. existing.ClassName .. ") — preview parenté dessus si possible.")
		if existing:IsA("Model") then
			return existing :: any
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = WORLD_NAME
	folder.Parent = workspace
	return folder
end

function LobbyEditingPreview.RemoveLobbyEditingPreview()
	local world = workspace:FindFirstChild(WORLD_NAME)
	if world then
		local preview = world:FindFirstChild(PREVIEW_NAME)
		if preview then
			preview:Destroy()
		end
	end
	local stray = workspace:FindFirstChild(PREVIEW_NAME)
	if stray then
		stray:Destroy()
	end
end

function LobbyEditingPreview.CreateLobbyEditingPreview()
	local Config = getConfig()
	local L = Config.Lobby
	local root = L.RootOffset
	local booth = L.SellBooth

	LobbyEditingPreview.RemoveLobbyEditingPreview()

	local world = ensureWorldRoot()
	local preview = Instance.new("Folder")
	preview.Name = PREVIEW_NAME
	preview:SetAttribute("LobbyEditingPreview", true)
	preview.Parent = world

	-- Plancher (mêmes Size / CFrame que ZoneService.buildLobby)
	local floor = ghostPart({
		Name = "Floor",
		Size = L.FloorSize,
		CFrame = CFrame.new(root - Vector3.new(0, L.FloorSize.Y / 2, 0)),
		Color = L.FloorColor,
		Transparency = 0.35,
	})
	floor.Parent = preview

	-- Chemin central
	ghostPart({
		Name = "LobbyPath",
		Size = Vector3.new(16, 1.5, 56),
		CFrame = CFrame.new(root + Vector3.new(0, 0.15, 10)),
		Color = Color3.fromRGB(40, 55, 95),
		Transparency = 0.45,
	}).Parent = preview

	-- Limites / rails (même géométrie que ZoneService.buildLobbyRailings)
	local h = L.RailingHeight
	local t = 1.2
	local y = root.Y + h / 2
	local halfX = L.FloorSize.X / 2
	local halfZ = L.FloorSize.Z / 2
	local entranceGap = 18
	local railColor = Color3.fromRGB(40, 140, 200)

	local function rail(name: string, size: Vector3, worldPos: Vector3)
		ghostPart({
			Name = name,
			Size = size,
			CFrame = CFrame.new(worldPos),
			Color = railColor,
			Material = Enum.Material.Glass,
			Transparency = MARKER_TRANSPARENCY,
		}).Parent = preview
	end

	local sideLen = (L.FloorSize.X - entranceGap) / 2
	if sideLen > 2 then
		rail(
			"RailNorthLeft",
			Vector3.new(sideLen, h, t),
			root + Vector3.new(-(entranceGap / 2 + sideLen / 2), y - root.Y, halfZ - t / 2)
		)
		rail(
			"RailNorthRight",
			Vector3.new(sideLen, h, t),
			root + Vector3.new(entranceGap / 2 + sideLen / 2, y - root.Y, halfZ - t / 2)
		)
	end
	rail("RailNorthThreshold", Vector3.new(entranceGap, 1.2, t + 1), root + Vector3.new(0, 0.6, halfZ - t / 2))
	rail("RailSouth", Vector3.new(L.FloorSize.X, h, t), root + Vector3.new(0, y - root.Y, -(halfZ - t / 2)))
	rail("RailEast", Vector3.new(t, h, L.FloorSize.Z), root + Vector3.new(halfX - t / 2, y - root.Y, 0))
	rail("RailWest", Vector3.new(t, h, L.FloorSize.Z), root + Vector3.new(-(halfX - t / 2), y - root.Y, 0))

	-- Repères nommés (visibles)
	local spawnMarker = ghostPart({
		Name = "LobbySpawnMarker",
		Size = Vector3.new(4, 1, 4),
		CFrame = CFrame.new(root + L.SpawnOffset),
		Color = Color3.fromRGB(80, 255, 120),
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	})
	spawnMarker.Parent = preview

	ghostPart({
		Name = "GameEntranceMarker",
		Size = L.EntranceSize,
		CFrame = CFrame.new(L.EntrancePosition),
		Color = Color3.fromRGB(255, 210, 90),
		Material = Enum.Material.Neon,
		Transparency = MARKER_TRANSPARENCY,
	}).Parent = preview

	-- SellZone : même fallback config que ZoneService (pad local × yaw booth)
	local sellCF = CFrame.new(root + booth.OriginOffset)
		* CFrame.Angles(0, math.rad(booth.YawDegrees), 0)
		* CFrame.new(booth.PadLocalOffset)
	ghostPart({
		Name = "SellZoneMarker",
		Size = L.SellZoneSize,
		CFrame = sellCF,
		Color = Color3.fromRGB(255, 120, 80),
		Material = Enum.Material.Neon,
		Transparency = MARKER_TRANSPARENCY,
	}).Parent = preview

	-- Hint origine booth (aide placement kiosque, sans toucher SellKiosk)
	ghostPart({
		Name = "SellBoothOriginMarker",
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(root + booth.OriginOffset),
		Color = Color3.fromRGB(255, 80, 180),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	}).Parent = preview

	-- Horizon montagneux visible aussi en preview Studio (idempotent).
	local ok, err = pcall(function()
		require(script.Parent.EnvironmentBackdropBuilder).Build()
	end)
	if not ok then
		warn("[LobbyEditingPreview] EnvironmentBackdrop: " .. tostring(err))
	end

	print("[LobbyEditingPreview] Créé: Workspace.BubblePopWorld.LobbyEditingPreview")
	print("[LobbyEditingPreview] Place SellKiosk dans Lobby (pas dans LobbyEditingPreview).")
	print("[LobbyEditingPreview] Retirer: require(...LobbyEditingPreview).RemoveLobbyEditingPreview()")
	return preview
end

return LobbyEditingPreview
