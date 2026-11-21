--!strict
-- The world simulation, generic across sites. Builders register flood and
-- vent groups in Registry; devices point at them with attributes.
--   floods   valves + cleared debris drive a water level
--   vents    a breaker runs fans that clear gas clouds in its group
--   jammers  cut the cable and the Directorate jammer dies
--   beacons  pinged beacons broadcast SOS and extend the mesh
--   patients treated residents recover over time
--   truth    the Hollow's propaganda screens can be taken over
-- Pure visuals (fan spin, strobes, flicker) run on clients in Ambience.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Devices = require(ReplicatedStorage.Shared.Util.Devices)
local Units = require(ReplicatedStorage.Shared.Util.Units)

local Characters = require(script.Parent.Parent.Characters)
local Feedback = require(script.Parent.Parent.Feedback)
local Mission = require(script.Parent.Parent.Mission)
local Registry = require(script.Parent.Parent.Registry)
local HollowBuilder = require(script.Parent.HollowBuilder)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Environment = {}

local ventOn: { [string]: boolean } = {}

local function devices(deviceType: string): { Instance }
	local out = {}
	for _, instance in CollectionService:GetTagged("Device") do
		if
			instance:GetAttribute("DeviceType") == deviceType and instance:IsDescendantOf(Workspace)
		then
			table.insert(out, instance)
		end
	end
	return out
end

local function setLamp(model: Instance, name: string, color: Color3)
	local lamp = model:FindFirstChild(name, true)
	if lamp and lamp:IsA("BasePart") then
		lamp.Color = color
		local pointLight = lamp:FindFirstChildOfClass("PointLight")
		if pointLight then
			pointLight.Color = color
		end
	end
end

---------------------------------------------------------------------------
-- Floods
---------------------------------------------------------------------------

-- Recomputes a flood group's water from its valves and cleared debris.
-- Returns (level, valves set correctly, description of the effect).
function Environment.updateFlood(group: string): (number, number, string)
	local spec = Registry.floods[group]
	if not spec then
		return 0, 0, ""
	end
	local correct = 0
	for _, valve in spec.valves do
		if (valve:GetAttribute("Open") == true) == (valve:GetAttribute("CorrectOpen") == true) then
			correct += 1
		end
	end
	local cleared = 0
	for _, debris in devices("Debris") do
		if
			debris:GetAttribute("Objective") == spec.debrisObjective
			and debris:GetAttribute("Cleared") == true
		then
			cleared += 1
		end
	end
	local progress = correct / math.max(1, #spec.valves) * 0.55
		+ math.min(cleared, spec.debrisTotal) / math.max(1, spec.debrisTotal) * 0.45
	local level = spec.apply(progress)
	Mission.set(spec.valveObjective, correct)
	return level, correct, spec.describe(level)
end

---------------------------------------------------------------------------
-- Ventilation
---------------------------------------------------------------------------

function Environment.setVent(group: string, on: boolean): string
	local spec = Registry.vents[group]
	if not spec then
		return ""
	end
	ventOn[group] = on
	local breaker = spec.breaker
	breaker:SetAttribute("On", on)
	breaker:SetAttribute("Status", if on then "FANS RUNNING" else "OFF")
	setLamp(
		breaker,
		"StatusLamp",
		if on then Color3.fromRGB(80, 255, 120) else Color3.fromRGB(255, 50, 50)
	)
	for _, fan in CollectionService:GetTagged("Fan") do
		if fan:GetAttribute("VentGroup") == group then
			fan:SetAttribute("Running", on)
		end
	end
	Mission.set(spec.objective, if on then 1 else 0)
	return if on then spec.onText else spec.offText
end

local function gasStep()
	for _, cloud in CollectionService:GetTagged("GasCloud") do
		if cloud:IsA("BasePart") then
			local group = cloud:GetAttribute("VentGroup")
			local scale = cloud:GetAttribute("Scale")
			local radius = cloud:GetAttribute("Radius")
			if
				typeof(group) == "string"
				and typeof(scale) == "number"
				and typeof(radius) == "number"
			then
				local on = ventOn[group] == true
				local target = if on then Config.GAS_VENTED_SCALE else 1
				local rate = if on then Config.GAS_VENT_RATE else 0.01
				local nextScale = if scale > target
					then math.max(target, scale - rate)
					else math.min(target, scale + rate)
				if nextScale ~= scale then
					cloud:SetAttribute("Scale", nextScale)
					cloud.Size = Vector3.one * math.max(0.2, radius * 2 * nextScale)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Network
---------------------------------------------------------------------------

function Environment.activateBeacon(beacon: Instance)
	beacon:SetAttribute("Active", true)
	beacon:SetAttribute("Status", "BROADCASTING SOS")
	beacon:SetAttribute("LinkRange", Config.LINK.BEACON_RANGE)
	beacon:SetAttribute("Temperature", 40)
end

function Environment.disableJammer(jammer: Instance)
	jammer:SetAttribute("Active", false)
	jammer:SetAttribute("Status", "DISABLED (cable cut)")
	jammer:SetAttribute("Temperature", 30)
	for _, glow in jammer:GetDescendants() do
		if glow:IsA("BasePart") and glow.Name == "Glow" then
			glow.Color = Color3.fromRGB(40, 20, 30)
			glow.Material = Enum.Material.SmoothPlastic
			local pointLight = glow:FindFirstChildOfClass("PointLight")
			if pointLight then
				pointLight.Enabled = false
			end
			-- A short shower of sparks from the cut
			local sparks = Instance.new("ParticleEmitter")
			sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparks.Color =
				ColorSequence.new(Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 90, 20))
			sparks.LightEmission = 1
			sparks.Size = NumberSequence.new(0.18, 0.02)
			sparks.Lifetime = NumberRange.new(0.4, 0.9)
			sparks.Speed = NumberRange.new(8, 18)
			sparks.SpreadAngle = Vector2.new(60, 60)
			sparks.Acceleration = Vector3.new(0, -60, 0)
			sparks.Drag = 1
			sparks.Rate = 0
			sparks.Parent = glow
			sparks:Emit(60)
			task.delay(3, function()
				sparks:Destroy()
			end)
		end
	end
	local cable = jammer:FindFirstChild("Cable", true)
	if cable and cable:IsA("BasePart") then
		cable.Size = Vector3.new(cable.Size.X, cable.Size.Y * 0.5, cable.Size.Z)
		cable.CFrame = cable.CFrame * CFrame.new(0, -cable.Size.Y / 2, 0)
	end
