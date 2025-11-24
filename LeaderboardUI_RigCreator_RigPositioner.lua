--!strict

-----------
-- Module --
-----------
local RigPositioner = {}

-- External dependencies (set by RigCreator)
RigPositioner.safeExecute = nil :: (((() -> ()) -> boolean))?

--[[
	Gets R15 position target with hip height offset

	R15 characters require hip height adjustment because the HumanoidRootPart
	is positioned differently from R6 characters.

	@param rankPositionReference Model - The rank position reference model
	@param characterRootPart BasePart - Character's HumanoidRootPart
	@param humanoid Humanoid - Character's Humanoid
	@return CFrame? - Target position CFrame, or nil if reference not found
]]
local function getR15PositionTarget(rankPositionReference: Model, characterRootPart: BasePart, humanoid: Humanoid): CFrame?
	local r15PositionTarget = rankPositionReference:FindFirstChild("R15")
	if not r15PositionTarget or not r15PositionTarget:IsA("BasePart") then
		return nil
	end

	local r15HeightOffset = humanoid.HipHeight + (characterRootPart.Size.Y * 0.5)
	return r15PositionTarget.CFrame * CFrame.new(0, r15HeightOffset, 0)
end

--[[
	Gets R6 position target

	R6 characters use the position reference directly without offset.

	@param rankPositionReference Model - The rank position reference model
	@return CFrame? - Target position CFrame, or nil if reference not found
]]
local function getR6PositionTarget(rankPositionReference: Model): CFrame?
	local r6PositionTarget = rankPositionReference:FindFirstChild("R6")
	return (r6PositionTarget and r6PositionTarget:IsA("BasePart")) and r6PositionTarget.CFrame or nil
end

--[[
	Positions a character rig at the designated rank location

	Handles both R15 and R6 rigs with appropriate positioning logic.

	@param characterRig Model - The character rig to position
	@param rankPositionReference Model - The rank position reference model
	@return boolean - True if positioning succeeded
]]
function RigPositioner.positionCharacterAtRankLocation(characterRig: Model, rankPositionReference: Model): boolean
	if not characterRig or not characterRig:IsA("Model") or not rankPositionReference or not rankPositionReference:IsA("Model") then
		return false
	end

	if not RigPositioner.safeExecute then
		return false
	end

	return RigPositioner.safeExecute(function()
		local characterHumanoid = characterRig:FindFirstChildOfClass("Humanoid")
		local characterRootPart = characterRig:FindFirstChild("HumanoidRootPart")

		if not characterHumanoid or not characterRootPart then
			return
		end

		local targetCFrame
		if characterHumanoid.RigType == Enum.HumanoidRigType.R15 then
			targetCFrame = getR15PositionTarget(rankPositionReference, characterRootPart, characterHumanoid)
			if targetCFrame then
				characterRig:PivotTo(targetCFrame)
			end
		else
			targetCFrame = getR6PositionTarget(rankPositionReference)
			if targetCFrame then
				characterRootPart.CFrame = targetCFrame
			end
		end
	end)
end

return RigPositioner