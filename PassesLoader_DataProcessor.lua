--!strict

-----------
-- Types --
-----------
export type GamepassData = {
	Id: number,
	Name: string,
	Icon: string,
	Price: number,
}

type GamepassInfo = {
	id: number?,
	name: string?,
	price: number?,
}

type GameInfo = {
	id: number?,
}

export type ProcessResult = {
	gamepasses: { GamepassData },
	skippedCount: number,
}

---------------
-- Constants --
---------------
local GAMEPASS_THUMBNAIL_FORMAT = "rbxthumb://type=GamePass&id=%d&w=150&h=150"

-----------
-- Module --
-----------
local DataProcessor = {}

--[[
	Validates gamepass data structure

	Requirements:
	- Must have numeric ID
	- Must have string name
	- Must have positive numeric price (filters free gamepasses)

	@param gamepassInfo any - Raw gamepass data
	@return boolean - True if valid
]]
function DataProcessor.isValidGamepassData(gamepassInfo: any): boolean
	if type(gamepassInfo) ~= "table" then
		return false
	end

	-- Must have an ID
	local gamepassId = gamepassInfo.id
	if not gamepassId or type(gamepassId) ~= "number" then
		return false
	end

	-- Must have a name
	local gamepassName = gamepassInfo.name
	if not gamepassName or type(gamepassName) ~= "string" then
		return false
	end

	-- Must have a valid price (only include paid passes)
	if not gamepassInfo.price or type(gamepassInfo.price) ~= "number" or gamepassInfo.price <= 0 then
		return false
	end

	return true
end

--[[
	Creates gamepass data structure with thumbnail URL

	@param gamepassInfo GamepassInfo - Validated gamepass info
	@return GamepassData
]]
local function createGamepassData(gamepassInfo: GamepassInfo): GamepassData
	local gamepassId = gamepassInfo.id :: number

	return {
		Id = gamepassId,
		Name = gamepassInfo.name :: string,
		Icon = string.format(GAMEPASS_THUMBNAIL_FORMAT, gamepassId),
		Price = gamepassInfo.price :: number,
	}
end

--[[
	Processes array of raw gamepass data

	Filters invalid entries and transforms valid ones.

	@param rawGamepassData {any} - Array of raw gamepass data
	@return ProcessResult - { gamepasses, skippedCount }
]]
function DataProcessor.processGamepasses(rawGamepassData: { any }): ProcessResult
	local processedGamepasses: { GamepassData } = {}
	local skippedCount = 0

	for _, gamepassInfo in rawGamepassData do
		if DataProcessor.isValidGamepassData(gamepassInfo) then
			table.insert(processedGamepasses, createGamepassData(gamepassInfo))
		else
			skippedCount += 1
		end
	end

	return {
		gamepasses = processedGamepasses,
		skippedCount = skippedCount,
	}
end

--[[
	Validates gamepass API response structure

	@param decodedData any - Decoded API response
	@param universeId number - Universe ID for logging
	@return boolean
]]
function DataProcessor.validateGamepassResponse(decodedData: any, universeId: number): boolean
	if not decodedData.gamePasses or type(decodedData.gamePasses) ~= "table" then
		warn(string.format("[DataProcessor] Invalid gamepass data structure for universe %d", universeId))
		return false
	end
	return true
end

--[[
	Extracts game ID from game info object

	@param gameInfo GameInfo - Raw game info
	@return number? - Game ID if valid
]]
local function extractGameId(gameInfo: GameInfo): number?
	return gameInfo.id
end

--[[
	Validates game ID

	@param gameId any - Value to validate
	@return boolean
]]
local function isValidGameId(gameId: any): boolean
	return type(gameId) == "number" and gameId > 0
end

--[[
	Processes array of game data, extracting valid game IDs

	@param rawGameData {any} - Array of raw game data
	@return {number} - Array of valid game IDs
]]
function DataProcessor.processGames(rawGameData: { any }): { number }
	local gameIds: { number } = {}

	for _, gameInfo in rawGameData do
		local gameId = extractGameId(gameInfo)

		if isValidGameId(gameId) then
			table.insert(gameIds, gameId :: number)
		end
	end

	return gameIds
end

--[[
	Validates games API response structure

	@param decodedData any - Decoded API response
	@param playerId number - Player ID for logging
	@return boolean
]]
function DataProcessor.validateGamesResponse(decodedData: any, playerId: number): boolean
	if not decodedData.data or type(decodedData.data) ~= "table" then
		warn(string.format("[DataProcessor] Invalid games data structure for player %d", playerId))
		return false
	end
	return true
end

return DataProcessor