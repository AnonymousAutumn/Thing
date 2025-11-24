--!strict

---------------
-- Constants --
---------------
local CHARACTER_IDLE_ANIMATION_IDS = {
	R15 = "rbxassetid://507766388",
	R6 = "rbxassetid://180435571",
}

-----------
-- Module --
-----------
local AnimationController = {}

-- External dependencies (set by RigCreator)
AnimationController.safeExecute = nil :: (((() -> ()) -> boolean))?

--[[
	Creates and loads an animation on an Animator

	@param animator Animator - The animator instance
	@param animationId string - The animation asset ID
	@return AnimationTrack - The loaded animation track
]]
local function createAndLoadAnimation(animator: Animator, animationId: string): AnimationTrack
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local idleTrack = animator:LoadAnimation(animation)
	idleTrack.Looped = true
	animation:Destroy()
	return idleTrack
end

--[[
	Starts the idle animation for a character humanoid

	Creates an Animator if one doesn't exist, loads the appropriate idle
	animation (R15 or R6), and starts playback.

	@param characterHumanoid Humanoid - The character's Humanoid instance
	@return AnimationTrack? - The playing animation track, or nil on failure
]]
function AnimationController.startCharacterIdleAnimation(characterHumanoid: Humanoid): AnimationTrack?
	if not characterHumanoid or not characterHumanoid:IsA("Humanoid") then
		return nil
	end

	local success, animationTrack = pcall(function()
		local animator = characterHumanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = characterHumanoid
		end

		local rigType = characterHumanoid.RigType
		local idleAnimationId = (rigType == Enum.HumanoidRigType.R15) and CHARACTER_IDLE_ANIMATION_IDS.R15 or CHARACTER_IDLE_ANIMATION_IDS.R6

		local track = createAndLoadAnimation(animator, idleAnimationId)
		track:Play()
		return track
	end)

	return (success and animationTrack and animationTrack:IsA("AnimationTrack")) and animationTrack or nil
end

--[[
	Cleans up an animation track

	Stops the animation if it's playing and destroys the track.

	@param animationTrack AnimationTrack - The animation track to cleanup
]]
function AnimationController.cleanupAnimationTrack(animationTrack: AnimationTrack): ()
	if not animationTrack then
		return
	end

	if not AnimationController.safeExecute then
		return
	end

	AnimationController.safeExecute(function()
		if animationTrack.IsPlaying then
			animationTrack:Stop()
		end
		animationTrack:Destroy()
	end)
end

return AnimationController