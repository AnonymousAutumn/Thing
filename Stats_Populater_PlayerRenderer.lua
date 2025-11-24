--!strict

--[[
	Stats Populater PlayerRenderer Module

	Renders player information (username, avatar) in leaderboard entries.
	Handles both real players and Studio test displays.

	Returns: PlayerRenderer table with rendering functions

	Usage:
		local PlayerRenderer = require(...)
		PlayerRenderer.setupRealPlayerDisplay(label, image, userId, name, config)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local ValidationUtils = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("ValidationUtils", 10), "Failed to find ValidationUtils"))

local PlayerRenderer = {}

---------------
-- Constants --
---------------
local STUDIO_TEST_AVATAR_ID = "rbxassetid://11569282129"
local STUDIO_TEST_NAME = "Studio Test Profile"

-----------
-- Types --
-----------
type DisplayConfiguration = {
	AVATAR_HEADSHOT_URL: string,
}

function PlayerRenderer.setupStudioTestDisplay(usernameLabel: TextLabel?, avatarImage: ImageLabel?): ()
	if ValidationUtils.isValidTextLabel(usernameLabel) then
		usernameLabel.Text = STUDIO_TEST_NAME
	end
	if ValidationUtils.isValidImageLabel(avatarImage) then
		avatarImage.Image = STUDIO_TEST_AVATAR_ID
	end
end

function PlayerRenderer.setupRealPlayerDisplay(
	usernameLabel: TextLabel?,
	avatarImage: ImageLabel?,
	playerUserId: number,
	formattedUsername: string,
	config: DisplayConfiguration
): ()
	if ValidationUtils.isValidTextLabel(usernameLabel) then
		usernameLabel.Text = formattedUsername
	end
	if ValidationUtils.isValidImageLabel(avatarImage) then
		avatarImage.Image = string.format(config.AVATAR_HEADSHOT_URL, playerUserId)
	end
end

return PlayerRenderer