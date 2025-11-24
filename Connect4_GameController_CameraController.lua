--!strict

--[[
	CameraController Module

	Manages camera updates for Connect4 players during gameplay.
	Returns a table with camera control methods.

	Usage:
		CameraController.updatePlayerCamera(player, true, cameraCFrame)
		CameraController.resetAllCameras(players)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Network folder not found") :: Folder
local remotes = assert(network:WaitForChild("Remotes", 10), "Remotes folder not found")
local connect4Remotes = assert(remotes:WaitForChild("Connect4", 10), "Connect4 remotes not found")

-----------
-- Module --
-----------
local CameraController = {}

--[[
	Updates camera for a player based on turn state

	@param player Player - Target player
	@param isPlayerTurn boolean - Whether it's this player's turn
	@param cameraCFrame CFrame? - Optional camera position/orientation
]]
function CameraController.updatePlayerCamera(player: Player, isPlayerTurn: boolean, cameraCFrame: CFrame?): ()
	if cameraCFrame then
		connect4Remotes.UpdateCamera:FireClient(player, isPlayerTurn, cameraCFrame)
	end
end

--[[
	Resets camera for a player (returns to normal)

	@param player Player - Target player
]]
function CameraController.resetPlayerCamera(player: Player): ()
	connect4Remotes.UpdateCamera:FireClient(player, false)
end

--[[
	Resets cameras for all players

	@param players {Player} - Array of players
]]
function CameraController.resetAllCameras(players: { Player }): ()
	for _, player in players do
		CameraController.resetPlayerCamera(player)
	end
end

return CameraController