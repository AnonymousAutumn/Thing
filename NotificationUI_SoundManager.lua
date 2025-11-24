--!strict

--------------
-- Services --
--------------
local SoundService = game:GetService("SoundService")

---------------
-- Constants --
---------------
local SOUND_NAMES = {
	Success = "Success",
	Warning = "Error",
	Error = "Error",
}

local feedbackSounds: SoundGroup = SoundService:WaitForChild("Feedback")

-----------
-- Module --
-----------
local SoundManager = {}

--[[
	Gets a sound from the feedback sound group

	@param soundName string - Name of the sound
	@return Sound? - Sound object or nil if not found
]]
local function getSound(soundName: string): Sound?
	local sound = feedbackSounds:FindFirstChild(soundName)
	if sound and sound:IsA("Sound") then
		return sound :: Sound
	end
	return nil
end

--[[
	Plays a sound by name

	@param soundName string - Sound name to play
]]
local function playSound(soundName: string): ()
	local success, errorMsg = pcall(function()
		local sound = getSound(soundName)
		if sound then
			sound:Play()
		end
	end)

	if not success then
		warn(string.format("[SoundManager] Failed to play sound %s: %s", soundName, tostring(errorMsg)))
	end
end

--[[
	Plays notification sound based on type

	@param notificationType string - Type of notification (Success, Warning, Error)
]]
function SoundManager.playForType(notificationType: string): ()
	local soundName = SOUND_NAMES[notificationType]
	if soundName then
		playSound(soundName)
	end
end

--[[
	Plays success sound
]]
function SoundManager.playSuccess(): ()
	playSound(SOUND_NAMES.Success)
end

--[[
	Plays error sound
]]
function SoundManager.playError(): ()
	playSound(SOUND_NAMES.Error)
end

return SoundManager