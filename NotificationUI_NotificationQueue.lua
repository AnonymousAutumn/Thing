--!strict

---------------
-- Constants --
---------------
local DISPLAY_DURATION = 4 -- seconds

-----------
-- Types --
-----------
export type NotificationData = {
	frame: Frame,
	textLabel: TextLabel,
	createdTime: number,
}

export type Queue = {
	notifications: { Frame },
	add: (self: Queue, frame: Frame) -> (),
	remove: (self: Queue, frame: Frame) -> (),
	getAll: (self: Queue) -> { Frame },
	getCount: (self: Queue) -> number,
	clear: (self: Queue) -> (),
	scheduleRemoval: (self: Queue, frame: Frame, textLabel: TextLabel, onRemove: (Frame, TextLabel) -> ()) -> (),
}

-----------
-- Module --
-----------
local NotificationQueue = {}
NotificationQueue.__index = NotificationQueue

--[[
	Creates a new notification queue

	@return Queue
]]
function NotificationQueue.new(): Queue
	local self = setmetatable({}, NotificationQueue) :: any
	self.notifications = {}
	return self :: Queue
end

--[[
	Adds a notification to the queue

	@param frame Frame - Notification frame to add
]]
function NotificationQueue:add(frame: Frame): ()
	table.insert(self.notifications, frame)
end

--[[
	Removes a notification from the queue

	@param frame Frame - Notification frame to remove
	@return boolean - True if removed, false if not found
]]
function NotificationQueue:remove(frame: Frame): boolean
	for index, activeFrame in self.notifications do
		if activeFrame == frame then
			table.remove(self.notifications, index)
			return true
		end
	end
	return false
end

--[[
	Gets all active notifications

	@return {Frame} - Array of notification frames
]]
function NotificationQueue:getAll(): { Frame }
	return self.notifications
end

--[[
	Gets count of active notifications

	@return number - Count
]]
function NotificationQueue:getCount(): number
	return #self.notifications
end

--[[
	Clears all notifications from queue

]]
function NotificationQueue:clear(): ()
	self.notifications = {}
end

--[[
	Schedules automatic removal of notification after display duration

	@param frame Frame - Notification frame
	@param textLabel TextLabel - Text label for animation
	@param onRemove (Frame, TextLabel) -> () - Callback before removal
]]
function NotificationQueue:scheduleRemoval(
	frame: Frame,
	textLabel: TextLabel,
	onRemove: (Frame, TextLabel) -> ()
): ()
	task.delay(DISPLAY_DURATION, function()
		if not frame.Parent then
			return -- Already destroyed
		end

		onRemove(frame, textLabel)
	end)
end

--[[
	Gets display duration constant

	@return number - Duration in seconds
]]
function NotificationQueue.getDisplayDuration(): number
	return DISPLAY_DURATION
end

return NotificationQueue