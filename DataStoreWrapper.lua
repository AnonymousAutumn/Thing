--!strict

--[[
	DataStoreWrapper

	Provides safe DataStore operations with automatic retry logic, budget management,
	and statistics tracking. Implements exponential backoff and request throttling
	to avoid hitting DataStore limits.

	Returns: Table with wrapped DataStore operations:
		- getAsync, setAsync, updateAsync, removeAsync, incrementAsync
		- getSortedAsync (for OrderedDataStore)
		- executeOperation (generic wrapper)
		- getStatistics, resetStatistics (for monitoring)

	Usage:
		local DataStoreWrapper = require(script.DataStoreWrapper)
		local result = DataStoreWrapper.getAsync(dataStore, "player_123", {
			maxRetries = 3,
			baseDelay = 1,
			budgetTimeout = 5
		})
		if result.success then
			print("Data:", result.data)
		else
			warn("Failed:", result.error)
		end
]]

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
	assert(typeof(dataStore) == "Instance", "dataStore must be a DataStore instance")
	assert(typeof(key) == "string" and #key > 0, "key must be a non-empty string")

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
	assert(typeof(dataStore) == "Instance", "dataStore must be a DataStore instance")
	assert(typeof(key) == "string" and #key > 0, "key must be a non-empty string")
	assert(value ~= nil, "value cannot be nil")

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
	assert(typeof(dataStore) == "Instance", "dataStore must be a DataStore instance")
	assert(typeof(key) == "string" and #key > 0, "key must be a non-empty string")
	assert(typeof(transformFunction) == "function", "transformFunction must be a function")

	return performOperationWithBudgetAndRetry(function()
		return dataStore:UpdateAsync(key, transformFunction)
	end, "UpdateAsync", Enum.DataStoreRequestType.UpdateAsync, config)
end

function DataStoreWrapper.removeAsync<T>(
	dataStore: DataStore,
	key: string,
	config: RetryConfig?
): OperationResult<T>
	assert(typeof(dataStore) == "Instance", "dataStore must be a DataStore instance")
	assert(typeof(key) == "string" and #key > 0, "key must be a non-empty string")

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
	assert(typeof(dataStore) == "Instance", "dataStore must be a DataStore instance")
	assert(typeof(key) == "string" and #key > 0, "key must be a non-empty string")
	assert(typeof(delta) == "number", "delta must be a number")

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
	assert(typeof(orderedDataStore) == "Instance", "orderedDataStore must be an OrderedDataStore instance")
	assert(typeof(ascending) == "boolean", "ascending must be a boolean")
	assert(typeof(pageSize) == "number" and pageSize > 0, "pageSize must be a positive number")

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
	assert(typeof(operation) == "function", "operation must be a function")
	assert(typeof(operationName) == "string" and #operationName > 0, "operationName must be a non-empty string")
	assert(typeof(requestType) == "EnumItem", "requestType must be a DataStoreRequestType enum")

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