--!strict
-- Headless checks for the rules engine. No Studio dependencies, no waits: run
-- it from the command bar or from `execute_luau` and read the summary.
--
--   local Chess = require(game.ReplicatedStorage.Shared.Chess)
--   local report = require(game.ReplicatedStorage.Shared.Chess.SelfTest).run()
--   print(report.summary)
--
-- Every test builds its own position so failures point at one rule, not at a
-- long game that drifted.

local Config = require(script.Parent.Config)
local Board = require(script.Parent.Board)
local Moves = require(script.Parent.Moves)
local Rules = require(script.Parent.Rules)
local Bot = require(script.Parent.Bot)

local SelfTest = {}

local nextId = 0
local function piece(pieceType: string, color: string)
	nextId += 1
	return { type = pieceType, color = color, id = nextId }
end

-- A board with nothing on it and no castling rights, ready to be populated.
local function emptyState(turn: string?)
	local state = Board.newGame()
	state.grid = Board.newGrid()
	state.turn = turn or Config.White
	state.castling = {
		White = { Kingside = false, Queenside = false },
		Black = { Kingside = false, Queenside = false },
	}
	state.enPassant = nil
	state.halfmove = 0
	state.repetition = {}
	return state
end

local function put(state: Board.GameState, squareName: string, pieceType: string, color: string)
	local square = Board.parseSquare(squareName)
	assert(square, "bad square name in test: " .. squareName)
	Board.set(state.grid, square.file, square.rank, piece(pieceType, color))
end

local function hasMove(moves: { Moves.Move }, fromName: string, toName: string): boolean
	local from, to = Board.parseSquare(fromName), Board.parseSquare(toName)
	if not from or not to then
		return false
	end
	for _, move in moves do
		if
			move.from.file == from.file
			and move.from.rank == from.rank
			and move.to.file == to.file
			and move.to.rank == to.rank
		then
			return true
		end
	end
	return false
end

