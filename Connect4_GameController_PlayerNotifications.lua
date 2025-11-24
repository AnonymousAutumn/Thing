--!strict

--[[
	Connect4_GameController_PlayerNotifications

	Handles sending UI update notifications to players via RemoteEvents.
	Provides utilities for notifying single players, multiple players, or all players except one.

	Returns: Table with notification functions:
		- sendToPlayer: Send UI update to a single player
		- sendToPlayers: Send UI update to multiple players
		- sendToPlayersExcept: Send to all except one player
		- clearUI: Clear UI for a single player
		- clearAllUI: Clear UI for all players

	Usage:
		local PlayerNotifications = require(script.Connect4_GameController_PlayerNotifications)
		PlayerNotifications.sendToPlayer(player, "Your turn!", 30, true)
		PlayerNotifications.clearUI(player)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Network folder not found in ReplicatedStorage") :: Folder
local remotes = assert(network:WaitForChild("Remotes", 10), "Remotes folder not found in Network")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Events folder not found in Remotes")

-----------
-- Module --
-----------
local PlayerNotifications = {}

--[[
	Sends a UI update to a single player

	@param player Player - Target player
	@param message string - Message to display
	@param timeout number? - Optional timeout duration
	@param exitButtonVisible boolean? - Whether to show exit button (default: false)
]]
function PlayerNotifications.sendToPlayer(
	player: Player,
	message: string,
	timeout: number?,
	exitButtonVisible: boolean?
): ()
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player must be a Player instance")
	assert(typeof(message) == "string", "message must be a string")

	local hideExitButton = not (exitButtonVisible or false)
	remoteEvents.UpdateGameUI:FireClient(player, message, timeout, hideExitButton)
end

--[[
	Sends a UI update to multiple players

	@param players {Player} - Array of target players
	@param message string - Message to display
	@param timeout number? - Optional timeout duration
	@param exitButtonVisible boolean? - Whether to show exit button
]]
function PlayerNotifications.sendToPlayers(
	players: { Player },
	message: string,
	timeout: number?,
	exitButtonVisible: boolean?
): ()
	assert(typeof(players) == "table", "players must be a table")
	assert(typeof(message) == "string", "message must be a string")

	for _, player in players do
		PlayerNotifications.sendToPlayer(player, message, timeout, exitButtonVisible)
	end
end

--[[
	Sends a UI update to all players except one

	@param players {Player} - Array of all players
	@param message string - Message to display
	@param excludePlayer Player? - Player to exclude from notification
]]
function PlayerNotifications.sendToPlayersExcept(
	players: { Player },
	message: string,
	excludePlayer: Player?
): ()
	assert(typeof(players) == "table", "players must be a table")
	assert(typeof(message) == "string", "message must be a string")

	for _, player in players do
		if player ~= excludePlayer then
			PlayerNotifications.sendToPlayer(player, message, nil, false)
		end
	end
end

--[[
	Clears UI for a single player

	@param player Player - Target player
]]
function PlayerNotifications.clearUI(player: Player): ()
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player must be a Player instance")
	PlayerNotifications.sendToPlayer(player, "", nil, false)
end

--[[
	Clears UI for all players

	@param players {Player} - Array of target players
]]
function PlayerNotifications.clearAllUI(players: { Player }): ()
	assert(typeof(players) == "table", "players must be a table")

	for _, player in players do
		PlayerNotifications.clearUI(player)
	end
end

return PlayerNotifications