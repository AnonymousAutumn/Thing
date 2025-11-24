--!strict

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
	local success, retrievedGiftData = pcall(function()
		return requestFunction:InvokeServer()
	end)

	if not success or not retrievedGiftData then
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
	if ServerComms.safeExecute then
		ServerComms.safeExecute(function()
			clearEvent:FireServer()
		end)
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
	if ServerComms.safeExecute then
		ServerComms.safeExecute(function()
			toggleEvent:FireServer(targetUserId)
		end)
	end
end

return ServerComms