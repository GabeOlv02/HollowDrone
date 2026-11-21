--!strict
-- Flight, camera, targeting and input.
--
-- Physics: the drone hull is owned by this client. We steer it with two
-- constraints the server created: LinearVelocity ("Thrust") for 6DOF
-- translation and AlignOrientation ("Gyro") for attitude.
--
-- Flight model (an inspection quad, not an arcade ship):
--   * the sticks command a velocity; the motors can only deliver MAX_ACCEL,
--     so the airframe has inertia, overshoot and a braking distance
--   * attitude follows ACCELERATION (a real quad tilts to accelerate)
--   * wind fields from running fans, the lift-shaft draft and surface gusts
--   * turbulence + propwash near walls, ground effect near the floor
--   * six proximity sensors, with gentle obstacle braking (like APAS)
--   * a 6S battery: voltage sags under load, current scales with thrust
-- Camera: first-person through the nose lens on a 3-axis gimbal that holds
-- the horizon, with a little motor vibration and turbulence bleed-through.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Devices = require(ReplicatedStorage.Shared.Util.Devices)
local Link = require(ReplicatedStorage.Shared.Util.Link)
local Sites = require(ReplicatedStorage.Shared.Util.Sites)
local DroneState = require(script.Parent.Parent.DroneState)
local Net = require(script.Parent.Parent.Net)

local DRONE = Config.DRONE

local Pilot = {}

local yaw = 0
local pitch = 0
local roll = 0
local velocity = Vector3.zero
local acceleration = Vector3.zero
local fov = DRONE.FOV
local clock = 0
local gimbal = CFrame.identity

type Axes = { lx: number, ly: number, rx: number, ry: number, lt: number, rt: number }
local axes: Axes = { lx = 0, ly = 0, rx = 0, ry = 0, lt = 0, rt = 0 }

-- Rotor animation: base C0 per weld
local rotorBase: { [Weld]: CFrame } = {}
local rotorAngle = 0

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

local function deadzone(x: number, y: number): (number, number)
	local magnitude = math.sqrt(x * x + y * y)
	if magnitude < 0.15 then
		return 0, 0
	end
	local scale = math.min(1, (magnitude - 0.15) / 0.85) / magnitude
	return x * scale, y * scale
end

local function readGamepad()
	axes.lx, axes.ly, axes.rx, axes.ry, axes.lt, axes.rt = 0, 0, 0, 0, 0, 0
	if not UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		return
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		local code = input.KeyCode
		if code == Enum.KeyCode.Thumbstick1 then
			axes.lx, axes.ly = deadzone(input.Position.X, input.Position.Y)
		elseif code == Enum.KeyCode.Thumbstick2 then
			axes.rx, axes.ry = deadzone(input.Position.X, input.Position.Y)
		elseif code == Enum.KeyCode.ButtonL2 then
			axes.lt = input.Position.Z
		elseif code == Enum.KeyCode.ButtonR2 then
			axes.rt = input.Position.Z
		end
	end
end

