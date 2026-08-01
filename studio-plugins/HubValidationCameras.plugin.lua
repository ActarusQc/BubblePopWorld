-- Plugin Studio local — caméras de validation du hub central.
--
-- Installation : copier ce fichier dans
--   %LOCALAPPDATA%\Roblox\Plugins\HubValidationCameras.lua
-- Puis redémarrer Studio. Boutons dans l'onglet Plugins, barre « BPW Hub Cameras ».
--
-- Rôle : poser des repères inertes servant de cadrages de comparaison entre la maquette
-- « Concept 2 — Équilibré » et le hub réel, puis déplacer la caméra dessus.
--
-- Modes autorisés :
--   * Create/Refresh et Remove : Studio Edit uniquement (ils écrivent dans la hiérarchie) ;
--   * Go To Selected View, List Views et Restore Test Camera : Studio Edit et Test (F5),
--     car le hub central n'est généré que pendant un test et les captures se font donc
--     en cours de test.
--
-- Pendant un test, le premier cadrage mémorise l'état de la caméra du joueur ;
-- « Restore Test Camera » le rétablit puis efface la mémoire.
--
-- Ce plugin ne touche jamais Players ni StarterPlayer, ne crée aucun LocalScript et ne
-- modifie aucun script de production. Les repères vivent sous Workspace.StudioDecoration,
-- zone déclarée intouchable par le code du jeu.

local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local DECOR_ROOT = "StudioDecoration"
local VISUAL_FOLDER = "CentralHubVisual"
local CAMERAS_FOLDER = "ValidationCameras"
local MARKER_ATTRIBUTE = "BPW_ValidationCamera"
local MARKER_SIZE = Vector3.new(1, 1, 1)

--------------------------------------------------------------------
-- Définition des cadrages
--
-- Position / cible en studs, repère monde du jeu.
-- Origine des valeurs :
--   * référence et latérale : imposées par la spécification approuvée ;
--   * les autres : calculées depuis les ancres réelles relevées en Phase 0
--     (docs/superpowers/specs/renders/anchors.txt), formule dans Derivation.
--------------------------------------------------------------------
local CAMERAS = {
	{
		Name = "CentralHubConcept2ReferenceCamera",
		Position = Vector3.new(0, 74, 124),
		Target = Vector3.new(0, 15, 4),
		FieldOfView = 36,
		Aspect = "16:9",
		Capture = "1920x1080",
		File = "2026-08-01-prototype-reference.png",
		Derivation = "imposé par la spécification (cadrage de la maquette Concept 2)",
	},
	{
		Name = "ValidationCam_Spawn",
		Position = Vector3.new(0, 17.5, 9),
		Target = Vector3.new(0, 21, -23),
		FieldOfView = 70,
		Aspect = "16:9",
		Capture = "1920x1080",
		File = "2026-08-01-prototype-spawn.png",
		Derivation = "spawn (0,12,8) + hauteur d'yeux 5.5 et +1 en Z pour dégager le "
			.. "médaillon ; cible = mur des panneaux arrière Z=-23 à mi-hauteur (27-6)",
	},
	{
		Name = "ValidationCam_FromBubbles",
		Position = Vector3.new(0, 13.85, 77.3),
		Target = Vector3.new(0, 16, 0),
		FieldOfView = 55,
		Aspect = "16:9",
		Capture = "1920x1080",
		File = "2026-08-01-prototype-from-bubbles.png",
		Derivation = "surface de marche des bulles 7.35 + 6.5 d'yeux ; "
			.. "Z = bord avant du palier 51.3 + 26 de recul",
	},
	{
		Name = "ValidationCam_Back",
		Position = Vector3.new(0, 45, -92),
		Target = Vector3.new(0, 20, -10),
		FieldOfView = 40,
		Aspect = "16:9",
		Capture = "1920x1080",
		File = "2026-08-01-prototype-back.png",
		Derivation = "centre des panneaux arrière Y=27 + 18 ; Z = -23 - 69 de recul",
	},
	{
		Name = "ValidationCam_Top",
		Position = Vector3.new(0, 150, 20),
		Target = Vector3.new(0, 12, 0),
		FieldOfView = 40,
		Aspect = "16:9",
		Capture = "1920x1080",
		File = "2026-08-01-prototype-top.png",
		Derivation = "deck 12 + 138 de hauteur ; +20 en Z pour incliner de ~8° et "
			.. "éviter la dégénérescence du vecteur up d'un regard vertical",
	},
	{
		Name = "ValidationCam_Side",
		Position = Vector3.new(120, 30, 0),
		Target = Vector3.new(0, 16, 0),
		FieldOfView = 40,
		Aspect = "16:9",
		Capture = "1920x1080",
		File = "2026-08-01-prototype-side.png",
		Derivation = "imposé par la spécification (recul latéral 120 pour 84 de large)",
	},
	{
		Name = "ValidationCam_Mobile",
		Position = Vector3.new(0, 20, 44),
		Target = Vector3.new(0, 15, -6),
		FieldOfView = 68,
		Aspect = "20:9",
		Capture = "2160x972",
		File = "2026-08-01-prototype-mobile.png",
		Derivation = "cadrage téléphone en approche : deck 12 + 8 de hauteur, "
			.. "Z=44 au milieu de l'escalier (37.75 → 51.3), FOV large",
	},
}

