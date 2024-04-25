--[[
Explanation:
The pool of items that is picked from is stored externally, which is what "LiveDataService" is for.
This uses a consistent Random seed for each cycle, then stores how many of an item have been bought in a memory store 
]]

--[[
    Quick maths

    UpdateAsync = 1 unit
    Limit = 1000 + 100 x number of users [PER MIN]
    
    if every server has at least ONE player
    that means we can do 100 requests per minute safely on every server.
    as such, an ideal update time is about 5 seconds (20 units). we can also combine
    the Save and Get requests into 1 update saving 2x units

    TLDR
    Trial Store uses 20% of the incremental budget for memory stores in a worst case scenario.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Imports
local Knit = require(ReplicatedStorage.Packages.Knit)
local RngUtil = require(ReplicatedStorage.Shared.RngUtil)
local TrialStoreUtils = require(ReplicatedStorage.Shared.TrialStoreUtils)
local DataUtil = require(ServerStorage.Modules.DataUtil)
local TableUtil = require(ReplicatedStorage.Shared.TableUtil)
local RewardService
local LiveDataService

-- Constants
local EXPIRATION_TIME = 86400 * 1.5
local UPDATE_INTERVAL = 60

local catalogStore = MemoryStoreService:GetSortedMap("TrialStore")

-- State
local currentCatalogId: string?

local catalogItems
local cachedCatalogSales = {}
local saleBuffer = {}

-- Main
local TrialShopService = Knit.CreateService({
	Name = "TrialShopService",
	Client = {
		CatalogChanged = Knit.CreateSignal(),
	},
})

local function GetLocalStockValue(itemId: string)
	if not catalogItems[itemId] then
		return -1
	end

	local totalStock = catalogItems[itemId].Stock
	return totalStock - ((cachedCatalogSales[itemId] or 0) + (saleBuffer[itemId] or 0))
end

function TrialShopService.Client:Buy(player: Player, itemId: string)
	local itemData = catalogItems[itemId]
	if not itemData then
		return 2, `Item no longer for sale.`
	end

	local profile = DataUtil:GetProfile(player)
	if GetLocalStockValue(itemId) > 0 then
		if profile.Data["Time Crystals"] >= itemData.Cost then
			DataUtil:Add(player, `Time Crystals`, -itemData.Cost)
			saleBuffer[itemId] = (saleBuffer[itemId] or 0) + 1
			RewardService:Award(player, itemData.Reward)
			return 1, `Purchase success!`
		else
			return 2, `Not enough Time Crystals!`
		end
	else
		return 2, `Item has sold out!`
	end
end

-- client will request this every 5 seconds when their UI is open
function TrialShopService.Client:GetData()
	if not catalogItems then
		return {}, TrialStoreUtils.NOT_LOADED_SALES
	end

	local itemDataToSend = {}
	for i, v in catalogItems do
		itemDataToSend[i] = table.clone(v)
	end

	local adjustedSaleTable = TrialStoreUtils.NOT_LOADED_SALES
	if cachedCatalogSales then
		adjustedSaleTable = table.clone(cachedCatalogSales)
		for i, v in saleBuffer do
			adjustedSaleTable[i] = (adjustedSaleTable[i] or 0) + v
		end
	end

	return itemDataToSend, adjustedSaleTable
end

function TrialShopService:PerformUpdate()
	local success, result = pcall(function()
		return catalogStore:UpdateAsync(currentCatalogId, function(currSaleTable)
			if not currSaleTable then
				return table.clone(saleBuffer)
			else
				for id, amount in saleBuffer do
					currSaleTable[id] = (currSaleTable[id] or 0) + amount
				end
				return currSaleTable
			end
		end, EXPIRATION_TIME)
	end)

	if not success then
		warn(`Failed to update trial store: {result}`)
	else
		table.clear(saleBuffer) -- Clear the sale buffer
		cachedCatalogSales = result -- Store the sales from the Update call
	end

	return success
end

-- does not run every call. only regens catalog if id is different
function TrialShopService:UpdateCatalog()
	local nextCatalogId = TrialStoreUtils.CurrentStockSeed(workspace:GetServerTimeNow())
	if currentCatalogId then
		if currentCatalogId ~= nextCatalogId then
			table.clear(saleBuffer)
			table.clear(cachedCatalogSales)
		else
			return -- No need to regenerate
		end
	end

	currentCatalogId = nextCatalogId

	local selectionPool = table.clone(LiveDataService:AwaitValue("trialShopContent"))
	local selectionPoolConst = TableUtil.filter(selectionPool, function(_, v)
		return v.Const
	end)
	selectionPool = TableUtil.filter(selectionPool, function(_, v)
		return not v.Const
	end)

	local pickedItems = {}

	-- Pick from normal pool
	do
		local sumItemWeight = 0
		for i, v in selectionPool do
			sumItemWeight += v.Weight
		end
		
		local numberOfItems = 6

		for i = 1, numberOfItems do
			local pick = RngUtil.SelectRandom(selectionPool, "Weight")
			pickedItems[pick] = table.clone(selectionPool[pick])
			pickedItems[pick].Weight = pickedItems[pick].Weight / sumItemWeight * 100
			selectionPool[pick] = nil -- Remove from the pool so it doesn't get picked again
		end
	end

	catalogItems = pickedItems

	self.Client.CatalogChanged:FireAll()

	return true
end

function TrialShopService:KnitStart()
	while true do
		self:UpdateCatalog()
		self:PerformUpdate()
		task.wait(UPDATE_INTERVAL)
	end
end

function TrialShopService:KnitInit()
	RewardService = Knit.GetService("RewardService")
	LiveDataService = Knit.GetService("LiveDataService")
end

return TrialShopService