local function down(code: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(code)
end

-- Returns the requested local-space move (x = strafe, z = forward is -Z) and vertical (-1..1).
local function blocked(): boolean
	return DroneState.menuOpen or DroneState.siteMenuOpen or DroneState.cinematic
end

local function flightInput(): (Vector3, number)
	if blocked() then
		return Vector3.zero, 0
	end
	local strafe, forward, vertical = axes.lx, axes.ly, axes.rt - axes.lt
	if down(Enum.KeyCode.W) then
		forward += 1
	end
	if down(Enum.KeyCode.S) then
		forward -= 1
	end
	if down(Enum.KeyCode.D) then
		strafe += 1
	end
	if down(Enum.KeyCode.A) then
		strafe -= 1
	end
	if down(Enum.KeyCode.Space) or down(Enum.KeyCode.E) then
		vertical += 1
	end
	if down(Enum.KeyCode.LeftControl) or down(Enum.KeyCode.Q) then
		vertical -= 1
	end
	local move = Vector3.new(math.clamp(strafe, -1, 1), 0, -math.clamp(forward, -1, 1))
	if move.Magnitude > 1 then
		move = move.Unit
	end
	return move, math.clamp(vertical, -1, 1)
end

local function look(dt: number)
	if blocked() then
		return
	end
	local dx = -axes.rx * DRONE.LOOK_SPEED_GAMEPAD * dt
	local dy = axes.ry * DRONE.LOOK_SPEED_GAMEPAD * 0.8 * dt
	local mouse = UserInputService:GetMouseDelta()
	dx -= mouse.X * DRONE.MOUSE_SENSITIVITY
	dy -= mouse.Y * DRONE.MOUSE_SENSITIVITY
	yaw = (yaw + dx) % (math.pi * 2)
	pitch = math.clamp(pitch + dy, -DRONE.MAX_PITCH, DRONE.MAX_PITCH)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function act(kind: string)
	if blocked() or not DroneState.drone then
		return
	end
	local target = if DroneState.targetInRange then DroneState.target else nil
	Net.fire("DroneAction", kind, DroneState.activeHardpoint, target)
end

local function onBegin(callback: () -> ())
	return function(
		_: string,
		state: Enum.UserInputState,
		_input: InputObject
	): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			callback()
		end
		return Enum.ContextActionResult.Sink
	end
end

local function command(name: string, ...: any)
	DroneState.Command.fire(name, ...)
end

local function menuOr(direction: string, otherwise: () -> ())
	return function()
		if DroneState.menuOpen or DroneState.siteMenuOpen then
			command("MenuNav", direction)
		else
			otherwise()
		end
	end
end

local function bindInputs()
	local bind = function(name: string, callback: () -> (), ...: any)
		ContextActionService:BindAction(name, onBegin(callback), false, ...)
	end

	bind("DronePrimary", function()
		if DroneState.menuOpen or DroneState.siteMenuOpen then
			command("MenuConfirm")
		else
			act("Primary")
		end
	end, Enum.KeyCode.ButtonA, Enum.UserInputType.MouseButton1, Enum.KeyCode.R)

	bind("DroneSecondary", function()
		if DroneState.menuOpen or DroneState.siteMenuOpen then
			command("MenuBack")
		else
			act("Secondary")
		end
	end, Enum.KeyCode.ButtonB, Enum.UserInputType.MouseButton2, Enum.KeyCode.G)

	bind("DroneSwitch", function()
		if not DroneState.menuOpen then
			DroneState.set(
				"activeHardpoint",
				if DroneState.activeHardpoint == "A" then "B" else "A"
			)
		end
	end, Enum.KeyCode.ButtonX, Enum.KeyCode.X, Enum.KeyCode.Tab)

	bind("DroneScan", function()
		command("Scan")
	end, Enum.KeyCode.ButtonR1, Enum.KeyCode.F)

	bind("DroneCamera", function()
		command("CycleCamera")
	end, Enum.KeyCode.ButtonL1, Enum.KeyCode.C)

	bind("DroneMenu", function()
		command("ToggleMenu")
	end, Enum.KeyCode.ButtonY, Enum.KeyCode.T)

	bind(
		"DroneLights",
		menuOr("Up", function()
			DroneState.set("headlights", not DroneState.headlights)
		end),
		Enum.KeyCode.DPadUp,
		Enum.KeyCode.L
	)

	bind(
		"DroneLog",
		menuOr("Down", function()
			DroneState.set("logOpen", not DroneState.logOpen)
		end),
		Enum.KeyCode.DPadDown,
		Enum.KeyCode.J
	)

	bind(
		"DroneHelp",
		menuOr("Left", function()
			DroneState.set("helpOpen", not DroneState.helpOpen)
		end),
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.H
	)

	bind("DroneRight", menuOr("Right", function() end), Enum.KeyCode.DPadRight)

	bind("DroneRecenter", function()
		pitch = 0
	end, Enum.KeyCode.ButtonR3, Enum.KeyCode.V)

	bind("DroneSites", function()
		command("ToggleSites")
	end, Enum.KeyCode.ButtonSelect, Enum.KeyCode.M)

	-- Keyboard menu navigation
	for code, direction in
		{
			[Enum.KeyCode.Up] = "Up",
			[Enum.KeyCode.Down] = "Down",
			[Enum.KeyCode.Left] = "Left",
			[Enum.KeyCode.Right] = "Right",
		}
	do
		bind("MenuArrow" .. direction, function()
			if DroneState.menuOpen or DroneState.siteMenuOpen then
				command("MenuNav", direction)
			end
		end, code)
	end
	bind("MenuEnter", function()
		if DroneState.menuOpen or DroneState.siteMenuOpen then
			command("MenuConfirm")
		end
	end, Enum.KeyCode.Return)

	-- Boost is held, not toggled
	ContextActionService:BindAction(
		"DroneBoost",
		function(_: string, state: Enum.UserInputState, _input: InputObject)
			DroneState.set(
				"boosting",
				state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
			)
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.KeyCode.ButtonL3,
		Enum.KeyCode.LeftShift
	)

	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local isPad = inputType.Name:sub(1, 7) == "Gamepad"
		local isKeyboard = inputType == Enum.UserInputType.Keyboard
			or inputType == Enum.UserInputType.MouseMovement
			or inputType == Enum.UserInputType.MouseButton1
		if isPad then
			DroneState.set("gamepad", true)
		elseif isKeyboard then
			DroneState.set("gamepad", false)
		end
	end)
	DroneState.set("gamepad", UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1))
