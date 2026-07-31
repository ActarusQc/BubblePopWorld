--!strict
-- Tests hors Roblox des modèles de preview de la boutique.
-- Lancer : python tools\run_shop_viewport_tests.py

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ShopCatalog = require(Shared.ShopCatalog)
local Models = require(Shared.ShopViewportModels)

local ShopViewportModelsTests = {}

local FIELD_OF_VIEW = 40
local CATEGORIES = { "Skills", "Items", "Cosmetics" }

local MIN_PARTS = 4
local MAX_PARTS = 10
local MAX_PART_DIMENSION = 3.2
local MIN_RADIUS = 1.0
local MAX_RADIUS = 3.2
local MAX_TRANSPARENCY = 0.45
local MIN_PART_LUMINANCE = 0.2

local ALLOWED_MATERIALS = {
	SmoothPlastic = true,
	Metal = true,
	Neon = true,
	Glass = true,
}

local ALLOWED_SHAPES = {
	Block = true,
	Cylinder = true,
	Ball = true,
}

local function luminance(color: Color3): number
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
end

local function allCatalogItems()
	local out = {}
	for _, category in ipairs(CATEGORIES) do
		for _, item in ipairs(ShopCatalog.GetCategoryItems(category)) do
			table.insert(out, item)
		end
	end
	return out
end

