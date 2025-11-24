--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

----------------
-- References --
----------------
local modules = ReplicatedStorage:WaitForChild("Modules")
local configuration = ReplicatedStorage:WaitForChild("Configuration")

local GameConfig = require(configuration.GameConfig)
local ResourceCleanup = require(modules.Wrappers.ResourceCleanup)

-- Submodules
local DonationTierCalculator = require(script.DonationTierCalculator)
local DonationFrameManager = require(script.DonationFrameManager)
local DonationFrameFactory = require(script.DonationFrameFactory)
local CrossServerBridge = require(script.CrossServerBridge)

type DonationTierInfo = DonationTierCalculator.DonationTierInfo
type DonationNotificationData = CrossServerBridge.DonationNotificationData

local instances = ReplicatedStorage:WaitForChild("Instances")
local guiPrefabs = instances:WaitForChild("GuiPrefabs")
local liveDonationPrefab = guiPrefabs:WaitForChild("LiveDonationPrefab")

local leaderboardsFolder = Workspace:WaitForChild("Leaderboards")
local liveDonationLeaderboard = leaderboardsFolder:WaitForChild(script.Name)
local leaderboardSurfaceGui = liveDonationLeaderboard:WaitForChild("SurfaceGui")
local leaderboardMainFrame = leaderboardSurfaceGui:WaitForChild("MainFrame")
local donationScrollingFrame = leaderboardMainFrame:WaitForChild("ScrollingFrame")
local largeDonationDisplayFrame = donationScrollingFrame:WaitForChild("DistinctFrame")
local standardDonationDisplayFrame = donationScrollingFrame:WaitForChild("NormalFrame")

---------------
-- Constants --
---------------
local TAG = "[LiveDonationLeaderboard]"
local DEFAULT_DONATION_DISPLAY_DURATION = GameConfig.LIVE_DONATION_CONFIG.DEFAULT_LIFETIME

---------------
-- Variables --
---------------
local resourceManager = ResourceCleanup.new()
local frameManager: any = nil
local crossServerBridge: any = nil
local isShuttingDown = false

-------------
-- Logging --
-------------
local function info(fmt: string, ...): ()
	print(TAG .. " " .. string.format(fmt, ...))
end

local function warnlog(fmt: string, ...): ()
	warn(TAG .. " " .. string.format(fmt, ...))
end

---------------
-- Utilities --
---------------
local function trackConnection(connection: RBXScriptConnection): RBXScriptConnection
	return resourceManager:trackConnection(connection)
end

local function trackTween(tween: Tween): Tween
	return resourceManager:trackTween(tween)
end

local function cleanupAllResources(): ()
	resourceManager:cleanupAll()
end

-------------------------------
-- Countdown Completion Logic --
-------------------------------
local function handleCountdownCompletion(donationFrame: CanvasGroup): ()
	-- Remove from large tracking
	frameManager:removeFromTracking(donationFrame, "large")

	-- Transition to standard display
	frameManager:adjustLayoutOrdering("Normal")
	donationFrame.LayoutOrder = 1

	-- Enforce standard frame limit
	local _, maxStandardFrames = DonationFrameManager.getMaxLimits()
	frameManager:enforceLimit("standard", maxStandardFrames)

	donationFrame.Parent = frameManager:getStandardContainer()
	frameManager:addStandardFrame(donationFrame)

	-- Schedule cleanup
	frameManager:scheduleCleanup(donationFrame, "standard", DEFAULT_DONATION_DISPLAY_DURATION)
end

--------------------------
-- Donation Display Logic --
--------------------------
local function setupLargeDonationDisplay(
	donationFrame: CanvasGroup,
	tierInfo: DonationTierInfo
): ()
	-- Setup countdown bar and animation
	local setupSuccess = DonationFrameFactory.setupLargeDonationCountdown(
		donationFrame,
		tierInfo,
		handleCountdownCompletion,
		trackTween,
		trackConnection
	)

	if not setupSuccess then
		warnlog("Failed to setup large donation countdown")
		return
	end

	-- Enforce frame limit before adding new frame
	local maxLargeFrames, _ = DonationFrameManager.getMaxLimits()
	frameManager:enforceLimit("large", maxLargeFrames)

	donationFrame.Parent = frameManager:getLargeContainer()
	frameManager:addLargeFrame(donationFrame)
end

local function setupStandardDonationDisplay(donationFrame: CanvasGroup): ()
	-- Enforce frame limit before adding new frame
	local _, maxStandardFrames = DonationFrameManager.getMaxLimits()
	frameManager:enforceLimit("standard", maxStandardFrames)

	donationFrame.Parent = frameManager:getStandardContainer()
	frameManager:addStandardFrame(donationFrame)

	-- Schedule cleanup
	frameManager:scheduleCleanup(donationFrame, "standard", DEFAULT_DONATION_DISPLAY_DURATION)
end

local function createAndDisplayDonationFrame(
	donorUserId: number,
	recipientUserId: number,
	donationAmount: number,
	tierInfo: DonationTierInfo,
	isLargeDonation: boolean
): ()
	local newDonationFrame = DonationFrameFactory.createFrame(
		liveDonationPrefab,
		donorUserId,
		recipientUserId,
		donationAmount,
		tierInfo,
		isLargeDonation,
		trackTween
	)

	if isLargeDonation then
		setupLargeDonationDisplay(newDonationFrame, tierInfo)
	else
		setupStandardDonationDisplay(newDonationFrame)
	end
end

--------------------------
-- Donation Processing  --
--------------------------
local function processDonationNotification(donationNotificationData: DonationNotificationData): ()
	if isShuttingDown then
		return
	end
	if not CrossServerBridge.validateDonationData(donationNotificationData) then
		return
	end

	local tierInfo = DonationTierCalculator.determineTierInfo(donationNotificationData.Amount)
	local isHighTier = DonationTierCalculator.isHighTier(tierInfo)

	if isHighTier then
		createAndDisplayDonationFrame(
			donationNotificationData.Donor,
			donationNotificationData.Receiver,
			donationNotificationData.Amount,
			tierInfo,
			true
		)
	else
		frameManager:adjustLayoutOrdering("Normal")
		createAndDisplayDonationFrame(
			donationNotificationData.Donor,
			donationNotificationData.Receiver,
			donationNotificationData.Amount,
			tierInfo,
			false
		)
	end
end

--------------------
-- Initialization --
--------------------
local function initialize(): ()
	-- Create frame manager
	frameManager = DonationFrameManager.new(largeDonationDisplayFrame, standardDonationDisplayFrame)

	-- Create cross-server bridge
	crossServerBridge = CrossServerBridge.new()

	-- Subscribe to cross-server donations
	local subscribed = crossServerBridge:subscribe(processDonationNotification)
	if not subscribed then
		warnlog("Failed to subscribe to cross-server donations")
	end

	-- Start frame cleanup loop
	frameManager:startCleanupLoop()

	info("Initialized successfully")
end

-------------
-- Cleanup --
-------------
local function cleanup(): ()
	isShuttingDown = true

	info("Shutting down live donation leaderboard...")

	-- Shutdown frame manager
	if frameManager then
		frameManager:shutdown()
		frameManager:destroyAll()
	end

	-- Shutdown cross-server bridge
	if crossServerBridge then
		crossServerBridge:shutdown()
	end

	-- Cleanup connections and tweens
	cleanupAllResources()
end

-- Initialize the live donation display system
initialize()

-- Bind cleanup to game shutdown
game:BindToClose(cleanup)