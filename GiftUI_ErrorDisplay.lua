--!strict

--[[
	GiftUI_ErrorDisplay - Error message display management

	This module manages error message display for the gift sending interface:
	- Shows error messages with input disable
	- Auto-hides error messages after a timeout
	- Manages UI element visibility during error states

	Returns: ErrorDisplay module with message display functions

	Usage:
		ErrorDisplay.safeExecute = yourSafeExecuteFunction
		ErrorDisplay.displayTemporaryErrorMessage(elements, "Error message")
]]

---------------
-- Constants --
---------------
local ERROR_MESSAGE_DISPLAY_DURATION = 3 -- seconds

-----------
-- Types --
-----------
export type ErrorDisplayElements = {
	errorMessageDisplayFrame: Frame,
	errorMessageLabel: TextLabel,
	usernameInputTextBox: TextBox,
	giftSendConfirmationButton: GuiButton,
}

-----------
-- Module --
-----------
local ErrorDisplay = {}

-- External dependencies (set by GiftUI)
ErrorDisplay.safeExecute = nil :: (((() -> ()) -> boolean))?

--[[
	Shows error message and disables input

	@param elements ErrorDisplayElements - UI elements
	@param errorMessageText string - Error message to display
]]
function ErrorDisplay.showErrorMessage(elements: ErrorDisplayElements, errorMessageText: string): ()
	assert(elements, "ErrorDisplay.showErrorMessage: elements is required")
	assert(typeof(errorMessageText) == "string", "ErrorDisplay.showErrorMessage: errorMessageText must be a string")

	if not ErrorDisplay.safeExecute then
		return
	end

	ErrorDisplay.safeExecute(function()
		elements.errorMessageDisplayFrame.Visible = true
		elements.errorMessageLabel.Text = errorMessageText
		elements.usernameInputTextBox.Visible = false
		elements.giftSendConfirmationButton.Active = false
	end)
end

--[[
	Hides error message and re-enables input

	@param elements ErrorDisplayElements - UI elements
]]
function ErrorDisplay.hideErrorMessage(elements: ErrorDisplayElements): ()
	assert(elements, "ErrorDisplay.hideErrorMessage: elements is required")

	if not ErrorDisplay.safeExecute then
		return
	end

	ErrorDisplay.safeExecute(function()
		elements.errorMessageDisplayFrame.Visible = false
		elements.errorMessageLabel.Text = ""
		elements.usernameInputTextBox.Visible = true
		elements.giftSendConfirmationButton.Active = true
	end)
end

--[[
	Displays temporary error message that auto-hides

	Shows error message for ERROR_MESSAGE_DISPLAY_DURATION seconds,
	then automatically hides it.

	@param elements ErrorDisplayElements - UI elements
	@param errorMessageText string - Error message to display
]]
function ErrorDisplay.displayTemporaryErrorMessage(elements: ErrorDisplayElements, errorMessageText: string): ()
	assert(elements, "ErrorDisplay.displayTemporaryErrorMessage: elements is required")
	assert(typeof(errorMessageText) == "string", "ErrorDisplay.displayTemporaryErrorMessage: errorMessageText must be a string")

	ErrorDisplay.showErrorMessage(elements, errorMessageText)
	task.delay(ERROR_MESSAGE_DISPLAY_DURATION, function()
		ErrorDisplay.hideErrorMessage(elements)
	end)
end

return ErrorDisplay