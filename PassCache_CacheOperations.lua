--!strict

local CacheOperations = {}

-----------
-- Types --
-----------
export type CacheMetadata = {
	loadedAt: number,
	lastAccessed: number,
	userId: number,
}

export type GamepassData = {
	Id: number,
	Name: string,
	Icon: string,
	Price: number,
}

export type PlayerDataCacheEntry = {
	gamepasses: { GamepassData },
	games: { number },
	metadata: CacheMetadata,
}

function CacheOperations.createEmpty(userId: number?): PlayerDataCacheEntry
	local currentTime = os.time()
	return {
		gamepasses = {},
		games = {},
		metadata = {
			loadedAt = currentTime,
			lastAccessed = currentTime,
			userId = userId or 0,
		},
	}
end

function CacheOperations.createCopy(cacheEntry: PlayerDataCacheEntry): PlayerDataCacheEntry
	return {
		gamepasses = table.clone(cacheEntry.gamepasses),
		games = table.clone(cacheEntry.games),
		metadata = {
			loadedAt = cacheEntry.metadata.loadedAt,
			lastAccessed = cacheEntry.metadata.lastAccessed,
			userId = cacheEntry.metadata.userId,
		},
	}
end

function CacheOperations.updateAccessTime(cacheEntry: PlayerDataCacheEntry): ()
	if cacheEntry and cacheEntry.metadata then
		cacheEntry.metadata.lastAccessed = os.time()
	end
end

function CacheOperations.isStale(cacheEntry: PlayerDataCacheEntry, currentTime: number, maxAge: number): boolean
	local age = currentTime - cacheEntry.metadata.loadedAt
	return age > maxAge
end

function CacheOperations.countEntries(tbl: { [any]: any }): number
	local count = 0
	for _ in tbl do
		count += 1
	end
	return count
end

return CacheOperations