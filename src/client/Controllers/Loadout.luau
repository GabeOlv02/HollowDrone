--!strict
-- DRONE SYSTEMS menu: swap modules on hardpoints A/B (only when docked),
-- or recall the drone to the bay from anywhere. Fully gamepad navigable.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DroneState = require(script.Parent.Parent.DroneState)
local Net = require(script.Parent.Parent.Net)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer
local theme = Ui.theme

local Loadout = {}

local FOCUS = { "A", "B", "Apply", "Recall" }

local window: Frame
local statusLabel: TextLabel
local hintLabel: TextLabel
local rows: { [string]: { frame: Frame, name: TextLabel, description: TextLabel } } = {}
local buttons: { [string]: TextButton } = {}
local focus = 1
local selection: { [string]: string } = { A = "Sensor", B = "Arm" }

local function focusStroke(instance: GuiObject): UIStroke
	local stroke = instance:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Ui.create("UIStroke", { Thickness = 2, Color = theme.amber, Parent = instance })
	end
	return stroke :: UIStroke
end

local function refresh()
	statusLabel.Text = if DroneState.docked
		then '<font color="#5AFF96">DOCKED</font>  module swap + charging available'
		else '<font color="#FFBE3C">NOT DOCKED</font>  fly onto a dock pad to swap modules'
	for _, hardpoint in { "A", "B" } do
		local spec = Config.MODULES[selection[hardpoint]]
		local row = rows[hardpoint]
		row.name.Text = ("<b>%s</b>"):format(spec.label)
		row.name.TextColor3 = spec.color
		row.description.Text = spec.description
	end
	for index, name in FOCUS do
		local target: GuiObject = if rows[name] then rows[name].frame else buttons[name]
		local stroke = focusStroke(target)
		stroke.Transparency = if index == focus then 0 else 1
	end
	buttons.Apply.BackgroundColor3 = if DroneState.docked
		then theme.amber
		else Color3.fromRGB(70, 70, 70)
	hintLabel.Text = if DroneState.gamepad
		then "D-Pad: select / change   A: confirm   B or Y: close"
		else "Click arrows or use arrow keys   Enter: confirm   T: close"
end

local function cycleModule(hardpoint: string, direction: number)
	local other = if hardpoint == "A" then "B" else "A"
	local order = Config.MODULE_ORDER
	local index = table.find(order, selection[hardpoint]) or 1
	for _ = 1, #order do
		index = (index - 1 + direction) % #order + 1
		if order[index] ~= selection[other] then
			selection[hardpoint] = order[index]
			break
		end
	end
	refresh()
end

local function close()
	window.Visible = false
	DroneState.set("menuOpen", false)
end

local function open()
	selection.A = DroneState.module("A") or Config.DEFAULT_LOADOUT.A
	selection.B = DroneState.module("B") or Config.DEFAULT_LOADOUT.B
	focus = 1
	window.Visible = true
	DroneState.set("menuOpen", true)
	refresh()
end

local function applyLoadout()
	if selection.A == selection.B then
		return
	end
	Net.fire("SetLoadout", { A = selection.A, B = selection.B })
	close()
end

local function recall()
	Net.fire("Recall")
	close()
end

local function button(
	name: string,
	text: string,
	color: Color3,
	parent: Instance,
	onClick: () -> ()
): TextButton
	local b = Ui.create("TextButton", {
		Text = text,
		Font = theme.fontBold,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(10, 14, 18),
		BackgroundColor3 = color,
		Size = UDim2.new(1 / 3, -6, 1, 0),
		Parent = parent,
	})
	Ui.create("UICorner", { CornerRadius = UDim.new(0, 2), Parent = b })
	b.Activated:Connect(onClick)
	buttons[name] = b
	return b
end

