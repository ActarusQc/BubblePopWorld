# Task 7
BASE: 52615eb HEAD: 92035c5f5021e8ef7bc8023b6377f205912850cb
## Commits
92035c5 feat: show backpack gauge from player attributes

## Stat
 src/Client/HUD.lua        | 70 +++++++++++++++++++++++++++++++++++++++++++++++
 src/Client/PopEffects.lua |  3 +-
 2 files changed, 72 insertions(+), 1 deletion(-)

## Diff
```diff
diff --git a/src/Client/HUD.lua b/src/Client/HUD.lua
index 94637ee..7c917c6 100644
--- a/src/Client/HUD.lua
+++ b/src/Client/HUD.lua
@@ -75,16 +75,47 @@ function HUD.Start()
 
 	local xpFill = Instance.new("Frame")
 	xpFill.Size = UDim2.new(0, 0, 1, 0)
 	xpFill.BackgroundColor3 = ACCENT
 	xpFill.BorderSizePixel = 0
 	xpFill.Parent = xpBack
 	corner(xpFill, 7)
 
+	-- Jauge du sac : son ├⌐tat provient exclusivement des attributs du joueur.
+	local backpackFrame = Instance.new("Frame")
+	backpackFrame.Size = UDim2.new(0, 260, 0, 74)
+	backpackFrame.Position = UDim2.new(0, 16, 0, 120)
+	backpackFrame.BackgroundColor3 = BG
+	backpackFrame.BackgroundTransparency = 0.15
+	backpackFrame.BorderSizePixel = 0
+	backpackFrame.Parent = gui
+	corner(backpackFrame, 14)
+
+	local backpackLabel = label(backpackFrame, "Sac 0 / 0", UDim2.new(1, -24, 0, 24), UDim2.new(0, 12, 0, 7))
+
+	local backpackBack = Instance.new("Frame")
+	backpackBack.Size = UDim2.new(1, -24, 0, 14)
+	backpackBack.Position = UDim2.new(0, 12, 0, 34)
+	backpackBack.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
+	backpackBack.BorderSizePixel = 0
+	backpackBack.Parent = backpackFrame
+	corner(backpackBack, 7)
+
+	local backpackFill = Instance.new("Frame")
+	backpackFill.Size = UDim2.new(0, 0, 1, 0)
+	backpackFill.BackgroundColor3 = ACCENT
+	backpackFill.BorderSizePixel = 0
+	backpackFill.Parent = backpackBack
+	corner(backpackFill, 7)
+
+	local backpackStatus = label(backpackFrame, "Place disponible", UDim2.new(1, -24, 0, 18), UDim2.new(0, 12, 0, 52), false)
+	backpackStatus.TextColor3 = ACCENT
+	backpackStatus.TextSize = 13
+
 	-- Compteur mondial
 	local globalFrame = Instance.new("Frame")
 	globalFrame.Size = UDim2.new(0, 320, 0, 52)
 	globalFrame.Position = UDim2.new(0.5, -160, 0, 12)
 	globalFrame.BackgroundColor3 = BG
 	globalFrame.BackgroundTransparency = 0.2
 	globalFrame.BorderSizePixel = 0
 	globalFrame.Parent = gui
@@ -142,24 +173,63 @@ function HUD.Start()
 		task.delay(4, function()
 			TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
 			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
 			task.wait(0.45)
 			frame:Destroy()
 		end)
 	end
 
+	local function attributeNumber(name: string): number
+		local value = player:GetAttribute(name)
+		return if type(value) == "number" then value else 0
+	end
+
+	local function refreshBackpack()
+		local current = math.max(0, attributeNumber("CurrentBubbles"))
+		local capacity = math.max(0, attributeNumber("BackpackCapacity"))
+		local pendingSellValue = math.max(0, attributeNumber("PendingSellValue"))
+		local area = player:GetAttribute("PlayerArea")
+		local ratio = if capacity > 0 then math.clamp(current / capacity, 0, 1) else 0
+
+		backpackLabel.Text = ("Sac %s / %s"):format(comma(current), comma(capacity))
+		backpackFill.Size = UDim2.new(ratio, 0, 1, 0)
+
+		if ratio >= 1 then
+			backpackFill.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
+			backpackStatus.TextColor3 = Color3.fromRGB(255, 120, 120)
+			backpackStatus.Text = "Sac plein !"
+		elseif ratio >= Config.Backpack.NearlyFullRatio then
+			backpackFill.BackgroundColor3 = Color3.fromRGB(255, 190, 70)
+			backpackStatus.TextColor3 = Color3.fromRGB(255, 210, 90)
+			backpackStatus.Text = "Sac presque plein"
+		else
+			backpackFill.BackgroundColor3 = ACCENT
+			backpackStatus.TextColor3 = ACCENT
+			backpackStatus.Text = "Place disponible"
+		end
+
+		if area == "Lobby" then
+			backpackStatus.Text = ("Valeur du sac : %s pi├¿ces"):format(comma(pendingSellValue))
+		end
+	end
+
 	-- Branchements
 	Remotes.Event("StatsUpdate").OnClientEvent:Connect(function(stats)
 		coinsLabel.Text = comma(stats.Coins) .. " pi├¿ces"
 		levelLabel.Text = ("Niveau %d  ┬╖  %s bulles"):format(stats.Level, comma(stats.Pops))
 		local ratio = if stats.XPNeeded > 0 then math.clamp(stats.XP / stats.XPNeeded, 0, 1) else 0
 		TweenService:Create(xpFill, TweenInfo.new(0.25), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
 	end)
 
+	for _, attributeName in { "CurrentBubbles", "BackpackCapacity", "PendingSellValue", "PlayerArea" } do
+		player:GetAttributeChangedSignal(attributeName):Connect(refreshBackpack)
+	end
+	refreshBackpack()
+
 	Remotes.Event("GlobalCounter").OnClientEvent:Connect(function(total, target)
 		globalLabel.Text = ("%s / %s bulles"):format(comma(total), comma(target))
 		goalFill.Size = UDim2.new(math.clamp(total / target, 0, 1), 0, 1, 0)
 	end)
 
 	Remotes.Event("Announce").OnClientEvent:Connect(toast)
 
 	HUD.Toast = toast
diff --git a/src/Client/PopEffects.lua b/src/Client/PopEffects.lua
index 08f0faf..3c7f186 100644
--- a/src/Client/PopEffects.lua
+++ b/src/Client/PopEffects.lua
@@ -114,17 +114,18 @@ function PopEffects.Start()
 			if origin and (pos - origin).Magnitude > 140 then continue end
 
 			local def = BubbleTypes.ById[rarity] or BubbleTypes.List[1]
 			local special = rarity ~= "Normal"
 
 			burst(pos, def.Color, special)
 
 			if special then
-				floatingText(pos, "+" .. def.Coins, def.Color)
+				local storageValue = if type(def.StorageValue) == "number" then math.max(1, math.floor(def.StorageValue)) else 1
+				floatingText(pos, "+" .. storageValue, def.Color)
 			end
 
 			if played < 4 then
 				playPop(rarity)
 				played += 1
 			end
 		end
 	end)

```
