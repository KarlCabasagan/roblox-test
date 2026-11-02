--!strict
-- Server entry point (ServerScriptService.Server).
--
-- Wires the match manager to remote events, builds the physical table at boot,
-- and is the only place that decides when a snapshot is broadcast. Every path
-- that changes the position ends in `broadcast`, so the 3D table and every
-- client panel are always looking at the same move.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chess = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Chess"))
local Table = require(script.Table)
local Match = require(script.Match)

local Config = Chess.Config
local Bot = Chess.Bot

local match = Match.new()

local REMOTES_FOLDER = "ChessRemotes"

local function ensureRemotes(): { [string]: RemoteEvent }
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER
		folder.Parent = ReplicatedStorage
	end

	local remotes = {}
	for _, name in { "StateSync", "StartMatch", "SubmitMove", "Resign", "Notice" } do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
	end
	return remotes
end

local remotes = ensureRemotes()

local function broadcast()
	local snapshot = match:snapshot()
	remotes.StateSync:FireAllClients(snapshot)
	Table.applySnapshot(snapshot)
end

-- The bot replies on the next tick rather than inside the remote handler, so a
-- player's move is never held hostage by a search.
local function maybePlayBotTurn()
	if not match:isBotTurn() then
		return
	end
	task.delay(0.35, function()
		if match:playBotMove() then
			broadcast()
		end
	end)
end

local function isSquare(value: any): boolean
	return type(value) == "number" and value == value // 1 and value >= 1
end

remotes.StartMatch.OnServerEvent:Connect(function(player: Player, mode: any, difficulty: any)
	if mode ~= "Bot" and mode ~= "Player" then
		return
	end

	if mode == "Bot" then
		local chosen = if type(difficulty) == "string" and table.find(Bot.Difficulties, difficulty) then difficulty else "Medium"
		match:startBotMatch(player.UserId, chosen)
	else
		local outcome = match:requestPlayer(player.UserId)
		if outcome == "Full" then
			remotes.Notice:FireClient(player, "A game is already in progress")
			return
		end
		if outcome == "Seated" then
			remotes.Notice:FireClient(player, "Finish the current game before starting another")
			return
		end
	end

	broadcast()
	maybePlayBotTurn()
end)

remotes.SubmitMove.OnServerEvent:Connect(function(
	player: Player,
	fromFile: any,
	fromRank: any,
	toFile: any,
	toRank: any,
	promotion: any
)
	if not (isSquare(fromFile) and isSquare(fromRank) and isSquare(toFile) and isSquare(toRank)) then
		return
	end
	if fromFile > Config.Files or toFile > Config.Files or fromRank > Config.Ranks or toRank > Config.Ranks then
		return
	end

	local chosenPromotion = nil
	if type(promotion) == "string" and table.find(Config.PromotionChoices, promotion) then
		chosenPromotion = promotion
	end

	local ok, reason = match:submitMove(
		player.UserId,
		{ file = fromFile, rank = fromRank },
		{ file = toFile, rank = toRank },
		chosenPromotion
	)

	if not ok then
		if reason then
			remotes.Notice:FireClient(player, reason)
		end
		return
	end

	broadcast()
	maybePlayBotTurn()
end)

remotes.Resign.OnServerEvent:Connect(function(player: Player)
	if match:resign(player.UserId) then
		broadcast()
	end
end)

Players.PlayerAdded:Connect(function(player: Player)
	remotes.StateSync:FireClient(player, match:snapshot())
end)

Players.PlayerRemoving:Connect(function(player: Player)
	if match.phase == "Finished" then
		return
	end
	if match.phase == "Waiting" and match.white == player.UserId then
		-- Nobody was paired yet, so the table simply goes idle again.
		match:reset()
		broadcast()
		return
	end
	match:scheduleDisconnectForfeit(player.UserId)
end)

-- Table is rebuilt on every server start; nothing about it is saved in the
-- place, so a fresh publish always gets the current geometry.
Table.build()
Table.placeSpawn()
broadcast()

print(string.format("[chess] table ready at origin, %d x %d squares", Config.Files, Config.Ranks))
