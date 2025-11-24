--!strict

--[[
	Connect4_GameController_TokenFactory

	Creates and manages Connect4 game tokens with animations and visual effects.
	Handles token instantiation, placement, drop animations, and victory effects.

	Returns: Table with factory functions:
		- createToken: Creates and animates a token drop with team color
		- applyVictoryEffects: Applies neon/transparency effects to winning tokens

	Usage:
		local TokenFactory = require(script.Connect4_GameController_TokenFactory)
		local token = TokenFactory.createToken(container, {
			column = 3,
			row = 2,
			teamIndex = 0,
			triggerPosition = Vector3.new(5, 10, 0),
			basePlateYPosition = 0,
			tokenHeight = 1
		})
		TokenFactory.applyVictoryEffects(token)
]]

--------------
-- Services --
--------------
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------
-- References --
----------------
local instances: Folder = assert(ReplicatedStorage:WaitForChild("Instances", 10), "Instances folder not found in ReplicatedStorage")
local objects = assert(instances:WaitForChild("Objects", 10), "Objects folder not found in Instances")
local tokenPrefab = assert(objects:WaitForChild("Token", 10), "Token prefab not found in Objects")

-----------
-- Types --
-----------
export type TokenConfig = {
	column: number,
	row: number,
	teamIndex: number,
	triggerPosition: Vector3,
	basePlateYPosition: number,
	tokenHeight: number,
	boardRotation: Vector3?,
}

---------------
-- Constants --
---------------
local CONFIG = {
	TOKEN = {
		DROP_HEIGHT_OFFSET = 10,
		SIZE = Vector3.new(0.1, 0.9 * 0.9, 3),
	},

	ANIMATION = {
		DROP = TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
	},

	TEAMS = {
		[0] = "Bright red", -- Red team
		[1] = "Gold", -- Yellow team
	},
}

-----------
-- Module --
-----------
local TokenFactory = {}

--[[
	Gets team color name from team index
	@param teamIndex number - Team identifier (0 or 1)
	@return string - BrickColor name
]]
local function getTeamColor(teamIndex: number): string
	return CONFIG.TEAMS[teamIndex] or CONFIG.TEAMS[0]
end

--[[
	Creates and animates a token drop

	Creates a token instance, positions it above the target location,
	applies team color and rotation, then animates it dropping into place.

	@param container Instance - Parent container for the token
	@param config TokenConfig - Configuration for token placement
	@return Part? - Created token part (or nil if invalid position)
]]
function TokenFactory.createToken(container: Instance, config: TokenConfig): Part?
	assert(typeof(container) == "Instance", "container must be an Instance")
	assert(typeof(config) == "table", "config must be a table")

	if not config.triggerPosition then
		return nil
	end

	local token = tokenPrefab:Clone()
	token.Parent = container

	-- Calculate positions
	local finalY = config.basePlateYPosition + (config.row - 1) * config.tokenHeight
	local startY = finalY + CONFIG.TOKEN.DROP_HEIGHT_OFFSET

	-- Set token properties
	token.Size = CONFIG.TOKEN.SIZE
	token.Position = Vector3.new(config.triggerPosition.X, startY, config.triggerPosition.Z)
	token.BrickColor = BrickColor.new(getTeamColor(config.teamIndex))

	-- Apply board rotation if provided
	if config.boardRotation then
		token.Rotation = Vector3.new(0, config.boardRotation.Y, 0)
	end

	-- Animate drop
	local finalPosition = Vector3.new(config.triggerPosition.X, finalY, config.triggerPosition.Z)
	local tween = TweenService:Create(token, CONFIG.ANIMATION.DROP, { Position = finalPosition })
	tween:Play()

	return token
end

--[[
	Applies victory effects to a token
	@param token Part - Token to apply effects to
]]
function TokenFactory.applyVictoryEffects(token: Part): ()
	assert(typeof(token) == "Instance" and token:IsA("BasePart"), "token must be a BasePart")

	token.Material = Enum.Material.Neon
	token.Transparency = 0.25
end

return TokenFactory