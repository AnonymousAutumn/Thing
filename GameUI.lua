--!strict

--[[
	GameUI

	Main client-side UI controller for Connect4 game status display.
	Manages status animations, timeouts, player exits, and cleanup lifecycle.

	Returns: Module initializes automatically and manages:
		- Game status interface with animations
		- Turn timeout countdown display
		- Exit button handling
		- Camera reset on cleanup
		- Resource tracking and cleanup on player leave

	Usage:
		Placed in ScreenGui, automatically initializes when player joins game.
		Listens for RemoteEvents to update UI state.
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----------------
-- References --
----------------
local network = assert(ReplicatedStorage:WaitForChild("Network", 10), "Network folder not found in ReplicatedStorage")
local bindables = assert(network:WaitForChild("Bindables", 10), "Bindables folder not found in Network")
local remotes = assert(network:WaitForChild("Remotes", 10), "Remotes folder not found in Network")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Events folder not found in Remotes")
local connect4Bindables = assert(bindables:WaitForChild("Connect4", 10), "Connect4 folder not found in Bindables")
local connect4Remotes = assert(remotes:WaitForChild("Connect4", 10), "Connect4 folder not found in Remotes")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local InputCategorizer = require(Modules.Utilities.InputCategorizer)

-- Submodules
local GameStateManager = require(script.GameStateManager)
local StatusAnimator = require(script.StatusAnimator)
local TimeoutManager = require(script.TimeoutManager)
local UpdateCoordinator = require(script.UpdateCoordinator)

local gameStatusInterface = assert(script.Parent:WaitForChild("MainFrame", 10), "MainFrame not found in GameUI parent") :: Frame
local statusHolder = assert(gameStatusInterface:WaitForChild("BarFrame", 10), "BarFrame not found in MainFrame") :: Frame
local statusLabel = assert(statusHolder:WaitForChild("TextLabel", 10), "TextLabel not found in BarFrame") :: TextLabel
local exitButton = assert(gameStatusInterface:WaitForChild("ExitButton", 10), "ExitButton not found in MainFrame") :: GuiButton

local localPlayer = Players.LocalPlayer
local isMobileDevice = InputCategorizer.getLastInputCategory() == "Touch"

---------------
-- Constants --
---------------
local CONFIG = {
	STATUS_MESSAGE_DISPLAY_DURATION = 3,
}

local MESSAGE_PLAYER_LEFT = "left the game"

-------------
-- Setup --
-------------
-- Wire up StatusAnimator dependencies
StatusAnimator.statusLabel = statusLabel
StatusAnimator.statusHolder = statusHolder
StatusAnimator.exitButton = exitButton
StatusAnimator.isMobileDevice = isMobileDevice

--[[
	Safe execution helper

	@param func () -> () - Function to execute
	@param errorMessage string - Error message to warn
	@return boolean - True if successful
]]
local function safeExecute(func: () -> (), errorMessage: string): boolean
	local success, errorDetails = pcall(func)
	if not success then
		warn(errorMessage, errorDetails)
	end
	return success
end

--------------------
-- Player Exit Logic --
--------------------
local function firePlayerExitedEvent(): ()
	safeExecute(function()
		connect4Remotes.PlayerExited:FireServer()
	end, "Error firing player exited event")
end

local function prepareForPlayerExit(): ()
	TimeoutManager.cancelTimeoutHandler()
	UpdateCoordinator.cancelAutoHideTask()
	StatusAnimator.setExitButtonVisibility(false)
end

local function scheduleExitCleanup(): ()
	local exitTask = task.delay(CONFIG.STATUS_MESSAGE_DISPLAY_DURATION, function()
		StatusAnimator.hideStatusInterface()
		StatusAnimator.updateStatusText(nil)
	end)

	GameStateManager.trackTask(exitTask)
end

local function handlePlayerExit(): ()
	safeExecute(function()
		firePlayerExitedEvent()
		prepareForPlayerExit()
		UpdateCoordinator.displayStatusIfChanged(MESSAGE_PLAYER_LEFT)
		UpdateCoordinator.setIgnoreUpdatesPeriod()
		scheduleExitCleanup()
	end, "Error handling player exit")
end

--------------------
-- Game Cleanup Logic --
--------------------
local function resetCamera(): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Custom

	local character = localPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
			return
		end
		if character.PrimaryPart then
			camera.CameraSubject = character.PrimaryPart
			return
		end
	end

	camera.CameraSubject = character
end

local function handleGameCleanup(): ()
	safeExecute(function()
		resetCamera()
		StatusAnimator.setExitButtonVisibility(false)
	end, "Error handling game cleanup")
end

-------------
-- Cleanup --
-------------
local function cleanup(): ()
	TimeoutManager.cancelTimeoutHandler()
	UpdateCoordinator.cancelAutoHideTask()
	GameStateManager.cancelAllTweens()
	GameStateManager.cancelAllTasks()
	GameStateManager.disconnectAllConnections()
	GameStateManager.resetState()
end

--------------------
-- Initialization --
--------------------
GameStateManager.trackConnection(exitButton.MouseButton1Click:Connect(handlePlayerExit))
GameStateManager.trackConnection(remoteEvents.UpdateGameUI.OnClientEvent:Connect(UpdateCoordinator.handleGameUIUpdate))
GameStateManager.trackConnection(connect4Remotes.Cleanup.OnClientEvent:Connect(handleGameCleanup))

GameStateManager.trackConnection(
	localPlayer.AncestryChanged:Connect(function()
		if not localPlayer:IsDescendantOf(game) then
			cleanup()
		end
	end)
)

GameStateManager.trackConnection(
	script.AncestryChanged:Connect(function()
		if not script:IsDescendantOf(game) then
			cleanup()
		end
	end)
)