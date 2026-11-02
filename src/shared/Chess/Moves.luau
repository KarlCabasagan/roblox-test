--!strict
-- Pseudo-legal move generation.
--
-- "Pseudo-legal" means the moves respect piece movement, occupancy, and whose
-- turn it is, but do not yet check whether they leave the mover's own king in
-- check. Rules.luau applies that filter. Keeping the split lets the attack
-- detector and the generator stay independent of each other.

local Config = require(script.Parent.Config)
local Board = require(script.Parent.Board)

local Moves = {}

local ORTHOGONAL = {
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
}

local DIAGONAL = {
	{ 1, 1 },
	{ 1, -1 },
	{ -1, 1 },
	{ -1, -1 },
}

local ALL_DIRECTIONS = {
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
	{ 1, 1 },
	{ 1, -1 },
	{ -1, 1 },
	{ -1, -1 },
}

local KNIGHT_OFFSETS = {
	{ 1, 2 },
	{ 2, 1 },
	{ 2, -1 },
	{ 1, -2 },
	{ -1, -2 },
	{ -2, -1 },
	{ -2, 1 },
	{ -1, 2 },
}

-- The Rift leaps exactly two squares: straight and diagonal, over anything.
local RIFT_OFFSETS = {
	{ 2, 0 },
	{ -2, 0 },
	{ 0, 2 },
	{ 0, -2 },
	{ 2, 2 },
	{ 2, -2 },
	{ -2, 2 },
	{ -2, -2 },
}

local KING_OFFSETS = ALL_DIRECTIONS

-- Pawns advance toward increasing rank for White, decreasing for Black.
local function pawnDirection(color: string): number
	return if color == Config.White then 1 else -1
end

-- Rank a pawn of this color starts on, and the rank it promotes on.
local function pawnHomeRank(color: string): number
	return if color == Config.White then 2 else 7
end

local function pawnPromotionRank(color: string): number
	return if color == Config.White then 8 else 1
end

Moves.pawnHomeRank = pawnHomeRank
Moves.pawnPromotionRank = pawnPromotionRank
Moves.pawnDirection = pawnDirection

export type Move = {
	from: Board.Square,
	to: Board.Square,
	pieceType: string,
	color: string,
	capture: Board.Piece?,
	-- Set only when the move lands a pawn on the far rank.
	promotion: string?,
	-- En passant captures a pawn that is not on the destination square.
	enPassant: boolean?,
	castle: string?,
	-- Hexer's once-per-game trade with a friendly piece.
	swap: Board.Square?,
}

local function newMove(from: Board.Square, to: Board.Square, piece: Board.Piece): Move
	return {
		from = { file = from.file, rank = from.rank },
		to = { file = to.file, rank = to.rank },
		pieceType = piece.type,
		color = piece.color,
		capture = nil,
	}
end

-- Slides outward from a square until the ray hits an edge, a friendly piece
-- (blocked), or an enemy piece (capturable, then blocked).
local function addSlideMoves(
	state: Board.GameState,
	from: Board.Square,
	piece: Board.Piece,
	directions: { { number } },
	moves: { Move }
)
	for _, direction in directions do
		local dx, dy = direction[1], direction[2]
		local file, rank = from.file + dx, from.rank + dy
		while Board.inBounds(file, rank) do
			local occupant = Board.get(state.grid, file, rank)
			if occupant then
				if occupant.color ~= piece.color then
					local move = newMove(from, { file = file, rank = rank }, piece)
					move.capture = occupant
					table.insert(moves, move)
				end
				break
			end
			table.insert(moves, newMove(from, { file = file, rank = rank }, piece))
			file += dx
			rank += dy
		end
	end
end

-- Leapers ignore occupancy between origin and destination.
local function addLeapMoves(
	state: Board.GameState,
	from: Board.Square,
	piece: Board.Piece,
	offsets: { { number } },
	moves: { Move }
)
	for _, offset in offsets do
		local file, rank = from.file + offset[1], from.rank + offset[2]
		if Board.inBounds(file, rank) then
			local occupant = Board.get(state.grid, file, rank)
			if not occupant then
				table.insert(moves, newMove(from, { file = file, rank = rank }, piece))
			elseif occupant.color ~= piece.color then
				local move = newMove(from, { file = file, rank = rank }, piece)
				move.capture = occupant
				table.insert(moves, move)
			end
		end
	end
