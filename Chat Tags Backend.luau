--[[
This module has a function that creates a list of every tag a player has. Then
when the game does something that might change a players tags, it tells this module
to send out the new tags for that specific player. The front end of this just listens
to those requests and handles the tagging accordingly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Imports
local Knit = require(ReplicatedStorage.Packages.Knit)
local Admins = require(ReplicatedStorage.Shared.Admins)
local DataUtil = require(ServerStorage.Modules.DataUtil)
local MarketUtil = require(ReplicatedStorage.Shared.MarketUtil)
local Rebirths = require(ReplicatedStorage.Shared.Stats.Rebirths)
local Leaderboard = require(ServerStorage.Modules.Leaderboard)
local LeaderboardService

local TEST_PLACE_ID = 000000

-- Constants
local BasicTags = {
	["Owner"] = { Text = "[Owner]", Color = Color3.fromRGB(255, 0, 0) },
	["VIP"] = { Text = "[VIP]", Color = Color3.fromRGB(110, 255, 91) },
	["VerifiedTW"] = { Text = "[✅]", Color = Color3.fromRGB(84, 255, 69) },
	["Tester"] = { Text = "[$]", Color = Color3.fromRGB(69, 181, 255) },
	["Admin"] = { Text = "[Admin]", Color = Color3.fromRGB(187, 69, 255) },
}

local BoardEmojis = {
	["Power"] = "⚔",
	["Coins"] = "💰",
	["Playtime"] = "⏰",
	["RobuxSpent"] = `\u{E002}`,
	--["TimeTrialSpeedruns"] = "⏳",
}

local groupRanks = {}

-- Main
local ChatTagService = Knit.CreateService({
	Name = "ChatTagService",
	Client = {
		SetTags = Knit.CreateSignal(),
	},
})

local function SerialiseTags(tagsTable)
	local result = {}
	for i, tag in tagsTable do
		tag = table.clone(tag)
		tag.Color = (tag.Color or Color3.new(1, 1, 1)):ToHex()
		result[i] = tag
	end
	return result
end

function ChatTagService.Client:RequestInitialTags()
	local tbl = {}
	for _, v in Players:GetPlayers() do
		tbl[tostring(v.UserId)] = ChatTagService:GetTags(v)
	end
	return tbl
end

function ChatTagService:UpdateTags(player: Player)
	self.Client.SetTags:FireAll(player.UserId, self:GetTags(player))
end

function ChatTagService:UpdateAllTags()
	for i, player in Players:GetPlayers() do
		self.Client.SetTags:FireAll(player.UserId, self:GetTags(player))
	end
end

function ChatTagService:GetTags(player: Player)
	local profile = DataUtil:GetProfile(player)
	if not profile then
		return {}
	end

	local tags = {}

	-- Owners/Devs/Admins
	local adminRankName = Admins[player.UserId]
	if adminRankName then
		table.insert(tags, BasicTags[adminRankName])
	end

	--if profile.Data.TwitterVerified and profile.Data.DiscordVerified then
	--	table.insert(tags, BasicTags.VerifiedDCTW)
	--elseif profile.Data.TwitterVerified then
	--	table.insert(tags, BasicTags.VerifiedTW)
	--elseif profile.Data.DiscordVerified then
	--	table.insert(tags, BasicTags.VerifiedDC)
	--end

	if profile.Data.TwitterVerified then
		table.insert(tags, BasicTags.VerifiedTW)
	end

	-- VIP
	if MarketUtil.HasGamepass(player, "VIP") then
		table.insert(tags, BasicTags.VIP)
	end

	-- Rebirth
	local rebirthData = Rebirths[profile.Data.Rebirth]
	if rebirthData.TagColor then
		table.insert(tags, { Text = `[{rebirthData.Name}]`, Color = Color3.fromHex(rebirthData.TagColor) })
	end

	-- Leaderboard ranks
	local bestPlayerRank = 999
	local bestLBTag
	for boardId, emoji in BoardEmojis do
		local board = Leaderboard.GetBoard(boardId)
		local playerRank = board:GetRank(player)
		if playerRank then
			if playerRank < bestPlayerRank then
				bestLBTag = { Text = `[{emoji}#{playerRank}]`, Color = Color3.fromRGB(59, 213, 255) }
				bestPlayerRank = playerRank
			end
		end
	end

	if bestLBTag then
		table.insert(tags, bestLBTag)
	end

	return SerialiseTags(tags)
end

function ChatTagService:KnitStart()
	local function OnPlayerAdded(player)
		groupRanks[player.UserId] = player:GetRankInGroup(32491412)

		local profile = DataUtil:GetProfilePromise(player):expect()

		self:UpdateTags(player)
	end

	for i, v in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, v)
	end
	Players.PlayerAdded:Connect(OnPlayerAdded)

	Leaderboard.WaitForNextRefresh():andThen(function()
		self:UpdateAllTags()
	end)

	LeaderboardService.Updated:Connect(function()
		self:UpdateAllTags()
	end)
end

function ChatTagService:KnitInit()
	LeaderboardService = Knit.GetService("LeaderboardService")
end

return ChatTagService
