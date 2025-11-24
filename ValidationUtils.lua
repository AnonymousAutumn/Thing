--!strict

--[[
	ValidationUtils Module

	Provides comprehensive validation functions for all data types.
	Validates players, UI elements, numbers, strings, and more.

	Returns: ValidationUtils table with validation functions

	Usage:
		local ValidationUtils = require(...)
		if ValidationUtils.isValidPlayer(player) then ... end
]]

--------------
-- Services --
--------------
local Players = game:GetService("Players")

-----------
-- Types --
-----------
export type ValidationResult = {
	isValid: boolean,
	error: string?,
}

---------------
-- Constants --
---------------
local MIN_USER_ID = 1

local ValidationUtils = {}

--[[
	Player Validation
]]

-- Validates that a player exists and is still in the game
function ValidationUtils.isValidPlayer(player: any): boolean
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent ~= nil
		and Players:FindFirstChild(player.Name) ~= nil
end

-- Validates a Roblox user ID (must be positive integer)
function ValidationUtils.isValidUserId(userId: any): boolean
	return userId >= MIN_USER_ID
end

--[[
	UI Element Validation
]]

-- Validates a Frame instance
function ValidationUtils.isValidFrame(frame: any): boolean
	return typeof(frame) == "Instance"
		and frame:IsA("Frame")
		and frame.Parent ~= nil
end

-- Validates a TextLabel instance
function ValidationUtils.isValidTextLabel(label: any): boolean
	return typeof(label) == "Instance"
		and label:IsA("TextLabel")
end

-- Validates a TextButton instance
function ValidationUtils.isValidTextButton(button: any): boolean
	return typeof(button) == "Instance"
		and button:IsA("TextButton")
end

-- Validates an ImageLabel instance
function ValidationUtils.isValidImageLabel(label: any): boolean
	return typeof(label) == "Instance"
		and label:IsA("ImageLabel")
end

-- Validates a UIStroke instance
function ValidationUtils.isValidUIStroke(stroke: any): boolean
	return typeof(stroke) == "Instance"
		and stroke:IsA("UIStroke")
end

-- Validates a UIGradient instance
function ValidationUtils.isValidUIGradient(gradient: any): boolean
	return typeof(gradient) == "Instance"
		and gradient:IsA("UIGradient")
end

-- Validates a ScrollingFrame instance
function ValidationUtils.isValidScrollingFrame(frame: any): boolean
	return typeof(frame) == "Instance"
		and frame:IsA("ScrollingFrame")
end

--[[
	Character/Humanoid Validation
]]

-- Validates a character model
function ValidationUtils.isValidCharacter(character: any): boolean
	return typeof(character) == "Instance"
		and character:IsA("Model")
		and character.Parent ~= nil
		and character:FindFirstChild("Humanoid") ~= nil
end

-- Validates a Humanoid instance
function ValidationUtils.isValidHumanoid(humanoid: any): boolean
	return typeof(humanoid) == "Instance"
		and humanoid:IsA("Humanoid")
		and humanoid.Health > 0
end

--[[
	Folder/Container Validation
]]

-- Validates a Folder instance
function ValidationUtils.isValidFolder(folder: any): boolean
	return typeof(folder) == "Instance"
		and folder:IsA("Folder")
end

-- Validates a StringValue instance
function ValidationUtils.isValidStringValue(value: any): boolean
	return typeof(value) == "Instance"
		and value:IsA("StringValue")
end

--[[
	Data Type Validation
]]

-- Validates a non-empty string
function ValidationUtils.isValidString(value: any): boolean
	return typeof(value) == "string"
		and #value > 0
end

-- Validates a positive number
function ValidationUtils.isValidNumber(value: any): boolean
	return typeof(value) == "number"
		and not (value ~= value) -- NaN check
		and value == value -- Another NaN check
		and math.abs(value) ~= math.huge -- Infinity check
end

-- Validates a positive integer
function ValidationUtils.isValidPositiveInteger(value: any): boolean
	return typeof(value) == "number"
		and value > 0
		and value == math.floor(value) -- Integer check
end

-- Validates a non-negative integer
function ValidationUtils.isValidNonNegativeInteger(value: any): boolean
	return typeof(value) == "number"
		and value >= 0
		and value == math.floor(value) -- Integer check