end

local function addPawnMoves(state: Board.GameState, from: Board.Square, piece: Board.Piece, moves: { Move })
	local dir = pawnDirection(piece.color)
	local startRank = pawnHomeRank(piece.color)
	local promoRank = pawnPromotionRank(piece.color)

	local function addPawnAdvance(targetFile: number, targetRank: number, capture: Board.Piece?, isEnPassant: boolean?)
		if not Board.inBounds(targetFile, targetRank) then
			return
		end
		local move = newMove(from, { file = targetFile, rank = targetRank }, piece)
		move.capture = capture
		if isEnPassant then
			move.enPassant = true
		end
		if targetRank == promoRank then
			for _, choice in Config.PromotionChoices do
				local promoted = table.clone(move)
				promoted.promotion = choice
				table.insert(moves, promoted)
			end
		else
			table.insert(moves, move)
		end
	end

	-- One square forward, only into an empty square.
	local oneRank = from.rank + dir
	if Board.inBounds(from.file, oneRank) and not Board.get(state.grid, from.file, oneRank) then
		addPawnAdvance(from.file, oneRank, nil, false)

		-- Two squares, from the home rank, with both squares empty.
		local twoRank = from.rank + dir * 2
		if from.rank == startRank and not Board.get(state.grid, from.file, twoRank) then
			addPawnAdvance(from.file, twoRank, nil, false)
		end
	end

	-- Diagonal captures.
	for _, side in { -1, 1 } do
		local targetFile = from.file + side
		local targetRank = from.rank + dir
		local victim = Board.get(state.grid, targetFile, targetRank)
		if victim and victim.color ~= piece.color then
			addPawnAdvance(targetFile, targetRank, victim, false)
		end
	end

	-- En passant: the target square sits behind an adjacent enemy pawn.
	local ep = state.enPassant
	if ep and ep.rank == from.rank + dir and math.abs(ep.file - from.file) == 1 then
		local victim = Board.get(state.grid, ep.file, from.rank)
		if victim and victim.color ~= piece.color and victim.type == "Pawn" then
			addPawnAdvance(ep.file, ep.rank, victim, true)
		end
	end
end

local function addCastlingMoves(state: Board.GameState, from: Board.Square, piece: Board.Piece, moves: { Move })
	local rights = state.castling[piece.color]
	if not rights or (not rights.Kingside and not rights.Queenside) then
		return
	end

	-- The king starts on file 6 for both sides; rooks sit on files 1 and 10.
	local homeRank = if piece.color == Config.White then 1 else 8
	if from.file ~= 6 or from.rank ~= homeRank then
		return
	end

	local function pathIsClear(fileFrom: number, fileTo: number): boolean
		local step = if fileTo > fileFrom then 1 else -1
		local file = fileFrom + step
		while file ~= fileTo do
			if Board.get(state.grid, file, homeRank) then
				return false
			end
			file += step
		end
		return true
	end

	if rights.Kingside then
		local rook = Board.get(state.grid, 10, homeRank)
		if
			rook
			and rook.type == "Rook"
			and rook.color == piece.color
			and pathIsClear(6, 10)
		then
			local move = newMove(from, { file = 8, rank = homeRank }, piece)
			move.castle = "Kingside"
			table.insert(moves, move)
		end
	end

	if rights.Queenside then
		local rook = Board.get(state.grid, 1, homeRank)
		if
			rook
			and rook.type == "Rook"
			and rook.color == piece.color
			and pathIsClear(6, 1)
		then
			local move = newMove(from, { file = 4, rank = homeRank }, piece)
			move.castle = "Queenside"
			table.insert(moves, move)
		end
	end
end

-- The Hexer's one trick: trade places with a friendly piece anywhere on the
-- board. It inherits whatever square that piece occupied, so it can never
-- escape check by itself — Rules.luau still verifies the king afterwards.
local function addHexerSwapMoves(state: Board.GameState, from: Board.Square, piece: Board.Piece, moves: { Move })
	if not state.hexerSwap[piece.color] then
		return
	end
	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local other = Board.get(state.grid, file, rank)
			if other and other.color == piece.color and other.id ~= piece.id and other.type ~= "King" then
				local move = newMove(from, { file = file, rank = rank }, piece)
				move.swap = { file = file, rank = rank }
				-- A swap takes no material, even in passing.
				move.capture = nil
				table.insert(moves, move)
			end
		end
	end
