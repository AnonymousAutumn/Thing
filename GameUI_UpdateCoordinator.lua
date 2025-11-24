--!strict

--[[
	GameUI_UpdateCoordinator

	Coordinates game UI updates with validation, auto-hide scheduling, and game-ending detection.
	Main handler for RemoteEvent UI update messages.

	Returns: Table with update coordination functions:
		- handleGameUIUpdate: Main entry point for UI updates
		- validateTurnUpdateParams: Input validation
		- displayStatusIfChanged: Shows status if different from previous
		- scheduleAutoHide, cancelAutoHideTask: Auto-hide management
		- isGameEndingMessage: Detects game-over conditions
		- setIgnoreUpdatesPeriod, shouldIgnoreUpdates: Update throttling

	Usage:
		local UpdateCoordinator = require(script.GameUI_UpdateCoordinator)
		remoteEvent.OnClientEvent:Connect(UpdateCoordinator.handleGameUIUpdate)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

local GameStateManager = require(script.Parent.GameStateManager)
local StatusAnimator = require(script.Parent.StatusAnimator)
local TimeoutManager = require(script.Parent.TimeoutManager)

---------------
-- Constants --
---------------
local CONFIG = {
	STATUS_MESSAGE_DISPLAY_DURATION = 3,
	IGNORE_UPDATES_BUFFER = 0.1,

	GAME_ENDING_PATTERNS = {
		"timed out",
		"stopped playing",
		"won!",
		"draw",
	},
}

-----------
-- Module --
-----------
local UpdateCoordinator = {}

--[[
	Gets current time

	@return number - Current time
]]
local function getCurrentTime(): number
	return os.clock()
end

--[[
	Safe execution helper

	@param func () -> () - Function to execute
	@param errorMessage string - Error message to warn
	@return boolean - True if successful
]]
local function safeExecute(func: () -> (), errorMessage: string): boolean
	local success, errorDetails = pcall(func)
	if not success then
		warn(errorMessage, errorDetails)
	end
	return success
end

--[[
	Validates turn update parameters

	@param statusText string - Status text
	@param timeoutSeconds number? - Optional timeout
	@return boolean - True if valid
]]
function UpdateCoordinator.validateTurnUpdateParams(statusText: string, timeoutSeconds: number?): boolean
	if not ValidationUtils.isValidString(statusText) then
		return false
	end
	if timeoutSeconds ~= nil and not (ValidationUtils.isValidNumber(timeoutSeconds) and timeoutSeconds >= 0) then
		return false
	end
	return true
end

--[[
	Displays status if changed from previous

	@param message string - Message to display
]]
function UpdateCoordinator.displayStatusIfChanged(message: string): ()
	if not ValidationUtils.isValidString(message) then
		return
	end

	if message ~= StatusAnimator.getPreviousStatusText() or not StatusAnimator.isStatusVisible() then
		StatusAnimator.updateStatusText(message)
		StatusAnimator.showStatusInterface()
	end
end

--[[
	Cancels auto-hide task
]]
function UpdateCoordinator.cancelAutoHideTask(): ()
	if not GameStateManager.state.autoHideTask then
		return
	end

	GameStateManager.incrementStatusSequence()

	safeExecute(function()
		task.cancel(GameStateManager.state.autoHideTask)
	end, "Error cancelling auto-hide task")

	GameStateManager.state.autoHideTask = nil
end

--[[
	Schedules automatic hiding of status
]]
function UpdateCoordinator.scheduleAutoHide(): ()
	UpdateCoordinator.cancelAutoHideTask()
	GameStateManager.incrementStatusSequence()
	local currentSequenceId = GameStateManager.getStatusSequenceId()

	GameStateManager.state.autoHideTask = task.delay(CONFIG.STATUS_MESSAGE_DISPLAY_DURATION, function()
		if GameStateManager.getStatusSequenceId() == currentSequenceId then
			StatusAnimator.hideStatusInterface()
			StatusAnimator.updateStatusText(nil)
			GameStateManager.state.autoHideTask = nil
		end
	end)

	GameStateManager.trackTask(GameStateManager.state.autoHideTask)
end

--[[
	Checks if message indicates game is ending

	@param message string - Message to check
	@return boolean - True if game ending
]]
function UpdateCoordinator.isGameEndingMessage(message: string): boolean
	if not ValidationUtils.isValidString(message) then
		return false
	end

	for _, pattern in CONFIG.GAME_ENDING_PATTERNS do
		if string.find(message, pattern) then
			return true
		end
	end
	return false
end

--[[
	Sets ignore updates period
]]
function UpdateCoordinator.setIgnoreUpdatesPeriod(): ()
	GameStateManager.state.ignoreUpdatesUntil = getCurrentTime() + CONFIG.STATUS_MESSAGE_DISPLAY_DURATION + CONFIG.IGNORE_UPDATES_BUFFER
end

--[[
	Checks if updates should be ignored

	@return boolean - True if should ignore
]]
function UpdateCoordinator.shouldIgnoreUpdates(): boolean
	return getCurrentTime() < GameStateManager.state.ignoreUpdatesUntil
end

--[[
	Handles empty status case

	@param hideExitButton boolean - Whether to hide exit button
	@param statusText string - Status text
	@return boolean - True if handled
]]
function UpdateCoordinator.handleEmptyStatus(hideExitButton: boolean, statusText: string): boolean
	if hideExitButton and statusText == "" then
		StatusAnimator.updateStatusText(nil)
		StatusAnimator.hideStatusInterface()
		return true
	end
	return false
end

--[[
	Prepares for turn update

	@param hideExitButton boolean - Whether to hide exit button
]]
function UpdateCoordinator.prepareForTurnUpdate(hideExitButton: boolean): ()
	GameStateManager.incrementTimeoutSequence()
	TimeoutManager.cancelTimeoutHandler()
	UpdateCoordinator.cancelAutoHideTask()
	StatusAnimator.setExitButtonVisibility(not hideExitButton)
end

--[[
	Handles game UI update

	@param statusText string - Status text
	@param timeoutSeconds number? - Optional timeout
	@param hideExitButton boolean - Whether to hide exit button
]]
function UpdateCoordinator.handleGameUIUpdate(statusText: string, timeoutSeconds: number?, hideExitButton: boolean): ()
	if not UpdateCoordinator.validateTurnUpdateParams(statusText, timeoutSeconds) then
		return
	end

	safeExecute(function()
		if UpdateCoordinator.shouldIgnoreUpdates() then
			return
		end

		UpdateCoordinator.prepareForTurnUpdate(hideExitButton)

		if UpdateCoordinator.handleEmptyStatus(hideExitButton, statusText) then
			return
		end

		UpdateCoordinator.displayStatusIfChanged(statusText)

		if timeoutSeconds then
			GameStateManager.state.activeTimeoutHandler = TimeoutManager.createTimeoutHandler(timeoutSeconds, statusText)
		else
			if UpdateCoordinator.isGameEndingMessage(statusText) then
				UpdateCoordinator.setIgnoreUpdatesPeriod()
			end
			UpdateCoordinator.scheduleAutoHide()
		end
	end, "Error handling game UI update")
end

return UpdateCoordinator