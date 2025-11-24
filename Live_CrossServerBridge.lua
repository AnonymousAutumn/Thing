--!strict

local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage:WaitForChild("Modules")
local configuration = ReplicatedStorage:WaitForChild("Configuration")

local ValidationUtils = require(modules.Utilities.ValidationUtils)
local GameConfig = require(configuration.GameConfig)

---------------
-- Constants --
---------------
local TAG = "[CrossServerBridge]"
local CROSS_SERVER_DONATION_MESSAGING_TOPIC = GameConfig.MESSAGING_SERVICE_CONFIG.LIVE_DONATION_TOPIC

-----------
-- Types --
-----------
export type DonationNotificationData = {
	Amount: number,
	Donor: number,
	Receiver: number,
}

export type MessagingServicePacket = {
	Data: any,
}

export type ProcessDonationCallback = (DonationNotificationData) -> ()

-----------
-- Module --
-----------
local CrossServerBridge = {}
CrossServerBridge.__index = CrossServerBridge

--[[
	Creates a new cross-server bridge instance

	@return CrossServerBridge
]]
function CrossServerBridge.new()
	local self = setmetatable({}, CrossServerBridge) :: any

	self.messagingSubscription = nil :: any
	self.isShuttingDown = false

	return self
end

--[[
	Validates donation data structure and values

	@param donationData any - Data to validate
	@return boolean - True if valid
]]
function CrossServerBridge.validateDonationData(donationData: any): boolean
	if type(donationData) ~= "table" then
		warn(TAG .. " Donation data is not a table")
		return false
	end
	if not (ValidationUtils.isValidNumber(donationData.Amount) and donationData.Amount > 0) then
		warn(string.format("%s Invalid donation amount: %s", TAG, tostring(donationData.Amount)))
		return false
	end
	if not ValidationUtils.isValidUserId(donationData.Donor) then
		warn(string.format("%s Invalid donor user ID: %s", TAG, tostring(donationData.Donor)))
		return false
	end
	if not ValidationUtils.isValidUserId(donationData.Receiver) then
		warn(string.format("%s Invalid receiver user ID: %s", TAG, tostring(donationData.Receiver)))
		return false
	end
	return true
end

--[[
	Handles incoming cross-server donation message

	@param messagingServicePacket MessagingServicePacket - Incoming packet
	@param processDonation ProcessDonationCallback - Callback to process donation
]]
function CrossServerBridge:handleMessage(
	messagingServicePacket: MessagingServicePacket,
	processDonation: ProcessDonationCallback
): ()
	if self.isShuttingDown then
		return
	end

	local success, errorMessage = pcall(processDonation, messagingServicePacket.Data)
	if not success then
		warn(string.format("%s Error processing cross-server donation message: %s", TAG, tostring(errorMessage)))
	end
end

--[[
	Establishes cross-server messaging connection

	@param processDonation ProcessDonationCallback - Callback to process donations
	@return boolean - True if subscription successful
]]
function CrossServerBridge:subscribe(processDonation: ProcessDonationCallback): boolean
	if self.messagingSubscription then
		warn(TAG .. " Already subscribed to messaging service")
		return false
	end

	local success, subscription = pcall(function()
		return MessagingService:SubscribeAsync(CROSS_SERVER_DONATION_MESSAGING_TOPIC, function(packet)
			self:handleMessage(packet, processDonation)
		end)
	end)

	if success then
		self.messagingSubscription = subscription
		print(string.format("%s Successfully subscribed to donation topic: %s", TAG, CROSS_SERVER_DONATION_MESSAGING_TOPIC))
		return true
	else
		warn(string.format("%s Failed to establish cross-server messaging connection: %s", TAG, tostring(subscription)))
		return false
	end
end

--[[
	Disconnects from cross-server messaging

	Safe to call multiple times
]]
function CrossServerBridge:disconnect(): ()
	if self.messagingSubscription then
		pcall(function()
			self.messagingSubscription:Disconnect()
		end)
		self.messagingSubscription = nil
		print(TAG .. " Disconnected from messaging service")
	end
end

--[[
	Marks bridge as shutting down
]]
function CrossServerBridge:shutdown(): ()
	self.isShuttingDown = true
	self:disconnect()
end

--[[
	Gets the messaging topic name

	@return string - Topic name
]]
function CrossServerBridge.getTopic(): string
	return CROSS_SERVER_DONATION_MESSAGING_TOPIC
end

return CrossServerBridge