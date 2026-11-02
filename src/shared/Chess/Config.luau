--!strict
-- Static definitions for the chess variant played in this place: board
-- geometry, piece identities, and the numbers the bot's evaluation uses.
-- Everything here is constant. Mutable game state lives in Board/Rules.

local Config = {}

Config.Files = 10
Config.Ranks = 8

Config.FileLetters = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" }

Config.White = "White"
Config.Black = "Black"

-- The opposing side, used constantly by move generation and material sums.
Config.Other = {
	White = "Black",
	Black = "White",
} :: { [string]: string }

Config.Piece = {
	Pawn = "Pawn",
	Rook = "Rook",
	Knight = "Knight",
	Bishop = "Bishop",
	Queen = "Queen",
	King = "King",
	Hexer = "Hexer",
	Rift = "Rift",
}

-- Centipawn values used by the bot. The King is never traded, so it scores 0.
Config.PieceValue = {
	Pawn = 100,
	Knight = 320,
	Bishop = 330,
	Rook = 500,
	Queen = 900,
	Hexer = 400,
	Rift = 420,
	King = 0,
} :: { [string]: number }

-- Single-letter symbols for compact notation and server logs.
Config.PieceSymbol = {
	Pawn = "",
	Knight = "N",
	Bishop = "B",
	Rook = "R",
	Queen = "Q",
	King = "K",
	Hexer = "H",
	Rift = "X",
} :: { [string]: string }

-- Back rank from file a to file j. Hexer sits on d and Rift on g, mirroring
-- the standard queen/bishop side split so both armies stay symmetric.
Config.InitialBackRank = {
	"Rook",
	"Knight",
	"Bishop",
	"Hexer",
	"Queen",
	"King",
	"Rift",
	"Bishop",
	"Knight",
	"Rook",
}

-- Anything a pawn may become on the far rank. The custom pieces are included:
-- promoting into a Hexer or Rift is a real choice, not a novelty.
Config.PromotionChoices = { "Queen", "Rook", "Bishop", "Knight", "Hexer", "Rift" }

return Config
