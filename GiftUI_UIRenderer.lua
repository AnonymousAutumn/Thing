--!strict

--[[
	GiftUI_UIRenderer - UI rendering for gift display

	This module handles rendering and updating gift UI elements:
	- Creates gift display frames from server data
	- Updates existing gift displays with new timestamps
	- Removes invalid gift frames
	- Manages time display entries for continuous updates

	Returns: UIRenderer module with UI population functions

	Usage:
		UIRenderer.populateGiftDisplayWithServerData(
			serverGiftDataList,
			uiRefs,
			timeDisplayEntries,
			safeExecute
		)
]]

--------------
-- Services --
--------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------
-- Constants --
---------------

local TAG = "[GiftUI.UIRenderer]"
local WAIT_TIMEOUT = 10

local MESSAGE_FORMAT_GIFT = "%s gifted you %s!"
local GIFT_ID_PREFIX = "Gift_"

----------------
-- References --
----------------

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), TAG .. " Modules folder not found")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", WAIT_TIMEOUT), TAG .. " Configuration folder not found")

local FormatString = require(Modules.Utilities.FormatString)
local GameConfig = require(Configuration.GameConfig)

-----------
-- Types --
-----------

local TimeFormatter = require(assert(script.Parent:WaitForChild("TimeFormatter", WAIT_TIMEOUT), TAG .. " TimeFormatter not found"))
local ValidationHandler = require(assert(script.Parent:WaitForChild("ValidationHandler", WAIT_TIMEOUT), TAG .. " ValidationHandler not found"))

type GiftData = ValidationHandler.GiftData
type TimeDisplayEntry = TimeFormatter.TimeDisplayEntry

type UIReferences = {
	giftReceivedPrefab: CanvasGroup,
	giftEntriesScrollingFrame: ScrollingFrame,
}

---------------
-- Functions --
---------------

local function generateGiftIdentifierKey(giftData: GiftData): string
	return GIFT_ID_PREFIX .. tostring(giftData.Id)
end

local function formatGiftAmount(amount: number): string
	return GameConfig.ROBUX_ICON_UTF .. FormatString.formatNumberWithThousandsSeparatorCommas(amount)
end

local function formatGiftMessage(gifterName: string, formattedAmount: string): string
	return string.format(MESSAGE_FORMAT_GIFT, gifterName, formattedAmount)
end

local function getAvatarHeadshotURL(userId: number): string
	return string.format(GameConfig.AVATAR_HEADSHOT_URL, userId)
end

local function configureGiftDisplayFrame(frame: Frame, giftData: GiftData): ()
	local gifterUserId = ValidationHandler.retrieveUserIdFromUsername(giftData.Gifter) or 1
	local formattedAmount = formatGiftAmount(giftData.Amount)
	local giftMessage = formatGiftMessage(giftData.Gifter, formattedAmount)

	local textLabel = frame:FindFirstChild("TextLabel")
	if textLabel and textLabel:IsA("TextLabel") then
		(textLabel :: TextLabel).Text = giftMessage
	end

	local gifterIcon = frame:FindFirstChild("GifterIcon")
	if gifterIcon and gifterIcon:IsA("ImageLabel") then
		(gifterIcon :: ImageLabel).Image = getAvatarHeadshotURL(gifterUserId)
	end

	local timeLabel = frame:FindFirstChild("TimeLabel")
	if timeLabel and timeLabel:IsA("TextLabel") then
		(timeLabel :: TextLabel).Text = TimeFormatter.calculateRelativeTimeDescription(giftData.Timestamp)
	end
end

local function createGiftDisplayFrameFromData(
	giftData: GiftData,
	uiRefs: UIReferences
): Frame?
	if not ValidationHandler.isValidGiftData(giftData) then
		return nil
	end

	local success, newFrame = pcall(function()
		local frame = uiRefs.giftReceivedPrefab:Clone()
		frame.Name = generateGiftIdentifierKey(giftData)
		frame.Visible = true
		configureGiftDisplayFrame(frame, giftData)
		return frame
	end)

	if success then
		return newFrame :: Frame
	end
	return nil
end

