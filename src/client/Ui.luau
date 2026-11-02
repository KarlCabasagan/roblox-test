--!strict
-- The 2D play surface.
--
-- This is where games are actually played. The world table is a mirror for
-- spectators; everything clickable lives here, which means input is plain GUI
-- picking and works the same on desktop, touch, and gamepad.
--
-- The panel keeps a local copy of the position only to paint legal-move hints.
-- Every click still travels to the server, which is the sole authority on
-- whether the move is allowed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Chess = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Chess"))
local Board = Chess.Board
local Config = Chess.Config
local Rules = Chess.Rules
local Serialize = Chess.Serialize

local Ui = {}
Ui.__index = Ui

local LIGHT_SQUARE = Color3.fromRGB(222, 214, 196)
local DARK_SQUARE = Color3.fromRGB(96, 104, 120)
local SELECTED_SQUARE = Color3.fromRGB(126, 168, 96)
local LAST_MOVE_SQUARE = Color3.fromRGB(198, 174, 88)
local WHITE_PIECE = Color3.fromRGB(252, 250, 242)
local BLACK_PIECE = Color3.fromRGB(28, 28, 34)
local TARGET_DOT = Color3.fromRGB(40, 44, 52)

-- A letter per piece. The two custom pieces get their own glyphs so a board
-- full of standard chess still reads at a glance.
local GLYPH = {
	Pawn = "P",
	Knight = "N",
	Bishop = "B",
	Rook = "R",
	Queen = "Q",
	King = "K",
	Hexer = "H",
	Rift = "X",
}

local function corner(parent: Instance, radius: number)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = color
	uiStroke.Thickness = thickness
	uiStroke.Parent = parent
end

local function displayName(userId: number?): string
	if not userId then
		return "Open seat"
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	return "Player " .. tostring(userId)
end

local function buildBoard(parent: Frame): { [string]: TextButton }
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(1 / Config.Files, 1 / Config.Ranks)
	grid.CellPadding = UDim2.fromOffset(0, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = parent

	local squares = {}
	local order = 0

	-- Built rank 8 down to rank 1 so raw layout order matches a board seen
	-- from White's side; flipping is done by re-assigning layout order.
	for rank = Config.Ranks, 1, -1 do
		for file = 1, Config.Files do
			order += 1
			local button = Instance.new("TextButton")
			button.Name = string.format("Sq_%d_%d", file, rank)
			button.AutoButtonColor = false
			button.BorderSizePixel = 0
			button.Text = ""
			button.TextScaled = true
			button.BackgroundColor3 = if (file + rank) % 2 == 0 then LIGHT_SQUARE else DARK_SQUARE
			button.LayoutOrder = order
			button.Parent = parent

			local textConstraint = Instance.new("UITextSizeConstraint")
			textConstraint.MaxTextSize = 34
			textConstraint.Parent = button

			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(0.5, 0.5)
			dot.Size = UDim2.fromScale(0.28, 0.28)
			dot.BackgroundColor3 = TARGET_DOT
			dot.BackgroundTransparency = 0.35
			dot.BorderSizePixel = 0
			dot.Visible = false
			dot.ZIndex = 2
			corner(dot, 12)
			dot.Parent = button

			squares[tostring(file) .. ":" .. tostring(rank)] = button
		end
	end

	return squares
end

local function buildHud(parent: Frame): (TextLabel, TextLabel, TextLabel, TextButton)
	local bar = Instance.new("Frame")
	bar.Name = "Hud"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0.015)
	bar.Size = UDim2.fromScale(0.66, 0.11)
	bar.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Parent = parent
	corner(bar, 10)

	local sideLabel = Instance.new("TextLabel")
	sideLabel.Name = "Sides"
	sideLabel.BackgroundTransparency = 1
	sideLabel.Position = UDim2.fromScale(0.02, 0.06)
	sideLabel.Size = UDim2.fromScale(0.6, 0.4)
	sideLabel.Font = Enum.Font.GothamMedium
	sideLabel.TextSize = 16
	sideLabel.TextXAlignment = Enum.TextXAlignment.Left
	sideLabel.TextColor3 = Color3.fromRGB(224, 226, 232)
	sideLabel.Text = ""
	sideLabel.Parent = bar

	local turnLabel = Instance.new("TextLabel")
	turnLabel.Name = "Turn"
	turnLabel.BackgroundTransparency = 1
	turnLabel.Position = UDim2.fromScale(0.02, 0.46)
	turnLabel.Size = UDim2.fromScale(0.6, 0.45)
	turnLabel.Font = Enum.Font.GothamBold
	turnLabel.TextSize = 18
	turnLabel.TextXAlignment = Enum.TextXAlignment.Left
	turnLabel.TextColor3 = Color3.fromRGB(246, 232, 176)
	turnLabel.Text = ""
	turnLabel.Parent = bar

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.AnchorPoint = Vector2.new(1, 0)
	statusLabel.Position = UDim2.fromScale(0.98, 0.06)
	statusLabel.Size = UDim2.fromScale(0.36, 0.86)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 14
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.TextWrapped = true
	statusLabel.TextColor3 = Color3.fromRGB(196, 200, 210)
	statusLabel.Text = ""
	statusLabel.Parent = bar

	local resign = Instance.new("TextButton")
	resign.Name = "Resign"
	resign.AnchorPoint = Vector2.new(1, 1)
	resign.Position = UDim2.fromScale(0.98, 0.98)
	resign.Size = UDim2.fromOffset(96, 30)
	resign.BackgroundColor3 = Color3.fromRGB(78, 34, 38)
	resign.BorderSizePixel = 0
	resign.Font = Enum.Font.GothamBold
	resign.TextSize = 13
	resign.TextColor3 = Color3.fromRGB(240, 214, 214)
	resign.Text = "Resign"
	resign.Visible = false
	resign.Parent = parent
	corner(resign, 8)

	return sideLabel, turnLabel, statusLabel, resign
