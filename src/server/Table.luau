--!strict
-- Builds and maintains the physical table in the world.
--
-- The 3D board is a spectator view: it mirrors whatever the server's match
-- state says and is rebuilt from snapshots, never used as an input surface.
-- Players interact with the 2D panel instead, which keeps picking logic out of
-- the world entirely.
--
-- Built at run time rather than saved into the place, so the repository stays
-- the single source of truth for the table's shape.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Chess = require(game.ReplicatedStorage.Shared.Chess)
local Config = Chess.Config

local Table = {}

local TILE = 8
-- Top surface of the plinth. Squares sit on it; pieces stand on the squares.
local BOARD_TOP = 2
local LIFT = 0.5

local LIGHT_SQUARE = Color3.fromRGB(238, 232, 216)
local DARK_SQUARE = Color3.fromRGB(92, 98, 116)
local LAST_MOVE_TINT = Color3.fromRGB(214, 189, 92)

local WHITE_PIECE = Color3.fromRGB(240, 238, 232)
local BLACK_PIECE = Color3.fromRGB(38, 40, 48)

local PIECE_HEIGHT = {
	Pawn = 3.4,
	Rook = 4.0,
	Knight = 4.2,
	Bishop = 4.6,
	Queen = 5.4,
	King = 5.8,
	Hexer = 4.8,
	Rift = 4.6,
}

local squareParts: { [string]: Part } = {}
local pieceModels: { [number]: Model } = {}

-- Centre of a square in world space. Rank 1 sits on the +Z side, so players
-- approaching from the south see White's home rank nearest them.
function Table.squarePosition(file: number, rank: number): Vector3
	local x = (file - (Config.Files + 1) / 2) * TILE
	local z = ((Config.Ranks + 1) / 2 - rank) * TILE
	return Vector3.new(x, BOARD_TOP, z)
end

local function squareKey(file: number, rank: number): string
	return tostring(file) .. ":" .. tostring(rank)
end

local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Cylinders are authored lying along X, so a vertical column is a cylinder
-- rotated 90 degrees about Z with height carried on its X axis.
local function makeColumn(parent: Instance, name: string, diameter: number, height: number, bottomY: number, color: Color3): Part
	local part = makePart(parent, name, Vector3.new(height, diameter, diameter), Vector3.new(0, bottomY + height / 2, 0), color)
	part.Shape = Enum.PartType.Cylinder
	part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, 0, math.rad(90))
	return part
end

local function weld(part0: BasePart, part1: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = part0
	constraint.Part1 = part1
	constraint.Parent = part0
end

-- Adds the head of a piece on top of its column, plus any extra silhouette
-- that makes the custom pieces readable from across the table.
local function addHead(parent: Instance, pieceType: string, color: Color3, bottomY: number, base: BasePart)
	local size: Vector3
	local shape = Enum.PartType.Block

	if pieceType == "Pawn" then
		size = Vector3.new(1.7, 1.7, 1.7)
		shape = Enum.PartType.Ball
	elseif pieceType == "Rook" then
		size = Vector3.new(2.4, 1.4, 2.4)
	elseif pieceType == "Knight" then
		size = Vector3.new(2.2, 1.9, 1.5)
	elseif pieceType == "Bishop" then
		size = Vector3.new(1.7, 2.3, 1.7)
	elseif pieceType == "Queen" then
		size = Vector3.new(2.2, 2.2, 2.2)
		shape = Enum.PartType.Ball
	elseif pieceType == "King" then
		size = Vector3.new(1.8, 2.6, 1.8)
	elseif pieceType == "Hexer" then
		size = Vector3.new(2.0, 2.0, 2.0)
	elseif pieceType == "Rift" then
		size = Vector3.new(1.0, 1.4, 1.0)
	else
		size = Vector3.new(1.7, 1.7, 1.7)
		shape = Enum.PartType.Ball
	end

	local head = makePart(parent, "Head", size, Vector3.new(base.Position.X, bottomY + size.Y / 2, base.Position.Z), color)
	head.Shape = shape
	weld(base, head)

	if pieceType == "Hexer" then
		-- A diamond, tipped so it reads as a crystal rather than a block.
		head.CFrame = CFrame.new(head.Position) * CFrame.Angles(math.rad(45), 0, math.rad(45))
	elseif pieceType == "Rift" then
		-- Two upright prongs with a gap: a doorway from any angle.
		for _, offset in { -1.5, 1.5 } do
			local prong = makePart(
				parent,
				"Prong",
				Vector3.new(0.5, 2.4, 1.0),
				Vector3.new(base.Position.X + offset, bottomY + 1.2, base.Position.Z),
				color
			)
			weld(base, prong)
		end
	end
end

local function createPieceModel(parent: Instance, piece: { type: string, color: string, id: number }): Model
	local color = if piece.color == Config.White then WHITE_PIECE else BLACK_PIECE
	local height = PIECE_HEIGHT[piece.type] or 4.0

	local model = Instance.new("Model")
	model.Name = piece.color .. piece.type .. tostring(piece.id)

	local baseY = BOARD_TOP + LIFT
	local base = makePart(model, "Base", Vector3.new(3.6, 0.6, 3.6), Vector3.new(0, 0, 0), color)
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.7, 3.6, 3.6)
	base.CFrame = CFrame.new(Vector3.new(0, 0, 0)) * CFrame.Angles(0, 0, math.rad(90))
	-- The base is the model's anchor, so it carries the square position.
	base.CFrame = CFrame.new(Vector3.new(0, baseY + 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90))

	local stemHeight = math.max(height * 0.4, 1.2)
	local stem = makeColumn(model, "Stem", 1.5, stemHeight, baseY + 0.7, color)
	weld(base, stem)

	addHead(model, piece.type, color, baseY + 0.7 + stemHeight, base)

	model.PrimaryPart = base
	model.Parent = parent
	return model
