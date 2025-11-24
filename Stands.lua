--!strict

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

local network = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")

local refreshStand = remoteEvents:WaitForChild("RefreshStand")

local modules = ReplicatedStorage:WaitForChild("Modules")
local GamepassCacheManager = require(modules.Caches.PassCache)

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