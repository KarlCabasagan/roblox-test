--!strict
-- Handles the client half of spawning the ball: the request fires once the
-- local character exists, so the server knows who asked and where they stand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = require(ReplicatedStorage.Shared)

local player = Players.LocalPlayer

-- Wait for our own character rather than firing on a module-load race.
local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

local remote: RemoteFunction = ReplicatedStorage:WaitForChild(Shared.REMOTE_NAME) :: RemoteFunction

local ok, err = pcall(function()
	return remote:InvokeServer()
end)

if not ok then
	warn(("[roblox-test] ball spawn request failed: %s"):format(tostring(err)))
end
