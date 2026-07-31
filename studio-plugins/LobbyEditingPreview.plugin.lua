-- Plugin Studio local (optionnel).
-- Installation : copier ce fichier dans
--   %LOCALAPPDATA%\Roblox\Plugins\LobbyEditingPreview.lua
-- Puis redémarrer Studio. Boutons dans l'onglet Plugins.
-- Prérequis : Rojo connecté (modules dans ReplicatedStorage.Shared).

local toolbar = plugin:CreateToolbar("BubblePopWorld")

local lobbyCreateBtn = toolbar:CreateButton(
	"Lobby Preview",
	"Crée LobbyEditingPreview pour placer SellKiosk",
	"rbxassetid://6031094678"
)
local lobbyRemoveBtn = toolbar:CreateButton(
	"Clear Lobby Preview",
	"Supprime LobbyEditingPreview",
	"rbxassetid://6031094678"
)

local summerCreateBtn = toolbar:CreateButton(
	"Create/Refresh Summer Preview",
	"Crée SummerZonePreview (Edit) — ne touche pas SummerZoneDecor",
	"rbxassetid://6031097226"
)
local summerRemoveBtn = toolbar:CreateButton(
	"Remove Summer Preview",
	"Supprime SummerZonePreview — conserve SummerZoneDecor",
	"rbxassetid://6031097226"
)

local lightsCreateBtn = toolbar:CreateButton(
	"Add Summer String Lights",
	"Rebuild contour depuis ZoneDefs actuel — remplace LightPosts/StringLights seulement",
	"rbxassetid://6031068421"
)
local lightsRefreshBtn = toolbar:CreateButton(
	"Refresh Summer String Lights",
	"Rebuild complet du contour lumineux selon les dimensions actuelles (après Summer Preview)",
	"rbxassetid://6031068421"
)
local lightsRemoveBtn = toolbar:CreateButton(
	"Remove Summer String Lights",
	"Supprime uniquement LightPosts/StringLights — conserve le reste de SummerZoneDecor",
	"rbxassetid://6031068421"
)

local decorImportBtn = toolbar:CreateButton(
	"Import Summer Decor Candidates",
	"Import quarantaine → sanitize → SummerDecorPendingApproval (Edit only)",
	"rbxassetid://6031097225"
)
local decorPreviewBtn = toolbar:CreateButton(
	"Preview Pending Summer Asset",
	"Prévisualise un pending dans un ViewportFrame (jamais Workspace)",
	"rbxassetid://6031097225"
)
local decorPromoteBtn = toolbar:CreateButton(
	"Promote Approved Summer Assets",
	"Copie props pending → SummerDecorAssets pour TemplateKeys approuvés (Edit only)",
	"rbxassetid://6031097225"
)
local decorCleanupBtn = toolbar:CreateButton(
	"Cleanup Auto Summer Decor",
	"Purge scènes fusionnées (tropical+beach+setup, tripo_*) + caches rejected",
	"rbxassetid://6031097225"
)
local decorGenBtn = toolbar:CreateButton(
	"Refresh Summer Decor Placement",
	"Place props atomiques approuvés sur 3 côtés du board (Edit)",
	"rbxassetid://6031097225"
)

local shopShellBtn = toolbar:CreateButton(
	"Create ItemShop Editable Shell",
	"Crée StudioDecoration/ItemShopVisual une seule fois — jamais d'écrasement",
	"rbxassetid://6031075931"
)
local shopExteriorBtn = toolbar:CreateButton(
	"Create ItemShop Exterior Draft",
	"Crée ItemShopVisual/Exterior/ExteriorDraft_v1 une seule fois — jamais d'écrasement",
	"rbxassetid://6031075931"
)
local shopInteriorBtn = toolbar:CreateButton(
	"Create ItemShop Interior Draft",
	"Crée ItemShopVisual/Interior/InteriorDraft_v1 une seule fois — jamais d'écrasement",
	"rbxassetid://6031075931"
)
local shopPolishBtn = toolbar:CreateButton(
	"Polish ItemShop Exterior",
	"Applique le polish v1 sur ExteriorDraft_v1 — une seule fois, sans reconstruction",
	"rbxassetid://6031075931"
)
local shopGuidesBtn = toolbar:CreateButton(
	"Align ItemShop (Visual + Guides)",
	"Déplace ItemShopVisual en bloc sur le pivot GameConfig puis régénère prompts / CameraPoints / Displays — aucun descendant du décor n'est modifié",
	"rbxassetid://6031075931"
)
local shopVisualAlignBtn = toolbar:CreateButton(
	"Realign ItemShop Visual Only",
	"Déplace uniquement ItemShopVisual sur le pivot GameConfig (Edit only)",
	"rbxassetid://6031075931"
)

