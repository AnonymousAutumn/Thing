--!strict

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local FormatString = require(Modules.Utilities.FormatString)
local PassUIUtilities = require(Modules.Utilities.PassUIUtilities)
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local GameConfig = require(Configuration.GameConfig)

local instances: Folder = ReplicatedStorage:WaitForChild("Instances")
local guiPrefabs = instances:WaitForChild("GuiPrefabs")
local passButtonPrefab = guiPrefabs:WaitForChild("PassButtonPrefab")

-----------
-- Types --
-----------
export type GamepassData = {
	Name: string,
	Id: number,
	Price: number,
	Icon: string,
}

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

export type ViewingContext = {
	Viewer: Player,
	Viewing: Player | number,
}

---------------
-- Constants --
---------------
local TAG = "[PassUI.DisplayRenderer]"

local MAX_GAMEPASS_DISPLAY = 100

local ATTR = {
	Viewing = "Viewing",
}

-----------
-- Module --
-----------
local DisplayRenderer = {}

---------------
-- Validation --
---------------
local function isValidGamepassData(data: any): boolean
	return typeof(data) == "table"
		and typeof(data.Name) == "string"
		and ValidationUtils.isValidUserId(data.Id)
		and typeof(data.Price) == "number"
		and data.Price >= 0
end

-----------------------
-- Template Building --
-----------------------

--[[
	Builds a UI template for displaying a single gamepass
	@param gamepassData GamepassData - The gamepass information
	@return TextButton? - The created template or nil on failure
]]
local function buildGamepassDisplayTemplate(gamepassData: GamepassData): TextButton?
	if not isValidGamepassData(gamepassData) then
		warn(TAG .. " Invalid gamepass data for template")
		return nil
	end

	local success, clonedTemplate = pcall(function()
		local template = passButtonPrefab:Clone()

		template.Name = gamepassData.Name
		template:SetAttribute("AssetId", gamepassData.Id)
		template.LayoutOrder = gamepassData.Price

		local priceWithCommas = FormatString.formatNumberWithThousandsSeparatorCommas(gamepassData.Price)
		template.ItemPrice.Text = "<font color='#ffb46a'>" .. GameConfig.ROBUX_ICON_UTF .. "</font> " .. priceWithCommas
		template.ItemIcon.Image = gamepassData.Icon or ""

		return template
	end)

	if not success then
		warn(TAG .. " Failed to build gamepass template: " .. tostring(clonedTemplate))
		return nil
	end

	return clonedTemplate :: TextButton
end

--[[
	Truncates gamepass list to maximum display limit
	@param gamepasses {GamepassData} - List of gamepasses
	@return {GamepassData} - Truncated list (or original if within limit)
]]
function DisplayRenderer.truncateGamepassList(gamepasses: { GamepassData }): { GamepassData }
	if #gamepasses <= MAX_GAMEPASS_DISPLAY then
		return gamepasses
	end

	warn(TAG .. " Gamepass count (" .. #gamepasses .. ") exceeds limit (" .. MAX_GAMEPASS_DISPLAY .. "), truncating")
	local truncated = {}
	for i = 1, MAX_GAMEPASS_DISPLAY do
		truncated[#truncated + 1] = gamepasses[i]
	end
	return truncated
end

-------------------------
-- Empty State Handling --
-------------------------

--[[
	Configures empty state visibility (InfoLabel and LinkTextBox)
	@param userInterface UIComponents - The UI components
	@param availableGamepasses {GamepassData} - Available gamepasses
	@param isOwnerViewingOwnPasses boolean - Whether owner is viewing their own passes
]]
function DisplayRenderer.configureEmptyStateVisibility(
	userInterface: UIComponents,
	availableGamepasses: { GamepassData },
	isOwnerViewingOwnPasses: boolean
): ()
	local shouldDisplayEmptyState = isOwnerViewingOwnPasses and #availableGamepasses == 0
	if userInterface.InfoLabel then
		userInterface.InfoLabel.Visible = shouldDisplayEmptyState
	end
	if userInterface.LinkTextBox then
		userInterface.LinkTextBox.Visible = shouldDisplayEmptyState
	end
end

--[[
	Configures empty state messages based on player data
	@param userInterface UIComponents - The UI components
	@param targetPlayerData any - Player's gamepass data
	@param gamepassCount number - Number of gamepasses
]]
function DisplayRenderer.configureEmptyStateMessages(
	userInterface: UIComponents,
	targetPlayerData: any,
	gamepassCount: number
): ()
	if not userInterface.InfoLabel or not userInterface.LinkTextBox then
		return
	end

	if targetPlayerData and targetPlayerData.games and #targetPlayerData.games == 0 then
		userInterface.InfoLabel.Text = GameConfig.GAMEPASS_CONFIG.NO_EXPERIENCES_STRING
		userInterface.LinkTextBox.Text = GameConfig.GAMEPASS_CONFIG.CREATION_PAGE_URL
	elseif gamepassCount == 0 then
		userInterface.InfoLabel.Text = GameConfig.GAMEPASS_CONFIG.NO_PASSES_STRING
		if targetPlayerData and targetPlayerData.games and #targetPlayerData.games > 0 then
			userInterface.LinkTextBox.Text = string.format(
				GameConfig.GAMEPASS_CONFIG.PASSES_PAGE_URL,
				targetPlayerData.games[1]
			)
		end
	end
end

--[[
	Determines if loading label should be visible
	@param userInterface UIComponents - The UI components
	@param availableGamepasses {GamepassData} - Available gamepasses
	@param isViewingOwnPasses boolean - Whether viewing own passes
	@param viewingContext ViewingContext - Viewing context information
	@return boolean - True if loading label should be visible
]]
function DisplayRenderer.shouldShowLoadingLabel(
	userInterface: UIComponents,
	availableGamepasses: { GamepassData },
	isViewingOwnPasses: boolean,
	viewingContext: ViewingContext
): boolean
	if userInterface.InfoLabel and userInterface.LinkTextBox then
		if userInterface.InfoLabel.Visible and userInterface.LinkTextBox.Visible then
			return false
		end
	end

	if not isViewingOwnPasses and #availableGamepasses == 0 then
		return true
	end

	if viewingContext.Viewing and #availableGamepasses == 0 then
		return true
	end

	return false
end

---------------------
-- Display Gamepasses --
---------------------

--[[
	Displays gamepasses in the scroll frame
	@param scrollFrame ScrollingFrame - The scroll frame to populate
	@param gamepasses {GamepassData} - List of gamepasses to display
	@param currentViewer Player - The player viewing the UI
	@param targetUserId number - The user ID being viewed
]]
function DisplayRenderer.displayGamepasses(
	scrollFrame: ScrollingFrame,
	gamepasses: { GamepassData },
	currentViewer: Player,
	targetUserId: number
): ()
	for i = 1, #gamepasses do
		local gamepassInfo = gamepasses[i]

		-- Check if viewer is still looking at the same target
		if currentViewer:GetAttribute(ATTR.Viewing) ~= targetUserId then
			PassUIUtilities.resetGamepassScrollFrame(scrollFrame)
			break
		end

		-- Only create template if it doesn't exist
		if not scrollFrame:FindFirstChild(gamepassInfo.Name) then
			local template = buildGamepassDisplayTemplate(gamepassInfo)
			if template then
				template.Parent = scrollFrame
			end
		end
	end
end

return DisplayRenderer