--!strict

--[[
	Music Handler - Scroll Animator

	Manages scrolling text animations for the music player track name display.
	Handles three display states: buffering (centered), text-fits (left-aligned),
	and overflowing text (scrolling animation).

	Returns: ScrollAnimator (module table with animation functions)

	Usage:
		ScrollAnimator.animateTrackNameScroll(trackLabel, trackFrame, scrollState, config)
		ScrollAnimator.cleanupScrollAnimations(scrollState)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules in ReplicatedStorage")
local TweenHelper = require(Modules.Utilities.TweenHelper)

-----------
-- Types --
-----------
export type ScrollState = {
	tween: Tween?,
	thread: thread?,
}

export type ScrollConfig = {
	SCROLL_SPEED: number,
	SCROLL_RESET_DELAY: number,
	SCROLL_INITIAL_DELAY: number,
	BUFFERING_TEXT: string,
}

-----------
-- Module --
-----------
local ScrollAnimator = {}

--[[
	Cleans up active scroll animations and threads

	@param scrollState ScrollState - The scroll state to clean up
]]
function ScrollAnimator.cleanupScrollAnimations(scrollState: ScrollState): ()
	if scrollState.tween then
		scrollState.tween:Cancel()
		scrollState.tween = nil
	end

	if scrollState.thread then
		task.cancel(scrollState.thread)
		scrollState.thread = nil
	end
end

--[[
	Sets up label for centered display (used for buffering)

	@param trackNameLabel TextLabel - The label to configure
]]
function ScrollAnimator.setupCenteredLabel(trackNameLabel: TextLabel): ()
	trackNameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	trackNameLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	trackNameLabel.Size = UDim2.new(1, 0, 1, 0)
end

--[[
	Sets up label for left-aligned display (used for scrolling)

	@param trackNameLabel TextLabel - The label to configure
]]
function ScrollAnimator.setupLeftAlignedLabel(trackNameLabel: TextLabel): ()
	trackNameLabel.AnchorPoint = Vector2.new(0, 0.5)
	trackNameLabel.Position = UDim2.new(0, 0, 0.5, 0)
end

--[[
	Creates scrolling animation for text that overflows the frame

	@param trackNameLabel TextLabel - The label to animate
	@param scrollState ScrollState - State to store tween/thread
	@param textWidth number - Width of the text
	@param frameWidth number - Width of the container frame
	@param config ScrollConfig - Scroll configuration
]]
function ScrollAnimator.createScrollAnimation(
	trackNameLabel: TextLabel,
	scrollState: ScrollState,
	textWidth: number,
	frameWidth: number,
	config: ScrollConfig
): ()
	trackNameLabel.Size = UDim2.new(0, textWidth, 1, 0)

	local startX = 0
	local endX = -(textWidth - frameWidth)
	local duration = math.abs(endX - startX) / config.SCROLL_SPEED

	scrollState.thread = task.spawn(function()
		while true do
			trackNameLabel.Position = UDim2.new(0, startX, 0.5, 0)

			scrollState.tween = TweenHelper.play(
				trackNameLabel,
				TweenInfo.new(duration, Enum.EasingStyle.Linear),
				{ Position = UDim2.new(0, endX, 0.5, 0) }
			)

			task.wait(config.SCROLL_INITIAL_DELAY)
			scrollState.tween.Completed:Wait()

			task.wait(config.SCROLL_RESET_DELAY)
		end
	end)
end

--[[
	Animates track name label with scrolling if text overflows

	Handles three cases:
	1. Buffering state: Center the text
	2. Text fits: Left-align without scrolling
	3. Text overflows: Scroll animation

	@param trackNameLabel TextLabel - The label to animate
	@param trackFrame Frame - The container frame
	@param scrollState ScrollState - State to store animation data
	@param config ScrollConfig - Scroll configuration
]]
function ScrollAnimator.animateTrackNameScroll(
	trackNameLabel: TextLabel,
	trackFrame: Frame,
	scrollState: ScrollState,
	config: ScrollConfig
): ()
	ScrollAnimator.cleanupScrollAnimations(scrollState)

	-- Handle buffering state with centered text
	if trackNameLabel.Text == config.BUFFERING_TEXT then
		ScrollAnimator.setupCenteredLabel(trackNameLabel)
		return
	end

	ScrollAnimator.setupLeftAlignedLabel(trackNameLabel)
	task.wait() -- allow TextBounds to update

	local textWidth = trackNameLabel.TextBounds.X
	local frameWidth = trackFrame.AbsoluteSize.X

	-- No scrolling needed if text fits within frame
	if textWidth <= frameWidth then
		trackNameLabel.Size = UDim2.new(1, 0, 1, 0)
		return
	end

	-- Create scrolling animation for overflowing text
	ScrollAnimator.createScrollAnimation(trackNameLabel, scrollState, textWidth, frameWidth, config)
end

return ScrollAnimator