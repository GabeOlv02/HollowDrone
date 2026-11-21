--!strict
-- Local-only life in the world, at full frame rate: fans spinning, faulty
-- lights flickering, fire light, aviation blinkers, sweeping Directorate
-- cameras, SOS beacon strobes, exhaust steam, the drone's own strobe and
-- sick people coughing.
-- The server only flips attributes; nothing here is replicated.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Ambience = {}

type LightState = {
	part: BasePart,
	color: Color3,
	material: Enum.Material,
	lights: { Light },
	base: { number },
	mode: string,
	seed: number,
	off: boolean,
}

local flickers: { [BasePart]: LightState } = {}
local cameras: { [Model]: { pivot: CFrame, seed: number } } = {}
local rng = Random.new()

local function track(part: Instance)
	if not part:IsA("BasePart") or flickers[part] then
		return
	end
	local lights: { Light } = {}
	local base: { number } = {}
	for _, child in part:GetChildren() do
		if child:IsA("Light") then
			table.insert(lights, child)
			table.insert(base, child.Brightness)
		end
	end
	local mode = part:GetAttribute("FlickerMode")
	flickers[part] = {
		part = part,
		color = part.Color,
		material = part.Material,
		lights = lights,
		base = base,
		mode = if typeof(mode) == "string" then mode else "Fault",
		seed = rng:NextNumber(0, 100),
		off = false,
	}
end

local function setLevel(state: LightState, level: number)
	for index, lightObject in state.lights do
		lightObject.Brightness = state.base[index] * level
	end
	local off = level < 0.15
	if off ~= state.off then
		state.off = off
		state.part.Material = if off then Enum.Material.SmoothPlastic else state.material
		state.part.Color = if off then state.color:Lerp(Color3.new(0, 0, 0), 0.7) else state.color
	end
end

local function flickerStep(t: number)
	for part, state in flickers do
		if not part.Parent then
			flickers[part] = nil
			continue
		end
		local mode = state.mode
		local level = 1
		if mode == "Fault" then
			-- mostly on, with bursts of failing starter
			local burst = math.noise(t * 0.4, state.seed) > 0.25
			if burst then
				level = if math.noise(t * 22, state.seed) > 0 then 1 else 0
			end
		elseif mode == "Pulse" then
			level = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 2.2 + state.seed))
		elseif mode == "Fire" then
			level = 0.75 + 0.25 * math.noise(t * 6, state.seed)
		elseif mode == "Blink" then
			level = if (t + state.seed) % 1.6 < 0.25 then 1 else 0.05
		elseif mode == "Rotate" then
			level = math.max(0, math.sin(t * 6 + state.seed)) ^ 2
		end
		setLevel(state, level)
	end
end

local spins: { [BasePart]: number } = {}

local function fanStep(dt: number)
	for _, fan in CollectionService:GetTagged("Fan") do
		if fan:IsA("BasePart") then
			local running = fan:GetAttribute("Running") == true
			local speed = spins[fan] or 0
			speed += ((if running then 14 else 0) - speed) * math.min(1, dt * 0.8)
			spins[fan] = speed
			if speed > 0.05 then
				fan.CFrame = fan.CFrame * CFrame.Angles(0, speed * dt, 0)
			end
		end
	end
end

local function cameraStep(t: number)
	for _, model in CollectionService:GetTagged("SweepCam") do
		if model:IsA("Model") then
			local state = cameras[model]
			if not state then
				state = { pivot = model:GetPivot(), seed = rng:NextNumber(0, 10) }
				cameras[model] = state
			end
			local angle = math.sin(t * 0.35 + state.seed) * math.rad(32)
			model:PivotTo(state.pivot * CFrame.Angles(0, angle, 0))
		end
	end
end

local function beaconStep(t: number)
	local on = t % 0.8 < 0.35
	for _, device in CollectionService:GetTagged("Device") do
		if
			device:GetAttribute("DeviceType") == "Beacon"
			and device:GetAttribute("Active") == true
		then
			local dome = device:FindFirstChild("Dome")
			if dome and dome:IsA("BasePart") then
				dome.Material = Enum.Material.Neon
				dome.Color = if on
					then Color3.fromRGB(255, 150, 40)
					else Color3.fromRGB(120, 40, 10)
				local strobe = dome:FindFirstChild("Strobe")
				if strobe and strobe:IsA("PointLight") then
					strobe.Brightness = if on then 3 else 0.3
				end
			end
		end
	end
	-- Drone anti-collision strobes: white double flash every 1.4 s; in guide
	-- mode a green pulse in time with the beep, bright enough to follow
	local phase = t % 1.4
	local flash = phase < 0.06 or (phase > 0.16 and phase < 0.22)
	for _, drone in CollectionService:GetTagged("Drone") do
		local strobe = drone:FindFirstChild("Strobe")
		local lightObject = strobe and strobe:FindFirstChild("Flash")
		if strobe and strobe:IsA("BasePart") and lightObject and lightObject:IsA("PointLight") then
			local guiding = drone:GetAttribute("Guiding")
			if typeof(guiding) == "string" and guiding ~= "" then
				local pulse = (t % 0.85) < 0.3
				lightObject.Color = Color3.fromRGB(60, 255, 120)
				lightObject.Range = 20
				lightObject.Brightness = if pulse then 5 else 0.4
				strobe.Color = Color3.fromRGB(60, 255, 120)
			else
				lightObject.Color = Color3.fromRGB(230, 230, 225)
				lightObject.Range = 9
				lightObject.Brightness = if flash then 4 else 0
				strobe.Color = Color3.fromRGB(230, 230, 225)
			end
		end
	end
