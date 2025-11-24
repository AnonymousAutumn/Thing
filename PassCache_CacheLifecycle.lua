--!strict

--[[
	PassCache - Cache Lifecycle Manager

	Manages the lifecycle of cache entries including periodic cleanup of stale
	entries, cleanup thread management, and shutdown procedures. Handles both
	player-keyed and user ID-keyed cache entries.

	Returns: CacheLifecycle (module table with lifecycle functions)

	Usage:
		CacheLifecycle.initialize({ checkStaleFunc, isValidPlayerFunc, logFunc })
		CacheLifecycle.startCleanupLoop(playerCache, tempCache, config)
		CacheLifecycle.stopCleanupLoop()
		CacheLifecycle.setShuttingDown(true)
]]

local CacheLifecycle = {}

-----------
-- Types --
-----------
type PlayerDataCacheEntry = {
	gamepasses: { any },
	games: { number },
	metadata: {
		loadedAt: number,
		lastAccessed: number,
		userId: number,
	},
}

type LifecycleState = {
	cleanupThread: thread?,
	isShuttingDown: boolean,
	checkStaleFunc: (PlayerDataCacheEntry, number, number) -> boolean,
	isValidPlayerFunc: (Player) -> boolean,
	logFunc: (string, ...any) -> (),
}

---------------
-- Constants --
---------------
local TAG = "[CacheLifecycle]"

---------------
-- Variables --
---------------
local state: LifecycleState = nil :: any

function CacheLifecycle.initialize(config: {
	checkStaleFunc: (PlayerDataCacheEntry, number, number) -> boolean,
	isValidPlayerFunc: (Player) -> boolean,
	logFunc: (string, ...any) -> (),
	}): ()
	assert(config, "config cannot be nil")
	assert(config.checkStaleFunc, "config.checkStaleFunc cannot be nil")
	assert(config.isValidPlayerFunc, "config.isValidPlayerFunc cannot be nil")
	assert(config.logFunc, "config.logFunc cannot be nil")

	state = {
		cleanupThread = nil,
		isShuttingDown = false,
		checkStaleFunc = config.checkStaleFunc,
		isValidPlayerFunc = config.isValidPlayerFunc,
		logFunc = config.logFunc,
	}
end

function CacheLifecycle.cancelCleanupThread(): ()
	if state.cleanupThread then
		task.cancel(state.cleanupThread)
		state.cleanupThread = nil
	end
end

function CacheLifecycle.removeStalePlayerEntries(
	playerCache: { [Player]: PlayerDataCacheEntry },
	currentTime: number,
	maxAge: number
): number
	local playersToRemove: { Player } = {}

	for player, cacheEntry in playerCache do
		if state.checkStaleFunc(cacheEntry, currentTime, maxAge) or not state.isValidPlayerFunc(player) then
			table.insert(playersToRemove, player)
		end
	end

	for _, player in playersToRemove do
		playerCache[player] = nil
	end

	return #playersToRemove
end

function CacheLifecycle.removeStaleTempEntries(
	temporaryCache: { [number]: PlayerDataCacheEntry },
	currentTime: number,
	maxAge: number
): number
	local userIdsToRemove: { number } = {}

	for userId, cacheEntry in temporaryCache do
		if state.checkStaleFunc(cacheEntry, currentTime, maxAge) then
			table.insert(userIdsToRemove, userId)
		end
	end

	for _, userId in userIdsToRemove do
		temporaryCache[userId] = nil
	end

	return #userIdsToRemove
end

function CacheLifecycle.performCleanup(
	playerCache: { [Player]: PlayerDataCacheEntry },
	temporaryCache: { [number]: PlayerDataCacheEntry },
	maxAge: number
): ()
	if state.isShuttingDown then
		return
	end

	local currentTime = os.time()

	local playerCacheRemoved = CacheLifecycle.removeStalePlayerEntries(playerCache, currentTime, maxAge)
	local tempCacheRemoved = CacheLifecycle.removeStaleTempEntries(temporaryCache, currentTime, maxAge)

	if playerCacheRemoved > 0 or tempCacheRemoved > 0 then
		state.logFunc("Cache cleanup: removed %d player entries, %d temporary entries", playerCacheRemoved, tempCacheRemoved)
	end
end

function CacheLifecycle.startCleanupLoop(
	playerCache: { [Player]: PlayerDataCacheEntry },
	temporaryCache: { [number]: PlayerDataCacheEntry },
	config: {
		enabled: boolean,
		intervalSeconds: number,
		maxAgeSeconds: number,
	}
): ()
	if not config.enabled or state.cleanupThread then
		return
	end

	state.cleanupThread = task.spawn(function()
		while not state.isShuttingDown do
			task.wait(config.intervalSeconds)
			CacheLifecycle.performCleanup(playerCache, temporaryCache, config.maxAgeSeconds)
		end
	end)
end

function CacheLifecycle.stopCleanupLoop(): ()
	CacheLifecycle.cancelCleanupThread()
end

function CacheLifecycle.setShuttingDown(value: boolean): ()
	state.isShuttingDown = value
end

return CacheLifecycle