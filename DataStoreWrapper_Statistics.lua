--!strict

local Statistics = {}

-----------
-- Types --
-----------
export type DataStoreStatistics = {
	totalOperations: number,
	successfulOperations: number,
	failedOperations: number,
	totalRetries: number,
	budgetWaits: number,
}

---------------
-- Variables --
---------------
local statistics: DataStoreStatistics = {
	totalOperations = 0,
	successfulOperations = 0,
	failedOperations = 0,
	totalRetries = 0,
	budgetWaits = 0,
}

function Statistics.incrementTotalOperations(): ()
	statistics.totalOperations += 1
end

function Statistics.incrementSuccessfulOperations(): ()
	statistics.successfulOperations += 1
end

function Statistics.incrementFailedOperations(): ()
	statistics.failedOperations += 1
end

function Statistics.incrementTotalRetries(): ()
	statistics.totalRetries += 1
end

function Statistics.incrementBudgetWaits(): ()
	statistics.budgetWaits += 1
end

function Statistics.get(): DataStoreStatistics
	return {
		totalOperations = statistics.totalOperations,
		successfulOperations = statistics.successfulOperations,
		failedOperations = statistics.failedOperations,
		totalRetries = statistics.totalRetries,
		budgetWaits = statistics.budgetWaits,
	}
end

function Statistics.reset(): ()
	statistics.totalOperations = 0
	statistics.successfulOperations = 0
	statistics.failedOperations = 0
	statistics.totalRetries = 0
	statistics.budgetWaits = 0
end

return Statistics