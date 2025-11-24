--!strict

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
	ErrorDisplay.showErrorMessage(elements, errorMessageText)
	task.delay(ERROR_MESSAGE_DISPLAY_DURATION, function()
		ErrorDisplay.hideErrorMessage(elements)
	end)
end

return ErrorDisplay