end

---------------------------------------------------------------------------
-- Sensing
---------------------------------------------------------------------------

local function updateTarget(hull: BasePart, camera: Camera)
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * 60
	local exclude: { Instance } = { Workspace:FindFirstChild("Drones") or hull }
	for _ = 1, 4 do
		raycastParams.FilterDescendantsInstances = exclude
		local hit = Workspace:Raycast(origin, direction, raycastParams)
		if not hit then
			break
		end
		if hit.Instance:GetAttribute("Carried") == true then
			table.insert(exclude, hit.Instance)
		else
			local root = Devices.root(hit.Instance)
			if root then
				local distance = (Devices.position(root) - hull.Position).Magnitude
				DroneState.target = root
				DroneState.targetDistance = distance
				DroneState.targetInRange = distance <= DRONE.INTERACT_RANGE + Devices.extent(root)
				return
			end
			break
		end
	end
	DroneState.target = nil
	DroneState.targetDistance = math.huge
	DroneState.targetInRange = false
end

local sensorParams = RaycastParams.new()
sensorParams.FilterType = Enum.RaycastFilterType.Exclude
sensorParams.RespectCanCollide = true

-- Six time-of-flight proximity sensors in the heading frame, plus AGL.
local function sense(hull: BasePart)
	local exclude: { Instance } = { Workspace:FindFirstChild("Drones") or hull }
	local held = DroneState.drone and DroneState.drone:GetAttribute("Holding") == true
	if held then
		for _, part in Workspace:GetPartBoundsInRadius(hull.Position, 4) do
			if part:GetAttribute("Carried") == true then
				table.insert(exclude, part)
			end
		end
	end
	sensorParams.FilterDescendantsInstances = exclude
	local heading = CFrame.Angles(0, yaw, 0)
	local range = DRONE.OBSTACLE_RANGE
	local directions: { [string]: Vector3 } = {
		front = heading.LookVector,
		back = -heading.LookVector,
		left = -heading.RightVector,
		right = heading.RightVector,
		up = Vector3.yAxis,
	}
	local obstacles = DroneState.obstacles :: any
	for name, direction in directions do
		local hit = Workspace:Raycast(hull.Position, direction * range, sensorParams)
		obstacles[name] = if hit then math.max(0, hit.Distance - 1.4) else math.huge
	end
	local ground = Workspace:Raycast(hull.Position, Vector3.new(0, -400, 0), sensorParams)
	DroneState.agl = if ground then math.max(0, ground.Distance - 0.6) else 400
	obstacles.down = if ground and ground.Distance < range
		then math.max(0, ground.Distance - 0.6)
		else math.huge
end

