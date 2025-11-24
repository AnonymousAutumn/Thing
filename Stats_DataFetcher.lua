--!strict

--[[
	Stats DataFetcher Module

	Handles leaderboard data retrieval from OrderedDataStores.
	Provides retry logic and data validation for leaderboard entries.

	Returns: DataFetcher table with data retrieval functions

	Usage:
		local DataFetcher = require(...)
		local success, data = DataFetcher.retrieveLeaderboardData(dataStore, count, config)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local RetryAsync = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("RetryAsync", 10), "Failed to find RetryAsync"))
local ValidationUtils = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("ValidationUtils", 10), "Failed to find ValidationUtils"))
local Populater = require(assert(script.Parent:WaitForChild("Populater", 10), "Failed to find Populater"))

---------------
-- Constants --
---------------
local TAG = "[DataFetcher]"

-----------
-- Module --
-----------
local DataFetcher = {}

--[[
	Extracts user ID from leaderboard entry

	@param leaderboardEntry any - Entry from leaderboard
	@return number? - User ID or nil
]]
function DataFetcher.extractUserId(leaderboardEntry: any): number?
	if not leaderboardEntry or not leaderboardEntry.key then
		return nil
	end

	local userId = tonumber(leaderboardEntry.key)
	if ValidationUtils.isValidUserId(userId) then
		return userId
	end
	return nil
end

--[[
	Prepares top players data for character display

	@param processedLeaderboardEntries {any} - Processed entries
	@param maxCharacterDisplayCount number - Max to display
	@return {[number]: number} - Map of rank to user ID
]]
function DataFetcher.prepareTopPlayersData(processedLeaderboardEntries: { any }, maxCharacterDisplayCount: number): { [number]: number }
	local topPlayersForCharacterDisplay = {}
	for entryIndex = 1, maxCharacterDisplayCount do
		local leaderboardEntry = processedLeaderboardEntries[entryIndex]
		local userId = DataFetcher.extractUserId(leaderboardEntry)
		if userId then
			topPlayersForCharacterDisplay[entryIndex] = userId
		end
	end
	return topPlayersForCharacterDisplay
end

--[[
	Validates leaderboard data pages

	@param dataPages any - Pages from DataStore
	@return boolean - True if valid
]]
function DataFetcher.validateLeaderboardDataPages(dataPages: any): boolean
	if not dataPages then
		return false
	end
	if type(dataPages.GetCurrentPage) ~= "function" then
		return false
	end
	return true
end

--[[
	Retrieves leaderboard data from DataStore

	@param orderedDataStore any - OrderedDataStore instance
	@param maximumEntriesToRetrieve number - Max entries
	@param systemConfiguration any - System config
	@return boolean, any - Success and data/error
]]
function DataFetcher.retrieveLeaderboardData(
	orderedDataStore: any,
	maximumEntriesToRetrieve: number,
	systemConfiguration: any
): (boolean, any)
	local dataRetrievalSuccess, retrievedDataResult = RetryAsync(
		function()
			return orderedDataStore:GetSortedAsync(false, maximumEntriesToRetrieve)
		end,
		systemConfiguration.LEADERBOARD_CONFIG.UPDATE_MAX_ATTEMPTS,
		systemConfiguration.LEADERBOARD_CONFIG.UPDATE_RETRY_PAUSE_CONSTANT,
		systemConfiguration.LEADERBOARD_CONFIG.UPDATE_RETRY_PAUSE_EXPONENT_BASE
	)
	return dataRetrievalSuccess, retrievedDataResult
end

--[[
	Extracts leaderboard entries from pages

	@param leaderboardDataPages any - Data pages
	@param displayCount number - Count to extract
	@return boolean, any - Success and entries/error
]]
function DataFetcher.extractLeaderboardEntries(leaderboardDataPages: any, displayCount: number): (boolean, any)
	local success, processedLeaderboardEntries = pcall(function()
		return Populater.extractLeaderboardDataFromPages(leaderboardDataPages, displayCount)
	end)
	if not success then
		warn(string.format("%s Failed to extract leaderboard entries: %s", TAG, tostring(processedLeaderboardEntries)))
	end
	return success, processedLeaderboardEntries
end

--[[
	Sends top player data to all clients

	@param clientUpdateEvent any - Remote event
	@param topPlayersData {[number]: number} - Top players map
	@param statisticName string - Leaderboard name
]]
function DataFetcher.sendTopPlayerDataToClients(
	clientUpdateEvent: any,
	topPlayersData: { [number]: number },
	statisticName: string
): ()
	local success, errorMessage = pcall(function()
		clientUpdateEvent:FireAllClients(topPlayersData)
	end)
	if not success then
		warn(string.format("%s Failed to fire client update for %s: %s", TAG, statisticName, tostring(errorMessage)))
	end
end

return DataFetcher