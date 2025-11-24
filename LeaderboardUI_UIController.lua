--!strict

--[[
	LeaderboardUI_UIController - UI interaction controller for leaderboards

	This module manages leaderboard UI interactions:
	- Sets up toggle button functionality
	- Manages visibility of leaderboard entries
	- Controls transparency states for leaderboard displays

	Returns: UIController module with UI setup functions

	Usage:
		UIController.setupToggle(
			toggleButton,
			scrollingFrame,
			clientHandler,
			state
		)
]]

-----------
-- Types --
-----------
type LeaderboardHandler = {
	processResults: (self: LeaderboardHandler, data: {any}) -> (),
	cleanup: (self: LeaderboardHandler) -> (),
	MainFrame: Frame,
}

type LeaderboardState = {
	handler: LeaderboardHandler?,
	resourceManager: any,
	isInitialized: boolean,
	lastUpdateTime: number?,
	updateCount: number,
}

--------------
-- Constants --
--------------
local TAG = "[LeaderboardUI_UIController]"
local LEADERBOARD_TRANSPARENCY = {
	VISIBLE = 0.85,
	HIDDEN = 0,
}

-----------
-- Module --
-----------
local UIController = {}

---------------
-- Utilities --
---------------
local function safeExecute(func: () -> ()): boolean
	local success, errorMessage = pcall(func)
	if not success then
		warn("Error in UIController.safeExecute:", errorMessage)
	end
	return success
end

local function toggleLeaderboardVisibility(scrollingFrame: ScrollingFrame, mainFrameLike: ViewportFrame): ()
	local shouldShowEntries = not scrollingFrame.Visible
	scrollingFrame.Visible = shouldShowEntries

	safeExecute(function()
		if mainFrameLike.ImageTransparency ~= nil then
			mainFrameLike.ImageTransparency = shouldShowEntries
				and LEADERBOARD_TRANSPARENCY.VISIBLE
				or LEADERBOARD_TRANSPARENCY.HIDDEN
		end
	end)
end

------------------
-- Public API --
------------------
function UIController.setupToggle(
	toggleButton: GuiButton,
	scrollingFrame: ScrollingFrame,
	clientHandler: LeaderboardHandler,
	state: LeaderboardState
): boolean
	assert(toggleButton, "UIController.setupToggle: toggleButton is required")
	assert(scrollingFrame, "UIController.setupToggle: scrollingFrame is required")
	assert(clientHandler, "UIController.setupToggle: clientHandler is required")
	assert(state, "UIController.setupToggle: state is required")

	return safeExecute(function()
		local toggleConnection = toggleButton.MouseButton1Click:Connect(function()
			safeExecute(function()
				toggleLeaderboardVisibility(scrollingFrame, clientHandler.MainFrame)
			end)
		end)
		state.resourceManager:trackConnection(toggleConnection)
	end)
end

return UIController