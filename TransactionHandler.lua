--!strict

--------------
-- Services --
--------------
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

----------------
-- References --
----------------

local network: Folder = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")
local remoteFunctions = remotes:WaitForChild("Functions")

local giftRequestFunction = remoteFunctions:WaitForChild("RequestGifts")
local giftClearanceEvent = remoteEvents:WaitForChild("ClearGifts")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UsernameCache = require(Modules.Caches.UsernameCache)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local EnhancedValidation = require(Modules.Utilities.EnhancedValidation)
local RateLimiter = require(Modules.Utilities.RateLimiter)

local GiftPersistence = require(script:WaitForChild("GiftPersistence"))
local DonationMessaging = require(script:WaitForChild("DonationMessaging"))
local DonationStatistics = require(script:WaitForChild("DonationStatistics"))
local PurchaseFlow = require(script:WaitForChild("PurchaseFlow"))

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