local function getSharedModule(name)
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	if not shared then
		warn("[" .. name .. "] ReplicatedStorage.Shared introuvable — lance rojo serve + Connect.")
		return nil
	end
	local mod = shared:FindFirstChild(name)
	if not mod then
		warn("[" .. name .. "] Module manquant dans Shared.")
		return nil
	end
	return require(mod)
end

local function getServerModule(name)
	local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
	if not server then
		warn("[" .. name .. "] ServerScriptService.Server introuvable — lance rojo serve + Connect.")
		return nil
	end
	local mod = server:FindFirstChild(name)
	if not mod then
		warn("[" .. name .. "] Module manquant dans Server.")
		return nil
	end
	return require(mod)
end

shopShellBtn.Click:Connect(function()
	local M = getSharedModule("ItemShopVisualShell")
	if M then
		M.CreateEditableShell()
	end
end)

shopExteriorBtn.Click:Connect(function()
	local M = getSharedModule("ItemShopVisualShell")
	if M then
		M.CreateExteriorDraft()
	end
end)

shopInteriorBtn.Click:Connect(function()
	local M = getSharedModule("ItemShopVisualShell")
	if M then
		M.CreateInteriorDraft()
	end
end)

shopPolishBtn.Click:Connect(function()
	local M = getSharedModule("ItemShopVisualShell")
	if M then
		M.PolishExteriorDraftV1()
	end
end)

shopGuidesBtn.Click:Connect(function()
	local M = getServerModule("ItemShopBuilder")
	if M then
		M.BuildGuides()
	end
end)

shopVisualAlignBtn.Click:Connect(function()
	local M = getSharedModule("ItemShopVisualShell")
	if M then
		M.RealignVisualModel()
	end
end)

lobbyCreateBtn.Click:Connect(function()
	local M = getSharedModule("LobbyEditingPreview")
	if M then
		M.CreateLobbyEditingPreview()
	end
end)

lobbyRemoveBtn.Click:Connect(function()
	local M = getSharedModule("LobbyEditingPreview")
	if M then
		M.RemoveLobbyEditingPreview()
	end
end)

summerCreateBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneEditingPreview")
	if M then
		M.CreateSummerZonePreview()
	end
end)

summerRemoveBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneEditingPreview")
	if M then
		M.RemoveSummerZonePreview()
	end
end)

lightsCreateBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneStringLights")
	if M then
		M.CreateSummerPerimeterLights()
	end
end)

lightsRefreshBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneStringLights")
	if M then
		-- Rebuild depuis ZoneDefs actuel (alias RebuildSummerPerimeterLights).
		if M.RebuildSummerPerimeterLights then
			M.RebuildSummerPerimeterLights()
		else
			M.RefreshSummerPerimeterLights()
		end
	end
end)

lightsRemoveBtn.Click:Connect(function()
	local M = getSharedModule("SummerZoneStringLights")
	if M then
		M.RemoveSummerPerimeterLights()
	end
end)

--------------------------------------------------------------------
-- Summer Decor secure import / preview / promote (Edit only)
--------------------------------------------------------------------
local RunService = game:GetService("RunService")

local function assertEdit(label)
	if not (RunService:IsStudio() and RunService:IsEdit()) then
		warn("[" .. label .. "] Action uniquement en mode Studio Edit.")
		return false
	end
	return true
end

