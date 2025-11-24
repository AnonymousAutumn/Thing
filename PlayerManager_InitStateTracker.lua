--!strict

--[[
	PlayerManager_InitStateTracker - Player initialization state tracking system

	What it does:
	- Tracks initialization state for each player (start time, completion, success/error)
	- Manages timeout threads for initialization deadlines
	- Provides scheduled cleanup of old initialization states
	- Tracks active initialization count
	- Cancels timeout threads on successful completion

	Returns: Module table with:
	- new() - Creates tracker instance
	- create(player) - Creates init state for player
	- scheduleTimeout(state, seconds, onTimeout) - Schedules timeout callback
	- cancelTimeout(state) - Cancels scheduled timeout
	- complete(state, success, error?) - Marks initialization complete
	- scheduleCleanup(userId, delaySeconds) - Schedules state cleanup
	- getState(userId) - Gets existing state
	- getActiveCount() - Gets count of active states
	- createWithTimeout(player, timeout?, onTimeout?) - Helper: create + schedule timeout

	Usage:
	local InitStateTracker = require(script.InitStateTracker)
	local tracker = InitStateTracker.new()
	local state = tracker:createWithTimeout(player, 30, handleTimeout)
	tracker:complete(state, true)
]]

-----------
-- Types --
-----------
export type InitState = {
	player: Player,
	startTime: number,
	completed: boolean,
	success: boolean,
	error: any?,
	timeoutThread: thread?,
}

export type InitTracker = {
	states: { [number]: InitState },
	create: (self: InitTracker, player: Player) -> InitState,
	scheduleTimeout: (self: InitTracker, state: InitState, timeoutSeconds: number, onTimeout: (InitState) -> ()) -> (),
	cancelTimeout: (self: InitTracker, state: InitState) -> (),
	complete: (self: InitTracker, state: InitState, success: boolean, error: any?) -> (),
	scheduleCleanup: (self: InitTracker, userId: number, delaySeconds: number) -> (),
	getState: (self: InitTracker, userId: number) -> InitState?,
	getActiveCount: (self: InitTracker) -> number,
}

---------------
-- Constants --
---------------
local DEFAULT_TIMEOUT = 30
local DEFAULT_CLEANUP_DELAY = 60

-----------
-- Module --
-----------
local InitStateTracker = {}
InitStateTracker.__index = InitStateTracker

--[[
	Creates a new initialization state tracker

	@return InitTracker
]]
function InitStateTracker.new(): InitTracker
	local self = setmetatable({}, InitStateTracker) :: any
	self.states = {}
	return self :: InitTracker
end

--[[
	Creates initialization state for a player

	@param player Player - Player to track
	@return InitState
]]
function InitStateTracker:create(player: Player): InitState
	local state: InitState = {
		player = player,
		startTime = os.time(),
		completed = false,
		success = false,
		error = nil,
		timeoutThread = nil,
	}

	self.states[player.UserId] = state
	return state
end

--[[
	Schedules a timeout for initialization

	@param state InitState - State to monitor
	@param timeoutSeconds number - Timeout duration
	@param onTimeout (InitState) -> () - Callback when timeout occurs
]]
function InitStateTracker:scheduleTimeout(
	state: InitState,
	timeoutSeconds: number,
	onTimeout: (InitState) -> ()
): ()
	local thread = task.delay(timeoutSeconds, function()
		if not state.completed then
			onTimeout(state)
		end
	end)

	state.timeoutThread = thread
end

--[[
	Cancels a scheduled timeout

	@param state InitState - State to cancel timeout for
]]
function InitStateTracker:cancelTimeout(state: InitState): ()
	if state.timeoutThread then
		pcall(function()
			task.cancel(state.timeoutThread)
		end)
		state.timeoutThread = nil
	end
end

--[[
	Marks initialization as complete

	@param state InitState - State to complete
	@param success boolean - Whether initialization succeeded
	@param error any? - Optional error information
]]
function InitStateTracker:complete(state: InitState, success: boolean, error: any?): ()
	state.completed = true
	state.success = success
	state.error = error

	self:cancelTimeout(state)
end

--[[
	Schedules cleanup of initialization state

	@param userId number - User ID to clean up
	@param delaySeconds number - Delay before cleanup
]]
function InitStateTracker:scheduleCleanup(userId: number, delaySeconds: number): ()
	task.delay(delaySeconds, function()
		self.states[userId] = nil
	end)
end

--[[
	Gets initialization state for a user

	@param userId number - User ID
	@return InitState? - State or nil if not found
]]
function InitStateTracker:getState(userId: number): InitState?
	return self.states[userId]
end

--[[
	Gets count of active initialization states

	@return number - Count of active states
]]
function InitStateTracker:getActiveCount(): number
	local count = 0
	for _ in self.states do
		count += 1
	end
	return count
end

--[[
	Helper: Creates state, schedules timeout, and returns state

	@param player Player - Player to initialize
	@param timeoutSeconds number? - Optional timeout (default: 30)
	@param onTimeout (InitState) -> ()? - Optional timeout callback
	@return InitState
]]
function InitStateTracker:createWithTimeout(
	player: Player,
	timeoutSeconds: number?,
	onTimeout: ((InitState) -> ())?
): InitState
	local state = self:create(player)

	if onTimeout then
		self:scheduleTimeout(state, timeoutSeconds or DEFAULT_TIMEOUT, onTimeout)
	end

	return state
end

return InitStateTracker