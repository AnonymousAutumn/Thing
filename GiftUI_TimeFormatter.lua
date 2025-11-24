--!strict

--[[
	GiftUI_TimeFormatter - Time formatting utilities for gift timestamps

	This module handles relative time display for gift timestamps:
	- Calculates relative time descriptions ("2 minutes ago", etc.)
	- Updates all gift time display labels
	- Handles multiple time granularities (seconds, minutes, hours, days)

	Returns: TimeFormatter module with time formatting functions

	Usage:
		local description = TimeFormatter.calculateRelativeTimeDescription(timestamp)
		TimeFormatter.updateAllGiftTimeDisplayLabels(timeDisplayEntries, safeExecute)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-----------
-- Types --
-----------
export type TimeDisplayEntry = {
	timeDisplayLabel: TextLabel,
	originalTimestamp: number,
}

---------------
-- Constants --
---------------
local TAG = "[GiftUI.TimeFormatter]"
local WAIT_TIMEOUT = 10

local TIME_THRESHOLDS = {
	MINUTE = 60,
	TWO_MINUTES = 120,
	HOUR = 3600,
	TWO_HOURS = 7200,
	DAY = 86400,
	TWO_DAYS = 172800,
}

local MESSAGE_FORMAT_MINUTES_AGO = "%d minutes ago"
local MESSAGE_FORMAT_HOURS_AGO = "%d hours ago"
local MESSAGE_FORMAT_DAYS_AGO = "%d days ago"

local TIME_DESC_FEW_SECONDS = "a few seconds ago"
local TIME_DESC_MINUTE = "a minute ago"
local TIME_DESC_HOUR = "an hour ago"
local TIME_DESC_DAY = "a day ago"

----------------
-- References --
----------------

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), TAG .. " Modules folder not found")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

---------------
-- Functions --
---------------

local function calculateRelativeTimeDescription(giftTimestamp: number): string
	if not (ValidationUtils.isValidNumber(giftTimestamp) and giftTimestamp >= 0) then
		return TIME_DESC_FEW_SECONDS
	end

	local secondsSinceGift = os.time() - giftTimestamp
	local T = TIME_THRESHOLDS

	if secondsSinceGift < T.MINUTE then
		return TIME_DESC_FEW_SECONDS
	elseif secondsSinceGift < T.TWO_MINUTES then
		return TIME_DESC_MINUTE
	elseif secondsSinceGift < T.HOUR then
		local minutesAgo = math.floor(secondsSinceGift / T.MINUTE)
		return string.format(MESSAGE_FORMAT_MINUTES_AGO, minutesAgo)
	elseif secondsSinceGift < T.TWO_HOURS then
		return TIME_DESC_HOUR
	elseif secondsSinceGift < T.DAY then
		local hoursAgo = math.floor(secondsSinceGift / T.HOUR)
		return string.format(MESSAGE_FORMAT_HOURS_AGO, hoursAgo)
	elseif secondsSinceGift < T.TWO_DAYS then
		return TIME_DESC_DAY
	else
		local daysAgo = math.floor(secondsSinceGift / T.DAY)
		return string.format(MESSAGE_FORMAT_DAYS_AGO, daysAgo)
	end
end

local function updateAllGiftTimeDisplayLabels(
	timeDisplayEntries: { TimeDisplayEntry },
	safeExecute: (func: () -> (), errorMessage: string) -> boolean
): ()
	assert(timeDisplayEntries, "updateAllGiftTimeDisplayLabels: timeDisplayEntries is required")
	assert(typeof(timeDisplayEntries) == "table", "updateAllGiftTimeDisplayLabels: timeDisplayEntries must be a table")
	assert(safeExecute, "updateAllGiftTimeDisplayLabels: safeExecute is required")

	for i, timeDisplayEntry in timeDisplayEntries do
		local label = timeDisplayEntry.timeDisplayLabel
		if label and label.Parent then
			safeExecute(function()
				label.Text = calculateRelativeTimeDescription(timeDisplayEntry.originalTimestamp)
			end, "Error updating time display label")
		end
	end
end

-----------
-- Setup --
-----------

local TimeFormatter = {
	calculateRelativeTimeDescription = calculateRelativeTimeDescription,
	updateAllGiftTimeDisplayLabels = updateAllGiftTimeDisplayLabels,
}

return TimeFormatter