--------------------------------------------------------------------
-- Barre d'outils
--------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("BPW Hub Cameras")

local buildBtn = toolbar:CreateButton(
	"Create/Refresh Hub Validation Cameras",
	"Crée ou met à jour StudioDecoration/CentralHubVisual/ValidationCameras (Edit only)",
	"rbxassetid://6031075931"
)
local gotoBtn = toolbar:CreateButton(
	"Go To Selected Validation View",
	"Place la caméra Studio sur le repère sélectionné (référence par défaut)",
	"rbxassetid://6031075931"
)
local listBtn = toolbar:CreateButton(
	"List Validation Views",
	"Affiche positions, cibles, FOV, résolutions et fichiers de capture attendus",
	"rbxassetid://6031075931"
)
local restoreBtn = toolbar:CreateButton(
	"Restore Test Camera",
	"Rend la caméra au joueur avec l'état mémorisé avant la première vue de validation",
	"rbxassetid://6031075931"
)
local removeBtn = toolbar:CreateButton(
	"Remove Validation Cameras",
	"Supprime ValidationCameras — à faire avant toute publication",
	"rbxassetid://6031075931"
)

-- Écriture dans la hiérarchie : Edit uniquement.
local function assertEdit(label: string): boolean
	if not (RunService:IsStudio() and RunService:IsEdit()) then
		warn("[HubValidationCameras] " .. label .. " : action réservée au mode Studio Edit "
			.. "(elle modifie la hiérarchie). Arrête le test puis relance-la.")
		return false
	end
	return true
end

-- Lecture seule / cadrage caméra : Edit et Test (F5).
local function assertStudio(label: string): boolean
	if not RunService:IsStudio() then
		warn("[HubValidationCameras] " .. label .. " : action réservée à Roblox Studio.")
		return false
	end
	return true
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		error(("[HubValidationCameras] %s.%s existe déjà en %s : renomme-le avant de continuer.")
			:format(parent:GetFullName(), name, existing.ClassName))
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function applyMarker(marker: Part, spec)
	marker.Name = spec.Name
	marker.Size = MARKER_SIZE
	marker.CFrame = CFrame.lookAt(spec.Position, spec.Target)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Massless = true
	marker.CastShadow = false
	marker.Transparency = 1
	marker.Locked = true
	marker.Shape = Enum.PartType.Block
	marker.Material = Enum.Material.SmoothPlastic
	marker.Color = Color3.fromRGB(255, 120, 0)

	marker:SetAttribute(MARKER_ATTRIBUTE, true)
	marker:SetAttribute("BPW_StudioOnly", true)
	marker:SetAttribute("BPW_FieldOfView", spec.FieldOfView)
	marker:SetAttribute("BPW_AspectRatio", spec.Aspect)
	marker:SetAttribute("BPW_CaptureResolution", spec.Capture)
	marker:SetAttribute("BPW_CaptureFile", spec.File)
	marker:SetAttribute("BPW_TargetPosition", spec.Target)
	marker:SetAttribute("BPW_Derivation", spec.Derivation)

	-- Un repère reste inerte : aucun script ne doit y vivre.
	for _, child in ipairs(marker:GetChildren()) do
		if child:IsA("LuaSourceContainer") then
			child:Destroy()
		end
	end
