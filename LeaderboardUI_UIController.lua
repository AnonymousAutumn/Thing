--!strict

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
	if not toggleButton or not scrollingFrame or not clientHandler or not state then
		return false
	end

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