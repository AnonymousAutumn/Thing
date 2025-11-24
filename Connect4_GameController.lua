--!strict

--[[
	Connect4GameController Module

	Manages individual Connect4 game board state, player interactions, win detection, and turn management.
	Returns a table with .new() constructor for creating game board controllers.

	Usage:
		local controller = Connect4GameController.new(boardModel)
]]

--------------
-- Services --
--------------
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

----------------
-- References --
----------------
local network: Folder = assert(ReplicatedStorage:WaitForChild("Network", 10), "Network folder not found") :: Folder
local bindables = assert(network:WaitForChild("Bindables", 10), "Bindables folder not found")
local remotes = assert(network:WaitForChild("Remotes", 10), "Remotes folder not found")
local connect4Bindables = assert(bindables:WaitForChild("Connect4", 10), "Connect4 bindables not found")
local connect4Remotes = assert(remotes:WaitForChild("Connect4", 10), "Connect4 remotes not found")

local Modules = assert(ReplicatedStorage:WaitForChild("Modules", 10), "Modules folder not found")
local Configuration = assert(ReplicatedStorage:WaitForChild("Configuration", 10), "Configuration folder not found")

local PlayerData = require(Modules.Managers.PlayerData)
local DataStoreWrapper = require(Modules.Wrappers.DataStore)
local GameConfig = require(Configuration.GameConfig)

-- Submodules
local WinDetection = require(script.WinDetection)
local TokenFactory = require(script.TokenFactory)
local BoardState = require(script.BoardState)
local PlayerNotifications = require(script.PlayerNotifications)
local CameraController = require(script.CameraController)
local GameTiming = require(script.GameTiming)

-----------
-- Types --
-----------
export type GameBoard = {
	boardModel: Model,
	tokenContainer: Instance,
	basePlateYPosition: number,
	gameObjectHolder: Instance,
	columnTriggers: Instance,
	joinGamePrompt: ProximityPrompt,
	gameCameraPart: BasePart,

	columnTriggerPositions: { [number]: Vector3 },
	currentGamePlayers: { Player },
	activePlayerIndex: number,
	boardState: any,
	isTokenCurrentlyDropping: boolean,
	isGameCurrentlyActive: boolean,
	timingManager: any,

	-- Performance cache
	_lastDistanceCheck: number?,
	_cachedBoardPosition: Vector3?,
}

---------------
-- Constants --
---------------
local CONFIG = {
	BOARD = {
		ROWS = 5,
		COLUMNS = 8,
		MAX_PLAYER_DISTANCE = 20,
		TOKEN_HEIGHT = 0.9,
		DISTANCE_CHECK_INTERVAL = 0.5,
	},
	PLAYER_CAPACITY = 2,
}

-- DataStore
local playerWinsDataStore = DataStoreService:GetOrderedDataStore(GameConfig.DATASTORE.WINS_ORDERED_KEY)

---------------
-- Utilities --
---------------
local function updateDataStore(playerId: number, dataStore, increment: number): number
	local result = DataStoreWrapper.incrementAsync(
		dataStore,
		tostring(playerId),
		increment,
		{ maxRetries = 3, baseDelay = 1 }
	)

	if not result.success then
		warn("Failed to update datastore for player " .. tostring(playerId) .. ": " .. tostring(result.error))
		return 0
	end

	return result.data or 0
end

local function recordPlayerWin(playerUserId: number, wins: number): ()
	updateDataStore(playerUserId, playerWinsDataStore, wins)
	PlayerData:IncrementPlayerStatistic(playerUserId, "Wins", wins)
end

---------------
-- GameBoard --
---------------
local Connect4GameBoard = {}
Connect4GameBoard.__index = Connect4GameBoard

