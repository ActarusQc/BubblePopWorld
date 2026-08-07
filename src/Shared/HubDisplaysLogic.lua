--!strict
-- Logique pure classements hub (niveaux, ancrages, validation FindFirstChild).

local LeaderboardUtil = require(script.Parent.LeaderboardUtil)

local HubDisplaysLogic = {}

HubDisplaysLogic.LEVELS_STORE = "GlobalHighestLevels_v1"
HubDisplaysLogic.TOP_N = 10
HubDisplaysLogic.REFRESH_INTERVAL_SEC = 60

function HubDisplaysLogic.SanitizeLevel(value: any): number?
	local n = tonumber(value)
	if type(n) ~= "number" then
		return nil
	end
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	-- Niveaux entiers ≥ 1 ; floor pour bloquer les fractions / temp.
	local floor = math.floor(n)
	if floor < 1 then
		return nil
	end
	return math.clamp(floor, 1, 2 ^ 31 - 1)
end

-- Ne jamais réduire le meilleur niveau enregistré (profil non chargé, temp, etc.).
function HubDisplaysLogic.MergeHighestLevel(existing: any, candidate: any): number?
	local cand = HubDisplaysLogic.SanitizeLevel(candidate)
	if cand == nil then
		return HubDisplaysLogic.SanitizeLevel(existing)
	end
	local prev = HubDisplaysLogic.SanitizeLevel(existing)
	if prev == nil then
		return cand
	end
	return math.max(prev, cand)
end

function HubDisplaysLogic.FormatLevel(value: number): string
	return "Lv " .. tostring(math.floor(math.max(0, value)))
end

function HubDisplaysLogic.TruncateName(name: string, maxChars: number?): string
	local n = maxChars or 14
	local s = tostring(name or "")
	if #s <= n then
		return s
	end
	return string.sub(s, 1, math.max(1, n - 1)) .. "…"
end

function HubDisplaysLogic.SafeFindFirstChild(parent: any, childName: string): Instance?
	if typeof(parent) ~= "Instance" then
		return nil
	end
	if not parent:IsA("Instance") then
		return nil
	end
	local child = parent:FindFirstChild(childName)
	if typeof(child) == "Instance" then
		return child
	end
	return nil
end

function HubDisplaysLogic.AsBasePart(inst: any): BasePart?
	if typeof(inst) ~= "Instance" then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	return nil
end

function HubDisplaysLogic.AsFrame(inst: any): Frame?
	if typeof(inst) ~= "Instance" then
		return nil
	end
	if inst:IsA("Frame") then
		return inst
	end
	return nil
end

function HubDisplaysLogic.AsSurfaceGui(inst: any): SurfaceGui?
	if typeof(inst) ~= "Instance" then
		return nil
	end
	if inst:IsA("SurfaceGui") then
		return inst
	end
	return nil
end

function HubDisplaysLogic.TakeTop(
	entries: { LeaderboardUtil.RawEntry },
	limit: number?
): { LeaderboardUtil.BoardEntry }
	return LeaderboardUtil.TakeTop(entries, limit or HubDisplaysLogic.TOP_N)
end

export type AnchorCheck = {
	Name: string,
	Anchored: boolean,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
	HasSurfaceGui: boolean,
	AdorneeMatches: boolean,
}

function HubDisplaysLogic.ValidateAnchorProps(props: {
	Anchored: boolean?,
	CanCollide: boolean?,
	CanTouch: boolean?,
	CanQuery: boolean?,
}): boolean
	return props.Anchored == true
		and props.CanCollide == false
		and props.CanTouch == false
		and props.CanQuery == false
end

function HubDisplaysLogic.PreserveOnRefresh(manualAttr: any): boolean
	return manualAttr == true
end

function HubDisplaysLogic.ExpectedDebugAdornmentCount(debugEnabled: boolean): number
	return if debugEnabled then 3 else 0
end

function HubDisplaysLogic.ServiceStartsOnce(previousStarts: number): number
	if previousStarts <= 0 then
		return 1
	end
	return previousStarts
end

return HubDisplaysLogic
