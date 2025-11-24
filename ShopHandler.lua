--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ButtonWrapper = require(Modules.Wrappers.Buttons)
local PurchaseWrapper = require(Modules.Wrappers.Purchases)
local NotificationHelper = require(Modules.Utilities.NotificationHelper)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

local Network = ReplicatedStorage:WaitForChild("Network")
local sendNotificationEvent = Network.Bindables.Events.CreateNotification

local uiSounds = SoundService.UI
local feedbackSounds = SoundService.Feedback

local ScrollingFrame = workspace.World.Structures.Store.ProductsHolder.SurfaceGui.MainFrame.ItemScrollingFrame

local resourceManager = ResourceCleanup.new()

local function handleProductPurchaseButtonInteraction(button)
	local assetId = button:GetAttribute("AssetId")

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
	local assetId = button:GetAttribute("AssetId")

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