function Connect4GameBoard.new(boardModel: Model): GameBoard
	assert(boardModel and boardModel:IsA("Model"), "boardModel must be a valid Model")

	local self = setmetatable({}, Connect4GameBoard) :: any

	self.boardModel = boardModel
	self.tokenContainer = assert(boardModel:WaitForChild("Tokens", 10), "Tokens container not found in board model")
	local basePart = assert(boardModel:WaitForChild("Base", 10), "Base part not found in board model")
	self.basePlateYPosition = basePart.Position.Y
	self.gameObjectHolder = assert(boardModel:WaitForChild("ObjectHolder", 10), "ObjectHolder not found in board model")
	self.columnTriggers = assert(boardModel:WaitForChild("Triggers", 10), "Triggers folder not found in board model")
	self.joinGamePrompt = assert(self.gameObjectHolder:WaitForChild("ProximityPrompt", 10), "ProximityPrompt not found")
	self.gameCameraPart = assert(boardModel:WaitForChild("CameraPart", 10), "CameraPart not found in board model")

	self.columnTriggerPositions = {}
	self.currentGamePlayers = {}
	self.activePlayerIndex = 0
	self.boardState = BoardState.new(CONFIG.BOARD.ROWS, CONFIG.BOARD.COLUMNS)
	self.timingManager = GameTiming.new()
	self.isTokenCurrentlyDropping = false
	self.isGameCurrentlyActive = false

	-- Performance cache
	self._lastDistanceCheck = 0
	self._cachedBoardPosition = nil

	self:_setupColumnTriggers()
	self:_setupJoinPrompt()
	self:_connectEvents()
	self:_startDistanceMonitoring()
	self:_updateJoinPrompt()

	return self :: GameBoard
end

function Connect4GameBoard:_setupColumnTriggers(): ()
	for _, trigger in self.columnTriggers:GetChildren() do
		if not trigger:IsA("BasePart") then
			continue
		end

		local columnIndex = tonumber(trigger.Name:match("C(%d+)"))
		if not columnIndex then
			continue
		end

		self.columnTriggerPositions[columnIndex] = trigger.Position

		local clickDetector = trigger:FindFirstChild("ClickDetector")
		if clickDetector and clickDetector:IsA("ClickDetector") then
			clickDetector.MouseClick:Connect(function(player)
				self:_attemptTokenDrop(player, columnIndex)
			end)
		end
	end
end

function Connect4GameBoard:_setupJoinPrompt(): ()
	self.joinGamePrompt.Triggered:Connect(function(player)
		if self.isGameCurrentlyActive then
			return
		end

		local playerIndex = table.find(self.currentGamePlayers, player)
		if playerIndex then
			table.remove(self.currentGamePlayers, playerIndex)
			PlayerNotifications.sendToPlayer(player, "left the queue", nil, false)
			self:_updateJoinPrompt()
			return
		end

		connect4Bindables.KickPlayer:Fire(player)

		if #self.currentGamePlayers < CONFIG.PLAYER_CAPACITY then
			table.insert(self.currentGamePlayers, player)
			self:_updateJoinPrompt()

			if #self.currentGamePlayers == CONFIG.PLAYER_CAPACITY then
				self:_startGame()
			else
				PlayerNotifications.sendToPlayer(player, "joined the queue", nil, false)
			end
		end
	end)
end

function Connect4GameBoard:_connectEvents(): ()
	connect4Bindables.DropToken.Event:Connect(function(player, column)
		self:_attemptTokenDrop(player, column)
	end)

	connect4Bindables.KickPlayer.Event:Connect(function(player)
		if table.find(self.currentGamePlayers, player) then
			PlayerNotifications.sendToPlayersExcept(self.currentGamePlayers, player.Name .. " stopped playing", player)
			self:_resetGame(true)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_handlePlayerLeaving(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = assert(character:WaitForChild("Humanoid", 10), "Humanoid not found in character")
			humanoid.Died:Connect(function()
				self:_handlePlayerLeaving(player)
			end)
		end)
	end)

	-- SECURITY: Validate player before processing RemoteEvent
	-- Roblox engine guarantees first parameter is Player, but validate to be safe
	connect4Remotes.PlayerExited.OnServerEvent:Connect(function(player)
		-- Step 1-3: Type validation (RemoteEvent security pattern)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			warn("[GameController] Invalid player in PlayerExited RemoteEvent")
			return
		end

		-- Step 5: Server authoritative - only kick if player is actually in the game
		-- (checked in KickPlayer handler via table.find)
		connect4Bindables.KickPlayer:Fire(player)
	end)
