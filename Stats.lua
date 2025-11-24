--!strict

--[[
	Stats/Leaderboard System

	Server-side leaderboard management and display system.
	Fetches data from OrderedDataStores and updates leaderboard UIs.

	Returns: Nothing (server-side initialization script)

	Usage: Runs automatically on server, manages all leaderboards
]]

--------------
-- Services --
--------------
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

----------------
-- References --
----------------
local network = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network")
local remotes = assert(network:WaitForChild("Remotes", 10), "Failed to find Remotes")
local leaderboardRemotes = assert(remotes:WaitForChild("Leaderboards", 10), "Failed to find Leaderboards")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Failed to find Configuration")

local ResourceCleanup = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("ResourceCleanup", 10), "Failed to find ResourceCleanup"))
local EnhancedValidation = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("EnhancedValidation", 10), "Failed to find EnhancedValidation"))
local GameConfig = require(assert(Configuration:WaitForChild("GameConfig", 10), "Failed to find GameConfig"))

-- Submodules
local DataFetcher = require(assert(script:WaitForChild("DataFetcher", 10), "Failed to find DataFetcher"))
local DisplayManager = require(assert(script:WaitForChild("DisplayManager", 10), "Failed to find DisplayManager"))
local UpdateScheduler = require(assert(script:WaitForChild("UpdateScheduler", 10), "Failed to find UpdateScheduler"))
local UIElementFinder = require(assert(script:WaitForChild("UIElementFinder", 10), "Failed to find UIElementFinder"))

local instances = assert(ReplicatedStorage:WaitForChild("Instances", 10), "Failed to find Instances")
local guiPrefabs = assert(instances:WaitForChild("GuiPrefabs", 10), "Failed to find GuiPrefabs")
local leaderboardPrefab = assert(guiPrefabs:WaitForChild("LeaderboardEntryPrefab", 10), "Failed to find LeaderboardEntryPrefab")

local leaderboardsContainer = assert(Workspace:WaitForChild("Leaderboards", 10), "Failed to find Leaderboards container")

----------------
-- Constants --
----------------
local TAG = "[LeaderboardStats]"

local LEADERBOARD_ENTRY_FADE_IN_DURATION = 0.5
local DATASTORE_MAXIMUM_PAGE_SIZE = 100
local UPDATE_STAGGER_DELAY = 2

local TRACKED_LEADERBOARD_CONFIGURATIONS = {
	{
		statisticName = "Donated",
		dataStoreKey = GameConfig.DATASTORE.DONATED_ORDERED_KEY,
		clientUpdateEvent = leaderboardRemotes:WaitForChild("UpdateDonated"),
		displayType = "currency",
	},
	{
		statisticName = "Raised",
		dataStoreKey = GameConfig.DATASTORE.RAISED_ORDERED_KEY,
		clientUpdateEvent = leaderboardRemotes:WaitForChild("UpdateRaised"),
		displayType = "currency",
	},
	{
		statisticName = "Wins",
		dataStoreKey = GameConfig.DATASTORE.WINS_ORDERED_KEY,
		clientUpdateEvent = leaderboardRemotes:WaitForChild("UpdateWins"),
		displayType = "number",
	},
}

---------------
-- Variables --
---------------
local activeLeaderboards = {}
local resourceManager = ResourceCleanup.new()
local activeThreads = {}

local isShuttingDown = false

-- Wire up dependencies
UIElementFinder.leaderboardsContainer = leaderboardsContainer
UpdateScheduler.isShuttingDown = isShuttingDown

---------------
-- Logging --
---------------
local function log(fmt: string, ...: any): ()
	print(TAG .. " " .. string.format(fmt, ...))
end

local function warnlog(fmt: string, ...: any): ()
	warn(TAG .. " " .. string.format(fmt, ...))
end

