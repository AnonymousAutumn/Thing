--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local modules = ReplicatedStorage:WaitForChild("Modules")
local configuration = ReplicatedStorage:WaitForChild("Configuration")

local FormatString = require(modules.Utilities.FormatString)
local UsernameCache = require(modules.Caches.UsernameCache)
local ValidationUtils = require(modules.Utilities.ValidationUtils)
local GameConfig = require(configuration.GameConfig)

local DonationTierCalculator = require(script.Parent.DonationTierCalculator)
type DonationTierInfo = DonationTierCalculator.DonationTierInfo

---------------
-- Constants --
---------------
local TAG = "[DonationFrameFactory]"

local ANONYMOUS_USER_DISPLAY_FORMAT = "<unknown%d>"
local DONATION_ANNOUNCEMENT_FORMAT = "%s has donated %s to %s!"
local PLAYER_AVATAR_HEADSHOT_URL_TEMPLATE = GameConfig.AVATAR_HEADSHOT_URL
local ROBUX_CURRENCY_ICON = GameConfig.ROBUX_ICON_UTF

local DONATION_FADE_IN_ANIMATION = TweenInfo.new(0.5)

local STANDARD_FRAME_BASE_LAYOUT_ORDER = 1

-----------
-- Types --
-----------
export type TweenTracker = (Tween) -> ()
export type CountdownCompletionHandler = (CanvasGroup) -> ()

-----------
-- Module --
-----------
local DonationFrameFactory = {}

--[[
	Retrieves player username from user ID

	@param playerUserId number - User ID
	@return string - Username or anonymous placeholder
]]
local function retrievePlayerUsernameFromId(playerUserId: number): string
	if not ValidationUtils.isValidUserId(playerUserId) then
		warn(string.format("%s Invalid user ID: %s", TAG, tostring(playerUserId)))
		return string.format(ANONYMOUS_USER_DISPLAY_FORMAT, playerUserId)
	end

	return UsernameCache.getUsername(playerUserId)
end

--[[
	Generates the donation announcement text

	@param donorUserId number - Donor's user ID
	@param recipientUserId number - Recipient's user ID
	@param donationAmount number - Amount donated
	@return string - Formatted announcement text
]]
local function generateDonationAnnouncementText(donorUserId: number, recipientUserId: number, donationAmount: number): string
	local donorName = retrievePlayerUsernameFromId(donorUserId)
	local recipientName = retrievePlayerUsernameFromId(recipientUserId)
	local formattedAmount = ROBUX_CURRENCY_ICON .. FormatString.formatNumberWithThousandsSeparatorCommas(donationAmount)
	return string.format(DONATION_ANNOUNCEMENT_FORMAT, donorName, formattedAmount, recipientName)
end

--[[
	Configures a text label with tier color and announcement text

	@param textLabel Instance - TextLabel to configure
	@param tierInfo DonationTierInfo - Tier information
	@param announcementText string - Text to display
]]
local function configureTextLabel(textLabel: Instance, tierInfo: DonationTierInfo, announcementText: string): ()
	if not (textLabel and textLabel:IsA("TextLabel")) then
		return
	end
	local lbl = textLabel :: TextLabel
	lbl.TextColor3 = tierInfo.Color
	lbl.Text = announcementText
end

--[[
	Configures an avatar icon with user headshot

	@param avatarIcon Instance - ImageLabel to configure
	@param userId number - User ID for headshot
]]
local function configureAvatarIcon(avatarIcon: Instance, userId: number): ()
	if not (avatarIcon and avatarIcon:IsA("ImageLabel")) then
		return
	end
	(avatarIcon :: ImageLabel).Image = string.format(PLAYER_AVATAR_HEADSHOT_URL_TEMPLATE, userId)
end

--[[
	Configures donation display frame with text, avatars, and fade-in animation

	@param donationFrame CanvasGroup - Frame to configure
	@param donorUserId number - Donor's user ID
	@param recipientUserId number - Recipient's user ID
	@param donationAmount number - Amount donated
	@param tierInfo DonationTierInfo - Tier information
	@param trackTween TweenTracker - Function to track tweens
]]
local function configureDonationDisplayFrame(
	donationFrame: CanvasGroup,
	donorUserId: number,
	recipientUserId: number,
	donationAmount: number,
	tierInfo: DonationTierInfo,
	trackTween: TweenTracker
): ()
	local announcementTextLabel = donationFrame:FindFirstChild("TextLabel")
	local donorAvatarIcon = donationFrame:FindFirstChild("DonorIcon")
	local recipientAvatarIcon = donationFrame:FindFirstChild("ReceiverIcon")

	local announcementText = generateDonationAnnouncementText(donorUserId, recipientUserId, donationAmount)
	configureTextLabel(announcementTextLabel, tierInfo, announcementText)
	configureAvatarIcon(donorAvatarIcon, donorUserId)
	configureAvatarIcon(recipientAvatarIcon, recipientUserId)

	-- Fade-in animation
	local fadeInAnimation = TweenService:Create(donationFrame, DONATION_FADE_IN_ANIMATION, { GroupTransparency = 0 })
	trackTween(fadeInAnimation)
	fadeInAnimation:Play()
end

