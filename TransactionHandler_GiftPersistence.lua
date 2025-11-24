--!strict

--[[
	TransactionHandler GiftPersistence Module

	Handles gift storage and retrieval in DataStores.
	Manages offline donation tracking for players.

	Returns: GiftPersistence table with persistence functions

	Usage:
		local GiftPersistence = require(...)
		GiftPersistence.saveGiftToDataStore(donorId, recipientId, amount)
]]

--------------
-- Services --
--------------

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Failed to find Configuration")

local UsernameCache = require(assert(Modules:WaitForChild("Caches", 10):WaitForChild("UsernameCache", 10), "Failed to find UsernameCache"))
local DataStoreWrapper = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("DataStore", 10), "Failed to find DataStore"))
local ValidationUtils = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("ValidationUtils", 10), "Failed to find ValidationUtils"))
local GameConfig = require(assert(Configuration:WaitForChild("GameConfig", 10), "Failed to find GameConfig"))

-----------
-- Types --
-----------

export type GiftRecord = {
	from: number,
	amount: number,
	timestamp: number,
	id: string,
}

export type FormattedGift = {
	Id: string,
	Gifter: string,
	Amount: number,
	Timestamp: number,
}

---------------
-- Constants --
---------------
local TAG = "[Transaction.GiftPersistence]"

local giftStorageDataStore = DataStoreService:GetDataStore(GameConfig.DATASTORE.GIFTS_KEY)

local MAX_DATASTORE_RETRIES = 3
local BASE_RETRY_DELAY = 1

local MIN_GIFT_AMOUNT = 1
local MAX_GIFTS_PER_PLAYER = 100

-----------
-- Module --
-----------
local GiftPersistence = {}

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
	return ValidationUtils.isValidNumber(amount)
		and amount >= MIN_GIFT_AMOUNT
end

local function isValidGiftRecord(record: any): boolean
	if typeof(record) ~= "table" then
		return false
	end
	return ValidationUtils.isValidUserId(record.from)
		and isValidGiftAmount(record.amount)
		and typeof(record.timestamp) == "number"
		and typeof(record.id) == "string"
end

----------------------
-- Gift Construction --
----------------------
local function constructGiftRecord(donorUserId: number, giftAmount: number): GiftRecord?
	if not ValidationUtils.isValidUserId(donorUserId) or not isValidGiftAmount(giftAmount) then
		warnlog("Invalid gift record parameters: donor=%s, amount=%s", tostring(donorUserId), tostring(giftAmount))
		return nil
	end

	return {
		from = donorUserId,
		amount = giftAmount,
		timestamp = os.time(),
		id = HttpService:GenerateGUID(false),
	}
end

local function validateGiftRecords(records: any): { GiftRecord }
	local validRecords = {}

	if type(records) ~= "table" then
		return validRecords
	end

	for _, record in records do
		if isValidGiftRecord(record) then
			table.insert(validRecords, record)
		end
	end

	return validRecords
end

local function enforceGiftLimit(giftHistory: { GiftRecord }, recipientUserId: number): ()
	if #giftHistory >= MAX_GIFTS_PER_PLAYER then
		warnlog("Player %d has reached maximum gift limit (%d)", recipientUserId, MAX_GIFTS_PER_PLAYER)
		table.remove(giftHistory, 1)
	end
end

---------------------
-- DataStore Operations --
---------------------
function GiftPersistence.saveGiftToDataStore(donorUserId: number, recipientUserId: number, giftAmount: number): boolean
	if not ValidationUtils.isValidUserId(donorUserId)
		or not ValidationUtils.isValidUserId(recipientUserId)
		or not isValidGiftAmount(giftAmount) then
		warnlog(
			"Invalid gift save parameters: donor=%s, recipient=%s, amount=%s",
			tostring(donorUserId),
			tostring(recipientUserId),
			tostring(giftAmount)
		)
		return false
	end

	local recipientDataKey = tostring(recipientUserId)

	local result = DataStoreWrapper.updateAsync(
		giftStorageDataStore,
		recipientDataKey,
		function(existingGiftRecords)
			local recipientGiftHistory = validateGiftRecords(existingGiftRecords)
			enforceGiftLimit(recipientGiftHistory, recipientUserId)

			local newGift = constructGiftRecord(donorUserId, giftAmount)
			if newGift then
				table.insert(recipientGiftHistory, newGift)
			end

			return recipientGiftHistory
		end,
		{ maxRetries = MAX_DATASTORE_RETRIES, baseDelay = BASE_RETRY_DELAY }
	)

	if result.success then
		return true
	else
		warnlog("Failed to save gift: %s", result.error or "unknown")
		return false
	end
end

local function formatGiftRecord(giftRecord: GiftRecord): FormattedGift
	local giftSenderName = UsernameCache.getUsername(giftRecord.from)
	return {
		Id = giftRecord.id,
		Gifter = giftSenderName,
		Amount = giftRecord.amount,
		Timestamp = giftRecord.timestamp,
	}
end

function GiftPersistence.retrievePlayerGiftHistory(requestingPlayer: Player): { FormattedGift }
	if not ValidationUtils.isValidPlayer(requestingPlayer) then
		warnlog("Invalid player for gift retrieval")
		return {}
	end

	local playerDataKey = tostring(requestingPlayer.UserId)

	local result = DataStoreWrapper.getAsync(giftStorageDataStore, playerDataKey, { maxRetries = MAX_DATASTORE_RETRIES })

	if not result.success then
		warnlog("Failed to retrieve gifts for player %d: %s", requestingPlayer.UserId, result.error or "unknown")
		return {}
	end

	local formattedGiftList = {}
	if type(result.data) == "table" then
		for _, giftRecord in result.data do
			if not isValidGiftRecord(giftRecord) then
				warnlog("Invalid gift record found for player %d", requestingPlayer.UserId)
				continue
			end
			table.insert(formattedGiftList, formatGiftRecord(giftRecord))
		end
	end

	return formattedGiftList
end

function GiftPersistence.removeAllPlayerGifts(targetPlayer: Player): boolean
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		warnlog("Invalid player for gift clearance")
		return false
	end

	local playerDataKey = tostring(targetPlayer.UserId)

	local result = DataStoreWrapper.removeAsync(giftStorageDataStore, playerDataKey, { maxRetries = MAX_DATASTORE_RETRIES })

	if result.success then
		log("Cleared gifts for player %s (%d)", targetPlayer.Name, targetPlayer.UserId)
		return true
	else
		warnlog("Failed to clear gifts for player %d: %s", targetPlayer.UserId, result.error or "unknown")
		return false
	end
end

return GiftPersistence