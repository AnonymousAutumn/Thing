--!strict

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
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local FormatString = require(Modules.Utilities.FormatString)
local RainbowifyString = require(Modules.Utilities.RainbowifyString)
local GameConfig = require(Configuration.GameConfig)

local systemChatChannel: TextChannel = TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXSystem") :: TextChannel

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