--!strict
-- Electronic detection. A ping wave sweeps outward from the drone. Every
-- electronic device it reaches is outlined through walls and tagged with its
-- device ID, type, status and raw block data, then fades after a few seconds.
-- People are not electronics: residents only show up on thermal.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Devices = require(ReplicatedStorage.Shared.Util.Devices)
local Types = require(ReplicatedStorage.Shared.Types)
local DroneState = require(script.Parent.Parent.DroneState)
local Ui = require(script.Parent.Parent.Ui)

local SCAN = Config.SCAN
local theme = Ui.theme

local Scanner = {}

type Mark = { highlight: Highlight, label: BillboardGui, expires: number }

local marks: { [Instance]: Mark } = {}
local folder: Folder
local lastScan = -math.huge
local generation = 0

local function anchorPart(device: Instance): BasePart?
	if device:IsA("BasePart") then
		return device
	elseif device:IsA("Model") then
		return device.PrimaryPart or device:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

-- "Block ID": the raw Roblox instance data behind the device.
local function blockId(device: Instance): string
	local part = anchorPart(device)
	if not part then
		return "BLK " .. device.ClassName
	end
	local size = part.Size
	return ("BLK %s<%s:%s> %.1fx%.1fx%.1f"):format(
		device.ClassName,
		part.ClassName,
		part.Material.Name,
		size.X,
		size.Y,
		size.Z
	)
end

local function clearMark(device: Instance)
	local mark = marks[device]
	if mark then
		mark.highlight:Destroy()
		mark.label:Destroy()
		marks[device] = nil
	end
end

local function makeMark(device: Instance, color: Color3, spec: Types.DeviceSpec?)
	local part = anchorPart(device)
	if not part or not device.Parent then
		return
	end
	clearMark(device)

	local highlight = Instance.new("Highlight")
	highlight.Adornee = device
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = color
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.Parent = folder

	local label = Ui.create("BillboardGui", {
		Adornee = part,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(240, 66),
		StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0),
		MaxDistance = 250,
		LightInfluence = 0,
		Parent = folder,
	})
	Ui.create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
		Parent = label,
	})
	local function line(order: number, text: string, size: number, lineColor: Color3)
		Ui.label({
			Text = text,
			TextSize = size,
			TextColor3 = lineColor,
			TextStrokeTransparency = 0.3,
			Position = UDim2.fromOffset(8, (order - 1) * 15),
			Size = UDim2.new(1, -8, 0, 15),
			RichText = false,
			Parent = label,
		})
	end
	local id = tostring(device:GetAttribute("DeviceId") or "????")
	line(1, ("[%s] %s"):format(id, if spec then spec.label else "UNKNOWN"), 13, color)
	line(2, tostring(device:GetAttribute("Label") or device.Name), 12, theme.text)
	line(3, tostring(device:GetAttribute("Status") or ""), 11, theme.dim)
	line(4, blockId(device), 10, Color3.fromRGB(110, 120, 130))

	marks[device] =
		{ highlight = highlight, label = label, expires = os.clock() + SCAN.HOLD_SECONDS }
end

local function ping()
	local hull = DroneState.hull
	if not hull or os.clock() - lastScan < SCAN.COOLDOWN then
		return
	end
	lastScan = os.clock()
	generation += 1
	local thisGeneration = generation

	-- Expanding wave
	local wave = Instance.new("Part")
	wave.Shape = Enum.PartType.Ball
	wave.Material = Enum.Material.ForceField
	wave.Color = theme.cyan
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.CanTouch = false
	wave.CastShadow = false
	wave.Size = Vector3.one * 2
	wave.CFrame = hull.CFrame
	wave.Parent = folder
	TweenService:Create(
		wave,
		TweenInfo.new(SCAN.WAVE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.one * SCAN.RANGE * 2,
			Transparency = 1,
		}
	):Play()
	Debris:AddItem(wave, SCAN.WAVE_SECONDS + 0.1)

	-- Devices in range, nearest first, within the highlight budget
	type Hit = { device: Instance, distance: number }
	local hits: { Hit } = {}
	for _, device in CollectionService:GetTagged("Device") do
		local deviceType = Devices.typeOf(device)
		local spec = if deviceType then Config.DEVICES[deviceType] else nil
		if spec and spec.category ~= "Life" and device:IsDescendantOf(Workspace) then
			local distance = (Devices.position(device) - hull.Position).Magnitude
			if distance <= SCAN.RANGE then
				table.insert(hits, { device = device, distance = distance })
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.distance < b.distance
	end)

	for device in marks do
		clearMark(device)
	end
	local count = math.min(#hits, SCAN.MAX_HIGHLIGHTS)
	DroneState.set("lastScanCount", count)
	DroneState.set("lastScanAt", os.clock())
	for i = 1, count do
		local hit = hits[i]
		local deviceType = Devices.typeOf(hit.device) :: string
		local spec = Config.DEVICES[deviceType]
		local color = Config.CATEGORY_COLORS[spec.category] or theme.cyan
		task.delay(hit.distance / SCAN.RANGE * SCAN.WAVE_SECONDS, function()
			if generation == thisGeneration then
				makeMark(hit.device, color, spec)
			end
		end)
	end
end

function Scanner.init()
	folder = Instance.new("Folder")
	folder.Name = "ScanFX"
	folder.Parent = Workspace
end

function Scanner.start()
	DroneState.Command.connect(function(name: string)
		if name == "Scan" then
			ping()
		end
	end)

	while true do
		task.wait(0.1)
		local now = os.clock()
		for device, mark in marks do
			local remaining = mark.expires - now
			if remaining <= 0 or not device.Parent then
				clearMark(device)
			elseif remaining < 1.5 then
				local fade = 1 - remaining / 1.5
				mark.highlight.OutlineTransparency = fade
				mark.highlight.FillTransparency = 0.8 + 0.2 * fade
			end
		end
	end
end

-- Seconds until the scanner is ready again (for the HUD).
function Scanner.cooldown(): number
	return math.max(0, SCAN.COOLDOWN - (os.clock() - lastScan))
end

return Scanner