decorImportBtn.Click:Connect(function()
	if not assertEdit("Import Summer Decor") then
		return
	end
	local M = getSharedModule("SummerDecorAssetImporter")
	if M then
		local results = M.ImportAllCandidates()
		local split, rejected, other = 0, 0, 0
		for id, status in pairs(results) do
			if status == "sanitized_pending" then
				split += 1
				print(("[Import Summer Decor] SPLIT OK asset %s"):format(tostring(id)))
			elseif status == "rejected_composite" then
				rejected += 1
				print(("[Import Summer Decor] REJECTED composite asset %s"):format(tostring(id)))
			else
				other += 1
				print(("[Import Summer Decor] %s → %s"):format(tostring(id), tostring(status)))
			end
		end
		print(("[Import Summer Decor] terminé — split=%d rejected_composite=%d other=%d"):format(split, rejected, other))
		print("[SummerDecorGenerator] Composite templates placed: 0")
	end
end)

-- DockWidget + ViewportFrame : un prop à la fois, jamais Workspace
local previewWidget = nil
local previewWorld = nil
local previewCamera = nil
local previewClone = nil
local previewProps = {}
local previewIndex = 1
local infoLabel = nil
local yaw = 0
local zoom = 12

local function destroyPreviewClone()
	if previewClone then
		previewClone:Destroy()
		previewClone = nil
	end
end

local function countParts(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function ensurePreviewWidget()
	if previewWidget then
		return previewWidget
	end
	local info = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		false,
		false,
		480,
		400,
		360,
		280
	)
	previewWidget = plugin:CreateDockWidgetPluginGui("BPW_SummerDecorPreview", info)
	previewWidget.Title = "Pending Summer Prop Preview"
	previewWidget.Name = "BPW_SummerDecorPreview"

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
	root.BorderSizePixel = 0
	root.Parent = previewWidget

	local top = Instance.new("Frame")
	top.Size = UDim2.new(1, 0, 0, 72)
	top.BackgroundColor3 = Color3.fromRGB(40, 42, 52)
	top.BorderSizePixel = 0
	top.Parent = root

	infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, -16, 0, 40)
	infoLabel.Position = UDim2.new(0, 8, 0, 4)
	infoLabel.BackgroundTransparency = 1
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.TextYAlignment = Enum.TextYAlignment.Top
	infoLabel.TextColor3 = Color3.new(1, 1, 1)
	infoLabel.TextSize = 12
	infoLabel.Font = Enum.Font.Code
	infoLabel.Text = "No pending props"
	infoLabel.Parent = top

	local function makeBtn(text, xScale, order)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.18, -4, 0, 24)
		b.Position = UDim2.new(xScale, 4, 0, 44)
		b.Text = text
		b.Parent = top
		return b
	end

	local prevBtn = makeBtn("Prev", 0, 1)
	local nextBtn = makeBtn("Next", 0.18, 2)
	local rejectBtn = makeBtn("Reject prop", 0.36, 3)
	local refreshBtn = makeBtn("Refresh", 0.54, 4)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.new(1, -8, 1, -80)
	viewport.Position = UDim2.new(0, 4, 0, 76)
	viewport.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	viewport.BorderSizePixel = 0
	viewport.Parent = root

	previewWorld = Instance.new("WorldModel")
	previewWorld.Parent = viewport
	previewCamera = Instance.new("Camera")
	previewCamera.Parent = viewport
	viewport.CurrentCamera = previewCamera

	local function lookAtClone()
		if not previewClone or not previewCamera then
			return
		end
		local ok, cf = pcall(function()
			return previewClone:GetBoundingBox()
		end)
		if not ok then
			return
		end
		local center = cf.Position
		local offset = CFrame.Angles(0, math.rad(yaw), 0) * Vector3.new(0, zoom * 0.25, zoom)
		previewCamera.CFrame = CFrame.new(center + offset, center)
	end

	viewport.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			zoom = math.clamp(zoom - input.Position.Z * 2, 4, 80)
			lookAtClone()
		end
	end)

	local dragging = false
	local lastX = 0
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			lastX = input.Position.X
		end
	end)
	viewport.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	viewport.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			yaw += (input.Position.X - lastX) * 0.4
			lastX = input.Position.X
			lookAtClone()
		end
	end)

	local function showCurrent()
		local Importer = getSharedModule("SummerDecorAssetImporter")
		if not Importer or not previewWorld or not infoLabel then
			return
		end
		destroyPreviewClone()
		if #previewProps == 0 then
			infoLabel.Text = "No pending props"
			return
		end
		previewIndex = math.clamp(previewIndex, 1, #previewProps)
		local model = previewProps[previewIndex]
		if not model or not model.Parent then
			infoLabel.Text = "Prop missing — Refresh"
			return
		end
		previewClone = Importer.CloneForViewportPreview(model, previewWorld)
		yaw = 35
		zoom = 12
		lookAtClone()
		local sourceId = tostring(model:GetAttribute("SourceAssetId") or "?")
		local key = tostring(model:GetAttribute("TemplateKey") or "?")
		local parts = countParts(model)
		infoLabel.Text = string.format(
			"[%d/%d] %s\nSourceAssetId=%s  TemplateKey=%s  Parts=%d",
			previewIndex,
			#previewProps,
			model.Name,
			sourceId,
			key,
			parts
		)
	end

	local function rebuildList()
		local Importer = getSharedModule("SummerDecorAssetImporter")
		previewProps = {}
		if Importer then
			previewProps = Importer.GetPendingProps()
		end
		previewIndex = 1
		showCurrent()
	end

	prevBtn.MouseButton1Click:Connect(function()
		if #previewProps == 0 then
			return
		end
		previewIndex -= 1
		if previewIndex < 1 then
			previewIndex = #previewProps
		end
		showCurrent()
	end)
	nextBtn.MouseButton1Click:Connect(function()
		if #previewProps == 0 then
			return
		end
		previewIndex += 1
		if previewIndex > #previewProps then
			previewIndex = 1
		end
		showCurrent()
	end)
	rejectBtn.MouseButton1Click:Connect(function()
		local Importer = getSharedModule("SummerDecorAssetImporter")
		if not Importer or #previewProps == 0 then
			return
		end
		local model = previewProps[previewIndex]
		local key = model and model:GetAttribute("TemplateKey")
		if type(key) == "string" then
			Importer.RejectPendingProp(key)
			rebuildList()
		end
	end)
	refreshBtn.MouseButton1Click:Connect(rebuildList)

	previewWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not previewWidget.Enabled then
			destroyPreviewClone()
		else
			rebuildList()
		end
	end)

	;(previewWidget :: any)._rebuildList = rebuildList
	return previewWidget
