--!strict

--[[
	PlayerManager - Main player initialization and lifecycle coordinator

	What it does:
	- Handles player join/leave events
	- Initializes player data systems (statistics, gamepasses, leaderboards)
	- Manages initialization state tracking with timeout protection
	- Coordinates cross-server leaderboard update synchronization
	- Implements graceful shutdown with data save
	- Kicks players on initialization failures with descriptive messages
	- Manages OrderedDataStore registry for leaderboards

	Returns: N/A (Event-driven module, no return value)

	Usage:
	- Automatically initializes on require()
	- Processes existing players in server
	- Handles PlayerAdded/PlayerRemoving events
	- Subscribes to cross-server leaderboard updates
	- Saves all data on game shutdown
]]

--------------
-- Services --
--------------
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----------------
-- References --
----------------
local network = assert(ReplicatedStorage:WaitForChild("Network", 10), "Network folder not found in ReplicatedStorage")
local bindables = assert(network:WaitForChild("Bindables", 10), "Bindables folder not found in Network")
local bindableEvents = assert(bindables:WaitForChild("Events", 10), "Events folder not found in Bindables")
local signals = assert(network:WaitForChild("Signals", 10), "Signals folder not found in Network")

local updateUI = assert(bindableEvents:WaitForChild("UpdateUI", 10), "UpdateUI event not found")
local dataLoaded = assert(signals:WaitForChild("DataLoaded", 10), "DataLoaded signal not found")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Configuration folder not found in ReplicatedStorage")

local PlayerData = require(Modules.Managers.PlayerData)
local GamepassCacheManager = require(Modules.Caches.PassCache)
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local GameConfig = require(Configuration.GameConfig)

-- Submodules
local LeaderboardBuilder = require(script.LeaderboardBuilder)
local InitStateTracker = require(script.InitStateTracker)
local CrossServerSync = require(script.CrossServerSync)

---------------
-- Constants --
---------------
local TAG = "[PlayerDataManager]"

local PLAYER_INIT_TIMEOUT = 30
local INIT_STATE_CLEANUP_DELAY = 60
local UI_UPDATE_STATISTIC = "Raised"

local KICK_MESSAGES = {
	DATA_FETCH_ERROR = "Error fetching data: %s",
	DATA_LOAD_FAILED = "Data loading failed. Please rejoin.",
	INIT_TIMEOUT = "Data initialization timed out. Please rejoin.",
}

---------------
-- Variables --
---------------
local orderedDataStoreRegistry = {}
local initTracker = InitStateTracker.new()
local crossServerSync = CrossServerSync.new()

local isShuttingDown = false
local resourceManager = ResourceCleanup.new()

---------------
-- Utilities --
---------------
local function log(message: string, ...): ()
	print(string.format(TAG .. " " .. message, ...))
end

local function warnlog(message: string, ...): ()
	warn(string.format(TAG .. " " .. message, ...))
end

local function safeKick(player: Player, message: string): ()
	if ValidationUtils.isValidPlayer(player) then
		player:Kick(message)
	end
end

-----------------------
-- DataStore Registry --
-----------------------
local function initializeDataStoreRegistry(): boolean
	local success, errorMessage = pcall(function()
		orderedDataStoreRegistry = {
			Wins = DataStoreService:GetOrderedDataStore(GameConfig.DATASTORE.WINS_ORDERED_KEY),
			Donated = DataStoreService:GetOrderedDataStore(GameConfig.DATASTORE.DONATED_ORDERED_KEY),
			Raised = DataStoreService:GetOrderedDataStore(GameConfig.DATASTORE.RAISED_ORDERED_KEY),
		}
	end)

	if not success then
		warnlog("Failed to initialize DataStore registry: %s", tostring(errorMessage))
	end

	return success
end

-----------------------------
-- Leaderboard UI Updates  --
-----------------------------
local function triggerUIRefresh(player: Player): ()
	if not ValidationUtils.isValidPlayer(player) then
		return
	end

	local success, errorMessage = pcall(function()
		updateUI:Fire(false, { Viewer = player }, true)
	end)

	if not success then
		warnlog("Failed to refresh UI for player %s (UserId: %d): %s", player.Name, player.UserId, tostring(errorMessage))
	end
end

local function updatePlayerStatisticDisplay(targetPlayer: Player, statisticName: string, updatedValue: number): ()
	local leaderboardFolder = LeaderboardBuilder.getLeaderstatsFolder(targetPlayer)
	if not leaderboardFolder then
		warnlog("No leaderboard display found for player %s (UserId: %d)", targetPlayer.Name, targetPlayer.UserId)
		return
	end

	local statisticObject = LeaderboardBuilder.getStatisticObject(leaderboardFolder, statisticName)
	if not statisticObject then
		warnlog("Statistic %s not found for player %s (UserId: %d)", statisticName, targetPlayer.Name, targetPlayer.UserId)
		return
	end

	if statisticObject.Value == updatedValue then
		return
	end

	statisticObject.Value = updatedValue

	if statisticName == UI_UPDATE_STATISTIC then
		triggerUIRefresh(targetPlayer)
	end
end

