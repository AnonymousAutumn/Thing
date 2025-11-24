--[[
	Pass Ownership Handler

	Handles special pass ownership functionality including freecam GUI replacement
	and car keys tool distribution. Listens to player attributes for pass ownership
	changes and grants appropriate items.

	Returns: nil (auto-initializes on require)

	Usage:
		Require this module in a LocalScript. It will automatically detect pass
		ownership and grant the appropriate items (freecam GUI, car keys tool).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = assert(LocalPlayer:WaitForChild("PlayerGui", 10), "Failed to find PlayerGui")

-- Reference to your GUI prefab in ReplicatedStorage
local modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules in ReplicatedStorage")
local configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Failed to find Configuration in ReplicatedStorage")

local PurchasesWrapper = require(modules.Wrappers.Purchases)
local gameConfig = require(configuration.GameConfig)

local instances = assert(ReplicatedStorage:WaitForChild("Instances", 10), "Failed to find Instances in ReplicatedStorage")
local tools = assert(instances:WaitForChild("Tools", 10), "Failed to find Tools in Instances")
local carKeys = assert(tools:WaitForChild("CarKeys", 10), "Failed to find CarKeys in Tools")
local guiPrefabs = assert(instances:WaitForChild("GuiPrefabs", 10), "Failed to find GuiPrefabs in Instances")
local customGui = assert(guiPrefabs:WaitForChild("CustomFreecam", 10), "Failed to find CustomFreecam in GuiPrefabs")

local ownsFreecam = false
local ownsCarKeys = false

-- Function to ensure we have ONLY your GUI
local function replaceDefaultFreecam()

	-- Check for Roblox's default one
	local defaultGui = PlayerGui:FindFirstChild("Freecam")

	if defaultGui then
		-- Destroy Roblox's version
		defaultGui:Destroy()
	end

	-- Check if your GUI is already inserted
	if not PlayerGui:FindFirstChild("CustomFreecam") then
		local newGui = customGui:Clone()
		newGui.Parent = PlayerGui
	end
end

-- Run immediately on start
if PurchasesWrapper.doesPlayerOwnPass(LocalPlayer, gameConfig.MONETIZATION.FREECAM) then
	ownsFreecam = true
	
	replaceDefaultFreecam()
end

if PurchasesWrapper.doesPlayerOwnPass(LocalPlayer, gameConfig.MONETIZATION.CAR_KEYS) then
	ownsCarKeys = true
	
	local carKeysClone = carKeys:Clone()
	carKeys.Parent = LocalPlayer.Backpack
end

LocalPlayer.AttributeChanged:Connect(function(attributeName)
	local value = LocalPlayer:GetAttribute(attributeName)
	if value ~= true then return end

	local id = tonumber(attributeName)
	
	if id == gameConfig.MONETIZATION.FREECAM and not ownsFreecam then
		replaceDefaultFreecam()
	elseif id == gameConfig.MONETIZATION.CAR_KEYS and not ownsCarKeys then
		local carKeysClone = carKeys:Clone()
		carKeysClone.Parent = LocalPlayer.Backpack
	end
end)