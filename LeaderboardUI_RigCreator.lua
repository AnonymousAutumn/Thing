--!strict

local LeaderboardCharacterDisplayManager = {}
LeaderboardCharacterDisplayManager.__index = LeaderboardCharacterDisplayManager

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------
-- Modules  --
--------------
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

-- Submodules
local RigBuilder = require(script.RigBuilder)
local RigPositioner = require(script.RigPositioner)
local AnimationController = require(script.AnimationController)

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
-- Constants --
---------------
local LEADERBOARD_RANK_POSITIONS = { "Gold", "Silver", "Bronze" }
local MAX_CHARACTERS_DISPLAYED = 3
local COMPONENT_WAIT_TIMEOUT = 10

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
	local mainFrame = waitForChildSafe(leaderboardSurfaceGui, "MainFrame", COMPONENT_WAIT_TIMEOUT)
	if not mainFrame or not mainFrame:IsA("ViewportFrame") then
		error("MainFrame not found")
	end

	local worldModel = waitForChildSafe(mainFrame, "WorldModel", COMPONENT_WAIT_TIMEOUT)
	if not worldModel or not worldModel:IsA("WorldModel") then
		error("WorldModel not found")
	end

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
	if typeof(topPlayerUserIds) ~= "table" then
		return
	end

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