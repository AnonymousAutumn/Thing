--!strict

--[[
	GameUI_StatusAnimator

	Handles visual animations and updates for the game status interface.
	Manages status bar positioning, text updates, and CoreGui toggling for mobile.

	Returns: Table with animation functions:
		- showStatusInterface, hideStatusInterface: Animated show/hide
		- updateStatusText: Updates status label text
		- setExitButtonVisibility: Shows/hides exit button
		- getVisiblePosition: Device-aware positioning
		- toggleCoreGui: Mobile-specific CoreGui management

	Usage:
		local StatusAnimator = require(script.GameUI_StatusAnimator)
		StatusAnimator.statusLabel = textLabel
		StatusAnimator.statusHolder = frame
		StatusAnimator.showStatusInterface()
		StatusAnimator.updateStatusText("Your turn!")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

local GameStateManager = require(script.Parent.GameStateManager)
type GameState = GameStateManager.GameState

---------------
-- Constants --
---------------
local CONFIG = {
	STATUS_ANIMATION_TWEEN_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),

	POSITIONS = {
		STATUS_VISIBLE_DESKTOP = UDim2.new(0.5, 0, 1, -80),
		STATUS_VISIBLE_MOBILE = UDim2.new(0.5, 0, 1, -20),
		STATUS_HIDDEN = UDim2.new(0.5, 0, 1, 40),
	},

	EMPTY_TEXT_PLACEHOLDER = "",
}

-----------
-- Module --
-----------
local StatusAnimator = {}

-- Will be set by init.lua
StatusAnimator.statusLabel = nil :: TextLabel?
StatusAnimator.statusHolder = nil :: Frame?
StatusAnimator.exitButton = nil :: GuiButton?
StatusAnimator.isMobileDevice = false

--[[
	Safe execution helper

	@param func () -> () - Function to execute
	@param errorMessage string - Error message to warn
	@return boolean - True if successful
]]
local function safeExecute(func: () -> (), errorMessage: string): boolean
	local success, errorDetails = pcall(func)
	if not success then
		warn(errorMessage, errorDetails)
	end
	return success
end

--[[
	Updates status text

	@param newText string? - New text or nil for empty
]]
function StatusAnimator.updateStatusText(newText: string?): ()
	safeExecute(function()
		local displayText = newText or CONFIG.EMPTY_TEXT_PLACEHOLDER
		if not ValidationUtils.isValidString(displayText) then
			return
		end
		if StatusAnimator.statusLabel then
			StatusAnimator.statusLabel.Text = displayText
			GameStateManager.state.previousStatusText = displayText
		end
	end, "Error updating status text")
end

--[[
	Sets exit button visibility

	@param isVisible boolean - Whether button should be visible
]]
function StatusAnimator.setExitButtonVisibility(isVisible: boolean): ()
	safeExecute(function()
		if StatusAnimator.exitButton then
			StatusAnimator.exitButton.Visible = isVisible
		end
	end, "Error setting exit button visibility")
end

--[[
	Gets visible position based on device type

	@return UDim2 - Position for visible status
]]
function StatusAnimator.getVisiblePosition(): UDim2
	return StatusAnimator.isMobileDevice and CONFIG.POSITIONS.STATUS_VISIBLE_MOBILE
		or CONFIG.POSITIONS.STATUS_VISIBLE_DESKTOP
end

--[[
	Toggles CoreGUI visibility (mobile only)

	@param enabled boolean - Whether to enable
]]
function StatusAnimator.toggleCoreGui(enabled: boolean): ()
	if not StatusAnimator.isMobileDevice then
		return
	end

	safeExecute(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
	end, "Error toggling core GUI")
end

--[[
	Creates and plays a tween

	@param target GuiObject - Target to animate
	@param properties {[string]: any} - Properties to animate
]]
function StatusAnimator.createAndPlayTween(target: GuiObject, properties: { [string]: any }): ()
	local tween = TweenService:Create(target, CONFIG.STATUS_ANIMATION_TWEEN_INFO, properties)
	GameStateManager.trackTween(tween)
	tween:Play()
end

--[[
	Shows the status interface with animation
]]
function StatusAnimator.showStatusInterface(): ()
	if GameStateManager.state.isStatusVisible then
		return
	end

	safeExecute(function()
		if not StatusAnimator.statusHolder then
			return
		end

		local targetPosition = StatusAnimator.getVisiblePosition()
		StatusAnimator.createAndPlayTween(StatusAnimator.statusHolder, { Position = targetPosition })

		GameStateManager.state.isStatusVisible = true
		StatusAnimator.toggleCoreGui(false)
	end, "Error showing status interface")
end

--[[
	Hides the status interface with animation
]]
function StatusAnimator.hideStatusInterface(): ()
	if not GameStateManager.state.isStatusVisible then
		return
	end

	safeExecute(function()
		if not StatusAnimator.statusHolder then
			return
		end

		StatusAnimator.createAndPlayTween(StatusAnimator.statusHolder, { Position = CONFIG.POSITIONS.STATUS_HIDDEN })

		GameStateManager.state.isStatusVisible = false
		GameStateManager.state.previousStatusText = ""

		StatusAnimator.toggleCoreGui(true)
	end, "Error hiding status interface")
end

--[[
	Checks if status is currently visible

	@return boolean - True if visible
]]
function StatusAnimator.isStatusVisible(): boolean
	return GameStateManager.state.isStatusVisible
end

--[[
	Gets previous status text

	@return string - Previous text
]]
function StatusAnimator.getPreviousStatusText(): string
	return GameStateManager.state.previousStatusText
end

return StatusAnimator