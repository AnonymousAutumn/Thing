--!strict

--[[
	StandsContainer Script

	Client-side stand UI management and display.
	Handles stand UI creation, button setup, and purchase flows.

	Returns: Nothing (client-side script)

	Usage: Runs automatically when placed in game
]]

--------------
-- Services --
--------------
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

----------------
-- References --
----------------

local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network") :: Folder
local bindables = assert(network:WaitForChild("Bindables", 10), "Failed to find Bindables")
local bindableEvents = assert(bindables:WaitForChild("Events", 10), "Failed to find bindable Events")
local remotes = assert(network:WaitForChild("Remotes", 10), "Failed to find Remotes")
local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Failed to find remote Events")
local unclaimStand = assert(remoteEvents:WaitForChild("UnclaimStand", 10), "Failed to find UnclaimStand")
local refreshStand = assert(remoteEvents:WaitForChild("RefreshStand", 10), "Failed to find RefreshStand")
local sendNotificationEvent = assert(bindableEvents:WaitForChild("CreateNotification", 10), "Failed to find CreateNotification")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Failed to find Configuration")

local GamepassCacheManager = require(assert(Modules:WaitForChild("Caches", 10):WaitForChild("PassCache", 10), "Failed to find PassCache"))
local ButtonWrapper = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("Buttons", 10), "Failed to find Buttons"))
local PurchaseWrapper = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("Purchases", 10), "Failed to find Purchases"))
local NotificationHelper = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("NotificationHelper", 10), "Failed to find NotificationHelper"))
local InputCategorizer = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("InputCategorizer", 10), "Failed to find InputCategorizer"))
local FormatString = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("FormatString", 10), "Failed to find FormatString"))
local GameConfig = require(assert(Configuration:WaitForChild("GameConfig", 10), "Failed to find GameConfig"))

local instances: Folder = assert(ReplicatedStorage:WaitForChild("Instances", 10), "Failed to find Instances")
local guiPrefabs = assert(instances:WaitForChild("GuiPrefabs", 10), "Failed to find GuiPrefabs")
local standUIPrefab = assert(guiPrefabs:WaitForChild("StandUIPrefab", 10), "Failed to find StandUIPrefab")
local passButtonPrefab = assert(guiPrefabs:WaitForChild("PassButtonPrefab", 10), "Failed to find PassButtonPrefab")

local uiSounds = assert(SoundService:WaitForChild("UI", 10), "Failed to find UI sounds")
local feedbackSounds = assert(SoundService:WaitForChild("Feedback", 10), "Failed to find Feedback sounds")

---------------
-- Variables --
---------------
local player = Players.LocalPlayer
local playerStandUIs = {} -- [standModel] = cloned SurfaceGui

--------------------
-- Private Functions
--------------------

-- Handle gamepass purchase attempt using shared handler
local function handlePurchase(button)
	local assetId = button:GetAttribute("AssetId")

	PurchaseWrapper.attemptPurchase({
		player = player,
		assetId = assetId,
		isDevProduct = false,
		sounds = {
			click = uiSounds.Click,
			error = feedbackSounds.Error,
		},
		onError = function(errorType, message)
			NotificationHelper.sendWarning(sendNotificationEvent, message)
		end,
	})
end

local function setupAllButtons(frame)
	ButtonWrapper.setupAllButtons(
		frame,
		handlePurchase,
		{ hover = uiSounds.Hover },
		nil, -- no connection tracker needed
		true -- watch for new buttons
	)
end

local function handleSurfaceGui(surfaceGui)
	if not surfaceGui:IsA("SurfaceGui") then
		return
	end
	local itemFrame = surfaceGui:FindFirstChild("ItemFrame", true)
	if not itemFrame then
		return
	end

	local layout = itemFrame:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		local function updateCanvas()
			pcall(function()
				itemFrame.CanvasSize = UDim2.new(0, layout.AbsoluteContentSize.X, 0, layout.AbsoluteContentSize.Y)
			end)
		end
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
		updateCanvas()
	end

	setupAllButtons(itemFrame)
end

-- Populate / Refresh Stand UI
local function populateStandUI(standModel, gamepasses, remove)
	if remove then
		local existingUI = playerStandUIs[standModel]
		if existingUI then
			existingUI:Destroy()
			playerStandUIs[standModel] = nil
		end
		return
	end

	if not standModel then
		return
	end

	if playerStandUIs[standModel] then
		playerStandUIs[standModel]:Destroy()
		playerStandUIs[standModel] = nil
	end

	local templateGui = standUIPrefab:Clone()
	templateGui.Name = "StandUI_" .. player.Name
	templateGui.Adornee = standModel:FindFirstChild("PassesHolder")
	templateGui.Parent = script.Parent

	playerStandUIs[standModel] = templateGui

	local itemFrame = templateGui:FindFirstChild("ItemFrame", true)
	if itemFrame and gamepasses then
		for _, pass in ipairs(gamepasses) do
			local formattedPrice = FormatString.formatNumberWithThousandsSeparatorCommas(pass.Price)
			local passTemplate = passButtonPrefab:Clone()
			passTemplate:SetAttribute("AssetId", pass.Id)
			passTemplate.Name = pass.Name
			passTemplate.LayoutOrder = pass.Price
			passTemplate.ItemPrice.Text = "<font color='#ffb46a'>"
				.. GameConfig.ROBUX_ICON_UTF
				.. "</font> "
				.. formattedPrice
			passTemplate.ItemIcon.Image = pass.Icon or ""
			passTemplate.Parent = itemFrame
		end
	end

	handleSurfaceGui(templateGui)
end

--------------
-- Events --
--------------
-- Initialize UI button handler with device detection
ButtonWrapper.initialize(InputCategorizer)

-- RemoteEvent listeners
unclaimStand.OnClientEvent:Connect(function(standModel, gamepasses, remove)
	if gamepasses and typeof(gamepasses) ~= "table" then
		gamepasses = {}
	end
	populateStandUI(standModel, gamepasses, remove)
end)

refreshStand.OnClientEvent:Connect(function(standModel, gamepasses, remove)
	if gamepasses and typeof(gamepasses) ~= "table" then
		gamepasses = {}
	end
	populateStandUI(standModel, gamepasses, remove)
end)