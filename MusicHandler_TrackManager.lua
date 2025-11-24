--!strict

--[[
	Music Handler - Track Manager

	Manages music track playback, sound instance creation, track validation,
	and sound event handling. Validates track approval before playback and
	handles automatic track progression.

	Returns: TrackManager (module table with track management functions)

	Usage:
		TrackManager.createSound(trackData, parent, volume, maxVolume)
		TrackManager.setupSoundEvents(sound, trackData, state, playFunction)
		TrackManager.isApprovedSound(trackData, testParent)
		TrackManager.stopCurrentTrack(state)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules in ReplicatedStorage")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

---------------
-- Constants --
---------------
local SOUND_LOAD_TIMEOUT = 5 -- seconds
local SOUND_LOAD_POLL_INTERVAL = 0.1 -- seconds

-----------
-- Types --
-----------
export type MusicTrack = {
	Id: number,
	Name: string,
}

export type PlaybackState = {
	currentAudioTrack: Sound?,
	currentTrackIndex: number,
	musicTracks: { MusicTrack },
	soundResourceManager: any, -- ResourceCleanup instance
	volumeState: any, -- VolumeState from VolumeControl
}

-----------
-- Module --
-----------
local TrackManager = {}

-- External dependencies (set by MusicHandler)
TrackManager.setBufferingCallback = nil :: ((boolean) -> ())? -- enable/disable drag detector
TrackManager.updateTrackNameCallback = nil :: ((string) -> ())? -- update track name label
TrackManager.animateScrollCallback = nil :: (() -> ())? -- trigger scroll animation

--[[
	Disconnects all sound-related event connections

	@param soundResourceManager any - ResourceCleanup instance
]]
function TrackManager.disconnectSoundConnections(soundResourceManager: any): ()
	soundResourceManager:cleanupConnections()
end

--[[
	Stops the current track and cleans up resources

	@param state PlaybackState - Current playback state
]]
function TrackManager.stopCurrentTrack(state: PlaybackState): ()
	TrackManager.disconnectSoundConnections(state.soundResourceManager)
	if state.currentAudioTrack then
		state.currentAudioTrack:Stop()
		state.currentAudioTrack:Destroy()
		state.currentAudioTrack = nil
	end
end

--[[
	Validates track index is within bounds

	@param index number - Index to validate
	@param musicTracks {MusicTrack} - Track list
	@return boolean - True if valid
]]
function TrackManager.isValidTrackIndex(index: number, musicTracks: { MusicTrack }): boolean
	return #musicTracks > 0 and index >= 1 and index <= #musicTracks
end

--[[
	Gets the next track index (wraps around)

	@param currentIndex number - Current track index
	@param musicTracks {MusicTrack} - Track list
	@return number - Next track index
]]
function TrackManager.getNextTrackIndex(currentIndex: number, musicTracks: { MusicTrack }): number
	if #musicTracks == 0 then
		return 1
	end
	return (currentIndex % #musicTracks) + 1
end

--[[
	Gets the previous track index (wraps around)

	@param currentIndex number - Current track index
	@param musicTracks {MusicTrack} - Track list
	@return number - Previous track index
]]
function TrackManager.getPreviousTrackIndex(currentIndex: number, musicTracks: { MusicTrack }): number
	if #musicTracks == 0 then
		return 1
	end
	return ((currentIndex - 2) % #musicTracks) + 1
end

--[[
	Creates a Sound instance for a track

	@param trackData MusicTrack - Track data
	@param parentInstance Instance - Parent for the sound
	@param currentVolumeNormalized number - Initial volume (0-1)
	@param maxVolume number - Maximum volume scale
	@return Sound - The created sound
]]
function TrackManager.createSound(
	trackData: MusicTrack,
	parentInstance: Instance,
	currentVolumeNormalized: number,
	maxVolume: number
): Sound
	local newSound = Instance.new("Sound")
	newSound.SoundId = `rbxassetid://{trackData.Id}`
	newSound.Name = trackData.Name

	-- Start at current volume (absolute)
	newSound.Volume = currentVolumeNormalized * maxVolume
	newSound.Parent = parentInstance
	return newSound
end

--[[
	Sets UI to buffering state

	@param bufferingText string - Text to display
]]
function TrackManager.setBufferingState(bufferingText: string): ()
	if TrackManager.setBufferingCallback then
		TrackManager.setBufferingCallback(false) -- disable drag
	end
	if TrackManager.updateTrackNameCallback then
		TrackManager.updateTrackNameCallback(bufferingText)
	end
	if TrackManager.animateScrollCallback then
		TrackManager.animateScrollCallback()
	end
end

--[[
	Handles sound loaded event

	@param trackData MusicTrack - Track data
]]
function TrackManager.onSoundLoaded(sound: Sound, trackData: MusicTrack): ()
	sound:Play()
	if TrackManager.setBufferingCallback then
		TrackManager.setBufferingCallback(true) -- enable drag
	end
	if TrackManager.updateTrackNameCallback then
		TrackManager.updateTrackNameCallback(trackData.Name)
	end
	if TrackManager.animateScrollCallback then
		TrackManager.animateScrollCallback()
	end
end

--[[
	Sets up Sound event connections (Loaded, Ended)

	@param sound Sound - Sound instance
	@param trackData MusicTrack - Track data
	@param state PlaybackState - Playback state
	@param playTrackAtIndexFn function - Function to play next track
]]
function TrackManager.setupSoundEvents(
	sound: Sound,
	trackData: MusicTrack,
	state: PlaybackState,
	playTrackAtIndexFn: (number) -> ()
): ()
	local loadedConnection = sound.Loaded:Connect(function()
		TrackManager.onSoundLoaded(sound, trackData)
	end)

	local endedConnection
	endedConnection = sound.Ended:Connect(function()
		-- Disconnect per-sound connections to avoid leaks
		if loadedConnection.Connected then
			loadedConnection:Disconnect()
		end
		if endedConnection and endedConnection.Connected then
			endedConnection:Disconnect()
		end

		TrackManager.stopCurrentTrack(state)
		local nextIndex = TrackManager.getNextTrackIndex(state.currentTrackIndex, state.musicTracks)
		playTrackAtIndexFn(nextIndex)
	end)

	state.soundResourceManager:trackConnection(loadedConnection)
	state.soundResourceManager:trackConnection(endedConnection)
end

--[[
	Validates if a sound asset is approved and loads properly

	Creates a temporary Sound instance to test if the asset loads.
	This prevents playing broken or unapproved audio.

	@param trackData MusicTrack - Track to validate
	@param testParent Instance - Parent for test sound
	@return boolean - True if sound is valid
]]
function TrackManager.isApprovedSound(trackData: MusicTrack, testParent: Instance): boolean
	local testSound = Instance.new("Sound")
	testSound.SoundId = `rbxassetid://{trackData.Id}`
	testSound.Parent = testParent

	local soundLoaded = false
	local loadConnection

	loadConnection = testSound.Loaded:Connect(function()
		soundLoaded = true
		loadConnection:Disconnect()
	end)

	-- Wait a short period for the sound to load
	local timeout = SOUND_LOAD_TIMEOUT
	local startTime = tick()
	while not soundLoaded and tick() - startTime < timeout do
		task.wait(SOUND_LOAD_POLL_INTERVAL)
	end

	testSound:Destroy()

	if soundLoaded then
		return true
	else
		return false
	end
end

return TrackManager