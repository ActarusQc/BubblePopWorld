--!strict
-- Logique pure du browse boutique walk-in : navigation cyclique + garde d'achat.
-- Aucune dépendance Roblox : testable hors Studio (tools/run_shop_browse_logic_tests.py).

export type ShopBrowseRow = {
	Id: string,
	Available: boolean?,
	ButtonState: string?,
}

local ShopBrowseLogic = {}

-- Étiquette bouton (EN, via L10n côté UI) -> nom du RemoteFunction à invoquer.
-- Seuls ces trois états déclenchent un achat/équipement serveur.
local ACTION_REMOTES: { [string]: string } = {
	Buy = "BuyItem",
	Upgrade = "BuyUpgrade",
	Equip = "EquipBackpack",
}

-- Index suivant en boucle (dernier -> premier). count <= 0 retombe sur 1 (liste vide).
function ShopBrowseLogic.NextIndex(index: number, count: number): number
	if count <= 0 then
		return 1
	end
	local i = math.floor(index)
	return (i % count) + 1
end

-- Index précédent en boucle (premier -> dernier).
function ShopBrowseLogic.PrevIndex(index: number, count: number): number
	if count <= 0 then
		return 1
	end
	local i = math.floor(index)
	return ((i - 2) % count) + 1
end

-- Ramène un index hors bornes (ex. liste raccourcie après refresh) dans [1, count].
function ShopBrowseLogic.ClampIndex(index: number, count: number): number
	if count <= 0 then
		return 1
	end
	return math.clamp(math.floor(index), 1, count)
end

-- Retrouve l'index d'un Id après un refresh serveur ; retombe sur fallback (clampé) si absent.
function ShopBrowseLogic.FindIndexById(items: { ShopBrowseRow }, id: string?, fallback: number): number
	if type(id) == "string" then
		for i, item in ipairs(items) do
			if item.Id == id then
				return i
			end
		end
	end
	return ShopBrowseLogic.ClampIndex(fallback, #items)
end

-- Seuls Buy / Upgrade / Equip déclenchent un remote, et seulement si Available == true.
-- ComingSoon / Locked / TooExpensive / Equipped / Max / Available=false : jamais.
function ShopBrowseLogic.CanInvokeAction(item: ShopBrowseRow?): boolean
	if type(item) ~= "table" then
		return false
	end
	if item.Available ~= true then
		return false
	end
	local state = item.ButtonState
	return type(state) == "string" and ACTION_REMOTES[state] ~= nil
end

-- Nom du RemoteFunction pour un ButtonState donné, ou nil si non actionnable.
function ShopBrowseLogic.RemoteForButtonState(buttonState: string?): string?
	if type(buttonState) ~= "string" then
		return nil
	end
	return ACTION_REMOTES[buttonState]
end

return ShopBrowseLogic