end

decorPreviewBtn.Click:Connect(function()
	if not assertEdit("Preview Pending Summer Asset") then
		return
	end
	local w = ensurePreviewWidget()
	w.Enabled = true
	local rebuild = (w :: any)._rebuildList
	if type(rebuild) == "function" then
		rebuild()
	end
end)

decorPromoteBtn.Click:Connect(function()
	if not assertEdit("Promote Approved Summer Assets") then
		return
	end
	local M = getSharedModule("SummerDecorAssetImporter")
	if not M then
		return
	end
	local result = M.PromotePendingApproved()
	print(("[Promote Summer Decor] promoted=%d missing=%d"):format(#result.promoted, #result.missing))
	print("[Promote Summer Decor] Approuver via SummerDecorConfig.ApprovedTemplateKeys puis Promote.")
	print("[Promote Summer Decor] Persister assets/summer-decor/*.rbxm après promote.")
end)

decorCleanupBtn.Click:Connect(function()
	if not assertEdit("Cleanup Auto Summer Decor") then
		return
	end
	local M = getSharedModule("SummerDecorAssetImporter")
	if M and M.PurgeCompositeRejected then
		local n = M.PurgeCompositeRejected()
		print(("[Cleanup Summer Decor] purged=%d"):format(n))
	end
end)

decorGenBtn.Click:Connect(function()
	if not assertEdit("Refresh Summer Decor Placement") then
		return
	end
	local Importer = getSharedModule("SummerDecorAssetImporter")
	if Importer and Importer.PurgeCompositeRejected then
		Importer.PurgeCompositeRejected()
	end
	local Gen = getSharedModule("SummerDecorGenerator")
	if Gen then
		Gen.Refresh()
	end
end)
