--!strict
-- Opponent for solo play and training matches.
--
-- Three tiers, chosen before a match starts:
--   Easy   - a random legal move. Punishes only real blunders.
--   Medium - 2-ply search with material and mobility evaluation.
--   Hard   - 3-ply alpha-beta with the same evaluation.
--
-- The search is wall-clock bounded. A deep position or a slow machine can
-- always abandon a partial search and return the best move found so far;
-- that property is what keeps a bot turn from ever freezing the server.
--
-- Everything here is pure: no waits, no state outside the arguments, so it can
-- be exercised headlessly without Studio's scheduler.

local Config = require(script.Parent.Config)
local Board = require(script.Parent.Board)
local Moves = require(script.Parent.Moves)
local Rules = require(script.Parent.Rules)

local Bot = {}

Bot.Difficulties = { "Easy", "Medium", "Hard" }

local MATE_SCORE = 100000

-- Default thinking time per move, in seconds.
local DEFAULT_BUDGET = 1.0

export type SearchContext = {
	deadline: number,
	aborted: boolean,
}

-- Material balance plus a light mobility term. Pawns get a small push for
-- advancing, which stops the bot from leaving them parked on their home rank
-- when nothing else is happening.
local function evaluate(state: Board.GameState, forColor: string): number
	local other = Config.Other[forColor]
	local score = Board.material(state, forColor) - Board.material(state, other)

	local myMoves = #Moves.forColor(state, forColor)
	local theirMoves = #Moves.forColor(state, other)
	score += (myMoves - theirMoves) * 2

	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local piece = Board.get(state.grid, file, rank)
			if piece and piece.type == "Pawn" then
				if piece.color == Config.White then
					score += (rank - 2) * 4
				else
					score -= (7 - rank) * 4
				end
			end
		end
	end

	return score
end

-- Captures first, biggest victim first. Pruning is only as good as the first
-- move considered, and a 3-ply search on an opening position needs it.
local function orderMoves(moves: { Moves.Move })
	table.sort(moves, function(a, b)
		local aValue = if a.capture then (Config.PieceValue[a.capture.type] or 0) else -1
		local bValue = if b.capture then (Config.PieceValue[b.capture.type] or 0) else -1
		return aValue > bValue
	end)
end

local function outOfTime(context: SearchContext): boolean
	if context.aborted then
		return true
	end
	if os.clock() > context.deadline then
		context.aborted = true
		return true
	end
	return false
end

-- Negamax with alpha-beta pruning. `forColor` is the side being optimized;
-- scores are always returned from that side's point of view.
local function search(
	state: Board.GameState,
	depth: number,
	alpha: number,
	beta: number,
	forColor: string,
	ply: number,
	context: SearchContext
): number
	if outOfTime(context) then
		return evaluate(state, forColor)
	end

	local moves = Rules.legalMovesFor(state, state.turn)

	if #moves == 0 then
		if Rules.isInCheck(state, state.turn) then
			-- Prefer faster mates: a mate found closer to the root scores higher.
			local sign = if state.turn == forColor then -1 else 1
			return sign * (MATE_SCORE - ply)
		end
		return 0
	end

	if depth == 0 then
		return evaluate(state, forColor)
	end

	orderMoves(moves)

	local best = -math.huge
	for _, move in moves do
		local child = Rules.apply(state, move, true)
		local score = -search(child, depth - 1, -beta, -alpha, Config.Other[state.turn], ply + 1, context)
		if score > best then
			best = score
		end
		if best > alpha then
			alpha = best
		end
		if alpha >= beta then
			break
		end
	end

	return best
end

-- Scores every legal move from the mover's perspective.
local function rankMoves(
	state: Board.GameState,
	depth: number,
	context: SearchContext
): { { move: Moves.Move, score: number } }
	local scored = {}
	local moves = Rules.legalMoves(state)
	orderMoves(moves)

	for _, move in moves do
		if outOfTime(context) then
			break
		end
		local child = Rules.apply(state, move, true)
		local score = -search(child, depth - 1, -math.huge, math.huge, Config.Other[state.turn], 1, context)
		table.insert(scored, { move = move, score = score })
	end

	return scored
end

local function randomOf(moves: { Moves.Move }): Moves.Move?
	if #moves == 0 then
		return nil
	end
	return moves[math.random(1, #moves)]
end

-- Picks a move for the side to move at the requested difficulty. Returns nil
-- only when the side has no legal moves at all.
function Bot.chooseMove(state: Board.GameState, difficulty: string, timeBudget: number?): Moves.Move?
	local moves = Rules.legalMoves(state)
	if #moves == 0 then
		return nil
	end

	if difficulty == "Easy" then
		return randomOf(moves)
	end

	local budget = timeBudget or DEFAULT_BUDGET
	local context: SearchContext = {
		deadline = os.clock() + budget,
		aborted = false,
	}

	local depth = if difficulty == "Hard" then 3 else 2
	local scored = rankMoves(state, depth, context)

	-- If the clock ran out before a single move was scored, fall back to a
	-- random legal move rather than forcing the caller to handle nil.
	if #scored == 0 then
		return randomOf(moves)
	end

	local bestScore = -math.huge
	local bestMoves = {}
	for _, entry in scored do
		if entry.score > bestScore + 0.001 then
			bestScore = entry.score
			bestMoves = { entry.move }
		elseif math.abs(entry.score - bestScore) <= 0.001 then
			table.insert(bestMoves, entry.move)
		end
	end

	-- Random tie-break keeps repeated training games from being identical.
	return randomOf(bestMoves)
end

-- Exposed for tests and for the HUD, which can show a rough evaluation.
function Bot.evaluate(state: Board.GameState, forColor: string): number
	return evaluate(state, forColor)
end

return Bot
