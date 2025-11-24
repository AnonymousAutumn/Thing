--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

local GameStateManager = require(script.Parent.GameStateManager)
local StatusAnimator = require(script.Parent.StatusAnimator)

type TimeoutHandler = GameStateManager.TimeoutHandler

---------------
-- Constants --
---------------
local MESSAGE_FORMAT_TIMEOUT = "Time Left: %d"

-----------
-- Module --
-----------
local TimeoutManager = {}

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
	Updates timeout display text

	@param secondsLeft number - Seconds remaining
]]
local function updateTimeoutDisplay(secondsLeft: number): ()
	safeExecute(function()
		StatusAnimator.updateStatusText(string.format(MESSAGE_FORMAT_TIMEOUT, secondsLeft))
	end, "Error updating timeout text")
end

--[[
	Checks if timeout is still active

	@param handlerId number - Timeout handler ID
	@param isCancelled boolean - Whether cancelled
	@return boolean - True if active
]]
local function isTimeoutActive(handlerId: number, isCancelled: boolean): boolean
	return not isCancelled and GameStateManager.getTimeoutSequenceId() == handlerId
end

--[[
	Runs the timeout countdown loop

	@param timeRemaining number - Initial time
	@param handlerId number - Handler ID
	@param isCancelledRef {value: boolean} - Cancellation flag
]]
local function runTimeoutCountdown(timeRemaining: number, handlerId: number, isCancelledRef: { value: boolean }): ()
	local secondsLeft = timeRemaining
	while secondsLeft > 0 and isTimeoutActive(handlerId, isCancelledRef.value) do
		updateTimeoutDisplay(secondsLeft)
		task.wait(1)
		secondsLeft -= 1
	end
end

--[[
	Finalizes timeout with message and hide

	@param finalMessage string - Final message to display
	@param handlerId number - Handler ID
	@param isCancelledRef {value: boolean} - Cancellation flag
]]
local function finalizeTimeout(finalMessage: string, handlerId: number, isCancelledRef: { value: boolean }): ()
	if isTimeoutActive(handlerId, isCancelledRef.value) then
		StatusAnimator.updateStatusText(finalMessage)
		StatusAnimator.hideStatusInterface()
	end
end

--[[
	Creates a timeout handler

	@param timeRemaining number - Time in seconds
	@param finalMessage string - Message to show when done
	@return TimeoutHandler - Handler with cancel/isActive methods
]]
function TimeoutManager.createTimeoutHandler(timeRemaining: number, finalMessage: string): TimeoutHandler
	if not (ValidationUtils.isValidNumber(timeRemaining) and timeRemaining >= 0) or not ValidationUtils.isValidString(finalMessage) then
		return {
			cancel = function() end,
			isActive = function()
				return false
			end,
		}
	end

	local handlerId = GameStateManager.getTimeoutSequenceId()
	local isCancelledRef = { value = false }

	local function cancel(): ()
		isCancelledRef.value = true
	end

	local function isActive(): boolean
		return isTimeoutActive(handlerId, isCancelledRef.value)
	end

	local timeoutTask = task.spawn(function()
		runTimeoutCountdown(timeRemaining, handlerId, isCancelledRef)
		finalizeTimeout(finalMessage, handlerId, isCancelledRef)
	end)

	GameStateManager.trackTask(timeoutTask)

	return {
		cancel = cancel,
		isActive = isActive,
	}
end

--[[
	Cancels the active timeout handler
]]
function TimeoutManager.cancelTimeoutHandler(): ()
	if not GameStateManager.state.activeTimeoutHandler then
		return
	end

	safeExecute(function()
		if GameStateManager.state.activeTimeoutHandler and GameStateManager.state.activeTimeoutHandler.isActive() then
			GameStateManager.state.activeTimeoutHandler.cancel()
		end
	end, "Error cancelling timeout handler")

	GameStateManager.state.activeTimeoutHandler = nil
end

return TimeoutManager