--!strict

--[[
	PassesLoader_ResponseParser - JSON response parser and error extractor

	What it does:
	- Safely decodes JSON responses from HTTP requests
	- Extracts and categorizes API errors from response data
	- Supports multiple error formats (Errors array, error field)
	- Validates response data presence

	Returns: Module table with functions:
	- parseResponse(responseData) - Parses HTTP response
		Returns: ParseResult { success, errorMessage, data? }

	Usage:
	local ResponseParser = require(script.ResponseParser)
	local result = ResponseParser.parseResponse(httpResponseData)
	if result.success then
		-- Process result.data
	else
		warn("API Error: " .. result.errorMessage)
	end
]]

--------------
-- Services --
--------------
local HttpService = game:GetService("HttpService")

---------------
-- Constants --
---------------
local ERROR_MESSAGES = {
	DEFAULT = "There was an error. Try again!",
	NO_RESPONSE = "No response data received from API",
	INVALID_DATA = "Invalid data received from API",
	EMPTY_RESPONSE = "Cannot decode empty response data",
}

-----------
-- Types --
-----------
export type ParseResult = {
	success: boolean,
	errorMessage: string,
	data: any?,
}

-----------
-- Module --
-----------
local ResponseParser = {}

--[[
	Decodes JSON response data safely

	@param responseData string? - JSON string to decode
	@return (boolean, any?) - Success status and decoded data
]]
local function decodeJsonResponse(responseData: string?): (boolean, any?)
	if not responseData or responseData == "" then
		warn("[ResponseParser] " .. ERROR_MESSAGES.EMPTY_RESPONSE)
		return false, nil
	end

	local success, decodedData = pcall(function()
		return HttpService:JSONDecode(responseData)
	end)

	if not success then
		warn("[ResponseParser] JSON decode failed: " .. tostring(decodedData))
		return false, nil
	end

	return true, decodedData
end

--[[
	Extracts error message from API response

	Supports multiple error formats:
	- Errors array: { Errors: [{message, code}] }
	- error field: { error: "message" }

	@param decodedData any - Decoded JSON response
	@return string? - Error message if found, nil otherwise
]]
local function extractApiErrorMessage(decodedData: any): string?
	-- Check for Errors array (Roblox API format)
	if decodedData.Errors and type(decodedData.Errors) == "table" and #decodedData.Errors > 0 then
		local apiError = decodedData.Errors[1]
		local errorMessage = apiError.message or apiError.Message or ERROR_MESSAGES.DEFAULT
		local errorCode = tostring(apiError.code or apiError.Code or "unknown")

		warn(string.format("[ResponseParser] API Error: %s (Code: %s)", errorMessage, errorCode))
		return errorMessage
	end

	-- Check for error field (simple format)
	if decodedData.error then
		local errorMsg = tostring(decodedData.error)
		warn("[ResponseParser] API Error: " .. errorMsg)
		return errorMsg
	end

	return nil
end

--[[
	Processes API response: decodes JSON and checks for errors

	@param responseData string? - Raw response string
	@return ParseResult - { success, errorMessage, data }
]]
function ResponseParser.parseResponse(responseData: string?): ParseResult
	if not responseData then
		warn("[ResponseParser] API request failed: " .. ERROR_MESSAGES.NO_RESPONSE)
		return {
			success = false,
			errorMessage = ERROR_MESSAGES.NO_RESPONSE,
			data = nil,
		}
	end

	-- Decode JSON
	local decodeSuccess, decodedData = decodeJsonResponse(responseData)

	if not decodeSuccess then
		return {
			success = false,
			errorMessage = ERROR_MESSAGES.INVALID_DATA,
			data = nil,
		}
	end

	-- Check for API errors
	local apiError = extractApiErrorMessage(decodedData)
	if apiError then
		return {
			success = false,
			errorMessage = apiError,
			data = nil,
		}
	end

	-- Success
	return {
		success = true,
		errorMessage = "",
		data = decodedData,
	}
end

return ResponseParser