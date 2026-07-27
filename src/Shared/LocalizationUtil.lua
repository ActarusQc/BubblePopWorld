--!strict
-- Helpers AutoLocalize : appliquer une fois à la création / init, jamais chaque frame.

local LocalizationUtil = {}

export type TextGui = TextLabel | TextButton | TextBox

function LocalizationUtil.localize(gui: TextGui, text: string?): TextGui
	if text ~= nil then
		gui.Text = text
	end
	gui.AutoLocalize = true
	return gui
end

function LocalizationUtil.dynamic(gui: TextGui, text: string?): TextGui
	if text ~= nil then
		gui.Text = text
	end
	gui.AutoLocalize = false
	return gui
end

-- Parcourt une fois les descendants Text* (init uniquement).
function LocalizationUtil.applyTree(root: Instance, localizeFixed: boolean?)
	local enable = if localizeFixed == nil then true else localizeFixed
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
			local skip = desc:GetAttribute("BPW_NoLocalize") == true
			if skip then
				(desc :: TextGui).AutoLocalize = false
			elseif enable then
				(desc :: TextGui).AutoLocalize = true
			end
		end
	end
end

function LocalizationUtil.markNoLocalize(gui: TextGui)
	gui:SetAttribute("BPW_NoLocalize", true)
	gui.AutoLocalize = false
end

return LocalizationUtil
