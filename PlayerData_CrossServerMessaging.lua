--!strict

--------------
-- Services --
--------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")

----------------
-- References --
----------------

local network = ReplicatedStorage:WaitForChild("Network") :: Folder
local bindables = network:WaitForChild("Bindables")
local bindableEvents = bindables:WaitForChild("Events")

local modules = ReplicatedStorage:WaitForChild("Modules")
local configuration = ReplicatedStorage:WaitForChild("Configuration")

local validationUtils = require(modules.Utilities.ValidationUtils)
local gameConfig = require(configuration.GameConfig)

-----------
-- Types --
-----------
export type CrossServerMessage = {
	UserId: number,
	Stat: string,
	Value: number,
}

---------------
-- Constants --
---------------
local TAG = "[PlayerData.CrossServerMessaging]"

local CROSS_SERVER_LEADERSTATS_UPDATE_TOPIC: string = gameConfig.MESSAGING_SERVICE_CONFIG.LEADERBOARD_UPDATE
local UI_UPDATE_STATISTIC_NAME: string = "Raised"

---------------
-- Variables --
---------------
local CrossServerMessaging = {}

local isShuttingDown: boolean = false
local messageConnection: RBXScriptConnection? = nil

---------------
-- Logging --
---------------
local function log(message: string, ...: any): ()
	print(string.format(TAG .. " " .. message, ...))
end

local function warnlog(message: string, ...: any): ()
	warn(string.format(TAG .. " " .. message, ...))
end

-------------------
-- Validation --
-------------------
local function isValidCrossServerMessage(message: any): boolean
	return type(message) == "table"
		and validationUtils.isValidUserId(message.UserId)
		and type(message.Stat) == "string"
		and type(message.Value) == "number"
end

--------------------------
-- UI Update Operations --
--------------------------
local function updatePlayerLeaderboardStatistics(
	targetPlayer: Player,
	statisticName: string,
	newStatisticValue: number
): ()
	if not validationUtils.isValidPlayer(targetPlayer) then
		return
	end

	local playerLeaderboardStats: Folder? = targetPlayer:FindFirstChild("leaderstats") :: Folder?
	if not playerLeaderboardStats then
		return
	end

	local leaderboardStatisticObject: IntValue? = playerLeaderboardStats:FindFirstChild(statisticName) :: IntValue?
	if leaderboardStatisticObject and leaderboardStatisticObject:IsA("IntValue") then
		leaderboardStatisticObject.Value = newStatisticValue
	end

	if statisticName == UI_UPDATE_STATISTIC_NAME then
		local userInterfaceUpdateBindableEvent: BindableEvent? = bindableEvents:FindFirstChild("UpdateUI") :: BindableEvent?
		if userInterfaceUpdateBindableEvent and userInterfaceUpdateBindableEvent:IsA("BindableEvent") then
			userInterfaceUpdateBindableEvent:Fire(false, { Viewer = targetPlayer }, true)
		end
	end
end

-------------------------------
-- Cross-Server Communication --
-------------------------------
function CrossServerMessaging.publishUpdate(updateMessage: CrossServerMessage): ()
	if isShuttingDown then
		return
	end

	local publishSuccess, publishErrorMessage = pcall(function()
		MessagingService:PublishAsync(CROSS_SERVER_LEADERSTATS_UPDATE_TOPIC, updateMessage)
	end)

	if not publishSuccess then
		warnlog("Failed to publish to messaging topic '%s': %s", CROSS_SERVER_LEADERSTATS_UPDATE_TOPIC, tostring(publishErrorMessage))
	end
end

local function handleCrossServerLeaderstatUpdate(message: any): ()
	if not isValidCrossServerMessage(message) then
		warnlog("Invalid cross-server leaderstat update message received")
		return
	end

	local targetPlayer: Player? = Players:GetPlayerByUserId(message.UserId)
	if targetPlayer then
		updatePlayerLeaderboardStatistics(targetPlayer, message.Stat, message.Value)
	end
end

function CrossServerMessaging.subscribe(connectionTracker: (connection: RBXScriptConnection) -> RBXScriptConnection): ()
	local subscribeSuccess, subscribeError = pcall(function()
		messageConnection = connectionTracker(
			MessagingService:SubscribeAsync(
				CROSS_SERVER_LEADERSTATS_UPDATE_TOPIC,
				function(envelope)
					local data = envelope and envelope.Data
					handleCrossServerLeaderstatUpdate(data)
				end
			)
		)
	end)

	if not subscribeSuccess then
		warnlog("Failed to subscribe to cross-server updates: %s", tostring(subscribeError))
	end
end

function CrossServerMessaging.updatePlayerStats(
	targetPlayer: Player,
	statisticName: string,
	newStatisticValue: number
): ()
	updatePlayerLeaderboardStatistics(targetPlayer, statisticName, newStatisticValue)
end

-----------------------
-- Lifecycle Control --
-----------------------
function CrossServerMessaging.setShutdown(shutdown: boolean): ()
	isShuttingDown = shutdown
end

function CrossServerMessaging.cleanup(): ()
	isShuttingDown = true
	if messageConnection then
		messageConnection:Disconnect()
		messageConnection = nil
	end
end

return CrossServerMessaging