--!strict
-- Opponent for solo play and training matches.
--
-- Three tiers, chosen before a match starts:
--   Easy   - a random legal move. Punishes only real blunders.
--   Medium - 2-ply search with material and mobility evaluation.
--   Hard   - 3-ply alpha-beta with the same evaluation.
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

-- Negamax with alpha-beta pruning. `forColor` is the side being optimized;
-- scores are always returned from that side's point of view.
local function search(
	state: Board.GameState,
	depth: number,
	alpha: number,
	beta: number,
	forColor: string,
	ply: number
): number
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

	local best = -math.huge
	for _, move in moves do
		local child = Rules.apply(state, move)
		local score = -search(child, depth - 1, -beta, -alpha, Config.Other[state.turn], ply + 1)
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

-- Scores every legal move from the mover's perspective. Used by Medium and
-- Hard so the caller can see how close the choice was, not just the winner.
local function rankMoves(state: Board.GameState, depth: number): { { move: Moves.Move, score: number } }
	local scored = {}
	for _, move in Rules.legalMoves(state) do
		local child = Rules.apply(state, move)
		local score = -search(child, depth - 1, -math.huge, math.huge, Config.Other[state.turn], 1)
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

-- Picks a move for the side to move at the requested difficulty.
function Bot.chooseMove(state: Board.GameState, difficulty: string): Moves.Move?
	local moves = Rules.legalMoves(state)
	if #moves == 0 then
		return nil
	end

	if difficulty == "Easy" then
		return randomOf(moves)
	end

	-- Medium searches one reply deeper than its name suggests: a 2-ply search
	-- is depth 2 including the bot's own move, so the opponent's answer is
	-- always seen.
	local depth = if difficulty == "Hard" then 3 else 2
	local scored = rankMoves(state, depth)

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
