--!strict

--[[
	GameUI_GameStateManager

	Manages game UI state including timeout sequences, status visibility, and resource cleanup.
	Centralizes state management for the GameUI module hierarchy.

	Returns: Table with state management functions:
		- trackConnection, trackTween, trackTask: Resource tracking
		- cancelAllTweens, cancelAllTasks, disconnectAllConnections: Cleanup
		- incrementTimeoutSequence, incrementStatusSequence: Sequence management
		- resetState: Resets UI state variables

	Usage:
		local GameStateManager = require(script.GameUI_GameStateManager)
		GameStateManager.trackConnection(event:Connect(handler))
		GameStateManager.incrementTimeoutSequence()
		GameStateManager.cancelAllTasks()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

-----------
-- Types --
-----------
export type TimeoutHandler = {
	cancel: () -> (),
	isActive: () -> boolean,
}

export type GameState = {
	timeoutSequenceId: number,
	activeTimeoutHandler: TimeoutHandler?,
	autoHideTask: thread?,
	statusSequenceId: number,
	ignoreUpdatesUntil: number,

	isStatusVisible: boolean,
	previousStatusText: string,

	resourceManager: any, -- ResourceCleanup.ResourceManager
}

-----------
-- Module --
-----------
local GameStateManager = {}

-- The global game state (singleton)
GameStateManager.state = {
	timeoutSequenceId = 0,
	activeTimeoutHandler = nil,
	autoHideTask = nil,
	statusSequenceId = 0,
	ignoreUpdatesUntil = 0,

	isStatusVisible = false,
	previousStatusText = "",

	resourceManager = ResourceCleanup.new(),
} :: GameState

--[[
	Safe execution helper

	@param func () -> () - Function to execute
	@param errorMessage string - Error message to warn
	@return boolean - True if successful
]]
local function safeExecute(func: () -> (), errorMessage: string): boolean
	local success, errorDetails = pcall(func)
	if not success then
		warn(errorMessage, errorDetails)
	end
	return success
end

--[[
	Tracks a connection

	@param connection RBXScriptConnection - Connection to track
	@return RBXScriptConnection - Same connection
]]
function GameStateManager.trackConnection(connection: RBXScriptConnection): RBXScriptConnection
	return GameStateManager.state.resourceManager:trackConnection(connection)
end

--[[
	Tracks a tween

	@param tween Tween - Tween to track
	@return Tween - Same tween
]]
function GameStateManager.trackTween(tween: Tween): Tween
	GameStateManager.state.resourceManager:trackTween(tween)
	return tween
end

--[[
	Tracks a task

	@param threadHandle thread - Task to track
	@return thread - Same task
]]
function GameStateManager.trackTask(threadHandle: thread): thread
	GameStateManager.state.resourceManager:trackThread(threadHandle)
	return threadHandle
end

--[[
	Cancels all tracked tweens
]]
function GameStateManager.cancelAllTweens(): ()
	GameStateManager.state.resourceManager:cleanupTweens()
end

--[[
	Cancels all tracked tasks
]]
function GameStateManager.cancelAllTasks(): ()
	GameStateManager.state.resourceManager:cleanupThreads()
end

--[[
	Disconnects all tracked connections
]]
function GameStateManager.disconnectAllConnections(): ()
	GameStateManager.state.resourceManager:cleanupConnections()
end

--[[
	Resets game state variables
]]
function GameStateManager.resetState(): ()
	GameStateManager.state.isStatusVisible = false
	GameStateManager.state.previousStatusText = ""
end

--[[
	Increments timeout sequence ID
]]
function GameStateManager.incrementTimeoutSequence(): ()
	GameStateManager.state.timeoutSequenceId += 1
end

--[[
	Increments status sequence ID
]]
function GameStateManager.incrementStatusSequence(): ()
	GameStateManager.state.statusSequenceId += 1
end

--[[
	Gets current timeout sequence ID

	@return number - Sequence ID
]]
function GameStateManager.getTimeoutSequenceId(): number
	return GameStateManager.state.timeoutSequenceId
end

--[[
	Gets current status sequence ID

	@return number - Sequence ID
]]
function GameStateManager.getStatusSequenceId(): number
	return GameStateManager.state.statusSequenceId
end

return GameStateManager