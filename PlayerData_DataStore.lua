--!strict

--[[
	PlayerData_DataStore - DataStore operations with retry logic and validation

	What it does:
	- Saves player statistics to DataStore using UpdateAsync (prevents data loss)
	- Loads player statistics from DataStore with retry and fallback to defaults
	- Validates and sanitizes all data from DataStore (prevents corrupt data)
	- Implements exponential backoff retry logic for DataStore operations
	- Uses UpdateAsync merge strategy to prevent stat rollback exploits
	- Handles concurrent writes safely (multi-server scenarios)

	Returns: Module table with functions:
	- savePlayerStatistics(userId, data) - Saves statistics (returns success boolean)
	- loadPlayerStatistics(userId) - Loads statistics (returns PlayerStatistics)

	Usage:
	local DataStore = require(script.DataStore)
	local success = DataStore.savePlayerStatistics(userId, statsData)
	local loadedData = DataStore.loadPlayerStatistics(userId)
]]

--------------
-- Services --
--------------

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Configuration folder not found in ReplicatedStorage")

local DataStoreWrapper = require(modules.Wrappers.DataStore)
local ValidationUtils = require(modules.Utilities.ValidationUtils)
local gameConfig = require(configuration.GameConfig)

-----------
-- Types --
-----------

export type PlayerStatistics = {
	Donated: number,
	Raised: number,
	Wins: number,
}

---------------
-- Constants --
---------------

local TAG = "[PlayerData.DataStore]"

local DEFAULT_PLAYER_STATISTICS: PlayerStatistics = {
	Donated = 0,
	Raised = 0,
	Wins = 0,
}

local DATASTORE_OPERATION_RETRY_ATTEMPTS: number = 3
local DATASTORE_OPERATION_RETRY_DELAY_SECONDS: number = 1
local DATASTORE_OPERATION_MAX_BACKOFF_SECONDS: number = 8

local playerStatisticsDataStore: DataStore = DataStoreService:GetDataStore(gameConfig.DATASTORE.STATS_KEY)

-----------
-- Module --
-----------
local DataStore = {}

---------------
-- Logging --
---------------
local function log(message: string, ...: any): ()
	print(string.format(TAG .. " " .. message, ...))
end

local function warnlog(message: string, ...: any): ()
	warn(string.format(TAG .. " " .. message, ...))
end

-----------------------
-- Data Validation --
-----------------------
local function validateAndSanitizeStatisticsData(data: any): PlayerStatistics
	if type(data) ~= "table" then
		return table.clone(DEFAULT_PLAYER_STATISTICS)
	end

	local sanitizedData: PlayerStatistics = {} :: PlayerStatistics

	for key, defaultValue in DEFAULT_PLAYER_STATISTICS do
		local value = data[key]
		if ValidationUtils.isValidNumber(value) and value >= 0 then
			sanitizedData[key] = value
		else
			sanitizedData[key] = defaultValue
		end
	end

	return sanitizedData
end

-------------------------
-- DataStore Operations --
-------------------------
function DataStore.savePlayerStatistics(playerUserId: string, playerStatisticsData: PlayerStatistics): boolean
	assert(typeof(playerUserId) == "string" and #playerUserId > 0, "playerUserId must be a non-empty string")
	assert(typeof(playerStatisticsData) == "table", "playerStatisticsData must be a table")

	-- SECURITY: Use UpdateAsync to prevent data loss from concurrent writes
	-- SetAsync would overwrite all data; UpdateAsync merges changes safely
	local result = DataStoreWrapper.updateAsync(
		playerStatisticsDataStore,
		playerUserId,
		function(oldData: any): PlayerStatistics
			-- CRITICAL: No yielding allowed in this callback (no task.wait, no RemoteEvents)

			-- If no existing data, this is a new player
			if oldData == nil then
				return playerStatisticsData
			end

			-- Validate and sanitize existing data
			local existingData = validateAndSanitizeStatisticsData(oldData)

			-- Merge new data into existing data
			-- This preserves stats that might have been updated on other servers
			for key, newValue in playerStatisticsData do
				if ValidationUtils.isValidNumber(newValue) and newValue >= 0 then
					-- Keep the higher value to prevent stat rollback exploits
					existingData[key] = math.max(existingData[key] or 0, newValue)
				end
			end

			return existingData
		end,
		{
			maxRetries = DATASTORE_OPERATION_RETRY_ATTEMPTS,
			baseDelay = DATASTORE_OPERATION_RETRY_DELAY_SECONDS,
			maxBackoff = DATASTORE_OPERATION_MAX_BACKOFF_SECONDS
		}
	)

	if not result.success then
		warnlog("Failed to save statistics data for user %s: %s", playerUserId, result.error or "unknown")
		return false
	end

	return true
end

function DataStore.loadPlayerStatistics(playerUserId: string): PlayerStatistics
	assert(typeof(playerUserId) == "string" and #playerUserId > 0, "playerUserId must be a non-empty string")

	local result = DataStoreWrapper.getAsync(
		playerStatisticsDataStore,
		playerUserId,
		{
			maxRetries = DATASTORE_OPERATION_RETRY_ATTEMPTS,
			baseDelay = DATASTORE_OPERATION_RETRY_DELAY_SECONDS,
			maxBackoff = DATASTORE_OPERATION_MAX_BACKOFF_SECONDS
		}
	)

	local sanitizedData: PlayerStatistics
	if result.success and result.data then
		sanitizedData = validateAndSanitizeStatisticsData(result.data)
	else
		sanitizedData = table.clone(DEFAULT_PLAYER_STATISTICS)
	end

	return sanitizedData
end

return DataStore