--!strict
-- Camera modes and screen effects, all local to this pilot.
--   NORMAL  - clean feed
--   THERMAL - world goes cold blue; heat signatures glow (through thin walls up close)
--   NIGHT   - green low-light amplification
--   CHEM    - needs the Sensor Pod; makes invisible gas clouds visible
--   LIDAR   - the spinning LiDAR puck builds a live point cloud (SLAM map),
--             rendered on black like a real survey viewer
-- Plus per-site lighting/atmosphere, a camera grade, scanlines, vignette and
-- signal static when the command link is weak.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Devices = require(ReplicatedStorage.Shared.Util.Devices)
local Units = require(ReplicatedStorage.Shared.Util.Units)
local Types = require(ReplicatedStorage.Shared.Types)
local DroneState = require(script.Parent.Parent.DroneState)
local Ui = require(script.Parent.Parent.Ui)

local THERMAL = Config.THERMAL
local player = Players.LocalPlayer

local Vision = {}

type Preset = {
	tint: Color3,
	brightness: number,
	contrast: number,
	saturation: number,
	ambient: Color3?,
	exposure: number?,
	bloom: number,
	scanlines: boolean,
}

local PRESETS: { [string]: Preset } = {
	Normal = {
		-- A real sensor: slightly flat, a touch cool, mild highlight bloom
		tint = Color3.fromRGB(246, 250, 255),
		brightness = 0.01,
		contrast = 0.12,
		saturation = -0.18,
		bloom = 0.35,
		scanlines = false,
	},
	Thermal = {
		tint = Color3.fromRGB(90, 110, 235),
		brightness = -0.02,
		contrast = 0.35,
		saturation = -1,
		ambient = Color3.fromRGB(80, 80, 95),
		exposure = 0.6,
		bloom = 0.9,
		scanlines = true,
	},
	Night = {
		tint = Color3.fromRGB(110, 255, 140),
		brightness = 0.18,
		contrast = 0.22,
		saturation = -1,
		ambient = Color3.fromRGB(105, 115, 105),
		exposure = 1.1,
		bloom = 1.3,
		scanlines = true,
	},
	Chem = {
		tint = Color3.fromRGB(220, 205, 255),
		brightness = 0.02,
		contrast = 0.15,
		saturation = -0.85,
		ambient = Color3.fromRGB(40, 40, 52),
		bloom = 0.6,
		scanlines = false,
	},
	Lidar = {
		tint = Color3.fromRGB(255, 255, 255),
		brightness = 0,
		contrast = 0,
		saturation = 0,
		bloom = 0.8,
		scanlines = false,
	},
}

local correction: ColorCorrectionEffect
local bloom: BloomEffect
local sunRays: SunRaysEffect
local atmosphere: Atmosphere
local siteLighting: Types.SiteLighting = Config.SITES[Config.DEFAULT_SITE].lighting
local scanlines: Frame
local staticLayer: Frame
local noise: { Frame } = {}
local linkLabel: TextLabel

type ThermalSlot = { highlight: Highlight, label: BillboardGui, text: TextLabel }
local slots: { ThermalSlot } = {}
local thermalFolder: Folder

---------------------------------------------------------------------------
-- Thermal
---------------------------------------------------------------------------

local RAMP: { { number } } = {
	-- temperature, r, g, b
	{ 20, 30, 0, 60 },
	{ 30, 120, 10, 70 },
	{ 34, 210, 40, 30 },
	{ 37, 255, 140, 0 },
	{ 39, 255, 235, 80 },
	{ 45, 255, 255, 255 },
}

function Vision.heatColor(temperature: number): Color3
	if temperature <= RAMP[1][1] then
		return Color3.fromRGB(RAMP[1][2], RAMP[1][3], RAMP[1][4])
	end
	for i = 2, #RAMP do
		local high = RAMP[i]
		if temperature <= high[1] then
			local low = RAMP[i - 1]
			local t = (temperature - low[1]) / (high[1] - low[1])
			return Color3.fromRGB(low[2], low[3], low[4])
				:Lerp(Color3.fromRGB(high[2], high[3], high[4]), t)
		end
	end
	return Color3.new(1, 1, 1)
end

local function hideSlot(slot: ThermalSlot)
	slot.highlight.Enabled = false
	slot.highlight.Adornee = nil
	slot.label.Enabled = false;
	(slot.label :: any).Adornee = nil
end

