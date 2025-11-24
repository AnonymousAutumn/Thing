--!strict

-----------------
-- Initializer --
-----------------

local InventoryHandler = {}

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local modules = ReplicatedStorage:WaitForChild("Modules")
local configuration = ReplicatedStorage:WaitForChild("Configuration")

local passesLoader = require(modules.Managers.PassesLoader)
local ResourceCleanup = require(modules.Wrappers.ResourceCleanup)
local validationUtils = require(modules.Utilities.ValidationUtils)
local gameConfig = require(configuration.GameConfig)

local CacheOperations = require(script.CacheOperations)
local CacheLifecycle = require(script.CacheLifecycle)
local DataLoader = require(script.DataLoader)
local CacheStatistics = require(script.CacheStatistics)

-----------
-- Types --
-----------
export type CacheMetadata = CacheOperations.CacheMetadata
export type GamepassData = CacheOperations.GamepassData
export type PlayerDataCacheEntry = CacheOperations.PlayerDataCacheEntry
export type CacheStatistics = CacheStatistics.CacheStatistics

---------------
-- Constants --
---------------
local TAG = "[PlayerGamepassDataCacheManager]"

local CACHE_OPERATION_TIMEOUT_SECONDS = 15
local CACHE_CLEAR_CHECK_INTERVAL_SECONDS = 0.1

local CACHE_ENTRY_MAX_AGE_SECONDS = 60 * 60 -- 1 hour
local CACHE_CLEANUP_INTERVAL_SECONDS = 60 * 10 -- 10 minutes
local ENABLE_CACHE_CLEANUP = true

local API_FETCH_RETRY_ATTEMPTS = 3
local API_FETCH_RETRY_DELAY_SECONDS = 1

local KICK_MESSAGES = {
	LOAD_FAILED = "\nGamepass data failed to load. Please rejoin.",
	CACHE_TIMEOUT = "Cache reload timeout occurred. Please rejoin.",
	RELOAD_FAILED = "Cache reload failed. Please rejoin.",
	NOT_FOUND = "Player gamepass data not found in cache. Please rejoin.",
}

---------------
-- Variables --
---------------
local resourceManager = ResourceCleanup.new()

InventoryHandler.PlayerDataCache = {}

local temporaryGiftRecipientCache: { [number]: PlayerDataCacheEntry } = {}

---------------
-- Utilities --
---------------
local function log(message: string, ...): ()
	print(TAG .. " " .. string.format(message, ...))
end

local function warnlog(message: string, ...): ()
	warn(TAG .. " " .. string.format(message, ...))
end

local function safeKickPlayer(player: Player, message: string): ()
	if validationUtils.isValidPlayer(player) then
		player:Kick(message)
	end
end

----------------------
-- Module Initialization --
----------------------
CacheLifecycle.initialize({
	checkStaleFunc = CacheOperations.isStale,
	isValidPlayerFunc = validationUtils.isValidPlayer,
	logFunc = log,
})

DataLoader.initialize({
	passesLoader = passesLoader,
	createEmptyEntry = CacheOperations.createEmpty,
	warnlog = warnlog,
})

--------------------
-- Public Methods --
--------------------

