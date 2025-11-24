--!strict

--[[
	VisibilityHandler Script

	Client-side player visibility and control management.
	Handles hiding/showing players and enabling/disabling controls during turns.

	Returns: Nothing (client-side script)

	Usage: Runs automatically when placed in game
]]

--------------
-- Services --
--------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----------------
-- References --
----------------

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local ResourceCleanup = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("ResourceCleanup", 10), "Failed to find ResourceCleanup"))

---------------
-- Constants --
---------------

local COMPLETELY_TRANSPARENT = 1
local FULLY_OPAQUE = 0

local COLLISION_DISABLED = false
local RAYCAST_DISABLED = false
local EFFECTS_DISABLED = false

local HIDEABLE_EFFECT_TYPES = {
	ParticleEmitter = true,
	Sparkles = true,
	Smoke = true,
	Fire = true,
	Beam = true,
}

local YOUR_TURN_MESSAGE = "Your turn!"

-----------
-- Types --
-----------

type InstanceState = {
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	Enabled: boolean?,
}

---------------
-- Variables --
---------------

local originalStates: { [Instance]: InstanceState } = {}

local localPlayer = Players.LocalPlayer
local playerControls: any = nil

local resourceManager = ResourceCleanup.new()

---------------
-- Helpers  --
---------------
local function setPropertySafely(instance: Instance, propertyName: string, value: any): boolean
	local success, errorMessage = pcall(function()
		(instance :: any)[propertyName] = value
	end)
	if not success then
		warn(`Failed to set {instance.Name}.{propertyName}: {errorMessage}`)
	end
	return success
end

local function isHideableEffect(instance: Instance): boolean
	return HIDEABLE_EFFECT_TYPES[instance.ClassName] == true
end

-----------------
-- Hide/Restore --
-----------------
local function storeOriginalState(instance: Instance): ()
	if originalStates[instance] then
		return
	end

	local state: InstanceState = {}
	if instance:IsA("BasePart") then
		local part = instance :: BasePart
		state.Transparency = part.Transparency
		state.CanCollide = part.CanCollide
		state.CanQuery = part.CanQuery
	elseif instance:IsA("Decal") then
		local decal = instance :: Decal
		state.Transparency = decal.Transparency
	elseif isHideableEffect(instance) then
		-- Many effects share Enabled property (ParticleEmitter, Sparkles, Smoke, Fire, Beam)
		state.Enabled = (instance :: any).Enabled
	else
		-- Nothing to store for other types
		return
	end

	originalStates[instance] = state
end

local function restoreAllStates(): ()
	for inst, state in pairs(originalStates) do
		if inst and inst.Parent then
			for propertyName, originalValue in pairs(state) do
				setPropertySafely(inst, propertyName, originalValue)
			end
		end
	end
	table.clear(originalStates)
end

local function hideInstance(instance: Instance): ()
	storeOriginalState(instance)

	if instance:IsA("BasePart") then
		setPropertySafely(instance, "Transparency", COMPLETELY_TRANSPARENT)
		setPropertySafely(instance, "CanCollide", COLLISION_DISABLED)
		setPropertySafely(instance, "CanQuery", RAYCAST_DISABLED)
	elseif instance:IsA("Decal") then
		setPropertySafely(instance, "Transparency", COMPLETELY_TRANSPARENT)
	elseif isHideableEffect(instance) then
		setPropertySafely(instance, "Enabled", EFFECTS_DISABLED)
	end
end

local function hideCharacter(character: Model?): ()
	if not character then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") or isHideableEffect(descendant) then
			hideInstance(descendant)
		elseif descendant:IsA("Accessory") then
			local handle = descendant:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				hideInstance(handle)
			end
		end
	end
end

local function showCharacter(_character: Model?): ()
	-- The underlying design restores everything recorded in originalStates,
	-- not just this specific character. Preserve this behavior.
	restoreAllStates()
end

local function forEachPlayerCharacter(action: (Model?) -> ()): ()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			action(player.Character)
		end
	end
end

local function showAllPlayers(): ()
	forEachPlayerCharacter(showCharacter)
end

local function hideAllPlayers(): ()
	forEachPlayerCharacter(hideCharacter)
end

-----------------
-- Controls API --
-----------------
local function enableControls(): ()
	if playerControls and playerControls.Enable then
		playerControls:Enable()
	end
end

local function disableControls(): ()
	if playerControls and playerControls.Disable then
		playerControls:Disable()
	end
end

local function showPlayersAndEnableControls(): ()
	showAllPlayers()
	enableControls()
end

local function hidePlayersAndDisableControls(): ()
	hideAllPlayers()
	disableControls()
end

-------------------------
-- Network Event Logic --
-------------------------
local function onTurnUIUpdate(turnMessage: string?, _turnTimeout: number?, shouldReset: boolean?): ()
	if shouldReset then
		showPlayersAndEnableControls()
	elseif turnMessage == YOUR_TURN_MESSAGE then
		hidePlayersAndDisableControls()
	else
		showPlayersAndEnableControls()
	end
end

--------------------
-- Initialization --
--------------------
local function initializePlayerControls(): ()
	-- PlayerModule is provided by Roblox; protect with pcall
	local playerScripts = assert(localPlayer:WaitForChild("PlayerScripts", 10), "Failed to find PlayerScripts")
	local moduleSuccess, playerModule = pcall(function()
		return playerScripts:WaitForChild("PlayerModule", 10)
	end)
	if not moduleSuccess or not playerModule then
		warn("Failed to access PlayerModule: ", tostring(playerModule))
		return
	end

	local requireSuccess, controlsProvider = pcall(function()
		return require(playerModule)
	end)
	if not requireSuccess or not controlsProvider or not controlsProvider.GetControls then
		warn("Failed to require PlayerModule or GetControls missing")
		return
	end

	local controlsSuccess, controls = pcall(function()
		return controlsProvider:GetControls()
	end)
	if controlsSuccess then
		playerControls = controls
	else
		warn("Failed to get controls: ", tostring(controls))
	end
end

local function initializeNetworkEvents(): ()
	local network : Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network")
	local remotes = assert(network:WaitForChild("Remotes", 10), "Failed to find Remotes")
	local remoteEvents = assert(remotes:WaitForChild("Events", 10), "Failed to find Events")
	local updateGameUIEvent = assert(remoteEvents:WaitForChild("UpdateGameUI", 10), "Failed to find UpdateGameUI")

	resourceManager:trackConnection(updateGameUIEvent.OnClientEvent:Connect(onTurnUIUpdate))
end

initializePlayerControls()
initializeNetworkEvents()

-- Make sure if character respawns while hidden, visibility is restored by default
resourceManager:trackConnection(localPlayer.CharacterAdded:Connect(showAllPlayers))

-- Clean up (restore states and enable controls) if script is removed
resourceManager:trackConnection(script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(game) then
		showPlayersAndEnableControls()
		resourceManager:cleanupAll()
	end
end))