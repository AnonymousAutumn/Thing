--!strict

-- Services
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- References
local network = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")

local unclaimStandEvent = remoteEvents:WaitForChild("UnclaimStand")
local sendNotificationEvent = remoteEvents:WaitForChild("CreateNotification")
local refreshStandEvent = remoteEvents:WaitForChild("RefreshStand")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local Claimer = require(script.Claimer)
local GamepassCacheManager = require(Modules.Caches.PassCache)
local StandManager = require(Modules.Managers.Stands)
local GameConfig = require(Configuration.GameConfig)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local EnhancedValidation = require(Modules.Utilities.EnhancedValidation)
local RateLimiter = require(Modules.Utilities.RateLimiter)

-- Stand tracking
local StandObjects = {}        -- [Model] = StandModule
local PlayerToStand = {}       -- [player.Name] = StandModule
local ClaimedStands = {}       -- [standModel] = {Owner = Player, gamepasses = {}}

-- Connection management
local resourceManager = ResourceCleanup.new()
local isShuttingDown = false

-- Allow StandUtils access
StandManager.SetPlayerToStandTable(PlayerToStand)

local StandMaster = {}

-- Functions

--[[
	Attempts to claim a stand for a player

	Stand Claiming Flow:
	1. Check if player already has a stand (early return if yes)
	2. Fetch player's gamepass data from cache
	3. Check if player owns the Stand gamepass via MarketplaceService
	4. If owned (or has OwnsStand attribute), claim immediately
	5. If not owned, prompt gamepass purchase
	6. Wait for purchase completion event
	7. If purchase successful, set attribute and claim stand

	@param player Player - The player attempting to claim the stand
	@param standObj StandModule - The stand object being claimed
]]
function StandMaster:TryClaimStand(player, standObj)
	if PlayerToStand[player.Name] then return end

	local playerPassData = GamepassCacheManager.GetPlayerCachedGamepassData(player)
	local gamepasses = playerPassData and playerPassData.gamepasses or {}

	local function claim()
		standObj:Claim(player)
		PlayerToStand[player.Name] = standObj

		-- Update authoritative table
		ClaimedStands[standObj.Stand] = {Owner = player, gamepasses = gamepasses}

		-- Replicate to all clients
		refreshStandEvent:FireAllClients(standObj.Stand, gamepasses, false)
	end

	-- Check gamepass ownership with error handling
	local ownsPass = false
	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GameConfig.MONETIZATION.STAND_ACCESS)
	end)

	if success then
		ownsPass = result
	else
		warn("[StandManager] Failed to check gamepass ownership for player " .. player.Name .. ": " .. tostring(result))
	end

	if ownsPass or player:GetAttribute(tostring(GameConfig.GAMEPASS_CONFIG.BUYABLE_PASSES.STAND)) then
		claim()
		return
	end

	-- Prompt purchase with error handling
	local promptSuccess, promptError = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, GameConfig.MONETIZATION.STAND_ACCESS)
	end)

	if not promptSuccess then
		warn("[StandManager] Failed to prompt gamepass purchase for player " .. player.Name .. ": " .. tostring(promptError))
		sendNotificationEvent:FireClient(player, "Failed to open purchase prompt. Please try again.", "Error")
		return
	end

	local purchaseSuccess = false
	local purchaseConnection
	local purchaseCompleteEvent = Instance.new("BindableEvent")

	purchaseConnection = MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasingPlayer, purchasedPassId, wasPurchaseSuccessful)
		if purchasingPlayer == player and purchasedPassId == GameConfig.MONETIZATION.STAND_ACCESS then
			purchaseSuccess = wasPurchaseSuccessful
			purchaseCompleteEvent:Fire()
			purchaseConnection:Disconnect()
		end
	end)

	-- Yield until purchase completes
	purchaseCompleteEvent.Event:Wait()
	purchaseCompleteEvent:Destroy()

	if purchaseSuccess then
		-- Roblox UserOwnsGamePassAsync caches results, so we use an attribute as workaround
		player:SetAttribute(tostring(GameConfig.GAMEPASS_CONFIG.BUYABLE_PASSES.STAND), true)

		-- Claim now
		claim()
	end
end

--[[
	Unclaims a player's stand and notifies all clients

	Removes the player's stand from tracking tables, resets the stand state,
	and broadcasts the unclaim to all clients for UI updates.

	@param player Player - The player unclaiming their stand
]]
local function unclaimStand(player: Player): ()
	local standObj = PlayerToStand[player.Name]
	if standObj then
		standObj:Reset()
		PlayerToStand[player.Name] = nil
		ClaimedStands[standObj.Stand] = nil

		refreshStandEvent:FireAllClients(standObj.Stand, nil, true)
	end

	sendNotificationEvent:FireClient(player, "You've unclaimed your stand.", "Error")
end

-- Initialize all stands in Workspace
for _, stand in ipairs(Workspace.Stands:GetChildren()) do
	if stand:IsA("Model") and stand:FindFirstChild("PromptHolder") then
		local standObj = Claimer.new(stand, StandMaster, refreshStandEvent, ClaimedStands)
		StandObjects[stand] = standObj
	end
end

--[[
	Replicates all stand states to a newly joined player

	When a player joins after stands have been claimed, this function sends
	the current state of all stands (claimed or unclaimed) to ensure the
	client has accurate UI information.

	@param player Player - The newly joined player to replicate stands to
]]
local function replicateAllStandsToPlayer(player: Player): ()
	if isShuttingDown then return end

	for standModel, standObj in pairs(StandObjects) do
		local claimedData = ClaimedStands[standModel]
		local gamepasses = claimedData and claimedData.gamepasses or {}
		local remove = false -- never remove; we're sending current state

		-- Always tell client about the stand, even if unclaimed
		refreshStandEvent:FireClient(player, standModel, gamepasses, remove)
	end
end

--------------------
-- Initialization --
--------------------

-- SECURITY: RemoteEvent for stand unclaiming
resourceManager:trackConnection(unclaimStandEvent.OnServerEvent:Connect(function(player: Player)
	-- Step 1-3: Validate player
	if not EnhancedValidation.validatePlayer(player) then
		warn("[StandMaster] Invalid player in unclaim stand event")
		return
	end

	-- Step 4: Rate limiting (prevent spam unclaiming)
	if not RateLimiter.checkRateLimit(player, "UnclaimStand", 3) then
		return -- Silent fail on rate limit
	end

	-- Step 5: Server authoritative - only unclaim OWN stand (checked in unclaimStand)
	-- Step 6-9: Handled in unclaimStand function
	unclaimStand(player)
end))

resourceManager:trackConnection(Players.PlayerRemoving:Connect(unclaimStand))

resourceManager:trackConnection(Players.PlayerAdded:Connect(function(player)
	replicateAllStandsToPlayer(player)
end))

-------------
-- Cleanup --
-------------
game:BindToClose(function()
	isShuttingDown = true
	resourceManager:cleanupAll()

	-- Unclaim all stands
	for playerName, standObj in pairs(PlayerToStand) do
		standObj:Reset()
	end
	table.clear(PlayerToStand)
	table.clear(ClaimedStands)
	table.clear(StandObjects)
end)