--!strict

--[[
	PassCache - Data Loader

	Handles fetching player gamepass and game ownership data from external APIs
	with retry logic. Manages API request attempts, retry delays, and cache
	clearing operations with timeout protection.

	Returns: DataLoader (module table with data fetching functions)

	Usage:
		DataLoader.initialize({ passesLoader, createEmptyEntry, warnlog })
		local success, entry = DataLoader.fetchPlayerDataSafely(userId, retries, delay)
		local cleared = DataLoader.waitForCacheClear(cache, player, timeout, interval, warnlog)
]]

local DataLoader = {}

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

type LoaderDependencies = {
	passesLoader: any,
	createEmptyEntry: (number?) -> PlayerDataCacheEntry,
	warnlog: (string, ...any) -> (),
}

---------------
-- Constants --
---------------
local TAG = "[DataLoader]"

---------------
-- Variables --
---------------
local deps: LoaderDependencies = nil :: any

function DataLoader.initialize(dependencies: LoaderDependencies): ()
	assert(dependencies, "dependencies cannot be nil")
	assert(dependencies.passesLoader, "dependencies.passesLoader cannot be nil")
	assert(dependencies.createEmptyEntry, "dependencies.createEmptyEntry cannot be nil")
	assert(dependencies.warnlog, "dependencies.warnlog cannot be nil")

	deps = dependencies
end

function DataLoader.fetchPlayerDataSafely(
	userId: number,
	retryAttempts: number,
	retryDelay: number
): (boolean, PlayerDataCacheEntry?)
	assert(userId, "userId cannot be nil")
	assert(type(userId) == "number", "userId must be a number")
	assert(retryAttempts, "retryAttempts cannot be nil")
	assert(type(retryAttempts) == "number", "retryAttempts must be a number")
	assert(retryDelay, "retryDelay cannot be nil")
	assert(type(retryDelay) == "number", "retryDelay must be a number")

	local lastError: any = nil

	for attempt = 1, retryAttempts do
		local gamepassFetchSuccess, gamepassError, playerOwnedGamepasses = deps.passesLoader:FetchAllPlayerGamepasses(userId)
		local gamesFetchSuccess, gamesError, playerOwnedGames = deps.passesLoader:FetchPlayerOwnedGames(userId)

		if gamepassFetchSuccess and gamesFetchSuccess then
			local dataEntry = deps.createEmptyEntry(userId)
			dataEntry.gamepasses = playerOwnedGamepasses or {}
			dataEntry.games = playerOwnedGames or {}
			return true, dataEntry
		end

		lastError = gamepassError or gamesError

		if attempt < retryAttempts then
			deps.warnlog("API fetch failed for user %d (attempt %d/%d): %s", userId, attempt, retryAttempts, tostring(lastError))
			task.wait(retryDelay * attempt)
		end
	end

	deps.warnlog("Failed to fetch data for user %d after %d attempts: %s", userId, retryAttempts, tostring(lastError))
	return false, nil
end

function DataLoader.waitForCacheClear(
	playerCache: { [Player]: PlayerDataCacheEntry },
	targetPlayer: Player,
	timeoutSeconds: number,
	checkInterval: number,
	warnlog: (string, ...any) -> ()
): boolean
	local cacheWaitStartTime = os.clock()

	while playerCache[targetPlayer] do
		if os.clock() - cacheWaitStartTime > timeoutSeconds then
			warnlog("Cache clear timeout for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)
			return false
		end
		task.wait(checkInterval)
	end

	return true
end

return DataLoader