--!strict

--[[
	GiftUI_ServerComms - Server communication layer for gift system

	This module handles all client-server communication for gifts:
	- Requests latest gift data from server
	- Notifies server when player clears gifts
	- Initiates gift sending process via remotes

	Returns: ServerComms module with server communication functions

	Usage:
		ServerComms.safeExecute = yourSafeExecuteFunction
		local gifts = ServerComms.requestLatestGiftDataFromServer(requestFunction)
		ServerComms.notifyServerOfGiftClearance(clearEvent)
		ServerComms.initiateGiftProcess(toggleEvent, targetUserId)
]]

-----------
-- Types --
-----------
export type ServerRefs = {
	requestGiftDataFunction: RemoteFunction,
	clearGiftDataEvent: RemoteEvent,
	toggleGiftUIEvent: RemoteEvent,
}

-----------
-- Module --
-----------
local ServerComms = {}

-- External dependencies (set by GiftUI)
ServerComms.safeExecute = nil :: (((() -> ()) -> boolean))?

--[[
	Requests latest gift data from server

	Invokes the RequestGifts RemoteFunction and returns the gift data array.
	Returns nil if the request fails or returns invalid data.

	@param requestFunction RemoteFunction - The request gifts function
	@return {any}? - Array of gift data, or nil on failure
]]
function ServerComms.requestLatestGiftDataFromServer(requestFunction: RemoteFunction): { any }?
	assert(requestFunction, "ServerComms.requestLatestGiftDataFromServer: requestFunction is required")
	assert(requestFunction:IsA("RemoteFunction"), "ServerComms.requestLatestGiftDataFromServer: requestFunction must be a RemoteFunction")

	local success, retrievedGiftData = pcall(function()
		return requestFunction:InvokeServer()
	end)

	if not success then
		warn("ServerComms.requestLatestGiftDataFromServer: Failed to invoke server")
		return nil
	end

	if not retrievedGiftData then
		return nil
	end

	return retrievedGiftData
end

--[[
	Notifies server that player has cleared their gifts

	Fires the ClearGifts RemoteEvent to mark all gifts as read/claimed.

	@param clearEvent RemoteEvent - The clear gifts event
]]
function ServerComms.notifyServerOfGiftClearance(clearEvent: RemoteEvent): ()
	assert(clearEvent, "ServerComms.notifyServerOfGiftClearance: clearEvent is required")
	assert(clearEvent:IsA("RemoteEvent"), "ServerComms.notifyServerOfGiftClearance: clearEvent must be a RemoteEvent")

	if ServerComms.safeExecute then
		ServerComms.safeExecute(function()
			clearEvent:FireServer()
		end)
	else
		clearEvent:FireServer()
	end
end

--[[
	Initiates gift process by toggling gift UI for target user

	Fires the ToggleGiftUI event to the server to start the gifting flow
	for the specified user ID.

	@param toggleEvent RemoteEvent - The toggle gift UI event
	@param targetUserId number - Target player's user ID
]]
function ServerComms.initiateGiftProcess(toggleEvent: RemoteEvent, targetUserId: number): ()
	assert(toggleEvent, "ServerComms.initiateGiftProcess: toggleEvent is required")
	assert(toggleEvent:IsA("RemoteEvent"), "ServerComms.initiateGiftProcess: toggleEvent must be a RemoteEvent")
	assert(typeof(targetUserId) == "number", "ServerComms.initiateGiftProcess: targetUserId must be a number")
	assert(targetUserId > 0, "ServerComms.initiateGiftProcess: targetUserId must be positive")

	if ServerComms.safeExecute then
		ServerComms.safeExecute(function()
			toggleEvent:FireServer(targetUserId)
		end)
	else
		toggleEvent:FireServer(targetUserId)
	end
end

return ServerComms