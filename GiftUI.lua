--!strict

--[[
	GiftUI - Main gift system UI controller

	This module manages the client-side gift system, handling:
	- Gift notifications and badge display
	- Sending gifts to other players with username validation
	- Displaying received gifts with timestamps
	- Background tasks for data refresh and time updates

	Returns: Nothing (initializes and runs automatically)

	Usage: This script runs automatically when parented to the player's UI.
	The UI initializes on startup and manages all gift-related interactions.
]]

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-----------
-- Types --
-----------
type GiftData = ValidationHandler.GiftData
type TimeDisplayEntry = TimeFormatter.TimeDisplayEntry

type GiftUIState = {
	activeGiftTimeDisplayEntries: { TimeDisplayEntry },
	cachedGiftDataFromServer: { GiftData },
	currentUnreadGiftCount: number,
	resourceManager: any, -- ResourceCleanup.ResourceManager
	isInitialized: boolean,
}

---------------
-- Constants --
---------------
local TAG = "[GiftUI]"
local WAIT_TIMEOUT = 10

----------------
-- References --
----------------
local localPlayer = Players.LocalPlayer
assert(localPlayer, TAG .. " LocalPlayer not found")

local localPlayerGui = assert(localPlayer:WaitForChild("PlayerGui", WAIT_TIMEOUT), TAG .. " PlayerGui not found")

local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", WAIT_TIMEOUT), TAG .. " Network folder not found") :: Folder
local remotes = assert(network:WaitForChild("Remotes", WAIT_TIMEOUT), TAG .. " Remotes folder not found")
local remoteEvents = assert(remotes:WaitForChild("Events", WAIT_TIMEOUT), TAG .. " Events folder not found")
local remoteFunctions = assert(remotes:WaitForChild("Functions", WAIT_TIMEOUT), TAG .. " Functions folder not found")

local toggleGiftUIEvent = assert(remoteEvents:WaitForChild("ToggleGiftUI", WAIT_TIMEOUT), TAG .. " ToggleGiftUI event not found")
local clearGiftDataEvent = assert(remoteEvents:WaitForChild("ClearGifts", WAIT_TIMEOUT), TAG .. " ClearGifts event not found")
local requestGiftDataFunction = assert(remoteFunctions:WaitForChild("RequestGifts", WAIT_TIMEOUT), TAG .. " RequestGifts function not found")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), TAG .. " Modules folder not found")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

-- Submodules (existing)
local TimeFormatter = require(assert(script:WaitForChild("TimeFormatter", WAIT_TIMEOUT), TAG .. " TimeFormatter not found"))
local UIRenderer = require(assert(script:WaitForChild("UIRenderer", WAIT_TIMEOUT), TAG .. " UIRenderer not found"))
local ValidationHandler = require(assert(script:WaitForChild("ValidationHandler", WAIT_TIMEOUT), TAG .. " ValidationHandler not found"))

-- Submodules (new)
local ServerComms = require(assert(script:WaitForChild("ServerComms", WAIT_TIMEOUT), TAG .. " ServerComms not found"))
local StateManager = require(assert(script:WaitForChild("StateManager", WAIT_TIMEOUT), TAG .. " StateManager not found"))
local ErrorDisplay = require(assert(script:WaitForChild("ErrorDisplay", WAIT_TIMEOUT), TAG .. " ErrorDisplay not found"))
local BackgroundTasks = require(assert(script:WaitForChild("BackgroundTasks", WAIT_TIMEOUT), TAG .. " BackgroundTasks not found"))

local instances: Folder = assert(ReplicatedStorage:WaitForChild("Instances", WAIT_TIMEOUT), TAG .. " Instances folder not found")
local guiPrefabs: Folder = assert(instances:WaitForChild("GuiPrefabs", WAIT_TIMEOUT), TAG .. " GuiPrefabs folder not found") :: Folder
local giftReceivedPrefab: CanvasGroup = assert(guiPrefabs:WaitForChild("GiftReceivedPrefab", WAIT_TIMEOUT), TAG .. " GiftReceivedPrefab not found") :: CanvasGroup

local topbarUserInterface = assert(localPlayerGui:WaitForChild("TopbarUI", WAIT_TIMEOUT), TAG .. " TopbarUI not found")
local topbarMainFrame = assert(topbarUserInterface:WaitForChild("MainFrame", WAIT_TIMEOUT), TAG .. " TopbarUI MainFrame not found")
local topbarContentHolder = assert(topbarMainFrame:WaitForChild("Holder", WAIT_TIMEOUT), TAG .. " TopbarUI Holder not found")
local giftNotificationButton = assert(topbarContentHolder:WaitForChild("GiftButton", WAIT_TIMEOUT), TAG .. " GiftButton not found") :: GuiButton
local giftCountNotificationLabel = assert(giftNotificationButton:WaitForChild("CountLabel", WAIT_TIMEOUT), TAG .. " CountLabel not found") :: TextLabel

