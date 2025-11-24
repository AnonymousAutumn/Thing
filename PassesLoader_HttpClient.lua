--!strict

--------------
-- Services --
--------------
local HttpService = game:GetService("HttpService")

---------------
-- Constants --
---------------
local CONFIG = {
	RETRY_ATTEMPTS = 3,
	RETRY_DELAY = 1,
	RATE_LIMIT_RETRY_DELAY = 1.0,
	REQUEST_TIMEOUT = 10,
}

local HTTP_STATUS = {
	OK = 200,
	RATE_LIMITED = 429,
}

local ERROR_MESSAGES = {
	TIMEOUT = "Request timed out",
	RATE_LIMITED = "API rate limit exceeded, retrying...",
}

-----------
-- Types --
-----------
export type HttpResult = {
	success: boolean,
	responseData: string?,
	statusCode: number?,
	error: string?,
	wasRateLimited: boolean?,
}

-----------
-- Module --
-----------
local HttpClient = {}

--[[
	Calculates backoff delay for retries
	@param attemptNumber number - Current attempt (1-indexed)
	@param baseDelay number - Base delay in seconds
	@return number - Delay in seconds
]]
local function calculateBackoffDelay(attemptNumber: number, baseDelay: number): number
	return baseDelay * attemptNumber
end

--[[
	Checks if request has timed out
	@param startTime number - Start time from os.clock()
	@param timeout number - Timeout duration in seconds
	@return boolean
]]
local function hasTimedOut(startTime: number, timeout: number): boolean
	return os.clock() - startTime > timeout
end

--[[
	Checks if error message indicates rate limiting
	@param errorMessage string - Error message to check
	@return boolean
]]
local function isRateLimitError(errorMessage: string): boolean
	local lowerMessage = string.lower(errorMessage)
	return string.find(lowerMessage, "429") ~= nil or string.find(lowerMessage, "toomanyrequest") ~= nil
end

--[[
	Makes an HTTP GET request with automatic retry logic

	Implements:
	- Exponential backoff for retries
	- Rate limit detection and handling
	- Timeout checking
	- Error categorization

	@param url string - URL to request
	@param maxRetries number? - Maximum retry attempts (default: 3)
	@param onRetry ((attempt: number, maxRetries: number, error: string) -> ())? - Optional retry callback
	@return HttpResult
]]
function HttpClient.makeRequest(
	url: string,
	maxRetries: number?,
	onRetry: ((attempt: number, maxRetries: number, error: string) -> ())?
): HttpResult
	local retries = maxRetries or CONFIG.RETRY_ATTEMPTS
	local lastError: string? = nil
	local lastStatusCode: number? = nil
	local lastWasRateLimited: boolean = false

	for attempt = 1, retries do
		local startTime = os.clock()

		local success, responseData = pcall(function()
			local response = HttpService:GetAsync(url)

			-- Check timeout
			if hasTimedOut(startTime, CONFIG.REQUEST_TIMEOUT) then
				error(ERROR_MESSAGES.TIMEOUT)
			end

			return response
		end)

		if success then
			return {
				success = true,
				responseData = responseData,
				statusCode = HTTP_STATUS.OK,
				error = nil,
				wasRateLimited = false,
			}
		else
			local errorMessage = tostring(responseData)
			lastError = errorMessage

			-- Determine if rate limited
			local isRateLimited = isRateLimitError(errorMessage)
			lastStatusCode = isRateLimited and HTTP_STATUS.RATE_LIMITED or nil

			-- Store rate limit status for final return if this is the last attempt
			if attempt == retries then
				lastWasRateLimited = isRateLimited
			end

			-- Call retry callback if provided
			if attempt < retries and onRetry then
				onRetry(attempt, retries, errorMessage)
			end

			-- Wait before retry (except on last attempt)
			if attempt < retries then
				local delay = if isRateLimited
					then calculateBackoffDelay(attempt, CONFIG.RATE_LIMIT_RETRY_DELAY)
					else calculateBackoffDelay(attempt, CONFIG.RETRY_DELAY)
				task.wait(delay)
			end
		end
	end

	-- All retries failed
	return {
		success = false,
		responseData = nil,
		statusCode = lastStatusCode,
		error = lastError,
		wasRateLimited = lastWasRateLimited,
	}
end

return HttpClient