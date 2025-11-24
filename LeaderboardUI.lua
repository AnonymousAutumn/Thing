--!strict

--[[
	LeaderboardUI - Main leaderboard system controller

	This module manages client-side leaderboard displays:
	- Initializes multiple leaderboard instances
	- Coordinates state management, UI, and updates
	- Handles retry logic for failed initializations
	- Manages cleanup on player/script removal

	Returns: Nothing (initializes and runs automatically)

	Usage: This script runs automatically when parented to the player's UI.
	Automatically discovers and initializes all SurfaceGui leaderboards.
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------
-- Constants --
--------------
local TAG = "[LeaderboardUI]"
local WAIT_TIMEOUT = 10
local MAX_INIT_RETRIES = 3
local INIT_RETRY_DELAY = 2

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), TAG .. " Modules folder not found")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local leaderboardDisplayHandler = require(assert(script:WaitForChild("RigCreator", WAIT_TIMEOUT), TAG .. " RigCreator not found"))

local currentLeaderboardScript = script.Parent
local localPlayer = Players.LocalPlayer
assert(localPlayer, TAG .. " LocalPlayer not found")

-- Submodules
local StateManager = require(assert(script:WaitForChild("StateManager", WAIT_TIMEOUT), TAG .. " StateManager not found"))
local ComponentFinder = require(assert(script:WaitForChild("ComponentFinder", WAIT_TIMEOUT), TAG .. " ComponentFinder not found"))
local UIController = require(assert(script:WaitForChild("UIController", WAIT_TIMEOUT), TAG .. " UIController not found"))
local UpdateHandler = require(assert(script:WaitForChild("UpdateHandler", WAIT_TIMEOUT), TAG .. " UpdateHandler not found"))

-----------
-- Types --
-----------
export type LeaderboardHandler = StateManager.LeaderboardHandler
export type LeaderboardState = StateManager.LeaderboardState
export type WorkspaceComponents = ComponentFinder.WorkspaceComponents

---------------
-- Variables --
---------------
local globalResourceManager = ResourceCleanup.new()

---------------
-- Utilities --
---------------
local function safeExecute(func: () -> ()): boolean
	local success, errorMessage = pcall(func)
	if not success then
		warn("Error in safeExecute:", errorMessage)
	end
	return success
end

------------------------
-- Initialization Logic --
------------------------
local function performLeaderboardInitialization(leaderboardSurfaceGui: SurfaceGui, state: LeaderboardState): boolean
	assert(leaderboardSurfaceGui, "performLeaderboardInitialization: leaderboardSurfaceGui is required")
	assert(state, "performLeaderboardInitialization: state is required")

	local leaderboardName = leaderboardSurfaceGui.Name

	-- Create handler
	local clientLeaderboardHandler = leaderboardDisplayHandler.new(leaderboardSurfaceGui)
	if not clientLeaderboardHandler then
		warn(TAG .. " Failed to create handler for " .. leaderboardName)
		return false
	end
	state.handler = clientLeaderboardHandler

	-- Get workspace components
	local workspaceComponents = ComponentFinder.getWorkspaceComponents(leaderboardName)
	if not workspaceComponents then
		warn(TAG .. " Failed to get workspace components for " .. leaderboardName)
		return false
	end

	-- Get update remote event
	local leaderboardUpdateRemoteEvent = ComponentFinder.getUpdateRemoteEvent(leaderboardName)
	if not leaderboardUpdateRemoteEvent then
		warn(TAG .. " Failed to get update remote event for " .. leaderboardName)
		return false
	end

	-- Setup toggle functionality
	if not UIController.setupToggle(
		workspaceComponents.toggleButton,
		workspaceComponents.scrollingFrame,
		clientLeaderboardHandler,
		state
		) then
		warn(TAG .. " Failed to setup toggle for " .. leaderboardName)
		return false
	end

	-- Setup update handling
	if not UpdateHandler.setupUpdates(
		leaderboardUpdateRemoteEvent,
		clientLeaderboardHandler,
		state,
		StateManager.updateState
		) then
		warn(TAG .. " Failed to setup updates for " .. leaderboardName)
		return false
	end

	return true
end

local function initializeLeaderboardInterface(leaderboardSurfaceGui: SurfaceGui): boolean
	if not leaderboardSurfaceGui then
		return false
	end

	local leaderboardName = leaderboardSurfaceGui.Name
	local state = StateManager.initializeState(leaderboardName)

	-- Already initialized
	if state.isInitialized then
		return true
	end

	-- Retry initialization with exponential backoff
	for attempt = 1, MAX_INIT_RETRIES do
		local success = pcall(function()
			performLeaderboardInitialization(leaderboardSurfaceGui, state)
		end)

		if success then
			state.isInitialized = true
			return true
		end

		if attempt < MAX_INIT_RETRIES then
			task.wait(INIT_RETRY_DELAY * attempt)
		end
	end

	-- Cleanup failed initialization
	StateManager.cleanup(leaderboardName)
	return false
end

local function initializeAllLeaderboards(): ()
	for i, leaderboardInstance in currentLeaderboardScript:GetChildren() do
		if leaderboardInstance:IsA("SurfaceGui") then
			safeExecute(function()
				initializeLeaderboardInterface(leaderboardInstance)
			end)
		end
	end
end

local function cleanup(): ()
	StateManager.cleanupAll()
	globalResourceManager:cleanupAll()
end

--------------------
-- Initialization --
--------------------
initializeAllLeaderboards()

-- Cleanup on player/script removal
globalResourceManager:trackConnection(
	localPlayer.AncestryChanged:Connect(function()
		if not localPlayer:IsDescendantOf(game) then
			cleanup()
		end
	end)
)

globalResourceManager:trackConnection(
	script.AncestryChanged:Connect(function()
		if not script:IsDescendantOf(game) then
			cleanup()
		end
	end)
)