--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-------------------
-- Configuration --
-------------------
local MAX_VOLUME = 0.5 -- Maximum allowed volume (0-1)

local MUSIC_PLAYER_CONFIG = {
	DEFAULT_VOLUME = 0.25, -- Initial volume (0-1). Slider is DEFAULT_VOLUME/MAX_VOLUME initially.
	SCROLL_SPEED = 35,
	SCROLL_RESET_DELAY = 1,
	SCROLL_INITIAL_DELAY = 2,
	BUFFERING_TEXT = "Buffering...",
}

-----------
-- Types --
-----------
type MusicTrack = {
	Id: number,
	Name: string,
}

type ScrollState = {
	tween: Tween?,
	thread: thread?,
}

type VolumeState = {
	currentVolumeNormalized: number,
	maxVolume: number,
}

type PlaybackState = {
	currentAudioTrack: Sound?,
	currentTrackIndex: number,
	musicTracks: { MusicTrack },
	soundResourceManager: any,
	volumeState: VolumeState,
}

----------------
-- References --
----------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local MusicLibrary = require(Configuration.MusicLibrary)

-- Submodules
local ScrollAnimator = require(script.ScrollAnimator)
local VolumeControl = require(script.VolumeControl)
local TrackManager = require(script.TrackManager)
local UIEventHandler = require(script.UIEventHandler)

local localPlayer = Players.LocalPlayer

local musicPlayerInterface = script.Parent:WaitForChild("MusicFrame")
local nextTrackButton = musicPlayerInterface:WaitForChild("NextButton") :: GuiButton
local previousTrackButton = musicPlayerInterface:WaitForChild("PreviousButton") :: GuiButton
local trackFrame = musicPlayerInterface:WaitForChild("TrackFrame") :: Frame
local trackNameLabel = trackFrame:WaitForChild("TextLabel") :: TextLabel
local sliderFrame = musicPlayerInterface:WaitForChild("SliderFrame") :: Frame
local volumeFill = sliderFrame:WaitForChild("Fill") :: Frame
local volumeDragHandle = sliderFrame:WaitForChild("DragButton") :: GuiObject
local volumeDragDetector = sliderFrame:WaitForChild("UIDragDetector") -- UIDragDetector

---------------
-- Variables --
---------------
local musicTracks: { MusicTrack } = MusicLibrary

local scrollState: ScrollState = {
	tween = nil,
	thread = nil,
}

local volumeState: VolumeState = {
	currentVolumeNormalized = MUSIC_PLAYER_CONFIG.DEFAULT_VOLUME / MAX_VOLUME,
	maxVolume = MAX_VOLUME,
}

local playbackState: PlaybackState = {
	currentAudioTrack = nil,
	currentTrackIndex = 0,
	musicTracks = musicTracks,
	soundResourceManager = ResourceCleanup.new(),
	volumeState = volumeState,
}

-- UI-wide connections (buttons/drag). Disconnected on cleanup only.
local uiResourceManager = ResourceCleanup.new()

-----------------------
-- Wrapper Functions --
-----------------------
local function animateTrackNameScroll(): ()
	ScrollAnimator.animateTrackNameScroll(trackNameLabel, trackFrame, scrollState, MUSIC_PLAYER_CONFIG)
end

local function updateVolume(newVolumeNormalized: number): ()
	VolumeControl.updateVolume(
		volumeState,
		playbackState.currentAudioTrack,
		volumeFill,
		volumeDragHandle,
		newVolumeNormalized
	)
end

-----------------------
-- Playback Control --
-----------------------

--[[
	Plays a track at the specified index in the playlist

	Automatically skips to the next track if the current track fails to load.
	This prevents the music player from getting stuck on broken tracks.

	@param targetIndex number - Index of the track to play (1-based)
]]
function playTrackAtIndex(targetIndex: number): ()
	if #musicTracks == 0 then
		warn("No music tracks available")
		return
	end

	targetIndex = math.clamp(targetIndex, 1, #musicTracks)
	playbackState.currentTrackIndex = targetIndex
	local trackData = musicTracks[targetIndex]

	-- Stop current track + UI setup
	TrackManager.stopCurrentTrack(playbackState)
	TrackManager.setBufferingState(MUSIC_PLAYER_CONFIG.BUFFERING_TEXT)
	ScrollAnimator.cleanupScrollAnimations(scrollState)

	-- If the track is invalid, skip to the next one
	if not TrackManager.isApprovedSound(trackData, script) then
		warn(("Skipping invalid sound: %s (%d)"):format(trackData.Name, trackData.Id))
		local nextIndex = TrackManager.getNextTrackIndex(playbackState.currentTrackIndex, musicTracks)
		playTrackAtIndex(nextIndex)
		return
	end

	-- Sound is valid – proceed
	local newSound = TrackManager.createSound(
		trackData,
		musicPlayerInterface,
		volumeState.currentVolumeNormalized,
		volumeState.maxVolume
	)
	TrackManager.setupSoundEvents(newSound, trackData, playbackState, playTrackAtIndex)
	playbackState.currentAudioTrack = newSound
end

local function playRandomTrack(): ()
	if #musicTracks == 0 then
		warn("No music tracks available")
		return
	end

	local randomIndex = math.random(1, #musicTracks)
	playTrackAtIndex(randomIndex)
end

local function playNextTrack(): ()
	local nextIndex = TrackManager.getNextTrackIndex(playbackState.currentTrackIndex, musicTracks)
	playTrackAtIndex(nextIndex)
end

local function playPreviousTrack(): ()
	local prevIndex = TrackManager.getPreviousTrackIndex(playbackState.currentTrackIndex, musicTracks)
	playTrackAtIndex(prevIndex)
end

--------------------
-- UI Event Setup --
--------------------

-- Wire up TrackManager callbacks
TrackManager.setBufferingCallback = function(enabled: boolean)
	volumeDragDetector.Enabled = enabled
end

TrackManager.updateTrackNameCallback = function(text: string)
	trackNameLabel.Text = text
end

TrackManager.animateScrollCallback = animateTrackNameScroll

-- Wire up UIEventHandler callbacks
UIEventHandler.updateVolumeCallback = updateVolume
UIEventHandler.playNextTrackCallback = playNextTrack
UIEventHandler.playPreviousTrackCallback = playPreviousTrack

local function setupEventConnections(): ()
	local uiElements = {
		sliderFrame = sliderFrame,
		volumeDragHandle = volumeDragHandle,
		volumeDragDetector = volumeDragDetector,
		nextTrackButton = nextTrackButton,
		previousTrackButton = previousTrackButton,
	}

	UIEventHandler.setupEventConnections(uiElements, uiResourceManager, musicTracks)
end

-------------
-- Cleanup --
-------------
local function cleanup(): ()
	uiResourceManager:cleanupAll()
	TrackManager.disconnectSoundConnections(playbackState.soundResourceManager)
	ScrollAnimator.cleanupScrollAnimations(scrollState)
	TrackManager.stopCurrentTrack(playbackState)
end

local function waitForPlayerLoaded(): ()
	while not localPlayer:GetAttribute("Loaded") do
		task.wait()
	end
	localPlayer:SetAttribute("Loaded", nil)
end

--------------------
-- Initialization --
--------------------
waitForPlayerLoaded()
VolumeControl.initializeDefaults(volumeFill, volumeDragHandle, volumeState.currentVolumeNormalized)
setupEventConnections()
playRandomTrack()

musicPlayerInterface.AncestryChanged:Connect(function()
	if not musicPlayerInterface.Parent then
		cleanup()
	end
end)