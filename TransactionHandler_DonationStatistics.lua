--!strict

--[[
	TransactionHandler DonationStatistics Module

	Manages donation statistics tracking and leaderboard updates.
	Handles OrderedDataStore updates and player notifications.

	Returns: DonationStatistics table with statistics functions

	Usage:
		local DonationStatistics = require(...)
		DonationStatistics.updateDonationStatistics(donorId, recipientId, amount)
]]

--------------
-- Services --
--------------

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local network = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network")
local remotes = assert(network:WaitForChild("Remotes", 10), "Failed to find Remotes")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Failed to find Events")

local notificationEvent: RemoteEvent = assert(remoteEvents:WaitForChild("CreateNotification", 10), "Failed to find CreateNotification")
local messageEvent: RemoteEvent = assert(remoteEvents:WaitForChild("SendMessage", 10), "Failed to find SendMessage")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Failed to find Configuration")

local PlayerData = require(assert(Modules:WaitForChild("Managers", 10):WaitForChild("PlayerData", 10), "Failed to find PlayerData"))
local DataStoreWrapper = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("DataStore", 10), "Failed to find DataStore"))
local ValidationUtils = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("ValidationUtils", 10), "Failed to find ValidationUtils"))
local GameConfig = require(assert(Configuration:WaitForChild("GameConfig", 10), "Failed to find GameConfig"))

---------------
-- Constants --
---------------
local TAG = "[Transaction.DonationStatistics]"

local donatedAmountsOrderedDataStore = DataStoreService:GetOrderedDataStore(GameConfig.DATASTORE.DONATED_ORDERED_KEY)
local raisedAmountsOrderedDataStore = DataStoreService:GetOrderedDataStore(GameConfig.DATASTORE.RAISED_ORDERED_KEY)

local messagingConfiguration = GameConfig.MESSAGING_SERVICE_CONFIG
local LARGE_DONATION_BROADCAST_TOPIC = messagingConfiguration.LARGE_DONATION_TOPIC
local LARGE_DONATION_THRESHOLD_AMOUNT = messagingConfiguration.DONATION_THRESHOLD

local CLIENT_NOTIFICATION_TYPES = {
	SUCCESS = "Success",
	WARNING = "Warning",
	ERROR = "Error",
}

local MAX_DATASTORE_RETRIES = 3
local BASE_RETRY_DELAY = 1

local MIN_GIFT_AMOUNT = 1

local DONATION_CONFIRMATION_FORMAT = "Your %s has been sent to %s!"
local PURCHASE_CANCELLED_MESSAGE = "Your purchase was cancelled."
local DONATION_FAILED_MESSAGE = "Failed to process donation. Please try again."

local TRANSACTION_TYPE_DONATION = "donation"
local TRANSACTION_TYPE_GIFT = "gift"

local ACTION_VERB_DONATED = "donated"
local ACTION_VERB_GIFTED = "gifted"

local STAT_KEY_DONATED = "Donated"
local STAT_KEY_RAISED = "Raised"

-----------
-- Module --
-----------
local DonationStatistics = {}

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
	return ValidationUtils.isValidNumber(amount) and amount >= MIN_GIFT_AMOUNT
end

-------------------------
-- DataStore Operations --
-------------------------
local function incrementOrderedDataStore(playerId: number, targetDataStore: OrderedDataStore, incrementAmount: number): number
	if not ValidationUtils.isValidUserId(playerId) or not isValidGiftAmount(incrementAmount) then
		warnlog(
			"Invalid parameters for DataStore increment: userId=%s, amount=%s",
			tostring(playerId),
			tostring(incrementAmount)
		)
		return 0
	end

	local result = DataStoreWrapper.incrementAsync(
		targetDataStore,
		tostring(playerId),
		incrementAmount,
		{ maxRetries = MAX_DATASTORE_RETRIES, baseDelay = BASE_RETRY_DELAY }
	)

	if result.success then
		return result.data or 0
	else
		warnlog("Failed to increment DataStore for player %d: %s", playerId, result.error or "unknown")
		return 0
	end
end

-----------------------
-- Notification Helpers --
-----------------------
local function sendClientNotification(player: Player, message: string, notificationType: string): ()
	if not ValidationUtils.isValidPlayer(player) then
		warnlog("Invalid player for notification")
		return
	end

	local success = pcall(function()
		notificationEvent:FireClient(player, message, notificationType)
	end)

	if not success then
		warnlog("Failed to send notification to player %s", player.Name)
	end
end

local function formatDonationConfirmation(recipientDisplayName: string, recipientIsOnline: boolean): string
	local transactionType = if recipientIsOnline then TRANSACTION_TYPE_DONATION else TRANSACTION_TYPE_GIFT
	return string.format(DONATION_CONFIRMATION_FORMAT, transactionType, recipientDisplayName)
end

