--!strict
-- One table, one match.
--
-- The server owns the only authoritative position. Clients send the squares
-- they want to move and this module decides whether that is legal, whose turn
-- it is, and whether the request came from a seated player at all. Nothing a
-- client sends is trusted beyond "these are the squares I clicked".
--
-- The match lives for the lifetime of the server process; there is no
-- persistence. Rematches reuse the same object by resetting it.

local Chess = require(game.ReplicatedStorage.Shared.Chess)

local Board = Chess.Board
local Bot = Chess.Bot
local Config = Chess.Config
local Rules = Chess.Rules
local Serialize = Chess.Serialize

local Match = {}
Match.__index = Match

-- How long the bot is allowed to think per move, in seconds. Kept under the
-- engine's own budget so a server tick is never held for long.
local BOT_THINK_BUDGET = 0.5

-- Grace period before a disconnected player forfeits.
Match.DISCONNECT_FORFEIT_SECONDS = 60

export type Phase = "Idle" | "Waiting" | "Active" | "Finished"

export type Move = Rules.Move

function Match.new()
	local self = setmetatable({}, Match)
	self.phase = "Idle"
	self.mode = nil
	self.difficulty = nil
	self.state = Board.newGame()
	self.white = nil
	self.black = nil
	self.botColor = nil
	self.lastMove = nil
	self.result = nil
	self.reason = nil
	self.moveCount = 0
	return self
end

-- Color this user is playing, or nil if they are a spectator.
function Match:seatOf(userId: number): string?
	if self.white == userId then
		return Config.White
	end
	if self.black == userId then
		return Config.Black
	end
	return nil
end

function Match:isSeated(userId: number): boolean
	return self:seatOf(userId) ~= nil
end

function Match:isBotTurn(): boolean
	return self.phase == "Active" and self.botColor ~= nil and self.state.turn == self.botColor
end

-- Resets the board and clears both seats.
function Match:reset()
	self.phase = "Idle"
	self.mode = nil
	self.difficulty = nil
	self.state = Board.newGame()
	self.white = nil
	self.black = nil
	self.botColor = nil
	self.lastMove = nil
	self.result = nil
	self.reason = nil
	self.moveCount = 0
end

function Match:startBotMatch(userId: number, difficulty: string)
	self:reset()
	self.mode = "Bot"
	self.difficulty = difficulty
	self.white = userId
	self.botColor = Config.Black
	self.phase = "Active"
end

-- Returns "Waiting" when the caller is first in the queue, "Started" when this
-- call completed the pairing, "Seated" when they already hold a seat, or
-- "Full" when both seats are taken.
function Match:requestPlayer(userId: number): string
	if self.phase == "Waiting" then
		if self.white == userId then
			return "Waiting"
		end
		self.black = userId
		self.phase = "Active"
		return "Started"
	end

	if self.phase == "Active" then
		if self:isSeated(userId) then
			return "Seated"
		end
		return "Full"
	end

	-- Idle or Finished: this player opens a new table.
	self:reset()
	self.mode = "Player"
	self.white = userId
	self.phase = "Waiting"
	return "Waiting"
end

local function recordStatus(self, status)
	if status.over then
		self.phase = "Finished"
		self.result = status.result
		self.reason = status.reason
	end
end

-- Applies an already-legalized move and advances match bookkeeping.
local function commitMove(self, move: Move)
	self.state = Rules.apply(self.state, move)
	self.lastMove = {
		fromFile = move.from.file,
		fromRank = move.from.rank,
		toFile = move.to.file,
		toRank = move.to.rank,
		notation = Rules.toNotation(move),
	}
	self.moveCount += 1
	recordStatus(self, Rules.status(self.state))
end

-- Handles a move request from a player. Returns ok, and a short reason when
-- the request was refused.
function Match:submitMove(userId: number, from: Board.Square, to: Board.Square, promotion: string?): (boolean, string?)
	if self.phase ~= "Active" then
		return false, "No active game"
	end

	local seat = self:seatOf(userId)
	if not seat then
		return false, "Spectators cannot move"
	end
	if seat ~= self.state.turn then
		return false, "Not your turn"
	end

	local move = Rules.findMove(self.state, from, to, promotion)
	if not move then
		return false, "Illegal move"
	end

	commitMove(self, move)
	return true
end

-- Plays the bot's reply. Called from a delayed task so a slow search never
-- blocks the remote handler that triggered it.
function Match:playBotMove()
	if not self:isBotTurn() then
		return nil
	end

	local move = Bot.chooseMove(self.state, self.difficulty or "Medium", BOT_THINK_BUDGET)
	if not move then
		-- No legal reply means the position is already terminal; the status was
		-- recorded when the player's move was committed.
		return nil
	end

	commitMove(self, move)
	return move
end

function Match:resign(userId: number): boolean
	local seat = self:seatOf(userId)
	if not seat or self.phase ~= "Active" then
		return false
	end
	self.phase = "Finished"
	self.result = if seat == Config.White then "BlackWin" else "WhiteWin"
	self.reason = "Resignation"
	return true
end

-- A player vanished mid-game. The opponent wins once the grace period passes,
-- but only if the same match is still running and the seat was not retaken by
-- a reconnecting player.
function Match:scheduleDisconnectForfeit(userId: number)
	local seat = self:seatOf(userId)
	if not seat or self.phase ~= "Active" then
		return
	end

	task.delay(Match.DISCONNECT_FORFEIT_SECONDS, function()
		if self.phase ~= "Active" then
			return
		end
		if self:seatOf(userId) ~= seat then
			return
		end
		self.phase = "Finished"
		self.result = if seat == Config.White then "BlackWin" else "WhiteWin"
		self.reason = "Disconnect"
	end)
end

function Match:snapshot()
	local meta = {
		phase = self.phase,
		mode = self.mode,
		difficulty = self.difficulty,
		white = self.white,
		black = self.black,
		lastMove = self.lastMove,
		result = self.result,
		reason = self.reason,
	}
	return Serialize.snapshot(self.state, meta)
end

return Match
