--!strict
-- Opening cinematic + site picker. While it runs, the camera tours the
-- Hollow (dome, Spire, the sealed deck, the Pit, the flooded collector, the
-- light coming down Shaft Zero) behind a title card. The same picker opens
-- later from [M]/[View] to switch sites or recall to the home dock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DroneState = require(script.Parent.Parent.DroneState)
local Net = require(script.Parent.Parent.Net)
local Ui = require(script.Parent.Parent.Ui)

local player = Players.LocalPlayer

local SiteSelect = {}

local WHITE = Color3.fromRGB(236, 242, 240)
local DIM = Color3.fromRGB(150, 160, 156)
local ACCENT = Color3.fromRGB(255, 196, 70)

-- Camera tour of the Hollow, in site-local coordinates: { from, lookAt, seconds }
local TOUR: { { Vector3 } } = {
	{ Vector3.new(70, 215, 70), Vector3.new(0, 70, 0) },
	{ Vector3.new(-60, 150, 55), Vector3.new(0, 96, 0) },
	{ Vector3.new(-40, 98, -30), Vector3.new(12, 86, 0) },
	{ Vector3.new(30, 60, -55), Vector3.new(-60, 30, 20) },
	{ Vector3.new(-50, 22, -30), Vector3.new(-95, 10, 0) },
	{ Vector3.new(10, 10, 20), Vector3.new(0, -4, 64) },
	{ Vector3.new(-30, -18, 58), Vector3.new(90, -26, 60) },
	{ Vector3.new(4, 250, 4), Vector3.new(0, 430, 0) },
	{ Vector3.new(20, 445, 40), Vector3.new(46, 432, 23) },
}
local LEG_SECONDS = 6.5

type Option = { id: string, title: string, detail: string }

local gui: ScreenGui
local card: Frame
local optionLabels: { TextLabel } = {}
local options: { Option } = {}
local focus = 1
local touring = false
local fade: Frame

local function buildOptions(includeRecall: boolean)
	table.clear(options)
	for _, id in Config.SITE_ORDER do
		local spec = Config.SITES[id]
		table.insert(options, { id = id, title = spec.name, detail = spec.subtitle })
	end
	if includeRecall then
		table.insert(options, {
			id = "Recall",
			title = "RECALL TO HOME DOCK",
			detail = "Return to this site's charging dock",
		})
		table.insert(options, { id = "Close", title = "CLOSE", detail = "Back to the feed" })
	end
end

local function refresh()
	for index, label in optionLabels do
		local option = options[index]
		label.Visible = option ~= nil
		if option then
			local selected = index == focus
			label.Text = ('<font color="#%s">%s %s</font>\n<font color="#9AA59F" size="13">   %s</font>'):format(
				if selected then "FFC446" else "ECF2F0",
				if selected then "▶" else " ",
				option.title,
				option.detail
			)
			label.BackgroundTransparency = if selected then 0.55 else 0.8
		end
	end
end

local function build()
	gui = Ui.create("ScreenGui", {
		Name = "SiteSelect",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Parent = player:WaitForChild("PlayerGui"),
	})
	-- Letterbox
	for _, y in { 0, 1 } do
		Ui.create("Frame", {
			AnchorPoint = Vector2.new(0, y),
			Position = UDim2.fromScale(0, y),
			Size = UDim2.new(1, 0, 0.09, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Name = "Letterbox",
			Parent = gui,
		})
	end
	card = Ui.create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 60, 0.52, 0),
		Size = UDim2.fromOffset(560, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.create(
		"UIListLayout",
		{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = card }
	)
	local function label(
		order: number,
		value: string,
		size: number,
		color: Color3,
		font: Enum.Font
	): TextLabel
		return Ui.create("TextLabel", {
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = value,
			TextColor3 = color,
			TextSize = size,
			Font = font,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextStrokeTransparency = 0.6,
			RichText = true,
			Parent = card,
		})
	end
	label(1, "PATRIOT HACKFEST 2026 · LIFE UNDERGROUND", 14, ACCENT, Enum.Font.GothamBold)
	label(2, "HOLLOW DRONE", 54, WHITE, Enum.Font.GothamBlack)
	label(
		3,
		"Sector 9, the Hollow, 2087. Blackouts, sewage floods, a jammed network, a lung-sickness cluster the Directorate won't count, and a surface nobody is allowed to see. One inspection drone with swappable sensors goes where people can't.",
		16,
		DIM,
		Enum.Font.Gotham
	)
	local problems = {}
	for number in Config.PROBLEMS do
		table.insert(problems, number)
	end
	table.sort(problems)
	local tags = {}
	for _, number in problems do
		table.insert(tags, "#" .. number)
	end
	label(
		4,
		("Covers %d of the 15 Hollow problems: %s"):format(#problems, table.concat(tags, " ")),
		14,
		ACCENT,
		Enum.Font.RobotoMono
	)
	for index = 1, 4 do
		local option = label(4 + index, "", 18, WHITE, Enum.Font.RobotoMono)
		option.BackgroundColor3 = Color3.new(0, 0, 0)
		Ui.create("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			Parent = option,
		})
		table.insert(optionLabels, option)
	end
	label(9, " ", 6, DIM, Enum.Font.Gotham)
	local hintLabel = label(10, "", 14, DIM, Enum.Font.RobotoMono)
	hintLabel.Name = "Hint"
	fade = Ui.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = gui,
	})
