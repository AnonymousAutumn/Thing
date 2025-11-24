--!strict

--[[
	Notification UI System

	Main notification display controller that manages the lifecycle of notification
	UI elements. Handles notification creation, animation, queueing, sound playback,
	and automatic removal. Listens to both remote and local notification events.

	Returns: nil (auto-initializes on require)

	Usage:
		Require this module in a LocalScript parented to the notification ScreenGui.
		Send notifications via the CreateNotification RemoteEvent or BindableEvent.
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network in ReplicatedStorage")
local bindables = assert(network:WaitForChild("Bindables", 10), "Failed to find Bindables in Network")
local bindableEvents = assert(bindables:WaitForChild("Events", 10), "Failed to find Events in Bindables")
local remotes = assert(network:WaitForChild("Remotes", 10), "Failed to find Remotes in Network")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Failed to find Events in Remotes")

local globalNotificationEvent = assert(remoteEvents:WaitForChild("CreateNotification", 10), "Failed to find CreateNotification RemoteEvent")
local localNotificationEvent = assert(bindableEvents:WaitForChild("CreateNotification", 10), "Failed to find CreateNotification BindableEvent")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules in ReplicatedStorage")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

-- Submodules
local NotificationAnimator = require(script.NotificationAnimator)
local NotificationQueue = require(script.NotificationQueue)
local SoundManager = require(script.SoundManager)

local instances: Folder = assert(ReplicatedStorage:WaitForChild("Instances", 10), "Failed to find Instances in ReplicatedStorage") :: Folder
local guiPrefabs = assert(instances:WaitForChild("GuiPrefabs", 10), "Failed to find GuiPrefabs in Instances") :: Folder
local notificationTemplate: Frame = assert(guiPrefabs:WaitForChild("NotificationPrefab", 10), "Failed to find NotificationPrefab in GuiPrefabs") :: Frame

local notificationSystemScript: ScreenGui = script.Parent :: ScreenGui
local mainFrame: Frame = assert(notificationSystemScript:WaitForChild("MainFrame", 10), "Failed to find MainFrame in NotificationUI") :: Frame
local notificationContainer: Frame = assert(mainFrame:WaitForChild("Holder", 10), "Failed to find Holder in MainFrame") :: Frame

---------------
-- Constants --
---------------
local NOTIFICATION_COLORS = {
	Success = Color3.fromRGB(0, 255, 0),
	Warning = Color3.fromRGB(255, 255, 0),
	Error = Color3.fromRGB(255, 75, 75),
}

local COMPONENT_TEXT_LABEL = "TextLabel"
local COMPONENT_UI_STROKE = "UIStroke"

local LOG_PREFIX = "[NotificationUI]"

---------------
-- Variables --
---------------
local notificationQueue = NotificationQueue.new()
local resourceManager = ResourceCleanup.new()

---------------
-- Utilities --
---------------
local function isValidNotificationType(notificationType: string): boolean
	return NOTIFICATION_COLORS[notificationType] ~= nil
end

local function safeExecute(func: () -> (), errorMessage: string): boolean
	local success, errorDetails = pcall(func)
	if not success then
		warn(string.format("%s %s: %s", LOG_PREFIX, errorMessage, tostring(errorDetails)))
		return false
	end
	return true
end

--[[
	Gets UIStroke component from frame

	@param frame Frame - Frame to search
	@return UIStroke? - Stroke or nil
]]
local function getUIStroke(frame: Frame): UIStroke?
	local uiStroke = frame:FindFirstChild(COMPONENT_UI_STROKE)
	return if ValidationUtils.isValidUIStroke(uiStroke) then uiStroke :: UIStroke else nil
end

--[[
	Gets TextLabel from frame

	@param frame Frame - Frame to search
	@return TextLabel? - TextLabel or nil
]]
local function getTextLabel(frame: Frame): TextLabel?
	return frame:FindFirstChild(COMPONENT_TEXT_LABEL) :: TextLabel?
end

--------------------------
-- Position Management --
--------------------------
local function isFrameInContainer(frame: Frame): boolean
	return frame and frame:IsDescendantOf(notificationContainer)
end

local function repositionSingleNotification(frame: Frame, index: number): ()
	if not isFrameInContainer(frame) then
		return
	end

	local newPosition = NotificationAnimator.calculatePosition(index, notificationQueue:getCount())

	safeExecute(function()
		NotificationAnimator.animateReposition(frame, newPosition)
	end, "Error repositioning notification")
end

local function repositionNotifications(): ()
	for index, frame in notificationQueue:getAll() do
		repositionSingleNotification(frame, index)
	end
end

-------------------------------
-- Notification Management --
-------------------------------
local function destroyNotificationFrame(frame: Frame): ()
	safeExecute(function()
		if frame.Parent then
			frame:Destroy()
		end
	end, "Error destroying notification frame")
end

local function handleNotificationRemoval(frame: Frame, textLabel: TextLabel): ()
	NotificationAnimator.animateExit(frame, textLabel)

	task.delay(NotificationAnimator.getStandardDuration(), function()
		destroyNotificationFrame(frame)
		notificationQueue:remove(frame)
		repositionNotifications()
	end)
end

--------------------------
-- Notification Creation --
--------------------------
local function validateNotificationParams(message: string, notificationType: string): boolean
	if not ValidationUtils.isValidString(message) then
		warn(LOG_PREFIX, "Invalid message for notification")
		return false
	end

	if not ValidationUtils.isValidString(notificationType) then
		warn(LOG_PREFIX, "Invalid notification type")
		return false
	end

	if not isValidNotificationType(notificationType) then
		warn(LOG_PREFIX, "Unknown notification type:", notificationType)
		return false
	end

	return true
end

local function cloneNotificationTemplate(): Frame?
	local success, clonedFrame = pcall(function()
		return notificationTemplate:Clone()
	end)

	if not success then
		warn(LOG_PREFIX, "Failed to clone notification template:", clonedFrame)
		return nil
	end

	return clonedFrame :: Frame
end

local function createNotification(message: string, notificationType: string): ()
	if not validateNotificationParams(message, notificationType) then
		return
	end

	local notificationFrame = cloneNotificationTemplate()
	if not notificationFrame then
		return
	end

	local textLabel = getTextLabel(notificationFrame)
	if not textLabel then
		warn(LOG_PREFIX, "TextLabel not found in notification template")
		return
	end

	-- Setup frame
	notificationFrame.Parent = notificationContainer
	textLabel.Text = string.upper(message)
	textLabel.TextColor3 = NOTIFICATION_COLORS[notificationType]

	notificationQueue:add(notificationFrame)

	-- Reposition all notifications
	repositionNotifications()

	-- Play sound
	SoundManager.playForType(notificationType)

	-- Animate entry
	local uiStroke = getUIStroke(notificationFrame)
	NotificationAnimator.animateEntry({
		frame = notificationFrame,
		textLabel = textLabel,
		uiStroke = uiStroke,
		notificationType = notificationType,
		typeColor = NOTIFICATION_COLORS[notificationType],
	})

	-- Schedule automatic removal
	notificationQueue:scheduleRemoval(notificationFrame, textLabel, handleNotificationRemoval)
end

--------------------------
-- Cleanup --
--------------------------
local function destroyAllNotifications(): ()
	for _, frame in notificationQueue:getAll() do
		destroyNotificationFrame(frame)
	end
	notificationQueue:clear()
end

local function cleanup(): ()
	destroyAllNotifications()
	resourceManager:cleanupAll()
end

--------------------
-- Initialization --
--------------------
if globalNotificationEvent then
	resourceManager:trackConnection(globalNotificationEvent.OnClientEvent:Connect(createNotification))
end

if localNotificationEvent then
	resourceManager:trackConnection(localNotificationEvent.Event:Connect(createNotification))
end

resourceManager:trackConnection(script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(game) then
		cleanup()
	end
end))