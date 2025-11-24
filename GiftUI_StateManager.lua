--!strict

--[[
	GiftUI_StateManager - State management for gift UI

	This module manages gift UI state and notification badges:
	- Updates gift notification badge display
	- Triggers text-to-speech notifications
	- Resets gift state when needed

	Returns: StateManager module with state management functions

	Usage:
		StateManager.safeExecute = yourSafeExecuteFunction
		StateManager.updateGiftNotificationBadgeDisplay(badgeElements, unreadCount)
		StateManager.resetGiftState(state)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------
-- Constants --
---------------
local WAIT_TIMEOUT = 10

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), "GiftUI_StateManager: Modules folder not found")
local TextToSpeech = require(Modules.Utilities.TextToSpeech)

-----------
-- Types --
-----------
export type BadgeElements = {
	giftCountNotificationLabel: TextLabel,
}

-----------
-- Module --
-----------
local StateManager = {}

-- External dependencies (set by GiftUI)
StateManager.safeExecute = nil :: (((() -> ()) -> boolean))?

--[[
	Updates the gift notification badge display

	Shows/hides the badge based on unread count and triggers TTS notification.

	@param badgeElements BadgeElements - UI elements for badge
	@param unreadGiftCount number - Number of unread gifts
]]
function StateManager.updateGiftNotificationBadgeDisplay(badgeElements: BadgeElements, unreadGiftCount: number): ()
	assert(badgeElements, "StateManager.updateGiftNotificationBadgeDisplay: badgeElements is required")
	assert(typeof(unreadGiftCount) == "number", "StateManager.updateGiftNotificationBadgeDisplay: unreadGiftCount must be a number")
	assert(unreadGiftCount >= 0, "StateManager.updateGiftNotificationBadgeDisplay: unreadGiftCount must be non-negative")

	if not StateManager.safeExecute then
		return
	end

	StateManager.safeExecute(function()
		if unreadGiftCount > 0 then
			badgeElements.giftCountNotificationLabel.Text = tostring(unreadGiftCount)
			badgeElements.giftCountNotificationLabel.Visible = true

			local suffix = (unreadGiftCount == 1) and "" or "s"
			local formattedSpeech = string.format("You have %d pending gift%s.", unreadGiftCount, suffix)
			TextToSpeech.Speak(formattedSpeech)
		else
			badgeElements.giftCountNotificationLabel.Visible = false
		end
	end)
end

--[[
	Resets gift state by clearing all tables and counters

	@param state any - GiftUIState object to reset
]]
function StateManager.resetGiftState(state: any): ()
	assert(state, "StateManager.resetGiftState: state is required")

	state.currentUnreadGiftCount = 0
	table.clear(state.cachedGiftDataFromServer)
	table.clear(state.activeGiftTimeDisplayEntries)
end

return StateManager