--!strict
-- Facade for the chess variant. Server and client both require this module and
-- reach the pieces they need through it, so there is one place to see how the
-- engine is composed:
--
--   Config - constants: board size, piece values, initial layout
--   Board  - the grid, the game state, cloning, position keys
--   Moves  - pseudo-legal move generation and the attack detector
--   Rules  - legal filtering, applying moves, terminal conditions
--   Bot    - the three built-in opponents
--   Serialize - snapshots for the wire, and rebuilding a grid from one

local Config = require(script.Config)
local Board = require(script.Board)
local Moves = require(script.Moves)
local Rules = require(script.Rules)
local Bot = require(script.Bot)
local Serialize = require(script.Serialize)

local Chess = {
	Config = Config,
	Board = Board,
	Moves = Moves,
	Rules = Rules,
	Bot = Bot,
	Serialize = Serialize,
}

return Chess
