--!strict

--[[
	Connect4_GameController_WinDetection

	Detects winning conditions in Connect4 by checking for 4 consecutive tokens
	in horizontal, vertical, and diagonal directions.

	Returns: Table with win detection function:
		- checkWin: Analyzes board state after a token placement to determine if a win occurred

	Usage:
		local WinDetection = require(script.Connect4_GameController_WinDetection)
		local result = WinDetection.checkWin(boardState, column, row, teamIndex)
		if result.hasWon then
			print("Win detected at positions:", result.winningPositions)
		end
]]

-----------
-- Types --
-----------
export type BoardState = { { number? } }
export type Position = { number }
export type WinResult = {
	hasWon: boolean,
	winningPositions: { Position }?,
}

---------------
-- Constants --
---------------
local WIN_CONDITION = 4

-- Direction vectors: (column_delta, row_delta)
-- Horizontal, Vertical, Diagonal-right, Diagonal-left
local DIRECTIONS = {
	{ 1, 0 }, -- Horizontal
	{ 0, 1 }, -- Vertical
	{ 1, 1 }, -- Diagonal (down-right)
	{ 1, -1 }, -- Diagonal (up-right)
}

-----------
-- Module --
-----------
local WinDetection = {}

--[[
	Checks if placing a token creates a winning condition

	Algorithm: For each direction, counts consecutive matching tokens
	in both positive and negative directions from the placed token.

	@param boardState BoardState - 2D array of token ownership (0, 1, or nil)
	@param column number - Column index where token was placed (1-indexed)
	@param row number - Row index where token was placed (1-indexed)
	@param teamIndex number - Team identifier (0 or 1)
	@return WinResult - { hasWon: boolean, winningPositions: {Position}? }
]]
function WinDetection.checkWin(
	boardState: BoardState,
	column: number,
	row: number,
	teamIndex: number
): WinResult
	assert(typeof(boardState) == "table", "boardState must be a table")
	assert(typeof(column) == "number" and column > 0, "column must be a positive number")
	assert(typeof(row) == "number" and row > 0, "row must be a positive number")
	assert(typeof(teamIndex) == "number", "teamIndex must be a number")

	for _, direction in DIRECTIONS do
		local dx, dy = direction[1], direction[2]
		local count = 1
		local positions: { Position } = { { column, row } }

		-- Check both directions along this line
		for _, multiplier in { 1, -1 } do
			local step = 1
			while true do
				local checkColumn = column + dx * step * multiplier
				local checkRow = row + dy * step * multiplier

				-- Check if position is valid and contains matching team
				local columnData = boardState[checkColumn]
				if columnData and columnData[checkRow] == teamIndex then
					count += 1
					table.insert(positions, { checkColumn, checkRow })
					step += 1
				else
					break
				end
			end
		end

		if count >= WIN_CONDITION then
			return {
				hasWon = true,
				winningPositions = positions,
			}
		end
	end

	return {
		hasWon = false,
		winningPositions = nil,
	}
end

return WinDetection