end

function Connect4GameBoard:_handlePlayerLeaving(player: Player): ()
	if table.find(self.currentGamePlayers, player) then
		PlayerNotifications.sendToPlayersExcept(self.currentGamePlayers, player.Name .. " stopped playing", player)
		self:_resetGame(true)
	end
end

--[[
	Monitors player distance and kicks players who wander too far
	Performance: Throttles checks to 2 FPS instead of 60 FPS (~97% reduction)
]]
function Connect4GameBoard:_startDistanceMonitoring(): ()
	RunService.Heartbeat:Connect(function()
		if not self.boardModel or not self.currentGamePlayers then
			return
		end

		-- Throttle distance checks
		local now = tick()
		if now - (self._lastDistanceCheck or 0) < CONFIG.BOARD.DISTANCE_CHECK_INTERVAL then
			return
		end
		self._lastDistanceCheck = now

		-- Cache board position
		local boardPosition = self._cachedBoardPosition or self.boardModel:GetPivot().Position
		self._cachedBoardPosition = boardPosition

		for i = #self.currentGamePlayers, 1, -1 do
			local player = self.currentGamePlayers[i]
			local character = player.Character
			if not character then
				continue
			end

			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then
				continue
			end

			local distance = (hrp.Position - boardPosition).Magnitude

			if distance > CONFIG.BOARD.MAX_PLAYER_DISTANCE then
				table.remove(self.currentGamePlayers, i)
				PlayerNotifications.sendToPlayer(player, "left the queue", nil, false)
				PlayerNotifications.sendToPlayersExcept(self.currentGamePlayers, player.Name .. " stopped playing", player)
				self:_updateJoinPrompt()

				if self.isGameCurrentlyActive then
					self:_resetGame(true)
				end
			end
		end
	end)
end

