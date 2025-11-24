--!strict

--------------
-- Services --
--------------

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------
-- Modules  --
--------------

local modules = ReplicatedStorage:WaitForChild("Modules")
local validationUtils = require(modules.Utilities.ValidationUtils)

-----------
-- Types --
-----------

export type PurchaseConfig = {
	player: Player,
	assetId: number,
	isDevProduct: boolean,
	onSuccess: (() -> ())?,
	onError: ((errorType: string, message: string) -> ())?,
	sounds: {
		click: Sound?,
		error: Sound?,
	}?,
	cooldownSeconds: number?,
}

export type PurchaseResult = {
	success: boolean,
	errorType: string?,
	errorMessage: string?,
}

---------------
-- Constants --
---------------

local DEFAULT_PURCHASE_COOLDOWN_SECONDS = 1

local MAX_DATASTORE_RETRIES = 3
local BASE_RETRY_DELAY = 1

local PURCHASE_ERROR_TYPES = {
	ALREADY_PROCESSING = "ALREADY_PROCESSING",
	PROMPTS_DISABLED = "PROMPTS_DISABLED",
	INVALID_ASSET_ID = "INVALID_ASSET_ID",
	IS_CREATOR = "IS_CREATOR",
	ALREADY_OWNED = "ALREADY_OWNED",
	API_ERROR = "API_ERROR",
}

local ERROR_MESSAGES = {
	CANNOT_PURCHASE_CREATED = "Cannot purchase your own passes!",
	CANNOT_PURCHASE_OWNED = "You already own that pass!",
	PROMPTS_DISABLED = "Purchases are currently disabled",
	INVALID_ASSET = "Invalid gamepass",
}

---------------
-- Variables --
---------------

local isPurchaseCurrentlyProcessing = false

---------------
-- Functions --
---------------

local function calculateRetryDelay(attemptNumber: number): number
	return BASE_RETRY_DELAY * attemptNumber
end

-- Resets purchase processing state after cooldown
local function resetPurchaseProcessingState(cooldownSeconds: number): ()
	task.delay(cooldownSeconds, function()
		isPurchaseCurrentlyProcessing = false
	end)
end

-- Checks if prompts are disabled via player attribute
local function arePromptsDisabled(player: Player): boolean
	return player:GetAttribute("PromptsDisabled") == true
end

-- Validates gamepass asset ID
local function isValidGamePassAssetId(assetId: number): boolean
	return validationUtils.isValidNumber(assetId) and assetId > 0
end

-- Checks if player is the creator of the gamepass
local function isPlayerGamePassCreator(player: Player, assetId: number): (boolean, boolean)
	local success, result = pcall(function()
		local productInfo = MarketplaceService:GetProductInfo(assetId, Enum.InfoType.GamePass)
		return productInfo.Creator.Id == player.UserId
	end)

	if success then
		return true, result
	end

	return false, false
end

-- Checks if player owns the gamepass
local function doesPlayerOwnGamePass(player: Player, assetId: number): (boolean, boolean)
	local success, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, assetId)
	end)

	-- If API call worked:
	if success then
		if ownsPass then
			return true, true   -- owns the pass
		end
	end

	-- If not owned via API, try attribute fallback
	if player:GetAttribute(tostring(assetId)) == true then
		return true, true
	end

	-- Final fallback: definitely does NOT own pass
	return true, false
end

local function fetchGamepassProductInfo(gamepassAssetId: number)
	for attempt = 1, MAX_DATASTORE_RETRIES do
		local success, result = pcall(function()
			return MarketplaceService:GetProductInfo(gamepassAssetId, Enum.InfoType.GamePass)
		end)

		if success then
			return result
		end

		warn("GetProductInfo attempt %d/%d failed: %s", attempt, MAX_DATASTORE_RETRIES, tostring(result))

		if attempt < MAX_DATASTORE_RETRIES then
			task.wait(calculateRetryDelay(attempt))
		end
	end

	return nil
end

-- Plays a sound safely
local function playSound(sound: Sound?): ()
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

----------------
-- Public API --
----------------

local GamePassPurchaseHandler = {}