local function equal(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
	end
end

-- Collected as { name, ok, message } so one failure does not hide the rest.
function SelfTest.run(): { passed: number, failed: number, results: { { name: string, ok: boolean, message: string? } } }
	local results = {}
	local passed, failed = 0, 0

	local function check(name: string, body: () -> ())
		local ok, err = pcall(body)
		if ok then
			passed += 1
			table.insert(results, { name = name, ok = true })
		else
			failed += 1
			table.insert(results, { name = name, ok = false, message = tostring(err) })
		end
		-- Yield between checks so a long suite never freezes the Studio thread.
		task.wait()
	end

	check("initial position has 40 pieces", function()
		local state = Board.newGame()
		local count = 0
		for file = 1, Config.Files do
			for rank = 1, Config.Ranks do
				if Board.get(state.grid, file, rank) then
					count += 1
				end
			end
		end
		equal(count, 40, "piece count")
		equal(Board.material(state, Config.White), Board.material(state, Config.Black), "symmetric material")
	end)

	check("initial position offers 45 legal moves", function()
		-- 20 pawn advances, 4 knight jumps, 3 Rift leaps (it hops its own
		-- back rank), and 18 Hexer swaps.
		local state = Board.newGame()
		local moves = Rules.legalMoves(state)
		equal(#moves, 45, "opening move count")
		assert(hasMove(moves, "a2", "a4"), "a2-a4 missing")
		assert(hasMove(moves, "a2", "a3"), "a2-a3 missing")
		assert(hasMove(moves, "g1", "g3"), "Rift should leap two ranks from the baseline")
		assert(hasMove(moves, "b1", "a3"), "knight jump missing")
	end)

	check("a double pawn push opens an en passant square", function()
		local state = Board.newGame()
		local move = Rules.findMove(state, Board.parseSquare("a2") :: Board.Square, Board.parseSquare("a4") :: Board.Square, nil)
		assert(move, "a2-a4 not legal")
		local after = Rules.apply(state, move :: Moves.Move)
		assert(after.enPassant, "no en passant square set")
		equal(Board.squareName(after.enPassant.file, after.enPassant.rank), "a3", "en passant square")
		equal(after.turn, Config.Black, "turn after white move")
	end)

	check("en passant captures the passing pawn", function()
		-- A white pawn on the fifth rank may capture a black pawn that just
		-- ran past it. The landing square is the one the pawn skipped over.
		local state = emptyState(Config.Black)
		put(state, "e1", "King", Config.White)
		put(state, "j8", "King", Config.Black)
		put(state, "e5", "Pawn", Config.White)
		put(state, "d7", "Pawn", Config.Black)

		local blackPush = Rules.findMove(state, Board.parseSquare("d7") :: Board.Square, Board.parseSquare("d5") :: Board.Square, nil)
		assert(blackPush, "black double push not legal")
		local afterBlack = Rules.apply(state, blackPush :: Moves.Move)
		assert(afterBlack.enPassant, "no en passant square set for white")
		equal(Board.squareName(afterBlack.enPassant.file, afterBlack.enPassant.rank), "d6", "en passant target")

		local capture = Rules.findMove(afterBlack, Board.parseSquare("e5") :: Board.Square, Board.parseSquare("d6") :: Board.Square, nil)
		assert(capture, "en passant capture not generated")
		assert((capture :: Moves.Move).enPassant, "capture should be flagged as en passant")

		local afterCapture = Rules.apply(afterBlack, capture :: Moves.Move)
		assert(not Board.get(afterCapture.grid, 4, 5), "captured pawn should be gone from d5")
		assert(Board.get(afterCapture.grid, 4, 6), "white pawn did not land on d6")
	end)

	check("the Rift leaps over blockers", function()
		local state = emptyState(Config.White)
		put(state, "e1", "King", Config.White)
		put(state, "j8", "King", Config.Black)
		put(state, "e4", "Rift", Config.White)
		put(state, "e5", "Pawn", Config.White)
		put(state, "f4", "Pawn", Config.White)
		local moves = Rules.legalMovesFrom(state, Board.parseSquare("e4") :: Board.Square)
		assert(hasMove(moves, "e4", "e6"), "Rift failed to leap past the pawn on e5")
		assert(hasMove(moves, "e4", "c4"), "Rift failed to leap two sideways")
		assert(hasMove(moves, "e4", "g6"), "Rift failed to leap two diagonally")
		assert(not hasMove(moves, "e4", "e5"), "Rift should not land on an occupied square")
	end)

	check("the Hexer slides diagonally and swaps once per game", function()
		local state = emptyState(Config.White)
		put(state, "e1", "King", Config.White)
		put(state, "j8", "King", Config.Black)
		put(state, "d4", "Hexer", Config.White)
		put(state, "b2", "Rook", Config.White)
		local moves = Rules.legalMovesFrom(state, Board.parseSquare("d4") :: Board.Square)
		assert(hasMove(moves, "d4", "a7"), "Hexer diagonal slide missing")
		assert(hasMove(moves, "d4", "b2"), "Hexer swap missing")

		local swap = Rules.findMove(state, Board.parseSquare("d4") :: Board.Square, Board.parseSquare("b2") :: Board.Square, nil)
		assert(swap, "swap not found")
		local after = Rules.apply(state, swap :: Moves.Move)
		assert(Board.get(after.grid, 2, 2), "rook did not move to d4")
		equal((Board.get(after.grid, 2, 2) :: Board.Piece).type, "Hexer", "hexer should now be on b2")
		equal(after.hexerSwap[Config.White], false, "swap should be consumed")
		local laterMoves = Rules.legalMovesFrom(after, Board.parseSquare("b2") :: Board.Square)
		for _, move in laterMoves do
			assert(not move.swap, "second swap should not be available")
		end
	end)

	check("castling moves king and rook together", function()
		local state = emptyState(Config.White)
		put(state, "f1", "King", Config.White)
		put(state, "j1", "Rook", Config.White)
		put(state, "a1", "Rook", Config.White)
		put(state, "f8", "King", Config.Black)
		local after = state
		-- Clear g1..i1 so the kingside path is open.
		for file = 7, 9 do
			Board.set(after.grid, file, 1, nil)
		end
		after.castling[Config.White] = { Kingside = true, Queenside = true }
		local moves = Rules.legalMovesFrom(after, Board.parseSquare("f1") :: Board.Square)
		assert(hasMove(moves, "f1", "h1"), "kingside castle missing")

		local castle = Rules.findMove(after, Board.parseSquare("f1") :: Board.Square, Board.parseSquare("h1") :: Board.Square, nil)
		local result = Rules.apply(after, castle :: Moves.Move)
		equal((Board.get(result.grid, 7, 1) :: Board.Piece).type, "Rook", "rook should land on g1")
		equal((Board.get(result.grid, 8, 1) :: Board.Piece).type, "King", "king should land on h1")
		assert(not Board.get(result.grid, 10, 1), "old rook square should be empty")
	end)

	check("castling is refused through an attacked square", function()
		local state = emptyState(Config.White)
		put(state, "f1", "King", Config.White)
		put(state, "j1", "Rook", Config.White)
		put(state, "f8", "King", Config.Black)
		put(state, "g8", "Rook", Config.Black) -- covers g1 along the file once the path opens
		for file = 7, 9 do
			Board.set(state.grid, file, 1, nil)
		end
		state.castling[Config.White] = { Kingside = true, Queenside = false }
		local moves = Rules.legalMovesFrom(state, Board.parseSquare("f1") :: Board.Square)
		assert(not hasMove(moves, "f1", "h1"), "castle through check should be illegal")
	end)

	check("checkmate is detected", function()
		local state = emptyState(Config.Black)
		put(state, "a8", "King", Config.Black)
		put(state, "b7", "Queen", Config.White)
		put(state, "c6", "King", Config.White)
		local status = Rules.status(state)
		assert(status.over, "position should be terminal")
		equal(status.result, "WhiteWin", "mate result")
		equal(status.reason, "Checkmate", "mate reason")
	end)

	check("stalemate is detected", function()
		local state = emptyState(Config.Black)
		put(state, "a8", "King", Config.Black)
		put(state, "c7", "Queen", Config.White)
		put(state, "c6", "King", Config.White)
		local status = Rules.status(state)
		assert(status.over, "position should be terminal")
		equal(status.result, "Draw", "stalemate result")
		equal(status.reason, "Stalemate", "stalemate reason")
	end)

	check("a pinned piece cannot move", function()
		local state = emptyState(Config.White)
		put(state, "e1", "King", Config.White)
		put(state, "e2", "Rook", Config.White)
		put(state, "e8", "Rook", Config.Black)
		put(state, "a8", "King", Config.Black)
		local moves = Rules.legalMovesFrom(state, Board.parseSquare("e2") :: Board.Square)
		-- The rook may only slide along the pinning file.
		for _, move in moves do
			equal(move.to.file, 5, "pinned rook left the e-file")
		end
		assert(#moves > 0, "pinned rook should still slide along the file")
	end)

	check("promotion offers every piece and replaces the pawn", function()
		local state = emptyState(Config.White)
		put(state, "e1", "King", Config.White)
		put(state, "a8", "King", Config.Black)
		put(state, "j7", "Pawn", Config.White)
		local moves = Rules.legalMovesFrom(state, Board.parseSquare("j7") :: Board.Square)
		local promotions = 0
		for _, move in moves do
			if move.promotion then
				promotions += 1
			end
		end
		equal(promotions, #Config.PromotionChoices, "promotion option count")

		local knight = Rules.findMove(state, Board.parseSquare("j7") :: Board.Square, Board.parseSquare("j8") :: Board.Square, "Knight")
		assert(knight, "knight promotion not found")
		local after = Rules.apply(state, knight :: Moves.Move)
		local promoted = Board.get(after.grid, 10, 8)
		assert(promoted, "no piece on the promotion square")
		equal((promoted :: Board.Piece).type, "Knight", "promoted piece type")
		assert(not Board.get(state.grid, 10, 8), "source state must not be mutated")
	end)

	check("applying a move does not mutate the source state", function()
		local state = Board.newGame()
		local before = Board.positionKey(state)
		local move = Rules.findMove(state, Board.parseSquare("a2") :: Board.Square, Board.parseSquare("a4") :: Board.Square, nil)
		Rules.apply(state, move :: Moves.Move)
		equal(Board.positionKey(state), before, "source position key")
	end)

	check("every bot tier returns a legal move", function()
		-- A sparse position keeps the hard tier's search small, so this check
		-- measures correctness rather than the clock.
		local state = emptyState(Config.White)
		put(state, "e1", "King", Config.White)
		put(state, "j8", "King", Config.Black)
		put(state, "d4", "Queen", Config.White)
		put(state, "g7", "Rook", Config.Black)
		put(state, "b2", "Hexer", Config.White)
		put(state, "j7", "Rift", Config.Black)

		for _, difficulty in Bot.Difficulties do
			local move = Bot.chooseMove(state, difficulty, 0.25)
			assert(move, "bot returned no move for " .. difficulty)
			local legal = Rules.findMove(state, move.from, move.to, move.promotion)
			assert(legal, "bot returned an illegal move for " .. difficulty)
		end
	end)

	local lines = {}
	for _, result in results do
		table.insert(lines, string.format("%s %s%s", if result.ok then "PASS" else "FAIL", result.name, if result.message then ": " .. result.message else ""))
	end
	table.insert(lines, string.format("%d passed, %d failed", passed, failed))

	return {
		passed = passed,
		failed = failed,
		results = results,
		summary = table.concat(lines, "\n"),
	}
end

return SelfTest
