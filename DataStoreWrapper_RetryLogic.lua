--!strict

--[[
	DataStoreWrapper_RetryLogic

	Implements exponential backoff retry logic for failed DataStore operations.
	Retries failed operations with increasing delays up to a maximum attempt count.

	Returns: Table with retry logic functions:
		- calculateBackoffDelay: Calculates exponential backoff delay
		- logOperationFailure: Logs retry attempts with context
		- retryOperationWithBackoff: Main retry wrapper with callbacks

	Usage:
		local RetryLogic = require(script.DataStoreWrapper_RetryLogic)
		local result = RetryLogic.retryOperationWithBackoff(
			function() return dataStore:GetAsync("key") end,
			"GetAsync",
			{ maxRetries = 3, baseDelay = 1, maxBackoff = 10 },
			onSuccess, onRetry, onFailure
		)
]]

local RetryLogic = {}

-----------
-- Types --
-----------
export type RetryConfig = {
	maxRetries: number?,
	baseDelay: number?,
	maxBackoff: number?,
}

export type OperationResult<T> = {
	success: boolean,
	data: T?,
	error: string?,
	attempts: number,
}

---------------
-- Constants --
---------------
local TAG = "[RetryLogic]"

local DEFAULT_MAX_RETRIES = 3
local DEFAULT_BASE_DELAY = 1 -- seconds
local DEFAULT_MAX_BACKOFF = 10 -- seconds

function RetryLogic.calculateBackoffDelay(attemptNumber: number, baseDelay: number, maxBackoff: number): number
	assert(typeof(attemptNumber) == "number" and attemptNumber > 0, "attemptNumber must be a positive number")
	assert(typeof(baseDelay) == "number" and baseDelay > 0, "baseDelay must be a positive number")
	assert(typeof(maxBackoff) == "number" and maxBackoff > 0, "maxBackoff must be a positive number")

	local exponentialDelay = baseDelay * (2 ^ (attemptNumber - 1))
	return math.min(exponentialDelay, maxBackoff)
end

function RetryLogic.logOperationFailure(
	operationName: string,
	attemptNumber: number,
	maxAttempts: number,
	errorMessage: string
): ()
	warn(TAG .. " " .. string.format("%s failed (attempt %d/%d): %s",
		operationName, attemptNumber, maxAttempts, tostring(errorMessage)))
end

function RetryLogic.retryOperationWithBackoff<T>(
	operation: () -> T,
	operationName: string,
	config: RetryConfig?,
	onSuccess: () -> (),
	onRetry: () -> (),
	onFailure: () -> ()
): OperationResult<T>
	assert(typeof(operation) == "function", "operation must be a function")
	assert(typeof(operationName) == "string" and #operationName > 0, "operationName must be a non-empty string")
	assert(typeof(onSuccess) == "function", "onSuccess must be a function")
	assert(typeof(onRetry) == "function", "onRetry must be a function")
	assert(typeof(onFailure) == "function", "onFailure must be a function")

	local maxRetries = config and config.maxRetries or DEFAULT_MAX_RETRIES
	local baseDelay = config and config.baseDelay or DEFAULT_BASE_DELAY
	local maxBackoff = config and config.maxBackoff or DEFAULT_MAX_BACKOFF

	for attemptNumber = 1, maxRetries do
		local success, result = pcall(operation)

		if success then
			onSuccess()
			return {
				success = true,
				data = result,
				error = nil,
				attempts = attemptNumber,
			}
		end

		RetryLogic.logOperationFailure(operationName, attemptNumber, maxRetries, result)

		if attemptNumber < maxRetries then
			onRetry()
			local retryDelay = RetryLogic.calculateBackoffDelay(attemptNumber, baseDelay, maxBackoff)
			task.wait(retryDelay)
		end
	end

	onFailure()
	return {
		success = false,
		data = nil,
		error = "Max retries exceeded",
		attempts = maxRetries,
	}
end

return RetryLogic