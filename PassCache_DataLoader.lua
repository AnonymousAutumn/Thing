--!strict

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
	deps = dependencies
end

function DataLoader.fetchPlayerDataSafely(
	userId: number,
	retryAttempts: number,
	retryDelay: number
): (boolean, PlayerDataCacheEntry?)
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