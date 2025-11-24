--!strict

--[[
	PassUIHandler_CooldownManager - Manages refresh button cooldowns for gamepass UI

	What it does:
	- Implements cooldown timer for gamepass data refresh operations
	- Manages refresh button visibility and timer label updates
	- Prevents refresh spam and coordinates with player state tracking
	- Handles cooldown thread lifecycle

	Returns: Module table with functions:
	- activateRefreshCooldownTimer(player, userInterface, isViewingOwnPasses) - Starts cooldown
	- handleRefreshButtonClick(player, userInterface, viewingData) - Processes refresh request
	- initializeRefreshButtonBehavior(player, userInterface, viewingData) - Sets up button connection

	Usage:
	local CooldownManager = require(script.CooldownManager)
	CooldownManager.playerUIStates = playerUIStates  -- Inject dependencies
	CooldownManager.activateRefreshCooldownTimer(player, ui, true)
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

local notificationEvent = assert(remoteEvents:WaitForChild("CreateNotification", 10), "CreateNotification event not found")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Configuration folder not found in ReplicatedStorage")

local GamepassCacheManager = require(Modules.Caches.PassCache)
local StandManager = require(Modules.Managers.Stands)
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local GameConfig = require(Configuration.GameConfig)

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
local TAG = "[PassUI.CooldownManager]"

local ATTR = {
	ViewingOwnPasses = "ViewingOwnPasses",
	CooldownTime = "CooldownTime",
	PromptsDisabled = "PromptsDisabled",
}

-----------
-- Module --
-----------
local CooldownManager = {}

-- External dependencies (set by PassUIHandler)
CooldownManager.playerUIStates = nil :: { [number]: PlayerUIState }?
CooldownManager.playerCooldownRegistry = nil :: { [number]: boolean }?
CooldownManager.populateGamepassDisplayFrame = nil :: ((ViewingContext, boolean, boolean) -> ())?

--[[
	Validates UI components
	@param components any - Components to validate
	@return boolean - True if valid
]]
local function validateUIComponents(components: any): boolean
	return typeof(components) == "table"
		and components.RefreshButton
		and components.TimerLabel
		and components.DataLabel
end

--[[
	Activates refresh cooldown timer for a player
	@param targetPlayer Player - The player to apply cooldown to
	@param userInterface UIComponents - The UI components
	@param isViewingOwnPasses boolean - Whether viewing own passes
]]
function CooldownManager.activateRefreshCooldownTimer(
	targetPlayer: Player,
	userInterface: UIComponents,
	isViewingOwnPasses: boolean
): ()
	if not ValidationUtils.isValidPlayer(targetPlayer) or not validateUIComponents(userInterface) then
		warn(TAG .. " Invalid parameters for cooldown timer")
		return
	end

	if not CooldownManager.playerUIStates then
		warn(TAG .. " playerUIStates not initialized")
		return
	end

	local state = CooldownManager.playerUIStates[targetPlayer.UserId]
	if not state then
		warn(TAG .. " No UI state found for player")
		return
	end

	if state.cooldownThread then
		task.cancel(state.cooldownThread)
	end

	local cooldownDurationSeconds = targetPlayer:GetAttribute(ATTR.CooldownTime)
		or GameConfig.GAMEPASS_CONFIG.REFRESH_COOLDOWN
	userInterface.RefreshButton.Visible = false
	userInterface.TimerLabel.Visible = isViewingOwnPasses

	state.cooldownThread = task.spawn(function()
		local remainingSeconds = cooldownDurationSeconds

		while remainingSeconds > 0 do
			if isViewingOwnPasses then
				userInterface.TimerLabel.Text = tostring(remainingSeconds)
			end

			targetPlayer:SetAttribute(ATTR.CooldownTime, remainingSeconds)
			task.wait(1)
			remainingSeconds = remainingSeconds - 1

			if not targetPlayer:GetAttribute(ATTR.ViewingOwnPasses) then
				userInterface.TimerLabel.Visible = false
				userInterface.RefreshButton.Visible = false
			end
		end

		userInterface.TimerLabel.Text = ""
		userInterface.TimerLabel.Visible = false
		targetPlayer:SetAttribute(ATTR.CooldownTime, nil)

		if CooldownManager.playerCooldownRegistry then
			CooldownManager.playerCooldownRegistry[targetPlayer.UserId] = nil
		end

		if state then
			state.cooldownThread = nil
		end

		if targetPlayer:GetAttribute(ATTR.ViewingOwnPasses) and userInterface.DataLabel.RichText then
			userInterface.RefreshButton.Visible = true
		end
	end)
end

--[[
	Handles refresh button click event
	@param currentViewer Player - The player clicking refresh
	@param userInterface UIComponents - The UI components
	@param viewingData ViewingContext - The viewing context
]]
function CooldownManager.handleRefreshButtonClick(
	currentViewer: Player,
	userInterface: UIComponents,
	viewingData: ViewingContext
): ()
	if not CooldownManager.playerCooldownRegistry or not CooldownManager.playerUIStates then
		warn(TAG .. " Registries not initialized")
		return
	end

	if CooldownManager.playerCooldownRegistry[currentViewer.UserId] then
		return
	end

	local success = pcall(function()
		CooldownManager.playerCooldownRegistry[currentViewer.UserId] = true
		currentViewer:SetAttribute(ATTR.PromptsDisabled, true)

		local state = CooldownManager.playerUIStates[currentViewer.UserId]
		if state then
			state.lastRefreshTime = os.time()
		end

		local refreshContext = { Viewer = currentViewer, Viewing = viewingData.Viewing }

		if CooldownManager.populateGamepassDisplayFrame then
			CooldownManager.populateGamepassDisplayFrame(refreshContext, true, false)
		end

		currentViewer:SetAttribute(ATTR.PromptsDisabled, false)

		CooldownManager.activateRefreshCooldownTimer(currentViewer, userInterface, true)
		notificationEvent:FireClient(currentViewer, "Your passes have been refreshed!", "Success")

		StandManager.BroadcastStandRefresh(currentViewer)
	end)

	if not success then
		warn(TAG .. " Error during refresh for " .. currentViewer.Name)
		CooldownManager.playerCooldownRegistry[currentViewer.UserId] = nil
		currentViewer:SetAttribute(ATTR.PromptsDisabled, false)
	end
end

--[[
	Initializes refresh button behavior
	@param currentViewer Player - The player viewing the UI
	@param userInterface UIComponents - The UI components
	@param viewingData ViewingContext - The viewing context
	@return RBXScriptConnection? - The connection or nil
]]
function CooldownManager.initializeRefreshButtonBehavior(
	currentViewer: Player,
	userInterface: UIComponents,
	viewingData: ViewingContext
): RBXScriptConnection?
	if not ValidationUtils.isValidPlayer(currentViewer) or not validateUIComponents(userInterface) then
		warn(TAG .. " Invalid parameters for refresh button")
		return nil
	end

	local refreshConnection = userInterface.RefreshButton.MouseButton1Click:Connect(function()
		CooldownManager.handleRefreshButtonClick(currentViewer, userInterface, viewingData)
	end)

	return refreshConnection
end

return CooldownManager