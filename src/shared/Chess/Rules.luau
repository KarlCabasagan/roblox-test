--!strict
-- Legal move filtering, move application, and terminal position detection.
--
-- Moves.luau produces pseudo-legal moves; this module removes any move that
-- would leave the mover's king attacked, applies the survivors to a copy of
-- the state, and reports checkmate / stalemate / draw conditions.

local Config = require(script.Parent.Config)
local Board = require(script.Parent.Board)
local Moves = require(script.Parent.Moves)

local Rules = {}

export type Move = Moves.Move

-- True when `color`'s king is attacked in this position.
function Rules.isInCheck(state: Board.GameState, color: string): boolean
	local king = Board.findKing(state, color)
	if not king then
		-- A position without a king is already lost; treat it as checked so
		-- the mover cannot wander further.
		return true
	end
	return Moves.isAttacked(state, king, Config.Other[color])
end

-- Applies a move to a copy of the state and returns the new state. The input
-- state is never modified. Callers are expected to pass a legal move; this
-- function does not re-validate.
--
-- `fast` skips repetition bookkeeping, which the bot's search never reads and
-- which costs a full position serialization per node.
function Rules.apply(state: Board.GameState, move: Move, fast: boolean?): Board.GameState
	local next_ = Board.cloneState(state, fast)
	local grid = next_.grid
	local color = move.color
	local other = Config.Other[color]

	local movingPiece = Board.get(grid, move.from.file, move.from.rank)
	if not movingPiece then
		return next_
	end

	local isCapture = move.capture ~= nil

	if move.swap then
		-- Hexer trades squares with a friendly piece. No material changes
		-- hands, and the swap is single-use for that side.
		local target = Board.get(grid, move.swap.file, move.swap.rank)
		Board.set(grid, move.from.file, move.from.rank, target)
		Board.set(grid, move.swap.file, move.swap.rank, movingPiece)
		next_.hexerSwap[color] = false
		next_.halfmove += 1
	else
		-- Remove the captured piece. En passant victims stand on a different
		-- square from the destination.
		if move.enPassant and move.capture then
			Board.set(grid, move.to.file, move.from.rank, nil)
		elseif move.capture then
			Board.set(grid, move.to.file, move.to.rank, nil)
		end

		Board.set(grid, move.from.file, move.from.rank, nil)
		Board.set(grid, move.to.file, move.to.rank, movingPiece)

		-- Castling also relocates the rook, which jumps over the king.
		if move.castle == "Kingside" then
			local rook = Board.get(grid, 10, move.to.rank)
			Board.set(grid, 10, move.to.rank, nil)
			Board.set(grid, 7, move.to.rank, rook)
		elseif move.castle == "Queenside" then
			local rook = Board.get(grid, 1, move.to.rank)
			Board.set(grid, 1, move.to.rank, nil)
			Board.set(grid, 5, move.to.rank, rook)
		end

		if move.promotion then
			local promoted = Board.get(grid, move.to.file, move.to.rank)
			if promoted then
				-- Replace rather than mutate: cloned grids share piece tables
				-- with the parent state, so writing .type here would corrupt
				-- the position we branched from.
				Board.set(grid, move.to.file, move.to.rank, {
					type = move.promotion,
					color = promoted.color,
					id = promoted.id,
				})
			end
		end

		-- Halfmove clock: pawn moves and captures reset it.
		if movingPiece.type == "Pawn" or isCapture then
			next_.halfmove = 0
		else
			next_.halfmove += 1
		end
	end

	-- Castling rights fall away when the king moves or a rook leaves / dies
	-- on its corner.
	local homeRank = if color == Config.White then 1 else 8
	local otherHomeRank = if other == Config.White then 1 else 8
	if movingPiece.type == "King" then
		next_.castling[color].Kingside = false
		next_.castling[color].Queenside = false
	elseif movingPiece.type == "Rook" then
		if move.from.file == 10 and move.from.rank == homeRank then
			next_.castling[color].Kingside = false
		elseif move.from.file == 1 and move.from.rank == homeRank then
			next_.castling[color].Queenside = false
		end
	end

	if isCapture then
		if move.to.file == 10 and move.to.rank == otherHomeRank then
			next_.castling[other].Kingside = false
		elseif move.to.file == 1 and move.to.rank == otherHomeRank then
			next_.castling[other].Queenside = false
		end
	end

	-- A two-square pawn advance creates a capture target for one turn.
	next_.enPassant = nil
	if movingPiece.type == "Pawn" and math.abs(move.to.rank - move.from.rank) == 2 then
		next_.enPassant = {
			file = move.from.file,
			rank = math.floor((move.to.rank + move.from.rank) / 2),
		}
	end

	if color == Config.Black then
		next_.fullmove += 1
	end
	next_.turn = other

	if not fast then
		local key = Board.positionKey(next_)
		next_.repetition[key] = (next_.repetition[key] or 0) + 1
	end

	return next_
