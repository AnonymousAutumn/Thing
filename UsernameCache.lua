--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----------------
-- References --
----------------
local modules = ReplicatedStorage:WaitForChild("Modules")
local validationUtils = require(modules.Utilities.ValidationUtils)
local CacheManager = require(modules.Wrappers.Cache)

-----------
-- Types --
-----------
type CacheStatistics = {
	hits: number,
	misses: number,
	evictions: number,
	size: number,
	apiCalls: number,
	failures: number,
}

---------------
-- Constants --
---------------
local TAG = "[UsernameCache]"

local DEFAULT_USERNAME = "Unknown"
local USERNAME_CACHE_EXPIRATION = 60 * 60 -- 1 hour in seconds
local USERNAME_CACHE_CLEANUP_INTERVAL = 60 * 10 -- 10 minutes in seconds
local MAX_USERNAME_RETRIES = 2
local USERNAME_FETCH_TIMEOUT = 5 -- seconds
local BASE_RETRY_DELAY = 1 -- seconds

---------------
-- Variables --
---------------
-- Use generic CacheManager instead of custom implementation
local usernameCache = CacheManager.new(
	USERNAME_CACHE_EXPIRATION,
	USERNAME_CACHE_CLEANUP_INTERVAL,
	true -- enable auto-cleanup
)

-- Track additional statistics not provided by CacheManager
local apiCalls = 0
local failures = 0

----------------------
-- Private Functions --
----------------------

-- Calculates exponential backoff retry delay
local function calculateRetryDelay(attemptNumber: number): number
	return BASE_RETRY_DELAY * attemptNumber
end

-- Checks if operation has exceeded timeout threshold
local function hasExceededTimeout(startTime: number, timeoutSeconds: number): boolean
	return os.clock() - startTime > timeoutSeconds
end

-- Fetches username from Roblox API with retry logic
local function fetchUsernameFromAPI(targetUserId: number): (boolean, string?)
	for attemptNumber = 1, MAX_USERNAME_RETRIES do
		apiCalls += 1
		local requestStartTime = os.clock()

		local success, result = pcall(function()
			local username = Players:GetNameFromUserIdAsync(targetUserId)
			if hasExceededTimeout(requestStartTime, USERNAME_FETCH_TIMEOUT) then
				error("Username fetch timeout")
			end
			return username
		end)

		if success and typeof(result) == "string" and #result > 0 then
			return true, result
		end

		warn(string.format("%s Username fetch attempt %d/%d failed for user %d: %s",
			TAG, attemptNumber, MAX_USERNAME_RETRIES, targetUserId, tostring(result)))

		if attemptNumber < MAX_USERNAME_RETRIES then
			task.wait(calculateRetryDelay(attemptNumber))
		end
	end

	failures += 1
	return false, nil
end

---------------
-- Public API --
---------------
local UsernameCache = {}

--[[
	Resolves a userId to a username, using cache if available
	Falls back to API call if not cached, with retry logic
	Returns DEFAULT_USERNAME if all attempts fail

	@param targetUserId - The Roblox user ID to resolve
	@return string - The username or DEFAULT_USERNAME if failed
]]
function UsernameCache.getUsername(targetUserId: number): string
	-- Validate input
	if not validationUtils.isValidUserId(targetUserId) then
		warn(string.format("%s Invalid user ID provided: %s", TAG, tostring(targetUserId)))
		return DEFAULT_USERNAME
	end

	-- Check cache first (CacheManager handles TTL automatically)
	local cachedName = usernameCache:get(targetUserId)
	if cachedName then
		return cachedName
	end

	-- Fetch from API if not cached
	local success, username = fetchUsernameFromAPI(targetUserId)
	if success and username then
		usernameCache:set(targetUserId, username)
		return username
	end

	-- Return default if all attempts failed
	return DEFAULT_USERNAME
end

--[[
	Asynchronously fetches username (same as getUsername, for backward compatibility)

	@param targetUserId - The Roblox user ID to resolve
	@return string - The username or DEFAULT_USERNAME if failed
]]
function UsernameCache.getUsernameAsync(targetUserId: number): string
	return UsernameCache.getUsername(targetUserId)
end

--[[
	Manually adds a username to the cache
	Useful for pre-caching known usernames

	@param userId - The user ID
	@param username - The username to cache
]]
function UsernameCache.setCachedUsername(userId: number, username: string): ()
	if not validationUtils.isValidUserId(userId) or not validationUtils.isValidString(username) then
		warn(string.format("%s Invalid userId or username provided to setCachedUsername", TAG))
		return
	end

	usernameCache:set(userId, username)
end

--[[
	Invalidates (removes) a cached username
	Forces next getUsername call to fetch from API

	@param userId - The user ID to invalidate
]]
function UsernameCache.invalidateCache(userId: number): ()
	usernameCache:invalidate(userId)
end

--[[
	Clears all cached usernames
]]
function UsernameCache.clearCache(): ()
	usernameCache:clear()
end

--[[
	Removes expired entries from cache
	Can be called periodically to reduce memory usage

	@return number - Count of entries removed
]]
function UsernameCache.cleanup(): number
	return usernameCache:cleanup()
end

--[[
	Returns cache statistics for monitoring

	@return CacheStatistics
]]
function UsernameCache.getStatistics(): CacheStatistics
	local baseStats = usernameCache:getStatistics()

	return {
		hits = baseStats.hits,
		misses = baseStats.misses,
		evictions = baseStats.evictions,
		size = baseStats.size,
		apiCalls = apiCalls,
		failures = failures,
	}
end

--[[
	Resets cache statistics
]]
function UsernameCache.resetStatistics(): ()
	usernameCache:resetStatistics()
	apiCalls = 0
	failures = 0
end

--[[
	Configures cache settings

	@param settings - Table with optional fields:
		- maxRetries: number (default 2)
		- timeout: number (default 5 seconds)
		- expiration: number (default 3600 seconds / 1 hour)
		- retryDelay: number (default 1 second)
]]
function UsernameCache.configure(settings: {
	maxRetries: number?,
	timeout: number?,
	expiration: number?,
	retryDelay: number?,
	}): ()
	warn(string.format("%s Note: configure() is not yet implemented. Using defaults.", TAG))
	-- Future enhancement: allow runtime configuration
end

--[[
	Stops automatic cleanup (for shutdown)
]]
function UsernameCache.shutdown(): ()
	usernameCache:stopAutoCleanup()
end

--------------
-- Return  --
--------------
return UsernameCache