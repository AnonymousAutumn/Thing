--!strict

--------------
-- Services --
--------------
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-----------
-- Types --
-----------

export type ButtonConfig = {
	button: TextButton,
	onClick: (button: TextButton) -> (),
	sounds: {
		hover: Sound?,
		click: Sound?,
	}?,
	connectionTracker: any?, -- ConnectionManager instance
}

type GamePassProductInfo = {
	Creator: { Id: number },
	[string]: any,
}

----------------
-- References --
----------------

local network = ReplicatedStorage:WaitForChild("Network")
local bindables = network:WaitForChild("Bindables")
local bindableEvents = bindables:WaitForChild("Events")

local sendNotificationEvent = bindableEvents:WaitForChild("CreateNotification")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PurchaseWrapper = require(Modules.Wrappers.Purchases)
local ButtonWrapper = require(Modules.Wrappers.Buttons)
local InputCategorizer = require(Modules.Utilities.InputCategorizer)
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local NotificationHelper = require(Modules.Utilities.NotificationHelper)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

local uiSounds : SoundGroup = SoundService:WaitForChild("UI")
local feedbackSounds : SoundGroup = SoundService:WaitForChild("Feedback")

local gamePassShopMainFrame = script.Parent:WaitForChild("MainFrame")
local gamePassItemsDisplayFrame = gamePassShopMainFrame:WaitForChild("ItemFrame")
local gamePassItemsLayoutManager = gamePassItemsDisplayFrame:WaitForChild("UIListLayout")

local localPlayer = Players.LocalPlayer

---------------
-- Constants --
---------------
local SHOP_ANIMATION_DURATION = 0.2
local SHOP_CLOSED_VERTICAL_OFFSET = -95
local SHOP_OPENED_VERTICAL_OFFSET = -80

local SHOP_ANIMATION_TWEEN_INFO = TweenInfo.new(
	SHOP_ANIMATION_DURATION,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)

local ATTR = {
	AssetId = "AssetId",
	PromptsDisabled = "PromptsDisabled",
}

---------------
-- Variables --
---------------
local resourceManager = ResourceCleanup.new()

---------------
-- Utility Functions --
---------------
local function isValidProductInfo(info)
	return typeof(info) == "table"
		and info.Creator ~= nil
		and typeof(info.Creator) == "table"
		and ValidationUtils.isValidNumber(info.Creator.Id) and info.Creator.Id > 0
end

local function safeExecute(func, _errorMessage)
	-- Silent guard to prevent UI disruption; keep behavior unchanged
	local success = pcall(func)
	return success
end

local function trackConnection(connection)
	return resourceManager:trackConnection(connection)
end

local function trackTween(tween)
	return resourceManager:trackTween(tween)
end

local function updateGamePassItemsScrollingCanvasSize()
	safeExecute(function()
		gamePassItemsDisplayFrame.CanvasSize = UDim2.new(
			0, gamePassItemsLayoutManager.AbsoluteContentSize.X,
			0, gamePassItemsLayoutManager.AbsoluteContentSize.Y
		)
	end, "Error updating canvas size")
end

local function createShopOpeningAnimation()
	local openingAnimation = TweenService:Create(
		gamePassShopMainFrame,
		SHOP_ANIMATION_TWEEN_INFO,
		{ Position = UDim2.new(0.5, 0, 1, SHOP_OPENED_VERTICAL_OFFSET) }
	)
	trackTween(openingAnimation)
	return openingAnimation
end

local function animateGamePassShopInterfaceOpen()
	safeExecute(function()
		gamePassShopMainFrame.Position = UDim2.new(0.5, 0, 1, SHOP_CLOSED_VERTICAL_OFFSET)
		local shopOpeningAnimation = createShopOpeningAnimation()
		shopOpeningAnimation:Play()
		uiSounds.Open:Play()
	end, "Error animating shop open")
end

local function isGamePassButton(element)
	return element:IsA("TextButton")
end

local function clearAllGamePassItemsFromDisplay()
	safeExecute(function()
		-- Cache GetChildren() result to avoid repeated calls in loop
		local children = gamePassItemsDisplayFrame:GetChildren()
		for _, childElement in children do
			if isGamePassButton(childElement) then
				childElement:Destroy()
			end
		end
		gamePassItemsDisplayFrame.CanvasPosition = Vector2.zero
	end, "Error clearing GamePass items")
end

local function handleGamePassPurchaseButtonInteraction(button)
	local assetId = button:GetAttribute("AssetId")

	PurchaseWrapper.attemptPurchase({
		player = localPlayer,
		assetId = assetId,
		isDevProduct = false,
		sounds = {
			click = uiSounds.Click,
			error = feedbackSounds.Error,
		},
		onError = function(errorType, message)
			NotificationHelper.sendWarning(sendNotificationEvent, message)
		end,
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

local function handleShopOpening()
	animateGamePassShopInterfaceOpen()
end

local function handleShopClosing()
	uiSounds:WaitForChild("Close"):Play()
	clearAllGamePassItemsFromDisplay()
end

local function handleGamePassShopVisibilityStateChange()
	if gamePassShopMainFrame.Visible then
		handleShopOpening()
	else
		handleShopClosing()
	end
end

local function setupExistingButtons()
	-- Ensure any pre-existing buttons in the frame are interactive
	local descendants = gamePassItemsDisplayFrame:GetChildren()
	for i = 1, #descendants do
		local inst = descendants[i]
		if inst:IsA("TextButton") then
			setupGamePassButtonInteractionHandlers(inst)
		end
	end
end

local function cleanup()
	resourceManager:cleanupAll()
end

-----------------------
-- Initialization --
-----------------------
-- Initialize UI button handler with device detection
ButtonWrapper.initialize(InputCategorizer)

-- Initialize current UI state
updateGamePassItemsScrollingCanvasSize()
setupExistingButtons()

-- Reactivity wiring
trackConnection(gamePassShopMainFrame:GetPropertyChangedSignal("Visible"):Connect(handleGamePassShopVisibilityStateChange))
trackConnection(gamePassItemsLayoutManager:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGamePassItemsScrollingCanvasSize))
trackConnection(gamePassItemsDisplayFrame.DescendantAdded:Connect(function(instance)
	if instance:IsA("TextButton") then
		setupGamePassButtonInteractionHandlers(instance)
	end
end))

trackConnection(
	script.AncestryChanged:Connect(function()
		if not script:IsDescendantOf(game) then
			cleanup()
		end
	end)
)