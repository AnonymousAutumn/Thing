--!strict

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")
local bindables = network:WaitForChild("Bindables")
local bindableEvents = bindables:WaitForChild("Events")

local highlightEvent = remoteEvents:WaitForChild("CreateHighlight")
local giftUIEvent = remoteEvents:WaitForChild("ToggleGiftUI")
local updateUIEvent = bindableEvents:WaitForChild("UpdateUI")
local ToggleUIEvent = bindableEvents:WaitForChild("ToggleUI")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local GamepassCacheManager = require(Modules.Caches.PassCache)
local PassUIUtilities = require(Modules.Utilities.PassUIUtilities)
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local EnhancedValidation = require(Modules.Utilities.EnhancedValidation)
local GameConfig = require(Configuration.GameConfig)

-- Submodules
local ComponentBuilder = require(script.ComponentBuilder)
local DisplayRenderer = require(script.DisplayRenderer)
local CooldownManager = require(script.CooldownManager)
local GiftInterface = require(script.GiftInterface)
local StateManager = require(script.StateManager)
local DataLabelManager = require(script.DataLabelManager)

-----------
-- Types --
-----------
type GamepassData = DisplayRenderer.GamepassData
type UIComponents = ComponentBuilder.UIComponents
type PlayerUIState = StateManager.PlayerUIState

type ViewingContext = {
	Viewer: Player,
	Viewing: Player | number,
}

-------------------
-- Configuration --
-------------------
local TAG = "[DonationUIManager]"

local ATTR = {
	Viewing = "Viewing",
	ViewingOwnPasses = "ViewingOwnPasses",
	Gifting = "Gifting",
	CooldownTime = "CooldownTime",
	PromptsDisabled = "PromptsDisabled",
}

---------------
-- Variables --
---------------
local playerCooldownRegistry: { [number]: boolean } = {}
local playerUIStates: { [number]: PlayerUIState } = {}
local globalResourceManager = ResourceCleanup.new()

-- Wire up dependencies for submodules
StateManager.playerUIStates = playerUIStates
StateManager.playerCooldownRegistry = playerCooldownRegistry
CooldownManager.playerUIStates = playerUIStates
CooldownManager.playerCooldownRegistry = playerCooldownRegistry

---------------
-- Utilities --
---------------
local function trackGlobalConnection(connection: RBXScriptConnection): RBXScriptConnection
	return globalResourceManager:trackConnection(connection)
end

-------------------------
-- UI Construction/Get --
-------------------------
local function retrievePlayerDonationInterface(targetPlayer: Player, isInGiftingMode: boolean): UIComponents?
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		warn(TAG .. " Invalid player for UI retrieval")
		return nil
	end

	local playerGuiContainer = targetPlayer:FindFirstChild("PlayerGui")
	if not playerGuiContainer then
		return nil
	end

	local donationInterface = playerGuiContainer:FindFirstChild("PassUI")
	if not donationInterface then
		return nil
	end

	local interfaceComponents = ComponentBuilder.buildUIComponents(donationInterface)
	if not interfaceComponents then
		return nil
	end

	local closeConnection = interfaceComponents.CloseButton.MouseButton1Click:Once(function()
		pcall(function()
			if isInGiftingMode then
				targetPlayer:SetAttribute(ATTR.Gifting, nil)
				local state = StateManager.getPlayerUIState(targetPlayer)
				if state then
					state.isGifting = false
				end
			end

			interfaceComponents.MainFrame.Visible = false
			highlightEvent:FireClient(targetPlayer, nil)
			StateManager.cleanupPlayerResources(targetPlayer, false)
		end)
	end)
	StateManager.trackPlayerConnection(targetPlayer, closeConnection)

	return interfaceComponents
end

--------------------
-- UI Manipulation --
--------------------
local function refreshDataDisplayLabel(isInGiftingMode: boolean, viewingContext: ViewingContext, shouldPlayAnimation: boolean): ()
	if not ValidationUtils.isValidPlayer(viewingContext.Viewer) then
		warn(TAG .. " Invalid viewer for data label refresh")
		return
	end

	local userInterface = retrievePlayerDonationInterface(viewingContext.Viewer, isInGiftingMode)
	if not userInterface then
		return
	end

	local success = pcall(function()
		DataLabelManager.updateDataDisplayLabel(
			userInterface.DataLabel,
			userInterface.TimerLabel,
			userInterface.RefreshButton,
			viewingContext.Viewer,
			viewingContext.Viewing,
			isInGiftingMode,
			shouldPlayAnimation or false,
			StateManager.trackPlayerTween
		)
	end)
	if not success then
		warn(TAG .. " Error refreshing data label for " .. viewingContext.Viewer.Name)
	end
