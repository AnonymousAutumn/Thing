--!strict

--[[
	TransactionHandler Module

	Server-side transaction and donation management system.
	Coordinates gift persistence, statistics tracking, and purchase flows.

	Returns: Nothing (server-side initialization script)

	Usage: Runs automatically on server, handles all gamepass purchases and donations
]]

--------------
-- Services --
--------------
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

----------------
-- References --
----------------

local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network")
local remotes = assert(network:WaitForChild("Remotes", 10), "Failed to find Remotes")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Failed to find Events")
local remoteFunctions = assert(remotes:WaitForChild("Functions", 10), "Failed to find Functions")

local giftRequestFunction = assert(remoteFunctions:WaitForChild("RequestGifts", 10), "Failed to find RequestGifts")
local giftClearanceEvent = assert(remoteEvents:WaitForChild("ClearGifts", 10), "Failed to find ClearGifts")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local UsernameCache = require(assert(Modules:WaitForChild("Caches", 10):WaitForChild("UsernameCache", 10), "Failed to find UsernameCache"))
local ResourceCleanup = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("ResourceCleanup", 10), "Failed to find ResourceCleanup"))
local EnhancedValidation = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("EnhancedValidation", 10), "Failed to find EnhancedValidation"))
local RateLimiter = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("RateLimiter", 10), "Failed to find RateLimiter"))

local GiftPersistence = require(assert(script:WaitForChild("GiftPersistence", 10), "Failed to find GiftPersistence"))
local DonationMessaging = require(assert(script:WaitForChild("DonationMessaging", 10), "Failed to find DonationMessaging"))
local DonationStatistics = require(assert(script:WaitForChild("DonationStatistics", 10), "Failed to find DonationStatistics"))
local PurchaseFlow = require(assert(script:WaitForChild("PurchaseFlow", 10), "Failed to find PurchaseFlow"))

---------------
-- Constants --
---------------
local TAG = "[TransactionHandler]"

---------------
-- Variables --
---------------
local resourceManager = ResourceCleanup.new()

---------------
-- Wire Dependencies --
---------------
-- PurchaseFlow depends on GiftPersistence, DonationStatistics, and DonationMessaging
PurchaseFlow.setGiftPersistenceModule(GiftPersistence)
PurchaseFlow.setDonationStatisticsModule(DonationStatistics)
PurchaseFlow.setDonationMessagingModule(DonationMessaging)

-- DonationStatistics depends on DonationMessaging
DonationStatistics.setDonationMessagingModule(DonationMessaging)

---------------
-- Logging --
---------------
local function log(message: string, ...: any): ()
	print(string.format(TAG .. " " .. message, ...))
end

-------------
-- Cleanup --
-------------
local function cleanup(): ()
	resourceManager:cleanupAll()
	DonationMessaging.cleanup()
	UsernameCache.clearCache()
	log("Cleanup complete")
end

--------------------
-- Initialization --
--------------------

-- SECURITY: RemoteFunction for gift history retrieval
giftRequestFunction.OnServerInvoke = function(player: Player)
	-- Step 1-3: Validate player (RemoteFunction guarantees Player but validate anyway)
	if not EnhancedValidation.validatePlayer(player) then
		warn("[TransactionHandler] Invalid player in gift request")
		return {}
	end

	-- Step 4: Rate limiting (prevent spam requests)
	if not RateLimiter.checkRateLimit(player, "RequestGifts", 2) then
		return {} -- Silent fail on rate limit
	end

	-- Step 5-9: Handled in GiftPersistence (server-authoritative data retrieval)
	return GiftPersistence.retrievePlayerGiftHistory(player)
end

-- SECURITY: RemoteEvent for gift clearance
resourceManager:trackConnection(giftClearanceEvent.OnServerEvent:Connect(function(player: Player)
	-- Step 1-3: Validate player
	if not EnhancedValidation.validatePlayer(player) then
		warn("[TransactionHandler] Invalid player in gift clearance")
		return
	end

	-- Step 4: Rate limiting (prevent spam clearance)
	if not RateLimiter.checkRateLimit(player, "ClearGifts", 5) then
		return -- Silent fail on rate limit
	end

	-- Step 5: Server authoritative - only clear OWN gifts (handled in GiftPersistence)
	-- Step 6-9: Handled in GiftPersistence.removeAllPlayerGifts
	GiftPersistence.removeAllPlayerGifts(player)
end))

resourceManager:trackConnection(MarketplaceService.PromptGamePassPurchaseFinished:Connect(PurchaseFlow.handleGamepassPurchaseCompletion))

DonationMessaging.subscribeToMessagingService()

-- Cleanup on server shutdown (runs on all servers, not just Studio)
game:BindToClose(cleanup)