---------------
-- Utilities --
---------------
local function trackThread(thr: thread): thread
	activeThreads[#activeThreads + 1] = thr
	return thr
end

local function cancelAllThreads(): ()
	for i = 1, #activeThreads do
		local thr = activeThreads[i]
		if thr and coroutine.status(thr) ~= "dead" then
			task.cancel(thr)
		end
	end
	table.clear(activeThreads)
end

local function cleanupAllResources(): ()
	resourceManager:cleanupAll()
	cancelAllThreads()
end

--[[
	Creates system configuration for a leaderboard

	@param leaderboardConfig any - Leaderboard config
	@return any - System configuration
]]
local function createSystemConfiguration(leaderboardConfig: any): any
	return {
		AVATAR_HEADSHOT_URL = GameConfig.AVATAR_HEADSHOT_URL,
		ROBUX_ICON_UTF = GameConfig.ROBUX_ICON_UTF,
		LEADERBOARD_CONFIG = GameConfig.LEADERBOARD_CONFIG,
		FormatHandler = require(Modules.Utilities.FormatString),
		displayType = leaderboardConfig.displayType,
	}
end

--------------------------
-- Leaderboard Refresh --
--------------------------
local function refreshLeaderboardDataAsync(leaderboardState: any): boolean
	if isShuttingDown then
		return false
	end

	local leaderboardConfig = leaderboardState.config
	local orderedDataStore = leaderboardState.dataStore
	local displayFrameCollection = leaderboardState.displayFrames
	local systemConfiguration = leaderboardState.systemConfig

	local maximumEntriesToRetrieve =
		math.min(systemConfiguration.LEADERBOARD_CONFIG.DISPLAY_COUNT, DATASTORE_MAXIMUM_PAGE_SIZE)

	local dataRetrievalSuccess, retrievedDataResult = DataFetcher.retrieveLeaderboardData(
		orderedDataStore,
		maximumEntriesToRetrieve,
		systemConfiguration
	)

	if not dataRetrievalSuccess then
		UpdateScheduler.updateLeaderboardState(leaderboardState, false)
		return false
	end

	if not DataFetcher.validateLeaderboardDataPages(retrievedDataResult) then
		UpdateScheduler.updateLeaderboardState(leaderboardState, false)
		return false
	end

	local leaderboardDataPages = retrievedDataResult

	local extractSuccess, processedLeaderboardEntries = DataFetcher.extractLeaderboardEntries(
		leaderboardDataPages,
		systemConfiguration.LEADERBOARD_CONFIG.DISPLAY_COUNT
	)

	if not extractSuccess or not processedLeaderboardEntries then
		UpdateScheduler.updateLeaderboardState(leaderboardState, false)
		return false
	end

	local maximumCharacterDisplayCount =
		math.min(systemConfiguration.LEADERBOARD_CONFIG.TOP_DISPLAY_AMOUNT, #processedLeaderboardEntries)

	local topPlayersForCharacterDisplay =
		DataFetcher.prepareTopPlayersData(processedLeaderboardEntries, maximumCharacterDisplayCount)
	DataFetcher.sendTopPlayerDataToClients(
		leaderboardConfig.clientUpdateEvent,
		topPlayersForCharacterDisplay,
		leaderboardConfig.statisticName
	)

	local displaySuccess = DisplayManager.updateDisplayFrames(
		displayFrameCollection,
		processedLeaderboardEntries,
		systemConfiguration,
		leaderboardConfig.statisticName
	)

	if not displaySuccess then
		UpdateScheduler.updateLeaderboardState(leaderboardState, false)
		return false
	end

	UpdateScheduler.updateLeaderboardState(leaderboardState, true)
	return true
end

--------------------------
-- Client Ready Handler --
--------------------------
local function connectClientReadyEvent(leaderboardState: any): ()
	-- SECURITY: RemoteEvent handler for client ready notifications
	local connection = leaderboardState.config.clientUpdateEvent.OnServerEvent:Connect(function(
		requestingPlayer,
		clientMessage
	)
		-- Step 1-3: Validate player and message type (defense-in-depth)
		-- UpdateScheduler also validates, but explicit validation at handler level is clearer
		if not EnhancedValidation.validateRemoteArgs(requestingPlayer, {
			{clientMessage, "string", {minLength = 1, maxLength = 100}},
			}) then
			return -- Silent fail on invalid input
		end

		-- Step 4: No rate limiting needed - this is a ready notification, not a frequent action
		-- Step 5-9: Handled in UpdateScheduler.handleClientReadyEvent
		UpdateScheduler.handleClientReadyEvent(requestingPlayer, clientMessage, leaderboardState)
	end)
	resourceManager:trackConnection(connection)
end

--------------------
-- Initialization --
--------------------
local function initializeLeaderboard(leaderboardConfig: any, index: number): any
	local success, orderedDataStore = pcall(function()
		return DataStoreService:GetOrderedDataStore(leaderboardConfig.dataStoreKey)
	end)

	if not success then
		warnlog("Failed to get OrderedDataStore for %s: %s", leaderboardConfig.statisticName, tostring(orderedDataStore))
		return nil
	end

	local leaderboardScrollingFrame = UIElementFinder.getLeaderboardUIElements(leaderboardConfig)
	if not leaderboardScrollingFrame then
		warnlog("Missing leaderboard UI for %s", leaderboardConfig.statisticName)
		return nil
	end

	local systemConfiguration = createSystemConfiguration(leaderboardConfig)

	local displayFrames = DisplayManager.createLeaderboardDisplayFrames(
		leaderboardScrollingFrame,
		systemConfiguration.LEADERBOARD_CONFIG.DISPLAY_COUNT,
		systemConfiguration.LEADERBOARD_CONFIG.COLORS,
		LEADERBOARD_ENTRY_FADE_IN_DURATION,
		leaderboardPrefab
	)

	if #displayFrames == 0 then
		warnlog("Failed to create display frames for leaderboard: %s", leaderboardConfig.statisticName)
		return nil
	end

	local leaderboardState = {
		config = leaderboardConfig,
		dataStore = orderedDataStore,
		displayFrames = displayFrames,
		systemConfig = systemConfiguration,
		updateThread = nil,
		consecutiveFailures = 0,
		lastUpdateTime = 0,
		lastUpdateSuccess = false,
	}

	connectClientReadyEvent(leaderboardState)

	task.delay(index * UPDATE_STAGGER_DELAY, function()
		if not isShuttingDown then
			UpdateScheduler.setupLeaderboardUpdateLoop(leaderboardState)
		end
	end)

	log("Successfully initialized leaderboard: %s", leaderboardConfig.statisticName)
	return leaderboardState
end

local function initializeAllLeaderboards(): ()
	-- Wire up UpdateScheduler dependencies
	UpdateScheduler.refreshLeaderboardDataAsync = refreshLeaderboardDataAsync
	UpdateScheduler.trackThread = trackThread

	for index = 1, #TRACKED_LEADERBOARD_CONFIGURATIONS do
		local leaderboardConfig = TRACKED_LEADERBOARD_CONFIGURATIONS[index]
		local leaderboardState = initializeLeaderboard(leaderboardConfig, index)
		if leaderboardState then
			activeLeaderboards[#activeLeaderboards + 1] = leaderboardState
		else
			warnlog("Failed to initialize leaderboard: %s", leaderboardConfig.statisticName)
		end
	end
end

--------------------
-- Initialization --
--------------------
initializeAllLeaderboards()

-------------
-- Cleanup --
-------------
game:BindToClose(function()
	isShuttingDown = true
	UpdateScheduler.isShuttingDown = true
	cleanupAllResources()
	table.clear(activeLeaderboards)
end)