end

-- Castling has two extra conditions beyond "the king ends up safe": the king
-- may not start in check, and may not pass through an attacked square.
local function castlePassesSafety(state: Board.GameState, move: Move): boolean
	if not move.castle then
		return true
	end
	local color = move.color
	local enemy = Config.Other[color]
	local rank = move.from.rank

	if Moves.isAttacked(state, { file = move.from.file, rank = rank }, enemy) then
		return false
	end

	local transitFile = if move.castle == "Kingside" then 7 else 5
	return not Moves.isAttacked(state, { file = transitFile, rank = rank }, enemy)
end

-- Every legal move for the side to move.
function Rules.legalMoves(state: Board.GameState): { Move }
	return Rules.legalMovesFor(state, state.turn)
end

function Rules.legalMovesFor(state: Board.GameState, color: string): { Move }
	local legal: { Move } = {}
	for _, move in Moves.forColor(state, color) do
		if castlePassesSafety(state, move) then
			local after = Rules.apply(state, move)
			if not Rules.isInCheck(after, color) then
				table.insert(legal, move)
			end
		end
	end
	return legal
end

function Rules.legalMovesFrom(state: Board.GameState, square: Board.Square): { Move }
	local legal: { Move } = {}
	for _, move in Moves.forSquare(state, square) do
		if castlePassesSafety(state, move) then
			local after = Rules.apply(state, move)
			if not Rules.isInCheck(after, move.color) then
				table.insert(legal, move)
			end
		end
	end
	return legal
end

-- Finds the legal move (or promotion variant) matching the requested squares.
function Rules.findMove(
	state: Board.GameState,
	from: Board.Square,
	to: Board.Square,
	promotion: string?
): Move?
	for _, move in Rules.legalMoves(state) do
		if move.from.file == from.file and move.from.rank == from.rank then
			if move.to.file == to.file and move.to.rank == to.rank then
				if not move.promotion then
					return move
				end
				if move.promotion == promotion then
					return move
				end
			end
		end
	end
	return nil
end

export type Status = {
	over: boolean,
	-- "WhiteWin", "BlackWin", or "Draw". Nil while the game continues.
	result: string?,
	reason: string?,
	inCheck: boolean,
}

-- Draws where neither side can force mate. With the custom pieces on the
-- board this only triggers for the bare-minimum material cases.
local function isInsufficientMaterial(state: Board.GameState): boolean
	local minors = { White = 0, Black = 0 }
	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local piece = Board.get(state.grid, file, rank)
			if piece then
				if piece.type == "Pawn" or piece.type == "Rook" or piece.type == "Queen" then
					return false
				elseif piece.type == "Hexer" or piece.type == "Rift" then
					-- Both retain mating potential with a king's help.
					return false
				elseif piece.type == "Knight" or piece.type == "Bishop" then
					minors[piece.color] += 1
				end
			end
		end
	end
	return minors.White <= 1 and minors.Black <= 1
end

function Rules.status(state: Board.GameState): Status
	local color = state.turn
	local inCheck = Rules.isInCheck(state, color)
	local hasMove = #Rules.legalMovesFor(state, color) > 0

	if not hasMove then
		if inCheck then
			return {
				over = true,
				result = if color == Config.White then "BlackWin" else "WhiteWin",
				reason = "Checkmate",
				inCheck = true,
			}
		end
		return { over = true, result = "Draw", reason = "Stalemate", inCheck = false }
	end

	if state.halfmove >= 100 then
		return { over = true, result = "Draw", reason = "FiftyMoveRule", inCheck = inCheck }
	end

	local key = Board.positionKey(state)
	if (state.repetition[key] or 0) >= 3 then
		return { over = true, result = "Draw", reason = "ThreefoldRepetition", inCheck = inCheck }
	end

	if isInsufficientMaterial(state) then
		return { over = true, result = "Draw", reason = "InsufficientMaterial", inCheck = inCheck }
	end

	return { over = false, result = nil, reason = nil, inCheck = inCheck }
end

-- Compact text form, used in server logs and for debugging games after the
-- fact. Algebraic enough to read, not strict SAN.
function Rules.toNotation(move: Move): string
	if move.swap then
		return "H" .. Board.squareName(move.from.file, move.from.rank) .. ">" .. Board.squareName(move.to.file, move.to.rank)
	end

	local prefix = Config.PieceSymbol[move.pieceType] or "?"
	local from = Board.squareName(move.from.file, move.from.rank)
	local to = Board.squareName(move.to.file, move.to.rank)
	local separator = if move.capture then "x" else "-"
	local suffix = if move.promotion then "=" .. (Config.PieceSymbol[move.promotion] or "Q") else ""
	return prefix .. from .. separator .. to .. suffix
end

return Rules
