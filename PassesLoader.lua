--!strict

--------------------
-- Initialization --
--------------------

local PassesLoader = {}

--------------
-- Services --
--------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local modules = ReplicatedStorage:WaitForChild("Modules")
local configuration = ReplicatedStorage:WaitForChild("Configuration")

local gameConfig = require(configuration.GameConfig)
local validationUtils = require(modules.Utilities.ValidationUtils)

local HttpClient = require(script.HttpClient)
local ResponseParser = require(script.ResponseParser)
local DataProcessor = require(script.DataProcessor)

-----------
-- Types --
-----------

export type GamepassData = DataProcessor.GamepassData

---------------
-- Constants --
---------------

local API_RATE_LIMIT_DELAY = 0.2

local ERROR_MESSAGES = {
	DEFAULT = "There was an error. Try again!",
	HTTP_FAILED = "HTTP request failed",
	INVALID_DATA = "Invalid data received from API",
	INVALID_UNIVERSE_ID = "Invalid universe ID",
	INVALID_PLAYER_ID = "Invalid player ID",
}

local LOG_PREFIX = "[PassesLoader]"

---------------
-- Variables --
---------------

local requestStats = {
	totalRequests = 0,
	successfulRequests = 0,
	failedRequests = 0,
	rateLimitHits = 0,
}

---------------
-- Logging --
---------------

local function logApiWarning(message: string, ...: any): ()
	warn(string.format(LOG_PREFIX .. " " .. message, ...))
end

local function logApiInfo(message: string, ...: any): ()
	print(string.format(LOG_PREFIX .. " " .. message, ...))
end

---------------
-- Statistics --
---------------

local function updateRequestStats(success: boolean, wasRateLimited: boolean?): ()
	requestStats.totalRequests += 1
	if success then
		requestStats.successfulRequests += 1
	else
		requestStats.failedRequests += 1
	end
	if wasRateLimited then
		requestStats.rateLimitHits += 1
	end
end

---------------
-- Validation --
---------------

local function validateGamepassResponse(decodedData: any, universeId: number): boolean
	if not decodedData.gamePasses or type(decodedData.gamePasses) ~= "table" then
		logApiWarning("Invalid gamepass data structure for universe %d", universeId)
		return false
	end
	return true
end

local function validateGamesResponse(decodedData: any, playerId: number): boolean
	if not decodedData.data or type(decodedData.data) ~= "table" then
		logApiWarning("Invalid games data structure for player %d", playerId)
		return false
	end
	return true
end

-----------------
-- Public API --
-----------------

