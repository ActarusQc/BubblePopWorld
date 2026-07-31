--!strict

local ShopAvatarVisibility = require(script.Parent.ShopAvatarVisibility)

local Tests = {}

local function check(condition: boolean, message: string)
	if not condition then
		error("[ShopAvatarVisibilityTests] " .. message, 2)
	end
end

local function fakePart(localTransparency: number): any
	return {
		Parent = {},
		LocalTransparencyModifier = localTransparency,
		IsA = function(_self: any, className: string): boolean
			return className == "BasePart"
		end,
	}
end

function Tests.Run(): boolean
	local body = fakePart(0)
	local accessoryHandle = fakePart(0.35)
	local toolHandle = fakePart(0.7)
	local nonPart = {
		IsA = function(): boolean
			return false
		end,
	}
	local character = {
		GetDescendants = function(): { any }
			return { body, accessoryHandle, toolHandle, nonPart }
		end,
	}
	local snapshot = {}

	ShopAvatarVisibility.HideCharacter(character :: any, snapshot)
	check(body.LocalTransparencyModifier == 1, "le corps doit être masqué localement")
	check(accessoryHandle.LocalTransparencyModifier == 1, "les accessoires doivent être masqués")
	check(toolHandle.LocalTransparencyModifier == 1, "les outils équipés doivent être masqués")

	ShopAvatarVisibility.HidePart(body :: any, snapshot)
	ShopAvatarVisibility.Restore(snapshot)
	check(body.LocalTransparencyModifier == 0, "le corps doit retrouver sa valeur exacte")
	check(accessoryHandle.LocalTransparencyModifier == 0.35, "l'accessoire doit retrouver sa valeur exacte")
	check(toolHandle.LocalTransparencyModifier == 0.7, "l'outil doit retrouver sa valeur exacte")
	check(next(snapshot) == nil, "la restauration doit vider l'instantané")

	ShopAvatarVisibility.Restore(snapshot)
	check(body.LocalTransparencyModifier == 0, "une seconde restauration doit être sans effet")

	local addedPart = fakePart(0.2)
	ShopAvatarVisibility.HidePart(addedPart :: any, snapshot)
	check(addedPart.LocalTransparencyModifier == 1, "une pièce ajoutée pendant le browse doit être masquée")
	ShopAvatarVisibility.Restore(snapshot)
	check(addedPart.LocalTransparencyModifier == 0.2, "une pièce ajoutée doit être restaurée exactement")

	print("[ShopAvatarVisibilityTests] OK")
	return true
end

return Tests