-- Wind from running fans (pulled along the fan axis), the lift-shaft draft
-- and surface gusts. Returns studs/s.
local function windAt(position: Vector3, t: number): Vector3
	local wind = Vector3.zero
	for _, fan in CollectionService:GetTagged("Fan") do
		if
			fan:IsA("BasePart")
			and fan:GetAttribute("Running") == true
			and fan:GetAttribute("VentGroup") ~= "Wind"
		then
			local offset = position - fan.Position
			local reach = math.max(fan.Size.X, fan.Size.Z) * 1.6
			if offset.Magnitude < reach then
				local strength = (1 - offset.Magnitude / reach) * 14
				wind += fan.CFrame.UpVector * strength
			end
		end
	end
	local site = Config.SITES.Hollow
	local localPos = position - site.origin
	if
		localPos.Y > 240
		and localPos.Y < 430
		and math.abs(localPos.X) < 14
		and math.abs(localPos.Z) < 14
	then
		-- cool surface air sinking down Shaft Zero
		wind += Vector3.new(0, -2.2, 0) + Vector3.new(
			math.noise(t * 0.3, 1),
			0,
			math.noise(t * 0.3, 2)
		) * 1.5
	elseif localPos.Y >= 430 and position.Z > 1500 then
		local gust = 0.6 + 0.4 * math.noise(t * 0.15, 7)
		wind += Vector3.new(7, 0, 2.5) * gust
	end
	return wind
end

local function slowUpdate(hull: BasePart)
	DroneState.set("link", Link.at(hull.Position))
	DroneState.set("site", Sites.at(hull.Position))
	local docked = false
	for _, dock in CollectionService:GetTagged("Device") do
		if dock:GetAttribute("DeviceType") == "Dock" then
			if (Devices.position(dock) - hull.Position).Magnitude <= DRONE.DOCK_RANGE then
				docked = true
				break
			end
		end
	end
	DroneState.set("docked", docked)
end

local function spinRotors(dt: number, throttle: number)
	rotorAngle += dt * (38 + throttle * 34)
	for _, model in CollectionService:GetTagged("Drone") do
		for _, blade in model:GetChildren() do
			if blade.Name == "Rotor" then
				local weld = blade:FindFirstChild("RotorWeld")
				if weld and weld:IsA("Weld") then
					local base = rotorBase[weld]
					if not base then
						base = weld.C0
						rotorBase[weld] = base
					end
					local spin = blade:GetAttribute("Spin")
					local direction = if typeof(spin) == "number" then spin else 1
					weld.C0 = base * CFrame.Angles(0, rotorAngle * direction, 0)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Flight model
---------------------------------------------------------------------------

-- Limits the commanded velocity toward close obstacles (soft braking).
local function avoid(desired: Vector3): Vector3
	local heading = CFrame.Angles(0, yaw, 0)
	local o = DroneState.obstacles
	local localDesired = heading:VectorToObjectSpace(desired)
	local avoiding = false
	local function limit(component: number, distance: number, positive: boolean): number
		local toward = if positive then component > 0 else component < 0
		if toward and distance < 4 then
			avoiding = true
			local cap = math.max(0, (distance - 0.6) * 2.5)
			return math.clamp(component, -cap, cap)
		end
		return component
	end
	local x = limit(localDesired.X, o.right, true)
	x = limit(x, o.left, false)
	local z = limit(localDesired.Z, o.back, true)
	z = limit(z, o.front, false)
	local y = limit(desired.Y, o.up, true)
	y = limit(y, o.down, false)
	DroneState.avoiding = avoiding
	return heading:VectorToWorldSpace(Vector3.new(x, 0, z)) + Vector3.new(0, y, 0)
end

