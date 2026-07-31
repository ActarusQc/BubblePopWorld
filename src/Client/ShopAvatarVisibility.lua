--!strict
-- Masquage 100 % local du personnage pendant le browse boutique.

export type Snapshot = { [BasePart]: number }

local ShopAvatarVisibility = {}

function ShopAvatarVisibility.HidePart(part: BasePart, snapshot: Snapshot)
	if snapshot[part] == nil then
		snapshot[part] = part.LocalTransparencyModifier
	end
	part.LocalTransparencyModifier = 1
end

function ShopAvatarVisibility.HideCharacter(character: Model, snapshot: Snapshot)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			ShopAvatarVisibility.HidePart(descendant, snapshot)
		end
	end
end

function ShopAvatarVisibility.Restore(snapshot: Snapshot)
	for part, localTransparency in pairs(snapshot) do
		pcall(function()
			part.LocalTransparencyModifier = localTransparency
		end)
	end
	table.clear(snapshot)
end

return ShopAvatarVisibility
