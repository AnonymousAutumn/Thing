--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

---------------
-- Constants --
---------------
local TAG = "[UpdateScheduler]"

local INITIAL_UPDATE_DELAY = 5
local FAILURE_BACKOFF_MULTIPLIER = 2
local MAX_BACKOFF_MULTIPLIER = 8
local MAX_CONSECUTIVE_FAILURES = 5

local CLIENT_READY_MESSAGE = "Ready"

-----------
-- Module --
-----------
local UpdateScheduler = {}

-- Will be set by init.lua
UpdateScheduler.refreshLeaderboardDataAsync = nil :: ((any) -> boolean)?
UpdateScheduler.trackThread = nil :: ((thread) -> thread)?
UpdateScheduler.isShuttingDown = false

--[[
	Updates leaderboard state based on success/failure

	@param leaderboardState any - State to update
	@param success boolean - Whether update succeeded
]]
function UpdateScheduler.updateLeaderboardState(leaderboardState: any, success: boolean): ()
	if success then
		leaderboardState.consecutiveFailures = 0
		leaderboardState.lastUpdateTime = os.time()
		leaderboardState.lastUpdateSuccess = true
	else
		leaderboardState.consecutiveFailures = leaderboardState.consecutiveFailures + 1
		leaderboardState.lastUpdateSuccess = false
	end
end

--[[
	Calculates backoff multiplier based on failures

	@param consecutiveFailures number - Number of failures
	@return number - Backoff multiplier
]]
function UpdateScheduler.calculateBackoffMultiplier(consecutiveFailures: number): number
	return math.min(FAILURE_BACKOFF_MULTIPLIER ^ consecutiveFailures, MAX_BACKOFF_MULTIPLIER)
end

--[[
	Calculates update interval with backoff

	@param leaderboardState any - Leaderboard state
	@return number - Interval in seconds
]]
function UpdateScheduler.calculateUpdateInterval(leaderboardState: any): number
	local baseInterval = leaderboardState.systemConfig.LEADERBOARD_CONFIG.UPDATE_INTERVAL
	if leaderboardState.consecutiveFailures > 0 then
		local backoffMultiplier = UpdateScheduler.calculateBackoffMultiplier(leaderboardState.consecutiveFailures)
		return baseInterval * backoffMultiplier
	end
	return baseInterval
end

--[[
	Logs backoff warning if failures occurred

	@param leaderboardState any - Leaderboard state
	@param updateInterval number - Next update interval
]]
function UpdateScheduler.logBackoffWarning(leaderboardState: any, updateInterval: number): ()
	if leaderboardState.consecutiveFailures > 0 then
		warn(
			string.format(
				"%s %s failed %d times in a row; next update in %ds",
				TAG,
				leaderboardState.config.statisticName,
				leaderboardState.consecutiveFailures,
				updateInterval
			)
		)
	end
end

--[[
	Sets up leaderboard update loop

	@param leaderboardState any - Leaderboard state
]]
function UpdateScheduler.setupLeaderboardUpdateLoop(leaderboardState: any): ()
	if not UpdateScheduler.refreshLeaderboardDataAsync or not UpdateScheduler.trackThread then
		warn(TAG .. " Dependencies not set")
		return
	end

	local updateThread = task.spawn(function()
		task.wait(INITIAL_UPDATE_DELAY)
		while not UpdateScheduler.isShuttingDown do
			UpdateScheduler.refreshLeaderboardDataAsync(leaderboardState)
			local updateInterval = UpdateScheduler.calculateUpdateInterval(leaderboardState)
			UpdateScheduler.logBackoffWarning(leaderboardState, updateInterval)
			task.wait(updateInterval)
		end
	end)

	leaderboardState.updateThread = updateThread
	UpdateScheduler.trackThread(updateThread)
end

--[[
	Validates client ready message

	@param message any - Message to validate
	@return boolean - True if valid
]]
function UpdateScheduler.isValidClientReadyMessage(message: any): boolean
	return type(message) == "string" and message == CLIENT_READY_MESSAGE
end

--[[
	Handles client ready event

	@param requestingPlayer Player - Requesting player
	@param clientMessage any - Client message
	@param leaderboardState any - Leaderboard state
]]
function UpdateScheduler.handleClientReadyEvent(requestingPlayer: Player, clientMessage: any, leaderboardState: any): ()
	if UpdateScheduler.isShuttingDown then
		return
	end
	if not ValidationUtils.isValidPlayer(requestingPlayer) then
		return
	end
	if not UpdateScheduler.isValidClientReadyMessage(clientMessage) then
		return
	end

	if not UpdateScheduler.refreshLeaderboardDataAsync then
		return
	end

	task.spawn(function()
		UpdateScheduler.refreshLeaderboardDataAsync(leaderboardState)
	end)
end

return UpdateScheduler