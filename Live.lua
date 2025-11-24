--!strict

--[[
	Live Donation Leaderboard System

	This module manages the live donation display leaderboard, showing real-time donation
	notifications with tiered visual effects. Handles cross-server donation notifications,
	frame animations, and automatic cleanup of donation displays.

	Returns: nil (auto-initializes on require)

	Usage:
		Simply require this module to start the live donation display system.
		The system will automatically:
		- Subscribe to cross-server donation events
		- Display donations in tiered frames (large/standard)
		- Manage frame lifecycle and cleanup
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

----------------
-- References --
----------------
local modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules in ReplicatedStorage")
local configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Failed to find Configuration in ReplicatedStorage")

local GameConfig = require(configuration.GameConfig)
local ResourceCleanup = require(modules.Wrappers.ResourceCleanup)

-- Submodules
local DonationTierCalculator = require(script.DonationTierCalculator)
local DonationFrameManager = require(script.DonationFrameManager)
local DonationFrameFactory = require(script.DonationFrameFactory)
local CrossServerBridge = require(script.CrossServerBridge)

type DonationTierInfo = DonationTierCalculator.DonationTierInfo
type DonationNotificationData = CrossServerBridge.DonationNotificationData

local instances = assert(ReplicatedStorage:WaitForChild("Instances", 10), "Failed to find Instances in ReplicatedStorage")
local guiPrefabs = assert(instances:WaitForChild("GuiPrefabs", 10), "Failed to find GuiPrefabs in Instances")
local liveDonationPrefab = assert(guiPrefabs:WaitForChild("LiveDonationPrefab", 10), "Failed to find LiveDonationPrefab in GuiPrefabs")

local leaderboardsFolder = assert(Workspace:WaitForChild("Leaderboards", 10), "Failed to find Leaderboards in Workspace")
local liveDonationLeaderboard = assert(leaderboardsFolder:WaitForChild(script.Name, 10), "Failed to find " .. script.Name .. " in Leaderboards")
local leaderboardSurfaceGui = assert(liveDonationLeaderboard:WaitForChild("SurfaceGui", 10), "Failed to find SurfaceGui in LiveDonationLeaderboard")
local leaderboardMainFrame = assert(leaderboardSurfaceGui:WaitForChild("MainFrame", 10), "Failed to find MainFrame in SurfaceGui")
local donationScrollingFrame = assert(leaderboardMainFrame:WaitForChild("ScrollingFrame", 10), "Failed to find ScrollingFrame in MainFrame")
local largeDonationDisplayFrame = assert(donationScrollingFrame:WaitForChild("DistinctFrame", 10), "Failed to find DistinctFrame in ScrollingFrame")
local standardDonationDisplayFrame = assert(donationScrollingFrame:WaitForChild("NormalFrame", 10), "Failed to find NormalFrame in ScrollingFrame")

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