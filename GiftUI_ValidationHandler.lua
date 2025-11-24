--!strict

--[[
	GiftUI_ValidationHandler - Input validation for gift system

	This module validates all gift-related user inputs and data:
	- Validates gift data structures from server
	- Validates usernames and user IDs
	- Prevents self-gifting
	- Retrieves user info from Roblox API

	Returns: ValidationHandler module with validation functions

	Usage:
		if ValidationHandler.isValidGiftData(data) then ... end
		local userId = ValidationHandler.retrieveUserIdFromUsername(username)
		if ValidationHandler.validateUsernameInput(username, errorCallback) then ... end
]]

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-----------
-- Types --
-----------
export type GiftData = {
	Id: any,
	Gifter: string,
	Amount: number,
	Timestamp: number,
}

---------------
-- Constants --
---------------
local TAG = "[GiftUI.ValidationHandler]"
local WAIT_TIMEOUT = 10

local ERROR_INVALID_USERNAME = "INVALID USERNAME"
local ERROR_CANNOT_GIFT_SELF = "CANNOT GIFT TO YOURSELF"

----------------
-- References --
----------------

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), TAG .. " Modules folder not found")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

---------------
-- Functions --
---------------

local function isValidGiftData(data: any): boolean
	if typeof(data) ~= "table" then
		return false
	end
	return data.Id ~= nil
		and ValidationUtils.isValidString(data.Gifter)
		and ValidationUtils.isValidNumber(data.Amount)
		and data.Amount >= 0
		and ValidationUtils.isValidNumber(data.Timestamp)
		and data.Timestamp >= 0
end

local function retrieveUserIdFromUsername(playerUsername: string): number?
	if not ValidationUtils.isValidUsername(playerUsername) then
		return nil
	end
	local success, result = pcall(Players.GetUserIdFromNameAsync, Players, playerUsername)
	return success and result or nil
end

local function retrieveUsernameFromUserId(userId: number): string?
	if not (ValidationUtils.isValidNumber(userId) and userId >= 0) then
		return nil
	end
	local success, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return success and result or nil
end

local function validateUsernameInput(
	username: string,
	displayTemporaryErrorMessage: (errorMessage: string) -> ()
): boolean
	assert(typeof(username) == "string", "validateUsernameInput: username must be a string")
	assert(displayTemporaryErrorMessage, "validateUsernameInput: displayTemporaryErrorMessage is required")

	if not ValidationUtils.isValidUsername(username) then
		displayTemporaryErrorMessage(ERROR_INVALID_USERNAME)
		return false
	end
	return true
end

local function validateTargetUserId(
	userId: number?,
	displayTemporaryErrorMessage: (errorMessage: string) -> ()
): boolean
	assert(displayTemporaryErrorMessage, "validateTargetUserId: displayTemporaryErrorMessage is required")

	if not userId then
		displayTemporaryErrorMessage(ERROR_INVALID_USERNAME)
		return false
	end
	return true
end

local function validateTargetUsername(
	username: string?,
	displayTemporaryErrorMessage: (errorMessage: string) -> ()
): boolean
	assert(displayTemporaryErrorMessage, "validateTargetUsername: displayTemporaryErrorMessage is required")

	if not username then
		displayTemporaryErrorMessage(ERROR_INVALID_USERNAME)
		return false
	end
	return true
end

local function isGiftingToSelf(
	username: string,
	localPlayerName: string,
	displayTemporaryErrorMessage: (errorMessage: string) -> ()
): boolean
	assert(typeof(username) == "string", "isGiftingToSelf: username must be a string")
	assert(typeof(localPlayerName) == "string", "isGiftingToSelf: localPlayerName must be a string")
	assert(displayTemporaryErrorMessage, "isGiftingToSelf: displayTemporaryErrorMessage is required")

	if username == localPlayerName then
		displayTemporaryErrorMessage(ERROR_CANNOT_GIFT_SELF)
		return true
	end
	return false
end

-----------
-- Setup --
-----------

local ValidationHandler = {
	isValidGiftData = isValidGiftData,
	retrieveUserIdFromUsername = retrieveUserIdFromUsername,
	retrieveUsernameFromUserId = retrieveUsernameFromUserId,
	validateUsernameInput = validateUsernameInput,
	validateTargetUserId = validateTargetUserId,
	validateTargetUsername = validateTargetUsername,
	isGiftingToSelf = isGiftingToSelf,
}

return ValidationHandler