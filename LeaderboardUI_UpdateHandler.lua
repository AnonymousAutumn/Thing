--!strict

--------------
-- Constants --
--------------
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
	if not updateRemoteEvent or not updateRemoteEvent:IsA("RemoteEvent") or not clientHandler or not state then
		return false
	end

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