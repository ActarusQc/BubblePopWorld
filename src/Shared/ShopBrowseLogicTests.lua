--!strict
-- Tests purs pour ShopBrowseLogic (navigation cyclique + garde d'achat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopBrowseLogic = require(Shared.ShopBrowseLogic)

local ShopBrowseLogicTests = {}

function ShopBrowseLogicTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[ShopBrowseLogicTests] FAIL:", msg)
		end
	end

	-- Navigation avant : boucle dernier -> premier.
	check(ShopBrowseLogic.NextIndex(1, 4) == 2, "next 1->2")
	check(ShopBrowseLogic.NextIndex(2, 4) == 3, "next 2->3")
	check(ShopBrowseLogic.NextIndex(3, 4) == 4, "next 3->4")
	check(ShopBrowseLogic.NextIndex(4, 4) == 1, "next loops last->first")
	check(ShopBrowseLogic.NextIndex(1, 1) == 1, "next single item stays 1")
	check(ShopBrowseLogic.NextIndex(1, 0) == 1, "next empty list stays 1")

	-- Navigation arrière : boucle premier -> dernier.
	check(ShopBrowseLogic.PrevIndex(4, 4) == 3, "prev 4->3")
	check(ShopBrowseLogic.PrevIndex(3, 4) == 2, "prev 3->2")
	check(ShopBrowseLogic.PrevIndex(2, 4) == 1, "prev 2->1")
	check(ShopBrowseLogic.PrevIndex(1, 4) == 4, "prev loops first->last")
	check(ShopBrowseLogic.PrevIndex(1, 1) == 1, "prev single item stays 1")
	check(ShopBrowseLogic.PrevIndex(1, 0) == 1, "prev empty list stays 1")

	-- Round-trip complet sur une liste de 5.
	do
		local index = 1
		for _ = 1, 5 do
			index = ShopBrowseLogic.NextIndex(index, 5)
		end
		check(index == 1, "5 next() ramène au point de départ")
	end

	-- Clamp après réduction de liste (ex. refresh serveur).
	check(ShopBrowseLogic.ClampIndex(7, 4) == 4, "clamp au-dessus retombe sur count")
	check(ShopBrowseLogic.ClampIndex(0, 4) == 1, "clamp en dessous retombe sur 1")
	check(ShopBrowseLogic.ClampIndex(2, 4) == 2, "clamp dans les bornes inchangé")
	check(ShopBrowseLogic.ClampIndex(1, 0) == 1, "clamp liste vide retombe sur 1")

	-- Conserver la sélection par Id après refresh.
	local items = {
		{ Id = "Speed" },
		{ Id = "Jump" },
		{ Id = "Power" },
	}
	check(ShopBrowseLogic.FindIndexById(items, "Jump", 1) == 2, "retrouve Jump index 2")
	check(ShopBrowseLogic.FindIndexById(items, "Unknown", 3) == 3, "Id absent retombe sur fallback clampé")
	check(ShopBrowseLogic.FindIndexById(items, nil, 2) == 2, "Id nil retombe sur fallback clampé")
	check(ShopBrowseLogic.FindIndexById({}, "Speed", 5) == 1, "liste vide retombe sur 1")

	-- Garde d'achat : uniquement Buy / Upgrade / Equip, et seulement si Available == true.
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "Buy" }) == true, "Buy invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "Upgrade" }) == true, "Upgrade invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "Equip" }) == true, "Equip invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "EquipCosmetic" }) == true, "EquipCosmetic invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "ComingSoon" }) == false, "ComingSoon jamais invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "Locked" }) == false, "Locked jamais invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "TooExpensive" }) == false, "TooExpensive jamais invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "Equipped" }) == false, "Equipped jamais invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = "Max" }) == false, "Max jamais invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = false, ButtonState = "Buy" }) == false, "Available=false bloque même si ButtonState=Buy")
	check(ShopBrowseLogic.CanInvokeAction(nil) == false, "item nil jamais invocable")
	check(ShopBrowseLogic.CanInvokeAction({ Available = true, ButtonState = nil }) == false, "ButtonState nil jamais invocable")

	-- Mapping remote exact.
	check(ShopBrowseLogic.RemoteForButtonState("Buy") == "BuyItem", "Buy -> BuyItem")
	check(ShopBrowseLogic.RemoteForButtonState("Upgrade") == "BuyUpgrade", "Upgrade -> BuyUpgrade")
	check(ShopBrowseLogic.RemoteForButtonState("Equip") == "EquipBackpack", "Equip -> EquipBackpack")
	check(ShopBrowseLogic.RemoteForButtonState("EquipCosmetic") == "EquipCosmetic", "EquipCosmetic -> EquipCosmetic")
	check(ShopBrowseLogic.RemoteForButtonState("ComingSoon") == nil, "ComingSoon -> aucun remote")
	check(ShopBrowseLogic.RemoteForButtonState(nil) == nil, "nil -> aucun remote")

	if failed == 0 then
		print("[ShopBrowseLogicTests] OK")
		return true
	end
	return false
end

return ShopBrowseLogicTests
