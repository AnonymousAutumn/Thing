--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ValidationUtils = require(Modules.Utilities.ValidationUtils)

local FrameValidator = {}

local function getFrameChild(frame: Instance, childName: string): Instance?
	return frame:FindFirstChild(childName)
end

function FrameValidator.validateStructure(frame: Frame): boolean
	if not ValidationUtils.isValidFrame(frame) then
		return false
	end
	local holderFrame = getFrameChild(frame, "Holder")
	if not holderFrame then
		return false
	end
	local infoFrame = getFrameChild(holderFrame, "InfoFrame")
	if not infoFrame then
		return false
	end
	return true
end

function FrameValidator.getChild(frame: Instance, childName: string): Instance?
	return frame:FindFirstChild(childName)
end

function FrameValidator.getHolderFrame(frame: Frame): Instance?
	return getFrameChild(frame, "Holder")
end

function FrameValidator.getInfoFrame(holderFrame: Instance): Instance?
	return getFrameChild(holderFrame, "InfoFrame")
end

function FrameValidator.getAmountFrame(frame: Frame): Instance?
	return getFrameChild(frame, "AmountFrame")
end

return FrameValidator