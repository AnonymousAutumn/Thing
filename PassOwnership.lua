local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Reference to your GUI prefab in ReplicatedStorage
local modules = ReplicatedStorage:WaitForChild("Modules")
local configuration = ReplicatedStorage:WaitForChild("Configuration")

local PurchasesWrapper = require(modules.Wrappers.Purchases)
local gameConfig = require(configuration.GameConfig)

local instances = ReplicatedStorage:WaitForChild("Instances")
local carKeys = instances.Tools.CarKeys
local customGui = instances.GuiPrefabs.CustomFreecam

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