end

local function setHint()
	local hintLabel = card:FindFirstChild("Hint")
	if hintLabel and hintLabel:IsA("TextLabel") then
		hintLabel.Text = if DroneState.gamepad
			then "D-Pad ▲▼ choose   A deploy   B close"
			else "↑ ↓ choose   Enter / Click deploy   RMB close"
	end
end

local function runTour()
	touring = true
	local camera = Workspace.CurrentCamera
	local origin = Config.SITES.Hollow.origin
	task.spawn(function()
		local leg = 1
		while touring do
			local a = TOUR[leg]
			local b = TOUR[leg % #TOUR + 1]
			local startCf = CFrame.lookAt(origin + a[1], origin + a[2])
			local endCf = CFrame.lookAt(origin + b[1], origin + b[2])
			local cut = (b[1] - a[1]).Magnitude > 160
			local t0 = os.clock()
			while touring and os.clock() - t0 < LEG_SECONDS do
				local alpha = (os.clock() - t0) / LEG_SECONDS
				camera.CameraType = Enum.CameraType.Scriptable
				camera.FieldOfView = 62
				if cut then
					-- Long jumps are hard cuts with a slow push-in, like an edit
					camera.CFrame = endCf:Lerp(endCf * CFrame.new(0, 0, -6), alpha)
				else
					local eased = alpha * alpha * (3 - 2 * alpha)
					camera.CFrame = startCf:Lerp(endCf, eased)
				end
				RunService.RenderStepped:Wait()
			end
			leg = leg % #TOUR + 1
		end
	end)
end

local function open(withTour: boolean)
	buildOptions(not withTour)
	focus = 1
	if not withTour then
		local index = table.find(Config.SITE_ORDER, DroneState.site)
		focus = index or 1
	end
	DroneState.set("siteMenuOpen", true)
	gui.Enabled = true
	for _, child in gui:GetChildren() do
		if child.Name == "Letterbox" and child:IsA("Frame") then
			child.Visible = withTour
		end
	end
	card.BackgroundTransparency = if withTour then 1 else 0.35
	card.BackgroundColor3 = Color3.new(0, 0, 0)
	setHint()
	refresh()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

local function close()
	touring = false
	DroneState.set("siteMenuOpen", false)
	gui.Enabled = false
	if DroneState.cinematic then
		fade.BackgroundTransparency = 0
		DroneState.set("cinematic", false)
		TweenService:Create(fade, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
		gui.Enabled = true
		card.Visible = false
		for _, child in gui:GetChildren() do
			if child.Name == "Letterbox" and child:IsA("Frame") then
				child.Visible = false
			end
		end
		task.delay(1.3, function()
			gui.Enabled = DroneState.siteMenuOpen
			card.Visible = true
		end)
	end
end

local function confirm()
	local option = options[focus]
	if not option then
		return
	end
	if option.id == "Recall" then
		Net.fire("Recall")
		close()
	elseif option.id == "Close" then
		close()
	else
		Net.fire("SelectSite", option.id)
		if DroneState.cinematic then
			fade.BackgroundTransparency = 1
			TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
			task.delay(0.6, close)
		else
			close()
		end
	end
end

function SiteSelect.init()
	build()
end

function SiteSelect.start()
	DroneState.waitForDrone()
	-- Give the terrain and the world a moment to stream in, then fade up
	task.wait(1)
	runTour()
	open(true)
	TweenService:Create(fade, TweenInfo.new(2.5), { BackgroundTransparency = 1 }):Play()

	DroneState.Command.connect(function(name: string, direction: string?)
		if name == "ToggleSites" then
			if DroneState.cinematic or DroneState.menuOpen then
				return
			end
			if DroneState.siteMenuOpen then
				close()
			else
				open(false)
			end
			return
		end
		if not DroneState.siteMenuOpen then
			return
		end
		if name == "MenuNav" then
			if direction == "Up" then
				focus = math.max(1, focus - 1)
			elseif direction == "Down" then
				focus = math.min(#options, focus + 1)
			end
			refresh()
		elseif name == "MenuConfirm" then
			confirm()
		elseif name == "MenuBack" and not DroneState.cinematic then
			close()
		end
	end)
	DroneState.Changed.connect(function(key: string)
		if key == "gamepad" then
			setHint()
		end
	end)
	-- Mouse: hovering an option focuses it; the click itself is the Primary bind
	for index, label in optionLabels do
		label.MouseEnter:Connect(function()
			if DroneState.siteMenuOpen and options[index] then
				focus = index
				refresh()
			end
		end)
	end
end

return SiteSelect