end

local function inside(zone: BasePart, position: Vector3): boolean
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

-- Recounts deployed relays inside every RelayZone (one objective per zone).
function Environment.countRelays()
	local relays = devices("RelayNode")
	for _, zone in CollectionService:GetTagged("RelayZone") do
		local objective = zone:GetAttribute("Objective")
		if zone:IsA("BasePart") and typeof(objective) == "string" then
			local count = 0
			for _, relay in relays do
				if inside(zone, Devices.position(relay)) then
					count += 1
				end
			end
			Mission.set(objective, count)
		end
	end
end

---------------------------------------------------------------------------
-- The truth broadcast (Hollow, OP-5)
---------------------------------------------------------------------------

local function countWhere(predicate: (Instance) -> boolean): number
	local count = 0
	for _, resident in devices("Resident") do
		if Devices.position(resident).Z > 1000 and predicate(resident) then
			count += 1
		end
	end
	return count
end

function Environment.broadcast(player: Player)
	local located = countWhere(function(r)
		return r:GetAttribute("Located") == true and r:GetAttribute("Condition") ~= "Healthy"
	end)
	local treated = countWhere(function(r)
		return r:GetAttribute("Treated") == true
	end)
	local surface = Workspace:GetAttribute("SurfaceAir")
	local air = if typeof(surface) == "string"
		then surface
		else "O2 20.8% · CO2 428 ppm · PM2.5 9 µg/m³ (Met Station 4 archive)"
	local cases = math.max(located, 4)
	local truth = ("INDEPENDENT DRONE SURVEY · 2087\n\nSURFACE AIR: %s\nVERDICT: BREATHABLE\n\nLEVEL 9 LUNG SICKNESS: %d+ CASES FOUND (Directorate says 3)\nMED KITS DELIVERED: %d\n\nTHE MESH IS OPEN. PASS IT ON."):format(
		air,
		cases,
		treated
	)
	for _, screen in CollectionService:GetTagged("PublicScreen") do
		screen:SetAttribute("Broadcast", true)
		screen:SetAttribute("Status", "RESISTANCE BROADCAST")
		local label = screen:FindFirstChild("Text", true)
		if label and label:IsA("TextLabel") then
			label.Text = truth
			label.TextColor3 = Color3.fromRGB(150, 245, 255)
		end
		local panel = screen:FindFirstChild("Panel", true)
		if panel and panel:IsA("BasePart") then
			panel.Color = Color3.fromRGB(4, 30, 40)
			local glow = panel:FindFirstChildOfClass("SurfaceLight")
			if glow then
				glow.Color = Color3.fromRGB(80, 220, 255)
			end
		end
	end
	Workspace:SetAttribute("TruthBroadcast", true)
	Feedback.all(
		"HOLLOW-WIDE BROADCAST",
		("%s pushed the surface logs through the mesh. Every public screen in Sector 9 now shows the real air data and outbreak count."):format(
			player.DisplayName
		),
		"success"
	)
