local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- Imports
local Knit = require(ReplicatedStorage.Packages.Knit)
local ClientGlobals = require(ReplicatedStorage.ClientModules.ClientGlobals)
local GuiUtil = require(ReplicatedStorage.ClientModules.GuiUtil)
local FrameController
local PromptController
local dialogModules: { DialogModule } = {}

-- Constants
type DialogModule = {
	NPCName: string,
	Nodes: { Node },
	EntryNode: string | (() -> string?),
}

type Node = {
	Text: string,
	Responses: { Response },
	OverrideIntervals: { [string]: number },
}

type Response = {
	Text: string,
	Gradient: string,
	NextNode: string,
}

local localPlayer = Players.LocalPlayer
local replica = ClientGlobals.Replica
local assets = ReplicatedStorage.Assets

local dialogFrame = ClientGlobals.PlayerGui.Overlay.Dialog
local camera = workspace.CurrentCamera

local screenGuisToDisable = {
	ClientGlobals.PlayerGui.HUD,
	ClientGlobals.PlayerGui.Frames,
}

local dialogInPosition = dialogFrame.Position
local dialogOutPosition = dialogFrame.Position + UDim2.fromScale(0, 0.5)

local DIALOG_TAG = "Core/Dialog"

-- State
local dialogActive = false
local currentNPC = nil

-- Main
local DialogController = Knit.CreateController({
	Name = "DialogController",
})

local responseButtons = {}

local function ClearResponseButtons()
	for i, v in responseButtons do
		v:Destroy()
	end
	table.clear(responseButtons)
end

local function eval(variant: () -> () | any, ...)
	if type(variant) == "function" then
		return variant(...)
	else
		return variant
	end
end

function DialogController:IsTalking()
	return dialogActive
end

function DialogController:HasDialog(npc: Model)
	return dialogModules[npc.Name] ~= nil
end

function DialogController:GetRemainingQuestCount(npc: Model)
	local questList = dialogModules[npc.Name].QuestList
	if not questList then
		return 0
	end
	local n = #questList
	for _, qid in questList do
		if replica.Data.CompletedQuests[qid] then
			n -= 1
		end
	end
	return n
end