end

-- Validates a boolean
function ValidationUtils.isValidBoolean(value: any): boolean
	return typeof(value) == "boolean"
end

-- Validates a table
function ValidationUtils.isValidTable(value: any): boolean
	return typeof(value) == "table"
end

--[[
	Range Validation
]]

-- Validates a number is within a range (inclusive)
function ValidationUtils.isInRange(value: number, min: number, max: number): boolean
	return value >= min and value <= max
end

-- Validates an amount is within valid Robux range (1 to 1,000,000)
function ValidationUtils.isValidRobuxAmount(amount: any): boolean
	return ValidationUtils.isValidNumber(amount)
		and amount >= 1
		and amount == math.floor(amount) -- Must be integer
end

-- Validates a donation amount (positive number)
function ValidationUtils.isValidDonationAmount(amount: any): boolean
	return ValidationUtils.isValidNumber(amount) and amount > 0
end

--[[
	Username Validation
]]

-- Validates a Roblox username format
-- Roblox usernames: 3-20 characters, alphanumeric + underscore, no consecutive underscores
function ValidationUtils.isValidUsername(username: any): boolean
	if not ValidationUtils.isValidString(username) then
		return false
	end

	local len = #username
	if len < 3 or len > 20 then
		return false
	end

	-- Check for valid characters (alphanumeric + underscore)
	if not string.match(username, "^[%w_]+$") then
		return false
	end

	-- Check for consecutive underscores (not allowed in Roblox usernames)
	if string.match(username, "__") then
		return false
	end

	return true
end

--[[
	Rank/Leaderboard Validation
]]

-- Validates a leaderboard rank position (positive integer)
function ValidationUtils.isValidRankPosition(rank: any): boolean
	return ValidationUtils.isValidPositiveInteger(rank)
end

-- Validates a leaderboard rank index (0-based or 1-based depending on context)
function ValidationUtils.isValidRankIndex(index: any): boolean
	return ValidationUtils.isValidNonNegativeInteger(index)
end

-- Validates a statistic value (non-negative number)
function ValidationUtils.isValidStatisticValue(value: any): boolean
	return ValidationUtils.isValidNumber(value) and value >= 0
end

--[[
	Display Count Validation
]]

-- Validates a display count (positive integer, typically used for leaderboards)
function ValidationUtils.isValidDisplayCount(count: any): boolean
	return ValidationUtils.isValidPositiveInteger(count) and count <= 100
end

--[[
	Combined Validation
]]

-- Validates required table fields exist and are non-nil
function ValidationUtils.hasRequiredFields(data: any, fields: {string}): boolean
	if not ValidationUtils.isValidTable(data) then
		return false
	end

	for _, field in fields do
		if data[field] == nil then
			return false
		end
	end

	return true
end

-- Validates with detailed error message
function ValidationUtils.validateWithError(isValid: boolean, errorMessage: string): ValidationResult
	return {
		isValid = isValid,
		error = if isValid then nil else errorMessage,
	}
end

--[[
	Track Index Validation (for media players, etc.)
]]

-- Validates a track/item index is within bounds
function ValidationUtils.isValidTrackIndex(index: number, maxIndex: number): boolean
	return ValidationUtils.isValidPositiveInteger(index)
		and index >= 1
		and index <= maxIndex
end

--[[
	ID Validation (Universe, Place, etc.)
]]

-- Validates a Roblox Universe ID
function ValidationUtils.isValidUniverseId(universeId: any): boolean
	return ValidationUtils.isValidPositiveInteger(universeId)
end

-- Validates a Roblox Place ID
function ValidationUtils.isValidPlaceId(placeId: any): boolean
	return ValidationUtils.isValidPositiveInteger(placeId)
end

-- Validates a Roblox Game ID (same as Place ID)
function ValidationUtils.isValidGameId(gameId: any): boolean
	return ValidationUtils.isValidPlaceId(gameId)
end

-- Validates a gamepass asset identifier
function ValidationUtils.isValidGamepassId(gamepassId: any): boolean
	return ValidationUtils.isValidPositiveInteger(gamepassId)
end

--------------
-- Return  --
--------------
return ValidationUtils