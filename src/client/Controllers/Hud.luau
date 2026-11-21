--!strict
-- Ground-control-station style OSD, modelled on real inspection-drone feeds:
--   top     REC timer + timestamp, compass heading tape, camera/sensor mode
--   centre  reticle, attitude (horizon) bar, proximity sensor arcs, target ID
--   sides   speed tape (left), altitude tape + vertical speed (right)
--   bottom  power (V / A / % / minutes), link (RSSI / latency / quality),
--           positioning (no GNSS underground: VIO + LiDAR SLAM), payloads
--   right   work orders for the site (mapped to the hackathon problems),
--           result cards from the server
-- Control hints switch between Xbox and keyboard labels.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Devices = require(ReplicatedStorage.Shared.Util.Devices)
local Gas = require(ReplicatedStorage.Shared.Util.Gas)
local Sites = require(ReplicatedStorage.Shared.Util.Sites)
local Units = require(ReplicatedStorage.Shared.Util.Units)
local Types = require(ReplicatedStorage.Shared.Types)
local DroneState = require(script.Parent.Parent.DroneState)
local Net = require(script.Parent.Parent.Net)
local Ui = require(script.Parent.Parent.Ui)
local Pilot = require(script.Parent.Pilot)
local Scanner = require(script.Parent.Scanner)

local player = Players.LocalPlayer
local M = Config.STUDS_TO_METERS

local Hud = {}

local WHITE = Color3.fromRGB(236, 242, 240)
local DIM = Color3.fromRGB(150, 165, 160)
local GREEN = Color3.fromRGB(110, 255, 150)
local AMBER = Color3.fromRGB(255, 196, 70)
local RED = Color3.fromRGB(255, 80, 80)
local CYAN = Color3.fromRGB(110, 225, 255)
local FONT = Enum.Font.RobotoMono
local FONT_BOLD = Enum.Font.GothamBold

local HINTS: { [string]: { pad: string, key: string } } = {
	Primary = { pad = "A", key = "LMB" },
	Secondary = { pad = "B", key = "RMB" },
	Switch = { pad = "X", key = "X" },
	Scan = { pad = "RB", key = "F" },
	Camera = { pad = "LB", key = "C" },
	Menu = { pad = "Y", key = "T" },
	Boost = { pad = "L3 hold", key = "Shift hold" },
	Lights = { pad = "D-Up", key = "L" },
	Log = { pad = "D-Down", key = "J" },
	Help = { pad = "D-Left", key = "H" },
	Sites = { pad = "View", key = "M" },
	Up = { pad = "RT", key = "Space / E" },
	Down = { pad = "LT", key = "Ctrl / Q" },
	Move = { pad = "Left stick", key = "WASD" },
	Look = { pad = "Right stick", key = "Mouse" },
	Recenter = { pad = "R3", key = "V" },
}

local SEVERITY_COLOR: { [string]: Color3 } = {
	info = CYAN,
	warning = AMBER,
	danger = RED,
	success = GREEN,
	data = WHITE,
}

local MODE_NAMES: { [string]: string } = {
	Normal = "EO · 4K · AUTO-EXP",
	Thermal = "IR · IRONBOW · 640",
	Night = "NV · GEN-III · GAIN HI",
	Chem = "CHEM · PID/EC SENSE",
	Lidar = "LIDAR · SLAM MAP",
}

local function hint(name: string): string
	local spec = HINTS[name]
	return if DroneState.gamepad then spec.pad else spec.key
end