end

--------------------------
-- Viewing Mode Handlers --
--------------------------
local function handleGiftRecipientDisplay(
	userInterface: UIComponents,
	currentViewer: Player,
	giftRecipientRef: Player | number
): ()
	local recipientUserId = nil
	if typeof(giftRecipientRef) == "number" then
		if ValidationUtils.isValidUserId(giftRecipientRef) then
			recipientUserId = giftRecipientRef
		end
	elseif typeof(giftRecipientRef) == "Instance" and giftRecipientRef:IsA("Player") then
		recipientUserId = giftRecipientRef.UserId
	end

	if not recipientUserId then
		return
	end

	currentViewer:SetAttribute(ATTR.Viewing, recipientUserId)

	local recipientGamepassData = GamepassCacheManager.LoadGiftRecipientGamepassDataTemporarily(recipientUserId)
	local recipientGamepasses = recipientGamepassData and recipientGamepassData.gamepasses or {}

	recipientGamepasses = DisplayRenderer.truncateGamepassList(recipientGamepasses)

	DisplayRenderer.configureEmptyStateVisibility(userInterface, recipientGamepasses, false)
	userInterface.LoadingLabel.Visible = (#recipientGamepasses == 0)

	DisplayRenderer.displayGamepasses(userInterface.ItemFrame, recipientGamepasses, currentViewer, recipientUserId)
end

local function handleStandardPlayerDisplay(
	userInterface: UIComponents,
	currentViewer: Player,
	targetPlayerToView: Player,
	viewingContext: ViewingContext,
	shouldReloadData: boolean
): ()
	if not ValidationUtils.isValidPlayer(targetPlayerToView) then
		warn(TAG .. " Invalid target player for viewing")
		return
	end

	local isViewingOwnPasses = (viewingContext.Viewing == nil)
	currentViewer:SetAttribute(ATTR.Viewing, targetPlayerToView.UserId)

	if shouldReloadData then
		GamepassCacheManager.ReloadPlayerGamepassDataCache(currentViewer)
	end

	local targetPlayerData = GamepassCacheManager.GetPlayerCachedGamepassData(targetPlayerToView)
	local targetPlayerGamepasses = targetPlayerData and targetPlayerData.gamepasses or {}

	targetPlayerGamepasses = DisplayRenderer.truncateGamepassList(targetPlayerGamepasses)

	DisplayRenderer.configureEmptyStateVisibility(userInterface, targetPlayerGamepasses, isViewingOwnPasses)
	userInterface.LoadingLabel.Visible = DisplayRenderer.shouldShowLoadingLabel(
		userInterface,
		targetPlayerGamepasses,
		isViewingOwnPasses,
		viewingContext
	)
	DisplayRenderer.configureEmptyStateMessages(userInterface, targetPlayerData, #targetPlayerGamepasses)
	DisplayRenderer.displayGamepasses(userInterface.ItemFrame, targetPlayerGamepasses, currentViewer, targetPlayerToView.UserId)
end

local function populateGamepassDisplayFrame(viewingContext: ViewingContext, shouldReloadData: boolean, isInGiftingMode: boolean): ()
	if not ValidationUtils.isValidPlayer(viewingContext.Viewer) then
		warn(TAG .. " Invalid viewer for gamepass display")
		return
	end

	local userInterface = retrievePlayerDonationInterface(viewingContext.Viewer, isInGiftingMode)
	if not userInterface then
		return
	end

	local success = pcall(function()
		PassUIUtilities.resetGamepassScrollFrame(userInterface.ItemFrame)
		userInterface.LoadingLabel.Visible = true
		userInterface.InfoLabel.Visible = false
		userInterface.LinkTextBox.Visible = false

		local currentViewer = viewingContext.Viewer

		if isInGiftingMode then
			handleGiftRecipientDisplay(userInterface, currentViewer, viewingContext.Viewing)
			return
		end

		local targetPlayerToView = viewingContext.Viewing or currentViewer
		handleStandardPlayerDisplay(
			userInterface,
			currentViewer,
			targetPlayerToView,
			viewingContext,
			shouldReloadData or false
		)
	end)

	if not success then
		warn(TAG .. " Error populating gamepass display for " .. viewingContext.Viewer.Name)
	end
end

-- Wire up dependencies for submodules
CooldownManager.populateGamepassDisplayFrame = populateGamepassDisplayFrame
GiftInterface.retrievePlayerDonationInterface = retrievePlayerDonationInterface
GiftInterface.refreshDataDisplayLabel = refreshDataDisplayLabel
GiftInterface.populateGamepassDisplayFrame = populateGamepassDisplayFrame
GiftInterface.getOrCreatePlayerUIState = StateManager.getOrCreatePlayerUIState

--------------------------
-- UI Visibility Config --
--------------------------
local function configureUIVisibility(
	userInterface: UIComponents,
	currentViewer: Player,
	isViewingOwnPasses: boolean,
	hasCloseButton: boolean
): ()
	userInterface.MainFrame.Visible = true
	userInterface.CloseButton.Visible = hasCloseButton

	currentViewer:SetAttribute(ATTR.ViewingOwnPasses, isViewingOwnPasses)

	local playerOnCooldown = StateManager.isPlayerOnCooldown(currentViewer)
	userInterface.RefreshButton.Visible = (isViewingOwnPasses and not playerOnCooldown)
	userInterface.TimerLabel.Visible = (isViewingOwnPasses and playerOnCooldown)

	if playerOnCooldown then
		local remainingCooldownTime = currentViewer:GetAttribute(ATTR.CooldownTime)
			or GameConfig.GAMEPASS_CONFIG.REFRESH_COOLDOWN
		userInterface.TimerLabel.Text = tostring(remainingCooldownTime)
	end
end

--------------------
-- UI Toggle Flow --
--------------------
local function handleDonationInterfaceToggle(viewingData: any): ()
	if not ValidationUtils.isValidPlayer(viewingData.Viewer) then
		warn(TAG .. " Invalid viewer for interface toggle")
		return
	end

	local currentViewer = viewingData.Viewer
	local userInterface = retrievePlayerDonationInterface(currentViewer, false)
	if not userInterface then
		return
	end

	local success = pcall(function()
		if not viewingData.Visible then
			userInterface.MainFrame.Visible = false
			currentViewer:SetAttribute(ATTR.ViewingOwnPasses, nil)
			StateManager.cleanupPlayerResources(currentViewer, true)
			return
		end

		local isViewingOwnPasses = (viewingData.Viewing == nil)
		configureUIVisibility(userInterface, currentViewer, isViewingOwnPasses, viewingData.Viewing ~= nil)

		if isViewingOwnPasses then
			local connection = CooldownManager.initializeRefreshButtonBehavior(currentViewer, userInterface, viewingData)
			if connection then
				StateManager.trackPlayerConnection(currentViewer, connection)
			end
		end

		highlightEvent:FireClient(currentViewer, viewingData.Viewing or nil)

		local displayContext = { Viewer = currentViewer, Viewing = viewingData.Viewing }
		refreshDataDisplayLabel(false, displayContext, false)
		populateGamepassDisplayFrame(displayContext, false, false)

		local activeCooldownTime = currentViewer:GetAttribute(ATTR.CooldownTime)
		if activeCooldownTime and activeCooldownTime > 0 then
			CooldownManager.activateRefreshCooldownTimer(currentViewer, userInterface, isViewingOwnPasses)
		end
	end)

	if not success then
		warn(TAG .. " Error toggling interface for " .. currentViewer.Name)
	end
end

-------------
-- Cleanup --
-------------
local function cleanup(): ()
	StateManager.cleanupAllStates()
	globalResourceManager:disconnectAll()
end

------------
-- Events --
------------
trackGlobalConnection(
	Players.PlayerRemoving:Connect(function(departingPlayer)
		StateManager.cleanupPlayerResources(departingPlayer, true)

		pcall(function()
			GamepassCacheManager.UnloadPlayerDataFromCache(departingPlayer)
		end)
	end)
)

-- SECURITY: RemoteEvent for gift UI toggling (defense-in-depth validation)
-- Note: GiftInterface.handleGiftInterfaceToggle also validates, but we validate here too
trackGlobalConnection(giftUIEvent.OnServerEvent:Connect(function(player: Player, recipient: Player | number)
	-- Step 1-3: Validate player at handler level (defense-in-depth)
	if not EnhancedValidation.validatePlayer(player) then
		warn("[PassUIHandler] Invalid player in gift UI toggle")
		return
	end

	-- Step 4-9: Handled in GiftInterface.handleGiftInterfaceToggle (includes rate limiting)
	GiftInterface.handleGiftInterfaceToggle(player, recipient)
end))
trackGlobalConnection(ToggleUIEvent.Event:Connect(handleDonationInterfaceToggle))
trackGlobalConnection(updateUIEvent.Event:Connect(refreshDataDisplayLabel))

trackGlobalConnection(
	game:BindToClose(function()
		cleanup()
	end)
)