function InventoryHandler.LoadPlayerGamepassDataIntoCache(targetPlayer: Player): boolean
	if not validationUtils.isValidPlayer(targetPlayer) then
		warnlog("Attempted to load cache for invalid player: %s", tostring(targetPlayer))
		return false
	end

	if InventoryHandler.PlayerDataCache[targetPlayer] then
		warnlog("Cache already exists for player %s (UserId: %d), updating access time", targetPlayer.Name, targetPlayer.UserId)
		CacheOperations.updateAccessTime(InventoryHandler.PlayerDataCache[targetPlayer])
		return true
	end

	local fetchSuccess, playerDataCacheEntry = DataLoader.fetchPlayerDataSafely(
		targetPlayer.UserId,
		API_FETCH_RETRY_ATTEMPTS,
		API_FETCH_RETRY_DELAY_SECONDS
	)

	if not fetchSuccess or not playerDataCacheEntry then
		warnlog("Failed to load gamepass data for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)
		safeKickPlayer(targetPlayer, KICK_MESSAGES.LOAD_FAILED)
		return false
	end

	InventoryHandler.PlayerDataCache[targetPlayer] = playerDataCacheEntry

	log(
		"Successfully loaded cache for player %s (UserId: %d) - %d gamepasses, %d games",
		targetPlayer.Name,
		targetPlayer.UserId,
		#playerDataCacheEntry.gamepasses,
		#playerDataCacheEntry.games
	)

	return true
end

function InventoryHandler.LoadGiftRecipientGamepassDataTemporarily(recipientUserId: number): PlayerDataCacheEntry?
	if not validationUtils.isValidUserId(recipientUserId) then
		warnlog("Invalid recipient user ID: %s", tostring(recipientUserId))
		return nil
	end

	local cachedEntry = temporaryGiftRecipientCache[recipientUserId]
	if cachedEntry then
		local currentTime = os.time()
		if not CacheOperations.isStale(cachedEntry, currentTime, CACHE_ENTRY_MAX_AGE_SECONDS) then
			CacheOperations.updateAccessTime(cachedEntry)
			return cachedEntry
		end
	end

	local fetchSuccess, temporaryDataCacheEntry = DataLoader.fetchPlayerDataSafely(
		recipientUserId,
		API_FETCH_RETRY_ATTEMPTS,
		API_FETCH_RETRY_DELAY_SECONDS
	)

	if not fetchSuccess or not temporaryDataCacheEntry then
		warnlog("Failed to fetch gamepass/game data for gift recipient (UserId: %d)", recipientUserId)
		return nil
	end

	temporaryGiftRecipientCache[recipientUserId] = temporaryDataCacheEntry

	log(
		"Loaded temporary cache for gift recipient (UserId: %d) - %d gamepasses, %d games",
		recipientUserId,
		#temporaryDataCacheEntry.gamepasses,
		#temporaryDataCacheEntry.games
	)

	return temporaryDataCacheEntry
end

function InventoryHandler.ReloadPlayerGamepassDataCache(targetPlayer: Player): boolean
	if not validationUtils.isValidPlayer(targetPlayer) then
		warnlog("Attempted to reload cache for invalid player: %s", tostring(targetPlayer))
		return false
	end

	log("Reloading cache for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)

	InventoryHandler.UnloadPlayerDataFromCache(targetPlayer)

	local cacheClearSuccess = DataLoader.waitForCacheClear(
		InventoryHandler.PlayerDataCache,
		targetPlayer,
		CACHE_OPERATION_TIMEOUT_SECONDS,
		CACHE_CLEAR_CHECK_INTERVAL_SECONDS,
		warnlog
	)
	if not cacheClearSuccess then
		warnlog("Cache clear timeout for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)
		safeKickPlayer(targetPlayer, KICK_MESSAGES.CACHE_TIMEOUT)
		return false
	end

	local success, loadResult =
		pcall(InventoryHandler.LoadPlayerGamepassDataIntoCache, targetPlayer)

	if not success then
		local errorMessage = loadResult :: any
		warnlog(
			"Cache reload error for player %s (UserId: %d): %s",
			targetPlayer.Name,
			targetPlayer.UserId,
			tostring(errorMessage)
		)
		safeKickPlayer(targetPlayer, KICK_MESSAGES.RELOAD_FAILED)
		return false
	end

	if not loadResult then
		warnlog("Cache reload failed for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)
		safeKickPlayer(targetPlayer, KICK_MESSAGES.RELOAD_FAILED)
		return false
	end

	log("Successfully reloaded cache for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)
	return true
end

function InventoryHandler.UnloadPlayerDataFromCache(targetPlayer: Player): ()
	if InventoryHandler.PlayerDataCache[targetPlayer] then
		log("Unloading cache for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)
		InventoryHandler.PlayerDataCache[targetPlayer] = nil
	end
end

function InventoryHandler.GetPlayerCachedGamepassData(targetPlayer: Player): PlayerDataCacheEntry?
	if not validationUtils.isValidPlayer(targetPlayer) then
		warnlog("Attempted to get cache for invalid player: %s", tostring(targetPlayer))
		return nil
	end

	local playerCachedData = InventoryHandler.PlayerDataCache[targetPlayer]

	if not playerCachedData then
		warnlog("Cache not found for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)
		safeKickPlayer(targetPlayer, KICK_MESSAGES.NOT_FOUND)
		return nil
	end

	CacheOperations.updateAccessTime(playerCachedData)
	return CacheOperations.createCopy(playerCachedData)
end

function InventoryHandler.ClearAllCachedData(): ()
	local playerCount = CacheOperations.countEntries(InventoryHandler.PlayerDataCache)
	local tempCount = CacheOperations.countEntries(temporaryGiftRecipientCache)

	table.clear(InventoryHandler.PlayerDataCache)
	table.clear(temporaryGiftRecipientCache)

	log("Cleared all cached data: %d player entries, %d temporary entries", playerCount, tempCount)
end

function InventoryHandler.GetCacheStatistics(): CacheStatistics
	return CacheStatistics.gather(InventoryHandler.PlayerDataCache, temporaryGiftRecipientCache)
end

-----------------------------
-- Helper Getters --
-----------------------------
function InventoryHandler.GetPlayerGamepassesAsList(targetPlayer: Player): { GamepassData }?
	local data = InventoryHandler.GetPlayerCachedGamepassData(targetPlayer)
	if not data then
		return nil
	end
	return data.gamepasses
end

function InventoryHandler.GetGiftRecipientGamepassesAsList(recipientUserId: number): { GamepassData }?
	local data = InventoryHandler.LoadGiftRecipientGamepassDataTemporarily(recipientUserId)
	if not data then
		return nil
	end
	return data.gamepasses
end

--------------------
-- Initialization --
--------------------
if RunService:IsServer() then
	CacheLifecycle.startCleanupLoop(
		InventoryHandler.PlayerDataCache,
		temporaryGiftRecipientCache,
		{
			enabled = ENABLE_CACHE_CLEANUP,
			intervalSeconds = CACHE_CLEANUP_INTERVAL_SECONDS,
			maxAgeSeconds = CACHE_ENTRY_MAX_AGE_SECONDS,
		}
	)

	resourceManager:trackConnection(
		Players.PlayerRemoving:Connect(function(player)
			InventoryHandler.UnloadPlayerDataFromCache(player)
		end)
	)

	game:BindToClose(function()
		CacheLifecycle.setShuttingDown(true)
		CacheLifecycle.stopCleanupLoop()
		resourceManager:cleanupAll()
		log("Clearing all caches on shutdown...")
		InventoryHandler.ClearAllCachedData()
	end)
end

--------------
-- Returner --
--------------
return InventoryHandler