local giftInterfaceScript = script.Parent
local giftDisplayFrame = assert(giftInterfaceScript:WaitForChild("GiftFrame", WAIT_TIMEOUT), TAG .. " GiftFrame not found") :: Frame
local giftEntriesScrollingFrame = assert(giftDisplayFrame:WaitForChild("ScrollingFrame", WAIT_TIMEOUT), TAG .. " GiftFrame ScrollingFrame not found") :: ScrollingFrame
local giftInterfaceCloseButton = assert(giftDisplayFrame:WaitForChild("CloseButton", WAIT_TIMEOUT), TAG .. " CloseButton not found") :: GuiButton

local sendGiftInterfaceFrame = assert(giftInterfaceScript:WaitForChild("SendGiftFrame", WAIT_TIMEOUT), TAG .. " SendGiftFrame not found") :: Frame
local usernameInputFrame = assert(sendGiftInterfaceFrame:WaitForChild("InputFrame", WAIT_TIMEOUT), TAG .. " InputFrame not found") :: Frame
local errorMessageDisplayFrame = assert(usernameInputFrame:WaitForChild("InvalidFrame", WAIT_TIMEOUT), TAG .. " InvalidFrame not found") :: Frame
local errorMessageLabel = assert(errorMessageDisplayFrame:WaitForChild("TextLabel", WAIT_TIMEOUT), TAG .. " InvalidFrame TextLabel not found") :: TextLabel
local usernameInputTextBox = assert(usernameInputFrame:WaitForChild("TextBox", WAIT_TIMEOUT), TAG .. " TextBox not found") :: TextBox
local giftSendConfirmationButton = assert(sendGiftInterfaceFrame:WaitForChild("ConfirmButton", WAIT_TIMEOUT), TAG .. " ConfirmButton not found") :: GuiButton

---------------
-- Variables --
---------------
local GiftUIState: GiftUIState = {
	activeGiftTimeDisplayEntries = {},
	cachedGiftDataFromServer = {},
	currentUnreadGiftCount = 0,
	resourceManager = ResourceCleanup.new(),
	isInitialized = false,
}

---------------
-- Utilities --
---------------
local function warnlog(fmt: string, ...): ()
	warn(TAG .. " " .. string.format(fmt, ...))
end

local function safeExecute(func: () -> ()): boolean
	local success, errorMessage = pcall(func)
	if not success then
		warnlog("Error: %s", errorMessage)
	end
	return success
end

-- Wire up submodule dependencies
ServerComms.safeExecute = safeExecute
StateManager.safeExecute = safeExecute
ErrorDisplay.safeExecute = safeExecute

---------------
-- Wrappers --
---------------
local function updateGiftNotificationBadgeDisplay(unreadGiftCount: number): ()
	StateManager.updateGiftNotificationBadgeDisplay(
		{ giftCountNotificationLabel = giftCountNotificationLabel },
		unreadGiftCount
	)
end

local errorDisplayElements = {
	errorMessageDisplayFrame = errorMessageDisplayFrame,
	errorMessageLabel = errorMessageLabel,
	usernameInputTextBox = usernameInputTextBox,
	giftSendConfirmationButton = giftSendConfirmationButton,
}

local function displayTemporaryErrorMessage(errorMessageText: string): ()
	ErrorDisplay.displayTemporaryErrorMessage(errorDisplayElements, errorMessageText)
end

---------------
-- Server comms --
---------------
local function requestLatestGiftDataFromServer(): ()
	local retrievedGiftData = ServerComms.requestLatestGiftDataFromServer(requestGiftDataFunction)

	if not retrievedGiftData then
		return
	end

	GiftUIState.cachedGiftDataFromServer = retrievedGiftData

	if giftDisplayFrame.Visible then
		UIRenderer.populateGiftDisplayWithServerData(
			retrievedGiftData,
			{
				giftReceivedPrefab = giftReceivedPrefab,
				giftEntriesScrollingFrame = giftEntriesScrollingFrame,
			},
			GiftUIState.activeGiftTimeDisplayEntries,
			safeExecute
		)
	else
		GiftUIState.currentUnreadGiftCount = #retrievedGiftData
		updateGiftNotificationBadgeDisplay(GiftUIState.currentUnreadGiftCount)
	end
end

---------------
-- UI helpers --
---------------
local function clearAllGiftDisplayElements(): ()
	-- Cache GetChildren() for performance
	local children = giftEntriesScrollingFrame:GetChildren()
	for i, childElement in children do
		if not childElement:IsA("UIListLayout") then
			safeExecute(function()
				childElement:Destroy()
			end)
		end
	end
end

local function clearAllGiftDataAndInterface(): ()
	clearAllGiftDisplayElements()

	giftDisplayFrame.Visible = false
	updateGiftNotificationBadgeDisplay(0)

	StateManager.resetGiftState(GiftUIState)
	ServerComms.notifyServerOfGiftClearance(clearGiftDataEvent)
end

local function showGiftDisplayFrame(): ()
	safeExecute(function()
		giftDisplayFrame.Visible = true
		sendGiftInterfaceFrame.Visible = false
		UIRenderer.populateGiftDisplayWithServerData(
			GiftUIState.cachedGiftDataFromServer,
			{
				giftReceivedPrefab = giftReceivedPrefab,
				giftEntriesScrollingFrame = giftEntriesScrollingFrame,
			},
			GiftUIState.activeGiftTimeDisplayEntries,
			safeExecute
		)
		GiftUIState.currentUnreadGiftCount = 0
		updateGiftNotificationBadgeDisplay(0)
		ServerComms.notifyServerOfGiftClearance(clearGiftDataEvent)
	end)
