--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network: Folder = ReplicatedStorage:WaitForChild("Network")
local bindables = network:WaitForChild("Bindables")
local bindableEvents = bindables:WaitForChild("Events")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")

local globalNotificationEvent = remoteEvents:WaitForChild("CreateNotification")
local localNotificationEvent = bindableEvents:WaitForChild("CreateNotification")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

-- Submodules
local NotificationAnimator = require(script.NotificationAnimator)
local NotificationQueue = require(script.NotificationQueue)
local SoundManager = require(script.SoundManager)

local instances: Folder = ReplicatedStorage:WaitForChild("Instances") :: Folder
local guiPrefabs = instances:WaitForChild("GuiPrefabs") :: Folder
local notificationTemplate: Frame = guiPrefabs:WaitForChild("NotificationPrefab") :: Frame

local notificationSystemScript: ScreenGui = script.Parent :: ScreenGui
local mainFrame: Frame = notificationSystemScript:WaitForChild("MainFrame") :: Frame
local notificationContainer: Frame = mainFrame:WaitForChild("Holder") :: Frame

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