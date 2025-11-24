--!strict

--[[
	Stats UIElementFinder Module

	Locates leaderboard UI elements in the workspace.
	Traverses hierarchy to find ScrollingFrames for leaderboards.

	Returns: UIElementFinder table with finder functions

	Usage:
		local UIElementFinder = require(...)
		UIElementFinder.leaderboardsContainer = workspace.Leaderboards
		local frame = UIElementFinder.getLeaderboardUIElements(config)
]]

---------------
-- Constants --
---------------
local TAG = "[UIElementFinder]"

-----------
-- Module --
-----------
local UIElementFinder = {}

-- Will be set by init.lua
UIElementFinder.leaderboardsContainer = nil :: Folder?

--[[
	Gets a single UI element from parent

	@param parent any - Parent instance
	@param elementName string - Element name
	@return Instance? - Found element or nil
]]
function UIElementFinder.getLeaderboardUIElement(parent: any, elementName: string): Instance?
	return parent:FindFirstChild(elementName)
end

--[[
	Gets leaderboard UI elements for a leaderboard config

	Traverses: Workspace/Leaderboards/{Name}/SurfaceGui/MainFrame/ScrollingFrame

	@param leaderboardConfig any - Leaderboard configuration
	@return ScrollingFrame? - Scrolling frame or nil
]]
function UIElementFinder.getLeaderboardUIElements(leaderboardConfig: any): ScrollingFrame?
	if not UIElementFinder.leaderboardsContainer then
		warn(TAG .. " Leaderboards container not set")
		return nil
	end

	local leaderboardPhysicalModel = UIElementFinder.leaderboardsContainer:FindFirstChild(leaderboardConfig.statisticName)
	if not leaderboardPhysicalModel then
		return nil
	end

	local leaderboardSurfaceGui = UIElementFinder.getLeaderboardUIElement(leaderboardPhysicalModel, "SurfaceGui")
	if not leaderboardSurfaceGui or not leaderboardSurfaceGui:IsA("SurfaceGui") then
		return nil
	end

	local leaderboardMainFrame = UIElementFinder.getLeaderboardUIElement(leaderboardSurfaceGui, "MainFrame")
	if not leaderboardMainFrame or not leaderboardMainFrame:IsA("Frame") then
		return nil
	end

	local leaderboardScrollingFrame = UIElementFinder.getLeaderboardUIElement(leaderboardMainFrame, "ScrollingFrame")
	if not leaderboardScrollingFrame or not leaderboardScrollingFrame:IsA("ScrollingFrame") then
		return nil
	end

	return leaderboardScrollingFrame
end

return UIElementFinder