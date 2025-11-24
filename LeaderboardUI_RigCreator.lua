--!strict

--[[
	LeaderboardUI_RigCreator - Character rig display manager for leaderboards

	This module manages 3D character displays in leaderboard ViewportFrames:
	- Creates and positions character rigs for top 3 players
	- Manages rig animations and cleanup
	- Coordinates with submodules for building, positioning, and animating

	Returns: LeaderboardCharacterDisplayManager class

	Usage:
		local manager = LeaderboardCharacterDisplayManager.new(surfaceGui)
		manager:processResults({userId1, userId2, userId3})
		manager:clearAllDisplayedCharacters()
		manager:cleanup()
]]

local LeaderboardCharacterDisplayManager = {}
LeaderboardCharacterDisplayManager.__index = LeaderboardCharacterDisplayManager

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------
-- Constants --
---------------
local TAG = "[LeaderboardUI_RigCreator]"
local WAIT_TIMEOUT = 10
local COMPONENT_WAIT_TIMEOUT = 10
local LEADERBOARD_RANK_POSITIONS = { "Gold", "Silver", "Bronze" }
local MAX_CHARACTERS_DISPLAYED = 3

--------------
-- Modules  --
--------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), TAG .. " Modules folder not found")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

-- Submodules
local RigBuilder = require(assert(script:WaitForChild("RigBuilder", WAIT_TIMEOUT), TAG .. " RigBuilder not found"))
local RigPositioner = require(assert(script:WaitForChild("RigPositioner", WAIT_TIMEOUT), TAG .. " RigPositioner not found"))
local AnimationController = require(assert(script:WaitForChild("AnimationController", WAIT_TIMEOUT), TAG .. " AnimationController not found"))

-----------
-- Types --
-----------
type CharacterRig = {
	model: Model,
	animationTrack: AnimationTrack?,
	userId: number,
	rank: number,
}

---------------
-- Utilities --
---------------
local function isValidRankIndex(rankIndex: any): boolean
	return typeof(rankIndex) == "number" and rankIndex >= 1 and rankIndex <= #LEADERBOARD_RANK_POSITIONS
end

local function safeExecute(func: () -> ()): boolean
	return pcall(func)
end

-- NOTE: Duplicated in LeaderboardUI.lua - consider extracting to shared utility if used elsewhere
local function waitForChildSafe(parent: Instance, childName: string, timeout: number): Instance?
	local success, child = pcall(function()
		return parent:WaitForChild(childName, timeout)
	end)
	return success and child or nil
end

-- Wire up submodule dependencies
RigBuilder.safeExecute = safeExecute
RigBuilder.positionCharacterAtRankLocation = function(characterRig: Model, rankPositionReference: Model): boolean
	return RigPositioner.positionCharacterAtRankLocation(characterRig, rankPositionReference)
end

RigPositioner.safeExecute = safeExecute
AnimationController.safeExecute = safeExecute

-----------------
-- Initializers --
-----------------
local function initializeComponents(leaderboardSurfaceGui: SurfaceGui): (ViewportFrame?, WorldModel?)
	assert(leaderboardSurfaceGui, "initializeComponents: leaderboardSurfaceGui is required")

	local mainFrame = assert(waitForChildSafe(leaderboardSurfaceGui, "MainFrame", COMPONENT_WAIT_TIMEOUT), TAG .. " MainFrame not found")
	assert(mainFrame:IsA("ViewportFrame"), TAG .. " MainFrame is not a ViewportFrame")

	local worldModel = assert(waitForChildSafe(mainFrame, "WorldModel", COMPONENT_WAIT_TIMEOUT), TAG .. " WorldModel not found")
	assert(worldModel:IsA("WorldModel"), TAG .. " WorldModel is not a WorldModel")

	return mainFrame :: ViewportFrame, worldModel :: WorldModel
end

function LeaderboardCharacterDisplayManager.new(leaderboardSurfaceGui: SurfaceGui)
	if not leaderboardSurfaceGui or not leaderboardSurfaceGui:IsA("SurfaceGui") then
		return nil
	end

	local self = setmetatable({}, LeaderboardCharacterDisplayManager)

	local success = pcall(function()
		self.LeaderboardInterface = leaderboardSurfaceGui
		local mainFrame, worldModel = initializeComponents(leaderboardSurfaceGui)
		self.MainFrame = mainFrame
		self.CharacterDisplayWorldModel = worldModel
		self.DisplayedCharacterRigs = {} :: { CharacterRig }
	end)

	return success and self or nil
end

-----------------
-- Presentation --
-----------------
local function cleanupCharacterRig(rigData: CharacterRig): ()
	if rigData.animationTrack then
		AnimationController.cleanupAnimationTrack(rigData.animationTrack)
	end

	if rigData.model and rigData.model.Parent then
		rigData.model:Destroy()
	end
end

function LeaderboardCharacterDisplayManager:clearAllDisplayedCharacters()
	safeExecute(function()
		-- Clean tracked rigs
		for _, rigData in ipairs(self.DisplayedCharacterRigs) do
			cleanupCharacterRig(rigData)
		end

		-- Clean any remaining rigs in WorldModel
		for _, child in ipairs(self.CharacterDisplayWorldModel:GetChildren()) do
			if child.Name:match("^" .. RigBuilder.CHARACTER_RIG_NAME_PREFIX) then
				child:Destroy()
			end
		end

		table.clear(self.DisplayedCharacterRigs)
	end)
end

local function processSinglePlayerCharacter(self: any, playerUserId: number, rankIndex: number): ()
	if not ValidationUtils.isValidUserId(playerUserId) or not isValidRankIndex(rankIndex) then
		return
	end

	local currentRankName = LEADERBOARD_RANK_POSITIONS[rankIndex]
	local rankPositionReferenceModel = self.CharacterDisplayWorldModel:FindFirstChild(currentRankName)
	if not rankPositionReferenceModel or not rankPositionReferenceModel:IsA("Model") then
		return
	end

	local createdCharacterRig = RigBuilder.createPlayerCharacterForDisplay(
		playerUserId,
		rankPositionReferenceModel,
		self.CharacterDisplayWorldModel
	)

	if createdCharacterRig then
		local humanoid = createdCharacterRig:FindFirstChildOfClass("Humanoid")
		local track = humanoid and AnimationController.startCharacterIdleAnimation(humanoid) or nil

		table.insert(self.DisplayedCharacterRigs, {
			model = createdCharacterRig,
			animationTrack = track,
			userId = playerUserId,
			rank = rankIndex,
		})
	end
end

function LeaderboardCharacterDisplayManager:processResults(topPlayerUserIds: { number })
	assert(typeof(topPlayerUserIds) == "table", "LeaderboardCharacterDisplayManager:processResults: topPlayerUserIds must be a table")

	local displayCount = math.min(#topPlayerUserIds, MAX_CHARACTERS_DISPLAYED)

	safeExecute(function()
		self:clearAllDisplayedCharacters()

		for rankIndex = 1, displayCount do
			local playerUserId = topPlayerUserIds[rankIndex]
			processSinglePlayerCharacter(self, playerUserId, rankIndex)
		end
	end)
end

function LeaderboardCharacterDisplayManager:cleanup()
	self:clearAllDisplayedCharacters()
	self.LeaderboardInterface = nil
	self.MainFrame = nil
	self.CharacterDisplayWorldModel = nil
end

return LeaderboardCharacterDisplayManager