--!strict

--[[
	EliminationHandler Module

	Manages player elimination logic including killer detection and win recording.
	Returns a table with handlePlayerElimination and getKillerFromHumanoid methods.

	Usage:
		EliminationHandler.handlePlayerElimination(victim, killer, recordWinCallback)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Network folder not found")
local remotes = assert(network:WaitForChild("Remotes", 10), "Remotes folder not found")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Events folder not found")
local updateGameUIEvent = assert(remoteEvents:WaitForChild("UpdateGameUI", 10), "UpdateGameUI event not found")
local playSoundEvent = assert(remoteEvents:WaitForChild("PlaySound", 10), "PlaySound event not found")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

---------------
-- Constants --
---------------
local BLOXXED_MESSAGE_FORMAT = "Bloxxed %s!"
local KILL_CREDIT = 1
local LOG_PREFIX = "[EliminationHandler]"

-----------
-- Module --
-----------
local EliminationHandler = {}

-----------------
-- Utilities
-----------------
local function getKillerFromCreatorTag(hum: Humanoid): Player?
	local creatorTag = hum:FindFirstChild("creator")
	if not creatorTag or not creatorTag:IsA("ObjectValue") then
		return nil
	end
	local creatorValue = (creatorTag :: ObjectValue).Value
	return if creatorValue and creatorValue:IsA("Player") then creatorValue else nil
end

local function playSound(targetPlayer: Player, soundEnabled: boolean): ()
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		return
	end
	local success, errorMessage = pcall(function()
		playSoundEvent:FireClient(targetPlayer, soundEnabled)
	end)
	if not success then
		warn(
			string.format(
				"%s Failed to play sound for player %s: %s",
				LOG_PREFIX,
				targetPlayer.Name,
				errorMessage
			)
		)
	end
end

local function notifyKillerOfElimination(killer: Player, victimName: string): ()
	if not ValidationUtils.isValidPlayer(killer) then
		return
	end
	local message = string.format(BLOXXED_MESSAGE_FORMAT, victimName)
	local success, errorMessage = pcall(function()
		updateGameUIEvent:FireClient(killer, message, nil, true) -- always hide exit button
	end)
	if not success then
		warn(string.format("%s Failed to notify killer %s: %s", LOG_PREFIX, killer.Name, errorMessage))
	end
	playSound(killer, false)
end

local function handleEliminationWithKiller(victim: Player, killer: Player, recordWinFunc: (number, number) -> ()): ()
	if not ValidationUtils.isValidPlayer(victim) or not ValidationUtils.isValidPlayer(killer) then
		return
	end
	recordWinFunc(killer.UserId, KILL_CREDIT)
	notifyKillerOfElimination(killer, victim.Name)
end

------------------
-- Public API --
------------------
function EliminationHandler.getKillerFromHumanoid(hum: Humanoid): Player?
	return getKillerFromCreatorTag(hum)
end

function EliminationHandler.handlePlayerElimination(
	victim: Player,
	killer: Player?,
	recordWinFunc: (number, number) -> ()
): ()
	if not ValidationUtils.isValidPlayer(victim) then
		return
	end
	playSound(victim, true)
	if killer and ValidationUtils.isValidPlayer(killer) then
		handleEliminationWithKiller(victim, killer, recordWinFunc)
	end
end

return EliminationHandler