--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
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
	state.currentUnreadGiftCount = 0
	table.clear(state.cachedGiftDataFromServer)
	table.clear(state.activeGiftTimeDisplayEntries)
end

return StateManager