end

local function toggleGiftDisplayFrameVisibility(): ()
	if GiftUIState.currentUnreadGiftCount <= 0 then
		return
	end

	if giftDisplayFrame.Visible then
		clearAllGiftDataAndInterface()
	else
		showGiftDisplayFrame()
	end
end

---------------
-- Validation + gift initiation --
---------------
local function validateUsernameAndInitiateGiftProcess(): ()
	if errorMessageDisplayFrame.Visible then
		return
	end

	local enteredUsername = usernameInputTextBox.Text
	if not ValidationHandler.validateUsernameInput(enteredUsername, displayTemporaryErrorMessage) then
		return
	end

	task.spawn(function()
		local targetPlayerUserId = ValidationHandler.retrieveUserIdFromUsername(enteredUsername)
		if not ValidationHandler.validateTargetUserId(targetPlayerUserId, displayTemporaryErrorMessage) then
			return
		end

		local verifiedPlayerName = ValidationHandler.retrieveUsernameFromUserId(targetPlayerUserId :: number)
		if not ValidationHandler.validateTargetUsername(verifiedPlayerName, displayTemporaryErrorMessage) then
			return
		end

		if ValidationHandler.isGiftingToSelf(verifiedPlayerName :: string, localPlayer.Name, displayTemporaryErrorMessage) then
			return
		end

		ServerComms.initiateGiftProcess(toggleGiftUIEvent, targetPlayerUserId :: number)
		sendGiftInterfaceFrame.Visible = false
	end)
end

local function handleGiftNotificationButtonClick(): ()
	if giftDisplayFrame.Visible then
		clearAllGiftDataAndInterface()
	elseif sendGiftInterfaceFrame.Visible then
		sendGiftInterfaceFrame.Visible = false
		if GiftUIState.currentUnreadGiftCount > 0 then
			toggleGiftDisplayFrameVisibility()
		end
	else
		if GiftUIState.currentUnreadGiftCount > 0 then
			toggleGiftDisplayFrameVisibility()
		else
			sendGiftInterfaceFrame.Visible = true
		end
	end
end

---------------
-- Lifecycle --
---------------
local function initializeGiftSystemOnStartup(): ()
	if GiftUIState.isInitialized then
		return
	end

	requestLatestGiftDataFromServer()

	if GiftUIState.currentUnreadGiftCount > 0 then
		safeExecute(function()
			giftDisplayFrame.Visible = true
			UIRenderer.populateGiftDisplayWithServerData(
				GiftUIState.cachedGiftDataFromServer,
				{
					giftReceivedPrefab = giftReceivedPrefab,
					giftEntriesScrollingFrame = giftEntriesScrollingFrame,
				},
				GiftUIState.activeGiftTimeDisplayEntries,
				safeExecute
			)
			updateGiftNotificationBadgeDisplay(0)
			GiftUIState.currentUnreadGiftCount = 0
			ServerComms.notifyServerOfGiftClearance(clearGiftDataEvent)
		end)
	end

	GiftUIState.isInitialized = true
end

local function cleanup(): ()
	GiftUIState.resourceManager:cleanupAll()
	StateManager.resetGiftState(GiftUIState)
	GiftUIState.isInitialized = false
end

-----------------------
-- Event Connections --
-----------------------
GiftUIState.resourceManager:trackConnection(
	giftNotificationButton.MouseButton1Click:Connect(handleGiftNotificationButtonClick)
)
GiftUIState.resourceManager:trackConnection(
	giftSendConfirmationButton.MouseButton1Click:Connect(validateUsernameAndInitiateGiftProcess)
)
GiftUIState.resourceManager:trackConnection(
	giftInterfaceCloseButton.MouseButton1Click:Connect(clearAllGiftDataAndInterface)
)

GiftUIState.resourceManager:trackConnection(script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(game) then
		cleanup()
	end
end))
GiftUIState.resourceManager:trackConnection(localPlayer.AncestryChanged:Connect(function()
	if not localPlayer:IsDescendantOf(game) then
		cleanup()
	end
end))

--------------------
-- Background Tasks --
--------------------

-- Wire up BackgroundTasks callbacks
BackgroundTasks.requestLatestGiftDataCallback = requestLatestGiftDataFromServer
BackgroundTasks.updateTimeDisplayCallback = function()
	TimeFormatter.updateAllGiftTimeDisplayLabels(GiftUIState.activeGiftTimeDisplayEntries, safeExecute)
end

-----------------------
-- Startup --
-----------------------
task.spawn(initializeGiftSystemOnStartup)
BackgroundTasks.startContinuousGiftDataRefreshLoop(GiftUIState.resourceManager)
BackgroundTasks.startContinuousTimeDisplayUpdateLoop(GiftUIState.resourceManager, giftDisplayFrame)