end

local function steamStep()
	for _, grate in CollectionService:GetTagged("VentSteam") do
		local group = grate:GetAttribute("VentGroup")
		local running = false
		for _, fan in CollectionService:GetTagged("Fan") do
			if fan:GetAttribute("VentGroup") == group and fan:GetAttribute("Running") == true then
				running = true
				break
			end
		end
		local emitter = grate:FindFirstChild("Exhaust")
		if emitter and emitter:IsA("ParticleEmitter") then
			emitter.Rate = if running then 22 else 2
			emitter.Speed = if running then NumberRange.new(12, 18) else NumberRange.new(3, 5)
		end
	end
end

-- Coughing: the server bumps a "Cough" counter on sick people; here each
-- cough is a sharp forward jerk of chest and head (on top of whatever
-- animation is playing), a puff of breath and, if configured, a sound.
local function joint(model: Model, part: string, name: string): Motor6D?
	local holder = model:FindFirstChild(part)
	local motor = holder and holder:FindFirstChild(name)
	return if motor and motor:IsA("Motor6D") then motor else nil
end

local function puff(head: BasePart)
	local emitter = head:FindFirstChild("CoughPuff") :: ParticleEmitter?
	if not emitter then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Mouth"
		attachment.Position = Vector3.new(0, -0.25, -0.6)
		attachment.Parent = head
		local made = Instance.new("ParticleEmitter")
		made.Name = "CoughPuff"
		made.Texture = "rbxasset://textures/particles/smoke_main.dds"
		made.Color = ColorSequence.new(Color3.fromRGB(225, 225, 220))
		made.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		})
		made.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 0.9),
		})
		made.Lifetime = NumberRange.new(0.5, 0.9)
		made.Speed = NumberRange.new(2, 4)
		made.SpreadAngle = Vector2.new(18, 18)
		made.EmissionDirection = Enum.NormalId.Front
		made.Drag = 4
		made.Rate = 0
		made.LightInfluence = 1
		made.Parent = attachment
		emitter = made
	end
	(emitter :: ParticleEmitter):Emit(5)
end

local restC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function cough(model: Model)
	local waist = joint(model, "UpperTorso", "Waist")
	local neck = joint(model, "Head", "Neck")
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		puff(head)
		local id = Config.COUGH_SOUND
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = id
			sound.Volume = 0.7
			sound.PlaybackSpeed = rng:NextNumber(0.9, 1.1)
			sound.RollOffMinDistance = 4
			sound.RollOffMaxDistance = 45
			sound.Parent = head
			sound:Play()
			sound.Ended:Once(function()
				sound:Destroy()
			end)
		end
	end
	local motors: { { motor: Motor6D, base: CFrame, angle: number } } = {}
	local function add(motor: Motor6D?, angle: number)
		if motor then
			restC0[motor] = restC0[motor] or motor.C0
			table.insert(motors, { motor = motor, base = restC0[motor], angle = angle })
		end
	end
	add(waist, 0.32)
	add(neck, 0.38)
	task.spawn(function()
		-- two quick hacks, then settle
		for _, bout in { 1, 0.7 } do
			for _, entry in motors do
				entry.motor.C0 = entry.base * CFrame.Angles(-entry.angle * bout, 0, 0)
			end
			task.wait(0.09)
			for _, entry in motors do
				entry.motor.C0 = entry.base * CFrame.Angles(-entry.angle * bout * 0.3, 0, 0)
			end
			task.wait(0.14)
		end
		for _, entry in motors do
			entry.motor.C0 = entry.base
		end
	end)
end

local coughHooks: { [Instance]: boolean } = {}
local function hookCough(model: Instance)
	if coughHooks[model] or not model:IsA("Model") then
		return
	end
	coughHooks[model] = true
	model:GetAttributeChangedSignal("Cough"):Connect(function()
		cough(model)
	end)
end

function Ambience.start()
	for _, model in CollectionService:GetTagged("NPC") do
		hookCough(model)
	end
	CollectionService:GetInstanceAddedSignal("NPC"):Connect(hookCough)
	for _, part in CollectionService:GetTagged("Flicker") do
		track(part)
	end
	CollectionService:GetInstanceAddedSignal("Flicker"):Connect(track)

	local slow = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local t = os.clock()
		flickerStep(t)
		fanStep(dt)
		cameraStep(t)
		beaconStep(t)
		slow += dt
		if slow > 0.5 then
			slow = 0
			steamStep()
		end
	end)
end

return Ambience
