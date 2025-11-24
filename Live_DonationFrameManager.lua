--!strict

-----------
-- Types --
-----------
export type ActiveFrameTracking = {
	large: { CanvasGroup },
	standard: { CanvasGroup },
}

---------------
-- Constants --
---------------
local MAX_STANDARD_FRAMES = 10
local MAX_LARGE_FRAMES = 5
local FRAME_CLEANUP_INTERVAL = 30

local LARGE_FRAME_LAYOUT_MODIFIER = -1
local STANDARD_FRAME_LAYOUT_MODIFIER = 1

local TAG = "[DonationFrameManager]"

-----------
-- Module --
-----------
local DonationFrameManager = {}
DonationFrameManager.__index = DonationFrameManager

--[[
	Creates a new frame manager instance

	@param largeDonationContainer Frame - Container for large donations
	@param standardDonationContainer Frame - Container for standard donations
	@return DonationFrameManager
]]
function DonationFrameManager.new(largeDonationContainer: Frame, standardDonationContainer: Frame)
	local self = setmetatable({}, DonationFrameManager) :: any

	self.activeDonationFrames = {
		large = {},
		standard = {},
	} :: ActiveFrameTracking

	self.largeDonationContainer = largeDonationContainer
	self.standardDonationContainer = standardDonationContainer
	self.cleanupThread = nil :: thread?
	self.isShuttingDown = false

	return self
end

--[[
	Removes a frame from tracking list

	@param frame CanvasGroup - Frame to remove
	@param frameType string - "large" or "standard"
]]
function DonationFrameManager:removeFromTracking(frame: CanvasGroup, frameType: string): ()
	local list = self.activeDonationFrames[frameType]
	for i, tracked in list do
		if tracked == frame then
			table.remove(list, i)
			break
		end
	end
end

--[[
	Destroys the oldest frame in a tracking list

	@param trackingList {CanvasGroup} - List to remove from
]]
local function destroyOldestFrame(trackingList: { CanvasGroup }): ()
	local oldestFrame = table.remove(trackingList, 1)
	if oldestFrame and oldestFrame.Parent ~= nil then
		oldestFrame:Destroy()
	end
end

--[[
	Enforces frame limit by removing oldest frames

	@param frameType string - "large" or "standard"
	@param maxFrames number - Maximum allowed frames
]]
function DonationFrameManager:enforceLimit(frameType: string, maxFrames: number): ()
	local list = self.activeDonationFrames[frameType]
	while #list >= maxFrames do
		destroyOldestFrame(list)
	end
end

--[[
	Adjusts layout order for all frames in a container

	@param donationDisplayType string - "Large" or "Normal"
]]
function DonationFrameManager:adjustLayoutOrdering(donationDisplayType: string): ()
	local targetDisplayFrame = if donationDisplayType == "Large"
		then self.largeDonationContainer
		else self.standardDonationContainer
	local layoutOrderModifier = if donationDisplayType == "Large"
		then LARGE_FRAME_LAYOUT_MODIFIER
		else STANDARD_FRAME_LAYOUT_MODIFIER

	-- Cache GetChildren() for performance (called on every donation)
	local children = targetDisplayFrame:GetChildren()
	for _, donationFrame in children do
		if donationFrame:IsA("CanvasGroup") then
			donationFrame.LayoutOrder += layoutOrderModifier
		end
	end
end

--[[
	Schedules a frame for automatic cleanup after delay

	@param frame CanvasGroup - Frame to cleanup
	@param frameType string - "large" or "standard"
	@param delaySeconds number - Delay before cleanup
]]
function DonationFrameManager:scheduleCleanup(frame: CanvasGroup, frameType: string, delaySeconds: number): ()
	task.delay(delaySeconds, function()
		self:removeFromTracking(frame, frameType)
		if frame and frame.Parent ~= nil then
			frame:Destroy()
		end
	end)
end

--[[
	Adds a frame to the large donations tracking list

	@param frame CanvasGroup - Frame to add
]]
function DonationFrameManager:addLargeFrame(frame: CanvasGroup): ()
	table.insert(self.activeDonationFrames.large, frame)
end

--[[
	Adds a frame to the standard donations tracking list

	@param frame CanvasGroup - Frame to add
]]
function DonationFrameManager:addStandardFrame(frame: CanvasGroup): ()
	table.insert(self.activeDonationFrames.standard, frame)
end

--[[
	Gets the large donation container

	@return Frame
]]
function DonationFrameManager:getLargeContainer(): Frame
	return self.largeDonationContainer
end

--[[
	Gets the standard donation container

	@return Frame
]]
function DonationFrameManager:getStandardContainer(): Frame
	return self.standardDonationContainer
end

--[[
	Gets max frame limits

	@return number, number - Max large frames, max standard frames
]]
function DonationFrameManager.getMaxLimits(): (number, number)
	return MAX_LARGE_FRAMES, MAX_STANDARD_FRAMES
end

--[[
	Performs cleanup of orphaned frames

	Removes frames from tracking lists if they no longer have a parent
]]
function DonationFrameManager:performCleanup(): ()
	if self.isShuttingDown then
		return
	end

	local cleanedCount = 0

	for i = #self.activeDonationFrames.large, 1, -1 do
		local frame = self.activeDonationFrames.large[i]
		if not (frame and frame.Parent ~= nil) then
			table.remove(self.activeDonationFrames.large, i)
			cleanedCount += 1
		end
	end

	for i = #self.activeDonationFrames.standard, 1, -1 do
		local frame = self.activeDonationFrames.standard[i]
		if not (frame and frame.Parent ~= nil) then
			table.remove(self.activeDonationFrames.standard, i)
			cleanedCount += 1
		end
	end

	if cleanedCount > 0 then
		print(string.format("%s Frame cleanup: removed %d orphaned frames", TAG, cleanedCount))
	end
end

--[[
	Starts the periodic frame cleanup loop
]]
function DonationFrameManager:startCleanupLoop(): ()
	if self.cleanupThread then
		return
	end

	self.cleanupThread = task.spawn(function()
		while not self.isShuttingDown do
			task.wait(FRAME_CLEANUP_INTERVAL)
			self:performCleanup()
		end
	end)
end

--[[
	Stops the periodic frame cleanup loop
]]
function DonationFrameManager:stopCleanupLoop(): ()
	if self.cleanupThread then
		task.cancel(self.cleanupThread)
		self.cleanupThread = nil
	end
end

--[[
	Destroys all active donation frames

	Used during shutdown to clean up all resources
]]
function DonationFrameManager:destroyAll(): ()
	for _, frame in self.activeDonationFrames.large do
		if frame and frame.Parent ~= nil then
			frame:Destroy()
		end
	end
	for _, frame in self.activeDonationFrames.standard do
		if frame and frame.Parent ~= nil then
			frame:Destroy()
		end
	end
	table.clear(self.activeDonationFrames.large)
	table.clear(self.activeDonationFrames.standard)
end

--[[
	Marks manager as shutting down and stops cleanup loop
]]
function DonationFrameManager:shutdown(): ()
	self.isShuttingDown = true
	self:stopCleanupLoop()
end

return DonationFrameManager