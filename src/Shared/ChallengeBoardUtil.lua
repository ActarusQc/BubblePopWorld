--!strict
-- Formatage pur des lignes Challenges pour le panneau 3D monde (testable).

local ChallengeBoardUtil = {}

export type ChallengePublic = {
	Id: string?,
	TitleKey: string?,
	DescKey: string?,
	Progress: number?,
	Target: number?,
	Completed: boolean?,
	Claimed: boolean?,
	Slot: string?,
}

export type BoardLine = {
	Id: string,
	Status: string, -- "✓" | "○"
	Title: string,
	ProgressText: string, -- "37 / 50"
	Completed: boolean,
}

local function safeText(v: any, fallback: string): string
	if type(v) == "string" and v ~= "" then
		return v
	end
	return fallback
end

function ChallengeBoardUtil.StatusMark(completed: boolean): string
	return if completed then "✓" else "○"
end

function ChallengeBoardUtil.ProgressText(progress: number, target: number): string
	local p = math.max(0, math.floor(progress))
	local t = math.max(1, math.floor(target))
	if p > t then
		p = t
	end
	return string.format("%d / %d", p, t)
end

-- localize(key, fallback) → string
function ChallengeBoardUtil.BuildLine(
	ch: ChallengePublic,
	localize: (string, string) -> string
): BoardLine
	local id = safeText(ch.Id, "unknown")
	local target = math.max(1, math.floor(tonumber(ch.Target) or 1))
	local progress = math.max(0, math.floor(tonumber(ch.Progress) or 0))
	local completed = ch.Completed == true or progress >= target or ch.Claimed == true
	if completed then
		progress = math.max(progress, target)
	end

	local titleKey = safeText(ch.TitleKey, "Challenge")
	local title = localize(titleKey, titleKey)
	-- Fallback description courte si le titre n'est qu'une clé brute
	if title == titleKey and type(ch.DescKey) == "string" and ch.DescKey ~= "" then
		local desc = localize(ch.DescKey, ch.DescKey)
		desc = desc:gsub("{target}", tostring(target)):gsub("{progress}", tostring(progress))
		title = desc
	end

	return {
		Id = id,
		Status = ChallengeBoardUtil.StatusMark(completed),
		Title = title,
		ProgressText = ChallengeBoardUtil.ProgressText(progress, target),
		Completed = completed,
	}
end

function ChallengeBoardUtil.BuildDailyLines(
	daily: { ChallengePublic }?,
	localize: (string, string) -> string,
	maxRows: number?
): { BoardLine }
	local limit = maxRows or 2
	local out: { BoardLine } = {}
	if type(daily) ~= "table" then
		return out
	end
	for _, ch in ipairs(daily) do
		if #out >= limit then
			break
		end
		if type(ch) == "table" then
			table.insert(out, ChallengeBoardUtil.BuildLine(ch, localize))
		end
	end
	return out
end

function ChallengeBoardUtil.BuildWeeklyLines(
	weekly: ChallengePublic?,
	localize: (string, string) -> string,
	maxRows: number?
): { BoardLine }
	local limit = maxRows or 3
	local out: { BoardLine } = {}
	if type(weekly) == "table" and (weekly.Id or weekly.TitleKey) then
		table.insert(out, ChallengeBoardUtil.BuildLine(weekly, localize))
	end
	while #out < limit do
		-- pas de faux défis : lignes vides gérées par l'UI
		break
	end
	return out
end

return ChallengeBoardUtil