local function collectExistingGiftFrames(uiRefs: UIReferences): { [string]: Frame }
	local existingFrames = {}
	for i, childFrame in uiRefs.giftEntriesScrollingFrame:GetChildren() do
		if childFrame:IsA("Frame") then
			existingFrames[childFrame.Name] = childFrame
		end
	end
	return existingFrames
end

local function updateExistingGiftFrame(
	frame: Frame,
	giftData: GiftData,
	safeExecute: (func: () -> (), errorMessage: string) -> boolean
): ()
	safeExecute(function()
		local timeLabel = frame:FindFirstChild("TimeLabel")
		if timeLabel and timeLabel:IsA("TextLabel") then
			(timeLabel :: TextLabel).Text = TimeFormatter.calculateRelativeTimeDescription(giftData.Timestamp)
		end
	end, "Error updating existing gift frame")
end

local function createOrUpdateGiftFrame(
	giftData: GiftData,
	uiRefs: UIReferences,
	safeExecute: (func: () -> (), errorMessage: string) -> boolean
): Frame?
	local giftIdentifierKey = generateGiftIdentifierKey(giftData)
	local existingFrame = uiRefs.giftEntriesScrollingFrame:FindFirstChild(giftIdentifierKey)

	if existingFrame and existingFrame:IsA("Frame") then
		updateExistingGiftFrame(existingFrame, giftData, safeExecute)
		return existingFrame
	else
		local newFrame = createGiftDisplayFrameFromData(giftData, uiRefs)
		if newFrame then
			newFrame.Parent = uiRefs.giftEntriesScrollingFrame
		end
		return newFrame
	end
end

local function registerTimeDisplayEntry(
	frame: Frame,
	timestamp: number,
	timeDisplayEntries: { TimeDisplayEntry }
): ()
	local label = frame:FindFirstChild("TimeLabel")
	if label and label:IsA("TextLabel") then
		table.insert(timeDisplayEntries, {
			timeDisplayLabel = (label :: TextLabel),
			originalTimestamp = timestamp,
		})
	end
end

local function removeInvalidGiftFrames(
	validKeys: { [string]: boolean },
	existingFrames: { [string]: Frame },
	safeExecute: (func: () -> (), errorMessage: string) -> boolean
): ()
	for frameIdentifier, frameInstance in existingFrames do
		if not validKeys[frameIdentifier] then
			safeExecute(function()
				frameInstance:Destroy()
			end, "Error destroying invalid gift frame")
		end
	end
end

local function populateGiftDisplayWithServerData(
	serverGiftDataList: { GiftData },
	uiRefs: UIReferences,
	timeDisplayEntries: { TimeDisplayEntry },
	safeExecute: (func: () -> (), errorMessage: string) -> boolean
): ()
	assert(serverGiftDataList, "populateGiftDisplayWithServerData: serverGiftDataList is required")
	assert(typeof(serverGiftDataList) == "table", "populateGiftDisplayWithServerData: serverGiftDataList must be a table")
	assert(uiRefs, "populateGiftDisplayWithServerData: uiRefs is required")
	assert(timeDisplayEntries, "populateGiftDisplayWithServerData: timeDisplayEntries is required")
	assert(typeof(timeDisplayEntries) == "table", "populateGiftDisplayWithServerData: timeDisplayEntries must be a table")
	assert(safeExecute, "populateGiftDisplayWithServerData: safeExecute is required")

	local validGiftIdentifierKeys = {}
	local existingGiftDisplayFrames = collectExistingGiftFrames(uiRefs)

	table.clear(timeDisplayEntries)

	for i, individualGiftData in serverGiftDataList do
		if not ValidationHandler.isValidGiftData(individualGiftData) then
			continue
		end

		local giftIdentifierKey = generateGiftIdentifierKey(individualGiftData)
		validGiftIdentifierKeys[giftIdentifierKey] = true

		local frame = createOrUpdateGiftFrame(individualGiftData, uiRefs, safeExecute)
		if frame then
			registerTimeDisplayEntry(frame, individualGiftData.Timestamp, timeDisplayEntries)
		end
	end

	removeInvalidGiftFrames(validGiftIdentifierKeys, existingGiftDisplayFrames, safeExecute)
end

-----------
-- Setup --
-----------

local UIRenderer = {
	populateGiftDisplayWithServerData = populateGiftDisplayWithServerData,
}

return UIRenderer