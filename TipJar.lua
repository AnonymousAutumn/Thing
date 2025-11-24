--!strict

--[[
	TipJar Tool Script

	Manages tip jar tool interactions and UI toggling.
	Handles tool equip/unequip, proximity prompt triggers, and player visibility.

	Returns: Nothing (tool script)

	Usage: Attached to a Tool instance in StarterPack or player backpack
]]

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

---------------
-- Constants --
---------------
local TAG = "[TipJar]"

local ATTRIBUTE_PROMPTS_DISABLED = "PromptsDisabled"
local ATTRIBUTE_SHOULD_HIDE_UI = "ShouldHideUI"

-- Debounce configuration (disabled by default to preserve current behavior)
local CONFIG = {
	ENABLE_PROMPT_DEBOUNCE = true, -- set true to enable
	DEBOUNCE_MODE = "player",       -- "player" or "tool"
	DEBOUNCE_DURATION_SEC = 1.25,   -- seconds
}

-----------
-- Types --
-----------
type UIViewingData = {
	Viewer: Player?,
	Viewing: Player?,
	Visible: boolean,
}

----------------
-- References --
----------------

local network : Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Failed to find Network") :: Folder
local bindables = assert(network:WaitForChild("Bindables", 10), "Failed to find Bindables") :: Folder
local bindableEvents = assert(bindables:WaitForChild("Events", 10), "Failed to find bindable Events")
local toggleUIEvent = assert(bindableEvents:WaitForChild("ToggleUI", 10), "Failed to find ToggleUI") :: RemoteEvent

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Failed to find Modules")
local ValidationUtils = require(assert(Modules:WaitForChild("Utilities", 10):WaitForChild("ValidationUtils", 10), "Failed to find ValidationUtils"))
local ResourceCleanup = require(assert(Modules:WaitForChild("Wrappers", 10):WaitForChild("ResourceCleanup", 10), "Failed to find ResourceCleanup"))

local interactableToolInstance = script.Parent :: Tool
local toolPhysicalHandle = assert(interactableToolInstance:WaitForChild("Handle", 10), "Failed to find Handle") :: BasePart
local toolInteractionProximityPrompt = assert(toolPhysicalHandle:WaitForChild("ProximityPrompt", 10), "Failed to find ProximityPrompt") :: ProximityPrompt

---------------
-- Variables --
---------------
local currentToolOwnerPlayer: Player? = nil
local resourceManager = ResourceCleanup.new()

-- Debounce state
local playerCooldownUntil: { [number]: number } = {}
local toolCooldownUntil: number? = nil

---------------
-- Helpers  --
---------------
local function log(fmt: string, ...): ()
	print(TAG .. " " .. string.format(fmt, ...))
end

local function warnlog(fmt: string, ...): ()
	warn(TAG .. " " .. string.format(fmt, ...))
end

local function triggerUserInterfaceToggle(uiViewingData: UIViewingData): ()
	local success, errorMessage = pcall(function()
		toggleUIEvent:Fire(uiViewingData)
	end)
	if not success then
		warnlog("Failed to toggle UI: %s", tostring(errorMessage))
	end
end

local function getToolOwner(): Player?
	local parentInstance = interactableToolInstance.Parent
	if not parentInstance then
		return nil
	end
	return Players:GetPlayerFromCharacter(parentInstance)
end

-- Debounce checks
local function now(): number
	return os.clock()
end

local function isDebouncedForPlayer(player: Player): boolean
	if not CONFIG.ENABLE_PROMPT_DEBOUNCE or CONFIG.DEBOUNCE_MODE ~= "player" then
		return false
	end
	local untilTime = playerCooldownUntil[player.UserId]
	return untilTime ~= nil and now() < untilTime
end

local function markPlayerDebounced(player: Player): ()
	if not CONFIG.ENABLE_PROMPT_DEBOUNCE or CONFIG.DEBOUNCE_MODE ~= "player" then
		return
	end
	playerCooldownUntil[player.UserId] = now() + CONFIG.DEBOUNCE_DURATION_SEC
end

