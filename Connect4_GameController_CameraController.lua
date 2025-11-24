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
local connect4Remotes = remotes:WaitForChild("Connect4")

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