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
	check(ShopCatalog.IsPurchasable("Cap") == true, "Cap purchasable")
	check(ShopCatalog.IsPurchasable("FrogHat") == true, "FrogHat purchasable")
	check(ShopCatalog.IsPurchasable("WizardHat") == true, "WizardHat purchasable")
	check(ShopCatalog.IsPurchasable("BlueJeweledCrown") == true, "BlueJeweledCrown purchasable")
	check(ShopCatalog.IsPurchasable("Unknown") == false, "Unknown not purchasable")

	check(#ShopCatalog.GetCategoryItems("Skills") >= 5, "Skills has live + coming soon")
	check(#ShopCatalog.GetCategoryItems("Items") >= 5, "Items has live + coming soon")
	check(#ShopCatalog.GetCategoryItems("Hats") == 4, "Hats populated")
	check(#ShopCatalog.GetCategoryItems("Vests") >= 1, "Vests populated")
	check(#ShopCatalog.GetCategoryItems("Shirts") >= 1, "Shirts populated")
	check(#ShopCatalog.GetCategoryItems("Accessories") >= 1, "Accessories populated")
	check(#ShopCatalog.GetCategoryItems("Shoes") >= 1, "Shoes populated")

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
	check(ShopCatalog.Categories[3] == "Hats", "third category Hats")
	check(ShopCatalog.Categories[7] == "Shoes", "seventh category Shoes")

	local speed = ShopCatalog.GetItem("Speed")
	check(speed ~= nil and speed.UpgradeId == "Speed", "Speed UpgradeId")
	check(speed ~= nil and speed.Type == "Upgrade", "Speed Type Upgrade")

	local gold = ShopCatalog.GetItem("BackpackGold")
	check(gold ~= nil and gold.ShopItemId == "BackpackGold", "BackpackGold ShopItemId")
	check(gold ~= nil and gold.Equipable == true, "BackpackGold Equipable")
	local cap = ShopCatalog.GetItem("Cap")
	check(cap ~= nil and cap.ModelName == "MulticolorCapAccessory", "Cap uses imported accessory")
	local frog = ShopCatalog.GetItem("FrogHat")
	check(frog ~= nil and frog.ModelName == "FrogHatAccessory", "FrogHat uses imported accessory")
	local wizard = ShopCatalog.GetItem("WizardHat")
	check(wizard ~= nil and wizard.ModelName == "WizardHatAccessory", "WizardHat uses imported accessory")
	local crown = ShopCatalog.GetItem("BlueJeweledCrown")
	check(crown ~= nil and crown.ModelName == "BlueJeweledCrownAccessory", "BlueJeweledCrown uses imported accessory")

	if failed == 0 then
		print("[ShopCatalogTests] OK")
		return true
	end
	return false
end

return ShopCatalogTests
