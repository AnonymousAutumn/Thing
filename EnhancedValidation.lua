--!strict

--[[
	EnhancedValidation

	Provides comprehensive input validation for RemoteEvent arguments with type checking,
	bounds validation, NaN/Infinity detection, and security helpers for player actions.

	Returns: Table with validation functions:
		- validateRemoteArgs: Validates multiple RemoteEvent arguments
		- validatePlayer, validateNumber, validateString: Type-specific validators
		- validatePositiveInteger, validateUserId: Common pattern validators
		- validateVector3, validateCFrame: Geometric type validators
		- isActionPhysicallyPossible: Security helper for distance checks

	Usage:
		local EnhancedValidation = require(script.EnhancedValidation)
		if not EnhancedValidation.validateRemoteArgs(player, {
			{column, "number", {min = 1, max = 7}},
			{message, "string", {maxLength = 100}}
		}) then
			return -- Invalid input
		end
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

-----------
-- Types --
-----------

export type ArgumentValidator = {
	value: any,
	expectedType: string,
	constraints: ValidationConstraints?,
}

export type ValidationConstraints = {
	min: number?,
	max: number?,
	minLength: number?,
	maxLength: number?,
	allowNil: boolean?,
	customValidator: ((any) -> boolean)?,
}


--[[export type RemoteArgValidation = {
	{any, string, ValidationConstraints?}
}]]

---------------
-- Constants --
---------------
local TAG = "[EnhancedValidation]"

-- Default constraints for common types
local DEFAULT_STRING_MAX_LENGTH = 1000 -- Prevent chat spam, long strings
local DEFAULT_NUMBER_MIN = -1e9
local DEFAULT_NUMBER_MAX = 1e9

local EnhancedValidation = {}

---------------
-- Logging --
---------------
local function warnlog(message: string, ...: any): ()
	warn(string.format(TAG .. " " .. message, ...))
end

--[[
	TYPE VALIDATION (Step 1 of 9-step pattern)
]]

--- Validates a single argument type
local function validateArgumentType(value: any, expectedType: string, allowNil: boolean?): boolean
	if allowNil and value == nil then
		return true
	end

	return typeof(value) == expectedType
end

--[[
	BOUNDS/RANGE VALIDATION (Step 2 of 9-step pattern)
]]

--- Validates number is within bounds
local function validateNumberBounds(value: number, constraints: ValidationConstraints?): boolean
	if not ValidationUtils.isValidNumber(value) then
		return false
	end

	local min = if constraints and constraints.min then constraints.min else DEFAULT_NUMBER_MIN
	local max = if constraints and constraints.max then constraints.max else DEFAULT_NUMBER_MAX

	return value >= min and value <= max
end

--- Validates string length
local function validateStringLength(value: string, constraints: ValidationConstraints?): boolean
	local length = #value
	local minLength = if constraints and constraints.minLength then constraints.minLength else 0
	local maxLength = if constraints and constraints.maxLength then constraints.maxLength else DEFAULT_STRING_MAX_LENGTH

	return length >= minLength and length <= maxLength
end

--[[
	NaN/INFINITY VALIDATION (Step 3 of 9-step pattern)
]]

--- Validates number is not NaN or Infinity
local function validateNumberSanity(value: any): boolean
	if typeof(value) ~= "number" then
		return true -- Not a number, so NaN/Infinity check doesn't apply
	end

	-- Use ValidationUtils which already has this check
	return ValidationUtils.isValidNumber(value)
end

--[[
	COMBINED VALIDATION
]]

--- Validates a single argument against all constraints
local function validateSingleArgument(value: any, expectedType: string, constraints: ValidationConstraints?): boolean
	local allowNil = constraints and constraints.allowNil or false

	-- Type check
	if not validateArgumentType(value, expectedType, allowNil) then
		return false
	end

	-- If nil and allowed, we're done
	if allowNil and value == nil then
		return true
	end

	-- Type-specific validation
	if expectedType == "number" then
		-- NaN/Infinity check
		if not validateNumberSanity(value) then
			return false
		end

		-- Bounds check
		if not validateNumberBounds(value, constraints) then
			return false
		end
	elseif expectedType == "string" then
		-- Length check
		if not validateStringLength(value, constraints) then
			return false
		end
	end

	-- Custom validator if provided
	if constraints and constraints.customValidator then
		if not constraints.customValidator(value) then
			return false
		end
	end

	return true
end

--[[
	PUBLIC API
]]

--- Validates multiple RemoteEvent arguments in one call
--- @param player Player - The player who sent the RemoteEvent
--- @param validations RemoteArgValidation - Array of {value, expectedType, constraints?}
--- @return boolean - True if all arguments are valid
function EnhancedValidation.validateRemoteArgs(player: Player, validations): boolean
	-- Validate player first (they send the event)
	if not ValidationUtils.isValidPlayer(player) then
		warnlog("Invalid player in RemoteEvent")
		return false
	end

	-- Validate each argument
	for _, validation in validations do
		local value = validation[1]
		local expectedType = validation[2]
		local constraints = validation[3]

		if not validateSingleArgument(value, expectedType, constraints) then
			warnlog("Invalid argument from player %s: expected %s", player.Name, expectedType)
			return false
		end
	end

	return true
end

--- Validates a player argument (Step 1 shorthand)
--- @param player any - The value to validate as a player
--- @return boolean
function EnhancedValidation.validatePlayer(player: any): boolean
	return ValidationUtils.isValidPlayer(player)
end

--- Validates a number with NaN/Infinity checks (Steps 1-3 combined)
--- @param value any - The value to validate
--- @param min number? - Minimum allowed value
--- @param max number? - Maximum allowed value
--- @return boolean
function EnhancedValidation.validateNumber(value: any, min: number?, max: number?): boolean
	return validateSingleArgument(value, "number", {
		min = min,
		max = max,
	})
end

--- Validates a string with length checks
--- @param value any - The value to validate
--- @param minLength number? - Minimum string length
--- @param maxLength number? - Maximum string length
--- @return boolean
function EnhancedValidation.validateString(value: any, minLength: number?, maxLength: number?): boolean
	return validateSingleArgument(value, "string", {
		minLength = minLength,
		maxLength = maxLength,
	})
end

--- Validates a positive integer (common for IDs, amounts)
--- @param value any - The value to validate
--- @param max number? - Maximum allowed value
--- @return boolean
function EnhancedValidation.validatePositiveInteger(value: any, max: number?): boolean
	if not ValidationUtils.isValidNumber(value) then
		return false
	end

	if value < 1 then
		return false
	end

	if value ~= math.floor(value) then
		return false
	end

	if max and value > max then
		return false
	end

	return true
end

--- Validates a user ID
--- @param userId any - The value to validate
--- @return boolean
function EnhancedValidation.validateUserId(userId: any): boolean
	return ValidationUtils.isValidUserId(userId)
end

--- Validates a table has required fields
--- @param data any - The table to validate
--- @param requiredFields {string} - Array of required field names
--- @return boolean
function EnhancedValidation.validateRequiredFields(data: any, requiredFields: {string}): boolean
	return ValidationUtils.hasRequiredFields(data, requiredFields)
end

--[[
	SECURITY HELPERS
]]

--- Checks if a player action is physically possible (Step 7 helper)
--- @param player Player
--- @param targetPosition Vector3?
--- @param maxDistance number?
--- @return boolean
function EnhancedValidation.isActionPhysicallyPossible(
	player: Player,
	targetPosition: Vector3?,
	maxDistance: number?
): boolean
	if not ValidationUtils.isValidPlayer(player) then
		return false
	end

	local character = player.Character
	if not ValidationUtils.isValidCharacter(character) then
		return false
	end

	-- If no target position specified, just verify player has character
	if not targetPosition then
		return true
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
		return false
	end

	local distance = (humanoidRootPart.Position - targetPosition).Magnitude
	local max = maxDistance or 100 -- Default max interaction distance

	return distance <= max
end

--- Validates that a number array contains only valid numbers (no NaN/Infinity)
--- @param array any
--- @return boolean
function EnhancedValidation.validateNumberArray(array: any): boolean
	if typeof(array) ~= "table" then
		return false
	end

	for _, value in array do
		if not ValidationUtils.isValidNumber(value) then
			return false
		end
	end

	return true
end

--- Validates Vector3 (no NaN/Infinity in components)
--- @param vector any
--- @return boolean
function EnhancedValidation.validateVector3(vector: any): boolean
	if typeof(vector) ~= "Vector3" then
		return false
	end

	return ValidationUtils.isValidNumber(vector.X)
		and ValidationUtils.isValidNumber(vector.Y)
		and ValidationUtils.isValidNumber(vector.Z)
end

--- Validates CFrame (no NaN/Infinity in components)
--- @param cframe any
--- @return boolean
function EnhancedValidation.validateCFrame(cframe: any): boolean
	if typeof(cframe) ~= "CFrame" then
		return false
	end

	local position = cframe.Position
	return ValidationUtils.isValidNumber(position.X)
		and ValidationUtils.isValidNumber(position.Y)
		and ValidationUtils.isValidNumber(position.Z)
end

--------------
-- Return  --
--------------
return EnhancedValidation