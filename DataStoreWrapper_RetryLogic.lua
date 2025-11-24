--!strict

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