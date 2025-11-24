--!strict

--[[
	DataPersistence Module

	Handles persistence of combat win data to DataStores and PlayerData system.
	Returns a table with recordPlayerWin method.

	Usage:
		DataPersistence.recordPlayerWin(userId, winCount)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Configuration folder not found")

local PlayerData = require(Modules.Managers.PlayerData)
local DataStoreWrapper = require(Modules.Wrappers.DataStore)
local GameConfig = require(Configuration.GameConfig)

---------------
-- Constants --
---------------
local WINS_STAT_KEY = "Wins"
local LOG_PREFIX = "[DataPersistence]"

local playerWinsDataStore = DataStoreService:GetOrderedDataStore(GameConfig.DATASTORE.WINS_ORDERED_KEY)

-----------
-- Module --
-----------
local DataPersistence = {}

---------------------
-- Data Operations
---------------------
local function updateDataStore(playerId: number, dataStore: OrderedDataStore, increment: number): number
	local config = { maxRetries = 3, baseDelay = 1 }
	local success, incrementedValue = DataStoreWrapper.incrementAsync(
		dataStore,
		tostring(playerId),
		increment,
		config
	)
	if not success then
		local errorMessage = incrementedValue :: any
		warn(
			string.format(
				"%s Failed to update datastore for player %d: %s",
				LOG_PREFIX,
				playerId,
				errorMessage
			)
		)
		return 0
	end
	return incrementedValue or 0
end

------------------
-- Public API --
------------------
function DataPersistence.recordPlayerWin(playerUserId: number, wins: number): ()
	updateDataStore(playerUserId, playerWinsDataStore, wins)
	local success, errorMessage = pcall(function()
		PlayerData:IncrementPlayerStatistic(playerUserId, WINS_STAT_KEY, wins)
	end)
	if not success then
		warn(
			string.format(
				"%s Failed to update player statistics for %d: %s",
				LOG_PREFIX,
				playerUserId,
				errorMessage
			)
		)
	end
end

return DataPersistence