--[[
	Attempts to purchase a gamepass with full validation

	@param config - Purchase configuration
	@return PurchaseResult - Result of the purchase attempt
]]
function GamePassPurchaseHandler.attemptPurchase(config: PurchaseConfig): PurchaseResult
	-- Early validation: Check if already processing
	if isPurchaseCurrentlyProcessing then
		return {
			success = false,
			errorType = PURCHASE_ERROR_TYPES.ALREADY_PROCESSING,
			errorMessage = nil,
		}
	end

	-- Check if prompts are disabled
	if arePromptsDisabled(config.player) then
		return {
			success = false,
			errorType = PURCHASE_ERROR_TYPES.PROMPTS_DISABLED,
			errorMessage = ERROR_MESSAGES.PROMPTS_DISABLED,
		}
	end

	-- Validate asset ID
	if not isValidGamePassAssetId(config.assetId) then
		return {
			success = false,
			errorType = PURCHASE_ERROR_TYPES.INVALID_ASSET_ID,
			errorMessage = ERROR_MESSAGES.INVALID_ASSET,
		}
	end

	-- Set processing state
	isPurchaseCurrentlyProcessing = true
	local cooldownSeconds = config.cooldownSeconds or DEFAULT_PURCHASE_COOLDOWN_SECONDS
	resetPurchaseProcessingState(cooldownSeconds)

	-- Play click sound
	if config.sounds then
		playSound(config.sounds.click)
	end

	-- Check if player is creator
	--[[local creatorCheckSuccess, isCreator = isPlayerGamePassCreator(config.player, config.assetId)
	if isCreator then
		if config.sounds then
			playSound(config.sounds.error)
		end
		if config.onError then
			config.onError(PURCHASE_ERROR_TYPES.IS_CREATOR, ERROR_MESSAGES.CANNOT_PURCHASE_CREATED)
		end
		return {
			success = false,
			errorType = PURCHASE_ERROR_TYPES.IS_CREATOR,
			errorMessage = ERROR_MESSAGES.CANNOT_PURCHASE_CREATED,
		}
	end

	-- Check if player owns the pass
	local ownershipCheckSuccess, ownsPass = doesPlayerOwnGamePass(config.player, config.assetId)
	if ownsPass then
		if config.sounds then
			playSound(config.sounds.error)
		end
		if config.onError then
			config.onError(PURCHASE_ERROR_TYPES.ALREADY_OWNED, ERROR_MESSAGES.CANNOT_PURCHASE_OWNED)
		end
		return {
			success = false,
			errorType = PURCHASE_ERROR_TYPES.ALREADY_OWNED,
			errorMessage = ERROR_MESSAGES.CANNOT_PURCHASE_OWNED,
		}
	end]]

	-- All checks passed - prompt purchase
	if config.isDevProduct then
		MarketplaceService:PromptProductPurchase(config.player, config.assetId)
	else
		MarketplaceService:PromptGamePassPurchase(config.player, config.assetId)
	end

	if config.onSuccess then
		config.onSuccess()
	end

	return {
		success = true,
		errorType = nil,
		errorMessage = nil,
	}
end

--[[
	Checks if prompts are currently disabled for a player

	@param player - The player to check
	@return boolean - True if prompts are disabled
]]
function GamePassPurchaseHandler.arePromptsDisabled(player: Player): boolean
	return arePromptsDisabled(player)
end

--[[
	Checks if a purchase is currently being processed

	@return boolean - True if processing
]]
function GamePassPurchaseHandler.isProcessing(): boolean
	return isPurchaseCurrentlyProcessing
end

--[[
	Validates a gamepass asset ID

	@param assetId - The asset ID to validate
	@return boolean - True if valid
]]
function GamePassPurchaseHandler.isValidAssetId(assetId: any): boolean
	return isValidGamePassAssetId(assetId)
end

--[[
	Gets the error message for an error type

	@param errorType - The error type
	@return string - The error message
]]
function GamePassPurchaseHandler.getErrorMessage(errorType: string): string?
	if errorType == PURCHASE_ERROR_TYPES.IS_CREATOR then
		return ERROR_MESSAGES.CANNOT_PURCHASE_CREATED
	elseif errorType == PURCHASE_ERROR_TYPES.ALREADY_OWNED then
		return ERROR_MESSAGES.CANNOT_PURCHASE_OWNED
	elseif errorType == PURCHASE_ERROR_TYPES.PROMPTS_DISABLED then
		return ERROR_MESSAGES.PROMPTS_DISABLED
	elseif errorType == PURCHASE_ERROR_TYPES.INVALID_ASSET_ID then
		return ERROR_MESSAGES.INVALID_ASSET
	end
	return nil
end

------------
-- Return --
------------

GamePassPurchaseHandler.doesPlayerOwnPass = doesPlayerOwnGamePass
GamePassPurchaseHandler.isPlayerCreator = isPlayerGamePassCreator
GamePassPurchaseHandler.fetchPassInfo = fetchGamepassProductInfo

return GamePassPurchaseHandler