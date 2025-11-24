--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

local ColorStyler = {}

---------------
-- Constants --
---------------
local DEFAULT_EVEN_ROW_COLOR = Color3.fromRGB(50, 50, 50)
local DEFAULT_ODD_ROW_COLOR = Color3.fromRGB(40, 40, 40)
local RANK_STROKE_THICKNESS = 3

-----------
-- Types --
-----------
type ColorConfiguration = {
	BACKGROUNDCOLOR: Color3,
	STROKECOLOR: Color3,
}

local function getFrameChild(frame: Instance, childName: string): Instance?
	return frame:FindFirstChild(childName)
end

function ColorStyler.getRankColor(playerRank: number, rankColorConfiguration: { ColorConfiguration }): ColorConfiguration?
	if type(rankColorConfiguration) ~= "table" then
		return nil
	end
	if playerRank > 0 and playerRank <= #rankColorConfiguration then
		return rankColorConfiguration[playerRank]
	end
	return nil
end

function ColorStyler.getAlternatingRowColor(rankPosition: number): Color3
	return (rankPosition % 2 == 0) and DEFAULT_EVEN_ROW_COLOR or DEFAULT_ODD_ROW_COLOR
end

function ColorStyler.applyStrokeToLabel(label: TextLabel, strokeColor: Color3): ()
	local uiStroke = getFrameChild(label, "UIStroke")
	if ValidationUtils.isValidUIStroke(uiStroke) then
		uiStroke.Thickness = RANK_STROKE_THICKNESS
		uiStroke.Color = strokeColor
	end
end

function ColorStyler.applyStrokeToLabels(labels: { TextLabel }, strokeColor: Color3): ()
	for _, label in labels do
		if ValidationUtils.isValidTextLabel(label) then
			ColorStyler.applyStrokeToLabel(label, strokeColor)
		end
	end
end

return ColorStyler