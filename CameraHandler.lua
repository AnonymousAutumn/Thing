--!strict

--------------
-- Services --
--------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local network : Folder = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local connect4RemoteEvents = remotes:WaitForChild("Connect4")
local updateCameraEvent = connect4RemoteEvents:WaitForChild("UpdateCamera")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local TweenHelper = require(Modules.Utilities.TweenHelper)

---------------
-- Constants --
---------------

local CAMERA_TWEEN_DURATION = 0.6
local CAMERA_TWEEN_INFO = TweenInfo.new(
	CAMERA_TWEEN_DURATION,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)

---------------
-- Variables --
---------------

local resourceManager = ResourceCleanup.new()
local savedCameraType: Enum.CameraType? = nil
local savedCameraFrame: CFrame? = nil
local currentCameraTween: Tween? = nil

---------------
-- Functions --
---------------

local function restoreOriginalCamera(): ()
	-- Cancel any active camera tween to prevent conflicts
	if currentCameraTween then
		currentCameraTween:Cancel()
		currentCameraTween = nil
	end

	-- Restore camera state if previously saved
	if savedCameraType and savedCameraFrame then
		camera.CameraType = savedCameraType
		camera.CFrame = savedCameraFrame
		savedCameraType = nil
		savedCameraFrame = nil
	end
end

local function focusOnGameBoard(boardCameraFrame: CFrame): ()
	-- Store original camera state on first focus
	if not savedCameraType then
		savedCameraType = camera.CameraType
		savedCameraFrame = camera.CFrame
	end

	-- Cancel previous tween if still playing
	if currentCameraTween then
		currentCameraTween:Cancel()
	end

	-- Set camera to scriptable mode and transition to board
	camera.CameraType = Enum.CameraType.Scriptable
	currentCameraTween = TweenHelper.play(camera, CAMERA_TWEEN_INFO, {
		CFrame = boardCameraFrame
	})
end

local function onCameraUpdateRequested(isPlayerTurn: boolean, boardCameraFrame: CFrame?): ()
	if isPlayerTurn and boardCameraFrame then
		focusOnGameBoard(boardCameraFrame)
	else
		restoreOriginalCamera()
	end
end

------------
-- Events --
------------

resourceManager:trackConnection(updateCameraEvent.OnClientEvent:Connect(onCameraUpdateRequested))
resourceManager:trackConnection(localPlayer.CharacterAdded:Connect(restoreOriginalCamera))

-- Cleanup on script removal
resourceManager:trackConnection(script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(game) then
		restoreOriginalCamera()
		resourceManager:cleanupAll()
	end
end))