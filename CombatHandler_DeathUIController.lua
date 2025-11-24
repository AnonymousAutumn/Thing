--!strict

--[[
	DeathUIController Module

	Displays animated death UI when player is eliminated in combat.
	Returns a function that displays the death UI animation.

	Usage:
		DeathUIController(guiTemplate, player)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found")
local TweenHelper = require(Modules.Utilities.TweenHelper)

-- Track last animation start per player so newer ones cancel older ones for that player
local lastShownAtByUserId: { [number]: number } = {}

-- Timing constants
local DURATION = {
	FadeIn = 0.2,
	MoveCenter = 0.2,
	Widen = 0.2,
	Hold = 3,
	FadeOut = 0.25,
	AnimationDelay = 0.2, -- Delay between animation stages
	ColorTransition = 0.2, -- Duration for background color change
}

-- Helpers
local function isValid(instance: Instance?): boolean
	return instance ~= nil and instance.Parent ~= nil
end

return function(guiTemplate: ScreenGui, targetPlayer: Player)
	task.spawn(function()
		-- Validate PlayerGui
		local playerGui = targetPlayer:FindFirstChild("PlayerGui") or targetPlayer:WaitForChild("PlayerGui", 5)
		if not playerGui then
			return
		end

		-- Clone and parent UI
		local guiClone = guiTemplate:Clone()
		guiClone.Parent = playerGui

		-- Resolve required descendants with type guards
		local banner = guiClone:FindFirstChild("LevelUpBanner")
		local vigilante = guiClone:FindFirstChild("Vigilante")
		local levelUpText = banner and banner:FindFirstChild("LevelUpText")

		if not (banner and vigilante and levelUpText) then
			guiClone:Destroy()
			return
		end
		if not (banner:IsA("Frame") and vigilante:IsA("ImageLabel") and levelUpText:IsA("TextLabel")) then
			guiClone:Destroy()
			return
		end

		local userId = targetPlayer.UserId
		local animationStartTime = os.clock()
		lastShownAtByUserId[userId] = animationStartTime

		local function abortIfStale(): boolean
			if lastShownAtByUserId[userId] ~= animationStartTime then
				if isValid(guiClone) then
					guiClone:Destroy()
				end
				return true
			end
			return false
		end

		-- Initial state: start off-screen left, thin, white, hidden text, hidden image
		banner.Position = UDim2.fromScale(-1.5, 0.5)
		banner.BackgroundColor3 = Color3.new(1, 1, 1)
		banner.Size = UDim2.fromScale(1.2, 0.015)
		banner.BackgroundTransparency = 0

		vigilante.ImageTransparency = 1
		levelUpText.Visible = false
		levelUpText.TextTransparency = 0

		-- Fade in the ?vigilante? image
		TweenHelper.play(vigilante, TweenInfo.new(DURATION.FadeIn), { ImageTransparency = 0 })

		-- Move banner to center
		TweenHelper.playAsync(banner, TweenInfo.new(DURATION.MoveCenter), {
			Position = UDim2.fromScale(0.5, 0.5),
		})

		task.wait(DURATION.AnimationDelay)
		if abortIfStale() then
			return
		end

		-- Widen banner with slight ?back? ease
		TweenHelper.playAsync(banner, TweenInfo.new(DURATION.Widen, Enum.EasingStyle.Back), {
			Size = UDim2.fromScale(1.2, 0.25),
		})
		if abortIfStale() then
			return
		end

		-- Reveal text
		levelUpText.Visible = true

		-- Background becomes red and slightly transparent
		TweenHelper.play(banner, TweenInfo.new(DURATION.ColorTransition), {
			BackgroundColor3 = Color3.fromRGB(255, 0, 0),
			BackgroundTransparency = 0.45,
		})

		-- Hold on screen
		task.wait(DURATION.Hold)
		if abortIfStale() then
			return
		end

		-- Fade everything out
		local fadeBanner = TweenHelper.play(banner, TweenInfo.new(DURATION.FadeOut), { BackgroundTransparency = 1 })
		TweenHelper.play(vigilante, TweenInfo.new(DURATION.FadeOut), { ImageTransparency = 1 })
		TweenHelper.play(levelUpText, TweenInfo.new(DURATION.FadeOut), { TextTransparency = 1 })

		-- Clean up after fade completes
		fadeBanner.Completed:Wait()
		if isValid(guiClone) then
			guiClone:Destroy()
		end
	end)
end