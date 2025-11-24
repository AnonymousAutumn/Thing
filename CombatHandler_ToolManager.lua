--!strict

--[[
	ToolManager Module

	Manages tool distribution and removal for combat system.
	Returns a table with giveToolToPlayer and removeToolFromPlayer methods.

	Usage:
		ToolManager.giveToolToPlayer(player, getHumanoidFunc)
		ToolManager.removeToolFromPlayer(player)
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

local instances: Folder = assert(ReplicatedStorage:WaitForChild("Instances", 10), "Instances folder not found")
local tools = assert(instances:WaitForChild("Tools", 10), "Tools folder not found")
local swordPrefab = assert(tools:WaitForChild("ClassicSword", 10), "ClassicSword tool not found")

---------------
-- Constants --
---------------
local TOOL_NAME = swordPrefab.Name
local LOG_PREFIX = "[ToolManager]"

-----------
-- Module --
-----------
local ToolManager = {}

--------------------
-- Tool Detection
--------------------
local function hasToolInBackpack(targetPlayer: Player): boolean
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		return false
	end
	local backpack = targetPlayer:FindFirstChild("Backpack")
	return backpack ~= nil and backpack:FindFirstChild(TOOL_NAME) ~= nil
end

local function hasToolInCharacter(targetPlayer: Player): boolean
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		return false
	end
	local char = targetPlayer.Character
	return char ~= nil and char:FindFirstChild(TOOL_NAME) ~= nil
end

local function playerHasTool(targetPlayer: Player): boolean
	return hasToolInBackpack(targetPlayer) or hasToolInCharacter(targetPlayer)
end

------------------
-- Public API --
------------------
function ToolManager.giveToolToPlayer(targetPlayer: Player, getHumanoidFunc: (Model) -> Humanoid?): ()
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		return
	end
	if playerHasTool(targetPlayer) then
		return
	end
	local char = targetPlayer.Character
	if not char then
		return
	end
	local hum = getHumanoidFunc(char)
	if not hum then
		return
	end
	local success, errorMessage = pcall(function()
		local toolClone = swordPrefab:Clone()
		toolClone.Parent = targetPlayer.Backpack
		hum:EquipTool(toolClone)
	end)
	if not success then
		warn(
			string.format("%s Failed to give tool to player %s: %s", LOG_PREFIX, targetPlayer.Name, errorMessage)
		)
	end
end

function ToolManager.removeToolFromPlayer(targetPlayer: Player): ()
	if not ValidationUtils.isValidPlayer(targetPlayer) then
		return
	end
	local success, errorMessage = pcall(function()
		-- Remove from backpack
		local backpack = targetPlayer:FindFirstChild("Backpack")
		if backpack then
			local toolInBackpack = backpack:FindFirstChild(TOOL_NAME)
			if toolInBackpack then
				toolInBackpack:Destroy()
			end
		end
		-- Remove from character
		local char = targetPlayer.Character
		if char then
			local toolInCharacter = char:FindFirstChild(TOOL_NAME)
			if toolInCharacter then
				toolInCharacter:Destroy()
			end
		end
	end)
	if not success then
		warn(
			string.format(
				"%s Failed to remove tool from player %s: %s",
				LOG_PREFIX,
				targetPlayer.Name,
				errorMessage
			)
		)
	end
end

return ToolManager