function DonationStatistics.sendDonationConfirmationToPlayer(
	donorPlayer: Player,
	recipientDisplayName: string,
	recipientIsOnline: boolean
): ()
	if not ValidationUtils.isValidPlayer(donorPlayer) then
		warnlog("Invalid donor player for confirmation")
		return
	end

	local confirmationMessage = formatDonationConfirmation(recipientDisplayName, recipientIsOnline)
	sendClientNotification(donorPlayer, confirmationMessage, CLIENT_NOTIFICATION_TYPES.SUCCESS)
end

function DonationStatistics.sendPurchaseCancellationNotification(player: Player): ()
	sendClientNotification(player, PURCHASE_CANCELLED_MESSAGE, CLIENT_NOTIFICATION_TYPES.WARNING)
end

function DonationStatistics.sendDonationFailureNotification(player: Player): ()
	sendClientNotification(player, DONATION_FAILED_MESSAGE, CLIENT_NOTIFICATION_TYPES.ERROR)
end

--------------------------
-- Announcement Helpers --
--------------------------
local function getDonationActionVerb(recipientIsOnline: boolean): string
	return if recipientIsOnline then ACTION_VERB_DONATED else ACTION_VERB_GIFTED
end

local function announceToAllClients(donorName: string, recipientName: string, actionVerb: string, amount: number): ()
	local success = pcall(function()
		messageEvent:FireAllClients(donorName, recipientName, actionVerb, amount)
	end)
	if not success then
		warnlog("Failed to announce donation to all clients")
	end
end

-- Import the broadcastToMessagingService from DonationMessaging (we'll use it through dependency injection)
local DonationMessaging = nil -- Will be set via setDonationMessagingModule

local function broadcastLargeDonation(donorName: string, recipientName: string, actionVerb: string, amount: number): ()
	if not DonationMessaging then
		warnlog("DonationMessaging module not set, cannot broadcast large donation")
		return
	end

	DonationMessaging.broadcastToMessagingService(LARGE_DONATION_BROADCAST_TOPIC, {
		Donor = donorName,
		Receiver = recipientName,
		Amount = amount,
		Filler = actionVerb,
	})
end

function DonationStatistics.announceDonationToAllPlayers(
	donorPlayer: Player,
	recipientDisplayName: string,
	donationAmount: number,
	recipientIsCurrentlyOnline: boolean
): ()
	if not ValidationUtils.isValidPlayer(donorPlayer) then
		warnlog("Invalid donor player for announcement")
		return
	end
	if not isValidGiftAmount(donationAmount) then
		warnlog("Invalid donation amount for announcement: %s", tostring(donationAmount))
		return
	end

	local donationActionVerb = getDonationActionVerb(recipientIsCurrentlyOnline)

	if donationAmount >= LARGE_DONATION_THRESHOLD_AMOUNT then
		-- Cross-server broadcast
		broadcastLargeDonation(donorPlayer.Name, recipientDisplayName, donationActionVerb, donationAmount)
	else
		-- Current server only
		announceToAllClients(donorPlayer.Name, recipientDisplayName, donationActionVerb, donationAmount)
	end
end

----------------------------
-- Statistics Integration --
----------------------------
local function updatePlayerStatistics(userId: number, statKey: string, amount: number): boolean
	local success, errorMessage = pcall(function()
		PlayerData:IncrementPlayerStatistic(userId, statKey, amount)
	end)
	if not success then
		warnlog("Failed to update player statistics for %d: %s", userId, tostring(errorMessage))
		return false
	end
	return true
end

function DonationStatistics.updateDonationStatistics(
	donorUserId: number,
	recipientUserId: number,
	transactionAmount: number
): boolean
	if
		not ValidationUtils.isValidUserId(donorUserId)
		or not ValidationUtils.isValidUserId(recipientUserId)
		or not isValidGiftAmount(transactionAmount)
	then
		warnlog(
			"Invalid statistics update parameters: donor=%s, recipient=%s, amount=%s",
			tostring(donorUserId),
			tostring(recipientUserId),
			tostring(transactionAmount)
		)
		return false
	end

	-- Cross-server ordered datastores
	local donatedSuccess = incrementOrderedDataStore(donorUserId, donatedAmountsOrderedDataStore, transactionAmount)
	local raisedSuccess = incrementOrderedDataStore(recipientUserId, raisedAmountsOrderedDataStore, transactionAmount)

	-- Local server player statistics
	local localDonatedSuccess = updatePlayerStatistics(donorUserId, STAT_KEY_DONATED, transactionAmount)
	local localRaisedSuccess = updatePlayerStatistics(recipientUserId, STAT_KEY_RAISED, transactionAmount)

	return (donatedSuccess > 0 or raisedSuccess > 0 or localDonatedSuccess or localRaisedSuccess)
end

--------------------------
-- Dependency Injection --
--------------------------
function DonationStatistics.setDonationMessagingModule(module: any): ()
	DonationMessaging = module
end

return DonationStatistics