local function thermalStep()
	local hull = DroneState.hull
	if not hull then
		return
	end
	type Source = { instance: Instance, temperature: number, distance: number }
	local sources: { Source } = {}
	local function consider(instance: Instance)
		local temperature = instance:GetAttribute("Temperature")
		if
			typeof(temperature) == "number"
			and temperature >= 28
			and instance ~= DroneState.drone
		then
			local distance = (Devices.position(instance) - hull.Position).Magnitude
			if distance <= THERMAL.RANGE then
				table.insert(
					sources,
					{ instance = instance, temperature = temperature, distance = distance }
				)
			end
		end
	end
	for _, instance in CollectionService:GetTagged("Device") do
		consider(instance)
	end
	for _, instance in CollectionService:GetTagged("Drone") do
		consider(instance)
	end
	for _, part in CollectionService:GetTagged("Heat") do
		local temperature = part:GetAttribute("Temperature")
		if typeof(temperature) == "number" and part:IsA("BasePart") then
			local distance = (part.Position - hull.Position).Magnitude
			if distance <= THERMAL.RANGE then
				-- Background people light up as a whole body
				local target: Instance = part
				local parent = part.Parent
				if parent and parent:IsA("Model") and parent.Name == "Bystander" then
					target = parent
				end
				table.insert(
					sources,
					{ instance = target, temperature = temperature, distance = distance }
				)
			end
		end
	end
	-- People and the hottest things matter most, then distance
	table.sort(sources, function(a, b)
		local aLife = a.instance:GetAttribute("DeviceType") == "Resident"
			or a.instance.Name == "Bystander"
		local bLife = b.instance:GetAttribute("DeviceType") == "Resident"
			or b.instance.Name == "Bystander"
		if aLife ~= bLife then
			return aLife
		end
		return a.distance < b.distance
	end)

	for index, slot in slots do
		local source = sources[index]
		if not source then
			hideSlot(slot)
		else
			local color = Vision.heatColor(source.temperature)
			slot.highlight.Adornee = source.instance
			slot.highlight.FillColor = color
			slot.highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.5)
			slot.highlight.DepthMode = if source.distance <= THERMAL.THROUGH_WALL_RANGE
				then Enum.HighlightDepthMode.AlwaysOnTop
				else Enum.HighlightDepthMode.Occluded
			slot.highlight.Enabled = true

			local anchor = if source.instance:IsA("Model")
				then (source.instance :: Model).PrimaryPart
				else source.instance
			if anchor and anchor:IsA("BasePart") then
				slot.label.Adornee = anchor
				slot.label.Enabled = true
				local isPerson = source.instance:GetAttribute("DeviceType") == "Resident"
				local identified = source.instance:GetAttribute("Located") == true
				slot.text.Text = ("%s%s"):format(
					Units.temp(source.temperature),
					if isPerson
						then (if identified
							then "  " .. tostring(source.instance:GetAttribute("Label"))
							else "  LIFESIGN?")
						else ""
				)
				slot.text.TextColor3 = color
			end
		end
	end
end

---------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------

local function setGasVisible(visible: boolean)
	for _, cloud in CollectionService:GetTagged("GasCloud") do
		if cloud:IsA("BasePart") then
			cloud.Transparency = if visible then 0.78 else 1
		end
	end
end

local function apply(mode: string)
	local preset = PRESETS[mode] or PRESETS.Normal
	correction.TintColor = preset.tint
	correction.Brightness = preset.brightness
	correction.Contrast = preset.contrast
	correction.Saturation = preset.saturation
	bloom.Intensity = preset.bloom
	Lighting.Ambient = preset.ambient or siteLighting.ambient
	Lighting.ExposureCompensation = siteLighting.exposure + (preset.exposure or 0)
	scanlines.Visible = preset.scanlines
	setGasVisible(mode == "Chem")
	Vision.setLidarVisible(mode == "Lidar")
	if mode ~= "Thermal" then
		for _, slot in slots do
			hideSlot(slot)
		end
	end
end

local function cycle()
	local modes = Config.CAMERA_MODES
	local index = table.find(modes, DroneState.cameraMode) or 1
	for _ = 1, #modes do
		index = index % #modes + 1
		local candidate = modes[index]
		if candidate ~= "Chem" or DroneState.hasModule("Sensor") then
			DroneState.set("cameraMode", candidate)
			return
		end
	end
end

---------------------------------------------------------------------------
-- Site lighting (the Hollow has a real sun far above; the range is sealed)
---------------------------------------------------------------------------