end

---------------------------------------------------------------------------
-- Patients
---------------------------------------------------------------------------

-- Every person has their own body temperature (BaseTemperature, rolled at
-- build time inside the band for their condition) and wobbles a little
-- around it. Treated patients cool back into the healthy band. Untreated
-- fever patients cough every few seconds (clients play the cough).
local VITALS = Config.VITALS
local vitalsRng = Random.new()
local nextCough: { [Instance]: number } = {}
local phases: { [Instance]: number } = {}

local function wobble(instance: Instance, base: number, t: number): number
	local phase = phases[instance]
	if not phase then
		phase = vitalsRng:NextNumber(0, 100)
		phases[instance] = phase
	end
	local value = base
		+ VITALS.DRIFT
			* (0.6 * math.sin(t * 0.21 + phase) + 0.4 * math.sin(t * 0.53 + phase * 2))
	return math.round(value * 10) / 10
end

local function residentStep(dt: number)
	local t = os.clock()
	for _, person in devices("Resident") do
		local base = person:GetAttribute("BaseTemperature")
		if typeof(base) ~= "number" then
			continue
		end
		local treated = person:GetAttribute("Treated") == true
		if treated then
			local target = person:GetAttribute("RecoveredTemperature")
			if typeof(target) ~= "number" then
				local band = VITALS.Healthy
				target = math.round(vitalsRng:NextNumber(band[1] + 0.3, band[2]) * 10) / 10
				person:SetAttribute("RecoveredTemperature", target)
			end
			if base > (target :: number) then
				base = math.max(target :: number, base - VITALS.RECOVERY_RATE * dt)
				person:SetAttribute("BaseTemperature", base)
			end
		end
		local temperature = wobble(person, base, t)
		if person:GetAttribute("Temperature") ~= temperature then
			person:SetAttribute("Temperature", temperature)
			if treated then
				person:SetAttribute(
					"Status",
					(if temperature >= VITALS.FEVER_LINE then "RECOVERING " else "RECOVERED ")
						.. Units.temp(temperature)
				)
			end
		end
		-- Coughing (fever, untreated)
		if person:GetAttribute("Condition") == "Fever" and not treated then
			local due = nextCough[person]
			if not due then
				nextCough[person] = t + vitalsRng:NextNumber(0, VITALS.COUGH_INTERVAL[2])
			elseif t >= due then
				local interval = VITALS.COUGH_INTERVAL
				nextCough[person] = t + vitalsRng:NextNumber(interval[1], interval[2])
				person:SetAttribute("Cough", ((person:GetAttribute("Cough") or 0) :: number) + 1)
			end
		end
	end
	-- Walkers and background people drift too
	for _, person in CollectionService:GetTagged("Walker") do
		local base = person:GetAttribute("BaseTemperature")
		if typeof(base) == "number" then
			person:SetAttribute("Temperature", wobble(person, base, t))
		end
	end
	for _, part in CollectionService:GetTagged("Heat") do
		local base = part:GetAttribute("BaseTemperature")
		if typeof(base) == "number" then
			part:SetAttribute("Temperature", wobble(part, base, t))
		end
	end
end

function Environment.init()
	WorldBuilder.get()
	HollowBuilder.get()
	Characters.settle()
	for group in Registry.floods do
		Environment.updateFlood(group)
	end
	for group in Registry.vents do
		Environment.setVent(group, false)
	end
end

function Environment.start()
	while true do
		local dt = task.wait(0.5)
		gasStep()
		residentStep(dt)
	end
end

return Environment
