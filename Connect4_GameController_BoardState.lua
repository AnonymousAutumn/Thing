--!strict

--[[
	BoardState Module

	Manages Connect4 board state tracking and token placement.
	Returns a table with .new() constructor for creating board state instances.

	Usage:
		local board = BoardState.new(5, 8)
		board:placeToken(column, row, teamIndex, tokenPart)
]]

-----------
-- Types --
-----------
export type BoardState = { { number? } }
export type TokenInstances = { { Part? } }

export type Board = {
	state: BoardState,
	tokenInstances: TokenInstances,
	rows: number,
	columns: number,
}

-----------
-- Module --
-----------
local BoardState = {}
BoardState.__index = BoardState

--[[
	Creates a new board state manager

	@param rows number - Number of rows in the board
	@param columns number - Number of columns in the board
	@return Board
]]
function BoardState.new(rows: number, columns: number): Board
	assert(type(rows) == "number" and rows > 0, "rows must be a positive number")
	assert(type(columns) == "number" and columns > 0, "columns must be a positive number")

	local self = setmetatable({}, BoardState) :: any

	self.rows = rows
	self.columns = columns
	self.state = {}
	self.tokenInstances = {}

	-- Initialize state arrays
	for column = 1, columns do
		self.state[column] = table.create(rows)
		self.tokenInstances[column] = table.create(rows)
	end

	return self :: Board
end

--[[
	Finds the lowest available row in a column

	@param column number - Column index (1-based)
	@return number? - Row index if available, nil if column is full
]]
function BoardState:findLowestAvailableRow(column: number): number?
	for row = 1, self.rows do
		if not self.state[column][row] then
			return row
		end
	end
	return nil
end

--[[
	Checks if the board is completely full

	@return boolean - True if no spaces remain
]]
function BoardState:isBoardFull(): boolean
	for column = 1, self.columns do
		if self:findLowestAvailableRow(column) then
			return false
		end
	end
	return true
end

--[[
	Places a token in the board state

	@param column number - Column index
	@param row number - Row index
	@param teamIndex number - Team identifier (0 or 1)
	@param tokenInstance Part? - Optional token part instance
]]
function BoardState:placeToken(column: number, row: number, teamIndex: number, tokenInstance: Part?): ()
	self.state[column][row] = teamIndex
	if tokenInstance then
		self.tokenInstances[column][row] = tokenInstance
	end
end

--[[
	Gets token instance at a position

	@param column number - Column index
	@param row number - Row index
	@return Part? - Token part or nil
]]
function BoardState:getTokenInstance(column: number, row: number): Part?
	local columnData = self.tokenInstances[column]
	if columnData then
		return columnData[row]
	end
	return nil
end

--[[
	Resets the entire board state to empty
]]
function BoardState:reset(): ()
	for column = 1, self.columns do
		for row = 1, self.rows do
			self.state[column][row] = nil
			self.tokenInstances[column][row] = nil
		end
	end
end

--[[
	Gets the current state value at a position

	@param column number - Column index
	@param row number - Row index
	@return number? - Team index or nil
]]
function BoardState:getState(column: number, row: number): number?
	local columnData = self.state[column]
	if columnData then
		return columnData[row]
	end
	return nil
end

return BoardState