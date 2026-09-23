--!strict
-- Style Custom des coffres : pas d'UI Roblox, mais il faut relayer E / clic.

local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local TentChestController = {}

local activePrompt: ProximityPrompt? = nil
local holding = false

local function isTentChestPrompt(prompt: ProximityPrompt): boolean
	return prompt.Name == "OpenTentChest" or type(prompt:GetAttribute("TentChestId")) == "string"
end

local function beginHold()
	local prompt = activePrompt
	if not prompt or holding then
		return
	end
	holding = true
	pcall(function()
		prompt:InputHoldBegin()
	end)
end

local function endHold()
	local prompt = activePrompt
	if not holding then
		return
	end
	holding = false
	if prompt then
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end
end

function TentChestController.Start()
	ProximityPromptService.PromptShown:Connect(function(prompt, _inputType)
		if not isTentChestPrompt(prompt) then
			return
		end
		activePrompt = prompt
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if prompt ~= activePrompt then
			return
		end
		endHold()
		activePrompt = nil
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or GuiService.MenuIsOpen then
			return
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if not activePrompt then
			return
		end
		local key = input.KeyCode
		local isActivate = key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonX
		if isActivate then
			beginHold()
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if not holding then
			return
		end
		local key = input.KeyCode
		local isActivate = key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonX
		if isActivate then
			endHold()
		end
	end)
end

return TentChestController
