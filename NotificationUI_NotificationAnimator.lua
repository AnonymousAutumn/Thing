--!strict

--------------
-- Services --
--------------
local TweenService = game:GetService("TweenService")

---------------
-- Constants --
---------------
local ANIMATION_DURATION = {
	STANDARD = 0.3,
	SPECIAL = 0.8, -- For warning/error
}

local TRANSPARENCY = {
	VISIBLE = 0,
	HIDDEN = 1,
	STROKE = 0.25,
}

local POSITION = {
	DEFAULT = UDim2.new(0.5, 0, 0, 0),
	SPECIAL_OFFSET = UDim2.new(0.45, 0, 0, 0), -- For warning/error
}

local SIZE = {
	COLLAPSED = UDim2.new(0, 0, 1, 0),
}

local SPACING_MULTIPLIER = 1.4
local MIN_WIDTH_PADDING = 50

-----------
-- Types --
-----------
export type AnimationConfig = {
	frame: Frame,
	textLabel: TextLabel,
	uiStroke: UIStroke?,
	notificationType: string,
	typeColor: Color3?,
}

-----------
-- Module --
-----------
local NotificationAnimator = {}

--[[
	Creates a tween with standard settings

	@param instance Instance - Object to animate
	@param properties table - Properties to tween
	@param duration number - Animation duration
	@return Tween
]]
local function createTween(instance: Instance, properties: { [string]: any }, duration: number): Tween
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, tweenInfo, properties)
	tween:Play()
	return tween
end

--[[
	Calculates position for notification in stack

	@param index number - Position in queue (1-based)
	@param totalCount number - Total notifications
	@return UDim2 - Calculated position
]]
function NotificationAnimator.calculatePosition(index: number, totalCount: number): UDim2
	local yPosition = -(totalCount - index) * SPACING_MULTIPLIER
	return UDim2.new(0.5, 0, yPosition, 0)
end

--[[
	Calculates width based on text bounds

	@param textLabel TextLabel - Text label to measure
	@return number - Target width
]]
function NotificationAnimator.calculateWidth(textLabel: TextLabel): number
	return math.max(textLabel.TextBounds.X + MIN_WIDTH_PADDING, MIN_WIDTH_PADDING)
end

--[[
	Sets initial transparency for new notification

	@param textLabel TextLabel - Text label
	@param uiStroke UIStroke? - Optional stroke
]]
local function setInitialTransparency(textLabel: TextLabel, uiStroke: UIStroke?): ()
	textLabel.TextTransparency = TRANSPARENCY.HIDDEN
	if uiStroke then
		uiStroke.Transparency = TRANSPARENCY.HIDDEN
	end
end

--[[
	Animates frame expansion

	@param frame Frame - Frame to expand
	@param targetWidth number - Target width
]]
local function animateExpansion(frame: Frame, targetWidth: number): ()
	frame:TweenSize(
		UDim2.new(0, targetWidth, 1, 0),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quad,
		ANIMATION_DURATION.STANDARD,
		true
	)
end

--[[
	Animates text fade in

	@param textLabel TextLabel - Text to fade in
]]
local function animateTextFadeIn(textLabel: TextLabel): ()
	createTween(textLabel, {
		TextTransparency = TRANSPARENCY.VISIBLE,
		TextStrokeTransparency = TRANSPARENCY.VISIBLE,
	}, ANIMATION_DURATION.STANDARD)
end

--[[
	Animates stroke fade in

	@param uiStroke UIStroke - Stroke to fade in
]]
local function animateStrokeFadeIn(uiStroke: UIStroke): ()
	createTween(uiStroke, { Transparency = TRANSPARENCY.STROKE }, ANIMATION_DURATION.STANDARD)
end

--[[
	Handles special animation for warnings/errors

	@param frame Frame - Frame to animate
	@param uiStroke UIStroke? - Optional stroke
	@param typeColor Color3 - Type color
]]
local function applySpecialAnimation(frame: Frame, uiStroke: UIStroke?, typeColor: Color3): ()
	frame.Position = POSITION.SPECIAL_OFFSET

	frame:TweenPosition(
		POSITION.DEFAULT,
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Elastic,
		ANIMATION_DURATION.SPECIAL,
		true
	)

	if uiStroke then
		uiStroke.Color = typeColor
	end
end

--[[
	Animates notification entry

	@param config AnimationConfig - Animation configuration
]]
function NotificationAnimator.animateEntry(config: AnimationConfig): ()
	setInitialTransparency(config.textLabel, config.uiStroke)

	local targetWidth = NotificationAnimator.calculateWidth(config.textLabel)
	config.frame.Size = UDim2.new(0, targetWidth - MIN_WIDTH_PADDING, 1, 0)

	animateExpansion(config.frame, targetWidth)
	animateTextFadeIn(config.textLabel)

	if config.uiStroke then
		animateStrokeFadeIn(config.uiStroke)
	end

	-- Apply special animation for warnings/errors
	if config.notificationType ~= "Success" and config.typeColor then
		applySpecialAnimation(config.frame, config.uiStroke, config.typeColor)
	end
end

--[[
	Animates frame collapse

	@param frame Frame - Frame to collapse
]]
local function animateCollapse(frame: Frame): ()
	frame:TweenSize(
		SIZE.COLLAPSED,
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quad,
		ANIMATION_DURATION.STANDARD,
		true
	)
end

--[[
	Animates text fade out

	@param textLabel TextLabel - Text to fade out
]]
local function animateTextFadeOut(textLabel: TextLabel): ()
	createTween(textLabel, {
		TextTransparency = TRANSPARENCY.HIDDEN,
		TextStrokeTransparency = TRANSPARENCY.HIDDEN,
	}, ANIMATION_DURATION.STANDARD)
end

--[[
	Animates notification exit

	@param frame Frame - Frame to animate out
	@param textLabel TextLabel - Text label
]]
function NotificationAnimator.animateExit(frame: Frame, textLabel: TextLabel): ()
	animateCollapse(frame)
	animateTextFadeOut(textLabel)
end

--[[
	Animates position change for notification repositioning

	@param frame Frame - Frame to reposition
	@param newPosition UDim2 - Target position
]]
function NotificationAnimator.animateReposition(frame: Frame, newPosition: UDim2): ()
	frame:TweenPosition(
		newPosition,
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quad,
		ANIMATION_DURATION.STANDARD,
		true
	)
end

--[[
	Gets animation duration for timing calculations

	@return number - Standard animation duration
]]
function NotificationAnimator.getStandardDuration(): number
	return ANIMATION_DURATION.STANDARD
end

return NotificationAnimator