local function applySite(site: string, instant: boolean)
	local spec = Config.SITES[site] or Config.SITES[Config.DEFAULT_SITE]
	siteLighting = spec.lighting
	local info = TweenInfo.new(if instant then 0 else 1.5)
	TweenService:Create(Lighting, info, {
		Brightness = siteLighting.brightness,
		ClockTime = siteLighting.clockTime,
		OutdoorAmbient = siteLighting.outdoorAmbient,
	}):Play()
	TweenService:Create(atmosphere, info, {
		Density = siteLighting.density,
		Haze = siteLighting.haze,
		Glare = siteLighting.glare,
		Color = siteLighting.atmosphereColor,
		Decay = siteLighting.decay,
	}):Play()
	Lighting.GeographicLatitude = 0
	apply(DroneState.cameraMode)
end

---------------------------------------------------------------------------
-- LiDAR SLAM point cloud
---------------------------------------------------------------------------

local lidarGui: ScreenGui
local lidarViewport: ViewportFrame
local lidarCamera: Camera
local lidarPool: { Part } = {}
local lidarNext = 1
local lidarCount = 0
local lidarBudget = 0
local lidarParams = RaycastParams.new()
lidarParams.FilterType = Enum.RaycastFilterType.Exclude

local function buildLidar()
	lidarGui = Ui.create("ScreenGui", {
		Name = "LidarView",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 0,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	lidarViewport = Ui.create("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(2, 3, 6),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(255, 255, 255),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(0, -1, 0),
		Parent = lidarGui,
	})
	lidarCamera = Instance.new("Camera")
	lidarCamera.Parent = lidarViewport
	lidarViewport.CurrentCamera = lidarCamera
	for _ = 1, Config.DRONE.LIDAR_POINTS do
		local point = Instance.new("Part")
		point.Anchored = true
		point.CanCollide = false
		point.CanQuery = false
		point.CanTouch = false
		point.CastShadow = false
		point.Material = Enum.Material.Neon
		point.Size = Vector3.new(0.2, 0.2, 0.2)
		point.CFrame = CFrame.new(0, -1e5, 0)
		point.Parent = lidarViewport
		table.insert(lidarPool, point)
	end
end

function Vision.setLidarVisible(visible: boolean)
	if lidarGui then
		lidarGui.Enabled = visible
	end
end

local function lidarStep(dt: number)
	local hull = DroneState.hull
	if not hull or DroneState.cinematic then
		return
	end
	lidarBudget += dt * Config.DRONE.LIDAR_RATE
	local count = math.floor(lidarBudget)
	lidarBudget -= count
	if count <= 0 then
		return
	end
	lidarParams.FilterDescendantsInstances = { Workspace:FindFirstChild("Drones") or hull }
	local origin = hull.Position + Vector3.new(0, 0.9, 0)
	local range = Config.DRONE.LIDAR_RANGE
	for _ = 1, math.min(count, 60) do
		local azimuth = math.random() * math.pi * 2
		local elevation = math.rad(-60 + math.random() * 100)
		local direction = (CFrame.Angles(0, azimuth, 0) * CFrame.Angles(elevation, 0, 0)).LookVector
		local hit = Workspace:Raycast(origin, direction * range, lidarParams)
		if hit then
			local point = lidarPool[lidarNext]
			point.CFrame = CFrame.new(hit.Position)
			local band = (hit.Position.Y / 36) % 1
			local closeness = 1 - math.clamp(hit.Distance / range, 0, 1) * 0.45
			point.Color = Color3.fromHSV(0.62 - band * 0.62, 0.8, closeness)
			lidarNext = lidarNext % #lidarPool + 1
			lidarCount = math.min(lidarCount + 1, #lidarPool)
		end
	end
	DroneState.lidarPoints = lidarCount
	if lidarGui.Enabled then
		local camera = Workspace.CurrentCamera
		lidarCamera.CFrame = camera.CFrame
		lidarCamera.FieldOfView = camera.FieldOfView
	end
end

---------------------------------------------------------------------------
-- Overlays
---------------------------------------------------------------------------

local function buildOverlay()
	local screen = Ui.create("ScreenGui", {
		Name = "VisionOverlay",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 1,
		Parent = player:WaitForChild("PlayerGui"),
	})

	scanlines = Ui.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = screen,
	})
	for i = 0, 59 do
		Ui.create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, i / 60),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = scanlines,
		})
	end

	-- Vignette: four gradient edges
	local edges = {
		{ position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.18), rotation = 90 },
		{ position = UDim2.fromScale(0, 0.82), size = UDim2.fromScale(1, 0.18), rotation = -90 },
		{ position = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.14, 1), rotation = 0 },
		{ position = UDim2.fromScale(0.86, 0), size = UDim2.fromScale(0.14, 1), rotation = 180 },
	}
	for _, edge in edges do
		local frame = Ui.create("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Position = edge.position,
			Size = edge.size,
			Parent = screen,
		})
		Ui.create("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new(0.25, 1),
			Parent = frame,
		})
	end

	staticLayer = Ui.create("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})
	for _ = 1, 90 do
		table.insert(
			noise,
			Ui.create("Frame", { BorderSizePixel = 0, Visible = false, Parent = staticLayer })
		)
	end
	linkLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(500, 40),
		Font = Enum.Font.GothamBlack,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Ui.theme.bad,
		TextStrokeTransparency = 0.4,
		RichText = false,
		Visible = false,
		Parent = screen,
	})
