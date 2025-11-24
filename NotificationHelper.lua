--!strict

-----------
-- Types --
-----------
export type NotificationType = "Success" | "Warning" | "Error" | "Info"

---------------
-- Constants --
---------------
local TAG = "[NotificationHelper]"

-- Standard notification types
local NOTIFICATION_TYPES = {
	SUCCESS = "Success",
	WARNING = "Warning",
	ERROR = "Error",
	INFO = "Info",
}

----------------------
-- Private Functions --
----------------------

-- Logs a warning message
local function logWarning(formatString: string, ...): ()
	warn(string.format("%s %s", TAG, string.format(formatString, ...)))
end

---------------
-- Public API --
---------------
local NotificationHelper = {}

-- Exported notification type constants
NotificationHelper.Types = NOTIFICATION_TYPES

--[[
	Sends a notification via a BindableEvent safely

	@param event - The BindableEvent to fire
	@param message - The notification message
	@param notificationType - The type of notification (Success, Warning, Error, Info)
	@return boolean - True if notification was sent successfully
]]
function NotificationHelper.send(
	event: BindableEvent,
	message: string,
	notificationType: NotificationType?
): boolean
	local success, errorMessage = pcall(function()
		event:Fire(message, notificationType or NOTIFICATION_TYPES.INFO)
	end)

	if not success then
		logWarning("Failed to send notification: %s", tostring(errorMessage))
		return false
	end

	return true
end

--[[
	Sends a success notification

	@param event - The BindableEvent to fire
	@param message - The notification message
	@return boolean - True if notification was sent successfully
]]
function NotificationHelper.sendSuccess(event: BindableEvent, message: string): boolean
	return NotificationHelper.send(event, message, NOTIFICATION_TYPES.SUCCESS)
end

--[[
	Sends a warning notification

	@param event - The BindableEvent to fire
	@param message - The notification message
	@return boolean - True if notification was sent successfully
]]
function NotificationHelper.sendWarning(event: BindableEvent, message: string): boolean
	return NotificationHelper.send(event, message, NOTIFICATION_TYPES.WARNING)
end

--[[
	Sends an error notification

	@param event - The BindableEvent to fire
	@param message - The notification message
	@return boolean - True if notification was sent successfully
]]
function NotificationHelper.sendError(event: BindableEvent, message: string): boolean
	return NotificationHelper.send(event, message, NOTIFICATION_TYPES.ERROR)
end

--[[
	Sends an info notification

	@param event - The BindableEvent to fire
	@param message - The notification message
	@return boolean - True if notification was sent successfully
]]
function NotificationHelper.sendInfo(event: BindableEvent, message: string): boolean
	return NotificationHelper.send(event, message, NOTIFICATION_TYPES.INFO)
end

--------------
-- Return  --
--------------
return NotificationHelper