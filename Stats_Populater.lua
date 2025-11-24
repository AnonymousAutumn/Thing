--!strict

-----------------
-- Initializer --
-----------------

local LeaderboardDisplayManager = {}

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local ValidationUtils = require(Modules.Utilities.ValidationUtils)
local UsernameCache = require(Modules.Caches.UsernameCache)

local FrameValidator = require(script.FrameValidator)
local DisplayFormatter = require(script.DisplayFormatter)
local ColorStyler = require(script.ColorStyler)
local PlayerRenderer = require(script.PlayerRenderer)
local DataExtractor = require(script.DataExtractor)

-----------
-- Types --
-----------
export type LeaderboardEntry = DataExtractor.LeaderboardEntry

type DisplayConfiguration = {
	displayType: string?,
	AVATAR_HEADSHOT_URL: string,
	ROBUX_ICON_UTF: string,
	FormatHandler: {
		formatNumberWithThousandsSeparatorCommas: (number) -> string,
	},
	LEADERBOARD_CONFIG: {
		DISPLAY_COUNT: number,
	},
}

type ColorConfiguration = {
	BACKGROUNDCOLOR: Color3,
	STROKECOLOR: Color3,
}

---------------
-- Helpers --
---------------

local function setupRankDisplay(frame: Frame, rankPosition: number): ()
	if not FrameValidator.validateStructure(frame) then
		return
	end
	local holderFrame = FrameValidator.getHolderFrame(frame)
	local infoFrame = FrameValidator.getInfoFrame(holderFrame)
	local rankLabel = FrameValidator.getChild(infoFrame, "RankLabel")

	if ValidationUtils.isValidTextLabel(rankLabel) then
		rankLabel.Text = DisplayFormatter.formatRank(rankPosition)
	end
end

local function applyRankColor(frame: Frame, rankPosition: number, rankColorConfiguration: { ColorConfiguration }): ()
	if not FrameValidator.validateStructure(frame) then
		return
	end

	local rankColor = ColorStyler.getRankColor(rankPosition, rankColorConfiguration)
	if not rankColor then
		frame.BackgroundColor3 = ColorStyler.getAlternatingRowColor(rankPosition)
		return
	end

	local holderFrame = FrameValidator.getHolderFrame(frame)
	local infoFrame = FrameValidator.getInfoFrame(holderFrame)
	local amountFrame = FrameValidator.getAmountFrame(frame)

	local rankLabel = FrameValidator.getChild(infoFrame, "RankLabel")
	local usernameLabel = FrameValidator.getChild(holderFrame, "UsernameLabel")
	local statisticLabel = FrameValidator.getChild(amountFrame, "StatisticLabel")

	frame.BackgroundColor3 = rankColor.BACKGROUNDCOLOR

	local labels = {}
	if ValidationUtils.isValidTextLabel(rankLabel) then
		table.insert(labels, rankLabel)
	end
	if ValidationUtils.isValidTextLabel(usernameLabel) then
		table.insert(labels, usernameLabel)
	end
	if ValidationUtils.isValidTextLabel(statisticLabel) then
		table.insert(labels, statisticLabel)
	end

	ColorStyler.applyStrokeToLabels(labels, rankColor.STROKECOLOR)
end

local function setupPlayerDisplay(frame: Frame, playerUserId: number?, config: DisplayConfiguration): ()
	if not FrameValidator.validateStructure(frame) then
		return
	end

	local holderFrame = FrameValidator.getHolderFrame(frame)
	local infoFrame = FrameValidator.getInfoFrame(holderFrame)
	local usernameLabel = FrameValidator.getChild(holderFrame, "UsernameLabel")
	local avatarImage = FrameValidator.getChild(infoFrame, "AvatarImage")

	if not ValidationUtils.isValidUserId(playerUserId) then
		PlayerRenderer.setupStudioTestDisplay(usernameLabel, avatarImage)
	else
		local username = DisplayFormatter.getUsernameFromId(playerUserId)
		local formattedUsername = DisplayFormatter.formatUsername(username)
		PlayerRenderer.setupRealPlayerDisplay(usernameLabel, avatarImage, playerUserId, formattedUsername, config)
	end
end

local function setupStatisticDisplay(frame: Frame, statisticValue: number?, config: DisplayConfiguration): ()
	local amountFrame = FrameValidator.getAmountFrame(frame)
	local statisticLabel = FrameValidator.getChild(amountFrame, "StatisticLabel")

	if not ValidationUtils.isValidTextLabel(statisticLabel) then
		return
	end

	statisticLabel.Text = DisplayFormatter.formatStatistic(statisticValue, config)
end

-----------------------
-- Public API (UI)  --
-----------------------

function LeaderboardDisplayManager.createLeaderboardEntryFrame(
	rankPosition: number,
	frameTemplate: Frame,
	parentContainer: GuiObject,
	rankColorConfiguration: { ColorConfiguration },
	fadeInAnimationDuration: number
): Frame?
	local newFrame = frameTemplate:Clone()
	newFrame.LayoutOrder = rankPosition
	newFrame.Visible = false
	newFrame.Parent = parentContainer
	setupRankDisplay(newFrame, rankPosition)
	applyRankColor(newFrame, rankPosition, rankColorConfiguration)
	return newFrame
end

function LeaderboardDisplayManager.populateLeaderboardEntryDataAsync(
	targetFrame: Frame,
	playerUserId: number?,
	playerStatisticValue: number?,
	displayConfiguration: DisplayConfiguration
): ()
	if not ValidationUtils.isValidFrame(targetFrame) then
		return
	end
	setupPlayerDisplay(targetFrame, playerUserId, displayConfiguration)
	setupStatisticDisplay(targetFrame, playerStatisticValue, displayConfiguration)
	targetFrame.Visible = true
end

-----------------------
-- Public API (Data) --
-----------------------

function LeaderboardDisplayManager.extractLeaderboardDataFromPages(
	dataStorePages: Pages,
	maximumEntryCount: number
): { LeaderboardEntry }
	return DataExtractor.extractFromPages(dataStorePages, maximumEntryCount)
end

function LeaderboardDisplayManager.refreshAllLeaderboardDisplayFrames(
	leaderboardFrames: { Frame },
	leaderboardData: { LeaderboardEntry },
	systemConfiguration: DisplayConfiguration
): ()
	local displayCount = systemConfiguration.LEADERBOARD_CONFIG.DISPLAY_COUNT
	for frameIndex = 1, displayCount do
		local entryData = leaderboardData[frameIndex]
		local displayFrame = leaderboardFrames[frameIndex]

		if not ValidationUtils.isValidFrame(displayFrame) then
			continue
		end

		if entryData and type(entryData) == "table" then
			LeaderboardDisplayManager.populateLeaderboardEntryDataAsync(
				displayFrame,
				tonumber(entryData.key),
				entryData.value,
				systemConfiguration
			)
		else
			displayFrame.Visible = false
		end
	end
end

function LeaderboardDisplayManager.clearUsernameCache(): ()
	UsernameCache.clearCache()
end

------------
-- Return --
------------
return LeaderboardDisplayManager