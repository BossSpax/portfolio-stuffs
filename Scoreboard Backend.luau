--[[
Uses buffers for maximum scalability
In other cases it would be more suitable to just send it over as a table

scoreboard buffer format:
	[
	[8 bytes] UserId (f64)
	[1 bytes] level (255)
	[2 bytes] kills (65536)
	[2 bytes] deaths (65536)
	[2 bytes] lifetime wins (65536)
	[2 bytes] lifetime kills (65536)	
	]: Total 17 bytes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Imports
local Knit = require(ReplicatedStorage.Packages.Knit)
local DataUtil = require(ServerStorage.Modules.DataUtil)
local Util = require(ReplicatedStorage.Shared.Util)

-- State
local playersChanged = {}

-- Main
local ScoreboardService = Knit.CreateService {
	Name = "ScoreboardService",
	Client = {
		UpdateData = Knit.CreateSignal()
	}
}

local function getReadyPlayers()
	local plrs = {}
	for i, v in Players:GetPlayers() do
		if DataUtil:GetProfile(v) then
			table.insert(plrs, v)
		end
	end
	return plrs
end

local function createBufferFromPlayers(players: { Player })
	local buf = buffer.create(#players * 17)
	for i, plr in players do
		local profile = DataUtil:GetProfile(plr)
		if not profile or not plr:IsDescendantOf(game) then
			continue
		end
		buffer.writef64(buf, 0, plr.UserId)
		buffer.writei16(buf, 8, profile.Data.Level)
		buffer.writei16(buf, 9, profile.Data.SessionData.Kills)
		buffer.writei16(buf, 11, profile.Data.SessionData.Deaths)
		buffer.writei16(buf, 13, profile.Data.Stats.LifetimeWins)
		buffer.writei16(buf, 15, profile.Data.Stats.LifetimeKills)
	end
	return buf
end

local requested = {}
function ScoreboardService.Client:RequestInitialData(plr)
	if requested[plr] then
		return 
	end
	return createBufferFromPlayers(getReadyPlayers())
end

function ScoreboardService:MarkPlayerChanged(plr)
	if table.find(playersChanged, plr) then
		return
	end
	table.insert(playersChanged, plr)
end

function ScoreboardService:Update()
	if next(playersChanged) then
		local buf = createBufferFromPlayers(playersChanged)
		self.Client.UpdateData:FireAll(buf)
		table.clear(playersChanged)
	end
end

function ScoreboardService:KnitStart()
	Players.PlayerRemoving:Connect(function(plr)
		requested[plr] = nil
		local index = table.find(playersChanged, plr)
		if index then
			table.remove(playersChanged, index)
		end
	end)
	
	while true do
		task.wait(0.5) -- we work frequently so we don't end up stacking tons of data to send
		self:Update()
	end
end

function ScoreboardService:KnitInit()

end

return ScoreboardService
