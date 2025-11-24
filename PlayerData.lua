--!strict

--[[
	PlayerData - Main coordinator for player statistics and data persistence

	What it does:
	- Manages player statistics (Donated, Raised, Wins) with caching and persistence
	- Coordinates DataStore operations with in-memory cache
	- Implements auto-save system with configurable intervals
	- Integrates cross-server messaging for statistic updates
	- Provides public API for statistic operations (get, set, increment)
	- Handles graceful shutdown with data save

	Returns: Module table with functions:
	- GetOrCreatePlayerStatisticsData(userId) - Loads/creates player stats
	- UpdatePlayerStatisticAndPublishChanges(userId, stat, amount, isAbsolute, isRemote?) - Updates stat
	- IncrementPlayerStatistic(userId, stat, amount, isRemote?) - Increments stat
	- SetPlayerStatisticAbsoluteValue(userId, stat, value, isRemote?) - Sets stat
	- GetPlayerStatisticValue(userId, stat) - Gets stat value
	- CachePlayerStatisticsDataInMemory(userId) - Preloads data to cache
	- RemovePlayerDataFromCacheAndSave(userId) - Saves and removes from cache
	- SaveAllCachedData() - Saves all cached data

	Usage:
	local PlayerData = require(Modules.Managers.PlayerData)
	PlayerData:IncrementPlayerStatistic(player.UserId, "Donated", 100)
	local raised = PlayerData:GetPlayerStatisticValue(player.UserId, "Raised")
]]

--------------
-- Services --

--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")

local ResourceCleanup = require(modules.Wrappers.ResourceCleanup)
local DataCache = assert(script:WaitForChild("DataCache", 10), "DataCache module not found")
local DataStore = assert(script:WaitForChild("DataStore", 10), "DataStore module not found")
local CrossServerMessaging = assert(script:WaitForChild("CrossServerMessaging", 10), "CrossServerMessaging module not found")
local StatisticsAPI = assert(script:WaitForChild("StatisticsAPI", 10), "StatisticsAPI module not found")

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
local TAG = "[PlayerData]"

local AUTO_SAVE_INTERVAL_SECONDS: number = 300
local ENABLE_AUTO_SAVE: boolean = true
local SHUTDOWN_SAVE_WAIT_SECONDS: number = 1

---------------
-- Variables --
---------------
local PlayerStatisticsDataStoreManager = {}

local resourceManager = ResourceCleanup.new()
local autoSaveThread: thread? = nil
local isShuttingDown: boolean = false

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
-- Thread Utils --
-------------------
local function cancelThread(threadHandle: thread?): ()
	if threadHandle and coroutine.status(threadHandle) ~= "dead" then
		task.cancel(threadHandle)
	end
end

---------------
-- Wire Dependencies --
---------------
-- StatisticsAPI depends on DataCache, DataStore, and CrossServerMessaging
StatisticsAPI.setDataCacheModule(DataCache)
StatisticsAPI.setDataStoreModule(DataStore)
StatisticsAPI.setCrossServerMessagingModule(CrossServerMessaging)

-- DataCache needs a callback for saving when entries are removed
DataCache.setRemovalCallback(function(playerUserId: string, data: PlayerStatistics)
	DataStore.savePlayerStatistics(playerUserId, data)
end)

-------------------
-- Auto-Save System --
-------------------
local function performAutoSave(): ()
	if isShuttingDown then
		return
	end

	local saveCount: number = 0
	local failCount: number = 0

	for playerUserId, playerStatisticsData in DataCache.getAllCachedData() do
		local success: boolean = DataStore.savePlayerStatistics(playerUserId, playerStatisticsData)
		if success then
			saveCount += 1
			DataCache.updateSaveTime(playerUserId)
			DataCache.setPendingSaveFlag(playerUserId, false)
		else
			failCount += 1
		end
	end

	if saveCount > 0 or failCount > 0 then
		log("Auto-save completed: %d successful, %d failed", saveCount, failCount)
	end
end

local function startAutoSaveLoop(): ()
	if not ENABLE_AUTO_SAVE or autoSaveThread then
		return
	end

	autoSaveThread = task.spawn(function()
		while not isShuttingDown do
			task.wait(AUTO_SAVE_INTERVAL_SECONDS)
			performAutoSave()
		end
	end)
end

local function stopAutoSaveLoop(): ()
	cancelThread(autoSaveThread)
	autoSaveThread = nil
end

-----------------------
-- Public API --
-----------------------

--- Retrieves or creates player statistics data for a given user ID.
-- @param playerUserId number|string
-- @return PlayerStatistics
function PlayerStatisticsDataStoreManager:GetOrCreatePlayerStatisticsData(
	playerUserId: number | string
): PlayerStatistics
	assert(playerUserId ~= nil, "playerUserId cannot be nil")
	local playerUserIdString: string = tostring(playerUserId)
	return DataStore.loadPlayerStatistics(playerUserIdString)