function DialogController:BeginDialog(npc: Model)
	local dialogData = dialogModules[npc.Name]
	if not dialogData then
		error(`no dialog module found for {npc}`)
	end
	if dialogActive then
		return
	end
	dialogActive = true
	currentNPC = npc
	PromptController.Lock:Add(DIALOG_TAG)
	localPlayer.Character:SetAttribute("NoMoving", true)

	for i, v in screenGuisToDisable do
		v.Enabled = false
	end

	local hrpCFrame = npc.HumanoidRootPart.CFrame
	local headOffset = npc.Head.Position.Y - hrpCFrame.Y
	local targetCamCFrame = CFrame.lookAt(hrpCFrame * Vector3.new(-4.5, headOffset + 2.5, -8), hrpCFrame.Position)
	local startCamCFrame = camera.CFrame

	local timeSinceCamLerp = 0
	local tweenTime = 0.7
	RunService:BindToRenderStep("TalkFocusCam", Enum.RenderPriority.Camera.Value, function(dt)
		timeSinceCamLerp += dt

		local alpha = math.clamp(timeSinceCamLerp / tweenTime, 0, 1)
		alpha = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		camera.CFrame = startCamCFrame:Lerp(targetCamCFrame, alpha)
	end)

	dialogFrame.Visible = true
	dialogFrame.Position = dialogOutPosition
	dialogFrame:TweenPosition(dialogInPosition, "In", "Sine", 0.6, true)

	dialogFrame.NPC.Text = dialogData.NPCName
	dialogFrame.DialogText.Text = ""

	if dialogData.QuestList then
		local numFinished = 0
		for i, v in dialogData.QuestList do
			if replica.Data.CompletedQuests[v] then
				numFinished += 1
			end
		end
		dialogFrame.QuestsLeft.Text = `{numFinished}/{#dialogData.QuestList}`		
	else
		dialogFrame.QuestsLeft.Text = ""
	end

	SoundService.Dialog.EnterDialog:Play()

	task.wait(0.8)

	-- Init tree
	local charactersPerSecond = 1 / 30

	local function GetCharacterWaitTime(node: Node, char)
		if node.OverrideIntervals then
			for cp, interval in node.OverrideIntervals do -- cp = character/pattern..
				if char:match(cp) then
					return interval
				end
			end
		end
		return charactersPerSecond
	end

	local function LoadNode(node: Node, entryState: any)
		if not node then
			self:EndDialog()
			return
		end
		
		dialogFrame.DialogText.Text = `<stroke transparency="0.4">{eval(node.Text, entryState)}</stroke>`
		dialogFrame.DialogText.MaxVisibleGraphemes = 0

		local graphemes = {}
		for _, pos in utf8.graphemes(dialogFrame.DialogText.ContentText) do
			table.insert(graphemes, dialogFrame.DialogText.ContentText:match(utf8.charpattern, pos))
		end

		ClearResponseButtons()

		local skipped = false
		local skipButton = assets.UI.DialogButton:Clone()
		skipButton.LayoutOrder = 1
		skipButton.TextLabel.Text = "Skip"
		GuiUtil:CopyGradient(skipButton.UIGradient, "ButtonBlue")
		skipButton.Parent = dialogFrame.Responses
		skipButton.Activated:Connect(function()
			skipped = true
		end)

		table.insert(responseButtons, skipButton)

		local function OnResponse(response: Response)
			local nextNode, nextEntryState = eval(response.NextNode, entryState)
			if not nextNode then
				self:EndDialog()
			else
				if type(nextNode) == "string" then
					LoadNode(dialogData.Nodes[nextNode], nextEntryState)
				else
					LoadNode(nextNode, nextEntryState)
				end
			end
		end

		--local typeSound = SoundService.Dialog:FindFirstChild(node.Sound or "nofindpls")
		--	or SoundService.Dialog.typewrite1

		local sound = SoundService.Dialog.SpeakLoopMale
		if npc.Name == "Beep" then
			sound = SoundService.Dialog.SpeakLoopRobot
		end
		
		sound.Playing = true
		
		for i, char in graphemes do
			dialogFrame.DialogText.MaxVisibleGraphemes = i
			if skipped then
				break
			end
			
			--typeSound = typeSound:Clone()
			--typeSound.Parent = ClientGlobals.PlayerGui.World
			--typeSound.PlaybackSpeed = math.random(100, 105) / 100
			--typeSound:Play()
			--Debris:AddItem(typeSound, 0.15)
			
			task.wait(GetCharacterWaitTime(node, char))
		end
		
		sound.Playing = false
		dialogFrame.DialogText.MaxVisibleGraphemes = #graphemes

		ClearResponseButtons()

		for i, v in node.Responses do
			local button = assets.UI.DialogButton:Clone()
			button.LayoutOrder = i
			button.TextLabel.Text = v.Text
			GuiUtil:CopyGradient(button.UIGradient, v.Gradient)
			button.Parent = dialogFrame.Responses
			button.Activated:Connect(function()
				OnResponse(v)
			end)

			table.insert(responseButtons, button)
		end
	end

	local entry, entryState = eval(dialogData.EntryNode)
	if entry then
		if type(entry) == "string" then
			LoadNode(dialogData.Nodes[entry], entryState)
		else
			LoadNode(entry, entryState)
		end
	else
		self:EndDialog()
	end
end

local ending = false
function DialogController:EndDialog()
	if not dialogActive or ending then
		return
	end

	ending = true
	dialogFrame:TweenPosition(dialogOutPosition, "In", "Sine", 0.6, true)

	task.delay(0.5, function()
		ending = false
		localPlayer.Character:SetAttribute("NoMoving", false)
		ClearResponseButtons()

		for i, v in screenGuisToDisable do
			v.Enabled = true
		end

		PromptController.Lock:Remove(DIALOG_TAG)

		RunService:UnbindFromRenderStep("TalkFocusCam")
		dialogActive = false
		currentNPC = nil
	end)
end

function DialogController:KnitStart() end

function DialogController:KnitInit()
	PromptController = Knit.GetController("PromptController")
	FrameController = Knit.GetController("FrameController")
	for i, v in ReplicatedStorage.ClientModules.DialogTrees:GetChildren() do
		if v.Name == "Util" then
			continue
		end
		local module = require(v)
		dialogModules[module.NPCName] = module
	end
end

return DialogController
