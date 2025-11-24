--!strict

-----------
-- Types --
-----------
export type ResourceManager = {
	connections: { RBXScriptConnection },
	tweens: { Tween },
	instances: { Instance },
	threads: { thread },
	callbacks: { () -> () },

	trackConnection: (self: ResourceManager, connection: RBXScriptConnection) -> (),
	trackTween: (self: ResourceManager, tween: Tween) -> (),
	trackInstance: (self: ResourceManager, instance: Instance) -> (),
	trackThread: (self: ResourceManager, thread: thread) -> (),
	trackCallback: (self: ResourceManager, callback: () -> ()) -> (),

	cleanupConnections: (self: ResourceManager) -> (),
	cleanupTweens: (self: ResourceManager) -> (),
	cleanupInstances: (self: ResourceManager) -> (),
	cleanupThreads: (self: ResourceManager) -> (),
	cleanupCallbacks: (self: ResourceManager) -> (),
	cleanupAll: (self: ResourceManager) -> (),
}

-----------
-- Module --
-----------
local ResourceCleanup = {}

--[[
	Creates a new resource manager

	@return ResourceManager
]]
function ResourceCleanup.new(): ResourceManager
	local self = {} :: any

	self.connections = {}
	self.tweens = {}
	self.instances = {}
	self.threads = {}
	self.callbacks = {}

	--[[
		Tracks a connection for cleanup

		@param connection RBXScriptConnection
	]]
	function self:trackConnection(connection: RBXScriptConnection): ()
		table.insert(self.connections, connection)
	end

	--[[
		Tracks a tween for cleanup

		@param tween Tween
	]]
	function self:trackTween(tween: Tween): ()
		table.insert(self.tweens, tween)
	end

	--[[
		Tracks an instance for cleanup (destruction)

		@param instance Instance
	]]
	function self:trackInstance(instance: Instance): ()
		table.insert(self.instances, instance)
	end

	--[[
		Tracks a thread for cleanup (cancellation)

		@param thread thread
	]]
	function self:trackThread(thread: thread): ()
		table.insert(self.threads, thread)
	end

	--[[
		Tracks a callback function to run on cleanup

		@param callback () -> ()
	]]
	function self:trackCallback(callback: () -> ()): ()
		table.insert(self.callbacks, callback)
	end

	--[[
		Disconnects all tracked connections
	]]
	function self:cleanupConnections(): ()
		for _, connection in self.connections do
			pcall(function()
				if connection.Connected then
					connection:Disconnect()
				end
			end)
		end
		self.connections = {}
	end

	--[[
		Cancels all tracked tweens
	]]
	function self:cleanupTweens(): ()
		for _, tween in self.tweens do
			pcall(function()
				tween:Cancel()
			end)
		end
		self.tweens = {}
	end

	--[[
		Destroys all tracked instances
	]]
	function self:cleanupInstances(): ()
		for _, instance in self.instances do
			pcall(function()
				if instance.Parent then
					instance:Destroy()
				end
			end)
		end
		self.instances = {}
	end

	--[[
		Cancels all tracked threads
	]]
	function self:cleanupThreads(): ()
		for _, thread in self.threads do
			pcall(function()
				task.cancel(thread)
			end)
		end
		self.threads = {}
	end

	--[[
		Executes all cleanup callbacks
	]]
	function self:cleanupCallbacks(): ()
		for _, callback in self.callbacks do
			pcall(callback)
		end
		self.callbacks = {}
	end

	--[[
		Cleans up all tracked resources
	]]
	function self:cleanupAll(): ()
		self:cleanupCallbacks()
		self:cleanupThreads()
		self:cleanupTweens()
		self:cleanupConnections()
		self:cleanupInstances()
	end

	return self :: ResourceManager
end

--[[
	Helper: Safely disconnects a connection

	@param connection RBXScriptConnection?
]]
function ResourceCleanup.safeDisconnect(connection: RBXScriptConnection?): ()
	if connection then
		pcall(function()
			if connection.Connected then
				connection:Disconnect()
			end
		end)
	end
end

--[[
	Helper: Safely destroys an instance

	@param instance Instance?
]]
function ResourceCleanup.safeDestroy(instance: Instance?): ()
	if instance then
		pcall(function()
			if instance.Parent then
				instance:Destroy()
			end
		end)
	end
end

--[[
	Helper: Safely cancels a tween

	@param tween Tween?
]]
function ResourceCleanup.safeCancelTween(tween: Tween?): ()
	if tween then
		pcall(function()
			tween:Cancel()
		end)
	end
end

--[[
	Helper: Safely cancels a thread

	@param thread thread?
]]
function ResourceCleanup.safeCancelThread(thread: thread?): ()
	if thread then
		pcall(function()
			task.cancel(thread)
		end)
	end
end

return ResourceCleanup