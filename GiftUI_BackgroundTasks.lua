--!strict

---------------
-- Constants --
---------------
local GIFT_DATA_REFRESH_INTERVAL = 10 -- seconds
local TIME_DISPLAY_UPDATE_INTERVAL = 1 -- seconds

-----------
-- Module --
-----------
local BackgroundTasks = {}

-- External dependencies (set by GiftUI)
BackgroundTasks.requestLatestGiftDataCallback = nil :: (() -> ())?
BackgroundTasks.updateTimeDisplayCallback = nil :: (() -> ())?

--[[
	Starts continuous gift data refresh loop

	Runs in background, fetching latest gift data from server at regular intervals.

	@param resourceManager any - ResourceCleanup instance to track the task
]]
function BackgroundTasks.startContinuousGiftDataRefreshLoop(resourceManager: any): ()
	local refreshTask = task.spawn(function()
		while true do
			task.wait(GIFT_DATA_REFRESH_INTERVAL)
			if BackgroundTasks.requestLatestGiftDataCallback then
				BackgroundTasks.requestLatestGiftDataCallback()
			end
		end
	end)
	resourceManager:trackThread(refreshTask)
end

--[[
	Starts continuous time display update loop

	Runs in background, updating "X minutes ago" labels for gift timestamps.

	@param resourceManager any - ResourceCleanup instance to track the task
	@param giftDisplayFrame Frame - The gift display frame to check visibility
]]
function BackgroundTasks.startContinuousTimeDisplayUpdateLoop(resourceManager: any, giftDisplayFrame: Frame): ()
	local updateTask = task.spawn(function()
		while true do
			task.wait(TIME_DISPLAY_UPDATE_INTERVAL)
			if giftDisplayFrame.Visible and BackgroundTasks.updateTimeDisplayCallback then
				BackgroundTasks.updateTimeDisplayCallback()
			end
		end
	end)
	resourceManager:trackThread(updateTask)
end

return BackgroundTasks