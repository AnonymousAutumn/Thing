--!strict

--[[
	LeaderboardUI_ComponentFinder - Locates leaderboard UI components

	This module finds and validates leaderboard components:
	- Locates workspace leaderboard SurfaceGuis
	- Finds ScrollingFrames and ToggleButtons
	- Locates update RemoteEvents for each leaderboard
	- Validates all components exist with proper types

	Returns: ComponentFinder module with component lookup functions

	Usage:
		local components = ComponentFinder.getWorkspaceComponents("LeaderboardName")
		local updateEvent = ComponentFinder.getUpdateRemoteEvent("LeaderboardName")
]]

--------------
-- Services --
--------------
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------
-- Constants --
--------------
local TAG = "[LeaderboardUI_ComponentFinder]"
local WAIT_TIMEOUT = 10
local COMPONENT_WAIT_TIMEOUT = 10
local REMOTE_EVENT_NAME_FORMAT = "Update%s"

----------------
-- References --
----------------
local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", WAIT_TIMEOUT), TAG .. " Network folder not found")
local remotes = assert(network:WaitForChild("Remotes", WAIT_TIMEOUT), TAG .. " Remotes folder not found")
local leaderboardEvents = assert(remotes:WaitForChild("Leaderboards", WAIT_TIMEOUT), TAG .. " Leaderboards folder not found")
local workspaceLeaderboardsContainer = assert(Workspace:WaitForChild("Leaderboards", WAIT_TIMEOUT), TAG .. " Workspace Leaderboards folder not found")

-----------
-- Types --
-----------
export type WorkspaceComponents = {
	scrollingFrame: ScrollingFrame,
	toggleButton: GuiButton,
}

-----------
-- Module --
-----------
local ComponentFinder = {}

---------------
-- Utilities --
---------------
local function waitForChildSafe(parent: Instance, childName: string, timeout: number): Instance?
	local success, child = pcall(function()
		return parent:WaitForChild(childName, timeout)
	end)
	return success and child or nil
end

------------------
-- Public API --
------------------
function ComponentFinder.getWorkspaceComponents(leaderboardName: string): WorkspaceComponents?
	assert(typeof(leaderboardName) == "string", "ComponentFinder.getWorkspaceComponents: leaderboardName must be a string")
	assert(leaderboardName ~= "", "ComponentFinder.getWorkspaceComponents: leaderboardName cannot be empty")

	local workspaceLeaderboard = workspaceLeaderboardsContainer:FindFirstChild(leaderboardName)
	if not workspaceLeaderboard then
		warn(TAG .. " Leaderboard not found in workspace: " .. leaderboardName)
		return nil
	end

	local surfaceGui = waitForChildSafe(workspaceLeaderboard, "SurfaceGui", COMPONENT_WAIT_TIMEOUT)
	if not surfaceGui then
		warn(TAG .. " SurfaceGui not found for: " .. leaderboardName)
		return nil
	end

	local mainFrame = waitForChildSafe(surfaceGui, "MainFrame", COMPONENT_WAIT_TIMEOUT)
	if not mainFrame then
		warn(TAG .. " MainFrame not found for: " .. leaderboardName)
		return nil
	end

	local scrollingFrame = waitForChildSafe(mainFrame, "ScrollingFrame", COMPONENT_WAIT_TIMEOUT)
	local toggleButton = waitForChildSafe(mainFrame, "ToggleButton", COMPONENT_WAIT_TIMEOUT)

	if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
		warn(TAG .. " ScrollingFrame not found or invalid for: " .. leaderboardName)
		return nil
	end
	if not toggleButton or not toggleButton:IsA("GuiButton") then
		warn(TAG .. " ToggleButton not found or invalid for: " .. leaderboardName)
		return nil
	end

	return {
		scrollingFrame = scrollingFrame :: ScrollingFrame,
		toggleButton = toggleButton :: GuiButton,
	}
end

function ComponentFinder.getUpdateRemoteEvent(leaderboardName: string): RemoteEvent?
	assert(typeof(leaderboardName) == "string", "ComponentFinder.getUpdateRemoteEvent: leaderboardName must be a string")
	assert(leaderboardName ~= "", "ComponentFinder.getUpdateRemoteEvent: leaderboardName cannot be empty")

	local updateEventName = string.format(REMOTE_EVENT_NAME_FORMAT, leaderboardName)
	local remoteEvent = leaderboardEvents:FindFirstChild(updateEventName)

	if not remoteEvent then
		warn(TAG .. " Update RemoteEvent not found: " .. updateEventName)
		return nil
	end

	if not remoteEvent:IsA("RemoteEvent") then
		warn(TAG .. " Update event is not a RemoteEvent: " .. updateEventName)
		return nil
	end

	return remoteEvent
end

return ComponentFinder