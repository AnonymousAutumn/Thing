--!strict

local DataExtractor = {}

---------------
-- Constants --
---------------
local TAG = "[DataExtractor]"

local MAX_PAGE_ITERATIONS = 100

-----------
-- Types --
-----------
export type LeaderboardEntry = {
	key: string,
	value: number,
}

local function logWarning(formatString: string, ...): ()
	warn(TAG .. " " .. string.format(formatString, ...))
end

local function isValidLeaderboardEntry(entry: any): boolean
	return type(entry) == "table" and entry.key ~= nil and entry.value ~= nil
end

local function extractEntriesFromPage(
	currentPageData: any,
	extractedEntries: { LeaderboardEntry },
	maximumEntryCount: number
): boolean
	if type(currentPageData) ~= "table" then
		logWarning("Current page data is not a table")
		return false
	end
	for _, entryData in currentPageData do
		if isValidLeaderboardEntry(entryData) then
			table.insert(extractedEntries, entryData)
			if #extractedEntries >= maximumEntryCount then
				return true
			end
		end
	end
	return false
end

local function getCurrentPage(dataStorePages: Pages): (boolean, any?)
	local success, currentPageData = pcall(function()
		return dataStorePages:GetCurrentPage()
	end)
	if not success then
		logWarning("Failed to get current page: %s", tostring(currentPageData))
		return false, nil
	end
	return true, currentPageData
end

local function advanceToNextPage(dataStorePages: Pages): boolean
	local advanceSuccess, advanceError = pcall(function()
		dataStorePages:AdvanceToNextPageAsync()
	end)
	if not advanceSuccess then
		logWarning("Failed to advance to next page: %s", tostring(advanceError))
		return false
	end
	return true
end

function DataExtractor.extractFromPages(
	dataStorePages: Pages,
	maximumEntryCount: number
): { LeaderboardEntry }
	local extractedEntries = {}
	local pageIterations = 0

	repeat
		pageIterations += 1
		if pageIterations > MAX_PAGE_ITERATIONS then
			logWarning("Maximum page iterations (%d) reached, stopping extraction", MAX_PAGE_ITERATIONS)
			break
		end

		local success, currentPageData = getCurrentPage(dataStorePages)
		if not success then
			break
		end

		local reachedMax = extractEntriesFromPage(currentPageData, extractedEntries, maximumEntryCount)
		if reachedMax or #extractedEntries >= maximumEntryCount or dataStorePages.IsFinished then
			break
		end

		if not advanceToNextPage(dataStorePages) then
			break
		end
	until false

	return extractedEntries
end

return DataExtractor