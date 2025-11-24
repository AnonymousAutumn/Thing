--!strict

---------------
-- Constants --
---------------
local CONFIG = {
	TURN_TIMEOUT = 30,
	TOKEN_DROP_COOLDOWN = 0.65,
	RESET_DELAY = 3,
}

-----------
-- Types --
-----------
export type TimeoutCallback = () -> ()

export type TimingManager = {
	currentTimeoutId: number,
	startTurnTimeout: (self: TimingManager, onTimeout: TimeoutCallback) -> (),
	cancelCurrentTimeout: (self: TimingManager) -> (),
	scheduleReset: (callback: TimeoutCallback) -> (),
	scheduleDropCooldown: (callback: TimeoutCallback) -> (),
}

-----------
-- Module --
-----------
local GameTiming = {}
GameTiming.__index = GameTiming

--[[
	Creates a new timing manager

	@return TimingManager
]]
function GameTiming.new(): TimingManager
	local self = setmetatable({}, GameTiming) :: any
	self.currentTimeoutId = 0
	return self :: TimingManager
end

--[[
	Starts a turn timeout

	Increments timeout ID and schedules callback after TURN_TIMEOUT seconds.
	If timeout is cancelled before firing, callback won't execute.

	@param onTimeout TimeoutCallback - Function to call when timeout expires
]]
function GameTiming:startTurnTimeout(onTimeout: TimeoutCallback): ()
	self.currentTimeoutId += 1
	local timeoutId = self.currentTimeoutId

	task.delay(CONFIG.TURN_TIMEOUT, function()
		if timeoutId == self.currentTimeoutId then
			onTimeout()
		end
	end)
end

--[[
	Cancels the current timeout by incrementing the ID

	Any pending timeout callbacks will see a mismatched ID and not execute.
]]
function GameTiming:cancelCurrentTimeout(): ()
	self.currentTimeoutId += 1
end

--[[
	Schedules a game reset after delay

	@param callback TimeoutCallback - Function to call after reset delay
]]
function GameTiming.scheduleReset(callback: TimeoutCallback): ()
	task.delay(CONFIG.RESET_DELAY, callback)
end

--[[
	Schedules token drop cooldown completion

	@param callback TimeoutCallback - Function to call after cooldown
]]
function GameTiming.scheduleDropCooldown(callback: TimeoutCallback): ()
	task.delay(CONFIG.TOKEN_DROP_COOLDOWN, callback)
end

--[[
	Gets the turn timeout duration

	@return number - Timeout duration in seconds
]]
function GameTiming.getTurnTimeout(): number
	return CONFIG.TURN_TIMEOUT
end

return GameTiming