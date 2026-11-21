--!strict
-- Client-side pilot state shared by every controller, plus a command bus so
-- input bindings (in Pilot) stay decoupled from the systems they trigger.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local player = Players.LocalPlayer

local DroneState = {
	drone = nil :: Model?,
	hull = nil :: BasePart?,

	activeHardpoint = "A",
	cameraMode = "Normal",
	headlights = true,
	boosting = false,
	gamepad = false,

	battery = 100,
	link = 1,
	speed = 0,
	docked = false,

	-- Flight telemetry (written by Pilot every frame)
	site = "Hollow",
	agl = 0, -- height above whatever is below (studs)
	verticalSpeed = 0,
	groundSpeed = 0,
	voltage = 25.2,
	current = 0, -- amps
	throttle = 0, -- 0..1
	wind = Vector3.zero,
	tilt = 0, -- degrees
	obstacles = {
		front = math.huge,
		back = math.huge,
		left = math.huge,
		right = math.huge,
		up = math.huge,
		down = math.huge,
	},
	avoiding = false,
	flightSeconds = 0,
	lidarPoints = 0,

	-- Intro cinematic / site picker owns the camera while true
	cinematic = true,

	-- What the reticle is on (device root) and how far away it is
	target = nil :: Instance?,
	targetDistance = math.huge,
	targetInRange = false,

	lastScanCount = 0,
	lastScanAt = -math.huge,

	menuOpen = false,
	siteMenuOpen = false,
	logOpen = true,
	helpOpen = true,

	-- fired(command: string, ...) e.g. "Scan", "CycleCamera", "ToggleMenu", "MenuNav"
	Command = Signal.new(),
	-- fired(key: string) when a state field changes through DroneState.set
	Changed = Signal.new(),
}

function DroneState.set(key: string, value: any)
	local state = DroneState :: any
	if state[key] ~= value then
		state[key] = value
		DroneState.Changed.fire(key)
	end
end

-- Module installed on a hardpoint ("A"/"B"); defaults to the active one.
function DroneState.module(hardpoint: string?): string?
	local drone = DroneState.drone
	if not drone then
		return nil
	end
	local value = drone:GetAttribute("Hardpoint" .. (hardpoint or DroneState.activeHardpoint))
	return if typeof(value) == "string" then value else nil
end

function DroneState.hasModule(module: string): boolean
	return DroneState.module("A") == module or DroneState.module("B") == module
end

-- Blocks until this pilot's drone exists, then caches it.
function DroneState.waitForDrone(): Model
	local folder = Workspace:WaitForChild("Drones")
	local drone = folder:WaitForChild("Drone_" .. player.UserId) :: Model
	local hull = drone:WaitForChild("Hull") :: BasePart
	DroneState.drone = drone
	DroneState.hull = hull
	return drone
end

return DroneState