end

--- Updates a player's statistic and publishes changes if needed.
-- @param playerUserId number|string
-- @param statisticName string
-- @param statisticAmount number
-- @param shouldSetAbsoluteValue boolean
-- @param isRemoteUpdate boolean?
function PlayerStatisticsDataStoreManager:UpdatePlayerStatisticAndPublishChanges(
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

	StatisticsAPI.updatePlayerStatistic(
		playerUserId,
		statisticName,
		statisticAmount,
		shouldSetAbsoluteValue,
		isRemoteUpdate
	)
end

--- Increments a player's statistic.
-- @param playerUserId number|string
-- @param statisticName string
-- @param incrementAmount number
-- @param isRemoteUpdate boolean?
function PlayerStatisticsDataStoreManager:IncrementPlayerStatistic(
	playerUserId: number | string,
	statisticName: string,
	incrementAmount: number,
	isRemoteUpdate: boolean?
): ()
	StatisticsAPI.incrementPlayerStatistic(
		playerUserId,
		statisticName,
		incrementAmount,
		isRemoteUpdate
	)
end

--- Sets a player's statistic to an absolute value.
-- @param playerUserId number|string
-- @param statisticName string
-- @param absoluteValue number
-- @param isRemoteUpdate boolean?
function PlayerStatisticsDataStoreManager:SetPlayerStatisticAbsoluteValue(
	playerUserId: number | string,
	statisticName: string,
	absoluteValue: number,
	isRemoteUpdate: boolean?
): ()
	StatisticsAPI.setPlayerStatisticAbsoluteValue(
		playerUserId,
		statisticName,
		absoluteValue,
		isRemoteUpdate
	)
end

--- Gets a player's statistic value.
-- @param playerUserId number|string
-- @param statisticName string
-- @return number
function PlayerStatisticsDataStoreManager:GetPlayerStatisticValue(
	playerUserId: number | string,
	statisticName: string
): number
	return StatisticsAPI.getPlayerStatisticValue(playerUserId, statisticName)
end

--- Caches player statistics data in memory.
-- @param playerUserId number|string
function PlayerStatisticsDataStoreManager:CachePlayerStatisticsDataInMemory(
	playerUserId: number | string
): ()
	local playerUserIdString: string = tostring(playerUserId)
	local playerStatisticsData = DataStore.loadPlayerStatistics(playerUserIdString)
	DataCache.setCachedData(playerUserIdString, playerStatisticsData)
end

--- Removes player data from cache and saves it.
-- @param playerUserId number|string
function PlayerStatisticsDataStoreManager:RemovePlayerDataFromCacheAndSave(
	playerUserId: number | string
): ()
	local playerUserIdString: string = tostring(playerUserId)
	DataCache.removeCacheEntry(playerUserIdString)
end

--- Saves all cached player data.
-- @return number, number
function PlayerStatisticsDataStoreManager:SaveAllCachedData(): (number, number)
	local successCount: number = 0
	local failCount: number = 0

	for playerUserId, playerStatisticsData in DataCache.getAllCachedData() do
		local success: boolean = DataStore.savePlayerStatistics(playerUserId, playerStatisticsData)
		if success then
			successCount += 1
			DataCache.updateSaveTime(playerUserId)
			DataCache.setPendingSaveFlag(playerUserId, false)
		else
			failCount += 1
		end
	end

	return successCount, failCount
end

--------------------
-- Initialization --
--------------------
local function trackConnection(connection: RBXScriptConnection): RBXScriptConnection
	return resourceManager:trackConnection(connection)
end

CrossServerMessaging.subscribe(trackConnection)
startAutoSaveLoop()
DataCache.startCleanupLoop()

log("Initialized successfully")

-------------
-- Cleanup --
-------------
game:BindToClose(function()
	isShuttingDown = true

	-- Set shutdown flag on all modules
	DataCache.setShutdown(true)
	CrossServerMessaging.setShutdown(true)

	-- Stop background loops
	stopAutoSaveLoop()
	DataCache.stopCleanupLoop()

	-- Disconnect all connections
	resourceManager:cleanupAll()
	CrossServerMessaging.cleanup()

	-- Save all cached data
	local cacheSize: number = 0
	for _ in DataCache.getAllCachedData() do
		cacheSize += 1
	end

	log("Saving %d player data entries before shutdown...", cacheSize)

	local successCount, failCount = PlayerStatisticsDataStoreManager:SaveAllCachedData()

	log("Shutdown save completed: %d successful, %d failed", successCount, failCount)

	task.wait(SHUTDOWN_SAVE_WAIT_SECONDS)
end)

--------------
-- Returner --
--------------
return PlayerStatisticsDataStoreManager