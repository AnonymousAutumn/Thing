--!strict

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

----------------
-- References --
----------------
local localPlayer = Players.LocalPlayer
local localPlayerGui = localPlayer:WaitForChild("PlayerGui")

local network: Folder = ReplicatedStorage:WaitForChild("Network") :: Folder
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")
local remoteFunctions = remotes:WaitForChild("Functions")

local toggleGiftUIEvent = remoteEvents:WaitForChild("ToggleGiftUI")
local clearGiftDataEvent = remoteEvents:WaitForChild("ClearGifts")
local requestGiftDataFunction = remoteFunctions:WaitForChild("RequestGifts")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

-- Submodules (existing)
local TimeFormatter = require(script:WaitForChild("TimeFormatter"))
local UIRenderer = require(script:WaitForChild("UIRenderer"))
local ValidationHandler = require(script:WaitForChild("ValidationHandler"))

-- Submodules (new)
local ServerComms = require(script.ServerComms)
local StateManager = require(script.StateManager)
local ErrorDisplay = require(script.ErrorDisplay)
local BackgroundTasks = require(script.BackgroundTasks)

local instances: Folder = ReplicatedStorage:WaitForChild("Instances")
local guiPrefabs: Folder = instances:WaitForChild("GuiPrefabs") :: Folder
local giftReceivedPrefab: CanvasGroup = guiPrefabs:WaitForChild("GiftReceivedPrefab") :: CanvasGroup

local topbarUserInterface = localPlayerGui:WaitForChild("TopbarUI")
local topbarMainFrame = topbarUserInterface:WaitForChild("MainFrame")
local topbarContentHolder = topbarMainFrame:WaitForChild("Holder")
local giftNotificationButton = topbarContentHolder:WaitForChild("GiftButton") :: GuiButton
local giftCountNotificationLabel = giftNotificationButton:WaitForChild("CountLabel") :: TextLabel

local giftInterfaceScript = script.Parent
local giftDisplayFrame = giftInterfaceScript:WaitForChild("GiftFrame") :: Frame
local giftEntriesScrollingFrame = giftDisplayFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local giftInterfaceCloseButton = giftDisplayFrame:WaitForChild("CloseButton") :: GuiButton

local sendGiftInterfaceFrame = giftInterfaceScript:WaitForChild("SendGiftFrame") :: Frame
local usernameInputFrame = sendGiftInterfaceFrame:WaitForChild("InputFrame") :: Frame
local errorMessageDisplayFrame = usernameInputFrame:WaitForChild("InvalidFrame") :: Frame
local errorMessageLabel = errorMessageDisplayFrame:WaitForChild("TextLabel") :: TextLabel
local usernameInputTextBox = usernameInputFrame:WaitForChild("TextBox") :: TextBox
local giftSendConfirmationButton = sendGiftInterfaceFrame:WaitForChild("ConfirmButton") :: GuiButton

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