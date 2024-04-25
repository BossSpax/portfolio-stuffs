local UIS = game:GetService("UserInputService")
local camera = workspace.CurrentCamera

local MouseCast = {}

local function Raycast(rayParams: RaycastParams)
	local pos = UIS:GetMouseLocation()
	local scrRay = camera:ViewportPointToRay(pos.X, pos.y)
	return workspace:Raycast(scrRay.Origin, scrRay.Direction * 500, rayParams)
end

function MouseCast:WithParams(rayParams: RaycastParams)
	return Raycast(rayParams)
end

local reuseParamsExclude = RaycastParams.new()
reuseParamsExclude.FilterType = Enum.RaycastFilterType.Exclude

function MouseCast:Exclude(exclusionList: { Instance })
	reuseParamsExclude.FilterDescendantsInstances = exclusionList
	return Raycast(reuseParamsExclude)
end

local reuseParamsInclude = RaycastParams.new()
reuseParamsInclude.FilterType = Enum.RaycastFilterType.Include

function MouseCast:Include(inclusionList: { Instance })
	reuseParamsInclude.FilterDescendantsInstances = inclusionList
	return Raycast(reuseParamsInclude)
end

return MouseCast
