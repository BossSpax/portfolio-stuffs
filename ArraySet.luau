--[[
This module serves as a faster dynamic array with constant time removals and insertions. 
Slower than normal arrays if data isn't being updated often due to function call overhead.
Also uses more memory because it uses a hash map to store indices along side the main array.
]]

type ArraySet = {
	values: { [number]: any },
	hashMap: { [any]: number },
	size: number
}

local ArraySet = {}

function ArraySet.create(): ArraySet
	return {
		values = {},
		hashMap = {},
		size = 0
	}
end

function ArraySet.contains(set: ArraySet, value: any)
	return set.hashMap[value] ~= nil
end

function ArraySet.add(set: ArraySet, value: any)
	if set.hashMap[value] then
		return
	end
	local index = set.size + 1
	set.values[index] = value
	set.hashMap[value] = index
	set.size = index
end

function ArraySet.remove(set: ArraySet, value: any)
	local removeIndex = set.hashMap[value]
	if not removeIndex then
		error(`{value} was not inside of the set.`)
	end
	if removeIndex ~= set.size and set.size > 1 then
		local swapValue = set.values[set.size]
		set.values[removeIndex] = swapValue
		set.hashMap[swapValue] = removeIndex
	end
	set.values[set.size] = nil
	set.hashMap[value] = nil
	set.size -= 1
end

function ArraySet.clear(set: ArraySet)
	table.clear(set.values)
	table.clear(set.hashMap)
	set.size = 0
end

return ArraySet
