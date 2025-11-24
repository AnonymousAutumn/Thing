--!strict

--[[
	CacheManager Module

	Provides time-based caching with automatic cleanup and statistics tracking.
	Returns a table with a .new() constructor for creating cache instances.

	Usage:
		local cache = CacheManager.new(3600, 600, true)
		cache:set("key", "value")
		local value = cache:get("key")
]]

-----------
-- Types --
-----------
type CacheEntry<T> = {
	data: T,
	timestamp: number,
	lastAccessed: number,
}

export type CacheStatistics = {
	hits: number,
	misses: number,
	evictions: number,
	size: number,
}

export type CacheManager<K, V> = {
	get: (self: CacheManager<K, V>, key: K) -> V?,
	set: (self: CacheManager<K, V>, key: K, value: V) -> (),
	has: (self: CacheManager<K, V>, key: K) -> boolean,
	invalidate: (self: CacheManager<K, V>, key: K) -> boolean,
	clear: (self: CacheManager<K, V>) -> (),
	cleanup: (self: CacheManager<K, V>) -> number,
	getStatistics: (self: CacheManager<K, V>) -> CacheStatistics,
	resetStatistics: (self: CacheManager<K, V>) -> (),
	stopAutoCleanup: (self: CacheManager<K, V>) -> (),
	getSize: (self: CacheManager<K, V>) -> number,
}

type CacheManagerInternal<K, V> = CacheManager<K, V> & {
	_cache: { [K]: CacheEntry<V> },
	_maxAge: number,
	_cleanupInterval: number,
	_cleanupThread: thread?,
	_statistics: CacheStatistics,
}

---------------
-- Constants --
---------------
local TAG = "[CacheManager]"

local DEFAULT_MAX_AGE = 3600 -- 1 hour in seconds
local DEFAULT_CLEANUP_INTERVAL = 600 -- 10 minutes in seconds

----------------------
-- Private Functions --
----------------------

-- Checks if a cache entry has expired
local function isCacheEntryExpired<T>(entry: CacheEntry<T>, currentTime: number, maxAge: number): boolean
	return (currentTime - entry.timestamp) >= maxAge
end

-- Removes expired entries from cache
local function performCacheCleanup<K, V>(cache: { [K]: CacheEntry<V> }, maxAge: number): number
	local currentTime = os.time()
	local removedCount = 0

	for key, entry in cache do
		if isCacheEntryExpired(entry, currentTime, maxAge) then
			cache[key] = nil
			removedCount += 1
		end
	end

	return removedCount
end

---------------
-- Public API --
---------------
local CacheManager = {}

--[[
	Creates a new CacheManager instance

	@param maxAge - Maximum age of cache entries in seconds (default: 3600 = 1 hour)
	@param cleanupInterval - Interval between automatic cleanup runs in seconds (default: 600 = 10 minutes)
	@param autoCleanup - Whether to start automatic cleanup (default: true)
	@return CacheManager
]]
function CacheManager.new<K, V>(
	maxAge: number?,
	cleanupInterval: number?,
	autoCleanup: boolean?
): CacheManager<K, V>
	if maxAge ~= nil then
		assert(type(maxAge) == "number" and maxAge > 0, "maxAge must be a positive number")
	end
	if cleanupInterval ~= nil then
		assert(type(cleanupInterval) == "number" and cleanupInterval > 0, "cleanupInterval must be a positive number")
	end

	local self: CacheManagerInternal<K, V> = {
		_cache = {},
		_maxAge = maxAge or DEFAULT_MAX_AGE,
		_cleanupInterval = cleanupInterval or DEFAULT_CLEANUP_INTERVAL,
		_cleanupThread = nil,
		_statistics = {
			hits = 0,
			misses = 0,
			evictions = 0,
			size = 0,
		},
	} :: any

	--[[
		Retrieves a value from the cache
		Returns nil if key not found or entry expired

		@param key - The cache key
		@return V? - The cached value or nil
	]]
	function self:get(key: K): V?
		local entry = self._cache[key]
		if not entry then
			self._statistics.misses += 1
			return nil
		end

		local currentTime = os.time()
		if isCacheEntryExpired(entry, currentTime, self._maxAge) then
			self._cache[key] = nil
			self._statistics.size -= 1
			self._statistics.evictions += 1
			self._statistics.misses += 1
			return nil
		end

		-- Update last accessed time
		entry.lastAccessed = currentTime
		self._statistics.hits += 1
		return entry.data
	end

	--[[
		Stores a value in the cache

		@param key - The cache key
		@param value - The value to cache
	]]
	function self:set(key: K, value: V): ()
		local isNewEntry = self._cache[key] == nil
		local currentTime = os.time()

		self._cache[key] = {
			data = value,
			timestamp = currentTime,
			lastAccessed = currentTime,
		}

		if isNewEntry then
			self._statistics.size += 1
		end
	end

	--[[
		Checks if a key exists in cache (and is not expired)

		@param key - The cache key
		@return boolean - True if key exists and not expired
	]]
	function self:has(key: K): boolean
		return self:get(key) ~= nil
	end

	--[[
		Removes a specific entry from cache

		@param key - The cache key to remove
		@return boolean - True if entry was removed
	]]
	function self:invalidate(key: K): boolean
		local existingEntry = self._cache[key]
		if existingEntry then
			self._cache[key] = nil
			self._statistics.size -= 1
			return true
		end
		return false
	end

	--[[
		Clears all entries from cache
	]]
	function self:clear(): ()
		table.clear(self._cache)
		self._statistics.size = 0
	end

	--[[
		Manually removes expired entries from cache

		@return number - Count of entries removed
	]]
	function self:cleanup(): number
		local removedCount = performCacheCleanup(self._cache, self._maxAge)
		self._statistics.size -= removedCount
		self._statistics.evictions += removedCount
		return removedCount
	end

	--[[
		Returns cache statistics for monitoring

		@return CacheStatistics
	]]
	function self:getStatistics(): CacheStatistics
		return {
			hits = self._statistics.hits,
			misses = self._statistics.misses,
			evictions = self._statistics.evictions,
			size = self._statistics.size,
		}
	end

	--[[
		Resets statistics counters
		Does not affect cache contents
	]]
	function self:resetStatistics(): ()
		self._statistics.hits = 0
		self._statistics.misses = 0
		self._statistics.evictions = 0
		-- Don't reset size as it reflects actual cache state
	end

	--[[
		Stops automatic cleanup thread
	]]
	function self:stopAutoCleanup(): ()
		if self._cleanupThread and coroutine.status(self._cleanupThread) ~= "dead" then
			task.cancel(self._cleanupThread)
			self._cleanupThread = nil
		end
	end

	--[[
		Gets the current size of the cache

		@return number - Number of entries in cache
	]]
	function self:getSize(): number
		return self._statistics.size
	end

	-- Start automatic cleanup if enabled
	if autoCleanup ~= false then
		self._cleanupThread = task.spawn(function()
			while true do
				task.wait(self._cleanupInterval)
				local removedCount = self:cleanup()
				if removedCount > 0 then
					-- Optional: log cleanup activity
					-- print(string.format("%s Auto-cleanup removed %d expired entries", TAG, removedCount))
				end
			end
		end)
	end

	return self :: CacheManager<K, V>
end

--------------
-- Return  --
--------------
return CacheManager