function Connect4GameBoard:_updateJoinPrompt(): ()
	if self.joinGamePrompt then
		self.joinGamePrompt.Enabled = not self.isGameCurrentlyActive
		self.joinGamePrompt.ActionText = "Join ("
			.. tostring(#self.currentGamePlayers)
			.. "/"
			.. tostring(CONFIG.PLAYER_CAPACITY)
			.. " Players)"
	end
end

function Connect4GameBoard:_switchTurn(): ()
	self.activePlayerIndex = 1 - self.activePlayerIndex
end

function Connect4GameBoard:_startGame(): ()
	self.isGameCurrentlyActive = true
	self.activePlayerIndex = 0
	self:_updateJoinPrompt()

	for i, player in self.currentGamePlayers do
		local isPlayerTurn = (self.activePlayerIndex == (i - 1))
		local message = isPlayerTurn and "Your turn!" or "Waiting for opponent..."
		local timeout = isPlayerTurn and GameTiming.getTurnTimeout() or nil

		PlayerNotifications.sendToPlayer(player, message, timeout, isPlayerTurn)
		CameraController.updatePlayerCamera(player, isPlayerTurn, self.gameCameraPart.CFrame)
	end

	self.timingManager:startTurnTimeout(function()
		PlayerNotifications.sendToPlayers(self.currentGamePlayers, "Turn timed out. Resetting game...")
		GameTiming.scheduleReset(function()
			self:_resetGame(true)
		end)
	end)
end

function Connect4GameBoard:_resetGame(shouldResetUI: boolean): ()
	self.isGameCurrentlyActive = false
	self.timingManager:cancelCurrentTimeout()

	if shouldResetUI then
		PlayerNotifications.clearAllUI(self.currentGamePlayers)
	end

	CameraController.resetAllCameras(self.currentGamePlayers)

	self.boardState:reset()

	-- Cache GetChildren() for performance (called after every game)
	local tokens = self.tokenContainer:GetChildren()
	for _, token in tokens do
		token:Destroy()
	end

	self.activePlayerIndex = 0
	self.currentGamePlayers = {}
	self._cachedBoardPosition = nil

	self:_updateJoinPrompt()
end

--[[
	Main game loop: attempts to drop a token into a column
	Validates state, creates token, checks win, manages transitions
]]
function Connect4GameBoard:_attemptTokenDrop(player: Player, column: number): boolean
	if not self.isGameCurrentlyActive or self.isTokenCurrentlyDropping then
		return false
	end

	if self.currentGamePlayers[self.activePlayerIndex + 1] ~= player then
		return false
	end

	local row = self.boardState:findLowestAvailableRow(column)
	if not row then
		return false
	end

	self.isTokenCurrentlyDropping = true

	-- Get board rotation for token alignment
	local boardRotation = nil
	if self.boardModel:FindFirstChild("LeftBase") then
		boardRotation = self.boardModel.LeftBase.Rotation
	end

	-- Create token
	local token = TokenFactory.createToken(self.tokenContainer, {
		column = column,
		row = row,
		teamIndex = self.activePlayerIndex,
		triggerPosition = self.columnTriggerPositions[column],
		basePlateYPosition = self.basePlateYPosition,
		tokenHeight = CONFIG.BOARD.TOKEN_HEIGHT,
		boardRotation = boardRotation,
	})

	self.boardState:placeToken(column, row, self.activePlayerIndex, token)
	self.timingManager:cancelCurrentTimeout()

	-- Check win condition
	local winResult = WinDetection.checkWin(self.boardState.state, column, row, self.activePlayerIndex)

	if winResult.hasWon then
		self:_handleWin(player, winResult.winningPositions)
	else
		self:_handleContinueOrDraw()
	end

	return true
end

function Connect4GameBoard:_handleWin(winner: Player, winningPositions: { { number } }): ()
	-- Apply victory effects to winning tokens
	for _, position in winningPositions do
		local token = self.boardState:getTokenInstance(position[1], position[2])
		if token then
			TokenFactory.applyVictoryEffects(token)
		end
	end

	-- Play win sound
	if self.gameObjectHolder:FindFirstChild("Win") then
		self.gameObjectHolder.Win:Play()
	end
	self.isGameCurrentlyActive = false

	-- Notify players
	for _, player in self.currentGamePlayers do
		PlayerNotifications.sendToPlayer(player, winner.Name .. " won!", nil, false)
		connect4Remotes.Cleanup:FireClient(player)
	end

	recordPlayerWin(winner.UserId, 1)

	GameTiming.scheduleReset(function()
		self:_resetGame(true)
		self.isTokenCurrentlyDropping = false
	end)
end

function Connect4GameBoard:_handleContinueOrDraw(): ()
	if self.boardState:isBoardFull() then
		self:_handleDraw()
	else
		self:_continueGame()
	end
end

function Connect4GameBoard:_handleDraw(): ()
	self.isGameCurrentlyActive = false

	for _, player in self.currentGamePlayers do
		if self.gameObjectHolder:FindFirstChild("Draw") then
			self.gameObjectHolder.Draw:Play()
		end
		PlayerNotifications.sendToPlayer(player, "It's a draw!", nil, false)
		connect4Remotes.Cleanup:FireClient(player)
	end

	GameTiming.scheduleReset(function()
		self:_resetGame(true)
		self.isTokenCurrentlyDropping = false
	end)
end

function Connect4GameBoard:_continueGame(): ()
	if self.gameObjectHolder:FindFirstChild("Click") then
		self.gameObjectHolder.Click:Play()
	end
	self:_switchTurn()

	for i, player in self.currentGamePlayers do
		local isPlayerTurn = (self.activePlayerIndex == (i - 1))
		local message = isPlayerTurn and "Your turn!" or "Waiting for opponent..."
		local timeout = isPlayerTurn and GameTiming.getTurnTimeout() or nil

		PlayerNotifications.sendToPlayer(player, message, timeout, isPlayerTurn)
		CameraController.updatePlayerCamera(player, isPlayerTurn, self.gameCameraPart.CFrame)
	end

	self.timingManager:startTurnTimeout(function()
		PlayerNotifications.sendToPlayers(self.currentGamePlayers, "Turn timed out. Resetting game...")
		GameTiming.scheduleReset(function()
			self:_resetGame(true)
		end)
	end)

	GameTiming.scheduleDropCooldown(function()
		self.isTokenCurrentlyDropping = false
	end)
end

return Connect4GameBoard