--[[
	Configures countdown bar color

	@param countdownBarMain Instance - Main countdown bar frame
	@param tierInfo DonationTierInfo - Tier information
]]
local function configureCountdownBar(countdownBarMain: Instance, tierInfo: DonationTierInfo): ()
	if countdownBarMain and countdownBarMain:IsA("Frame") then
		(countdownBarMain :: Frame).BackgroundColor3 = tierInfo.Color
	end
end

--[[
	Creates countdown bar animation tween

	@param countdownBarFrame Instance - Countdown bar frame
	@param tierInfo DonationTierInfo - Tier information
	@param trackTween TweenTracker - Function to track tweens
	@return Tween? - Created tween or nil
]]
local function createCountdownBarAnimation(
	countdownBarFrame: Instance,
	tierInfo: DonationTierInfo,
	trackTween: TweenTracker
): Tween?
	if not (countdownBarFrame and countdownBarFrame:IsA("Frame")) then
		return nil
	end
	local frame = countdownBarFrame :: Frame
	local countdownBarAnimationInfo = TweenInfo.new(tierInfo.Lifetime, Enum.EasingStyle.Linear)
	local countdownBarAnimation = TweenService:Create(frame, countdownBarAnimationInfo, { Size = UDim2.new(0, 0, 0, 5) })
	trackTween(countdownBarAnimation)
	return countdownBarAnimation
end

--[[
	Sets up countdown completion handler

	@param countdownBarAnimation Tween - Countdown animation
	@param donationFrame CanvasGroup - Donation frame
	@param onCompletion CountdownCompletionHandler - Completion callback
	@param trackConnection (RBXScriptConnection) -> () - Function to track connections
]]
local function setupCountdownCompletionHandler(
	countdownBarAnimation: Tween,
	donationFrame: CanvasGroup,
	onCompletion: CountdownCompletionHandler,
	trackConnection: (RBXScriptConnection) -> ()
): ()
	local connection: RBXScriptConnection? = nil
	connection = countdownBarAnimation.Completed:Connect(function()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		onCompletion(donationFrame)
	end)
	if connection then
		trackConnection(connection)
	end
end

--[[
	Calculates frame layout order based on donation type and amount

	@param isLargeDonation boolean - Whether this is a large donation
	@param donationAmount number - Amount donated
	@return number - Layout order value
]]
function DonationFrameFactory.calculateLayoutOrder(isLargeDonation: boolean, donationAmount: number): number
	return if isLargeDonation then -donationAmount else STANDARD_FRAME_BASE_LAYOUT_ORDER
end

--[[
	Creates and configures a donation frame

	@param liveDonationPrefab Instance - Template to clone
	@param donorUserId number - Donor's user ID
	@param recipientUserId number - Recipient's user ID
	@param donationAmount number - Amount donated
	@param tierInfo DonationTierInfo - Tier information
	@param isLargeDonation boolean - Whether this is a large donation
	@param trackTween TweenTracker - Function to track tweens
	@return CanvasGroup - Configured donation frame
]]
function DonationFrameFactory.createFrame(
	liveDonationPrefab: Instance,
	donorUserId: number,
	recipientUserId: number,
	donationAmount: number,
	tierInfo: DonationTierInfo,
	isLargeDonation: boolean,
	trackTween: TweenTracker
): CanvasGroup
	local newDonationFrame = liveDonationPrefab:Clone() :: CanvasGroup
	newDonationFrame.LayoutOrder = DonationFrameFactory.calculateLayoutOrder(isLargeDonation, donationAmount)
	newDonationFrame.GroupTransparency = 1 -- start invisible for fade-in

	configureDonationDisplayFrame(newDonationFrame, donorUserId, recipientUserId, donationAmount, tierInfo, trackTween)

	return newDonationFrame
end

--[[
	Sets up large donation display with countdown bar

	@param donationFrame CanvasGroup - Donation frame
	@param tierInfo DonationTierInfo - Tier information
	@param onCountdownComplete CountdownCompletionHandler - Countdown completion callback
	@param trackTween TweenTracker - Function to track tweens
	@param trackConnection (RBXScriptConnection) -> () - Function to track connections
	@return boolean - True if setup successful
]]
function DonationFrameFactory.setupLargeDonationCountdown(
	donationFrame: CanvasGroup,
	tierInfo: DonationTierInfo,
	onCountdownComplete: CountdownCompletionHandler,
	trackTween: TweenTracker,
	trackConnection: (RBXScriptConnection) -> ()
): boolean
	local countdownBarFrame = donationFrame:FindFirstChild("BarFrame")
	if not countdownBarFrame then
		warn(TAG .. " BarFrame not found in donation template")
		return false
	end

	local countdownBarMain = countdownBarFrame:FindFirstChild("Main")
	if not countdownBarMain then
		warn(TAG .. " Main bar not found in BarFrame")
		return false
	end

	if countdownBarFrame:IsA("Frame") then
		countdownBarFrame.Visible = true
	end
	configureCountdownBar(countdownBarMain, tierInfo)

	-- Create and execute countdown bar animation
	local countdownBarAnimation = createCountdownBarAnimation(countdownBarFrame, tierInfo, trackTween)
	if countdownBarAnimation then
		setupCountdownCompletionHandler(countdownBarAnimation, donationFrame, onCountdownComplete, trackConnection)
		countdownBarAnimation:Play()
		return true
	end

	return false
end

return DonationFrameFactory