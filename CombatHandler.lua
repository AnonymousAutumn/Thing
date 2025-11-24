--!strict

--[[
	CombatHandler Module

	Manages combat zone detection, tool distribution, and player elimination tracking.
	Returns nothing - executes automatically when required.

	Usage:
		Automatically runs when character spawns to handle combat interactions.
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-----------
-- Types --
-----------
type CharacterDescendant = BasePart | Humanoid | Accessory | Script | LocalScript

----------------
-- References --
----------------
local character = script.Parent :: Model
local humanoid = assert(character:WaitForChild("Humanoid", 10), "Humanoid not found") :: Humanoid
local player = assert(Players:GetPlayerFromCharacter(character), "Player not found for character") :: Player

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

local instances: Folder = assert(ReplicatedStorage:WaitForChild("Instances", 10), "Instances folder not found")
local guiPrefabs = assert(instances:WaitForChild("GuiPrefabs", 10), "GuiPrefabs folder not found")
local bloxxedUIPrefab = assert(guiPrefabs:WaitForChild("DeathUIPrefab", 10), "DeathUIPrefab not found")

local worldFolder: Folder = assert(workspace:WaitForChild("World", 10), "World folder not found") :: Folder
local environmentFolder: Folder = assert(worldFolder:WaitForChild("Environment", 10), "Environment folder not found") :: Folder
local combatZonePart: BasePart = assert(environmentFolder:WaitForChild("CombatZonePart", 10), "CombatZonePart not found") :: BasePart
combatZonePart.Transparency = 1

-- Submodules
local ToolManager = require(script.ToolManager)
local DataPersistence = require(script.DataPersistence)
local EliminationHandler = require(script.EliminationHandler)
local ZoneDetector = require(script.ZoneDetector)
local DeathUIController = require(script.DeathUIController)
local isPlayerInPart = require(script.isPlayerInPart)

---------------
-- Constants --
---------------
local FIGHTING_ATTRIBUTE_NAME = "Fighting"
local LOG_PREFIX = "[CombatHandler]"

--------------------
-- Validation Utils
--------------------
local function getHumanoidFromCharacter(char: Model): Humanoid?
	if not ValidationUtils.isValidCharacter(char) then
		return nil
	end
	local hum = char:FindFirstChild("Humanoid")
	return if ValidationUtils.isValidHumanoid(hum) then hum else nil
end

local function isPlayerInCombat(char: Model): boolean
	return char:GetAttribute(FIGHTING_ATTRIBUTE_NAME) == true
end

-----------------------
-- Wrapper Functions --
-----------------------
-- These wrap the submodule functions to provide the required dependencies

local function giveToolWrapper(targetPlayer: Player): ()
	ToolManager.giveToolToPlayer(targetPlayer, getHumanoidFromCharacter)
end

local function removeToolWrapper(targetPlayer: Player): ()
	ToolManager.removeToolFromPlayer(targetPlayer)
end

local function recordWinWrapper(userId: number, wins: number): ()
	DataPersistence.recordPlayerWin(userId, wins)
end

local function handleEliminationWrapper(victim: Player, killer: Player?): ()
	EliminationHandler.handlePlayerElimination(victim, killer, recordWinWrapper)
end

--------------------
-- Initialization --
--------------------
-- Start zone monitoring
ZoneDetector.startMonitoring(
	player,
	combatZonePart,
	isPlayerInPart,
	giveToolWrapper,
	removeToolWrapper
)

-- Handle player death
humanoid.Died:Connect(function()
	if not ValidationUtils.isValidCharacter(character) then
		return
	end
	if not isPlayerInCombat(character) then
		return
	end

	local killerPlayer = EliminationHandler.getKillerFromHumanoid(humanoid)
	handleEliminationWrapper(player, killerPlayer)

	DeathUIController(bloxxedUIPrefab, player)
end)