--!strict

--[[
	PlayerData_StatisticsAPI - High-level API for player statistic operations

	What it does:
	- Provides high-level functions for statistic updates (increment, set, get)
	- Manages cache-first data access with DataStore fallback
	- Implements debounced save system (15 second delay)
	- Coordinates UI updates and cross-server message publishing
	- Validates all inputs (userId, statistic name, values)
	- Uses dependency injection for DataCache, DataStore, CrossServerMessaging

	Returns: Module table with functions:
	- updatePlayerStatistic(userId, stat, amount, isAbsolute, isRemote?) - Main update function
	- incrementPlayerStatistic(userId, stat, amount, isRemote?) - Increments stat
	- setPlayerStatisticAbsoluteValue(userId, stat, value, isRemote?) - Sets stat
	- getPlayerStatisticValue(userId, stat) - Gets stat value
	- setDataCacheModule(module) / setDataStoreModule(module) / setCrossServerMessagingModule(module) - DI

	Usage:
	local StatisticsAPI = require(script.StatisticsAPI)
	StatisticsAPI.setDataCacheModule(DataCache)
	StatisticsAPI.incrementPlayerStatistic(userId, "Donated", 100)
]]

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local ValidationUtils = require(modules.Utilities.ValidationUtils)

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
local TAG = "[PlayerData.StatisticsAPI]"

local DEFAULT_PLAYER_STATISTICS: PlayerStatistics = {
	Donated = 0,
	Raised = 0,
	Wins = 0,
}

local SAVE_DEBOUNCE_SECONDS: number = 15

-----------
-- Module --
-----------
local StatisticsAPI = {}

-- Module dependencies (injected)
local DataCache = nil
local DataStore = nil
local CrossServerMessaging = nil

---------------
-- Logging --
---------------
local function log(message: string, ...: any): ()
	print(string.format(TAG .. " " .. message, ...))
end

local function warnlog(message: string, ...: any): ()
	warn(string.format(TAG .. " " .. message, ...))
end

-------------------
-- Validation --
-------------------
local function isValidStatisticName(statisticName: string): boolean
	return DEFAULT_PLAYER_STATISTICS[statisticName] ~= nil
end

-----------------------
-- Debounced Saving --
-----------------------
local function scheduleDebouncedSave(playerUserId: string): ()
	if DataCache.getSaveDelayHandle(playerUserId) then
		return
	end

	local handle = task.delay(SAVE_DEBOUNCE_SECONDS, function()
		DataCache.setSaveDelayHandle(playerUserId, nil)
		if DataCache.getPendingSaveFlag(playerUserId) then
			local cachedData = DataCache.getCachedData(playerUserId)
			if cachedData then
				local success = DataStore.savePlayerStatistics(playerUserId, cachedData)
				if success then
					DataCache.updateSaveTime(playerUserId)
					DataCache.setPendingSaveFlag(playerUserId, false)
				end
			end
		end
	end)

	DataCache.setSaveDelayHandle(playerUserId)
end

--------------------------
-- Statistics Operations --
--------------------------
function StatisticsAPI.updatePlayerStatistic(
	playerUserId: number | string,
	statisticName: string,
	statisticAmount: number,
	shouldSetAbsoluteValue: boolean,
	isRemoteUpdate: boolean?
): ()
	assert(playerUserId ~= nil, "playerUserId cannot be nil")
	assert(typeof(statisticName) == "string" and #statisticName > 0, "statisticName must be a non-empty string")
	assert(typeof(statisticAmount) == "number", "statisticAmount must be a number")
	assert(typeof(shouldSetAbsoluteValue) == "boolean", "shouldSetAbsoluteValue must be a boolean")

	local playerUserIdString: string = tostring(playerUserId)
	local playerUserIdNumber: number? = tonumber(playerUserId)

	if not ValidationUtils.isValidUserId(playerUserIdNumber) then
		warnlog("Invalid player user ID: %s", tostring(playerUserId))
		return
	end

	if not isValidStatisticName(statisticName) then
		warnlog("Invalid statistic name: %s", tostring(statisticName))
		return
	end

	if not (ValidationUtils.isValidNumber(statisticAmount) and statisticAmount >= 0) then
		warnlog("Invalid statistic amount (must be non-negative): %s", tostring(statisticAmount))
		return
	end

	-- Get or load player statistics
	local playerStatisticsData: PlayerStatistics = DataCache.getCachedData(playerUserIdString)
	if not playerStatisticsData then
		playerStatisticsData = DataStore.loadPlayerStatistics(playerUserIdString)
		DataCache.setCachedData(playerUserIdString, playerStatisticsData)
	end

	-- Update the statistic
	if shouldSetAbsoluteValue then
		playerStatisticsData[statisticName] = statisticAmount
	else
		playerStatisticsData[statisticName] = (playerStatisticsData[statisticName] or 0) + statisticAmount
	end

	-- Update cache
	DataCache.setCachedData(playerUserIdString, playerStatisticsData)
	DataCache.setPendingSaveFlag(playerUserIdString, true)

	-- Schedule save if not a remote update
	if not isRemoteUpdate then
		scheduleDebouncedSave(playerUserIdString)
	end

	-- Update UI or publish cross-server message
	local targetPlayerInServer: Player? = Players:GetPlayerByUserId(playerUserIdNumber :: number)
	if targetPlayerInServer then
		CrossServerMessaging.updatePlayerStats(
			targetPlayerInServer,
			statisticName,
			playerStatisticsData[statisticName]
		)
	elseif not isRemoteUpdate then
		CrossServerMessaging.publishUpdate({
			UserId = playerUserIdNumber :: number,
			Stat = statisticName,
			Value = playerStatisticsData[statisticName],
		})
	end
end

function StatisticsAPI.incrementPlayerStatistic(
	playerUserId: number | string,
	statisticName: string,
	incrementAmount: number,
	isRemoteUpdate: boolean?
): ()
	StatisticsAPI.updatePlayerStatistic(
		playerUserId,
		statisticName,
		incrementAmount,
		false,
		isRemoteUpdate
	)
end

function StatisticsAPI.setPlayerStatisticAbsoluteValue(
	playerUserId: number | string,
	statisticName: string,
	absoluteValue: number,
	isRemoteUpdate: boolean?
): ()
	StatisticsAPI.updatePlayerStatistic(
		playerUserId,
		statisticName,
		absoluteValue,
		true,
		isRemoteUpdate
	)
end

function StatisticsAPI.getPlayerStatisticValue(
	playerUserId: number | string,
	statisticName: string
): number
	local playerUserIdString: string = tostring(playerUserId)

	-- Get or load player statistics
	local playerStatisticsData: PlayerStatistics = DataCache.getCachedData(playerUserIdString)
	if not playerStatisticsData then
		playerStatisticsData = DataStore.loadPlayerStatistics(playerUserIdString)
		DataCache.setCachedData(playerUserIdString, playerStatisticsData)
	end

	return playerStatisticsData[statisticName] or 0
end

--------------------------
-- Dependency Injection --
--------------------------
function StatisticsAPI.setDataCacheModule(module: any): ()
	DataCache = module
end

function StatisticsAPI.setDataStoreModule(module: any): ()
	DataStore = module
end

function StatisticsAPI.setCrossServerMessagingModule(module: any): ()
	CrossServerMessaging = module
end

return StatisticsAPI