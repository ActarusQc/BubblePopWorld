--!strict
-- HubShopPrompt Studio-owned : préserver pose Studio ; fallback HubLayout seulement si absent.

local HubShopPromptLogic = {}

export type PromptDefaults = {
	ActionText: string,
	ObjectText: string,
	MaxActivationDistance: number,
	HoldDuration: number,
	RequiresLineOfSight: boolean,
	KeyboardKeyCode: Enum.KeyCode,
	GamepadKeyCode: Enum.KeyCode,
	ShopCategory: string,
	OpenFullShop: boolean,
}

function HubShopPromptLogic.ShouldPreserveStudioOwned(existingIsBasePart: boolean): boolean
	return existingIsBasePart == true
end

function HubShopPromptLogic.DefaultPromptConfig(maxDistance: number?): PromptDefaults
	return {
		ActionText = "Open Shop",
		ObjectText = "SHOP",
		MaxActivationDistance = if type(maxDistance) == "number" then maxDistance else 13,
		HoldDuration = 0,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		ShopCategory = "Skills",
		OpenFullShop = true,
	}
end

function HubShopPromptLogic.FindExisting(functional: Folder): BasePart?
	local inst = functional:FindFirstChild("HubShopPrompt")
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function findBrowsePrompt(anchor: BasePart): ProximityPrompt?
	local named = anchor:FindFirstChild("BrowsePrompt")
	if named and named:IsA("ProximityPrompt") then
		return named
	end
	local any = anchor:FindFirstChildWhichIsA("ProximityPrompt")
	if any then
		return any
	end
	return nil
end

--- Configure le ProximityPrompt sans toucher CFrame/Size du Part.
--- Préserve ActionText/ObjectText/etc. déjà définis ; complète seulement le nécessaire.
function HubShopPromptLogic.EnsureBrowsePrompt(anchor: BasePart, defaults: PromptDefaults): ProximityPrompt
	local prompt = findBrowsePrompt(anchor)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BrowsePrompt"
		prompt.ActionText = defaults.ActionText
		prompt.ObjectText = defaults.ObjectText
		prompt.HoldDuration = defaults.HoldDuration
		prompt.MaxActivationDistance = defaults.MaxActivationDistance
		prompt.RequiresLineOfSight = defaults.RequiresLineOfSight
		prompt.KeyboardKeyCode = defaults.KeyboardKeyCode
		prompt.GamepadKeyCode = defaults.GamepadKeyCode
		prompt.Parent = anchor
	else
		if prompt.Name == "" then
			prompt.Name = "BrowsePrompt"
		end
		-- Propriétés runtime strictement nécessaires si absentes / invalides.
		if prompt.MaxActivationDistance <= 0 then
			prompt.MaxActivationDistance = defaults.MaxActivationDistance
		end
		prompt.RequiresLineOfSight = false
	end

	if prompt:GetAttribute("BPW_ShopCategory") == nil then
		prompt:SetAttribute("BPW_ShopCategory", defaults.ShopCategory)
	end
	if prompt:GetAttribute("BPW_OpenFullShop") == nil then
		prompt:SetAttribute("BPW_OpenFullShop", defaults.OpenFullShop)
	end
	return prompt
end

function HubShopPromptLogic.TagStudioOwned(anchor: BasePart)
	anchor:SetAttribute("BPW_ManualPlacement", true)
	anchor:SetAttribute("HubInteraction", "Shop")
end

--- Autorité unique : HubFunction.HubShopPrompt.
--- Si présent → aucune écriture CFrame/Position/Size/Orientation.
--- Si absent → createFallback (HubLayout côté builder).
function HubShopPromptLogic.Ensure(
	functional: Folder,
	createFallback: (Folder) -> BasePart,
	defaults: PromptDefaults
): BasePart
	local existing = HubShopPromptLogic.FindExisting(functional)
	if existing and HubShopPromptLogic.ShouldPreserveStudioOwned(true) then
		HubShopPromptLogic.TagStudioOwned(existing)
		HubShopPromptLogic.EnsureBrowsePrompt(existing, defaults)
		return existing
	end

	local created = createFallback(functional)
	HubShopPromptLogic.TagStudioOwned(created)
	HubShopPromptLogic.EnsureBrowsePrompt(created, defaults)
	return created
end

return HubShopPromptLogic
