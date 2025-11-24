--!strict

--[[
	LeaderboardUI_StateManager - State management for leaderboard system

	This module manages state for multiple leaderboards:
	- Initializes and tracks state per leaderboard
	- Manages resource cleanup for each leaderboard
	- Handles state updates and tracking
	- Provides cleanup utilities

	Returns: StateManager module with state management functions

	Usage:
		local state = StateManager.initializeState("LeaderboardName")
		StateManager.updateState(state)
		StateManager.cleanup("LeaderboardName")
		StateManager.cleanupAll()
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------
-- Constants --
---------------
local TAG = "[LeaderboardUI_StateManager]"
local WAIT_TIMEOUT = 10

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), TAG .. " Modules folder not found")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

-----------
-- Types --
-----------
export type LeaderboardHandler = {
	processResults: (self: LeaderboardHandler, data: {any}) -> (),
	cleanup: (self: LeaderboardHandler) -> (),
	MainFrame: Frame,
}

export type LeaderboardState = {
	handler: LeaderboardHandler?,
	resourceManager: any, -- ResourceCleanup.ResourceManager
	isInitialized: boolean,
	lastUpdateTime: number?,
	updateCount: number,
}

-----------
-- Module --
-----------
local StateManager = {}

---------------
-- Variables --
---------------
local leaderboardStates: {[string]: LeaderboardState} = {}

---------------
-- Utilities --
---------------
local function safeExecute(func: () -> ()): boolean
	local success, errorMessage = pcall(func)
	if not success then
		warn("Error in StateManager.safeExecute:", errorMessage)
	end
	return success
end

------------------
-- Public API --
------------------
function StateManager.initializeState(leaderboardName: string): LeaderboardState
	assert(typeof(leaderboardName) == "string", "StateManager.initializeState: leaderboardName must be a string")
	assert(leaderboardName ~= "", "StateManager.initializeState: leaderboardName cannot be empty")

	if not leaderboardStates[leaderboardName] then
		leaderboardStates[leaderboardName] = {
			handler = nil,
			resourceManager = ResourceCleanup.new(),
			isInitialized = false,
			lastUpdateTime = nil,
			updateCount = 0,
		}
	end
	return leaderboardStates[leaderboardName]
end

function StateManager.getState(leaderboardName: string): LeaderboardState?
	assert(typeof(leaderboardName) == "string", "StateManager.getState: leaderboardName must be a string")
	return leaderboardStates[leaderboardName]
end

function StateManager.cleanup(leaderboardName: string): ()
	assert(typeof(leaderboardName) == "string", "StateManager.cleanup: leaderboardName must be a string")

	local state = leaderboardStates[leaderboardName]
	if not state then
		return
	end

	if state.handler and state.handler.cleanup then
		safeExecute(function()
			state.handler:cleanup()
		end)
	end

	state.resourceManager:cleanupAll()
	leaderboardStates[leaderboardName] = nil
end

function StateManager.cleanupAll(): ()
	for leaderboardName, _ in leaderboardStates do
		StateManager.cleanup(leaderboardName)
	end
end

function StateManager.updateState(state: LeaderboardState): ()
	assert(state, "StateManager.updateState: state is required")

	state.updateCount = state.updateCount + 1
	state.lastUpdateTime = os.time()
end

return StateManager