function ShopViewportModelsTests.Run(): boolean
	local failures = 0
	local checks = 0

	local function check(condition: boolean, label: string)
		checks += 1
		if not condition then
			failures += 1
			print("[ShopViewportModels] FAIL: " .. label)
		end
	end

	----------------------------------------------------------------
	-- 1) Couverture du catalogue
	----------------------------------------------------------------

	local items = allCatalogItems()
	check(#items > 0, "catalogue non vide")

	for _, item in ipairs(items) do
		check(Models.HasDedicatedSpec(item.Id), "modèle dédié : " .. item.Id)
	end

	----------------------------------------------------------------
	-- 2) Structure et budget de chaque spec dédiée
	----------------------------------------------------------------

	local ids = Models.GetIds()
	check(#ids >= #items, "au moins autant de specs que d'items")

	local totalParts = 0
	for _, id in ipairs(ids) do
		local spec = Models.GetSpec(id)
		check(spec.Id == id, "spec résolue sans repli : " .. id)

		local count = #spec.Parts
		totalParts += count
		check(count >= MIN_PARTS and count <= MAX_PARTS, ("budget parts (%d) : %s"):format(count, id))

		local seen = {}
		for _, entry in ipairs(spec.Parts) do
			check(entry.Name ~= "" and seen[entry.Name] == nil, "nom de part unique : " .. id .. "." .. entry.Name)
			seen[entry.Name] = true

			check(ALLOWED_MATERIALS[entry.Material] == true, "matériau autorisé : " .. id .. "." .. entry.Name)
			check(
				entry.Shape == nil or ALLOWED_SHAPES[entry.Shape] == true,
				"forme autorisée : " .. id .. "." .. entry.Name
			)

			local size = entry.Size
			check(
				size.X > 0.05 and size.Y > 0.05 and size.Z > 0.05,
				"taille positive : " .. id .. "." .. entry.Name
			)
			check(
				size.X <= MAX_PART_DIMENSION and size.Y <= MAX_PART_DIMENSION and size.Z <= MAX_PART_DIMENSION,
				"part compacte : " .. id .. "." .. entry.Name
			)

			local transparency = entry.Transparency or 0
			check(transparency <= MAX_TRANSPARENCY, "part visible : " .. id .. "." .. entry.Name)
		end
	end

	check(totalParts <= 160, ("budget global des previews (%d parts)"):format(totalParts))

	----------------------------------------------------------------
	-- 3) Lisibilité : contraste avec le fond du ViewportFrame
	----------------------------------------------------------------

	-- Le fond réellement derrière le modèle est le fond uni du ViewportFrame,
	-- pas le dégradé du Frame décoratif placé derrière.
	local brightestBackground = 0
	for _, category in ipairs(CATEGORIES) do
		brightestBackground = math.max(brightestBackground, luminance(Models.GetViewportBackground(category)))
	end

	for _, id in ipairs(ids) do
		local spec = Models.GetSpec(id)
		local brightest = 0
		local darkest = 1
		for _, entry in ipairs(spec.Parts) do
			local luma = luminance(entry.Color)
			brightest = math.max(brightest, luma)
			darkest = math.min(darkest, luma)
		end
		check(brightest - brightestBackground >= 0.3, "contraste avec le fond : " .. id)
		check(darkest >= MIN_PART_LUMINANCE, ("part trop sombre (%.3f) : %s"):format(darkest, id))
	end

	----------------------------------------------------------------
	-- 3b) Fond, éclairage et arrière-plan par catégorie
	----------------------------------------------------------------

	local seenBackgrounds = {}
	local seenViewportBackgrounds = {}
	local referenceDirection: Vector3? = nil
	for _, category in ipairs(CATEGORIES) do
		local background = Models.GetBackground(category)
		local top = luminance(background.Top)
		local bottom = luminance(background.Bottom)

		check(bottom >= 0.045, "fond jamais noir pur : " .. category)
		check(top <= 0.3, "fond reste sombre et premium : " .. category)
		check(top > bottom, "dégradé de haut en bas : " .. category)

		-- Fond uni du ViewportFrame : jamais quasi noir, jamais délavé.
		local viewportBackground = Models.GetViewportBackground(category)
		local viewportLuma = luminance(viewportBackground)
		check(viewportLuma >= 0.2, ("fond ViewportFrame jamais sombre (%.3f) : %s"):format(viewportLuma, category))
		check(viewportLuma <= 0.42, ("fond ViewportFrame pas délavé (%.3f) : %s"):format(viewportLuma, category))
		check(viewportLuma > top, "fond ViewportFrame plus clair que le dégradé : " .. category)

		local viewportKey = ("%d-%d-%d"):format(
			viewportBackground.R * 255,
			viewportBackground.G * 255,
			viewportBackground.B * 255
		)
		check(seenViewportBackgrounds[viewportKey] == nil, "fond ViewportFrame distinct : " .. category)
		seenViewportBackgrounds[viewportKey] = true

		-- Teinte de catégorie discrète : présente, mais jamais dominante.
		local channels = { background.Top.R, background.Top.G, background.Top.B }
		table.sort(channels)
		check(channels[3] - channels[1] <= 0.2, "teinte discrète : " .. category)
		check(channels[3] - channels[1] >= 0.03, "teinte perceptible : " .. category)

		local key = ("%d-%d-%d"):format(background.Top.R * 255, background.Top.G * 255, background.Top.B * 255)
		check(seenBackgrounds[key] == nil, "fond distinct par catégorie : " .. category)
		seenBackgrounds[key] = true

		local lighting = Models.GetLighting(category)
		check(luminance(lighting.Ambient) >= 0.75, "ambiante débouche les ombres : " .. category)
		check(luminance(lighting.Ambient) <= 0.92, "ambiante sans surexposition : " .. category)
		check(luminance(lighting.LightColor) >= 0.9, "lumière clé franche : " .. category)

		local light = lighting.LightColor
		local lightChannels = { light.R, light.G, light.B }
		table.sort(lightChannels)
		check(lightChannels[3] - lightChannels[1] <= 0.12, "lumière quasi neutre : " .. category)

		local direction = lighting.LightDirection
		check(direction.Y < -0.4, "lumière clé plongeante : " .. category)
		local camera = Models.GetCameraDirection()
		local towardCamera = -(direction.X * camera.X + direction.Y * camera.Y + direction.Z * camera.Z)
		check(towardCamera > 0, "lumière clé côté caméra : " .. category)

		-- Direction constante : plus aucun balayage de directions au runtime.
		if referenceDirection == nil then
			referenceDirection = direction
		else
			local reference = referenceDirection :: Vector3
			check(
				direction.X == reference.X and direction.Y == reference.Y and direction.Z == reference.Z,
				"direction de lumière constante : " .. category
			)
		end
	end

	check(Models.GetBackground(nil).Bottom ~= nil, "fond par défaut disponible")
	check(Models.GetLighting(nil).Ambient ~= nil, "éclairage par défaut disponible")
	check(luminance(Models.GetViewportBackground(nil)) >= 0.2, "fond ViewportFrame par défaut lisible")

	----------------------------------------------------------------
	-- 4) Cadrage : centré, jamais coupé, jamais minuscule
	----------------------------------------------------------------

	local halfFov = math.rad(FIELD_OF_VIEW / 2)
	for _, id in ipairs(ids) do
		local spec = Models.GetSpec(id)
		local bounds = Models.GetBounds(spec)
		check(bounds.Radius >= MIN_RADIUS, ("preview assez grande (%.2f) : %s"):format(bounds.Radius, id))
		check(bounds.Radius <= MAX_RADIUS, ("preview pas surdimensionnée (%.2f) : %s"):format(bounds.Radius, id))

		local ratio = math.max(bounds.Size.X, bounds.Size.Y) / math.max(math.min(bounds.Size.X, bounds.Size.Y), 0.01)
		check(ratio <= 3.2, ("silhouette non écrasée (%.2f) : %s"):format(ratio, id))

		local distance = Models.GetCameraDistance(bounds.Radius, FIELD_OF_VIEW)
		check(distance * math.sin(halfFov) >= bounds.Radius, "objet entièrement dans le cadre : " .. id)
		check(distance * math.sin(halfFov) <= bounds.Radius * 1.4, "objet pas trop petit dans le cadre : " .. id)
	end

	----------------------------------------------------------------
	-- 4b) Halo et socle : détachent la silhouette sans sortir du cadre
	----------------------------------------------------------------

	local smallestSocle, smallestSocleId = math.huge, ""
	for _, category in ipairs(CATEGORIES) do
		local accent = Models.GetCategoryAccent(category)
		for _, id in ipairs(ids) do
			local bounds = Models.GetBounds(Models.GetSpec(id))
			local distance = Models.GetCameraDistance(bounds.Radius, FIELD_OF_VIEW)
			local backdrop = Models.GetBackdropSpec(category, bounds, FIELD_OF_VIEW)
			local label = category .. "/" .. id

			check(#backdrop == 4, "halo + socle complets : " .. label)

			local names = {}
			for _, entry in ipairs(backdrop) do
				names[entry.Name] = entry
				check(entry.Diameter > 0.2, "élément de fond visible : " .. label .. "." .. entry.Name)
				check(
					entry.Transparency >= 0.05 and entry.Transparency <= 0.85,
					"élément de fond discret : " .. label .. "." .. entry.Name
				)

				-- Rien ne doit sortir du cadre calculé pour l'objet.
				local halfSize = entry.Diameter / 2
				if entry.Placement == "Behind" then
					local limit = (distance + entry.Offset) * math.tan(math.rad(FIELD_OF_VIEW / 2))
					check(halfSize <= limit, "halo dans le cadre : " .. label .. "." .. entry.Name)
				else
					local reach = math.sqrt(halfSize * halfSize + entry.Offset * entry.Offset)
					check(reach <= distance * math.sin(math.rad(FIELD_OF_VIEW / 2)), "socle dans le cadre : " .. label .. "." .. entry.Name)
				end
			end

			check(names.Halo ~= nil and names.Halo.Placement == "Behind", "halo derrière l'objet : " .. label)
			check(names.HaloCore ~= nil and names.HaloCore.Offset < names.Halo.Offset, "cœur de halo devant le halo : " .. label)
			check(names.Socle ~= nil and names.Socle.Placement == "Ground", "socle sous l'objet : " .. label)
			check(names.SocleRing ~= nil and names.SocleRing.Diameter > names.Socle.Diameter, "anneau plus large que le socle : " .. label)
			check(names.Halo.Diameter > names.HaloCore.Diameter, "halo plus large que son cœur : " .. label)
			check(names.Halo.Color == accent, "halo teinté catégorie : " .. label)
			check(names.SocleRing.Color == accent, "anneau teinté catégorie : " .. label)
			check(names.Socle.Color ~= accent, "socle neutre : " .. label)
			check(names.Socle.Offset >= bounds.Size.Y / 2, "socle sous la silhouette : " .. label)
			check(names.Socle.Diameter >= 0.55, ("socle exploitable (%.2f) : %s"):format(names.Socle.Diameter, label))

			if names.Socle.Diameter < smallestSocle then
				smallestSocle = names.Socle.Diameter
				smallestSocleId = id
			end
		end
	end

	print(("[ShopViewportModels] socle le plus étroit : %.2f studs (%s)"):format(smallestSocle, smallestSocleId))

	----------------------------------------------------------------
	-- 5) Replis par famille
	----------------------------------------------------------------

	local fallbackKeys = Models.GetFallbackKeys()
	for _, expected in ipairs({ "Cosmetic", "Item", "Skill", "Tool" }) do
		check(table.find(fallbackKeys, expected) ~= nil, "repli disponible : " .. expected)
	end

	check(Models.GetFallbackKey("Upgrade") == "Skill", "repli Upgrade → Skill")
	check(Models.GetFallbackKey("Backpack") == "Item", "repli Backpack → Item")
	check(Models.GetFallbackKey("Cosmetic") == "Cosmetic", "repli Cosmetic → Cosmetic")
	check(Models.GetFallbackKey("Tool") == "Tool", "repli Tool → Tool")
	check(Models.GetFallbackKey(nil, "Cosmetics") == "Cosmetic", "repli par catégorie")
	check(Models.GetFallbackKey(nil, nil) == "Item", "repli par défaut")

	local unknown = Models.GetSpec("ItemQuiNExistePas", "Upgrade", "Skills")
	check(unknown.Id == "Skill", "item inconnu → repli Skill")
	check(#unknown.Parts >= MIN_PARTS, "repli non vide")

	for _, itemType in ipairs({ "Upgrade", "Backpack", "Cosmetic", "Tool" }) do
		local spec = Models.GetSpec(nil, itemType)
		local bounds = Models.GetBounds(spec)
		check(spec.Id == Models.GetFallbackKey(itemType), "repli résolu : " .. itemType)
		check(#spec.Parts >= MIN_PARTS and #spec.Parts <= MAX_PARTS, "budget du repli : " .. itemType)
		check(bounds.Radius >= MIN_RADIUS and bounds.Radius <= MAX_RADIUS, "repli bien dimensionné : " .. itemType)
	end

	----------------------------------------------------------------
	-- 6) Cohérence des accents de catégorie
	----------------------------------------------------------------

	local palette = Models.Palette
	check(Models.GetCategoryAccent("Skills") == palette.Cyan, "accent Skills")
	check(Models.GetCategoryAccent("Items") == palette.Gold, "accent Items")
	check(Models.GetCategoryAccent("Cosmetics") == palette.Violet, "accent Cosmetics")

	for _, item in ipairs(items) do
		local spec = Models.GetSpec(item.Id, item.Type, item.Category)
		local accentLuma = luminance(spec.Accent)
		check(accentLuma - brightestBackground >= 0.2, "accent lisible : " .. item.Id)
	end

	----------------------------------------------------------------
	-- 7) Les trois sacs partagent la même silhouette
	----------------------------------------------------------------

	local goldParts = Models.GetSpec("BackpackGold").Parts
	for _, id in ipairs({ "BackpackEmerald", "BackpackNeon" }) do
		local other = Models.GetSpec(id).Parts
		check(#other == #goldParts, "silhouette de sac identique : " .. id)
		local sameNames = true
		for index, entry in ipairs(other) do
			if goldParts[index] == nil or goldParts[index].Name ~= entry.Name then
				sameNames = false
			end
		end
		check(sameNames, "mêmes composants de sac : " .. id)
	end

	----------------------------------------------------------------
	-- 8) ShopUI : gradient hors du ViewportFrame, aucun code de debug
	----------------------------------------------------------------

	-- Source injectée par le harnais hors Roblox ; absente en jeu.
	local source: string? = (getfenv() :: any).SHOPUI_SOURCE
	if source then
		local text = source :: string

		local function contains(needle: string): boolean
			return string.find(text, needle, 1, true) ~= nil
		end

		print(("[ShopViewportModels] source ShopUI analysée : %d caractères"):format(#text))
		check(contains('previewBackground.Name = "PreviewBackground"'), "Frame PreviewBackground créé")
		check(contains("viewportGradient.Parent = previewBackground"), "dégradé porté par PreviewBackground")
		check(not contains("viewportGradient.Parent = viewport"), "aucun UIGradient enfant du ViewportFrame")

		-- Un seul UIGradient dans le panneau, et il n'appartient pas au viewport.
		local gradientCount = 0
		for _ in string.gmatch(text, 'Instance%.new%("UIGradient"%)') do
			gradientCount += 1
		end
		check(gradientCount == 1, ("un seul UIGradient dans ShopUI (%d)"):format(gradientCount))

		check(
			contains("viewport.BackgroundColor3 = ShopViewportModels.GetViewportBackground"),
			"fond du ViewportFrame issu de la catégorie"
		)
		check(contains("viewport.BackgroundTransparency = 0"), "fond du ViewportFrame opaque")
		check(not contains("viewport.BackgroundTransparency = 1"), "fond du ViewportFrame jamais transparent")
		check(contains("previewBackground.ZIndex = 3"), "PreviewBackground derrière")
		check(contains("viewport.ZIndex = 4"), "ViewportFrame au-dessus")

		for _, forbidden in ipairs({
			"DEBUG_VIEWPORT_LIGHTING",
			"DEBUG_LIGHT_DIRECTIONS",
			"ShopViewportDebug",
			"runViewportDebug",
			"restoreDebugGradients",
			"reportOverlays",
			"debugGeneration",
			"task.wait(2)",
			"print(",
		}) do
			check(not contains(forbidden), "aucun code de diagnostic résiduel : " .. forbidden)
		end

		-- Le rendu reste piloté par le module partagé.
		check(contains("ShopViewportModels.GetLighting"), "éclairage issu du module partagé")
		check(contains("ShopViewportModels.BuildBackdrop"), "halo et socle conservés")
		check(contains("ShopViewportModels.GetCameraCFrame"), "cadrage automatique conservé")
		check(contains("CFrame.Angles(0, previewSpin, 0)"), "rotation lente conservée")
	end

	print(("[ShopViewportModels] %d vérifications, %d échecs"):format(checks, failures))
	return failures == 0
end

return ShopViewportModelsTests
