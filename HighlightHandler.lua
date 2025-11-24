--!strict

--[[
	HighlightHandler - Character highlight system

	This script manages visual highlighting of player characters:
	- Creates outline highlights on target characters
	- Handles highlight cleanup on character death/removal
	- Listens for server highlight requests via RemoteEvent
	- Supports both Player instances and userId references

	Returns: Nothing (initializes and runs automatically)

	Usage: This script runs automatically when parented to a character model.
	Server triggers highlights via CreateHighlight RemoteEvent.
]]

--------------
-- Services --
--------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------
-- Constants --
---------------

local TAG = "[HighlightHandler]"
local WAIT_TIMEOUT = 10
local HUMANOID_WAIT_TIMEOUT = 10

----------------
-- References --
----------------

local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", WAIT_TIMEOUT), TAG .. " Network folder not found")
local remotes = assert(network:WaitForChild("Remotes", WAIT_TIMEOUT), TAG .. " Remotes folder not found")
local remoteEvents = assert(remotes:WaitForChild("Events", WAIT_TIMEOUT), TAG .. " Events folder not found")
local createHighlightEvent = assert(remoteEvents:WaitForChild("CreateHighlight", WAIT_TIMEOUT), TAG .. " CreateHighlight event not found")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", WAIT_TIMEOUT), TAG .. " Modules folder not found")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

local HIGHLIGHT_CONFIG = {
	instanceName = "PlayerHighlight",
	fillTransparency = 1,
	outlineColor = Color3.fromRGB(255, 255, 255),
	depthMode = Enum.HighlightDepthMode.AlwaysOnTop,
}

-----------
-- State --
-----------
type State = {
	ownerCharacter: Model,
	ownerHumanoid: Humanoid?,
	activeHighlight: Highlight?,
	resourceManager: any, -- ResourceCleanup.ResourceManager
}

local state: State = {
	ownerCharacter = script.Parent :: Model,
	ownerHumanoid = nil,
	activeHighlight = nil,
	resourceManager = ResourceCleanup.new(),
}

---------------
-- Helpers --
---------------

local function removeActiveHighlight(): ()
	if state.activeHighlight then
		state.activeHighlight:Destroy()
		state.activeHighlight = nil
	end
end

local function createHighlight(targetCharacter: Model): Highlight?
	assert(targetCharacter, "createHighlight: targetCharacter is required")
	assert(targetCharacter:IsA("Model"), "createHighlight: targetCharacter must be a Model")

	if not targetCharacter.Parent then
		return nil
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_CONFIG.instanceName
	highlight.Adornee = targetCharacter
	highlight.FillTransparency = HIGHLIGHT_CONFIG.fillTransparency
	highlight.OutlineColor = HIGHLIGHT_CONFIG.outlineColor
	highlight.DepthMode = HIGHLIGHT_CONFIG.depthMode
	highlight.Parent = targetCharacter

	return highlight
end

local function resolveTargetPlayer(arg: any): Player?
	-- Accept Player instance directly
	if typeof(arg) == "Instance" and arg:IsA("Player") then
		return arg
	end
	-- Accept userId (number) and resolve to Player in this server
	if typeof(arg) == "number" and arg > 0 then
		return Players:GetPlayerByUserId(arg)
	end
	return nil
end

---------------
-- Handlers --
---------------
local function onHighlightRequest(targetRef: any): ()
	-- Always clear current highlight first
	removeActiveHighlight()

	-- Accept nil (means clear)
	if targetRef == nil then
		return
	end

	local targetPlayer = resolveTargetPlayer(targetRef)
	if not targetPlayer then
		return
	end

	local targetCharacter = targetPlayer.Character
	if not targetCharacter then
		-- Preserve original behavior (do not wait for spawn)
		return
	end

	state.activeHighlight = createHighlight(targetCharacter)
end

local function onOwnerCharacterAncestryChanged(): ()
	if not state.ownerCharacter.Parent then
		removeActiveHighlight()
		state.resourceManager:cleanupAll()
	end
end

local function cleanup(): ()
	removeActiveHighlight()
	state.resourceManager:cleanupAll()
end

---------------
-- Initialize --
---------------
local function initialize(): boolean
	-- Validate owner character
	if not state.ownerCharacter or not state.ownerCharacter:IsA("Model") then
		warn(TAG .. " script.Parent is not a Model; aborting.")
		return false
	end

	local humanoid = state.ownerCharacter:WaitForChild("Humanoid", HUMANOID_WAIT_TIMEOUT)
	assert(humanoid, TAG .. " Humanoid not found in " .. state.ownerCharacter.Name)
	assert(humanoid:IsA("Humanoid"), TAG .. " Humanoid is not a Humanoid instance")

	state.ownerHumanoid = humanoid :: Humanoid
	return true
end

local function connectEvents(): ()
	state.resourceManager:trackConnection(createHighlightEvent.OnClientEvent:Connect(onHighlightRequest))
	if state.ownerHumanoid then
		state.resourceManager:trackConnection(state.ownerHumanoid.Died:Connect(removeActiveHighlight))
	end
	state.resourceManager:trackConnection(state.ownerCharacter.AncestryChanged:Connect(onOwnerCharacterAncestryChanged))
	-- Also cleanup if this script is removed
	state.resourceManager:trackConnection(script.AncestryChanged:Connect(function()
		if not script:IsDescendantOf(game) then
			cleanup()
		end
	end))
end

if initialize() then
	connectEvents()
end