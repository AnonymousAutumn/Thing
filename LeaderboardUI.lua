--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----------------
-- References --
----------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local leaderboardDisplayHandler = require(script.RigCreator)

local currentLeaderboardScript = script.Parent
local localPlayer = Players.LocalPlayer

-- Submodules
local StateManager = require(script.StateManager)
local ComponentFinder = require(script.ComponentFinder)
local UIController = require(script.UIController)
local UpdateHandler = require(script.UpdateHandler)

-----------
-- Types --
-----------
export type LeaderboardHandler = StateManager.LeaderboardHandler
export type LeaderboardState = StateManager.LeaderboardState
export type WorkspaceComponents = ComponentFinder.WorkspaceComponents

--------------
-- Constants --
--------------
local MAX_INIT_RETRIES = 3
local INIT_RETRY_DELAY = 2

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
	local leaderboardName = leaderboardSurfaceGui.Name

	-- Create handler
	local clientLeaderboardHandler = leaderboardDisplayHandler.new(leaderboardSurfaceGui)
	if not clientLeaderboardHandler then
		warn("Failed to create handler for", leaderboardName)
		return false
	end
	state.handler = clientLeaderboardHandler

	-- Get workspace components
	local workspaceComponents = ComponentFinder.getWorkspaceComponents(leaderboardName)
	if not workspaceComponents then
		warn("Failed to get workspace components for", leaderboardName)
		return false
	end

	-- Get update remote event
	local leaderboardUpdateRemoteEvent = ComponentFinder.getUpdateRemoteEvent(leaderboardName)
	if not leaderboardUpdateRemoteEvent then
		warn("Failed to get update remote event for", leaderboardName)
		return false
	end

	-- Setup toggle functionality
	if not UIController.setupToggle(
		workspaceComponents.toggleButton,
		workspaceComponents.scrollingFrame,
		clientLeaderboardHandler,
		state
		) then
		warn("Failed to setup toggle for", leaderboardName)
		return false
	end

	-- Setup update handling
	if not UpdateHandler.setupUpdates(
		leaderboardUpdateRemoteEvent,
		clientLeaderboardHandler,
		state,
		StateManager.updateState
		) then
		warn("Failed to setup updates for", leaderboardName)
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