local function fly(dt: number, hull: BasePart, thrust: LinearVelocity, gyro: AlignOrientation)
	clock += dt
	readGamepad()
	look(dt)

	local move, vertical = flightInput()
	local lowPower = DroneState.battery <= 0
	local boost = DroneState.boosting and not lowPower
	local speed = if lowPower
		then DRONE.LOW_POWER_SPEED
		elseif boost then DRONE.BOOST_SPEED
		else DRONE.SPEED
	-- Voltage sag trims the top speed on a tired pack
	speed *= 0.82 + 0.18 * math.clamp(DroneState.battery / 40, 0, 1)
	local heading = CFrame.Angles(0, yaw, 0)
	local desired = heading:VectorToWorldSpace(move) * speed
		+ Vector3.new(
			0,
			vertical * (if lowPower then DRONE.LOW_POWER_SPEED else DRONE.VERTICAL_SPEED),
			0
		)
	desired = avoid(desired)

	-- Velocity controller with limited authority (inertia + braking distance)
	local sticks = move.Magnitude + math.abs(vertical)
	local gain = if sticks > 0.05 then 3.2 else DRONE.BRAKE
	local wanted = (desired - velocity) * gain
	local maxAccel = DRONE.MAX_ACCEL * (if boost then 1.35 else 1)
	if wanted.Magnitude > maxAccel then
		wanted = wanted.Unit * maxAccel
	end
	acceleration = acceleration:Lerp(wanted, math.min(1, dt * 12))
	velocity += acceleration * dt
	velocity -= velocity * DRONE.DRAG * 0.08 * dt

	-- Disturbances: wind, turbulence, propwash near surfaces, ground effect
	local wind = windAt(hull.Position, clock)
	DroneState.wind = wind
	local o = DroneState.obstacles
	local nearest = math.min(o.front, o.back, o.left, o.right, o.up, DroneState.agl)
	local wash = math.clamp(1 - nearest / 6, 0, 1)
	local t = clock * 1.7
	local turbulence = Vector3.new(
		math.noise(t, 0.1, 3.3),
		math.noise(t, 5.2, 1.1) * 0.6,
		math.noise(t, 9.7, 4.4)
	) * (DRONE.TURBULENCE + wash * DRONE.PROPWASH + wind.Magnitude * 0.12)
	local groundEffect = 0
	if DroneState.agl < DRONE.GROUND_EFFECT_HEIGHT then
		groundEffect = (1 - DroneState.agl / DRONE.GROUND_EFFECT_HEIGHT) * 1.8
	end
	local applied = velocity
		+ wind * DRONE.WIND_RESPONSE
		+ turbulence
		+ Vector3.new(0, groundEffect, 0)
	thrust.VectorVelocity = applied

	-- Attitude from acceleration (plus a share of the wind the motors fight)
	local tiltSource = heading:VectorToObjectSpace(acceleration + wind * 0.8)
	local maxTilt = math.rad(28)
	local tiltPitch = math.clamp(tiltSource.Z / DRONE.MAX_ACCEL, -1, 1) * maxTilt
	roll = -math.clamp(tiltSource.X / DRONE.MAX_ACCEL, -1, 1) * maxTilt
	local wobble = CFrame.Angles(turbulence.Z * 0.012, 0, -turbulence.X * 0.012)
	gyro.CFrame = heading * CFrame.Angles(tiltPitch, 0, roll) * wobble
	DroneState.tilt = math.deg(math.sqrt(tiltPitch * tiltPitch + roll * roll))

	-- Power: hover current + thrust for acceleration and climbing
	local load = math.clamp(
		0.42
			+ acceleration.Magnitude / DRONE.MAX_ACCEL * 0.4
			+ math.max(0, velocity.Y) / DRONE.VERTICAL_SPEED * 0.25
			+ wind.Magnitude * 0.01,
		0,
		1
	)
	DroneState.throttle = load
	DroneState.current = 9 + load * 46
	local visionDrain = if DroneState.cameraMode ~= "Normal" then DRONE.BATTERY_VISION else 0
	local drain = DRONE.BATTERY_IDLE + DRONE.BATTERY_MOVE * (load - 0.42) * 2.4 + visionDrain
	local battery = if DroneState.docked
		then DroneState.battery + DRONE.BATTERY_RECHARGE * dt
		else DroneState.battery - math.max(DRONE.BATTERY_IDLE, drain) * dt
	DroneState.battery = math.clamp(battery, 0, 100)
	local rest = DRONE.CELL_EMPTY
		+ (DRONE.CELL_FULL - DRONE.CELL_EMPTY) * (DroneState.battery / 100) ^ 0.7
	DroneState.voltage = rest - DRONE.SAG * load
	DroneState.speed = hull.AssemblyLinearVelocity.Magnitude
	local planar = hull.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	DroneState.groundSpeed = planar.Magnitude
	DroneState.verticalSpeed = hull.AssemblyLinearVelocity.Y
	if not DroneState.docked then
		DroneState.flightSeconds += dt
	end

	spinRotors(dt, load)