end

local function buildLobby(parent: Frame)
	local overlay = Instance.new("Frame")
	overlay.Name = "Lobby"
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromOffset(380, 320)
	overlay.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	overlay.BackgroundTransparency = 0.06
	overlay.BorderSizePixel = 0
	overlay.Parent = parent
	corner(overlay, 14)
	stroke(overlay, Color3.fromRGB(86, 74, 52), 2)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0, 0.06)
	title.Size = UDim2.fromScale(1, 0.16)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 26
	title.TextColor3 = Color3.fromRGB(246, 232, 176)
	title.Text = "CHESS: STEROIDS"
	title.Parent = overlay

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0.06, 0.22)
	subtitle.Size = UDim2.fromScale(0.88, 0.12)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 13
	subtitle.TextWrapped = true
	subtitle.TextColor3 = Color3.fromRGB(178, 182, 192)
	subtitle.Text = "10x8 board. Standard army plus the Hexer and the Rift."
	subtitle.Parent = overlay

	local function makeButton(name: string, text: string, position: UDim2, size: UDim2, accent: Color3): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Position = position
		button.Size = size
		button.BackgroundColor3 = accent
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.TextColor3 = Color3.fromRGB(240, 240, 244)
		button.Text = text
		button.Parent = overlay
		corner(button, 8)
		return button
	end

	local botButton = makeButton("PlayBot", "Play vs Bot", UDim2.fromScale(0.08, 0.38), UDim2.fromScale(0.84, 0.13), Color3.fromRGB(52, 84, 66))
	local pvpButton = makeButton("PlayPvp", "Play vs Player", UDim2.fromScale(0.08, 0.54), UDim2.fromScale(0.84, 0.13), Color3.fromRGB(58, 66, 96))

	local difficultyButton = makeButton("Difficulty", "Difficulty: Medium", UDim2.fromScale(0.08, 0.70), UDim2.fromScale(0.84, 0.11), Color3.fromRGB(44, 46, 56))
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromScale(0.06, 0.84)
	hint.Size = UDim2.fromScale(0.88, 0.14)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 12
	hint.TextWrapped = true
	hint.TextColor3 = Color3.fromRGB(150, 154, 164)
	hint.Text = "Tap a piece, then a highlighted square."
	hint.Parent = overlay

	return {
		overlay = overlay,
		subtitle = subtitle,
		botButton = botButton,
		pvpButton = pvpButton,
		difficultyButton = difficultyButton,
	}
end