end

-- Creates the plinth and the tiled surface. Safe to call twice: a previous
-- table is destroyed first.
function Table.build()
	local existing = Workspace:FindFirstChild("ChessTable")
	if existing then
		existing:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "ChessTable"

	local boardWidth = Config.Files * TILE
	local boardDepth = Config.Ranks * TILE

	local plinth = makePart(root, "Plinth", Vector3.new(boardWidth + 6, 2, boardDepth + 6), Vector3.new(0, 1, 0), Color3.fromRGB(52, 42, 36))
	plinth.Material = Enum.Material.WoodPlanks
	plinth.CanCollide = true

	makePart(root, "RailSouth", Vector3.new(boardWidth + 6, 1.2, 1.5), Vector3.new(0, 2.6, boardDepth / 2 + 2.2), Color3.fromRGB(66, 52, 42))
	makePart(root, "RailNorth", Vector3.new(boardWidth + 6, 1.2, 1.5), Vector3.new(0, 2.6, -boardDepth / 2 - 2.2), Color3.fromRGB(66, 52, 42))
	makePart(root, "RailEast", Vector3.new(1.5, 1.2, boardDepth + 6), Vector3.new(boardWidth / 2 + 2.2, 2.6, 0), Color3.fromRGB(66, 52, 42))
	makePart(root, "RailWest", Vector3.new(1.5, 1.2, boardDepth + 6), Vector3.new(-boardWidth / 2 - 2.2, 2.6, 0), Color3.fromRGB(66, 52, 42))

	local tiles = Instance.new("Folder")
	tiles.Name = "Squares"
	tiles.Parent = root

	squareParts = {}
	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			local isLight = (file + rank) % 2 == 0
			local position = Table.squarePosition(file, rank) + Vector3.new(0, 0.1, 0)
			local part = makePart(tiles, string.format("S%d_%d", file, rank), Vector3.new(TILE, 0.2, TILE), position, if isLight then LIGHT_SQUARE else DARK_SQUARE)
			squareParts[squareKey(file, rank)] = part
		end
	end

	local pieces = Instance.new("Folder")
	pieces.Name = "Pieces"
	pieces.Parent = root

	pieceModels = {}
	root.Parent = Workspace
	return root
end

local function baseColorOf(file: number, rank: number): Color3
	return if (file + rank) % 2 == 0 then LIGHT_SQUARE else DARK_SQUARE
end

local function tintSquare(file: number, rank: number, tint: Color3?)
	local part = squareParts[squareKey(file, rank)]
	if part then
		part.Color = tint or baseColorOf(file, rank)
	end
end

-- Brings the physical table in line with a wire snapshot: creates, moves, and
-- removes piece models, and highlights the last move.
function Table.applySnapshot(snapshot: { squares: { { number } }, lastMove: any })
	local root = Workspace:FindFirstChild("ChessTable")
	if not root then
		return
	end
	local piecesFolder = root:FindFirstChild("Pieces")
	if not piecesFolder then
		return
	end

	local seen: { [number]: boolean } = {}

	for _, entry in snapshot.squares do
		local file, rank, pieceType, color, id = entry[1], entry[2], entry[3], entry[4], entry[5]
		seen[id] = true

		local model = pieceModels[id]
		if not model then
			model = createPieceModel(piecesFolder, { type = pieceType, color = color, id = id })
			pieceModels[id] = model
		end

		local primary = model.PrimaryPart
		if primary then
			-- The base part's centre sits half its thickness above the lift line,
			-- which createPieceModel bakes in; match that here or pieces sink.
			local target = Table.squarePosition(file, rank) + Vector3.new(0, LIFT + 0.35, 0)
			if (primary.Position - target).Magnitude > 0.05 then
				-- Rotation is preserved so a tween never spins the piece.
				local goal = CFrame.new(target) * (primary.CFrame - primary.CFrame.Position)
				TweenService:Create(
					primary,
					TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = goal }
				):Play()
			end
		end
	end

	for id, model in pieceModels do
		if not seen[id] then
			model:Destroy()
			pieceModels[id] = nil
		end
	end

	for file = 1, Config.Files do
		for rank = 1, Config.Ranks do
			tintSquare(file, rank, nil)
		end
	end
	local lastMove = snapshot.lastMove
	if lastMove then
		tintSquare(lastMove.fromFile, lastMove.fromRank, LAST_MOVE_TINT)
		tintSquare(lastMove.toFile, lastMove.toRank, LAST_MOVE_TINT)
	end
end

-- Moves the default spawn behind the south rail so players arrive facing the
-- board instead of inside the plinth.
function Table.placeSpawn()
	local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawnLocation then
		return
	end
	local depth = Config.Ranks * TILE / 2 + 16
	spawnLocation.CFrame = CFrame.new(Vector3.new(0, 0.5, depth)) * CFrame.Angles(0, math.rad(180), 0)
	spawnLocation.Size = Vector3.new(12, 1, 12)
end

return Table
