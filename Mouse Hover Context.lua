--[[
Unlike the traditional approach of using MouseEnter and MouseLeave, we can take advantage of
GetGuiObjectsAtPosition respecting visibility AND is sorted by ZIndex. 

We can then run that every frame, then use attributes to determine if any object under the mouse
has a context applied to it then display it
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Imports
local Knit = require(ReplicatedStorage.Packages.Knit)
local ClientGlobals = require(ReplicatedStorage.ClientModules.ClientGlobals)
local GuiUtil = require(ReplicatedStorage.ClientModules.GuiUtil)
local TableUtil = require(ReplicatedStorage.Shared.TableUtil)
local EnchantBar = require(ReplicatedStorage.ClientModules.Components.UIElements.EnchantBar)
local Trove = require(ReplicatedStorage.Packages.Trove)

-- Constants
local hoverGUI = ClientGlobals.PlayerGui.HoverContext
local hoverFrame = ClientGlobals.PlayerGui.HoverContext.Main

local assets = ReplicatedStorage.Assets

local defaultColGradient = Instance.new("UIGradient")
defaultColGradient.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))

local stylePropDefaults = {
	BackgroundTransparency = hoverFrame.BackgroundTransparency,
	BackgroundColor3 = hoverFrame.BackgroundColor3,
	StrokeGradient = defaultColGradient,
	StrokeThickness = 1
}

local TEXT_SIZES_BY_RESOLUTION = {
	{ Y = 1400, TextSize = 24 },
	{ Y = 400, TextSize = 20 },
	{ Y = 0, TextSize = 14 },
}

-- State
local currStyleString = nil
local hoverEnchantBar = EnchantBar.CreateNew({ Enchants = {} }, hoverGUI)

-- Main
local HoverContextController = Knit.CreateController({
	Name = "HoverContextController",
})

local function SerialiseStyle(styleTable)
	return HttpService:JSONEncode(styleTable)
end

local function ApplyStyleProp(propName, value)
	if propName == "StrokeGradient" then
		GuiUtil:CopyGradient(hoverFrame.UIStroke.UIGradient, value)
	elseif propName == "StrokeThickness" then
		hoverFrame.UIStroke.Thickness = value
	else
		hoverFrame[propName] = value
	end
end

local function ApplyStyle(styleString: string?)
	if currStyleString == styleString then
		return
	end

	currStyleString = styleString

	local data = if styleString then HttpService:JSONDecode(styleString) else stylePropDefaults
	for propName, default in stylePropDefaults do
		ApplyStyleProp(propName, if data[propName] then data[propName] else default)
	end
end

function HoverContextController:SetTextContext(text: string?)
	if text then
		hoverFrame.Label.Text = text
		hoverFrame.Visible = true
	else
		hoverFrame.Visible = false
		hoverFrame.Label.Text = ""
	end
end

function HoverContextController:AddContext(
	guiObject: GuiObject,
	text: string,
	style: typeof(stylePropDefaults)
)
	guiObject:SetAttribute("HoverContext", text)
	if style then
		guiObject:SetAttribute("HoverStyle", SerialiseStyle(style))
	else
		guiObject:SetAttribute("HoverStyle", nil)
	end
end

do
	local storedContexts = {}
	local currEnchantContext = nil

	function HoverContextController:SetEnchantContext(data)
		if currEnchantContext == data then
			return
		end

		currEnchantContext = data
		if data then
			hoverEnchantBar:SetData(data)
		else
			hoverEnchantBar:SetData({})
		end
	end

	function HoverContextController:AddEnchantContext(guiObject: GuiObject, data)
		if data == nil or not next(data) then
			return
		end

		if storedContexts[guiObject] then
			storedContexts[guiObject].Data = data
		else
			local ctx = {}
			ctx.Trove = Trove.new()
			ctx.Data = data

			ctx.Trove:AttachToInstance(guiObject)
			ctx.Trove:Add(function()
				storedContexts[guiObject] = nil
			end)

			storedContexts[guiObject] = ctx
		end
	end

	function HoverContextController:RemoveEnchantContext(guiObject)
		if storedContexts[guiObject] then
			storedContexts[guiObject].Trove:Destroy()
		end
	end

	function HoverContextController:GetEnchantContext(guiObject: GuiObject)
		if storedContexts[guiObject] then
			return storedContexts[guiObject].Data
		end
	end
end

local function ClampObjectPositionToScreen(guiObject: GuiObject)
	local absPos = guiObject.AbsolutePosition
	local absSize = guiObject.AbsoluteSize
	local screenBounds = hoverGUI.AbsoluteSize

	local clamped = Vector2.new(
		math.clamp(absPos.X, 3, screenBounds.X - absSize.X - 3),
		math.clamp(absPos.Y, 3, screenBounds.Y - absSize.Y - 3)
	)
	guiObject.Position = UDim2.fromOffset(clamped.X, clamped.Y)
end

function HoverContextController:KnitStart()
	RunService.RenderStepped:Connect(function(deltaTime)
		local pos = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()

		local guiObjects = ClientGlobals.PlayerGui:GetGuiObjectsAtPosition(pos.X, pos.Y)

		local resY = hoverGUI.AbsoluteSize.Y
		for i, v in TEXT_SIZES_BY_RESOLUTION do
			if resY >= v.Y then
				hoverFrame.Label.TextSize = v.TextSize
				break
			end
		end

		hoverFrame.Position = UDim2.fromOffset(pos.X + 16, pos.Y + 4)
		hoverEnchantBar.Instance.Position = UDim2.fromOffset(pos.X + 20, pos.Y + 8)


		for i, v in guiObjects do
			local enabledValue = v:GetAttribute("HoverContextEnabled")
			if enabledValue == false then -- not using "not" on purpose
				continue
			end

			local enchantContext = self:GetEnchantContext(v)
			if enchantContext then
				self:SetEnchantContext(enchantContext)
				self:SetTextContext(nil)
				ClampObjectPositionToScreen(hoverEnchantBar.Instance)
				return
			else
				local textContext = v:GetAttribute("HoverContext")
				if textContext then
					local styleString = v:GetAttribute("HoverStyle")
					ApplyStyle(styleString)
					
					self:SetTextContext(textContext)
					self:SetEnchantContext(nil)
					ClampObjectPositionToScreen(hoverFrame)
					return
				end
			end
		end
          
    -- no context to display so hide everything
		self:SetTextContext(nil)
		self:SetEnchantContext(nil)
	end)
end

function HoverContextController:KnitInit() end

return HoverContextController