end

local function buildCameras()
	if not assertEdit("Create/Refresh") then
		return
	end

	local recording = ChangeHistoryService:TryBeginRecording("BPW Hub Validation Cameras")

	local decor = ensureFolder(workspace, DECOR_ROOT)
	local visual = ensureFolder(decor, VISUAL_FOLDER)
	local folder = ensureFolder(visual, CAMERAS_FOLDER)
	folder:SetAttribute("BPW_StudioOnly", true)
	folder:SetAttribute("BPW_ValidationCameras", true)

	local created, updated = 0, 0
	for _, spec in ipairs(CAMERAS) do
		local marker = folder:FindFirstChild(spec.Name)
		if marker and not marker:IsA("Part") then
			marker:Destroy()
			marker = nil
		end
		if marker then
			updated += 1
		else
			marker = Instance.new("Part")
			marker.Parent = folder
			created += 1
		end
		applyMarker(marker :: Part, spec)
	end

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	print(("[HubValidationCameras] Workspace.%s.%s.%s prêt — %d créé(s), %d mis à jour, %d au total.")
		:format(DECOR_ROOT, VISUAL_FOLDER, CAMERAS_FOLDER, created, updated, #CAMERAS))
	print("[HubValidationCameras] Repères inertes (invisibles, sans collision, sans script). "
		.. "Supprime-les avant publication via « Remove Validation Cameras ».")
end

local function findFolder(): Folder?
	local decor = workspace:FindFirstChild(DECOR_ROOT)
	local visual = decor and decor:FindFirstChild(VISUAL_FOLDER)
	local folder = visual and visual:FindFirstChild(CAMERAS_FOLDER)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function resolveTarget(): Part?
	local folder = findFolder()
	if not folder then
		warn("[HubValidationCameras] ValidationCameras absent — lance Create/Refresh en mode "
			.. "Edit, puis relance le test.")
		return nil
	end

	for _, selected in ipairs(Selection:Get()) do
		if selected:IsA("Part") and selected:GetAttribute(MARKER_ATTRIBUTE) == true then
			return selected
		end
	end

	local fallback = folder:FindFirstChild("CentralHubConcept2ReferenceCamera")
	if fallback and fallback:IsA("Part") then
		print("[HubValidationCameras] Aucun repère sélectionné — caméra de référence utilisée.")
		return fallback
	end

	warn("[HubValidationCameras] Aucun repère utilisable trouvé.")
	return nil
end

--------------------------------------------------------------------
-- État de la caméra du joueur pendant un test
--
-- Mémorisé au premier « Go To Selected View » d'une session de test, jamais écrasé
-- ensuite : les 7 captures s'enchaînent sans perdre l'état initial. Restauré et effacé
-- par « Restore Test Camera ».
--------------------------------------------------------------------
type SavedCamera = {
	Camera: Camera,
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	CFrame: CFrame,
	Focus: CFrame,
	FieldOfView: number,
}

local savedTestCamera: SavedCamera? = nil

local function saveTestCameraOnce(camera: Camera)
	local existing = savedTestCamera
	-- Nouvelle session de test : la caméra précédente n'existe plus, l'état est périmé.
	if existing and existing.Camera == camera and camera.Parent ~= nil then
		return
	end

	savedTestCamera = {
		Camera = camera,
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		Focus = camera.Focus,
		FieldOfView = camera.FieldOfView,
	}

	print(("[HubValidationCameras] État caméra du test mémorisé — CameraType=%s, FOV=%.1f, sujet=%s.")
		:format(
			camera.CameraType.Name,
			camera.FieldOfView,
			if camera.CameraSubject then camera.CameraSubject.Name else "aucun"
		))
end

local function gotoView()
	-- Le hub central n'existe que pendant un test : le cadrage doit donc fonctionner
	-- aussi bien en Edit qu'en Test (F5).
	if not assertStudio("Go To View") then
		return
	end

	local marker = resolveTarget()
	if not marker then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		warn("[HubValidationCameras] workspace.CurrentCamera introuvable.")
		return
	end

	local running = RunService:IsRunning()
	if running then
		-- Mémorisation une seule fois par session de test : passer d'une vue de validation
		-- à une autre ne doit jamais écraser l'état initial du joueur.
		saveTestCameraOnce(camera)
		-- Sans Scriptable, les scripts de caméra reprennent la main à la frame suivante
		-- et le cadrage est perdu avant la capture.
		camera.CameraType = Enum.CameraType.Scriptable
	end

	camera.CFrame = marker.CFrame
	camera.Focus = CFrame.new(marker:GetAttribute("BPW_TargetPosition") or marker.Position)
	local fov = marker:GetAttribute("BPW_FieldOfView")
	if type(fov) == "number" then
		camera.FieldOfView = fov
	end

	print(("[HubValidationCameras] Vue « %s » — FOV %s, %s (%s) → capture attendue : %s")
		:format(
			marker.Name,
			tostring(marker:GetAttribute("BPW_FieldOfView")),
			tostring(marker:GetAttribute("BPW_CaptureResolution")),
			tostring(marker:GetAttribute("BPW_AspectRatio")),
			tostring(marker:GetAttribute("BPW_CaptureFile"))
		))

	if running then
		print("[HubValidationCameras] Test en cours : caméra passée en Scriptable pour tenir "
			.. "le cadrage. Enchaîne les 7 captures, puis clique « Restore Test Camera ».")
	end
end

local function restoreTestCamera()
	if not assertStudio("Restore Test Camera") then
		return
	end

	if not savedTestCamera then
		print("[HubValidationCameras] No saved test camera state to restore.")
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		warn("[HubValidationCameras] workspace.CurrentCamera introuvable — état conservé.")
		return
	end

	local state = savedTestCamera

	camera.CameraType = state.CameraType

	-- Le sujet peut avoir été détruit ou reparenté depuis (mort du personnage, respawn).
	local subject = state.CameraSubject
	local subjectRestored = false
	if subject and subject.Parent ~= nil then
		camera.CameraSubject = subject
		subjectRestored = true
	end

	camera.CFrame = state.CFrame
	camera.Focus = state.Focus
	camera.FieldOfView = state.FieldOfView

	savedTestCamera = nil

	print(("[HubValidationCameras] Caméra de test restaurée — CameraType=%s, FOV=%.1f, sujet %s.")
		:format(
			state.CameraType.Name,
			state.FieldOfView,
			if subjectRestored
				then ("rétabli (%s)"):format(subject.Name)
				else "non rétabli (instance absente ou détachée)"
		))
end

local function listViews()
	if not assertStudio("List Views") then
		return
	end
	print("[HubValidationCameras] Cadrages de validation du hub central :")
	for _, spec in ipairs(CAMERAS) do
		print(("  %-34s pos %s  cible %s  FOV %d  %s (%s)  →  %s"):format(
			spec.Name,
			tostring(spec.Position),
			tostring(spec.Target),
			spec.FieldOfView,
			spec.Capture,
			spec.Aspect,
			spec.File
		))
		print(("      dérivation : %s"):format(spec.Derivation))
	end
	print("  Dossier de destination : docs/superpowers/specs/renders/")
end

local function removeCameras()
	if not assertEdit("Remove") then
		return
	end
	local folder = findFolder()
	if not folder then
		print("[HubValidationCameras] Rien à supprimer.")
		return
	end
	local recording = ChangeHistoryService:TryBeginRecording("BPW Remove Hub Validation Cameras")
	folder:Destroy()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	print("[HubValidationCameras] ValidationCameras supprimé — CentralHubVisual conservé.")
end

buildBtn.Click:Connect(buildCameras)
gotoBtn.Click:Connect(gotoView)
listBtn.Click:Connect(listViews)
restoreBtn.Click:Connect(restoreTestCamera)
removeBtn.Click:Connect(removeCameras)
