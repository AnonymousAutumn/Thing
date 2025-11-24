--!strict

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------
-- Modules  --
--------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

---------------
-- Constants --
---------------
local UNWANTED_INSTANCE_CLASSES = { "Sound", "LocalScript" }
local CHARACTER_RIG_NAME_PREFIX = "ViewportRig_"

local MAX_CHARACTER_CREATION_RETRIES = 3
local CHARACTER_CREATION_RETRY_DELAY = 1
local CHARACTER_CREATION_TIMEOUT = 10

-----------
-- Module --
-----------
local RigBuilder = {}

-- External dependencies (set by RigCreator)
RigBuilder.safeExecute = nil :: (((() -> ()) -> boolean))?
RigBuilder.positionCharacterAtRankLocation = nil :: ((Model, Model) -> boolean)?

--[[
	Checks if an instance should be removed from character model

	Removes unwanted classes like Sound and LocalScript for performance.

	@param instance Instance - The instance to check
	@return boolean - True if should be removed
]]
local function shouldRemoveInstance(instance: Instance): boolean
	for _, unwantedClassName in ipairs(UNWANTED_INSTANCE_CLASSES) do
		if instance:IsA(unwantedClassName) then
			return true
		end
	end
	return false
end

--[[
	Removes unwanted instances from a character model

	Cleans up sounds, scripts, and other unnecessary instances.

	@param characterModel Model - The character model to clean
]]
function RigBuilder.removeUnwantedInstancesFromModel(characterModel: Model): ()
	if not characterModel or not characterModel:IsA("Model") then
		return
	end

	if not RigBuilder.safeExecute then
		return
	end

	RigBuilder.safeExecute(function()
		for _, modelDescendant in ipairs(characterModel:GetDescendants()) do
			if shouldRemoveInstance(modelDescendant) then
				modelDescendant:Destroy()
			end
		end
	end)
end

--[[
	Checks if character creation has timed out

	@param startTime number - The creation start time
	@param timeout number - Timeout in seconds
	@return boolean - True if timed out
]]
local function hasTimedOut(startTime: number, timeout: number): boolean
	return os.clock() - startTime > timeout
end

--[[
	Creates a character rig from user ID

	@param playerUserId number - The player's user ID
	@param startTime number - Creation start time for timeout tracking
	@return Model? - The created rig, or error on timeout
]]
local function createCharacterRig(playerUserId: number, startTime: number): Model?
	local rig = Players:CreateHumanoidModelFromUserId(playerUserId)

	if hasTimedOut(startTime, CHARACTER_CREATION_TIMEOUT) then
		error("Character creation timeout")
	end

	return rig
end

--[[
	Configures a created character rig

	Sets name, positions, removes unwanted instances, and parents to WorldModel.

	@param createdCharacterRig Model - The rig to configure
	@param playerUserId number - The player's user ID
	@param rankPositionReference Model - Position reference for the rank
	@param worldModel WorldModel - The WorldModel to parent to
]]
local function configureCharacterRig(
	createdCharacterRig: Model,
	playerUserId: number,
	rankPositionReference: Model,
	worldModel: WorldModel
): ()
	createdCharacterRig.Name = CHARACTER_RIG_NAME_PREFIX .. tostring(playerUserId)

	if RigBuilder.positionCharacterAtRankLocation then
		RigBuilder.positionCharacterAtRankLocation(createdCharacterRig, rankPositionReference)
	end

	RigBuilder.removeUnwantedInstancesFromModel(createdCharacterRig)
	createdCharacterRig.Parent = worldModel
end

--[[
	Attempts to create a character rig

	@param playerUserId number - The player's user ID
	@param rankPositionReference Model - Position reference for the rank
	@param worldModel WorldModel - The WorldModel to parent to
	@return Model? - The created rig, or nil on failure
]]
local function attemptCharacterCreation(
	playerUserId: number,
	rankPositionReference: Model,
	worldModel: WorldModel
): Model?
	local startTime = os.clock()

	local createSuccess, createdCharacterRig = pcall(function()
		return createCharacterRig(playerUserId, startTime)
	end)

	if not createSuccess or not createdCharacterRig or not createdCharacterRig:IsA("Model") then
		return nil
	end

	local configureSuccess = pcall(function()
		configureCharacterRig(createdCharacterRig, playerUserId, rankPositionReference, worldModel)
	end)

	if not configureSuccess then
		createdCharacterRig:Destroy()
		return nil
	end

	return createdCharacterRig
end

--[[
	Creates a player character for display with retry logic

	Attempts creation up to MAX_CHARACTER_CREATION_RETRIES times with
	exponential backoff on failure.

	@param playerUserId number - The player's user ID
	@param rankPositionReference Model - Position reference for the rank
	@param worldModel WorldModel - The WorldModel to parent to
	@return Model? - The created rig, or nil on failure
]]
function RigBuilder.createPlayerCharacterForDisplay(
	playerUserId: number,
	rankPositionReference: Model,
	worldModel: WorldModel
): Model?
	if not ValidationUtils.isValidUserId(playerUserId) or not rankPositionReference or not rankPositionReference:IsA("Model") then
		return nil
	end

	for attempt = 1, MAX_CHARACTER_CREATION_RETRIES do
		local createdCharacterRig = attemptCharacterCreation(playerUserId, rankPositionReference, worldModel)

		if createdCharacterRig then
			return createdCharacterRig
		end

		if attempt < MAX_CHARACTER_CREATION_RETRIES then
			task.wait(CHARACTER_CREATION_RETRY_DELAY * attempt)
		end
	end

	return nil
end

-- Export constants for use in main module
RigBuilder.CHARACTER_RIG_NAME_PREFIX = CHARACTER_RIG_NAME_PREFIX

return RigBuilder