--!strict
-- Conversion between the engine's live state and the flat tables that travel
-- over RemoteEvents.
--
-- A full snapshot is small enough (at most 40 occupied squares) that every
-- state change rebroadcasts the whole position rather than streaming deltas.
-- That keeps the client stateless: it renders whatever it was last handed.

local Config = require(script.Parent.Config)
local Board = require(script.Parent.Board)
local Rules = require(script.Parent.Rules)

local Serialize = {}

export type WireSquare = { number }

export type Snapshot = {
	-- { file, rank, type, color, id } for every occupied square.
	squares: { { number } },
	turn: string,
	halfmove: number,
	fullmove: number,
	castling: any,
	enPassant: any,
	hexerSwap: any,
	status: any,
	-- Everything below is match metadata, not chess state.
	phase: string,
	mode: string?,
	difficulty: string?,
	white: number?,
	black: number?,
	lastMove: any,
	result: string?,
	reason: string?,
}

-- Serializes a position plus the match metadata around it.
function Serialize.snapshot(state: Board.GameState, meta: { [string]: any }?): Snapshot
	local squares = {}
	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local piece = Board.get(state.grid, file, rank)
			if piece then
				table.insert(squares, { file, rank, piece.type, piece.color, piece.id })
			end
		end
	end

	local snapshot = {
		squares = squares,
		turn = state.turn,
		halfmove = state.halfmove,
		fullmove = state.fullmove,
		castling = state.castling,
		enPassant = state.enPassant,
		hexerSwap = state.hexerSwap,
		status = Rules.status(state),
		phase = "Active",
		mode = nil,
		difficulty = nil,
		white = nil,
		black = nil,
		lastMove = nil,
		result = nil,
		reason = nil,
	}

	if meta then
		for key, value in meta do
			snapshot[key] = value
		end
	end

	return snapshot :: Snapshot
end

-- Rebuilds a display grid from a snapshot, keyed the same way as the engine's
-- grid so board coordinates and rendering logic stay in sync.
function Serialize.gridFromSnapshot(snapshot: Snapshot): { [number]: { [number]: any } }
	local grid = Board.newGrid()
	for _, entry in snapshot.squares do
		local file, rank, pieceType, color, id = entry[1], entry[2], entry[3], entry[4], entry[5]
		if Board.inBounds(file, rank) then
			grid[file][rank] = { type = pieceType, color = color, id = id }
		end
	end
	return grid
end

return Serialize
