--!strict

--------------
-- Services --
--------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

---------------
-- Constants --
---------------

local network : Folder = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")
local createHighlightEvent = remoteEvents:WaitForChild("CreateHighlight")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

local HIGHLIGHT_CONFIG = {
	instanceName = "PlayerHighlight",
	fillTransparency = 1,
	outlineColor = Color3.fromRGB(255, 255, 255),
	depthMode = Enum.HighlightDepthMode.AlwaysOnTop,
}

local HUMANOID_WAIT_TIMEOUT = 10

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
	if not targetCharacter or not targetCharacter.Parent then
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
		warn("HighlightHandler: script.Parent is not a Model; aborting.")
		return false
	end

	local success, humanoid = pcall(function()
		return state.ownerCharacter:WaitForChild("Humanoid", HUMANOID_WAIT_TIMEOUT)
	end)
	if not success or not humanoid then
		warn(string.format("HighlightHandler: Humanoid not found in %s", state.ownerCharacter.Name))
		return false
	end

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