end

local rng = Random.new()

local function staticStep()
	local link = DroneState.link
	local intensity = math.clamp(1 - link / Config.LINK.WEAK, 0, 1) * 0.6
	staticLayer.BackgroundTransparency = 1 - intensity * 0.3
	for _, frame in noise do
		if rng:NextNumber() < intensity * 0.7 then
			frame.Visible = true
			frame.Position = UDim2.fromScale(rng:NextNumber(-0.1, 1), rng:NextNumber())
			frame.Size = UDim2.new(rng:NextNumber(0.02, 0.3), 0, 0, rng:NextInteger(1, 4))
			local shade = rng:NextNumber(0.4, 1)
			frame.BackgroundColor3 = Color3.new(shade, shade, shade)
			frame.BackgroundTransparency = 1 - intensity * rng:NextNumber(0.3, 0.8)
		else
			frame.Visible = false
		end
	end
	if link < Config.LINK.LOST then
		linkLabel.Visible = os.clock() % 1 < 0.6
		linkLabel.Text = "LINK LOST // NO COMMAND UPLINK"
	elseif link < Config.LINK.WEAK then
		linkLabel.Visible = true
		linkLabel.Text = ("SIGNAL WEAK %d%%"):format(math.floor(link * 100))
		linkLabel.TextSize = 20
	else
		linkLabel.Visible = false
		linkLabel.TextSize = 30
	end
end

---------------------------------------------------------------------------

function Vision.init()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Offset = 0
	atmosphere.Parent = Lighting
	sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.7
	sunRays.Parent = Lighting
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "VisionCorrection"
	correction.Parent = Lighting
	bloom = Instance.new("BloomEffect")
	bloom.Name = "VisionBloom"
	bloom.Threshold = 1.1
	bloom.Size = 24
	bloom.Parent = Lighting

	thermalFolder = Instance.new("Folder")
	thermalFolder.Name = "ThermalFX"
	thermalFolder.Parent = Workspace
	for _ = 1, THERMAL.MAX_HIGHLIGHTS do
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.1
		highlight.OutlineTransparency = 0.4
		highlight.Enabled = false
		highlight.Parent = thermalFolder
		local label = Ui.create("BillboardGui", {
			AlwaysOnTop = true,
			Size = UDim2.fromOffset(200, 20),
			StudsOffsetWorldSpace = Vector3.new(0, 3, 0),
			MaxDistance = THERMAL.RANGE,
			LightInfluence = 0,
			Enabled = false,
			Parent = thermalFolder,
		})
		local text = Ui.label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 14,
			Font = Ui.theme.fontBold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.2,
			RichText = false,
			Parent = label,
		})
		table.insert(slots, { highlight = highlight, label = label, text = text })
	end

	buildOverlay()
	buildLidar()
	applySite(Config.DEFAULT_SITE, true)
end

function Vision.start()
	DroneState.Command.connect(function(name: string)
		if name == "CycleCamera" then
			cycle()
		end
	end)
	DroneState.Changed.connect(function(key: string)
		if key == "cameraMode" then
			apply(DroneState.cameraMode)
		elseif key == "site" then
			applySite(DroneState.site, false)
		end
	end)

	local drone = DroneState.waitForDrone()
	local function checkModules()
		if DroneState.cameraMode == "Chem" and not DroneState.hasModule("Sensor") then
			DroneState.set("cameraMode", "Normal")
		end
	end
	drone:GetAttributeChangedSignal("HardpointA"):Connect(checkModules)
	drone:GetAttributeChangedSignal("HardpointB"):Connect(checkModules)

	RunService.RenderStepped:Connect(function(dt: number)
		staticStep()
		lidarStep(dt)
	end)

	while true do
		task.wait(0.25)
		if DroneState.cameraMode == "Thermal" then
			thermalStep()
		end
	end
end

return Vision
