--!strict

--------------
-- Services --
--------------

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local Network = ReplicatedStorage:WaitForChild("Network")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local SendNotificationEvent = Network.Remotes.Events.CreateNotification

local UsernameCache = require(Modules.Caches.UsernameCache)
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local GameConfig = require(Configuration.GameConfig)

-----------
-- Types --
-----------

export type GamepassProductInfo = {
	Creator: { Id: number }?,
	PriceInRobux: number?,
	[string]: any,
}

---------------
-- Constants --
---------------

local TAG = "[Transaction.PurchaseFlow]"

local MAX_DATASTORE_RETRIES = 3
local BASE_RETRY_DELAY = 1

-----------
-- Module --
-----------
local PurchaseFlow = {}

---------------
-- Variables --
---------------
-- Dependencies (set via dependency injection)
local GiftPersistence = nil
local DonationStatistics = nil
local DonationMessaging = nil

---------------
-- Logging --
---------------
local function log(message: string, ...: any): ()
	print(string.format(TAG .. " " .. message, ...))
end

local function warnlog(message: string, ...: any): ()
	warn(string.format(TAG .. " " .. message, ...))
end

---------------
-- Validation --
---------------
local function isValidGiftAmount(amount: any): boolean
	return ValidationUtils.isValidNumber(amount) and amount >= 1 
end

local function isValidGamepassInfo(info: any): boolean
	if typeof(info) ~= "table" then
		return false
	end
	return info.Creator ~= nil
		and typeof(info.Creator) == "table"
		and ValidationUtils.isValidUserId(info.Creator.Id)
end

---------------
-- Helpers --
---------------
local function calculateRetryDelay(attemptNumber: number): number
	return BASE_RETRY_DELAY * attemptNumber
end

-----------------------------
-- Product Info Retrieval --
-----------------------------
local function fetchGamepassProductInfo(gamepassAssetId: number)
	for attempt = 1, MAX_DATASTORE_RETRIES do
		local success, result = pcall(function()
			return MarketplaceService:GetProductInfo(gamepassAssetId, Enum.InfoType.GamePass)
		end)

		if success and isValidGamepassInfo(result) then
			return result
		end

		warnlog("GetProductInfo attempt %d/%d failed: %s", attempt, MAX_DATASTORE_RETRIES, tostring(result))

		if attempt < MAX_DATASTORE_RETRIES then
			task.wait(calculateRetryDelay(attempt))
		end
	end

	return nil
end

local function extractCreatorInfo(gamepassProductInfo: GamepassProductInfo): (number?, number?)
	local creatorUserId = gamepassProductInfo.Creator and gamepassProductInfo.Creator.Id
	local priceInRobux = gamepassProductInfo.PriceInRobux or 0

	if not ValidationUtils.isValidUserId(creatorUserId) then
		warnlog("Invalid creator user ID from gamepass info")
		return nil, nil
	end
	if not isValidGiftAmount(priceInRobux) then
		warnlog("Invalid gamepass price: %s", tostring(priceInRobux))
		return nil, nil
	end

	return creatorUserId, priceInRobux
end

--------------------------
-- Purchase Processing --
--------------------------
local function processSuccessfulPurchase(purchasingPlayer: Player, gamepassAssetId: number): ()
	local gamepassProductInfo = fetchGamepassProductInfo(gamepassAssetId)
	if not gamepassProductInfo then
		warnlog("Failed to retrieve product information for gamepass %d", gamepassAssetId)
		if DonationStatistics then
			DonationStatistics.sendDonationFailureNotification(purchasingPlayer)
		end
		return
	end

	local creatorUserId, priceInRobux = extractCreatorInfo(gamepassProductInfo)
	if not creatorUserId or not priceInRobux then
		return
	end

	local creatorPlayerInstance = Players:GetPlayerByUserId(creatorUserId)
	local creatorDisplayName = UsernameCache.getUsername(creatorUserId)
	local creatorIsOnline = creatorPlayerInstance ~= nil

	-- Update statistics
	if DonationStatistics then
		local statsUpdated = DonationStatistics.updateDonationStatistics(
			purchasingPlayer.UserId,
			creatorUserId,
			priceInRobux
		)
		if not statsUpdated then
			warnlog("Failed to update donation statistics")
		end
	end

	-- Save gift if creator is offline
	if not creatorIsOnline and GiftPersistence then
		local giftSaved = GiftPersistence.saveGiftToDataStore(purchasingPlayer.UserId, creatorUserId, priceInRobux)
		if not giftSaved then
			warnlog("Failed to save gift to DataStore")
		end
	end

	-- Send confirmation to donor
	if DonationStatistics then
		DonationStatistics.sendDonationConfirmationToPlayer(purchasingPlayer, creatorDisplayName, creatorIsOnline)
	end
	
	purchasingPlayer:SetAttribute(tostring(gamepassAssetId), true)

	-- Live donation broadcast (numeric IDs and amount)
	if DonationMessaging then
		local messagingConfiguration = GameConfig.MESSAGING_SERVICE_CONFIG
		local LIVE_DONATION_BROADCAST_TOPIC = messagingConfiguration.LIVE_DONATION_TOPIC

		DonationMessaging.broadcastToMessagingService(LIVE_DONATION_BROADCAST_TOPIC, {
			Donor = purchasingPlayer.UserId,
			Receiver = creatorUserId,
			Amount = priceInRobux,
		})
	end

	-- Announce donation to all players
	if DonationStatistics then
		DonationStatistics.announceDonationToAllPlayers(
			purchasingPlayer,
			creatorDisplayName,
			priceInRobux,
			creatorIsOnline
		)
	end
end

function PurchaseFlow.handleGamepassPurchaseCompletion(
	purchasingPlayer: Player,
	gamepassAssetId: number,
	purchaseWasSuccessful: boolean
): ()
	if not ValidationUtils.isValidPlayer(purchasingPlayer) then
		warnlog("Invalid player for purchase completion")
		return
	end

	if not purchaseWasSuccessful then
		if DonationStatistics then
			DonationStatistics.sendPurchaseCancellationNotification(purchasingPlayer)
		end
		return
	end

	for _, pass in pairs(GameConfig.MONETIZATION) do
		if gamepassAssetId == pass then
			local gamepassProductInfo = fetchGamepassProductInfo(gamepassAssetId)
			
			if gamepassProductInfo then
				SendNotificationEvent:FireClient(purchasingPlayer, string.format("You purchased the %s pass!", gamepassProductInfo.Name), "Success")
				
				local statsUpdated = DonationStatistics.updateDonationStatistics(
					purchasingPlayer.UserId,
					game.CreatorId,
					gamepassProductInfo.PriceInRobux
				)
				if not statsUpdated then
					warnlog("Failed to update donation statistics")
				end	
			end
			
			purchasingPlayer:SetAttribute(tostring(gamepassAssetId), true)
				
			return
		end
	end

	task.spawn(processSuccessfulPurchase, purchasingPlayer, gamepassAssetId)
end

--------------------------
-- Dependency Injection --
--------------------------
function PurchaseFlow.setGiftPersistenceModule(module: any): ()
	GiftPersistence = module
end

function PurchaseFlow.setDonationStatisticsModule(module: any): ()
	DonationStatistics = module
end

function PurchaseFlow.setDonationMessagingModule(module: any): ()
	DonationMessaging = module
end

return PurchaseFlow