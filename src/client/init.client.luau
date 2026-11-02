--!strict
-- Client entry point (StarterPlayerScripts.Client).
--
-- Holds the 2D panel and forwards player intent. It renders whatever snapshot
-- the server last sent and nothing else, so a client that misses an update is
-- corrected by the next one rather than drifting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = require(script.Ui)

local player = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild("ChessRemotes")
local stateSync = remotesFolder:WaitForChild("StateSync") :: RemoteEvent
local startMatch = remotesFolder:WaitForChild("StartMatch") :: RemoteEvent
local submitMove = remotesFolder:WaitForChild("SubmitMove") :: RemoteEvent
local resign = remotesFolder:WaitForChild("Resign") :: RemoteEvent
local notice = remotesFolder:WaitForChild("Notice") :: RemoteEvent

local ui = Ui.new(player)

ui:setHandlers({
	onStart = function(mode: string, difficulty: string?)
		startMatch:FireServer(mode, difficulty)
	end,
	onMove = function(fromFile: number, fromRank: number, toFile: number, toRank: number, promotion: string?)
		submitMove:FireServer(fromFile, fromRank, toFile, toRank, promotion)
	end,
	onResign = function()
		resign:FireServer()
	end,
})

stateSync.OnClientEvent:Connect(function(snapshot)
	ui:render(snapshot)
end)

notice.OnClientEvent:Connect(function(message: string)
	ui:notice(message)
end)

print("[chess] client panel ready")
