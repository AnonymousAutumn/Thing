--!strict

-----------
-- Types --
-----------
type ClaimedStandData = {
	gamepasses: { any }?,
}

type StandMaster = {
	TryClaimStand: (self: StandMaster, player: Player, stand: any) -> (),
}

export type StandModule = {
	Stand: Model,
	Prompt: ProximityPrompt,
	Data: Frame,
	PassesHolder: Folder,
	Owner: Player?,
	Master: StandMaster,
	RefreshEvent: RemoteEvent,
	ClaimedStands: { [Model]: ClaimedStandData },
	connectionManager: any,
	_connectPrompt: (self: StandModule) -> (),
	_populateFrame: (self: StandModule, reset: boolean?) -> (),
	Populate: (self: StandModule, player: Player) -> (),
	Claim: (self: StandModule, player: Player) -> (),
	Reset: (self: StandModule) -> (),
}

--------------
-- Services --
--------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------

local network = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")

local sendNotificationEvent = remoteEvents:WaitForChild("CreateNotification")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceCleanup = require(Modules.Wrappers.ResourceCleanup)
local GamepassCacheManager = require(Modules.Caches.PassCache)
local FormatString = require(Modules.Utilities.FormatString)

-----------
-- Module --
-----------

local StandModule = {}
StandModule.__index = StandModule

function StandModule.new(stand: Model, master: StandMaster, refreshEvent: RemoteEvent, claimedStands: { [Model]: ClaimedStandData }): StandModule
	local self = setmetatable({}, StandModule)
	self.Stand = stand
	self.Prompt = stand.PromptHolder.Attachment.ProximityPrompt
	self.Data = stand.DataHolder.Holder.MainFrame
	self.PassesHolder = stand.PassesHolder
	self.Owner = nil
	self.Master = master
	self.RefreshEvent = refreshEvent
	self.ClaimedStands = claimedStands -- reference authoritative table
	self.resourceManager = ResourceCleanup.new()

	self:_connectPrompt()
	return self
end

function StandModule:_connectPrompt(): ()
	self.Prompt.Triggered:Connect(function(player: Player)
		if self.Owner then return end
		self.Master:TryClaimStand(player, self)
	end)
end

-- Always use authoritative ClaimedStands
function StandModule:_populateFrame(reset: boolean?): ()
	local claimedData = self.ClaimedStands[self.Stand]
	if not claimedData then return end
	local gamepasses = claimedData.gamepasses or {}

	self.RefreshEvent:FireAllClients(self.Stand, gamepasses, reset)
end

function StandModule:Populate(player: Player): ()
	if not self.Owner then return end

	-- Set up display name
	local displayName = player.DisplayName or player.Name
	self.Data.OwnerName.Text = string.format("%s's Stand", displayName)

	-- Set up raised amount tracking
	local leaderstats = player:FindFirstChild("leaderstats")
	local raisedStat = leaderstats and leaderstats:FindFirstChild("Raised")

	if raisedStat then
		local updateRaisedDisplay = function()
			self.Data.RaisedAmount.Text = string.format(
				"Raised: %s",
				FormatString.formatNumberWithThousandsSeparatorCommas(raisedStat.Value)
			)
		end

		self.Data.RaisedAmount.Visible = true
		updateRaisedDisplay()

		self.resourceManager:trackConnection(
			raisedStat:GetPropertyChangedSignal("Value"):Connect(updateRaisedDisplay)
		)
	end

	self:_populateFrame()
end

function StandModule:Claim(player: Player): ()
	self.Owner = player
	self.Stand:SetAttribute("Owner", player.Name)
	self.Prompt.Enabled = false
	self:Populate(player)
	sendNotificationEvent:FireClient(player, "Successfully claimed a stand!", "Success")
end

function StandModule:Reset(): ()
	self.Stand:SetAttribute("Owner", "")
	self.Prompt.Enabled = true

	if self.Owner then
		self:_populateFrame(true)
	end

	self.Owner = nil
	self.Data.OwnerName.Text = "UNCLAIMED"
	self.Data.RaisedAmount.Visible = false

	self.resourceManager:cleanupAll()
end

return StandModule