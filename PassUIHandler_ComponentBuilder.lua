--!strict

--[[
	PassUIHandler_ComponentBuilder - UI component reference builder for donation interface

	What it does:
	- Validates and constructs UI component references from ScreenGui
	- Ensures all required UI elements exist before returning component table
	- Provides type-safe access to UI elements

	Returns: Module table with functions:
	- buildUIComponents(donationInterface: ScreenGui): UIComponents? - Builds component table
	- validateUIComponents(components: any): boolean - Validates component structure

	Usage:
	local ComponentBuilder = require(script.ComponentBuilder)
	local components = ComponentBuilder.buildUIComponents(playerGui.PassUI)
	if components then
		components.MainFrame.Visible = true
	end
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local PassUIUtilities = require(Modules.Utilities.PassUIUtilities)

-----------
-- Types --
-----------
export type UIComponents = {
	MainFrame: Frame,
	HelpFrame: Frame,
	ItemFrame: ScrollingFrame,
	LoadingLabel: TextLabel,
	CloseButton: TextButton,
	RefreshButton: TextButton,
	TimerLabel: TextLabel,
	DataLabel: TextLabel,
	InfoLabel: TextLabel?,
	LinkTextBox: TextBox?,
}

---------------
-- Constants --
---------------
local TAG = "[PassUI.ComponentBuilder]"

local UI_COMPONENT_NAMES = {
	"MainFrame",
	"HelpFrame",
	"ItemFrame",
	"LoadingLabel",
	"CloseButton",
	"RefreshButton",
	"TimerLabel",
	"DataLabel",
	"InfoLabel",
	"LinkTextBox",
}

-----------
-- Module --
-----------
local ComponentBuilder = {}

--[[
	Validates that all required UI components are present
	@param components table - Components table to validate
	@return boolean - True if all required components exist
]]
local function validateUIComponents(components: any): boolean
	if typeof(components) ~= "table" then
		return false
	end
	for i = 1, #UI_COMPONENT_NAMES do
		local componentName = UI_COMPONENT_NAMES[i]
		if not components[componentName] then
			warn(TAG .. " Missing required UI component: " .. componentName)
			return false
		end
	end
	return true
end

--[[
	Builds UI component references from donation interface
	@param donationInterface ScreenGui - The donation UI ScreenGui
	@return UIComponents? - Table of UI components or nil if build failed
]]
function ComponentBuilder.buildUIComponents(donationInterface: ScreenGui): UIComponents?
	local primaryFrame = donationInterface:FindFirstChild("MainFrame")
	if not primaryFrame then
		return nil
	end

	local topNavigationBar = primaryFrame:FindFirstChild("Topbar")
	if not topNavigationBar then
		return nil
	end

	local navigationButtonFrame = topNavigationBar:FindFirstChild("ButtonFrame")
	if not navigationButtonFrame then
		return nil
	end

	local buttonContainer = navigationButtonFrame:FindFirstChild("Holder")
	if not buttonContainer then
		return nil
	end

	local textFrameHolder = topNavigationBar:FindFirstChild("TextFrame")
	if not textFrameHolder then
		return nil
	end

	local textHolder = textFrameHolder:FindFirstChild("Holder")
	if not textHolder then
		return nil
	end

	local components: UIComponents = {
		MainFrame = primaryFrame :: Frame,
		HelpFrame = PassUIUtilities.safeWaitForChild(primaryFrame, "HelpFrame") :: Frame,
		ItemFrame = PassUIUtilities.safeWaitForChild(primaryFrame, "ItemFrame") :: ScrollingFrame,
		LoadingLabel = PassUIUtilities.safeWaitForChild(primaryFrame, "LoadingLabel") :: TextLabel,
		CloseButton = PassUIUtilities.safeWaitForChild(buttonContainer, "CloseButton") :: TextButton,
		RefreshButton = PassUIUtilities.safeWaitForChild(buttonContainer, "RefreshButton") :: TextButton,
		TimerLabel = PassUIUtilities.safeWaitForChild(buttonContainer, "TimerLabel") :: TextLabel,
		DataLabel = PassUIUtilities.safeWaitForChild(textHolder, "TextLabel") :: TextLabel,
		InfoLabel = nil,
		LinkTextBox = nil,
	}

	if components.HelpFrame then
		components.InfoLabel = PassUIUtilities.safeWaitForChild(components.HelpFrame, "InfoLabel") :: TextLabel
		components.LinkTextBox = PassUIUtilities.safeWaitForChild(components.HelpFrame, "LinkTextBox") :: TextBox
	end

	if not validateUIComponents(components) then
		return nil
	end

	return components
end

--[[
	Validates UI components table
	@param components any - Components to validate
	@return boolean - True if valid
]]
function ComponentBuilder.validateUIComponents(components: any): boolean
	return validateUIComponents(components)
end

return ComponentBuilder