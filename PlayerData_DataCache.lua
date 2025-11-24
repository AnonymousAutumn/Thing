--!strict

--------------
-- Services --
--------------

local Players = game:GetService("Players")

-----------
-- Types --
-----------

export type CacheMetadata = {
	lastAccessed: number,
	lastSaved: number,
}

export type PlayerStatistics = {
	Donated: number,
	Raised: number,
	Wins: number,
}

---------------
-- Constants --
---------------

local TAG = "[PlayerData.DataCache]"

local CACHE_CLEANUP_INTERVAL_SECONDS: number = 600 -- 10 minutes
local CACHE_ENTRY_MAX_AGE_SECONDS: number = 900 -- 15 minutes

---------------
-- Variables --
---------------

local DataCache = {}

local playerDataMemoryCache: {[string]: PlayerStatistics} = {}
local cacheMetadata: {[string]: CacheMetadata} = {}
local pendingSaveFlags: {[string]: boolean} = {}
local saveDelayHandles: {[string]: thread} = {}

local cacheCleanupThread: thread? = nil
local isShuttingDown: boolean = false

local onCacheEntryRemoved: ((playerUserId: string, data: PlayerStatistics) -> ())? = nil

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

---------------------
-- Cache Management --
---------------------
function DataCache.updateMetadata(playerUserId: string): ()
	local currentTime: number = os.time()

	if not cacheMetadata[playerUserId] then
		cacheMetadata[playerUserId] = {
			lastAccessed = currentTime,
			lastSaved = currentTime,
		}
	else
		cacheMetadata[playerUserId].lastAccessed = currentTime
	end
end

function DataCache.updateSaveTime(playerUserId: string): ()
	local metadata: CacheMetadata? = cacheMetadata[playerUserId]
	if metadata then
		metadata.lastSaved = os.time()
	end
end

local function isCacheEntryStale(metadata: CacheMetadata, currentTime: number): boolean
	return (currentTime - metadata.lastAccessed) > CACHE_ENTRY_MAX_AGE_SECONDS
end

function DataCache.removeCacheEntry(playerUserId: string): ()
	local cachedData: PlayerStatistics? = playerDataMemoryCache[playerUserId]

	-- Call the removal callback if set (for saving data)
	if cachedData and onCacheEntryRemoved then
		onCacheEntryRemoved(playerUserId, cachedData)
	end

	playerDataMemoryCache[playerUserId] = nil
	cacheMetadata[playerUserId] = nil
	pendingSaveFlags[playerUserId] = nil

	local handle = saveDelayHandles[playerUserId]
	if handle then
		cancelThread(handle)
		saveDelayHandles[playerUserId] = nil
	end
end

local function performCacheCleanup(): ()
	if isShuttingDown then
		return
	end

	local currentTime: number = os.time()
	local removedCount: number = 0

	for playerUserId, metadata in cacheMetadata do
		if isCacheEntryStale(metadata, currentTime) then
			local userId: number? = tonumber(playerUserId)
			local player: Player? = if userId then Players:GetPlayerByUserId(userId) else nil

			if not player then
				DataCache.removeCacheEntry(playerUserId)
				removedCount += 1
			end
		end
	end

	if removedCount > 0 then
		log("Cache cleanup: removed %d entries", removedCount)
	end
end

function DataCache.startCleanupLoop(): ()
	if cacheCleanupThread then
		return
	end

	cacheCleanupThread = task.spawn(function()
		while not isShuttingDown do
			task.wait(CACHE_CLEANUP_INTERVAL_SECONDS)
			performCacheCleanup()
		end
	end)
end

function DataCache.stopCleanupLoop(): ()
	cancelThread(cacheCleanupThread)
	cacheCleanupThread = nil
end

------------------------
-- Cache Data Access --
------------------------
function DataCache.getCachedData(playerUserId: string): PlayerStatistics?
	return playerDataMemoryCache[playerUserId]
end

function DataCache.setCachedData(playerUserId: string, data: PlayerStatistics): ()
	playerDataMemoryCache[playerUserId] = data
	DataCache.updateMetadata(playerUserId)
end

function DataCache.getAllCachedData(): {[string]: PlayerStatistics}
	return playerDataMemoryCache
end

function DataCache.getPendingSaveFlag(playerUserId: string): boolean
	return pendingSaveFlags[playerUserId] == true
end

function DataCache.setPendingSaveFlag(playerUserId: string, value: boolean): ()
	pendingSaveFlags[playerUserId] = value
end

function DataCache.getSaveDelayHandle(playerUserId: string): thread?
	return saveDelayHandles[playerUserId]
end

function DataCache.setSaveDelayHandle(playerUserId: string, handle: thread?): ()
	if handle == nil then
		local existingHandle = saveDelayHandles[playerUserId]
		if existingHandle then
			cancelThread(existingHandle)
		end
		saveDelayHandles[playerUserId] = nil
	else
		saveDelayHandles[playerUserId] = handle
	end
end

-----------------------
-- Lifecycle Control --
-----------------------
function DataCache.setShutdown(shutdown: boolean): ()
	isShuttingDown = shutdown
end

function DataCache.setRemovalCallback(callback: (playerUserId: string, data: PlayerStatistics) -> ()): ()
	onCacheEntryRemoved = callback
end

function DataCache.cleanup(): ()
	isShuttingDown = true
	DataCache.stopCleanupLoop()

	for _, handle in saveDelayHandles do
		cancelThread(handle)
	end
	table.clear(saveDelayHandles)
end

return DataCache