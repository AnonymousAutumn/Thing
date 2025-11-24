--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

----------------
-- References --
----------------

local network : Folder = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")
local playSoundEvent = remoteEvents:WaitForChild("PlaySound")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

local feedbackGroup : SoundGroup = SoundService:WaitForChild("Feedback")
local defeatSound = feedbackGroup:WaitForChild("Defeat")
local victorySound = feedbackGroup:WaitForChild("Victory")

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