--!strict

--[[
	PassUIHandler_StateManager - Player UI state tracking and resource cleanup

	What it does:
	- Manages per-player UI state (connections, tweens, cooldown threads, gifting flag)
	- Tracks connections and tweens for automatic cleanup
	- Provides state lifecycle management (create, track, cleanup)
	- Handles cooldown state registry

	Returns: Module table with functions:
	- getOrCreatePlayerUIState(player) - Gets/creates player state
	- trackPlayerConnection(player, connection) - Tracks connection for cleanup
	- trackPlayerTween(player, tween) - Tracks tween for cleanup
	- cleanupPlayerResources(player, preserveCooldown) - Cleans up player resources
	- cleanupAllStates() - Cleans up all states (shutdown)
	- isPlayerOnCooldown(player) - Checks cooldown status
	- getPlayerUIState(player) - Gets existing state

	Usage:
	local StateManager = require(script.StateManager)
	StateManager.playerUIStates = {}  -- Inject shared registries
	local state = StateManager.getOrCreatePlayerUIState(player)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found in ReplicatedStorage")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)

-----------
-- Types --
-----------
export type PlayerUIState = {
	resourceManager: any, -- ResourceCleanup.ResourceManager
	cooldownThread: thread?,
	isGifting: boolean,
	lastRefreshTime: number?,
}

---------------
-- Constants --
---------------
local TAG = "[StateManager]"

-----------
-- Module --
-----------
local StateManager = {}

-- Shared registries (will be initialized by parent)
StateManager.playerUIStates = {} :: { [number]: PlayerUIState }
StateManager.playerCooldownRegistry = {} :: { [number]: boolean }

--[[
	Gets or creates player UI state

	@param player Player - Player to get state for
	@return PlayerUIState - Player's UI state
]]
function StateManager.getOrCreatePlayerUIState(player: Player): PlayerUIState
	local userId = player.UserId
	if not StateManager.playerUIStates[userId] then
		StateManager.playerUIStates[userId] = {
			resourceManager = ResourceCleanup.new(),
			cooldownThread = nil,
			isGifting = false,
			lastRefreshTime = nil,
		}
	end
	return StateManager.playerUIStates[userId]
end

--[[
	Tracks a connection for a player

	@param player Player - Player whose connection to track
	@param connection RBXScriptConnection - Connection to track
	@return RBXScriptConnection - Same connection for chaining
]]
function StateManager.trackPlayerConnection(player: Player, connection: RBXScriptConnection): RBXScriptConnection
	local state = StateManager.getOrCreatePlayerUIState(player)
	state.resourceManager:trackConnection(connection)
	return connection
end

--[[
	Tracks a tween for a player

	@param player Player - Player whose tween to track
	@param tween Tween - Tween to track
	@return Tween - Same tween for chaining
]]
function StateManager.trackPlayerTween(player: Player, tween: Tween): Tween
	local state = StateManager.getOrCreatePlayerUIState(player)
	state.resourceManager:trackTween(tween)
	return tween
end

--[[
	Cleans up all resources for a player

	Disconnects all connections, cancels all tweens, optionally preserves cooldown thread

	@param player Player - Player to cleanup
	@param preserveCooldownThread boolean - Whether to preserve cooldown thread
]]
function StateManager.cleanupPlayerResources(player: Player, preserveCooldownThread: boolean): ()
	local userId = player.UserId
	local state = StateManager.playerUIStates[userId]
	if not state then
		return
	end

	-- Clean up all tracked resources (connections, tweens)
	state.resourceManager:cleanupAll()

	-- Handle cooldown thread separately since it's tracked outside ResourceManager
	if state.cooldownThread and not preserveCooldownThread then
		task.cancel(state.cooldownThread)
	end

	StateManager.playerUIStates[userId] = nil
	StateManager.playerCooldownRegistry[userId] = nil

	print(TAG .. " Cleaned up resources for " .. player.Name .. " (" .. userId .. ")")
end

--[[
	Cleans up all player states

	Used during shutdown to cleanup all players
]]
function StateManager.cleanupAllStates(): ()
	local Players = game:GetService("Players")

	for userId in next, StateManager.playerUIStates do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			StateManager.cleanupPlayerResources(player, true)
		end
	end

	table.clear(StateManager.playerCooldownRegistry)
	table.clear(StateManager.playerUIStates)
end

--[[
	Checks if player is on cooldown

	@param player Player - Player to check
	@return boolean - True if on cooldown
]]
function StateManager.isPlayerOnCooldown(player: Player): boolean
	return StateManager.playerCooldownRegistry[player.UserId] ~= nil
end

--[[
	Gets player UI state if it exists

	@param player Player - Player to get state for
	@return PlayerUIState? - State or nil
]]
function StateManager.getPlayerUIState(player: Player): PlayerUIState?
	return StateManager.playerUIStates[player.UserId]
end

return StateManager