end

function Pilot.init()
	DroneState.targetInRange = false
end

function Pilot.start()
	local drone = DroneState.waitForDrone()
	local hull = DroneState.hull :: BasePart
	local thrust = hull:WaitForChild("Thrust") :: LinearVelocity
	local gyro = hull:WaitForChild("Gyro") :: AlignOrientation
	local headlight = hull:WaitForChild("Headlight") :: SpotLight
	local camera = Workspace.CurrentCamera

	-- Start looking the way the drone was spawned
	local _, spawnYaw, _ = hull.CFrame:ToEulerAnglesYXZ()
	yaw = spawnYaw

	bindInputs()

	DroneState.Changed.connect(function(key: string)
		if key == "headlights" then
			headlight.Enabled = DroneState.headlights
		end
	end)

	-- Teleports (site change / recall): reset the controller state
	local lastPosition = hull.Position

	RunService:BindToRenderStep(
		"DroneFlight",
		Enum.RenderPriority.Input.Value + 1,
		function(dt: number)
			if not drone.Parent then
				return
			end
			if (hull.Position - lastPosition).Magnitude > 40 then
				velocity = Vector3.zero
				acceleration = Vector3.zero
				local _, newYaw, _ = hull.CFrame:ToEulerAnglesYXZ()
				yaw = newYaw
			end
			lastPosition = hull.Position
			fly(math.min(dt, 0.05), hull, thrust, gyro)
		end
	)

	-- Camera (after Roblox's camera scripts so nothing overrides us)
	RunService:BindToRenderStep(
		"DroneCamera",
		Enum.RenderPriority.Camera.Value + 1,
		function(dt: number)
			if not drone.Parent or DroneState.cinematic then
				return
			end
			camera.CameraType = Enum.CameraType.Scriptable
			local targetFov = if DroneState.boosting then DRONE.FOV + 4 else DRONE.FOV
			fov += (targetFov - fov) * math.min(1, dt * 4)
			camera.FieldOfView = fov

			-- 3-axis gimbal: slews toward the commanded look with a little lag
			local goal = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
			gimbal = gimbal:Lerp(goal, math.min(1, dt * 18))
			local vibration = CFrame.Angles(
				math.noise(clock * 40, 1) * 0.0012 * (0.5 + DroneState.throttle),
				math.noise(clock * 40, 2) * 0.0012 * (0.5 + DroneState.throttle),
				roll * 0.12 + math.noise(clock * 3, 3) * 0.004
			)
			local lens = CFrame.new(hull.Position)
				* CFrame.Angles(0, yaw, 0)
				* CFrame.new(0, 0.05, -1.45)
			camera.CFrame = CFrame.new(lens.Position) * gimbal.Rotation * vibration

			local menu = DroneState.menuOpen or DroneState.siteMenuOpen
			UserInputService.MouseBehavior = if menu
				then Enum.MouseBehavior.Default
				else Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = menu

			updateTarget(hull, camera)
		end
	)

	local sensorClock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sensorClock += dt
		if sensorClock >= 1 / 15 and drone.Parent then
			sensorClock = 0
			sense(hull)
		end
	end)

	while true do
		task.wait(0.2)
		if drone.Parent then
			slowUpdate(hull)
		end
	end
end

-- Exposed for the HUD
function Pilot.heading(): number
	return (360 - math.deg(yaw)) % 360
end

function Pilot.pitch(): number
	return math.deg(pitch)
end

function Pilot.roll(): number
	return math.deg(roll)
end

return Pilot
