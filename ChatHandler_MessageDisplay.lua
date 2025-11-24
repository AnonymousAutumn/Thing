--!strict

--[[
	MessageDisplay Module

	Displays Robux transaction messages in system chat.
	Returns a table with displayRobuxTransaction method.

	Usage:
		MessageDisplay.displayRobuxTransaction("Player1", "Player2", "sent", 1000, false)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

---------------
-- Constants --
---------------
local ROBUX_CURRENCY_COLOR: string = "#ffb46a"

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Configuration folder not found")

local FormatString = require(Modules.Utilities.FormatString)
local RainbowifyString = require(Modules.Utilities.RainbowifyString)
local GameConfig = require(Configuration.GameConfig)

local textChannels = assert(TextChatService:WaitForChild("TextChannels", 10), "TextChannels not found")
local systemChatChannel: TextChannel = assert(textChannels:WaitForChild("RBXSystem", 10), "RBXSystem channel not found") :: TextChannel

-----------
-- Module --
-----------
local MessageDisplay = {}

---------------------------------
-- Robux Transaction Display --
---------------------------------
function MessageDisplay.displayRobuxTransaction(
	sender: string,
	receiver: string,
	action: string,
	amount: number,
	useRainbow: boolean
): ()
	local formattedRobux: string = FormatString.formatNumberWithThousandsSeparatorCommas(amount)
	local baseMessage: string = string.format(
		`%s %s <font color='#ffb46a'>{GameConfig.ROBUX_ICON_UTF}</font>%s to %s!`,
		sender,
		action,
		formattedRobux,
		receiver
	)

	-- Apply rainbow effect if needed
	local finalMessage: string = if useRainbow then RainbowifyString(baseMessage) else baseMessage
	local metadata: string? = if useRainbow then "Global" else nil

	systemChatChannel:DisplaySystemMessage(finalMessage, metadata)
end

return MessageDisplay