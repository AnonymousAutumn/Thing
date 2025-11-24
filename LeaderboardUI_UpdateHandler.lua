--!strict

--[[
	LeaderboardUI_UpdateHandler - Update handling for leaderboards

	This module manages leaderboard update events:
	- Connects to server update RemoteEvents
	- Processes incoming leaderboard data
	- Signals client readiness to server
	- Tracks update connections for cleanup

	Returns: UpdateHandler module with update setup functions

	Usage:
		UpdateHandler.setupUpdates(
			updateRemoteEvent,
			clientHandler,
			state,
			updateStateFunc
		)
]]

--------------
-- Constants --
--------------
local TAG = "[LeaderboardUI_UpdateHandler]"
local CLIENT_READY_MESSAGE = "Ready"

-----------
-- Types --
-----------
type LeaderboardHandler = {
	processResults: (self: LeaderboardHandler, data: {any}) -> (),
	cleanup: (self: LeaderboardHandler) -> (),
	MainFrame: Frame,
}

type LeaderboardState = {
	handler: LeaderboardHandler?,
	resourceManager: any,
	isInitialized: boolean,
	lastUpdateTime: number?,
	updateCount: number,
}

-----------
-- Module --
-----------
local UpdateHandler = {}

---------------
-- Utilities --
---------------
local function safeExecute(func: () -> ()): boolean
	local success, errorMessage = pcall(func)
	if not success then
		warn("Error in UpdateHandler.safeExecute:", errorMessage)
	end
	return success
end

local function handleLeaderboardUpdate(
	serverLeaderboardData: {any},
	clientHandler: LeaderboardHandler,
	updateStateFunc: (state: LeaderboardState) -> ()
): ()
	if typeof(serverLeaderboardData) ~= "table" then
		return
	end

	safeExecute(function()
		clientHandler:processResults(serverLeaderboardData)
	end)
end

------------------
-- Public API --
------------------
function UpdateHandler.setupUpdates(
	updateRemoteEvent: RemoteEvent,
	clientHandler: LeaderboardHandler,
	state: LeaderboardState,
	updateStateFunc: (state: LeaderboardState) -> ()
): boolean
	assert(updateRemoteEvent, "UpdateHandler.setupUpdates: updateRemoteEvent is required")
	assert(updateRemoteEvent:IsA("RemoteEvent"), "UpdateHandler.setupUpdates: updateRemoteEvent must be a RemoteEvent")
	assert(clientHandler, "UpdateHandler.setupUpdates: clientHandler is required")
	assert(state, "UpdateHandler.setupUpdates: state is required")
	assert(updateStateFunc, "UpdateHandler.setupUpdates: updateStateFunc is required")

	return safeExecute(function()
		local updateConnection = updateRemoteEvent.OnClientEvent:Connect(function(serverLeaderboardData)
			updateStateFunc(state)
			handleLeaderboardUpdate(serverLeaderboardData, clientHandler, updateStateFunc)
		end)
		state.resourceManager:trackConnection(updateConnection)

		-- Signal server that client is ready
		updateRemoteEvent:FireServer(CLIENT_READY_MESSAGE)
	end)
end

return UpdateHandler