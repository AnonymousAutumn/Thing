--!strict

--[[
	Stats DisplayManager Module

	Manages leaderboard display frame creation and updates.
	Handles UI frame generation and data population.

	Returns: DisplayManager table with display functions

	Usage:
		local DisplayManager = require(...)
		local frames = DisplayManager.createLeaderboardDisplayFrames(parent, count, colors, duration, prefab)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local Populater = require(assert(script.Parent:WaitForChild("Populater", 10), "Failed to find Populater"))

---------------
-- Constants --
---------------
local TAG = "[DisplayManager]"

-----------
-- Module --
-----------
local DisplayManager = {}

--[[
	Checks if display count is valid

	@param count any - Count to validate
	@return boolean - True if valid
]]
function DisplayManager.isValidDisplayCount(count: any): boolean
	return type(count) == "number" and count > 0
end

--[[
	Checks if UI element is valid

	@param element any - Element to validate
	@return boolean - True if valid
]]
function DisplayManager.isValidUIElement(element: any): boolean
	return element ~= nil and element.Parent ~= nil
end

--[[
	Creates a single display frame

	@param frameIndex number - Index in leaderboard
	@param parentScrollingFrame any - Parent frame
	@param colorConfiguration any - Color config
	@param fadeInDuration number - Fade animation duration
	@param leaderboardPrefab any - Entry prefab
	@return any? - Created frame or nil
]]
function DisplayManager.createSingleDisplayFrame(
	frameIndex: number,
	parentScrollingFrame: any,
	colorConfiguration: any,
	fadeInDuration: number,
	leaderboardPrefab: any
): any?
	local success, frameOrError = pcall(function()
		return Populater.createLeaderboardEntryFrame(
			frameIndex,
			leaderboardPrefab,
			parentScrollingFrame,
			colorConfiguration,
			fadeInDuration
		)
	end)
	if success and frameOrError then
		return frameOrError
	end
	if not success then
		warn(string.format("%s Failed to create leaderboard frame for index %d: %s", TAG, frameIndex, tostring(frameOrError)))
	end
	return nil
end

--[[
	Creates all leaderboard display frames

	@param parentScrollingFrame any - Parent frame
	@param totalDisplayCount number - Total frames to create
	@param colorConfiguration any - Color config
	@param fadeInDuration number - Fade animation duration
	@param leaderboardPrefab any - Entry prefab
	@return {any} - Created frames
]]
function DisplayManager.createLeaderboardDisplayFrames(
	parentScrollingFrame: any,
	totalDisplayCount: number,
	colorConfiguration: any,
	fadeInDuration: number,
	leaderboardPrefab: any
): { any }
	if not DisplayManager.isValidUIElement(parentScrollingFrame) then
		return {}
	end
	if not DisplayManager.isValidDisplayCount(totalDisplayCount) then
		return {}
	end

	local createdDisplayFrames = {}
	for frameIndex = 1, totalDisplayCount do
		local frame = DisplayManager.createSingleDisplayFrame(
			frameIndex,
			parentScrollingFrame,
			colorConfiguration,
			fadeInDuration,
			leaderboardPrefab
		)
		if frame then
			createdDisplayFrames[frameIndex] = frame
		end
	end

	return createdDisplayFrames
end

--[[
	Updates display frames with new data

	@param displayFrameCollection {any} - Frames to update
	@param processedLeaderboardEntries {any} - New data
	@param systemConfiguration any - System config
	@param statisticName string - Leaderboard name
	@return boolean - True if successful
]]
function DisplayManager.updateDisplayFrames(
	displayFrameCollection: { any },
	processedLeaderboardEntries: { any },
	systemConfiguration: any,
	statisticName: string
): boolean
	local success, errorMessage = pcall(function()
		Populater.refreshAllLeaderboardDisplayFrames(displayFrameCollection, processedLeaderboardEntries, systemConfiguration)
	end)
	if not success then
		warn(string.format("%s Failed to update display frames for %s: %s", TAG, statisticName, tostring(errorMessage)))
		return false
	end
	return true
end

return DisplayManager