end

-- Pseudo-legal moves for the piece standing on a square. Empty list if the
-- square is empty or holds a piece that cannot move (the King always can).
function Moves.forSquare(state: Board.GameState, square: Board.Square): { Move }
	local piece = Board.get(state.grid, square.file, square.rank)
	if not piece then
		return {}
	end

	local moves: { Move } = {}

	if piece.type == "Pawn" then
		addPawnMoves(state, square, piece, moves)
	elseif piece.type == "Knight" then
		addLeapMoves(state, square, piece, KNIGHT_OFFSETS, moves)
	elseif piece.type == "Bishop" then
		addSlideMoves(state, square, piece, DIAGONAL, moves)
	elseif piece.type == "Rook" then
		addSlideMoves(state, square, piece, ORTHOGONAL, moves)
	elseif piece.type == "Queen" then
		addSlideMoves(state, square, piece, ALL_DIRECTIONS, moves)
	elseif piece.type == "Hexer" then
		addSlideMoves(state, square, piece, DIAGONAL, moves)
		addHexerSwapMoves(state, square, piece, moves)
	elseif piece.type == "Rift" then
		addLeapMoves(state, square, piece, RIFT_OFFSETS, moves)
	elseif piece.type == "King" then
		addLeapMoves(state, square, piece, KING_OFFSETS, moves)
		addCastlingMoves(state, square, piece, moves)
	end

	return moves
end

-- Pseudo-legal moves for every piece of one side.
function Moves.forColor(state: Board.GameState, color: string): { Move }
	local moves: { Move } = {}
	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local piece = Board.get(state.grid, file, rank)
			if piece and piece.color == color then
				local square = { file = file, rank = rank }
				for _, move in Moves.forSquare(state, square) do
					table.insert(moves, move)
				end
			end
		end
	end
	return moves
end

-- True when any piece of `byColor` could capture on `square` right now.
-- This is the engine's only definition of "attacked", so check detection and
-- castling safety both route through it. Occupancy of `square` is ignored:
-- a king cannot step onto a square it is attacking with its own body.
function Moves.isAttacked(state: Board.GameState, square: Board.Square, byColor: string): boolean
	local file, rank = square.file, square.rank

	-- Pawns capture diagonally one rank forward, so look one rank *back*.
	local pawnRank = if byColor == Config.White then rank - 1 else rank + 1
	for _, side in { -1, 1 } do
		local pawn = Board.get(state.grid, file + side, pawnRank)
		if pawn and pawn.color == byColor and pawn.type == "Pawn" then
			return true
		end
	end

	for _, offset in KNIGHT_OFFSETS do
		local piece = Board.get(state.grid, file + offset[1], rank + offset[2])
		if piece and piece.color == byColor and piece.type == "Knight" then
			return true
		end
	end

	for _, offset in RIFT_OFFSETS do
		local piece = Board.get(state.grid, file + offset[1], rank + offset[2])
		if piece and piece.color == byColor and piece.type == "Rift" then
			return true
		end
	end

	for _, direction in KING_OFFSETS do
		local piece = Board.get(state.grid, file + direction[1], rank + direction[2])
		if piece and piece.color == byColor and piece.type == "King" then
			return true
		end
	end

	local function rayHits(offsets: { { number } }, wanted: { string })
		for _, direction in offsets do
			local dx, dy = direction[1], direction[2]
			local probeFile, probeRank = file + dx, rank + dy
			while Board.inBounds(probeFile, probeRank) do
				local piece = Board.get(state.grid, probeFile, probeRank)
				if piece then
					if piece.color == byColor and table.find(wanted, piece.type) then
						return true
					end
					break
				end
				probeFile += dx
				probeRank += dy
			end
		end
		return false
	end

	if rayHits(ORTHOGONAL, { "Rook", "Queen" }) then
		return true
	end
	if rayHits(DIAGONAL, { "Bishop", "Queen", "Hexer" }) then
		return true
	end

	return false
end

return Moves
