--!strict

--------------
-- Services --
--------------
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local network: Folder = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local leaderboardEvents = remotes:WaitForChild("Leaderboards")
local workspaceLeaderboardsContainer = Workspace:WaitForChild("Leaderboards")

--------------
-- Constants --
--------------
local COMPONENT_WAIT_TIMEOUT = 10
local REMOTE_EVENT_NAME_FORMAT = "Update%s"

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
	if typeof(leaderboardName) ~= "string" or leaderboardName == "" then
		return nil
	end

	local workspaceLeaderboard = workspaceLeaderboardsContainer:FindFirstChild(leaderboardName)
	if not workspaceLeaderboard then
		return nil
	end

	local surfaceGui = waitForChildSafe(workspaceLeaderboard, "SurfaceGui", COMPONENT_WAIT_TIMEOUT)
	if not surfaceGui then
		return nil
	end

	local mainFrame = waitForChildSafe(surfaceGui, "MainFrame", COMPONENT_WAIT_TIMEOUT)
	if not mainFrame then
		return nil
	end

	local scrollingFrame = waitForChildSafe(mainFrame, "ScrollingFrame", COMPONENT_WAIT_TIMEOUT)
	local toggleButton = waitForChildSafe(mainFrame, "ToggleButton", COMPONENT_WAIT_TIMEOUT)

	if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
		return nil
	end
	if not toggleButton or not toggleButton:IsA("GuiButton") then
		return nil
	end

	return {
		scrollingFrame = scrollingFrame :: ScrollingFrame,
		toggleButton = toggleButton :: GuiButton,
	}
end

function ComponentFinder.getUpdateRemoteEvent(leaderboardName: string): RemoteEvent?
	local updateEventName = string.format(REMOTE_EVENT_NAME_FORMAT, leaderboardName)
	local remoteEvent = leaderboardEvents:FindFirstChild(updateEventName)
	return (remoteEvent and remoteEvent:IsA("RemoteEvent")) and remoteEvent or nil
end

return ComponentFinder