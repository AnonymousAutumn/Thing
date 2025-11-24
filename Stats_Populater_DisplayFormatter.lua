--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local UsernameCache = require(Modules.Caches.UsernameCache)

local DisplayFormatter = {}

---------------
-- Constants --
---------------
local TAG = "[DisplayFormatter]"

local USERNAME_FORMAT = "@%s"
local RANK_FORMAT = "#%d"
local UNKNOWN_USER_FORMAT = "<unknown%d>"
local CURRENCY_FORMAT = "<font color='#ffb46a'>%s</font> %s"
local WINS_FORMAT = "%s wins"

local DISPLAY_TYPE_CURRENCY = "currency"

-----------
-- Types --
-----------
type DisplayConfiguration = {
	displayType: string?,
	ROBUX_ICON_UTF: string,
	FormatHandler: {
		formatNumberWithThousandsSeparatorCommas: (number) -> string,
	},
}

local function logWarning(formatString: string, ...): ()
	warn(TAG .. " " .. string.format(formatString, ...))
end

function DisplayFormatter.getUsernameFromId(playerUserId: number): string
	if not ValidationUtils.isValidUserId(playerUserId) then
		logWarning("Invalid user ID: %s", tostring(playerUserId))
		return string.format(UNKNOWN_USER_FORMAT, tonumber(playerUserId) or -1)
	end
	return UsernameCache.getUsername(playerUserId)
end

function DisplayFormatter.formatUsername(username: string): string
	return string.format(USERNAME_FORMAT, username)
end

function DisplayFormatter.formatRank(rankPosition: number): string
	return string.format(RANK_FORMAT, rankPosition)
end

function DisplayFormatter.formatStatistic(statisticValue: number?, config: DisplayConfiguration): string
	local value = (type(statisticValue) == "number") and statisticValue or 0
	local formattedValue = config.FormatHandler.formatNumberWithThousandsSeparatorCommas(value)

	if config.displayType == DISPLAY_TYPE_CURRENCY then
		return string.format(CURRENCY_FORMAT, config.ROBUX_ICON_UTF, formattedValue)
	else
		return string.format(WINS_FORMAT, formattedValue)
	end
end

return DisplayFormatter