local function isDebouncedForTool(): boolean
	if not CONFIG.ENABLE_PROMPT_DEBOUNCE or CONFIG.DEBOUNCE_MODE ~= "tool" then
		return false
	end
	return toolCooldownUntil ~= nil and now() < (toolCooldownUntil :: number)
end

local function markToolDebounced(): ()
	if not CONFIG.ENABLE_PROMPT_DEBOUNCE or CONFIG.DEBOUNCE_MODE ~= "tool" then
		return
	end
	toolCooldownUntil = now() + CONFIG.DEBOUNCE_DURATION_SEC
end

local function clearDebounceState(): ()
	table.clear(playerCooldownUntil)
	toolCooldownUntil = nil
end

---------------
-- Handlers  --
---------------
local function handleToolEquippedByPlayer(): ()
	local owner = getToolOwner()
	if not ValidationUtils.isValidPlayer(owner) then
		return
	end

	currentToolOwnerPlayer = owner

	triggerUserInterfaceToggle({
		Viewer = owner,
		Viewing = nil,
		Visible = true,
	})
end

local function handleToolUnequippedByPlayer(): ()
	if currentToolOwnerPlayer then
		triggerUserInterfaceToggle({
			Viewer = currentToolOwnerPlayer,
			Viewing = nil,
			Visible = false,
		})
	end
	currentToolOwnerPlayer = nil
end

local function unequipCurrentToolIfAny(triggeringPlayer: Player): ()
	local character = triggeringPlayer.Character or triggeringPlayer.CharacterAdded:Wait()
	if not character then
		return
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool then
		local backpack = triggeringPlayer:FindFirstChildOfClass("Backpack")
			or triggeringPlayer:FindFirstChild("Backpack")
		if backpack then
			equippedTool.Parent = backpack
		end
	end
end

local function handleProximityPromptTriggeredByPlayer(triggeringPlayer: Player): ()
	if not ValidationUtils.isValidPlayer(triggeringPlayer) then
		return
	end
	if triggeringPlayer:GetAttribute(ATTRIBUTE_PROMPTS_DISABLED) then
		return
	end

	-- Debounce gate
	if CONFIG.DEBOUNCE_MODE == "player" and isDebouncedForPlayer(triggeringPlayer) then
		return
	elseif CONFIG.DEBOUNCE_MODE == "tool" and isDebouncedForTool() then
		return
	end

	-- Mark debounced immediately
	if CONFIG.DEBOUNCE_MODE == "player" then
		markPlayerDebounced(triggeringPlayer)
	elseif CONFIG.DEBOUNCE_MODE == "tool" then
		markToolDebounced()
	end

	task.spawn(function()
		-- Ensure player isn't holding another tool (avoids dual-tool UX conflicts)
		unequipCurrentToolIfAny(triggeringPlayer)

		-- Let client-side systems hide unrelated UIs if needed
		triggeringPlayer:SetAttribute(ATTRIBUTE_SHOULD_HIDE_UI, true)

		-- Open Tip UI: viewer is the triggering player; viewing is the current tool owner
		triggerUserInterfaceToggle({
			Viewer = triggeringPlayer,
			Viewing = currentToolOwnerPlayer,
			Visible = true,
		})
	end)
end

-------------
-- Cleanup --
-------------
local function cleanup(): ()
	resourceManager:cleanupAll()
	clearDebounceState()
	currentToolOwnerPlayer = nil
end

--------------------
-- Initialization --
--------------------
resourceManager:trackConnection(interactableToolInstance.Equipped:Connect(handleToolEquippedByPlayer))
resourceManager:trackConnection(interactableToolInstance.Unequipped:Connect(handleToolUnequippedByPlayer))
resourceManager:trackConnection(toolInteractionProximityPrompt.Triggered:Connect(handleProximityPromptTriggeredByPlayer))

-- Cleanup if the tool is removed from the game
resourceManager:trackConnection(interactableToolInstance.AncestryChanged:Connect(function()
	if not interactableToolInstance:IsDescendantOf(game) then
		cleanup()
	end
end))