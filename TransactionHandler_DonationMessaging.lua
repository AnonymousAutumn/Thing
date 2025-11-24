--!strict

--------------
-- Services --
--------------

local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local network = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")

local sendMessageEvent = remoteEvents:WaitForChild("SendMessage")

local Configuration = ReplicatedStorage:WaitForChild("Configuration")
local GameConfig = require(Configuration.GameConfig)

-----------
-- Types --
-----------

export type BroadcastData = {
	Donor: string | number,
	Receiver: string | number,
	Amount: number,
	Filler: string?,
}

type MessagingPacket = {
	Data: BroadcastData,
	Sent: number,
}

---------------
-- Constants --
---------------

local TAG = "[Transaction.DonationMessaging]"

local messagingConfiguration = GameConfig.MESSAGING_SERVICE_CONFIG
local LARGE_DONATION_BROADCAST_TOPIC = messagingConfiguration.LARGE_DONATION_TOPIC

local MAX_MESSAGING_RETRIES = 3
local BASE_RETRY_DELAY = 1
local MESSAGING_TIMEOUT = 5

-----------
-- Module --
-----------
local DonationMessaging = {}

---------------
-- Variables --
---------------
local messagingSubscription = nil

---------------
-- Logging --
---------------
local function log(message: string, ...: any): ()
	print(TAG .. " " .. string.format(message, ...))
end

local function warnlog(message: string, ...: any): ()
	warn(TAG .. " " .. string.format(message, ...))
end

---------------
-- Validation --
---------------
local function isValidBroadcastData(data: any): boolean
	if typeof(data) ~= "table" then
		return false
	end
	return data.Donor ~= nil and data.Receiver ~= nil and data.Amount ~= nil
end

---------------
-- Helpers --
---------------
local function hasTimedOut(startTime: number, timeout: number): boolean
	return os.clock() - startTime > timeout
end

local function calculateRetryDelay(attemptNumber: number): number
	return BASE_RETRY_DELAY * attemptNumber
end

local function disconnectMessagingSubscription(): ()
	if messagingSubscription then
		pcall(function()
			messagingSubscription:Disconnect()
		end)
		messagingSubscription = nil
	end
end

-------------------------------
-- MessagingService Operations --
-------------------------------
local function publishToMessagingService(topic: string, messageData: BroadcastData): boolean
	for attempt = 1, MAX_MESSAGING_RETRIES do
		local startTime = os.clock()
		local success, result = pcall(function()
			MessagingService:PublishAsync(topic, messageData)
			if hasTimedOut(startTime, MESSAGING_TIMEOUT) then
				error("MessagingService timeout")
			end
		end)

		if success then
			return true
		end

		warnlog(
			"MessagingService publish attempt %d/%d failed: %s",
			attempt,
			MAX_MESSAGING_RETRIES,
			tostring(result)
		)

		if attempt < MAX_MESSAGING_RETRIES then
			task.wait(calculateRetryDelay(attempt))
		end
	end

	warnlog("Failed to publish message after %d attempts", MAX_MESSAGING_RETRIES)
	return false
end

function DonationMessaging.broadcastToMessagingService(broadcastTopic: string, messageData: BroadcastData): boolean
	if not isValidBroadcastData(messageData) then
		warnlog("Invalid message data for broadcast")
		return false
	end

	return publishToMessagingService(broadcastTopic, messageData)
end

local function processLargeDonationBroadcast(messagingPacket: MessagingPacket): ()
	local broadcastData = messagingPacket.Data
	if not isValidBroadcastData(broadcastData) then
		warnlog("Invalid or incomplete broadcast data received")
		return
	end

	local success = pcall(function()
		sendMessageEvent:FireAllClients(
			broadcastData.Donor,
			broadcastData.Receiver,
			broadcastData.Filler,
			broadcastData.Amount,
			true
		)
	end)

	if not success then
		warnlog("Failed to fire large donation broadcast to clients")
	end
end

function DonationMessaging.subscribeToMessagingService(): ()
	local success, subscription = pcall(function()
		return MessagingService:SubscribeAsync(LARGE_DONATION_BROADCAST_TOPIC, processLargeDonationBroadcast)
	end)

	if success then
		messagingSubscription = subscription
		log("Subscribed to MessagingService topic: %s", LARGE_DONATION_BROADCAST_TOPIC)
	else
		warnlog("Failed to subscribe to MessagingService: %s", tostring(subscription))
	end
end

function DonationMessaging.cleanup(): ()
	disconnectMessagingSubscription()
end

return DonationMessaging