--!strict

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

-----------
-- Types --
-----------

export type RateLimitEntry = {
	lastCallTime: number,
	violationCount: number,
}

export type RateLimitData = {
	[string]: RateLimitEntry, -- actionName -> entry
}

---------------
-- Constants --
---------------
local TAG = "[RateLimiter]"

local DEFAULT_COOLDOWN_SECONDS = 1
local CLEANUP_INTERVAL_SECONDS = 300 -- Clean up old entries every 5 minutes
local ENTRY_EXPIRY_SECONDS = 600 -- Remove entries older than 10 minutes
local VIOLATION_THRESHOLD = 10 -- Warn after this many violations
local SUSPICIOUS_THRESHOLD = 50 -- Log as suspicious after this many violations

---------------
-- Variables --
---------------
local rateLimitData: {[number]: RateLimitData} = {} -- UserId -> RateLimitData
local globalCooldowns: {[string]: number} = {} -- actionName -> cooldown duration
local resourceManager = ResourceCleanup.new()
local cleanupThread: thread? = nil

local RateLimiter = {}

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
-- Helper Functions --
-------------------

--- Gets or creates rate limit data for a player
local function getOrCreatePlayerData(userId: number): RateLimitData
	if not rateLimitData[userId] then
		rateLimitData[userId] = {}
	end
	return rateLimitData[userId]
end

--- Gets or creates rate limit entry for a specific action
local function getOrCreateEntry(playerData: RateLimitData, actionName: string): RateLimitEntry
	if not playerData[actionName] then
		playerData[actionName] = {
			lastCallTime = 0,
			violationCount = 0,
		}
	end
	return playerData[actionName]
end

--- Gets the cooldown duration for an action
local function getCooldownDuration(actionName: string): number
	return globalCooldowns[actionName] or DEFAULT_COOLDOWN_SECONDS
end

--- Checks if entry has expired and should be cleaned up
local function isEntryExpired(entry: RateLimitEntry, currentTime: number): boolean
	return (currentTime - entry.lastCallTime) > ENTRY_EXPIRY_SECONDS
end

-------------------
-- Cleanup System --
-------------------

--- Removes expired entries for a player
local function cleanupPlayerData(userId: number, currentTime: number): ()
	local playerData = rateLimitData[userId]
	if not playerData then
		return
	end

	local entriesRemoved = 0
	for actionName, entry in playerData do
		if isEntryExpired(entry, currentTime) then
			playerData[actionName] = nil
			entriesRemoved += 1
		end
	end

	-- If no entries left, remove entire player data
	if next(playerData) == nil then
		rateLimitData[userId] = nil
	end
end

--- Cleanup loop that runs periodically
local function performCleanup(): ()
	local currentTime = tick()
	local playersProcessed = 0
	local entriesRemoved = 0

	for userId in rateLimitData do
		cleanupPlayerData(userId, currentTime)
		playersProcessed += 1
	end

	if playersProcessed > 0 then
		log("Cleanup completed: processed %d players", playersProcessed)
	end
end

--- Starts the automatic cleanup loop
local function startCleanupLoop(): ()
	if cleanupThread then
		return
	end

	cleanupThread = task.spawn(function()
		while true do
			task.wait(CLEANUP_INTERVAL_SECONDS)
			performCleanup()
		end
	end)

	log("Cleanup loop started (interval: %ds)", CLEANUP_INTERVAL_SECONDS)
end

--- Stops the cleanup loop
local function stopCleanupLoop(): ()
	if cleanupThread then
		task.cancel(cleanupThread)
		cleanupThread = nil
		log("Cleanup loop stopped")
	end
end

--- Handles player leaving (cleanup their rate limit data)
local function onPlayerRemoving(player: Player): ()
	local userId = player.UserId
	if rateLimitData[userId] then
		rateLimitData[userId] = nil
		log("Cleaned up rate limit data for player %s (%d)", player.Name, userId)
	end
end

--[[
	PUBLIC API
]]

