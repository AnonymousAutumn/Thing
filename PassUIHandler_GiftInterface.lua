--!strict

--[[
	PassUIHandler_GiftInterface - Gift UI mode toggle and state management

	What it does:
	- Handles remote event for toggling gift interface
	- Validates gift giver and recipient (Player or UserId)
	- Implements rate limiting to prevent UI spam
	- Manages gifting state and unequips held tools
	- Coordinates with parent module for UI operations

	Returns: Module table with functions:
	- handleGiftInterfaceToggle(giftGiver, giftRecipient) - Toggles gift UI

	Usage:
	local GiftInterface = require(script.GiftInterface)
	GiftInterface.retrievePlayerDonationInterface = parentFunc  -- Inject dependencies
	GiftInterface.handleGiftInterfaceToggle(player, recipientPlayer)
]]

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network = assert(ReplicatedStorage:WaitForChild("Network", 10), "Network folder not found in ReplicatedStorage")
local remotes = assert(network:WaitForChild("Remotes", 10), "Remotes folder not found in Network")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Events folder not found in Remotes")

local highlightEvent = assert(remoteEvents:WaitForChild("CreateHighlight", 10), "CreateHighlight event not found")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local EnhancedValidation = require(Modules.Utilities.EnhancedValidation)
local RateLimiter = require(Modules.Utilities.RateLimiter)

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

export type ViewingContext = {
	Viewer: Player,
	Viewing: Player | number,
}

export type PlayerUIState = {
	connections: { RBXScriptConnection },
	tweens: { Tween },
	cooldownThread: thread?,
	isGifting: boolean,
	lastRefreshTime: number?,
}

---------------
-- Constants --
---------------
local TAG = "[PassUI.GiftInterface]"

local ATTR = {
	Gifting = "Gifting",
}

-----------
-- Module --
-----------
local GiftInterface = {}

-- External dependencies (set by PassUIHandler)
GiftInterface.retrievePlayerDonationInterface = nil :: ((Player, boolean) -> UIComponents?)?
GiftInterface.refreshDataDisplayLabel = nil :: ((boolean, ViewingContext, boolean) -> ())?
GiftInterface.populateGamepassDisplayFrame = nil :: ((ViewingContext, boolean, boolean) -> ())?
GiftInterface.getOrCreatePlayerUIState = nil :: ((Player) -> PlayerUIState)?

--[[
	Unequips currently held tool from player
	@param player Player - The player to unequip from
]]
local function unequipHeldTool(player: Player): ()
	local character = player.Character
	if not character then
		return
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool then
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			equippedTool.Parent = backpack
		end
	end
end

--[[
	Handles gift interface toggle for a player
	@param giftGiver Player - The player giving the gift
	@param giftRecipient Player | number - The gift recipient (Player or UserId)
]]
function GiftInterface.handleGiftInterfaceToggle(giftGiver: Player, giftRecipient: Player | number): ()
	-- Step 1-3: Validate player (giftGiver)
	if not EnhancedValidation.validatePlayer(giftGiver) then
		warn(TAG .. " Invalid gift giver")
		return
	end

	-- Step 1-3: Validate recipient (Player or UserId)
	local isValidRecipient = false
	if typeof(giftRecipient) == "Instance" and giftRecipient:IsA("Player") then
		isValidRecipient = ValidationUtils.isValidPlayer(giftRecipient)
	elseif typeof(giftRecipient) == "number" then
		isValidRecipient = EnhancedValidation.validateUserId(giftRecipient)
	end

	if not isValidRecipient then
		warn(TAG .. " Invalid gift recipient")
		return
	end

	-- Step 4: Rate limiting (prevent UI spam)
	if not RateLimiter.checkRateLimit(giftGiver, "ToggleGiftUI", 1) then
		return -- Silent fail on rate limit
	end

	-- Step 5-9: Business logic below (UI toggle, no sensitive data modification)

	local success = pcall(function()
		highlightEvent:FireClient(giftGiver, nil)
		unequipHeldTool(giftGiver)

		giftGiver:SetAttribute(ATTR.Gifting, true)

		if GiftInterface.getOrCreatePlayerUIState then
			local state = GiftInterface.getOrCreatePlayerUIState(giftGiver)
			state.isGifting = true
		end

		local giftingContext: ViewingContext = { Viewer = giftGiver, Viewing = giftRecipient }

		local giftInterface = nil
		if GiftInterface.retrievePlayerDonationInterface then
			giftInterface = GiftInterface.retrievePlayerDonationInterface(giftGiver, true)
		end

		if not giftInterface then
			warn(TAG .. " Failed to retrieve gift interface")
			return
		end

		giftInterface.MainFrame.Visible = true
		giftInterface.CloseButton.Visible = true

		if GiftInterface.refreshDataDisplayLabel then
			GiftInterface.refreshDataDisplayLabel(true, giftingContext, false)
		end

		if GiftInterface.populateGamepassDisplayFrame then
			GiftInterface.populateGamepassDisplayFrame(giftingContext, false, true)
		end
	end)

	if not success then
		warn(TAG .. " Error toggling gift interface for " .. giftGiver.Name)
	end
end

return GiftInterface