local function hex(color: Color3): string
	return ("#%02X%02X%02X"):format(
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

local function colored(text: string, color: Color3): string
	return ('<font color="%s">%s</font>'):format(hex(color), text)
end

local function text(props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextSize = 14,
		TextStrokeTransparency = 0.55,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		RichText = true,
	}
	for key, value in props do
		merged[key] = value
	end
	return Ui.create("TextLabel", merged)
end

local function line(
	parent: Instance,
	position: UDim2,
	size: UDim2,
	color: Color3?,
	transparency: number?
): Frame
	return Ui.create("Frame", {
		BackgroundColor3 = color or WHITE,
		BackgroundTransparency = transparency or 0.15,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = parent,
	})
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local gui: ScreenGui
local recLabel: TextLabel
local clockLabel: TextLabel
local siteLabel: TextLabel
local modeLabel: TextLabel
local tape: Frame
local tapeMarks: { TextLabel } = {}
local headingLabel: TextLabel
local reticle: { Frame } = {}
local horizon: Frame
local proximity: { [string]: Frame } = {}
local speedBox: TextLabel
local altBox: TextLabel
local vsLabel: TextLabel
local aglLabel: TextLabel
local powerLabel: TextLabel
local linkLabel: TextLabel
local navLabel: TextLabel
local payloadLabel: TextLabel
local hardpointLabel: TextLabel
local actionLabel: TextLabel
local warnLabel: TextLabel
local gasLabel: TextLabel
local targetPanel: Frame
local targetLines: { TextLabel } = {}
local opsPanel: Frame
local opsText: TextLabel
local helpPanel: Frame
local helpText: TextLabel
local feedbackStack: Frame
local feedbackOrder = 0
local startedAt = os.clock()

local function build()
	gui = Ui.create("ScreenGui", {
		Name = "OSD",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local safe = Ui.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -48, 1, -40),
		Position = UDim2.fromOffset(24, 20),
		Parent = gui,
	})

	-- Top-left: recording + time + site
	recLabel = text({
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.fromOffset(320, 18),
		TextSize = 15,
		Parent = safe,
	})
	clockLabel = text({
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.fromOffset(320, 16),
		TextColor3 = DIM,
		Parent = safe,
	})
	siteLabel = text({
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.fromOffset(420, 16),
		TextColor3 = DIM,
		Parent = safe,
	})
	modeLabel = text({
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.fromOffset(420, 16),
		TextColor3 = CYAN,
		Parent = safe,
	})

	-- Top-centre: heading tape
	tape = Ui.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(460, 34),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = safe,
	})
	line(tape, UDim2.new(0.5, 0, 0, 22), UDim2.new(1, 0, 0, 1), WHITE, 0.5)
	for _ = 1, 25 do
		local mark = text({
			Size = UDim2.fromOffset(40, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 12,
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = tape,
		})
		table.insert(tapeMarks, mark)
	end
	headingLabel = text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 36),
		Size = UDim2.fromOffset(80, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 15,
		Font = FONT_BOLD,
		Parent = safe,
	})
	line(safe, UDim2.new(0.5, 0, 0, 30), UDim2.fromOffset(2, 10), AMBER, 0)

	-- Centre: reticle (thin cross with a gap), attitude bar, proximity arcs
	local centre = Ui.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(240, 240),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	for _, r in
		{
			{ UDim2.new(0.5, -14, 0.5, 0), UDim2.fromOffset(14, 2) },
			{ UDim2.new(0.5, 14, 0.5, 0), UDim2.fromOffset(14, 2) },
			{ UDim2.new(0.5, 0, 0.5, -14), UDim2.fromOffset(2, 14) },
			{ UDim2.new(0.5, 0, 0.5, 14), UDim2.fromOffset(2, 14) },
		}
	do
		table.insert(reticle, line(centre, r[1], r[2], WHITE, 0.1))
	end
	table.insert(reticle, line(centre, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(2, 2), WHITE, 0))
	horizon = Ui.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(200, 1),
		BackgroundTransparency = 1,
		Parent = centre,
	})
	line(horizon, UDim2.new(0, 30, 0.5, 0), UDim2.fromOffset(60, 1), GREEN, 0.35)
	line(horizon, UDim2.new(1, -30, 0.5, 0), UDim2.fromOffset(60, 1), GREEN, 0.35)
	local arcs: { [string]: { UDim2 } } = {
		front = { UDim2.new(0.5, 0, 0, 6), UDim2.fromOffset(70, 3) },
		back = { UDim2.new(0.5, 0, 1, -6), UDim2.fromOffset(70, 3) },
		left = { UDim2.new(0, 6, 0.5, 0), UDim2.fromOffset(3, 70) },
		right = { UDim2.new(1, -6, 0.5, 0), UDim2.fromOffset(3, 70) },
	}
	for name, spec in arcs do
		proximity[name] = line(centre, spec[1], spec[2], AMBER, 1)
	end

	-- Speed (left) and altitude (right) boxes, like a PFD
	local function tapeBox(anchor: number, x: UDim): TextLabel
		local frame = Ui.create("Frame", {
			AnchorPoint = Vector2.new(anchor, 0.5),
			Position = UDim2.new(x, UDim.new(0.5, 0)),
			Size = UDim2.fromOffset(96, 30),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Parent = gui,
		})
		Ui.create("UIStroke", { Color = WHITE, Transparency = 0.5, Parent = frame })
		return text({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 16,
			Font = FONT_BOLD,
			Parent = frame,
		})
	end
	speedBox = tapeBox(1, UDim.new(0.5, -170))
	altBox = tapeBox(0, UDim.new(0.5, 170))
	text({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -170, 0.5, -26),
		Size = UDim2.fromOffset(96, 14),
		Text = "H.S m/s",
		TextColor3 = DIM,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	text({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 170, 0.5, -26),
		Size = UDim2.fromOffset(96, 14),
		Text = "ALT m (L9 datum)",
		TextColor3 = DIM,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gui,
	})
	vsLabel = text({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 170, 0.5, 26),
		Size = UDim2.fromOffset(120, 14),
		TextSize = 12,
		Parent = gui,
	})
	aglLabel = text({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 170, 0.5, 42),
		Size = UDim2.fromOffset(120, 14),
		TextSize = 12,
		Parent = gui,
	})

	-- Target identification (right of the reticle)
	targetPanel = Ui.create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 40, 0.5, 90),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	})
	Ui.create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = targetPanel,
	})
	local bar = Ui.create("Frame", {
		Name = "Bar",
		Size = UDim2.new(0, 3, 1, 12),
		Position = UDim2.fromOffset(-8, -6),
		BorderSizePixel = 0,
		BackgroundColor3 = CYAN,
		Parent = targetPanel,
	})
	bar.ZIndex = 2
	local body = Ui.create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = targetPanel,
	})
	Ui.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	for index = 1, 5 do
		table.insert(
			targetLines,
			text({
				LayoutOrder = index,
				TextSize = if index == 1 then 14 else 13,
				TextWrapped = true,
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = body,
			})
		)
	end

	-- Bottom-left: power, link, navigation, gas
	local bottomLeft = Ui.create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(520, 110),
		BackgroundTransparency = 1,
		Parent = safe,
	})
	Ui.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Parent = bottomLeft,
	})
	gasLabel = text({ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), Parent = bottomLeft })
	powerLabel =
		text({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 18), TextSize = 15, Parent = bottomLeft })
	linkLabel =
		text({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 18), TextSize = 15, Parent = bottomLeft })
	navLabel = text({
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = DIM,
		Parent = bottomLeft,
	})

	-- Bottom-right: hardpoints and payload
	local bottomRight = Ui.create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(460, 80),
		BackgroundTransparency = 1,
		Parent = safe,
	})
	Ui.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Parent = bottomRight,
	})
	payloadLabel = text({
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = bottomRight,
	})
	hardpointLabel = text({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextSize = 15,
		Parent = bottomRight,
	})

	-- Bottom-centre: action prompt + warnings
	actionLabel = text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(700, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 15,
		Parent = safe,
	})
	warnLabel = text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(700, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 16,
		Font = FONT_BOLD,
		Parent = safe,
	})

	-- Right: work orders
	opsPanel = Ui.create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Parent = safe,
	})
	Ui.create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		Parent = opsPanel,
	})
	opsText = text({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextSize = 13,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = opsPanel,
	})

	feedbackStack = Ui.create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -96),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = safe,
	})
	Ui.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 6),
		Parent = feedbackStack,
	})

	-- Help card (left, under the header)
	helpPanel = Ui.create("Frame", {
		Position = UDim2.fromOffset(0, 126),
		Size = UDim2.fromOffset(450, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = safe,
	})
	Ui.create("UIPadding", {
		PaddingLeft = UDim.new(0, 15),
		PaddingRight = UDim.new(0, 15),
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		Parent = helpPanel,
	})
	helpText = text({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextSize = 18,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = helpPanel,
	})
end

---------------------------------------------------------------------------
-- Feedback cards
---------------------------------------------------------------------------

local function parseFeedback(raw: unknown): Types.Feedback?
	if typeof(raw) ~= "table" then
		return nil
	end
	local t = raw :: { [string]: unknown }
	if
		typeof(t.title) ~= "string"
		or typeof(t.text) ~= "string"
		or typeof(t.severity) ~= "string"
	then
		return nil
	end
	return { title = t.title, text = t.text, severity = t.severity :: Types.Severity }
end

local function showFeedback(feedback: Types.Feedback)
	local color = SEVERITY_COLOR[feedback.severity] or CYAN
	feedbackOrder += 1
	local card = Ui.create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		LayoutOrder = feedbackOrder,
		Parent = feedbackStack,
	})
	Ui.create("Frame", {
		Size = UDim2.new(0, 3, 1, 0),
		BorderSizePixel = 0,
		BackgroundColor3 = color,
		Parent = card,
	})
	local body = Ui.create("Frame", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -20, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	})
	Ui.create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		Parent = body,
	})
	Ui.create(
		"UIListLayout",
		{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = body }
	)
	text({
		Text = feedback.title,
		TextColor3 = color,
		Font = FONT_BOLD,
		TextSize = 13,
		RichText = false,
		LayoutOrder = 1,
		Parent = body,
	})
	text({
		Text = feedback.text,
		TextSize = 13,
		RichText = false,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 2,
		Parent = body,
	})
	local cards: { Frame } = {}
	for _, child in feedbackStack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #cards > 3 do
		local oldest = table.remove(cards, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local lifetime = if feedback.severity == "data" or feedback.severity == "danger" then 12 else 7
	task.delay(lifetime, function()
		card:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function actionText(hardpoint: string, deviceType: string?): string
	local drone = DroneState.drone
	if not drone then
		return ""
	end
	local module = DroneState.module(hardpoint)
	local _, primary = Devices.resolve(module, "Primary", deviceType, drone)
	local _, secondary = Devices.resolve(module, "Secondary", deviceType, drone)
	local parts = {}
	if primary then
		table.insert(parts, ("[%s] %s"):format(hint("Primary"), primary))
	end
	if secondary then
		table.insert(parts, ("[%s] %s"):format(hint("Secondary"), secondary))
	end
	return table.concat(parts, "    ")
end

local function refreshTarget()
	local target = DroneState.target
	local deviceType = Devices.typeOf(target)
	local spec = if deviceType then Config.DEVICES[deviceType] else nil
	local reticleColor = WHITE
	if target and spec then
		local categoryColor = Config.CATEGORY_COLORS[spec.category] or CYAN
		reticleColor = if DroneState.targetInRange then GREEN else categoryColor
		targetPanel.Visible = true
		local bar = targetPanel:FindFirstChild("Bar")
		if bar and bar:IsA("Frame") then
			bar.BackgroundColor3 = categoryColor
		end
		targetLines[1].Text = colored(
			("%s  %s"):format(tostring(target:GetAttribute("DeviceId")), spec.label),
			categoryColor
		) .. colored(("   %.1fm"):format(DroneState.targetDistance * M), DIM)
		targetLines[2].Text = tostring(target:GetAttribute("Label") or target.Name)
		local status = target:GetAttribute("Status")
		targetLines[3].Text = colored(tostring(status or ""), DIM)
		targetLines[3].Visible = status ~= nil
		local temperature = target:GetAttribute("Temperature")
		local showTemp = typeof(temperature) == "number" and DroneState.cameraMode == "Thermal"
		targetLines[4].Text = if showTemp
			then colored("SURFACE " .. Units.temp(temperature :: number), AMBER)
			else ""
		targetLines[4].Visible = showTemp
		if DroneState.targetInRange then
			local prompt = actionText(DroneState.activeHardpoint, deviceType)
			targetLines[5].Text = if prompt ~= ""
				then colored(prompt, GREEN)
				else colored(
					("No %s action. [%s] other hardpoint"):format(
						DroneState.module() or "?",
						hint("Switch")
					),
					DIM
				)
		else
			targetLines[5].Text = colored(
				("Close to %.1fm to interact"):format(Config.DRONE.INTERACT_RANGE * M),
				AMBER
			)
		end
		actionLabel.Text = ""
	else
		targetPanel.Visible = false
		local prompt = actionText(DroneState.activeHardpoint, nil)
		actionLabel.Text = if prompt ~= "" then prompt else ""
	end
	for _, piece in reticle do
		piece.BackgroundColor3 = reticleColor
	end
end

local function refreshTape()
	local heading = Pilot.heading()
	local width = 460
	local pixelsPerDegree = 4
	local index = 1
	local first = math.floor((heading - 55) / 5) * 5
	for degree = first, first + 120, 5 do
		local mark = tapeMarks[index]
		if not mark then
			break
		end
		index += 1
		local offset = (degree - heading) * pixelsPerDegree + width / 2
		local normalized = degree % 360
		local label = ""
		if normalized % 90 == 0 then
			label = ({ [0] = "N", [90] = "E", [180] = "S", [270] = "W" })[normalized]
		elseif normalized % 30 == 0 then
			label = tostring(normalized // 10)
		elseif normalized % 10 == 0 then
			label = "|"
		else
			label = "·"
		end
		mark.Text = label
		mark.Position = UDim2.fromOffset(offset, 2)
		mark.TextColor3 = if normalized % 90 == 0 then AMBER else WHITE
		mark.Visible = offset > 10 and offset < width - 10
	end
	for i = index, #tapeMarks do
		tapeMarks[i].Visible = false
	end
	headingLabel.Text = ("%03d°"):format(math.floor(heading + 0.5) % 360)
end

local drainEstimate = 0.2
local lastBattery = 100

local function refreshTelemetry(dt: number)
	local hull = DroneState.hull
	if not hull then
		return
	end
	local site = Config.SITES[DroneState.site] or Config.SITES[Config.DEFAULT_SITE]
	local localPos = hull.Position - site.origin

	-- Header
	local elapsed = os.clock() - startedAt
	local blink = elapsed % 1 < 0.6
	recLabel.Text = colored(if blink then "● REC" else "○ REC", RED)
		.. ("  %02d:%02d:%02d"):format(elapsed // 3600, (elapsed // 60) % 60, elapsed % 60)
	local now = os.date("!*t")
	clockLabel.Text = ("2087-11-20  %02d:%02d:%02d  ·  UNIT HD-%04d"):format(
		now.hour,
		now.min,
		now.sec,
		player.UserId % 10000
	)
	siteLabel.Text = site.name
	local modeName = MODE_NAMES[DroneState.cameraMode] or DroneState.cameraMode
	if DroneState.cameraMode == "Lidar" then
		modeName ..= ("  ·  %d pts"):format(DroneState.lidarPoints)
	end
	modeLabel.Text = modeName .. (if DroneState.headlights then "  ·  LIGHT ON" else "")

	refreshTape()

	-- Attitude bar: the airframe's roll and pitch (camera stays level)
	horizon.Rotation = Pilot.roll()
	horizon.Position = UDim2.new(0.5, 0, 0.5, math.clamp(DroneState.tilt, -30, 30) * 0.6)

	-- Speeds and heights
	speedBox.Text = ("%.1f"):format(DroneState.groundSpeed * M)
	altBox.Text = ("%+.1f"):format((localPos.Y - site.datum) * M)
	local vs = DroneState.verticalSpeed * M
	vsLabel.Text = ("VS %s%.1f m/s"):format(if vs >= 0 then "▲" else "▼", math.abs(vs))
	aglLabel.Text = ("AGL %.1f m"):format(math.min(DroneState.agl, 99) * M)

	-- Power
	local battery = DroneState.battery
	local delta = (lastBattery - battery) / math.max(dt, 1e-3)
	lastBattery = battery
	if not DroneState.docked and delta > 0 then
		drainEstimate += (delta - drainEstimate) * math.min(1, dt * 0.5)
	end
	local minutes = battery / math.max(drainEstimate, 0.05) / 60
	local batteryColor = if battery > 40 then GREEN elseif battery > 20 then AMBER else RED
	powerLabel.Text = colored(("BAT %3d%%"):format(math.floor(battery)), batteryColor)
		.. ("  %.1fV  %2dA  ~%d min"):format(
			DroneState.voltage,
			math.floor(DroneState.current),
			math.floor(minutes)
		)
		.. (if DroneState.docked then colored("  ⚡ DOCK CHARGING", GREEN) else "")

	-- Link
	local link = DroneState.link
	local rssi = -48 - (1 - link) * 46
	local latency = 22 + (1 - link) * 160 + math.noise(elapsed * 2) * 6
	local linkColor = if link >= Config.LINK.WEAK
		then GREEN
		elseif link >= Config.LINK.LOST then AMBER
		else RED
	linkLabel.Text = colored(("LINK %3d%%"):format(math.floor(link * 100)), linkColor)
		.. ("  %d dBm  %d ms  MESH 2.4/5.8"):format(
			math.floor(rssi),
			math.floor(math.max(15, latency))
		)

	-- Navigation (no satellites underground)
	navLabel.Text = ("POS VIO+LIDAR SLAM · GNSS NONE   X%+.1f Y%+.1f Z%+.1f m"):format(
		localPos.X * M,
		localPos.Y * M,
		localPos.Z * M
	)

	-- Gas sensor (Sensor pod only)
	if DroneState.hasModule("Sensor") then
		local readings = Gas.at(hull.Position, Gas.gather())
		local parts = {}
		for _, gas in { "H2S", "CH4", "Spores", "CO2" } do
			local value = readings[gas]
			if value and value >= 1 then
				local gasSpec = Config.GASES[gas]
				local harmful = value >= gasSpec.danger
				table.insert(
					parts,
					colored(
						("%s %d %s"):format(gasSpec.label, math.floor(value), gasSpec.unit),
						if harmful then RED else AMBER
					)
				)
			end
		end
		gasLabel.Text = "GAS  "
			.. (if #parts > 0 then table.concat(parts, "   ") else colored("clear", GREEN))
	else
		gasLabel.Text = ""
	end

	-- Proximity arcs
	local o = DroneState.obstacles
	for name, frame in proximity do
		local distance = (o :: any)[name] :: number
		if distance < 6 then
			frame.BackgroundTransparency = 0.1 + distance / 8
			frame.BackgroundColor3 = if distance < 2 then RED else AMBER
		else
			frame.BackgroundTransparency = 1
		end
	end

	-- Warnings (one line, most important first)
	local warning = ""
	if battery <= 0 then
		warning = colored("BATTERY DEPLETED · LIMP MODE · RETURN TO DOCK", RED)
	elseif battery < 20 then
		warning = colored(
			("LOW BATTERY %d%% · RETURN TO A DOCK"):format(math.floor(battery)),
			if blink then RED else AMBER
		)
	elseif DroneState.avoiding then
		warning = colored("OBSTACLE · AUTO-BRAKE", AMBER)
	elseif DroneState.wind.Magnitude > 6 then
		warning = colored(
			("WIND %.1f m/s · HOLDING POSITION"):format(DroneState.wind.Magnitude * M),
			AMBER
		)
	end
	warnLabel.Text = warning
end

local function refreshHardpoints()
	local drone = DroneState.drone
	if not drone then
		return
	end
	local lines = {}
	for _, hardpoint in { "A", "B" } do
		local module = DroneState.module(hardpoint)
		local spec = if module then Config.MODULES[module] else nil
		local active = DroneState.activeHardpoint == hardpoint
		local label = if spec then spec.label else "EMPTY"
		local color = if spec then spec.color else DIM
		table.insert(
			lines,
			(if active then "▶ " else "  ")
				.. colored(("HP-%s %s"):format(hardpoint, label), if active then color else DIM)
		)
	end
	hardpointLabel.Text = table.concat(lines, "\n")

	local cargo = {}
	local relays = drone:GetAttribute("Relays")
	if DroneState.hasModule("DataJack") then
		table.insert(cargo, ("RELAYS %d"):format(if typeof(relays) == "number" then relays else 0))
	end
	local packet = drone:GetAttribute("Packet")
	if typeof(packet) == "string" and packet ~= "" then
		table.insert(cargo, colored("DATA " .. packet, CYAN))
	end
	if drone:GetAttribute("Payload") == true then
		table.insert(cargo, colored("MED KIT LOADED", GREEN))
	end
	if drone:GetAttribute("Holding") == true then
		table.insert(cargo, colored("GRIPPING", AMBER))
	end
	local guiding = drone:GetAttribute("Guiding")
	if typeof(guiding) == "string" and guiding ~= "" then
		local follower: Model? = nil
		for _, model in CollectionService:GetTagged("Walker") do
			if model:IsA("Model") and model:GetAttribute("FollowerOf") == player.UserId then
				follower = model
			end
		end
		local hull = DroneState.hull
		if follower and hull then
			local distance = (follower:GetPivot().Position - hull.Position).Magnitude * M
			local first = string.split(guiding, ",")[1]
			local close = distance <= Config.DRONE.GUIDE_RANGE * M
			table.insert(
				cargo,
				colored(
					("♪ GUIDING %s %.0fm"):format(string.upper(first), distance),
					if close then GREEN else RED
				)
			)
		end
	end
	local cooldown = Scanner.cooldown()
	table.insert(
		cargo,
		if cooldown > 0 then ("SCAN %.1fs"):format(cooldown) else ("SCAN [%s]"):format(hint("Scan"))
	)
	payloadLabel.Text = table.concat(cargo, "   ")
end

local function refreshOps()
	opsPanel.Visible = DroneState.logOpen
	if not DroneState.logOpen then
		return
	end
	local mission = game:GetService("ReplicatedStorage"):FindFirstChild("Mission")
	local site = DroneState.site
	local out = {
		colored(
			"WORK ORDERS · " .. (Config.SITES[site] and Config.SITES[site].name or site),
			WHITE
		),
	}
	for _, group in Sites.groups(site) do
		local done = true
		local rows = {}
		for _, item in group.items do
			local value = if mission then mission:GetAttribute(item.key) else 0
			local count = if typeof(value) == "number" then value else 0
			local complete = count >= item.total
			done = done and complete
			table.insert(
				rows,
				("  %s %s %s"):format(
					if complete then colored("■", GREEN) else colored("□", DIM),
					if complete then colored(item.label, DIM) else item.label,
					colored(
						("%d/%d"):format(math.min(count, item.total), item.total),
						if complete then GREEN else AMBER
					)
				)
			)
		end
		local problems = {}
		for _, number in group.problems do
			table.insert(problems, "#" .. number)
		end
		table.insert(out, "")
		table.insert(
			out,
			colored(group.zone, if done then GREEN else CYAN)
				.. colored("  " .. table.concat(problems, " "), DIM)
		)
		if not done then
			table.insert(out, colored("  " .. group.brief, DIM))
		end
		for _, row in rows do
			table.insert(out, row)
		end
	end
	table.insert(out, "")
	table.insert(
		out,
		colored(
			("[%s] hide   [%s] sites   #n = hackathon problem"):format(hint("Log"), hint("Sites")),
			DIM
		)
	)
	opsText.Text = table.concat(out, "\n")
end

local function refreshHelp()
	helpPanel.Visible = DroneState.helpOpen
	if not DroneState.helpOpen then
		return
	end
	local rows = {
		{ "Move", "Fly (horizontal)" },
		{ "Up", "Climb" },
		{ "Down", "Descend" },
		{ "Look", "Gimbal / heading" },
		{ "Recenter", "Level the gimbal" },
		{ "Boost", "Sport mode" },
		{ "Primary", "Module action" },
		{ "Secondary", "Alt action" },
		{ "Switch", "Swap hardpoint" },
		{ "Scan", "Device scan ping" },
		{ "Camera", "EO / IR / NV / CHEM / LIDAR" },
		{ "Lights", "Headlight" },
		{ "Menu", "Loadout (at a dock)" },
		{ "Sites", "Site / recall menu" },
		{ "Log", "Work orders" },
		{ "Help", "Hide this" },
	}
	local out = {
		colored(
			"CONTROLS · " .. (if DroneState.gamepad then "XBOX" else "KEYBOARD + MOUSE"),
			WHITE
		),
	}
	for _, row in rows do
		table.insert(out, colored(("%-12s"):format(hint(row[1])), AMBER) .. row[2])
	end
	helpText.Text = table.concat(out, "\n")
end

function Hud.init()
	build()
end

function Hud.start()
	Net.on("Feedback", function(raw: unknown)
		local feedback = parseFeedback(raw)
		if feedback then
			showFeedback(feedback)
		end
	end)
	DroneState.waitForDrone()

	local slow = 0
	RunService.RenderStepped:Connect(function(dt: number)
		gui.Enabled = not DroneState.cinematic
		if DroneState.cinematic then
			return
		end
		refreshTarget()
		refreshTelemetry(dt)
		slow += dt
		if slow > 0.25 then
			slow = 0
			refreshHardpoints()
			refreshOps()
			refreshHelp()
		end
	end)
end

return Hud
