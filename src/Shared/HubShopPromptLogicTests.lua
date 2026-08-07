--!strict
-- Tests HubShopPrompt Studio-owned (préserve pose à travers Ensure / Build path).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubShopPromptLogic = require(Shared.HubShopPromptLogic)

local HubShopPromptLogicTests = {}

local function cfAlmostEqual(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4
		and (a.LookVector - b.LookVector).Magnitude < 1e-4
end

function HubShopPromptLogicTests.Run(): boolean
	local ok = true
	local function check(cond: boolean, msg: string)
		if not cond then
			ok = false
			warn("[HubShopPromptLogicTests] FAIL:", msg)
		end
	end

	--------------------------------------------------------------------
	-- Décisions pures
	--------------------------------------------------------------------
	check(HubShopPromptLogic.ShouldPreserveStudioOwned(true) == true, "BasePart existant → preserve")
	check(HubShopPromptLogic.ShouldPreserveStudioOwned(false) == false, "absent → fallback")

	--------------------------------------------------------------------
	-- Cas 1 — prompt Studio existant : même instance, CFrame strictement identique
	--------------------------------------------------------------------
	local functional1 = Instance.new("Folder")
	functional1.Name = "HubFunction"
	local studioCF = CFrame.new(12.5, 19.25, -88.3) * CFrame.Angles(0, math.rad(37), 0)
	local studioPart = Instance.new("Part")
	studioPart.Name = "HubShopPrompt"
	studioPart.Size = Vector3.new(3, 4, 1.5)
	studioPart.CFrame = studioCF
	studioPart.Anchored = true
	studioPart.Parent = functional1
	local studioPrompt = Instance.new("ProximityPrompt")
	studioPrompt.Name = "BrowsePrompt"
	studioPrompt:SetAttribute("BPW_ShopCategory", "Skills")
	studioPrompt:SetAttribute("BPW_OpenFullShop", true)
	studioPrompt.Parent = studioPart

	local defaults = HubShopPromptLogic.DefaultPromptConfig(13)
	local out1 = HubShopPromptLogic.Ensure(functional1, function(_parent: Folder): BasePart
		error("fallback ne doit pas être appelé quand Studio existe")
	end, defaults)

	check(out1 == studioPart, "Cas1: même instance")
	check(cfAlmostEqual(out1.CFrame, studioCF), "Cas1: CFrame strictement identique")
	check(out1.Size == Vector3.new(3, 4, 1.5), "Cas1: Size préservée")
	check(out1:GetAttribute("BPW_ManualPlacement") == true, "Cas1: BPW_ManualPlacement")
	local p1 = out1:FindFirstChildWhichIsA("ProximityPrompt")
	check(p1 ~= nil, "Cas1: ProximityPrompt présent")
	check(p1 ~= nil and p1:GetAttribute("BPW_ShopCategory") == "Skills", "Cas1: catégorie Skills")
	check(p1 ~= nil and p1:GetAttribute("BPW_OpenFullShop") == true, "Cas1: OpenFullShop")

	--------------------------------------------------------------------
	-- Cas 3 — second Ensure : toujours même pose / instance
	--------------------------------------------------------------------
	local out1b = HubShopPromptLogic.Ensure(functional1, function(_parent: Folder): BasePart
		error("fallback ne doit pas être appelé au 2e Ensure")
	end, defaults)
	check(out1b == studioPart, "Cas3: instance inchangée au 2e Ensure")
	check(cfAlmostEqual(out1b.CFrame, studioCF), "Cas3: CFrame inchangé au 2e Ensure")

	functional1:Destroy()

	--------------------------------------------------------------------
	-- Cas 2 — prompt absent : fallback créé et fonctionnel
	--------------------------------------------------------------------
	local functional2 = Instance.new("Folder")
	functional2.Name = "HubFunction"
	local createdCF = CFrame.new(1, 2, 3)
	local fallbackCalls = 0
	local out2 = HubShopPromptLogic.Ensure(functional2, function(parent: Folder): BasePart
		fallbackCalls += 1
		local p = Instance.new("Part")
		p.Name = "HubShopPrompt"
		p.Size = Vector3.new(4, 5, 2)
		p.CFrame = createdCF
		p.Anchored = true
		p.Parent = parent
		return p
	end, defaults)

	check(fallbackCalls == 1, "Cas2: fallback appelé une fois")
	check(out2.Name == "HubShopPrompt", "Cas2: nom HubShopPrompt")
	check(out2:GetAttribute("BPW_ManualPlacement") == true, "Cas2: tag manuel après création")
	local p2 = out2:FindFirstChildWhichIsA("ProximityPrompt")
	check(p2 ~= nil, "Cas2: ProximityPrompt créé")
	check(p2 ~= nil and p2:GetAttribute("BPW_ShopCategory") == "Skills", "Cas2: catégorie")
	check(p2 ~= nil and p2:GetAttribute("BPW_OpenFullShop") == true, "Cas2: OpenFullShop")

	-- Cas 3 bis : second Ensure après création fallback → pas de nouveau Destroy/recreate
	local cfAfterCreate = out2.CFrame
	local out2b = HubShopPromptLogic.Ensure(functional2, function(_parent: Folder): BasePart
		error("fallback ne doit plus être appelé une fois créé")
	end, defaults)
	check(out2b == out2, "Cas3bis: même instance après création")
	check(cfAlmostEqual(out2b.CFrame, cfAfterCreate), "Cas3bis: pose stable")

	functional2:Destroy()

	if ok then
		print("[HubShopPromptLogicTests] OK")
	end
	return ok
end

return HubShopPromptLogicTests
