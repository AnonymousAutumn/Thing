--!strict

----------------
-- References --
----------------

local Connect4GameController = require(script:WaitForChild("GameController"))
local connect4BoardsContainer = workspace:WaitForChild("Connect4Boards")

-----------
-- Types --
-----------

type GameBoardController = typeof(Connect4GameController.new(Instance.new("Model")))

----------------
-- Variables --
----------------

local activeBoardControllers: {GameBoardController} = {}

----------------
-- Functions --
----------------

--[[
	Initializes all Connect 4 game boards found in the workspace container

	Iterates through all children of the boards container and attempts to create
	a game controller for each board model. Failed initializations are logged
	but do not prevent other boards from being set up.

	@return {GameBoardController} - Array of successfully initialized board controllers
]]
local function setupConnect4GameBoards(): {GameBoardController}
	local boardModelCollection = connect4BoardsContainer:GetChildren()
	local initializedBoardControllers: {GameBoardController} = table.create(#boardModelCollection)

	for index, boardModel in boardModelCollection do
		local success, boardGameController = pcall(function()
			return Connect4GameController.new(boardModel)
		end)

		if success and boardGameController then
			table.insert(initializedBoardControllers, boardGameController)
		else
			warn("Failed to initialize Connect4 board controller for " .. boardModel.Name)
		end
	end

	return initializedBoardControllers
end

--------------------
-- Initialization --
--------------------

activeBoardControllers = setupConnect4GameBoards()