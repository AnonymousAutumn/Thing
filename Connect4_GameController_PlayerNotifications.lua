--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network: Folder = ReplicatedStorage:WaitForChild("Network") :: Folder
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")

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
	PlayerNotifications.sendToPlayer(player, "", nil, false)
end

--[[
	Clears UI for all players

	@param players {Player} - Array of target players
]]
function PlayerNotifications.clearAllUI(players: { Player }): ()
	for _, player in players do
		PlayerNotifications.clearUI(player)
	end
end

return PlayerNotifications