--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local PlayerData = require(Modules.Managers.PlayerData)

---------------
-- Constants --
---------------
local TRACKED_STATISTICS = { "Donated", "Raised", "Wins" }

local DISPLAY_PRIORITIES = {
	Donated = 2,
	Raised = 1,
	Wins = 0,
}

local DEFAULT_VALUE = 0

-----------
-- Module --
-----------
local LeaderboardBuilder = {}

--[[
	Gets display priority for a statistic

	@param statisticName string - Statistic name
	@return number? - Priority value
]]
local function getDisplayPriority(statisticName: string): number?
	return DISPLAY_PRIORITIES[statisticName]
end

--[[
	Creates priority value object for sorting

	@param statisticName string - Statistic name
	@param parent Instance - Parent instance
]]
local function createPriorityValue(statisticName: string, parent: Instance): ()
	local priority = getDisplayPriority(statisticName)
	if not priority then
		return
	end

	local priorityValue = Instance.new("NumberValue")
	priorityValue.Name = "Priority"
	priorityValue.Value = priority
	priorityValue.Parent = parent
end

--[[
	Creates a statistic value object

	@param statisticName string - Statistic name
	@param initialValue number - Initial value
	@param parent Instance - Parent folder
	@return IntValue? - Created value object or nil on failure
]]
local function createStatisticValue(statisticName: string, initialValue: number, parent: Instance): IntValue?
	local success, valueObject = pcall(function()
		local intValue = Instance.new("IntValue")
		intValue.Name = statisticName
		intValue.Value = initialValue
		intValue.Parent = parent

		createPriorityValue(statisticName, intValue)
		return intValue
	end)

	if not success then
		warn(string.format("[LeaderboardBuilder] Failed to create value object for %s: %s", statisticName, tostring(valueObject)))
		return nil
	end

	return valueObject
end

--[[
	Creates leaderstats folder for player

	@param player Player - Target player
	@return Folder - Created leaderstats folder
]]
local function createLeaderstatsFolder(player: Player): Folder
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	folder.Parent = player
	return folder
end

--[[
	Creates all statistic value objects for a player

	@param playerUserId number - Player user ID
	@param leaderboardFolder Folder - Parent leaderstats folder
]]
local function createAllStatistics(playerUserId: number, leaderboardFolder: Folder): ()
	for _, statisticName in TRACKED_STATISTICS do
		local statisticValue = PlayerData:GetPlayerStatisticValue(playerUserId, statisticName) or DEFAULT_VALUE

		local valueObject = createStatisticValue(statisticName, statisticValue, leaderboardFolder)
		if not valueObject then
			error(string.format("Failed to create value object for %s", statisticName))
		end
	end
end

--[[
	Creates complete leaderboard display for a player

	@param player Player - Target player
	@return boolean - True if successful
]]
function LeaderboardBuilder.createLeaderboard(player: Player): boolean
	local success, errorMessage = pcall(function()
		PlayerData:CachePlayerStatisticsDataInMemory(player.UserId)

		local leaderboardFolder = createLeaderstatsFolder(player)
		createAllStatistics(player.UserId, leaderboardFolder)
	end)

	if not success then
		warn(string.format("[LeaderboardBuilder] Failed to create leaderboard for %s (UserId: %d): %s", player.Name, player.UserId, tostring(errorMessage)))
		return false
	end

	return true
end

--[[
	Gets leaderstats folder for a player

	@param player Player - Target player
	@return Folder? - Leaderstats folder or nil
]]
function LeaderboardBuilder.getLeaderstatsFolder(player: Player): Folder?
	return player:WaitForChild("leaderstats")
end

--[[
	Gets a specific statistic display object

	@param leaderboardFolder Folder - Leaderstats folder
	@param statisticName string - Statistic name
	@return IntValue? - Statistic value object or nil
]]
function LeaderboardBuilder.getStatisticObject(leaderboardFolder: Folder, statisticName: string): IntValue?
	local statObject = leaderboardFolder:FindFirstChild(statisticName)
	if not statObject or not statObject:IsA("IntValue") then
		return nil
	end
	return statObject
end

return LeaderboardBuilder