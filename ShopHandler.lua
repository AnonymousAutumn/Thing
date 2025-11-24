--!strict

--[[
	ShopHandler Script

	Handles shop UI interactions and purchase button setup.
	Manages product and gamepass purchase flows on the client side.

	Returns: Nothing (client-side script)

	Usage: Runs automatically when placed in game
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules in ReplicatedStorage")
local ButtonWrapper = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("Buttons", 10), "Failed to find Buttons wrapper"))
local PurchaseWrapper = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("Purchases", 10), "Failed to find Purchases wrapper"))
local NotificationHelper = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("NotificationHelper", 10), "Failed to find NotificationHelper"))
local ResourceCleanup = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("ResourceCleanup", 10), "Failed to find ResourceCleanup"))

local Network = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network in ReplicatedStorage")
local sendNotificationEvent = assert(Network:WaitForChild("Bindables", 10):WaitForChild("Events", 10):WaitForChild("CreateNotification", 10), "Failed to find CreateNotification event")

local uiSounds = assert(SoundService:WaitForChild("UI", 10), "Failed to find UI sounds")
local feedbackSounds = assert(SoundService:WaitForChild("Feedback", 10), "Failed to find Feedback sounds")

local ScrollingFrame = assert(workspace:WaitForChild("World", 10):WaitForChild("Structures", 10):WaitForChild("Store", 10):WaitForChild("ProductsHolder", 10):WaitForChild("SurfaceGui", 10):WaitForChild("MainFrame", 10):WaitForChild("ItemScrollingFrame", 10), "Failed to find shop ScrollingFrame")

local resourceManager = ResourceCleanup.new()

local function handleProductPurchaseButtonInteraction(button)
	assert(button, "Button is required")
	local assetId = button:GetAttribute("AssetId")
	assert(assetId, "AssetId attribute is required on button")

	PurchaseWrapper.attemptPurchase({
		player = LocalPlayer,
		assetId = assetId,
		isDevProduct = true,
		sounds = {
			click = uiSounds.Click,
			error = feedbackSounds.Error,
		},
		onError = function(errorType, message)
			NotificationHelper.sendWarning(sendNotificationEvent, message)
		end,
	})
end

local function handleGamePassPurchaseButtonInteraction(button)
	assert(button, "Button is required")
	local assetId = button:GetAttribute("AssetId")
	assert(assetId, "AssetId attribute is required on button")

	PurchaseWrapper.attemptPurchase({
		player = LocalPlayer,
		assetId = assetId,
		sounds = {
			click = uiSounds.Click,
			error = feedbackSounds.Error,
		},
		onError = function(errorType, message)
			NotificationHelper.sendWarning(sendNotificationEvent, message)
		end,
	})
end

local function setupProductButtonInteractionHandlers(gamePassButton)
	ButtonWrapper.setupButton({
		button = gamePassButton,
		onClick = handleProductPurchaseButtonInteraction,
		sounds = {
			hover = uiSounds:WaitForChild("Hover"),
		},
		connectionTracker = resourceManager,
	})
end

local function setupGamePassButtonInteractionHandlers(gamePassButton)
	ButtonWrapper.setupButton({
		button = gamePassButton,
		onClick = handleGamePassPurchaseButtonInteraction,
		sounds = {
			hover = uiSounds:WaitForChild("Hover"),
		},
		connectionTracker = resourceManager,
	})
end

setupGamePassButtonInteractionHandlers(ScrollingFrame.Freecam.ButtonPrefab)
setupGamePassButtonInteractionHandlers(ScrollingFrame.VehicleSpawner.ButtonPrefab)
setupGamePassButtonInteractionHandlers(ScrollingFrame.BoothAccess.ButtonPrefab)

setupProductButtonInteractionHandlers(ScrollingFrame.Product20.ButtonPrefab)
setupProductButtonInteractionHandlers(ScrollingFrame.Product100.ButtonPrefab)
setupProductButtonInteractionHandlers(ScrollingFrame.Product500.ButtonPrefab)
setupProductButtonInteractionHandlers(ScrollingFrame.Product1000.ButtonPrefab)
setupProductButtonInteractionHandlers(ScrollingFrame.Product5000.ButtonPrefab)
setupProductButtonInteractionHandlers(ScrollingFrame.Product10000.ButtonPrefab)