--!strict

--[[
	ZoneDetector Module

	Monitors player position relative to combat zone and manages entry/exit.
	Returns a table with startMonitoring method.

	Usage:
		ZoneDetector.startMonitoring(player, zonePart, isInPartFunc, giveToolFunc, removeToolFunc)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

----------------
-- References --
----------------
local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Network folder not found")
local remotes = assert(network:WaitForChild("Remotes", 10), "Remotes folder not found")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Events folder not found")
local updateGameUIEvent = assert(remoteEvents:WaitForChild("UpdateGameUI", 10), "UpdateGameUI event not found")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

---------------
-- Constants --
---------------
local FIGHTING_ATTRIBUTE_NAME = "Fighting"
local ZONE_UPDATE_INTERVAL = 0.2 -- 5 times per second

local COMBAT_MESSAGES = {
	Enter = "Entered combat",
	Exit = "Left combat",
}

local LOG_PREFIX = "[ZoneDetector]"

-----------
-- Module --
-----------
local ZoneDetector = {}

---------------------------
-- Zone Entry/Exit Handlers
---------------------------
local function handleCombatZoneEntry(
	targetPlayer: Player,
	giveToolFunc: (Player) -> ()
): ()
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		return
	end
	local char = targetPlayer.Character
	if not char then
		return
	end
	local success, errorMessage = pcall(function()
		giveToolFunc(targetPlayer)
		updateGameUIEvent:FireClient(targetPlayer, COMBAT_MESSAGES.Enter, nil, true) -- hide exit button
		char:SetAttribute(FIGHTING_ATTRIBUTE_NAME, true)
	end)
	if not success then
		warn(
			string.format(
				"%s Failed to handle zone entry for %s: %s",
				LOG_PREFIX,
				targetPlayer.Name,
				errorMessage
			)
		)
	end
end

local function handleCombatZoneExit(
	targetPlayer: Player,
	removeToolFunc: (Player) -> ()
): ()
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		return
	end
	local char = targetPlayer.Character
	if not char then
		return
	end
	local success, errorMessage = pcall(function()
		removeToolFunc(targetPlayer)
		updateGameUIEvent:FireClient(targetPlayer, COMBAT_MESSAGES.Exit, nil, true) -- hide exit button
		char:SetAttribute(FIGHTING_ATTRIBUTE_NAME, false)
	end)
	if not success then
		warn(
			string.format(
				"%s Failed to handle zone exit for %s: %s",
				LOG_PREFIX,
				targetPlayer.Name,
				errorMessage
			)
		)
	end
end

------------------
-- Public API --
------------------
function ZoneDetector.startMonitoring(
	player: Player,
	combatZonePart: BasePart,
	isPlayerInPartFunc: (Player, BasePart) -> boolean,
	giveToolFunc: (Player) -> (),
	removeToolFunc: (Player) -> ()
): ()
	local lastZoneUpdate = 0
	local wasPlayerInZone = false

	local function updatePlayerZoneStatus(): ()
		local isInZone = isPlayerInPartFunc(player, combatZonePart)

		-- Detect a *change* in state
		if isInZone and not wasPlayerInZone then
			-- Player just entered
			handleCombatZoneEntry(player, giveToolFunc)
		elseif not isInZone and wasPlayerInZone then
			-- Player just exited
			handleCombatZoneExit(player, removeToolFunc)
		end

		-- Update stored state
		wasPlayerInZone = isInZone
	end

	local function onHeartbeat(deltaTime: number): ()
		-- Throttle: only check zone every ZONE_UPDATE_INTERVAL seconds
		local elapsed = os.clock() - lastZoneUpdate
		if elapsed < ZONE_UPDATE_INTERVAL then
			return
		end

		lastZoneUpdate = os.clock()
		updatePlayerZoneStatus()
	end

	RunService.Heartbeat:Connect(onHeartbeat)
end

return ZoneDetector