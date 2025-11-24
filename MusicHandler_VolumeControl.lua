--!strict

-----------
-- Types --
-----------
export type VolumeState = {
	currentVolumeNormalized: number, -- 0-1 normalized volume
	maxVolume: number, -- Maximum allowed volume (0-1)
}

-----------
-- Module --
-----------
local VolumeControl = {}

--[[
	Updates the volume for the current audio track and UI elements

	Takes a normalized volume (0-1) and scales it by the maximum volume.
	Updates the Sound instance volume and syncs the slider UI.

	@param volumeState VolumeState - Current volume state
	@param currentAudioTrack Sound? - The active audio track (if any)
	@param volumeFill Frame - The visual fill bar
	@param volumeDragHandle GuiObject - The draggable slider handle
	@param newVolumeNormalized number - New volume (0-1, will be clamped)
]]
function VolumeControl.updateVolume(
	volumeState: VolumeState,
	currentAudioTrack: Sound?,
	volumeFill: Frame,
	volumeDragHandle: GuiObject,
	newVolumeNormalized: number
): ()
	-- Clamp and store normalized volume (0–1)
	volumeState.currentVolumeNormalized = math.clamp(newVolumeNormalized, 0, 1)

	-- Scale by MAX_VOLUME
	local scaledVolume = volumeState.currentVolumeNormalized * volumeState.maxVolume

	-- Apply to current track (if one exists)
	if currentAudioTrack then
		currentAudioTrack.Volume = scaledVolume
	end

	-- Update UI
	volumeFill.Size = UDim2.new(volumeState.currentVolumeNormalized, 0, 1, 0)
	volumeDragHandle.Position = UDim2.new(volumeState.currentVolumeNormalized, 0, 0.5, 0)
end

--[[
	Initializes volume slider UI to default positions

	@param volumeFill Frame - The visual fill bar
	@param volumeDragHandle GuiObject - The draggable slider handle
	@param currentVolumeNormalized number - Initial volume (0-1)
]]
function VolumeControl.initializeDefaults(
	volumeFill: Frame,
	volumeDragHandle: GuiObject,
	currentVolumeNormalized: number
): ()
	local sliderPosition = math.clamp(currentVolumeNormalized, 0, 1)
	volumeDragHandle.Position = UDim2.new(sliderPosition, 0, 0.5, 0)
	volumeFill.Size = UDim2.new(sliderPosition, 0, 1, 0)
end

return VolumeControl