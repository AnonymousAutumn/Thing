--!strict

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

local network: Folder = ReplicatedStorage:WaitForChild("Network") :: Folder
local bindables = network:WaitForChild("Bindables")
local bindableEvents = bindables:WaitForChild("Events")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")
local unclaimStand = remoteEvents:WaitForChild("UnclaimStand")
local refreshStand = remoteEvents:WaitForChild("RefreshStand")
local sendNotificationEvent = bindableEvents:WaitForChild("CreateNotification")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")

local GamepassCacheManager = require(Modules.Caches.PassCache)
local ButtonWrapper = require(Modules.Wrappers.Buttons)
local PurchaseWrapper = require(Modules.Wrappers.Purchases)
local NotificationHelper = require(Modules.Utilities.NotificationHelper)
local InputCategorizer = require(Modules.Utilities.InputCategorizer)
local FormatString = require(Modules.Utilities.FormatString)
local GameConfig = require(Configuration.GameConfig)

local instances: Folder = ReplicatedStorage:WaitForChild("Instances")
local guiPrefabs = instances:WaitForChild("GuiPrefabs")
local standUIPrefab = guiPrefabs:WaitForChild("StandUIPrefab")
local passButtonPrefab = guiPrefabs:WaitForChild("PassButtonPrefab")

local uiSounds = SoundService:WaitForChild("UI")
local feedbackSounds = SoundService:WaitForChild("Feedback")

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