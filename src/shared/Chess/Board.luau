--!strict
-- The board grid and the game state that travels with it.
--
-- Coordinates are file 1..10 (a..j) and rank 1..8. Rank 1 is White's back
-- rank. The grid is grid[file][rank] = piece | nil, where a piece is
-- { type: string, color: string, id: number }.
--
-- This module has no rules in it. It only knows how to build, copy, and
-- describe a position, so both the rules engine and the bot can share it.

local Config = require(script.Parent.Config)

local Board = {}

export type Piece = {
	type: string,
	color: string,
	id: number,
}

export type Square = {
	file: number,
	rank: number,
}

export type CastlingRights = {
	White: { Kingside: boolean, Queenside: boolean },
	Black: { Kingside: boolean, Queenside: boolean },
}

export type GameState = {
	grid: { [number]: { [number]: Piece? } },
	turn: string,
	castling: CastlingRights,
	-- Target square behind a pawn that just advanced two, or nil.
	enPassant: Square?,
	halfmove: number,
	fullmove: number,
	-- True while that side still has its one Hexer swap available.
	hexerSwap: { White: boolean, Black: boolean },
	-- Position keys seen so far, for threefold repetition.
	repetition: { [string]: number },
}

local NEXT_PIECE_ID = 1

local function newPiece(pieceType: string, color: string): Piece
	NEXT_PIECE_ID += 1
	return {
		type = pieceType,
		color = color,
		id = NEXT_PIECE_ID,
	}
end

function Board.newGrid(): { [number]: { [number]: Piece? } }
	local grid = {}
	for file = 1, Config.Files do
		local column = {}
		for rank = 1, Config.Ranks do
			column[rank] = nil
		end
		grid[file] = column
	end
	return grid
end

function Board.cloneGrid(grid: { [number]: { [number]: Piece? } }): { [number]: { [number]: Piece? } }
	local copy = {}
	for file = 1, Config.Files do
		local source = grid[file]
		local column = {}
		for rank = 1, Config.Ranks do
			column[rank] = source[rank]
		end
		copy[file] = column
	end
	return copy
end

function Board.inBounds(file: number, rank: number): boolean
	return file >= 1 and file <= Config.Files and rank >= 1 and rank <= Config.Ranks
end

function Board.get(grid: { [number]: { [number]: Piece? } }, file: number, rank: number): Piece?
	if not Board.inBounds(file, rank) then
		return nil
	end
	return grid[file][rank]
end

function Board.set(grid: { [number]: { [number]: Piece? } }, file: number, rank: number, piece: Piece?)
	if not Board.inBounds(file, rank) then
		return
	end
	grid[file][rank] = piece
end

-- Human-readable square name, e.g. (3, 2) -> "c2".
function Board.squareName(file: number, rank: number): string
	local letter = Config.FileLetters[file] or "?"
	return letter .. tostring(rank)
end

-- Parses "c2" into { file = 3, rank = 2 }. Returns nil for anything malformed.
function Board.parseSquare(name: string): Square?
	local letter, rankText = string.match(name, "^(%a)(%d+)$")
	if not letter or not rankText then
		return nil
	end
	local lowered = string.lower(letter)
	local file = nil
	for index, candidate in Config.FileLetters do
		if candidate == lowered then
			file = index
			break
		end
	end
	local rank = tonumber(rankText)
	if not file or not rank or not Board.inBounds(file, rank) then
		return nil
	end
	return { file = file, rank = rank }
end

function Board.newGame(): GameState
	local grid = Board.newGrid()

	for file = 1, Config.Files do
		Board.set(grid, file, 1, newPiece(Config.InitialBackRank[file], Config.White))
		Board.set(grid, file, 2, newPiece("Pawn", Config.White))
		Board.set(grid, file, 7, newPiece("Pawn", Config.Black))
		Board.set(grid, file, 8, newPiece(Config.InitialBackRank[file], Config.Black))
	end

	local state: GameState = {
		grid = grid,
		turn = Config.White,
		castling = {
			White = { Kingside = true, Queenside = true },
			Black = { Kingside = true, Queenside = true },
		},
		enPassant = nil,
		halfmove = 0,
		fullmove = 1,
		hexerSwap = { White = true, Black = true },
		repetition = {},
	}

	state.repetition[Board.positionKey(state)] = 1
	return state
end

-- `fast` skips the repetition table, which the bot's search never reads. Games
-- always clone with the full state so threefold detection stays correct.
function Board.cloneState(state: GameState, fast: boolean?): GameState
	local repetition = {} :: { [string]: number }
	if not fast then
		for key, count in state.repetition do
			repetition[key] = count
		end
	end

	return {
		grid = Board.cloneGrid(state.grid),
		turn = state.turn,
		castling = {
			White = {
				Kingside = state.castling.White.Kingside,
				Queenside = state.castling.White.Queenside,
			},
			Black = {
				Kingside = state.castling.Black.Kingside,
				Queenside = state.castling.Black.Queenside,
			},
		},
		enPassant = state.enPassant and { file = state.enPassant.file, rank = state.enPassant.rank } or nil,
		halfmove = state.halfmove,
		fullmove = state.fullmove,
		hexerSwap = {
			White = state.hexerSwap.White,
			Black = state.hexerSwap.Black,
		},
		repetition = repetition,
	}
end

-- Everything that makes two positions legally identical, cheaply serialized.
-- Used for repetition detection, not for display.
function Board.positionKey(state: GameState): string
	local parts = {}
	for rank = Config.Ranks, 1, -1 do
		for file = 1, Config.Files do
			local piece = Board.get(state.grid, file, rank)
			if piece then
				local symbol = Config.PieceSymbol[piece.type] or "?"
				if piece.type == "Pawn" then
					symbol = "p"
				end
				if piece.color == Config.White then
					symbol = string.upper(symbol)
				else
					symbol = string.lower(symbol)
				end
				table.insert(parts, symbol)
			else
				table.insert(parts, ".")
			end
		end
	end

	local castling = ""
	if state.castling.White.Kingside then
		castling ..= "K"
	end
	if state.castling.White.Queenside then
		castling ..= "Q"
	end
	if state.castling.Black.Kingside then
		castling ..= "k"
	end
	if state.castling.Black.Queenside then
		castling ..= "q"
	end
	if castling == "" then
		castling = "-"
	end

	local ep = "-"
	if state.enPassant then
		ep = Board.squareName(state.enPassant.file, state.enPassant.rank)
	end

	return table.concat(parts) .. "|" .. state.turn .. "|" .. castling .. "|" .. ep
end

-- Finds the square holding a side's king. Returns nil only for a malformed
-- position; real games always have exactly one king per side.
function Board.findKing(state: GameState, color: string): Square?
	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local piece = Board.get(state.grid, file, rank)
			if piece and piece.color == color and piece.type == "King" then
				return { file = file, rank = rank }
			end
		end
	end
	return nil
end

-- Sum of centipawn values on the board for one side, excluding the king.
function Board.material(state: GameState, color: string): number
	local total = 0
	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local piece = Board.get(state.grid, file, rank)
			if piece and piece.color == color then
				total += Config.PieceValue[piece.type] or 0
			end
		end
	end
	return total
end

-- All pieces of one side, as { square, piece } entries. Move generation and
-- the bot both walk this.
function Board.piecesOf(state: GameState, color: string): { { square: Square, piece: Piece } }
	local found = {}
	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local piece = Board.get(state.grid, file, rank)
			if piece and piece.color == color then
				table.insert(found, {
					square = { file = file, rank = rank },
					piece = piece,
				})
			end
		end
	end
	return found
end

return Board
