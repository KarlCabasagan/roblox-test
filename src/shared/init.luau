--!strict
-- Shared constants and pure helpers used by both server and client.

local Shared = {}

-- Name of the RemoteFunction the client uses to ask the server for a ball.
Shared.REMOTE_NAME = "SpawnBall"

-- How far in front of the character the ball appears, in studs.
Shared.FORWARD_DISTANCE = 6

-- How far above the character's feet the ball rests, in studs.
Shared.HEIGHT_OFFSET = 2

Shared.BALL_DIAMETER = 4
Shared.BALL_COLOR = Color3.fromRGB(255, 170, 0)

--- Returns the world position `distance` studs ahead of a character root part,
--- at `heightOffset` above the root's own position. Uses the character's facing
--- direction, ignoring pitch so looking up or down does not move the ball.
function Shared.getSpawnPosition(rootPart: BasePart, distance: number, heightOffset: number): Vector3
	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)

	-- Guard against a degenerate direction (looking straight up or down): fall
	-- back to -Z, which is the convention for "forward" in Roblox.
	if flatLook.Magnitude < 1e-4 then
		flatLook = Vector3.new(0, 0, -1)
	end

	return rootPart.Position + flatLook.Unit * distance + Vector3.new(0, heightOffset, 0)
end

return Shared
