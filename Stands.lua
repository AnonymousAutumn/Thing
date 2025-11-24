--!strict

--[[
	Stands Utility Module

	Provides utility functions for stand management and refresh operations.
	Handles stand UI updates and player-to-stand mappings.

	Returns: StandUtils table with utility functions

	Usage:
		local StandUtils = require(...)
		StandUtils.SetPlayerToStandTable(playerToStandMap)
		StandUtils.RefreshStandForPlayer(player)
]]

local StandUtils = {}

-----------
-- Types --
-----------
type StandObject = {
	Stand: Model,
	[any]: any,
}

type StandObjects = { [Model]: StandObject }

type ClaimedStandData = {
	gamepasses: { any }?,
}

type ClaimedStands = { [Model]: ClaimedStandData }

type PlayerToStandMap = { [string]: StandObject }

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local network = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network in ReplicatedStorage")
local remotes = assert(network:WaitForChild("Remotes", 10), "Failed to find Remotes folder")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Failed to find Events folder")

local refreshStand = assert(remoteEvents:WaitForChild("RefreshStand", 10), "Failed to find RefreshStand event")

local modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules in ReplicatedStorage")
local GamepassCacheManager = require(assert(modules:WaitForChild("Caches", 10):WaitForChild("PassCache", 10), "Failed to find PassCache"))

---------------
-- Variables --
---------------

local PlayerToStand: PlayerToStandMap = {} -- [player.Name] = StandModule

----------------------
-- Private Functions --
----------------------

-- Fetches cached gamepass data for a player, returning empty table as fallback
local function getPlayerGamepasses(player: Player): { any }
	local playerPassData = GamepassCacheManager.GetPlayerCachedGamepassData(player)
	return playerPassData and playerPassData.gamepasses or {}
end

--------------------
-- Public Functions
--------------------

-- Allow main server script to provide PlayerToStand mapping
function StandUtils.SetPlayerToStandTable(tbl: PlayerToStandMap): ()
	PlayerToStand = tbl
end

-- Refresh a specific player's stand UI with their current gamepasses
function StandUtils.RefreshStandForPlayer(player: Player): ()
	local standObject = PlayerToStand[player.Name]
	if not standObject then
		return
	end

	local playerGamepasses = getPlayerGamepasses(player)
	refreshStand:FireClient(player, standObject.Stand, playerGamepasses, false)
end

-- Refresh all stands for a player (used when player joins late)
function StandUtils.RefreshAllStandsForPlayer(player: Player, StandObjects: StandObjects, ClaimedStands: ClaimedStands): ()
	for standModel, standObject in pairs(StandObjects) do
		local claimedData = ClaimedStands[standModel]
		local gamepasses = claimedData and claimedData.gamepasses or {}
		local isUnclaimed = not claimedData
		refreshStand:FireClient(player, standModel, gamepasses, isUnclaimed)
	end
end

-- Broadcast stand refresh to all clients (used when ownership changes)
function StandUtils.BroadcastStandRefresh(player: Player): ()
	local standObject = PlayerToStand[player.Name]
	if not standObject then
		return
	end

	local playerGamepasses = getPlayerGamepasses(player)
	refreshStand:FireAllClients(standObject.Stand, playerGamepasses, false)
end

--------------
-- Return --
--------------
return StandUtils