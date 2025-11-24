--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

---------------
-- Constants --
---------------
local DRAG_DETECTION_RADIUS = 300 -- pixels

-----------
-- Types --
-----------
export type UIElements = {
	sliderFrame: Frame,
	volumeDragHandle: GuiObject,
	volumeDragDetector: any, -- UIDragDetector
	nextTrackButton: GuiButton,
	previousTrackButton: GuiButton,
}

-----------
-- Module --
-----------
local UIEventHandler = {}

-- External dependencies (set by MusicHandler)
UIEventHandler.updateVolumeCallback = nil :: ((number) -> ())? -- Update volume
UIEventHandler.playNextTrackCallback = nil :: (() -> ())? -- Play next track
UIEventHandler.playPreviousTrackCallback = nil :: (() -> ())? -- Play previous track

--[[
	Calculates relative X position (0-1) within the slider frame

	@param sliderFrame Frame - The slider container
	@param inputPosX number - Absolute X position
	@return number - Relative position (0-1)
]]
local function getRelativeX(sliderFrame: Frame, inputPosX: number): number
	local sliderWidth = math.max(sliderFrame.AbsoluteSize.X, 1)
	local relative = (inputPosX - sliderFrame.AbsolutePosition.X) / sliderWidth
	return math.clamp(relative, 0, 1)
end

--[[
	Sets up all UI event connections for the music player

	Connects:
	- Volume slider drag events (DragStart, DragContinue, DragEnd)
	- Next track button
	- Previous track button

	@param uiElements UIElements - UI element references
	@param resourceManager any - ResourceCleanup instance
	@param musicTracks {any} - Music track list (for validation)
]]
function UIEventHandler.setupEventConnections(
	uiElements: UIElements,
	resourceManager: any,
	musicTracks: { any }
): ()
	local dragging = false
	local pseudoRadius = DRAG_DETECTION_RADIUS -- how far from the knob the user can click to start drag

	-- Drag begin
	resourceManager:trackConnection(uiElements.volumeDragDetector.DragStart:Connect(function(inputPos: Vector2)
		local knobX = uiElements.volumeDragHandle.AbsolutePosition.X
		local knobSizeX = uiElements.volumeDragHandle.AbsoluteSize.X

		-- Ignore drags that start too far away from the knob
		if inputPos.X < (knobX - pseudoRadius) or inputPos.X > (knobX + knobSizeX + pseudoRadius) then
			return
		end

		dragging = true
		if UIEventHandler.updateVolumeCallback then
			UIEventHandler.updateVolumeCallback(getRelativeX(uiElements.sliderFrame, inputPos.X))
		end
	end))

	-- Drag continue
	resourceManager:trackConnection(uiElements.volumeDragDetector.DragContinue:Connect(function(inputPos: Vector2)
		if not dragging then
			return
		end
		if UIEventHandler.updateVolumeCallback then
			UIEventHandler.updateVolumeCallback(getRelativeX(uiElements.sliderFrame, inputPos.X))
		end
	end))

	-- Drag end
	resourceManager:trackConnection(uiElements.volumeDragDetector.DragEnd:Connect(function()
		dragging = false
	end))

	-- Next/Previous buttons
	resourceManager:trackConnection(uiElements.nextTrackButton.MouseButton1Click:Connect(function()
		if #musicTracks > 0 and UIEventHandler.playNextTrackCallback then
			UIEventHandler.playNextTrackCallback()
		end
	end))

	resourceManager:trackConnection(uiElements.previousTrackButton.MouseButton1Click:Connect(function()
		if #musicTracks > 0 and UIEventHandler.playPreviousTrackCallback then
			UIEventHandler.playPreviousTrackCallback()
		end
	end))
end

return UIEventHandler