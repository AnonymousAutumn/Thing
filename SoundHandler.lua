--!strict

--[[
	SoundHandler Script

	Handles client-side sound playback for game outcomes (victory/defeat).
	Listens to server sound requests and plays appropriate sounds.

	Returns: Nothing (client-side script)

	Usage: Runs automatically when placed in game
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

----------------
-- References --
----------------

local network : Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network in ReplicatedStorage")
local remotes = assert(network:WaitForChild("Remotes", 10), "Failed to find Remotes folder")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Failed to find Events folder")
local playSoundEvent = assert(remoteEvents:WaitForChild("PlaySound", 10), "Failed to find PlaySound event")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules in ReplicatedStorage")
local ResourceCleanup = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("ResourceCleanup", 10), "Failed to find ResourceCleanup"))

local feedbackGroup : SoundGroup = assert(SoundService:WaitForChild("Feedback", 10), "Failed to find Feedback sound group")
local defeatSound = assert(feedbackGroup:WaitForChild("Defeat", 10), "Failed to find Defeat sound")
local victorySound = assert(feedbackGroup:WaitForChild("Victory", 10), "Failed to find Victory sound")

---------------
-- State/Utils --
---------------
local resourceManager = ResourceCleanup.new()
local localPlayer = Players.LocalPlayer

local function getSoundForOutcome(playerWasDefeated: boolean): Sound?
	local soundCandidate = if playerWasDefeated then defeatSound else victorySound
	return if soundCandidate:IsA("Sound") then soundCandidate else nil
end

---------------
-- Handlers --
---------------
local function handleSoundRequest(playerWasDefeated: boolean): ()
	if typeof(playerWasDefeated) ~= "boolean" then
		return
	end

	local soundToPlay = getSoundForOutcome(playerWasDefeated)
	if soundToPlay then
		soundToPlay:Play()
	end
end

--------------------
-- Initialization --
--------------------
resourceManager:trackConnection(playSoundEvent.OnClientEvent:Connect(handleSoundRequest))

-- Clean up if player or script is removed (prevent lingering connections)
resourceManager:trackConnection(
	script.AncestryChanged:Connect(function()
		if not script:IsDescendantOf(game) then
			resourceManager:cleanupAll()
		end
	end)
)

if localPlayer then
	resourceManager:trackConnection(
		localPlayer.AncestryChanged:Connect(function()
			if not localPlayer:IsDescendantOf(game) then
				resourceManager:cleanupAll()
			end
		end)
	)
end