local function build()
	local screen = Ui.create("ScreenGui", {
		Name = "DroneSystems",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Parent = player:WaitForChild("PlayerGui"),
	})
	window = Ui.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.08,
		Visible = false,
		Parent = screen,
	})
	Ui.create(
		"UIListLayout",
		{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = window }
	)
	Ui.label({
		Text = "DRONE SYSTEMS // HARDPOINTS",
		Font = theme.fontBold,
		TextSize = 20,
		TextColor3 = theme.cyan,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 0,
		Parent = window,
	})
	statusLabel = Ui.label({ TextSize = 14, LayoutOrder = 1, Parent = window })

	for index, hardpoint in { "A", "B" } do
		local frame = Ui.create("Frame", {
			BackgroundColor3 = Color3.fromRGB(10, 20, 26),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 58),
			LayoutOrder = 1 + index,
			Parent = window,
		})
		Ui.label({
			Text = "HARDPOINT " .. hardpoint .. (if hardpoint == "A"
				then "  (left)"
				else "  (right)"),
			TextColor3 = theme.dim,
			TextSize = 12,
			Position = UDim2.fromOffset(46, 4),
			Parent = frame,
		})
		local name = Ui.label({
			TextSize = 17,
			Position = UDim2.fromOffset(46, 18),
			Size = UDim2.new(1, -92, 0, 20),
			Parent = frame,
		})
		local description = Ui.label({
			TextSize = 12,
			TextColor3 = theme.text,
			Position = UDim2.fromOffset(46, 38),
			Size = UDim2.new(1, -92, 0, 16),
			Parent = frame,
		})
		for _, arrow in
			{ { text = "<", x = 6, direction = -1 }, { text = ">", x = -38, direction = 1 } }
		do
			local arrowButton = Ui.create("TextButton", {
				Text = arrow.text,
				Font = theme.fontBold,
				TextSize = 20,
				TextColor3 = theme.cyan,
				BackgroundColor3 = Color3.fromRGB(20, 40, 50),
				Position = if arrow.x < 0
					then UDim2.new(1, arrow.x, 0.5, -16)
					else UDim2.new(0, arrow.x, 0.5, -16),
				Size = UDim2.fromOffset(32, 32),
				Parent = frame,
			})
			arrowButton.Activated:Connect(function()
				focus = index
				cycleModule(hardpoint, arrow.direction)
			end)
		end
		rows[hardpoint] = { frame = frame, name = name, description = description }
	end

	local actions = Ui.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = 10,
		Parent = window,
	})
	Ui.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 9),
		Parent = actions,
	})
	button("Apply", "APPLY LOADOUT", theme.amber, actions, applyLoadout)
	button("Recall", "RECALL TO BAY", theme.cyan, actions, recall)
	button("Close", "CLOSE", Color3.fromRGB(120, 130, 140), actions, close)

	hintLabel =
		Ui.label({ TextSize = 12, TextColor3 = theme.dim, LayoutOrder = 11, Parent = window })
end

function Loadout.init()
	build()
end

function Loadout.start()
	DroneState.Command.connect(function(name: string, direction: string?)
		if name == "ToggleMenu" then
			if DroneState.siteMenuOpen or DroneState.cinematic then
				return
			end
			if window.Visible then
				close()
			else
				open()
			end
		elseif not window.Visible then
			return
		elseif name == "MenuBack" then
			close()
		elseif name == "MenuNav" then
			if direction == "Up" then
				focus = math.max(1, focus - 1)
			elseif direction == "Down" then
				focus = math.min(#FOCUS, focus + 1)
			elseif direction == "Left" or direction == "Right" then
				local field = FOCUS[focus]
				if field == "A" or field == "B" then
					cycleModule(field, if direction == "Left" then -1 else 1)
				elseif field == "Apply" or field == "Recall" then
					focus = if field == "Apply" then 4 else 3
				end
			end
			refresh()
		elseif name == "MenuConfirm" then
			local field = FOCUS[focus]
			if field == "Apply" then
				applyLoadout()
			elseif field == "Recall" then
				recall()
			else
				focus += 1
				refresh()
			end
		end
	end)
	DroneState.Changed.connect(function(key: string)
		if window.Visible and (key == "docked" or key == "gamepad") then
			refresh()
		end
	end)
end

return Loadout
