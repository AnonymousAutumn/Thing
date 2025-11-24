--!strict

--------------
-- Services --
--------------
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local GameConfig = require(Configuration.GameConfig)

-----------
-- Types --
-----------
export type LeaderboardUpdate = {
	UserId: number,
	Stat: string,
	Value: number,
}

export type MessageHandler = (message: any) -> ()

export type SyncManager = {
	connection: RBXScriptConnection?,
	subscribe: (self: SyncManager, topic: string, handler: MessageHandler, maxRetries: number?) -> boolean,
	disconnect: (self: SyncManager) -> (),
	isConnected: (self: SyncManager) -> boolean,
}

---------------
-- Constants --
---------------
local RETRY_DELAY = 5
local MAX_RETRY_ATTEMPTS = 3

local VALID_STATISTICS = { "Donated", "Raised", "Wins" }

-----------
-- Module --
-----------
local CrossServerSync = {}
CrossServerSync.__index = CrossServerSync

--[[
	Creates a new cross-server sync manager

	@return SyncManager
]]
function CrossServerSync.new(): SyncManager
	local self = setmetatable({}, CrossServerSync) :: any
	self.connection = nil
	return self :: SyncManager
end

--[[
	Validates statistic name

	@param statisticName string - Statistic to validate
	@return boolean
]]
local function isValidStatistic(statisticName: string): boolean
	for _, name in VALID_STATISTICS do
		if name == statisticName then
			return true
		end
	end
	return false
end

--[[
	Validates statistic value

	@param value any - Value to validate
	@return boolean
]]
local function isValidValue(value: any): boolean
	return type(value) == "number"
end

--[[
	Extracts update data from message

	@param message any - Raw message
	@return LeaderboardUpdate?
]]
local function extractUpdateData(message: any): LeaderboardUpdate?
	if type(message) ~= "table" then
		return nil
	end

	local payload = message.Data or message
	if type(payload) ~= "table" then
		return nil
	end

	return payload
end

--[[
	Validates leaderboard update message

	@param message any - Message to validate
	@return boolean - True if valid
]]
function CrossServerSync.validateUpdateMessage(message: any): boolean
	local updateData = extractUpdateData(message)
	if not updateData then
		return false
	end

	if not ValidationUtils.isValidUserId(updateData.UserId) then
		return false
	end

	if type(updateData.Stat) ~= "string" or not isValidStatistic(updateData.Stat) then
		return false
	end

	if not isValidValue(updateData.Value) then
		return false
	end

	return true
end

--[[
	Extracts validated update data from message

	@param message any - Raw message
	@return LeaderboardUpdate? - Update data or nil if invalid
]]
function CrossServerSync.extractUpdate(message: any): LeaderboardUpdate?
	if not CrossServerSync.validateUpdateMessage(message) then
		return nil
	end

	return extractUpdateData(message)
end

--[[
	Calculates retry delay based on attempt number

	@param attemptNumber number - Current attempt
	@return number - Delay in seconds
]]
local function calculateRetryDelay(attemptNumber: number): number
	return RETRY_DELAY * attemptNumber
end

--[[
	Establishes MessagingService subscription with retry

	@param topic string - Topic to subscribe to
	@param handler MessageHandler - Message handler function
	@param attemptNumber number - Current attempt number
	@param maxRetries number - Maximum retry attempts
	@return RBXScriptConnection? - Connection or nil if failed
]]
local function establishConnection(
	topic: string,
	handler: MessageHandler,
	attemptNumber: number,
	maxRetries: number
): RBXScriptConnection?
	if attemptNumber > maxRetries then
		warn(string.format("[CrossServerSync] Failed to connect after %d attempts", maxRetries))
		return nil
	end

	local success, result = pcall(function()
		return MessagingService:SubscribeAsync(topic, handler)
	end)

	if success then
		print(string.format("[CrossServerSync] Connected to topic: %s", topic))
		return result
	else
		warn(string.format("[CrossServerSync] Connection failed (attempt %d/%d): %s", attemptNumber, maxRetries, tostring(result)))
		task.wait(calculateRetryDelay(attemptNumber))

		if attemptNumber < maxRetries then
			warn(string.format("[CrossServerSync] Retrying connection (attempt %d)...", attemptNumber + 1))
			return establishConnection(topic, handler, attemptNumber + 1, maxRetries)
		end

		return nil
	end
end

--[[
	Subscribes to a messaging topic with retry logic

	@param topic string - Topic to subscribe to
	@param handler MessageHandler - Message handler
	@param maxRetries number? - Max retry attempts (default: 3)
	@return boolean - True if successfully subscribed
]]
function CrossServerSync:subscribe(topic: string, handler: MessageHandler, maxRetries: number?): boolean
	local retries = maxRetries or MAX_RETRY_ATTEMPTS

	self.connection = establishConnection(topic, handler, 1, retries)

	return self.connection ~= nil
end

--[[
	Disconnects from messaging service

]]
function CrossServerSync:disconnect(): ()
	if self.connection then
		pcall(function()
			self.connection:Disconnect()
		end)
		self.connection = nil
	end
end

--[[
	Checks if connected to messaging service

	@return boolean
]]
function CrossServerSync:isConnected(): boolean
	return self.connection ~= nil
end

--[[
	Helper: Creates sync manager and subscribes to leaderboard updates

	@param handler MessageHandler - Update handler
	@return SyncManager - Connected sync manager
]]
function CrossServerSync.createLeaderboardSync(handler: MessageHandler): SyncManager
	local sync = CrossServerSync.new()
	local topic = GameConfig.MESSAGING_SERVICE_CONFIG.LEADERBOARD_UPDATE

	sync:subscribe(topic, handler)

	return sync
end

return CrossServerSync