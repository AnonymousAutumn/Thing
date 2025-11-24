--!strict

---------------
-- Constants --
---------------
local RGB_MULTIPLIER: number = 255

-----------
-- Types --
-----------
export type GradientColorKeypoint = {
	Time: number,
	R: number,
	G: number,
	B: number,
}

-----------
-- Module --
-----------
local GradientProcessor = {}

---------------------
-- Validation Utils --
---------------------
function GradientProcessor.isValidUIGradient(instance: any): boolean
	if typeof(instance) ~= "Instance" or not instance:IsA("UIGradient") then
		return false
	end

	local colorSequence: ColorSequence? = instance.Color
	return colorSequence ~= nil
		and colorSequence.Keypoints ~= nil
		and #colorSequence.Keypoints > 0
end

-----------------------
-- Color Conversion --
-----------------------
local function color3ToRGB(color: Color3): (number, number, number)
	return math.floor(color.R * RGB_MULTIPLIER),
	math.floor(color.G * RGB_MULTIPLIER),
	math.floor(color.B * RGB_MULTIPLIER)
end

local function createColoredCharacter(character: string, color: Color3): string
	local r, g, b = color3ToRGB(color)
	return string.format("<font color='rgb(%d,%d,%d)'>%s</font>", r, g, b, character)
end

--------------------------
-- Gradient Processing --
--------------------------
local function extractColorKeypoints(gradient: UIGradient): {GradientColorKeypoint}?
	local keypoints: {ColorSequenceKeypoint} = gradient.Color.Keypoints
	if #keypoints == 0 then
		return nil
	end

	local extractedKeypoints: {GradientColorKeypoint} = table.create(#keypoints)

	for index, keypoint in keypoints do
		extractedKeypoints[index] = {
			Time = keypoint.Time,
			R = keypoint.Value.R,
			G = keypoint.Value.G,
			B = keypoint.Value.B,
		}
	end

	-- Sort by time to ensure proper interpolation
	table.sort(extractedKeypoints, function(firstKeypoint, secondKeypoint)
		return firstKeypoint.Time < secondKeypoint.Time
	end)

	return extractedKeypoints
end

local function interpolateGradientColor(
	keypoints: {GradientColorKeypoint},
	time: number
): Color3
	local keypointCount: number = #keypoints

	-- Single keypoint - return that color
	if keypointCount == 1 then
		local keypoint: GradientColorKeypoint = keypoints[1]
		return Color3.new(keypoint.R, keypoint.G, keypoint.B)
	end

	local firstKeypoint: GradientColorKeypoint = keypoints[1]
	local lastKeypoint: GradientColorKeypoint = keypoints[keypointCount]

	-- Before first keypoint
	if time <= firstKeypoint.Time then
		return Color3.new(firstKeypoint.R, firstKeypoint.G, firstKeypoint.B)
	end

	-- After last keypoint
	if time >= lastKeypoint.Time then
		return Color3.new(lastKeypoint.R, lastKeypoint.G, lastKeypoint.B)
	end

	-- Find surrounding keypoints and interpolate
	for i = 1, keypointCount - 1 do
		local currentKeypoint: GradientColorKeypoint = keypoints[i]
		local nextKeypoint: GradientColorKeypoint = keypoints[i + 1]

		if time >= currentKeypoint.Time and time <= nextKeypoint.Time then
			local alpha: number = (time - currentKeypoint.Time) / (nextKeypoint.Time - currentKeypoint.Time)
			local currentColor: Color3 = Color3.new(currentKeypoint.R, currentKeypoint.G, currentKeypoint.B)
			local nextColor: Color3 = Color3.new(nextKeypoint.R, nextKeypoint.G, nextKeypoint.B)

			return currentColor:Lerp(nextColor, alpha)
		end
	end

	-- Fallback to last keypoint
	return Color3.new(lastKeypoint.R, lastKeypoint.G, lastKeypoint.B)
end

local function applyGradientToText(text: string, keypoints: {GradientColorKeypoint}): string
	local textLength: number = #text

	if textLength <= 1 then
		return text
	end

	local characters: {string} = table.create(textLength)
	local lengthMinusOne: number = textLength - 1

	for i = 1, textLength do
		local time: number = (i - 1) / lengthMinusOne
		local color: Color3 = interpolateGradientColor(keypoints, time)
		local character: string = string.sub(text, i, i)

		characters[i] = createColoredCharacter(character, color)
	end

	return table.concat(characters)
end

------------------
-- Public API --
------------------
function GradientProcessor.processGradientText(
	gradient: UIGradient?,
	text: string,
	stripRichTextFunc: (string) -> string
): string
	if not GradientProcessor.isValidUIGradient(gradient) then
		return text
	end

	local keypoints: {GradientColorKeypoint}? = extractColorKeypoints(gradient :: UIGradient)
	if not keypoints or #keypoints == 0 then
		return text
	end

	local plainText: string = stripRichTextFunc(text)
	if #plainText == 0 then
		return text
	end

	return applyGradientToText(plainText, keypoints)
end

return GradientProcessor