function PassesLoader:FetchGamepassesFromUniverseId(universeId: number): (boolean, string, {GamepassData}?)
	if not validationUtils.isValidUniverseId(universeId) then
		logApiWarning("Invalid universe ID: %s", tostring(universeId))
		return false, ERROR_MESSAGES.INVALID_UNIVERSE_ID, nil
	end

	-- First, check if universe has any gamepasses (optimization)
	local checkUrl = string.format(
		gameConfig.GAMEPASS_CONFIG.GAMEPASS_FETCH_ROOT_URL,
		universeId,
		gameConfig.GAMEPASS_CONFIG.GAMEPASSES_CHECK_LIMIT,
		""
	)

	local httpResult = HttpClient.makeRequest(checkUrl)
	updateRequestStats(httpResult.success, httpResult.wasRateLimited)

	if not httpResult.success then
		logApiWarning("Failed to check gamepasses for universe %d", universeId)
		return false, ERROR_MESSAGES.HTTP_FAILED, nil
	end

	local parseResult = ResponseParser.parseResponse(httpResult.responseData)
	if not parseResult.success then
		return false, parseResult.errorMessage, nil
	end

	if not validateGamepassResponse(parseResult.data, universeId) then
		return false, ERROR_MESSAGES.INVALID_DATA, nil
	end

	-- If no gamepasses, return empty list
	if not parseResult.data.gamePasses or #parseResult.data.gamePasses == 0 then
		return true, "", {}
	end

	-- Universe has gamepasses, fetch all pages
	local allGamepasses: {GamepassData} = {}
	local nextPageToken = ""
	local pageCount = 0

	repeat
		pageCount += 1

		local gamepassApiUrl = string.format(
			gameConfig.GAMEPASS_CONFIG.GAMEPASS_FETCH_ROOT_URL,
			universeId,
			gameConfig.GAMEPASS_CONFIG.GAMEPASSES_PAGE_LIMIT,
			nextPageToken
		)

		local pageHttpResult = HttpClient.makeRequest(gamepassApiUrl)
		updateRequestStats(pageHttpResult.success, pageHttpResult.wasRateLimited)

		if not pageHttpResult.success then
			logApiWarning("Gamepass fetch failed for universe %d (page %d)", universeId, pageCount)
			break
		end

		local pageParseResult = ResponseParser.parseResponse(pageHttpResult.responseData)
		if not pageParseResult.success then
			logApiWarning("Parse error for universe %d (page %d): %s", universeId, pageCount, pageParseResult.errorMessage)
			break
		end

		if not validateGamepassResponse(pageParseResult.data, universeId) then
			break
		end

		-- Process this page's gamepasses
		local processResult = DataProcessor.processGamepasses(pageParseResult.data.gamePasses)
		for _, gamepassData in processResult.gamepasses do
			table.insert(allGamepasses, gamepassData)
		end

		-- Check for next page
		nextPageToken = pageParseResult.data.nextPageCursor or ""
	until nextPageToken == ""

	logApiInfo("Fetched %d gamepasses for universe %d (%d pages)", #allGamepasses, universeId, pageCount)

	return true, "", allGamepasses
end

function PassesLoader:FetchPlayerOwnedGames(playerId: number): (boolean, string, {number}?)
	if not validationUtils.isValidUserId(playerId) then
		logApiWarning("Invalid player ID: %s", tostring(playerId))
		return false, ERROR_MESSAGES.INVALID_PLAYER_ID, nil
	end

	local allUniverseIds: {number} = {}
	local nextCursor = ""
	local pageCount = 0

	repeat
		pageCount += 1

		-- Build API URL with cursor
		local playerGamesApiUrl = string.format(
			gameConfig.GAMEPASS_CONFIG.GAMES_FETCH_ROOT_URL,
			playerId,
			gameConfig.GAMEPASS_CONFIG.UNIVERSES_PAGE_LIMIT,
			nextCursor
		)

		-- Make HTTP request
		local httpResult = HttpClient.makeRequest(playerGamesApiUrl)
		updateRequestStats(httpResult.success, httpResult.wasRateLimited)

		if not httpResult.success then
			logApiWarning(
				"Player games fetch failed for player %d (page %d): HTTP request unsuccessful",
				playerId,
				pageCount
			)
			-- Return what we have so far rather than failing completely
			break
		end

		-- Process response
		local parseResult = ResponseParser.parseResponse(httpResult.responseData)
		if not parseResult.success then
			logApiWarning("Failed to process page %d for player %d: %s", pageCount, playerId, parseResult.errorMessage)
			break
		end

		-- Validate response structure
		if not validateGamesResponse(parseResult.data, playerId) then
			break
		end

		-- Extract game IDs from this page
		local pageGameIds = DataProcessor.processGames(parseResult.data.data)

		-- Add to collection
		for _, universeId in pageGameIds do
			table.insert(allUniverseIds, universeId)
		end

		-- Get next cursor
		nextCursor = parseResult.data.nextPageCursor or ""

		-- Rate limit between pages
		if nextCursor ~= "" then
			task.wait(API_RATE_LIMIT_DELAY)
		end

	until nextCursor == ""

	logApiInfo("Found %d universes for player %d across %d pages", #allUniverseIds, playerId, pageCount)

	return true, "", allUniverseIds
end

function PassesLoader:FetchAllPlayerGamepasses(playerId: number): (boolean, string, {GamepassData}?)
	-- First, fetch all games the player owns
	local gamesSuccess, gamesError, playerOwnedGames = self:FetchPlayerOwnedGames(playerId)

	if not gamesSuccess or not playerOwnedGames then
		logApiWarning("Failed to fetch games for player %d: %s", playerId, gamesError)
		return false, gamesError, nil
	end

	if #playerOwnedGames == 0 then
		logApiInfo("Player %d owns no games", playerId)
		return true, "", {}
	end

	-- Fetch gamepasses from each game
	local aggregatedGamepasses: {GamepassData} = {}
	local successfulFetches = 0
	local failedFetches = 0
	local skippedUniverses = 0

	for index, gameUniverseId in playerOwnedGames do
		local gamepassSuccess, gamepassError, gameGamepasses = self:FetchGamepassesFromUniverseId(gameUniverseId)

		if gamepassSuccess and gameGamepasses then
			successfulFetches += 1

			if #gameGamepasses == 0 then
				skippedUniverses += 1
			else
				for _, gamepassData in gameGamepasses do
					table.insert(aggregatedGamepasses, gamepassData)
				end
			end
		else
			failedFetches += 1
			logApiWarning("Skipping game %d due to error: %s", gameUniverseId, gamepassError)
		end

		-- Rate limiting between requests
		if index < #playerOwnedGames then
			task.wait(API_RATE_LIMIT_DELAY)
		end
	end

	logApiInfo(
		"Fetched gamepasses for player %d: %d games successful, %d failed, %d without passes, %d total gamepasses",
		playerId,
		successfulFetches,
		failedFetches,
		skippedUniverses,
		#aggregatedGamepasses
	)

	return true, "", aggregatedGamepasses
end

logApiInfo("Initialized successfully")

--------------
-- Returner --
--------------

return PassesLoader