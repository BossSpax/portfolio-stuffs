local RS = game:GetService("RunService")

local RayHitbox = {}
RayHitbox.__index = RayHitbox

function RayHitbox.CreateHitbox(model: Model, rayParams)
	local self = setmetatable({
		Attachments = {},
		RaycastParams = rayParams,
		_runners = {}
	}, RayHitbox)
	
	for i, v in model:GetDescendants() do
		if v.Name == "DmgPoint" then
			table.insert(self.Attachments, v)
		end
	end
	
	model.DescendantAdded:Connect(function(att)
		if att.Name == "DmgPoint" then
			table.insert(self.Attachments, att)
		end
	end)
	
	return self
end

function RayHitbox:Start(onHit)
	local lastPositions = {}
	for _, v in self.Attachments do
		lastPositions[v] = v.WorldPosition
	end
	
	table.insert(self._runners, RS.Heartbeat:Connect(function()
		for _, v in self.Attachments do
			local newPos = v.WorldPosition
			local lastPos = lastPositions[v]
			if not lastPos then
				continue
			end
			
			local hit = workspace:Raycast(lastPos, newPos - lastPos, self.RaycastParams)
			if hit then
				onHit(hit, hit.Instance.Parent:FindFirstChildOfClass("Humanoid"), newPos - lastPos)
			end
			
			lastPositions[v] = newPos
		end
	end))
end

function RayHitbox:Stop()
	for i, v in self._runners do
		v:Disconnect()
	end
	table.clear(self._runners)
end

return RayHitbox
