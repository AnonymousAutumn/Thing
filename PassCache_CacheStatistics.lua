--!strict

local CacheStatistics = {}

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

export type CacheStatistics = {
	totalEntries: number,
	oldestEntry: number?,
	newestEntry: number?,
	temporaryEntries: number,
}

local function countTableEntries(tbl: { [any]: any }): number
	local count = 0
	for _ in tbl do
		count += 1
	end
	return count
end

function CacheStatistics.gather(
	playerCache: { [Player]: PlayerDataCacheEntry },
	temporaryCache: { [number]: PlayerDataCacheEntry }
): CacheStatistics
	local totalEntries = 0
	local oldestEntry: number? = nil
	local newestEntry: number? = nil
	local currentTime = os.time()

	for _, cacheEntry in playerCache do
		totalEntries += 1

		local age = currentTime - cacheEntry.metadata.loadedAt

		if not oldestEntry or age > oldestEntry then
			oldestEntry = age
		end

		if not newestEntry or age < newestEntry then
			newestEntry = age
		end
	end

	local temporaryEntries = countTableEntries(temporaryCache)

	return {
		totalEntries = totalEntries,
		oldestEntry = oldestEntry,
		newestEntry = newestEntry,
		temporaryEntries = temporaryEntries,
	}
end

return CacheStatistics