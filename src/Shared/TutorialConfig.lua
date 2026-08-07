--!strict
-- Configuration du tutoriel d'accueil (textes, seuils, récompenses).
-- Aucune magie numérique / texte dans la logique service/client.

local TutorialConfig = {}

TutorialConfig.Enabled = true
TutorialConfig.Version = 1
TutorialConfig.AttributeName = "TutorialStep" -- attribut miroir optionnel (debug / UI)

-- Remote payload kinds
TutorialConfig.PayloadKind = table.freeze({
	Show = "Show",
	Progress = "Progress",
	StepComplete = "StepComplete",
	Done = "Done",
})

TutorialConfig.Guide = table.freeze({
	HighlightFill = Color3.fromRGB(90, 220, 255),
	HighlightOutline = Color3.fromRGB(255, 230, 90),
	HighlightFillTransparency = 0.55,
	HighlightOutlineTransparency = 0.15,
	BillboardStudsOffset = Vector3.new(0, 5.5, 0),
	BillboardSize = UDim2.fromOffset(48, 48),
	ArrowGlyph = "▼",
	BeamColor0 = Color3.fromRGB(90, 220, 255),
	BeamColor1 = Color3.fromRGB(255, 210, 90),
	BeamWidth0 = 0.35,
	BeamWidth1 = 0.12,
	ScanInterval = 0.35,
	GuideToolId = "Marteau",
})

TutorialConfig.UI = table.freeze({
	ScreenName = "BPW_Tutorial",
	MessageBubbleName = "TutorialBubble",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.12, 0),
	Size = UDim2.new(0.72, 0, 0, 72),
	MaxWidthPx = 420,
	MinWidthPx = 220,
	Background = Color3.fromRGB(18, 28, 44),
	BackgroundTransparency = 0.12,
	Stroke = Color3.fromRGB(90, 220, 255),
	Text = Color3.fromRGB(240, 248, 255),
	ProgressMuted = Color3.fromRGB(160, 180, 200),
	RewardGold = Color3.fromRGB(255, 210, 70),
	Font = Enum.Font.GothamBold,
	FontSize = 18,
	ProgressFontSize = 14,
	CornerRadius = 16,
	TweenIn = 0.22,
	TweenOut = 0.18,
	CelebrateDuration = 0.85,
	SoundId = "rbxassetid://6026984224",
	SoundVolume = 0.35,
})

-- Identifiants d'outil / zones reliés au gameplay existant.
TutorialConfig.Ids = table.freeze({
	HammerToolId = "Marteau",
	DefaultBoardZoneId = "ClassicZone",
})

export type RewardCoins = {
	Kind: "Coins",
	Amount: number,
	Source: string,
}

export type RewardTool = {
	Kind: "Tool",
	ToolId: string,
	-- Si true et que le joueur a déjà l'outil (ramassage), ne pas re-donner.
	SkipIfOwned: boolean,
}

export type Reward = RewardCoins | RewardTool

export type StepDef = {
	Id: number,
	Key: string,
	Message: string,
	-- Condition serveur (voir TutorialService).
	Condition: string,
	-- Paramètres de condition.
	Threshold: number?,
	ToolId: string?,
	Reward: Reward,
	Guide: boolean?,
}

TutorialConfig.Steps = table.freeze({
	{
		Id = 1,
		Key = "PopFirstBubbles",
		Message = "Pète tes 10 premières bulles !",
		Condition = "PopCount",
		Threshold = 10,
		Reward = {
			Kind = "Coins",
			Amount = 25,
			Source = "Tutorial",
		},
		Guide = false,
	},
	{
		Id = 2,
		Key = "SellBubbles",
		Message = "Bravo ! Va vendre tes bulles à gauche.",
		Condition = "BackpackSold",
		Threshold = 1,
		Reward = {
			Kind = "Coins",
			Amount = 50,
			Source = "Tutorial",
		},
		Guide = false,
	},
	{
		Id = 3,
		Key = "FindHammer",
		Message = "Va trouver le marteau !",
		Condition = "AcquireTool",
		ToolId = "Marteau",
		Threshold = 1,
		Reward = {
			Kind = "Tool",
			ToolId = "Marteau",
			SkipIfOwned = true,
		},
		Guide = true,
	},
	{
		Id = 4,
		Key = "UseHammerMulti",
		Message = "Appuie pour crever plusieurs bulles d'un coup !",
		Condition = "ToolMultiPop",
		ToolId = "Marteau",
		Threshold = 2, -- au moins 2 bulles en une activation marteau
		Reward = {
			Kind = "Coins",
			Amount = 100,
			Source = "Tutorial",
		},
		Guide = false,
	},
} :: { StepDef })

function TutorialConfig.GetStep(stepId: number): StepDef?
	for _, step in ipairs(TutorialConfig.Steps) do
		if step.Id == stepId then
			return step
		end
	end
	return nil
end

function TutorialConfig.FirstStepId(): number
	local first = TutorialConfig.Steps[1]
	return if first then first.Id else 1
end

function TutorialConfig.LastStepId(): number
	local last = TutorialConfig.Steps[#TutorialConfig.Steps]
	return if last then last.Id else 1
end

function TutorialConfig.NextStepId(stepId: number): number?
	local found = false
	for _, step in ipairs(TutorialConfig.Steps) do
		if found then
			return step.Id
		end
		if step.Id == stepId then
			found = true
		end
	end
	return nil
end

return TutorialConfig
