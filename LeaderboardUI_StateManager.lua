--!strict

----------------
-- References --
----------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
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
	return leaderboardStates[leaderboardName]
end

function StateManager.cleanup(leaderboardName: string): ()
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
	state.updateCount = state.updateCount + 1
	state.lastUpdateTime = os.time()
end

return StateManager