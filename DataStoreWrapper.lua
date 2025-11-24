--!strict

local RetryLogic = require(script.RetryLogic)
local BudgetManager = require(script.BudgetManager)
local Statistics = require(script.Statistics)

-----------
-- Types --
-----------
export type RetryConfig = {
	maxRetries: number?,
	baseDelay: number?,
	maxBackoff: number?,
	budgetTimeout: number?,
}

export type OperationResult<T> = {
	success: boolean,
	data: T?,
	error: string?,
	attempts: number,
}

export type DataStoreStatistics = Statistics.DataStoreStatistics

---------------
-- Constants --
---------------
local DEFAULT_BUDGET_TIMEOUT = 5 -- seconds

---------------
-- Helpers --
---------------
local function performOperationWithBudgetAndRetry<T>(
	operation: () -> T,
	operationName: string,
	requestType: Enum.DataStoreRequestType,
	config: RetryConfig?
): OperationResult<T>
	local budgetTimeout = config and config.budgetTimeout or DEFAULT_BUDGET_TIMEOUT

	Statistics.incrementTotalOperations()

	if not BudgetManager.waitForRequestBudget(requestType, budgetTimeout, Statistics.incrementBudgetWaits) then
		Statistics.incrementFailedOperations()
		return {
			success = false,
			data = nil,
			error = "Budget timeout",
			attempts = 0,
		}
	end

	return RetryLogic.retryOperationWithBackoff(
		operation,
		operationName,
		config,
		Statistics.incrementSuccessfulOperations,
		Statistics.incrementTotalRetries,
		Statistics.incrementFailedOperations
	)
end

---------------
-- Public API --
---------------
local DataStoreWrapper = {}

function DataStoreWrapper.getAsync<T>(
	dataStore: DataStore,
	key: string,
	config: RetryConfig?
): OperationResult<T>
	return performOperationWithBudgetAndRetry(function()
		return dataStore:GetAsync(key)
	end, "GetAsync", Enum.DataStoreRequestType.GetAsync, config)
end

function DataStoreWrapper.setAsync<T>(
	dataStore: DataStore,
	key: string,
	value: T,
	config: RetryConfig?
): OperationResult<T>
	return performOperationWithBudgetAndRetry(function()
		dataStore:SetAsync(key, value)
		return value
	end, "SetAsync", Enum.DataStoreRequestType.SetIncrementAsync, config)
end

function DataStoreWrapper.updateAsync<T>(
	dataStore: DataStore,
	key: string,
	transformFunction: (oldValue: T?) -> T,
	config: RetryConfig?
): OperationResult<T>
	return performOperationWithBudgetAndRetry(function()
		return dataStore:UpdateAsync(key, transformFunction)
	end, "UpdateAsync", Enum.DataStoreRequestType.UpdateAsync, config)
end

function DataStoreWrapper.removeAsync<T>(
	dataStore: DataStore,
	key: string,
	config: RetryConfig?
): OperationResult<T>
	return performOperationWithBudgetAndRetry(function()
		return dataStore:RemoveAsync(key)
	end, "RemoveAsync", Enum.DataStoreRequestType.SetIncrementAsync, config)
end

function DataStoreWrapper.incrementAsync(
	dataStore: DataStore,
	key: string,
	delta: number,
	config: RetryConfig?
): OperationResult<number>
	return performOperationWithBudgetAndRetry(function()
		return dataStore:IncrementAsync(key, delta)
	end, "IncrementAsync", Enum.DataStoreRequestType.SetIncrementAsync, config)
end

function DataStoreWrapper.getSortedAsync(
	orderedDataStore: OrderedDataStore,
	ascending: boolean,
	pageSize: number,
	minValue: number?,
	maxValue: number?,
	config: RetryConfig?
): OperationResult<DataStorePages>
	return performOperationWithBudgetAndRetry(function()
		return orderedDataStore:GetSortedAsync(ascending, pageSize, minValue, maxValue)
	end, "GetSortedAsync", Enum.DataStoreRequestType.GetSortedAsync, config)
end

function DataStoreWrapper.executeOperation<T>(
	operation: () -> T,
	operationName: string,
	requestType: Enum.DataStoreRequestType,
	config: RetryConfig?
): OperationResult<T>
	return performOperationWithBudgetAndRetry(operation, operationName, requestType, config)
end

function DataStoreWrapper.getStatistics(): DataStoreStatistics
	return Statistics.get()
end

function DataStoreWrapper.resetStatistics(): ()
	Statistics.reset()
end

--------------
-- Return  --
--------------
return DataStoreWrapper