--- Checks if a player's action is within rate limit
--- @param player Player - The player performing the action
--- @param actionName string - Name of the action (e.g., "PurchaseItem", "SendChat")
--- @param cooldownSeconds number? - Cooldown duration (uses global or default if not provided)
--- @return boolean - True if action is allowed, false if rate limited
function RateLimiter.checkRateLimit(player: Player, actionName: string, cooldownSeconds: number?): boolean
	if not ValidationUtils.isValidPlayer(player) then
		warnlog("Invalid player for rate limit check")
		return false
	end

	if not ValidationUtils.isValidString(actionName) then
		warnlog("Invalid action name for rate limit check")
		return false
	end

	local userId = player.UserId
	local currentTime = tick()
	local cooldown = cooldownSeconds or getCooldownDuration(actionName)

	-- Get or create player's rate limit data
	local playerData = getOrCreatePlayerData(userId)
	local entry = getOrCreateEntry(playerData, actionName)

	-- Check if cooldown has expired
	local timeSinceLastCall = currentTime - entry.lastCallTime

	if timeSinceLastCall < cooldown then
		-- Rate limit violation
		entry.violationCount += 1

		-- Log warnings for suspicious activity
		if entry.violationCount == VIOLATION_THRESHOLD then
			warnlog(
				"Player %s (%d) has %d rate limit violations for action '%s'",
				player.Name,
				userId,
				entry.violationCount,
				actionName
			)
		elseif entry.violationCount >= SUSPICIOUS_THRESHOLD then
			warnlog(
				"SUSPICIOUS: Player %s (%d) has %d rate limit violations for action '%s' (possible exploit)",
				player.Name,
				userId,
				entry.violationCount,
				actionName
			)
		end

		return false
	end

	-- Update last call time
	entry.lastCallTime = currentTime

	-- Reset violation count on successful call (they've waited the cooldown)
	if entry.violationCount > 0 then
		entry.violationCount = 0
	end

	return true
end

--- Sets a global cooldown for a specific action
--- @param actionName string - Name of the action
--- @param cooldownSeconds number - Cooldown duration in seconds
function RateLimiter.setGlobalCooldown(actionName: string, cooldownSeconds: number): ()
	if not ValidationUtils.isValidString(actionName) then
		warnlog("Invalid action name for global cooldown")
		return
	end

	if not ValidationUtils.isValidNumber(cooldownSeconds) or cooldownSeconds < 0 then
		warnlog("Invalid cooldown duration: %s", tostring(cooldownSeconds))
		return
	end

	globalCooldowns[actionName] = cooldownSeconds
	log("Set global cooldown for '%s': %.2fs", actionName, cooldownSeconds)
end

--- Gets the cooldown duration for an action
--- @param actionName string - Name of the action
--- @return number - Cooldown duration in seconds
function RateLimiter.getCooldown(actionName: string): number
	return getCooldownDuration(actionName)
end

--- Manually resets rate limit for a player's action (admin/testing use)
--- @param player Player - The player
--- @param actionName string - Name of the action to reset
function RateLimiter.resetPlayerRateLimit(player: Player, actionName: string): ()
	if not ValidationUtils.isValidPlayer(player) then
		warnlog("Invalid player for rate limit reset")
		return
	end

	local userId = player.UserId
	local playerData = rateLimitData[userId]

	if playerData and playerData[actionName] then
		playerData[actionName] = nil
		log("Reset rate limit for player %s (%d), action '%s'", player.Name, userId, actionName)
	end
end

--- Gets statistics about rate limit violations
--- @param player Player - The player
--- @return {[string]: number} - Map of action names to violation counts
function RateLimiter.getPlayerViolations(player: Player): {[string]: number}
	if not ValidationUtils.isValidPlayer(player) then
		return {}
	end

	local userId = player.UserId
	local playerData = rateLimitData[userId]
	local violations: {[string]: number} = {}

	if playerData then
		for actionName, entry in playerData do
			if entry.violationCount > 0 then
				violations[actionName] = entry.violationCount
			end
		end
	end

	return violations
end

--- Clears all rate limit data (admin/testing use)
function RateLimiter.clearAllData(): ()
	rateLimitData = {}
	log("Cleared all rate limit data")
end

--- Gets total number of players being tracked
--- @return number
function RateLimiter.getTrackedPlayerCount(): number
	local count = 0
	for _ in rateLimitData do
		count += 1
	end
	return count
end

--------------------
-- Initialization --
--------------------
local function initialize(): ()
	-- Track player leaving events for cleanup
	resourceManager:trackConnection(Players.PlayerRemoving:Connect(onPlayerRemoving))

	-- Start cleanup loop
	startCleanupLoop()

	log("Initialized successfully")
end

initialize()

-------------
-- Cleanup --
-------------
game:BindToClose(function()
	stopCleanupLoop()
	resourceManager:cleanupAll()
	log("Shutdown cleanup completed")
end)

--------------
-- Return  --
--------------
return RateLimiter