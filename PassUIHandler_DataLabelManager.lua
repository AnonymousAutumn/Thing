--!strict

--[[
	REFACTOR SUMMARY:
	Extracted from PassUIHandler.lua (513 lines)

	Purpose: Data label management
	- Display name resolution from Player or UserId
	- Data label text updates and formatting
	- Animation playback for data label
	- Rich text formatting for raised amounts

	Benefits:
	- Isolated label display logic
	- Reusable display name resolution
	- Clear animation management
	- Separation from UI construction
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local FormatString = require(Modules.Utilities.FormatString)
local PassUIUtilities = require(Modules.Utilities.PassUIUtilities)
local UsernameCache = require(Modules.Caches.UsernameCache)
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local GameConfig = require(Configuration.GameConfig)

local uiSounds: SoundGroup = SoundService:WaitForChild("UI")

---------------
-- Constants --
---------------
local TAG = "[DataLabelManager]"

local ANIMATION_SETTINGS = {
	DATA_LABEL_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 1, true),
}

-----------
-- Types --
-----------
export type TweenTracker = (Player, Tween) -> Tween

-----------
-- Module --
-----------
local DataLabelManager = {}

--[[
	Resolves display name from Player or UserId

	@param playerReference Player | number - Player instance or UserId
	@return string - Display name or "Unknown"
]]
function DataLabelManager.resolvePlayerDisplayName(playerReference: Player | number): string
	if typeof(playerReference) == "Instance" and playerReference:IsA("Player") then
		return playerReference.DisplayName or playerReference.Name or "Unknown"
	end

	if not ValidationUtils.isValidUserId(playerReference) then
		warn(TAG .. " Invalid player reference: " .. tostring(playerReference))
		return "Unknown"
	end

	return UsernameCache.getUsername(playerReference)
end

--[[
	Plays data label animation with sound

	@param player Player - Player viewing the UI
	@param dataLabel TextLabel - Label to animate
	@param trackTween TweenTracker - Function to track tween
]]
function DataLabelManager.playDataLabelAnimation(player: Player, dataLabel: TextLabel, trackTween: TweenTracker): ()
	local coinJangleSound = uiSounds:FindFirstChild("Jangle")
	if coinJangleSound and coinJangleSound:IsA("Sound") then
		coinJangleSound:Play()
	end

	local labelAnimationTween = TweenService:Create(
		dataLabel.Parent,
		ANIMATION_SETTINGS.DATA_LABEL_TWEEN,
		{ Position = UDim2.new(0.485, 0, 0.75, 0) }
	)

	trackTween(player, labelAnimationTween)
	labelAnimationTween:Play()
end

--[[
	Updates data label for viewing mode (others' items)

	@param dataLabel TextLabel - Label to update
	@param currentlyViewing Player | number - Player being viewed
]]
function DataLabelManager.updateLabelForViewingMode(dataLabel: TextLabel, currentlyViewing: Player | number): ()
	local targetDisplayName = DataLabelManager.resolvePlayerDisplayName(currentlyViewing)
	dataLabel.RichText = false
	dataLabel.Text = targetDisplayName .. "'s items"
end

--[[
	Updates data label for own passes mode (raised amount)

	@param dataLabel TextLabel - Label to update
	@param viewer Player - Viewer player
	@return number - Raised amount value
]]
function DataLabelManager.updateLabelForOwnMode(dataLabel: TextLabel, viewer: Player): number
	local leaderstats = PassUIUtilities.safeWaitForChild(viewer, "leaderstats", 3)
	local raisedValue = 0

	if leaderstats then
		local raised = PassUIUtilities.safeWaitForChild(leaderstats, "Raised", 3)
		if raised and typeof(raised.Value) == "number" then
			raisedValue = raised.Value
		end
	end

	local formattedRaisedAmount = FormatString.formatNumberWithThousandsSeparatorCommas(raisedValue)
	dataLabel.RichText = true
	dataLabel.Text = string.format(GameConfig.AMOUNT_RAISED_RICHTEXT, formattedRaisedAmount)

	return raisedValue
end

--[[
	Updates data display label based on viewing context

	@param dataLabel TextLabel - Label to update
	@param timerLabel TextLabel - Timer label to configure
	@param refreshButton GuiButton - Refresh button to configure
	@param viewer Player - Viewer player
	@param currentlyViewing Player | number? - Player being viewed (nil = own passes)
	@param isInGiftingMode boolean - Whether in gifting mode
	@param shouldPlayAnimation boolean - Whether to play animation
	@param trackTween TweenTracker - Function to track tween
]]
function DataLabelManager.updateDataDisplayLabel(
	dataLabel: TextLabel,
	timerLabel: TextLabel,
	refreshButton: GuiButton,
	viewer: Player,
	currentlyViewing: (Player | number)?,
	isInGiftingMode: boolean,
	shouldPlayAnimation: boolean,
	trackTween: TweenTracker
): ()
	if isInGiftingMode or currentlyViewing then
		DataLabelManager.updateLabelForViewingMode(dataLabel, currentlyViewing)
		timerLabel.Visible = false
		refreshButton.Visible = false
	else
		DataLabelManager.updateLabelForOwnMode(dataLabel, viewer)

		if shouldPlayAnimation then
			DataLabelManager.playDataLabelAnimation(viewer, dataLabel, trackTween)
		end
	end
end

return DataLabelManager