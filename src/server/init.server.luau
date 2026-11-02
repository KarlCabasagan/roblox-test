--!strict
-- Server half: creates a single remote that lets a client request a ball, then
-- builds that ball in front of the requesting character.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = require(ReplicatedStorage.Shared)

-- Create (or reuse) the RemoteFunction the client calls.
local existing = ReplicatedStorage:FindFirstChild(Shared.REMOTE_NAME)
if existing and not existing:IsA("RemoteFunction") then
	existing:Destroy()
	existing = nil
end

local spawnBallRemote: RemoteFunction = if existing
	then existing :: RemoteFunction
	else Instance.new("RemoteFunction")

spawnBallRemote.Name = Shared.REMOTE_NAME
spawnBallRemote.Parent = ReplicatedStorage

local response = script:FindFirstChild("SpawnBallResponse")
if not response then
	response = Instance.new("StringValue")
	response.Name = "SpawnBallResponse"
	response.Value = ""
	response.Parent = script
end

local function buildBall(position: Vector3): Part
	local ball = Instance.new("Part")
	ball.Name = "TestBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(Shared.BALL_DIAMETER, Shared.BALL_DIAMETER, Shared.BALL_DIAMETER)
	ball.Color = Shared.BALL_COLOR
	ball.Material = Enum.Material.Neon
	ball.Position = position
	ball.Anchored = false
	ball.CanCollide = true
	ball.TopSurface = Enum.SurfaceType.Smooth
	ball.BottomSurface = Enum.SurfaceType.Smooth
	return ball
end

spawnBallRemote.OnServerInvoke = function(player: Player): boolean
	local character = player.Character
	if not character then
		warn(("[roblox-test] no character for %s"):format(player.Name))
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		warn(("[roblox-test] no HumanoidRootPart for %s"):format(player.Name))
		return false
	end

	local position = Shared.getSpawnPosition(rootPart, Shared.FORWARD_DISTANCE, Shared.HEIGHT_OFFSET)
	local ball = buildBall(position)
	ball.Parent = workspace

	print(("[roblox-test] spawned TestBall for %s at %s"):format(player.Name, tostring(position)))

	response.Value = ("spawned TestBall at %s for %s"):format(tostring(position), player.Name)

	return true
end

print("[roblox-test] server booted")
