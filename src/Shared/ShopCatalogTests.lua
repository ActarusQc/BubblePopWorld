--!strict
-- Tests purs pour ShopCatalog (items live, Coming Soon, catégories).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopCatalog = require(Shared.ShopCatalog)

local ShopCatalogTests = {}

function ShopCatalogTests.Run(): boolean
	local failed = 0
	local function check(cond: boolean, msg: string)
		if not cond then
			failed += 1
			warn("[ShopCatalogTests] FAIL:", msg)
		end
	end

	check(ShopCatalog.IsPurchasable("Speed") == true, "Speed purchasable")
	check(ShopCatalog.IsPurchasable("Jump") == true, "Jump purchasable")
	check(ShopCatalog.IsPurchasable("BackpackGold") == true, "BackpackGold purchasable")
	check(ShopCatalog.IsPurchasable("BackpackEmerald") == true, "BackpackEmerald purchasable")
	check(ShopCatalog.IsPurchasable("BackpackNeon") == true, "BackpackNeon purchasable")
	check(ShopCatalog.IsPurchasable("Magnet") == false, "Magnet not purchasable")
	check(ShopCatalog.IsPurchasable("Luck") == false, "Luck not purchasable")
	check(ShopCatalog.IsPurchasable("Cap") == false, "Cap not purchasable")
	check(ShopCatalog.IsPurchasable("Unknown") == false, "Unknown not purchasable")

	check(#ShopCatalog.GetCategoryItems("Skills") >= 5, "Skills has live + coming soon")
	check(#ShopCatalog.GetCategoryItems("Items") >= 5, "Items has live + coming soon")
	check(#ShopCatalog.GetCategoryItems("Cosmetics") >= 3, "Cosmetics populated")

	local skills = ShopCatalog.GetCategoryItems("Skills")
	local liveSkillCount = 0
	for _, item in ipairs(skills) do
		if item.Available then
			liveSkillCount += 1
		end
	end
	check(liveSkillCount == 4, "Skills has 4 live upgrades")

	check(ShopCatalog.Categories[1] == "Skills", "first category Skills")
	check(ShopCatalog.Categories[2] == "Items", "second category Items")
	check(ShopCatalog.Categories[3] == "Cosmetics", "third category Cosmetics")

	local speed = ShopCatalog.GetItem("Speed")
	check(speed ~= nil and speed.UpgradeId == "Speed", "Speed UpgradeId")
	check(speed ~= nil and speed.Type == "Upgrade", "Speed Type Upgrade")

	local gold = ShopCatalog.GetItem("BackpackGold")
	check(gold ~= nil and gold.ShopItemId == "BackpackGold", "BackpackGold ShopItemId")
	check(gold ~= nil and gold.Equipable == true, "BackpackGold Equipable")

	if failed == 0 then
		print("[ShopCatalogTests] OK")
		return true
	end
	return false
end

return ShopCatalogTests
