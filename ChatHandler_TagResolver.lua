--!strict

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

----------------
-- References --
----------------
local Configuration = ReplicatedStorage:WaitForChild("Configuration")
local tagConfig = Configuration.TagConfig

-----------
-- Module --
-----------
local TagResolver = {}

-------------------------
-- Tag Determination --
-------------------------
function TagResolver.getChatTagProperties(message: TextChatMessage): (UIGradient?, string?)
	-- Server message (no TextSource and not Global)
	if not message.TextSource and message.Metadata ~= "Global" then
		local tag: Folder = tagConfig.Server :: Folder
		return tag.UIGradient :: UIGradient, tag.Tag.Value
	end

	local source: TextSource? = message.TextSource
	if not source then
		return nil, nil
	end

	-- Creator message
	if source.UserId == game.CreatorId then
		local tag: Folder = tagConfig.Creator :: Folder
		return tag.UIGradient :: UIGradient, tag.Tag.Value
	end

	-- Tester message
	local player: Player = Players:GetPlayerByUserId(source.UserId)
	if player and player:IsFriendsWith(game.CreatorId) then
		local tag: Folder = tagConfig.Tester :: Folder
		return tag.UIGradient :: UIGradient, tag.Tag.Value
	end

	return nil, nil
end

return TagResolver