local function buildPromotion(parent: Frame)
	local overlay = Instance.new("Frame")
	overlay.Name = "Promotion"
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromOffset(340, 120)
	overlay.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = parent
	corner(overlay, 12)
	stroke(overlay, Color3.fromRGB(120, 104, 64), 2)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, 0.06)
	label.Size = UDim2.fromScale(1, 0.24)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(236, 226, 196)
	label.Text = "Promote to"
	label.Parent = overlay

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.03, 0.38)
	row.Size = UDim2.fromScale(0.94, 0.5)
	row.Parent = overlay

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(1 / #Config.PromotionChoices - 0.008, 1)
	grid.CellPadding = UDim2.fromOffset(4, 0)
	grid.Parent = row

	local buttons = {}
	for index, pieceType in Config.PromotionChoices do
		local button = Instance.new("TextButton")
		button.Name = pieceType
		button.LayoutOrder = index
		button.BackgroundColor3 = Color3.fromRGB(56, 60, 72)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextSize = 18
		button.TextColor3 = Color3.fromRGB(238, 238, 242)
		button.Text = GLYPH[pieceType] or "?"
		button.Parent = row
		corner(button, 6)
		buttons[pieceType] = button
	end

	return { overlay = overlay, buttons = buttons }
end

function Ui.new(player: Player)
	local self = setmetatable({}, Ui)
	self.player = player
	self.selected = nil
	self.legalTargets = {}
	self.snapshot = nil
	self.myColor = nil
	self.pendingPromotion = nil
	self.difficulty = "Medium"
	self.handlers = {}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ChessUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player:WaitForChild("PlayerGui")
	self.screenGui = screenGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = screenGui
	self.root = root

	local boardHolder = Instance.new("Frame")
	boardHolder.Name = "BoardHolder"
	boardHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	boardHolder.Position = UDim2.fromScale(0.5, 0.56)
	-- Width drives the size; the aspect constraint then sets height from it.
	-- Without a dominant axis the constraint sizes off the full screen height
	-- and the board overflows a wide viewport. 0.46 clears the HUD above and
	-- the resign button below on a 16:9 screen.
	boardHolder.Size = UDim2.fromScale(0.46, 1)
	boardHolder.BackgroundColor3 = Color3.fromRGB(30, 26, 22)
	boardHolder.BorderSizePixel = 0
	boardHolder.Parent = root
	corner(boardHolder, 8)
	stroke(boardHolder, Color3.fromRGB(74, 62, 48), 3)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = Config.Files / Config.Ranks
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = boardHolder

	self.squareButtons = buildBoard(boardHolder)

	local sideLabel, turnLabel, statusLabel, resignButton = buildHud(root)
	self.sideLabel = sideLabel
	self.turnLabel = turnLabel
	self.statusLabel = statusLabel
	self.resignButton = resignButton

	local lobby = buildLobby(root)
	self.lobby = lobby

	local promotion = buildPromotion(root)
	self.promotion = promotion

	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.fromScale(0.5, 0.98)
	toast.Size = UDim2.fromOffset(420, 34)
	toast.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	toast.BackgroundTransparency = 0.1
	toast.BorderSizePixel = 0
	toast.Font = Enum.Font.GothamMedium
	toast.TextSize = 15
	toast.TextColor3 = Color3.fromRGB(246, 232, 176)
	toast.Text = ""
	toast.Visible = false
	toast.Parent = root
	corner(toast, 8)
	self.toast = toast

	-- Interaction wiring -----------------------------------------------------

	for key, button in self.squareButtons do
		button.Activated:Connect(function()
			self:_onSquareActivated(key)
		end)
	end

	lobby.botButton.Activated:Connect(function()
		self:_fire("onStart", "Bot", self.difficulty)
	end)

	lobby.pvpButton.Activated:Connect(function()
		self:_fire("onStart", "Player", nil)
	end)

	lobby.difficultyButton.Activated:Connect(function()
		local order = { "Easy", "Medium", "Hard" }
		local current = table.find(order, self.difficulty) or 2
		self.difficulty = order[(current % #order) + 1]
		lobby.difficultyButton.Text = "Difficulty: " .. self.difficulty
	end)

	resignButton.Activated:Connect(function()
		self:_fire("onResign")
	end)

	for pieceType, button in promotion.buttons do
		button.Activated:Connect(function()
			self:_completePromotion(pieceType)
		end)
	end

	return self
end

function Ui:setHandlers(handlers: { [string]: (...any) -> () })
	self.handlers = handlers
end

function Ui:_fire(name: string, ...)
	local handler = self.handlers[name]
	if handler then
		handler(...)
	end
end

function Ui:notice(message: string)
	local toast = self.toast
	toast.Text = message
	toast.Visible = true
	task.delay(2.5, function()
		if toast.Text == message then
			toast.Visible = false
		end
	end)
end

-- Rebuilds the clickable state for the current position.
local function clientState(snapshot): any
	local state = {
		grid = Serialize.gridFromSnapshot(snapshot),
		turn = snapshot.turn,
		castling = snapshot.castling,
		enPassant = snapshot.enPassant,
		hexerSwap = snapshot.hexerSwap or { White = false, Black = false },
		halfmove = snapshot.halfmove,
		fullmove = snapshot.fullmove,
		repetition = {},
	}
	return state
end

local function squareKey(file: number, rank: number): string
	return tostring(file) .. ":" .. tostring(rank)
end

function Ui:_onSquareActivated(key: string)
	local snapshot = self.snapshot
	if not snapshot or snapshot.phase ~= "Active" then
		return
	end
	if not self.myColor or snapshot.turn ~= self.myColor then
		return
	end

	local fileText, rankText = string.match(key, "^(%d+):(%d+)$")
	local file, rank = tonumber(fileText), tonumber(rankText)
	if not file or not rank then
		return
	end

	local state = clientState(snapshot)
	local piece = state.grid[file][rank]

	-- Second click: a highlighted destination.
	local target = self.legalTargets[key]
	if target then
		self.selected = nil
		self.legalTargets = {}
		if target.promotion then
			self.pendingPromotion = target
			self.promotion.overlay.Visible = true
			return
		end
		self:_fire("onMove", target.from.file, target.from.rank, target.to.file, target.to.rank, nil)
		self:_paint()
		return
	end

	-- First click: select a piece of the local player's colour.
	if piece and piece.color == self.myColor then
		self.selected = { file = file, rank = rank }
		self.legalTargets = {}
		for _, move in Rules.legalMovesFrom(state, { file = file, rank = rank }) do
			local key2 = squareKey(move.to.file, move.to.rank)
			-- Promotion variants share a square; remember that one is pending.
			if not self.legalTargets[key2] or move.promotion then
				self.legalTargets[key2] = move
			end
		end
		self:_paint()
		return
	end

	self.selected = nil
	self.legalTargets = {}
	self:_paint()
end

function Ui:_completePromotion(pieceType: string)
	local pending = self.pendingPromotion
	self.pendingPromotion = nil
	self.promotion.overlay.Visible = false
	if not pending then
		return
	end
	self:_fire("onMove", pending.from.file, pending.from.rank, pending.to.file, pending.to.rank, pieceType)
	self:_paint()
end

-- Repaints every square. Cheap enough at 80 buttons to run on each change, and
-- it removes every stale highlight bug at once.
function Ui:_paint()
	local snapshot = self.snapshot
	if not snapshot then
		return
	end

	local state = clientState(snapshot)
	local flipped = self.myColor == Config.Black
	local lastMove = snapshot.lastMove

	for rank = 1, Config.Ranks do
		for file = 1, Config.Files do
			local button = self.squareButtons[squareKey(file, rank)]
			if button then
				local isLight = (file + rank) % 2 == 0
				button.BackgroundColor3 = if isLight then LIGHT_SQUARE else DARK_SQUARE

				local piece = state.grid[file][rank]
				button.Text = if piece then (GLYPH[piece.type] or "?") else ""
				if piece then
					button.TextColor3 = if piece.color == Config.White then WHITE_PIECE else BLACK_PIECE
					button.TextStrokeTransparency = 0
					button.TextStrokeColor3 = if piece.color == Config.White then Color3.fromRGB(20, 20, 24) else Color3.fromRGB(238, 238, 242)
				else
					button.TextStrokeTransparency = 1
				end

				if lastMove and
					((file == lastMove.fromFile and rank == lastMove.fromRank)
						or (file == lastMove.toFile and rank == lastMove.toRank))
				then
					button.BackgroundColor3 = LAST_MOVE_SQUARE
				end

				if self.selected and self.selected.file == file and self.selected.rank == rank then
					button.BackgroundColor3 = SELECTED_SQUARE
				end

				local dot = button:FindFirstChild("Dot")
				if dot then
					local isTarget = self.legalTargets[squareKey(file, rank)] ~= nil
					dot.Visible = isTarget
					if isTarget then
						local capturing = piece ~= nil
						dot.Size = if capturing then UDim2.fromScale(0.72, 0.72) else UDim2.fromScale(0.28, 0.28)
						dot.BackgroundTransparency = if capturing then 0.55 else 0.35
					end
				end

				-- Flip reading order so Black sees their own back rank at the bottom.
				button.LayoutOrder = if flipped then (rank - 1) * Config.Files + (Config.Files + 1 - file)
					else (Config.Ranks - rank) * Config.Files + file
			end
		end
	end

	-- HUD -------------------------------------------------------------------

	self.sideLabel.Text = string.format("White: %s     Black: %s", displayName(snapshot.white), displayName(snapshot.black))

	local modeText = "Spectating"
	if self.myColor then
		modeText = "You are " .. self.myColor
		if snapshot.mode == "Bot" then
			modeText ..= string.format("  ·  vs %s bot", snapshot.difficulty or "Medium")
		end
	end

	if snapshot.phase == "Active" then
		self.turnLabel.Text = string.format("%s to move  ·  %s", snapshot.turn, modeText)
	elseif snapshot.phase == "Finished" then
		self.turnLabel.Text = string.format("%s  ·  %s", snapshot.reason or "Finished", modeText)
	elseif snapshot.phase == "Waiting" then
		self.turnLabel.Text = "Waiting for an opponent"
	else
		self.turnLabel.Text = modeText
	end

	local statusParts = {}
	if snapshot.status and snapshot.status.inCheck and snapshot.phase == "Active" then
		table.insert(statusParts, "Check")
	end
	if snapshot.phase == "Finished" then
		local result = snapshot.result
		if result == "Draw" then
			table.insert(statusParts, "Draw")
		elseif result then
			table.insert(statusParts, (result == "WhiteWin" and "White" or "Black") .. " wins")
		end
	end
	if snapshot.lastMove and snapshot.lastMove.notation then
		table.insert(statusParts, snapshot.lastMove.notation)
	end
	self.statusLabel.Text = table.concat(statusParts, "\n")

	local active = snapshot.phase == "Active" or snapshot.phase == "Waiting"
	self.resignButton.Visible = (snapshot.phase == "Active") and self.myColor ~= nil

	-- Lobby -----------------------------------------------------------------

	local showLobby = snapshot.phase == "Idle" or snapshot.phase == "Finished" or snapshot.phase == "Waiting"
	self.lobby.overlay.Visible = showLobby
	if showLobby then
		if snapshot.phase == "Waiting" then
			self.lobby.subtitle.Text = "Waiting for a second player to join..."
			self.lobby.botButton.Visible = false
			self.lobby.pvpButton.Visible = false
			self.lobby.difficultyButton.Visible = false
		else
			self.lobby.subtitle.Text = if snapshot.phase == "Finished"
				then string.format("Last game: %s (%s)", snapshot.result or "over", snapshot.reason or "")
				else "10x8 board. Standard army plus the Hexer and the Rift."
			self.lobby.botButton.Visible = true
			self.lobby.pvpButton.Visible = true
			self.lobby.difficultyButton.Visible = true
		end
	end

	if active == false then
		self.selected = nil
		self.legalTargets = {}
	end
end

function Ui:render(snapshot)
	self.snapshot = snapshot
	local playerId = self.player.UserId
	self.myColor = nil
	if snapshot.white == playerId then
		self.myColor = Config.White
	elseif snapshot.black == playerId then
		self.myColor = Config.Black
	end

	-- A new position invalidates any half-finished selection.
	self.selected = nil
	self.legalTargets = {}
	if snapshot.phase ~= "Active" then
		self.promotion.overlay.Visible = false
		self.pendingPromotion = nil
	end

	self:_paint()
end

return Ui
