--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----------------
-- References --
----------------
local network = ReplicatedStorage:WaitForChild("Network")
local bindables = network:WaitForChild("Bindables")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")
local connect4Bindables = bindables:WaitForChild("Connect4")
local connect4Remotes = remotes:WaitForChild("Connect4")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local InputCategorizer = require(Modules.Utilities.InputCategorizer)

-- Submodules
local GameStateManager = require(script.GameStateManager)
local StatusAnimator = require(script.StatusAnimator)
local TimeoutManager = require(script.TimeoutManager)
local UpdateCoordinator = require(script.UpdateCoordinator)

local gameStatusInterface = script.Parent:WaitForChild("MainFrame") :: Frame
local statusHolder = gameStatusInterface:WaitForChild("BarFrame") :: Frame
local statusLabel = statusHolder:WaitForChild("TextLabel") :: TextLabel
local exitButton = gameStatusInterface:WaitForChild("ExitButton") :: GuiButton

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