------------------------------
-- Cross-Server Update Handling --
------------------------------
local function processLeaderboardUpdate(crossServerMessage: any): ()
	if isShuttingDown then
		return
	end

	local updateData = CrossServerSync.extractUpdate(crossServerMessage)
	if not updateData then
		warnlog("Invalid leaderboard update message received")
		return
	end

	PlayerData:UpdatePlayerStatisticAndPublishChanges(
		updateData.UserId,
		updateData.Stat,
		updateData.Value,
		true,
		true
	)

	local targetPlayer = Players:GetPlayerByUserId(updateData.UserId)
	if targetPlayer and ValidationUtils.isValidPlayer(targetPlayer) then
		updatePlayerStatisticDisplay(targetPlayer, updateData.Stat, updateData.Value)
	end
end

---------------------------
-- Player Data Load Flow --
---------------------------
local function loadPlayerGamepassData(player: Player): ()
	GamepassCacheManager.LoadPlayerGamepassDataIntoCache(player)
end

local function loadPlayerStatisticsData(playerUserId: number): ()
	PlayerData:GetOrCreatePlayerStatisticsData(playerUserId)
end

local function createPlayerLeaderboard(player: Player): ()
	local leaderboardCreated = LeaderboardBuilder.createLeaderboard(player)

	if not leaderboardCreated then
		error("Player leaderboard display creation failed")
	end
end

local function handleFailedInit(player: Player, errorMessage: string): ()
	warnlog("Error initializing player data systems for %s (UserId: %d): %s", player.Name, player.UserId, tostring(errorMessage))

	if ValidationUtils.isValidPlayer(player) then
		safeKick(player, KICK_MESSAGES.DATA_LOAD_FAILED)
	end
end

local function handleInitTimeout(initState: any): ()
	if isShuttingDown or not ValidationUtils.isValidPlayer(initState.player) then
		return
	end

	warnlog("Player initialization timed out for %s (UserId: %d)", initState.player.Name, initState.player.UserId)
	safeKick(initState.player, KICK_MESSAGES.INIT_TIMEOUT)
end

local function initializePlayerDataSystems(connectingPlayer: Player): ()
	if not ValidationUtils.isValidPlayer(connectingPlayer) or isShuttingDown then
		return
	end

	local initState = initTracker:createWithTimeout(connectingPlayer, PLAYER_INIT_TIMEOUT, handleInitTimeout)

	local success, errorMessage = pcall(function()
		loadPlayerGamepassData(connectingPlayer)
		loadPlayerStatisticsData(connectingPlayer.UserId)
		createPlayerLeaderboard(connectingPlayer)
	end)

	initTracker:complete(initState, success, errorMessage)

	if success then
		dataLoaded:FireClient(connectingPlayer)
	else
		handleFailedInit(connectingPlayer, tostring(errorMessage))
	end

	initTracker:scheduleCleanup(connectingPlayer.UserId, INIT_STATE_CLEANUP_DELAY)
end

-------------------------
-- Player Connections  --
-------------------------
local function handlePlayerConnection(connectingPlayer: Player): ()
	if isShuttingDown then
		return
	end
	task.spawn(function()
		initializePlayerDataSystems(connectingPlayer)
	end)
end

local function cleanupPlayerData(player: Player): ()
	local success, errorMessage = pcall(function()
		PlayerData:RemovePlayerDataFromCacheAndSave(player.UserId)
		GamepassCacheManager.UnloadPlayerDataFromCache(player)
	end)
	if not success then
		warnlog("Error cleaning up player data cache for %s (UserId: %d): %s", player.Name, player.UserId, tostring(errorMessage))
	end
end

local function handlePlayerDisconnection(disconnectingPlayer: Player): ()
	cleanupPlayerData(disconnectingPlayer)
end

local function initializeExistingPlayers(): ()
	for _, existingPlayer in Players:GetPlayers() do
		task.spawn(handlePlayerConnection, existingPlayer)
	end
end

local function saveAllPlayerData(): ()
	for _, player in Players:GetPlayers() do
		pcall(function()
			PlayerData:RemovePlayerDataFromCacheAndSave(player.UserId)
			GamepassCacheManager.UnloadPlayerDataFromCache(player)
		end)
	end
end

local function cleanupAllResources(): ()
	resourceManager:cleanupAll()
	crossServerSync:disconnect()
end

--------------------
-- Initialization --
--------------------
if not initializeDataStoreRegistry() then
	error("Failed to initialize DataStore registry - cannot continue")
end

resourceManager:trackConnection(Players.PlayerAdded:Connect(handlePlayerConnection))
resourceManager:trackConnection(Players.PlayerRemoving:Connect(handlePlayerDisconnection))

initializeExistingPlayers()

-- Subscribe to cross-server leaderboard updates
crossServerSync:subscribe(
	GameConfig.MESSAGING_SERVICE_CONFIG.LEADERBOARD_UPDATE,
	processLeaderboardUpdate
)

-------------
-- Cleanup --
-------------
game:BindToClose(function()
	isShuttingDown = true

	cleanupAllResources()
	saveAllPlayerData()
end)

log("Initialized successfully")