--!strict
-- Junction 9 test range: one hall where every drone mechanic can be shown
-- in a couple of minutes. Every interactive object is tagged "Device" with a
-- DeviceId / DeviceType / Label so the scanner can identify it and the
-- server can validate actions against it.
--
-- Top view (studs). Floor y = 0, ceiling y = 32, hall x -66..66, z -48..48.
--
--   z -48 ┌──────────────┬───────────────────────┬──────────────────────┐
--         │ WARD (sealed)│ MESH: terminal A,     │ SEWER POOL (sunken)  │
--         │ 3 patients,  │ jammer J-8 (cage),    │ valves on north wall │
--         │ visitor,     │ SOS beacon, camera    │ gas + ceiling fans   │
--         │ heater decoy │                       │ drain under debris   │
--         │ door barred ═╡      open floor       │ outflow pipes (east) │
--   z -8  ├──────────────┘                       └──────── breaker ─────┤
--         │ MEZZANINE (y 12): Ada, lost         transformer (inspect)   │
--         │                                                             │
--         │      ramp ════════>  DOCK        SHELTER: Kofi (family),    │
--   z 48  └──────────────────────────────── terminal B, MED RACK ───────┘
--        x -66                    x 0                               x 66
--
-- The med rack is in the far (south-east) corner from the ward's patients,
-- so a delivery is a real flight across the hall and through the ward door.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Characters = require(script.Parent.Parent.Characters)
local Registry = require(script.Parent.Parent.Registry)

export type Refs = {
	root: Folder,
	spawn: CFrame,
	docks: { Model },
	water: BasePart,
	sewerGas: { BasePart },
	valves: { Model },
	breaker: Model,
	fans: { BasePart },
	jammer: Model,
	beacons: { Model },
	terminals: { Model },
	residents: { Model },
}

-- Construction kit (primitives + standard devices) lives in Kit.luau
local Kit = require(script.Parent.Parent.Kit)
local newPart = Kit.newPart
local box = Kit.box
local cylinder = Kit.cylinder
local ball = Kit.ball
local decor = Kit.decor
local light = Kit.light
local lamp = Kit.lamp
local sign = Kit.sign
local facing = Kit.facing
local rect = Kit.rect
local wallX = Kit.wallX
local wallZ = Kit.wallZ
local device = Kit.device
local newModel = Kit.newModel
local buildDock = Kit.buildDock
local buildJunctionBox = Kit.buildJunctionBox
local buildCamera = Kit.buildCamera
local buildGas = Kit.buildGas
local buildDebris = Kit.buildDebris
local buildTerminal = Kit.buildTerminal
local buildBeacon = Kit.buildBeacon
local buildResident = Kit.buildResident
local buildValve = Kit.buildValve
local buildSamplePoint = Kit.buildSamplePoint

local CONCRETE = Kit.colors.CONCRETE
local CONCRETE_DARK = Kit.colors.CONCRETE_DARK
local SEWER = Kit.colors.SEWER
local METAL = Kit.colors.METAL
local METAL_DARK = Kit.colors.METAL_DARK
local HAZARD = Kit.colors.HAZARD
local CYAN = Kit.colors.CYAN
local MAGENTA = Kit.colors.MAGENTA
local RED = Kit.colors.RED
local WHITE = Kit.colors.WHITE
local GREEN = Color3.fromRGB(120, 255, 140)
local MED = Color3.fromRGB(255, 150, 180)
local LAMP = Color3.fromRGB(214, 228, 240)
local EMERGENCY = Color3.fromRGB(255, 70, 50)

-- Hall extents
local X0, X1 = -66, 66
local Z0, Z1 = -48, 48
local CEILING = 32

-- Sewer pool (sunken pit in the north-east)
local POOL = { x0 = 24, x1 = 62, z0 = -46, z1 = -12, bottom = -6 }
local WATER_HIGH = -0.6
local WATER_LOW = -5.2

-- Ward (sealed room in the north-west)
local WARD = { x0 = X0, x1 = -30, z0 = Z0, z1 = -8, roof = 14 }

-- Mezzanine (south-west), reached by a ramp along the south wall
local MEZZ = { x0 = X0, x1 = -40, z0 = 14, z1 = Z1, top = 12 }
local RAMP = { top = Vector3.new(-40, 12, 44), bottom = Vector3.new(-14, 0, 44), width = 6 }

local WorldBuilder = {}

local built: Refs? = nil

---------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------

local function volume(parent: Instance, name: string, a: Vector3, b: Vector3): Part
	local part = box(parent, name, a, b, WHITE)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function glass(parent: Instance, a: Vector3, b: Vector3)
	local pane = box(parent, "Window", a, b, Color3.fromRGB(150, 175, 190), Enum.Material.Glass)
	pane.Transparency = 0.65
	pane.CastShadow = false
end

-- Hip-height rail between two points (collidable, so nothing walks off)
local function rail(parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local bar = newPart(
		parent,
		"Rail",
		Vector3.new(0.3, 0.3, length),
		CFrame.lookAt(mid + Vector3.new(0, 3.4, 0), b + Vector3.new(0, 3.4, 0)),
		HAZARD,
		Enum.Material.Metal
	)
	bar.CastShadow = false
	local guard = newPart(
		parent,
		"RailGuard",
		Vector3.new(0.2, 3.6, length),
		CFrame.lookAt(mid + Vector3.new(0, 1.7, 0), b + Vector3.new(0, 1.7, 0)),
		METAL_DARK,
		Enum.Material.DiamondPlate
	)
	guard.Transparency = 0.55
	guard.CastShadow = false
end

local function ramp(parent: Instance, top: Vector3, bottom: Vector3, width: number)
	local length = (bottom - top).Magnitude
	local cf = CFrame.lookAt((top + bottom) / 2, bottom) * CFrame.new(0, -0.5, 0)
	newPart(
		parent,
		"Ramp",
		Vector3.new(width, 1, length),
		cf,
		METAL_DARK,
		Enum.Material.DiamondPlate
	)
	for side = -1, 1, 2 do
		local offset = Vector3.new(0, 0, side * (width / 2 - 0.2))
		rail(parent, top + offset, bottom + offset)
	end
end

-- A hospital bed. Returns the hip CFrame for a person lying in it (head
-- toward the pillow at the cframe's +Z end).
local function bed(parent: Instance, cf: CFrame, blanket: Color3): CFrame
	newPart(
		parent,
		"BedFrame",
		Vector3.new(3.4, 1.4, 7),
		cf * CFrame.new(0, 0.7, 0),
		METAL,
		Enum.Material.Metal
	)
	newPart(
		parent,
		"Mattress",
		Vector3.new(3.2, 0.6, 6.8),
		cf * CFrame.new(0, 1.7, 0),
		Color3.fromRGB(150, 146, 136),
		Enum.Material.Fabric
	)
	decor(
		newPart(
			parent,
			"Pillow",
			Vector3.new(2.2, 0.4, 1.1),
			cf * CFrame.new(0, 2.2, 2.75),
			Color3.fromRGB(196, 192, 182),
			Enum.Material.Fabric
		)
	)
	decor(
		newPart(
			parent,
			"Blanket",
			Vector3.new(3.3, 1.15, 3.4),
			cf * CFrame.new(0, 2.55, -1.75),
			blanket,
			Enum.Material.Fabric
		)
	)
	decor(
		newPart(
			parent,
			"Headboard",
			Vector3.new(3.4, 2.4, 0.3),
			cf * CFrame.new(0, 2.6, 3.4),
			METAL,
			Enum.Material.Metal
		)
	)
	return cf * CFrame.new(0, 2.4, 0.6)
end

-- A low bench seat (top at y + 0.85, sized for R15 legs so feet reach the
-- floor). Returns the hip CFrame of someone sitting on it.
local function seat(parent: Instance, cf: CFrame, width: number): CFrame
	newPart(
		parent,
		"Seat",
		Vector3.new(width, 0.4, 1.8),
		cf * CFrame.new(0, 0.65, 0),
		Color3.fromRGB(80, 64, 48),
		Enum.Material.Wood
	)
	newPart(
		parent,
		"SeatBack",
		Vector3.new(width, 2.2, 0.3),
		cf * CFrame.new(0, 1.95, 0.85),
		Color3.fromRGB(80, 64, 48),
		Enum.Material.Wood
	)
	for side = -1, 1, 2 do
		decor(
			newPart(
				parent,
				"SeatLeg",
				Vector3.new(0.3, 0.45, 1.6),
				cf * CFrame.new(side * (width / 2 - 0.3), 0.225, 0),
				METAL_DARK,
				Enum.Material.Metal
			)
		)
	end
	return cf * CFrame.new(0, 1.05, 0.05)
end

-- A person who can walk (guide mode); stands at hip CFrame `cf`
local function civilian(
	parent: Instance,
	name: string,
	cf: CFrame,
	shirt: Color3,
	attributes: { [string]: any }
): Model
	local model = Characters.spawn(
		parent,
		"Civilian",
		{ pose = "Stand", cf = cf, shirt = shirt, mobile = true }
	)
	local temperature = Characters.temperature("Healthy")
	local all: { [string]: any } =
		{ Temperature = temperature, BaseTemperature = temperature, Status = "WAITING" }
	for key, value in attributes do
		all[key] = value
	end
	device(model, "Civilian", name, all)
	CollectionService:AddTag(model, "Walker")
	return model
end

-- Background person: warm on thermal, nothing to interact with
local function bystander(parent: Instance, cf: CFrame, pose: string, shirt: Color3)
	local model = Characters.spawn(parent, "Bystander", { pose = pose, cf = cf, shirt = shirt })
	local chest = Characters.chest(model)
	local temperature = Characters.temperature("Healthy")
	chest:SetAttribute("Temperature", temperature)
	chest:SetAttribute("BaseTemperature", temperature)
	CollectionService:AddTag(chest, "Heat")
end

-- Wall-mounted ventilation breaker facing `normal`
local function buildBreaker(parent: Instance, refs: Refs, position: Vector3, normal: Vector3)
	local breaker = newModel(parent, "Breaker")
	local cf = CFrame.lookAt(position, position + normal)
	local panel =
		newPart(breaker, "Panel", Vector3.new(3, 4, 0.6), cf, METAL_DARK, Enum.Material.Metal)
	newPart(
		breaker,
		"Lever",
		Vector3.new(0.4, 1.6, 0.6),
		cf * CFrame.new(0, -0.6, -0.6),
		HAZARD,
		Enum.Material.Metal
	)
	local status = decor(
		ball(
			breaker,
			"StatusLamp",
			0.6,
			(cf * CFrame.new(1, 1.4, -0.4)).Position,
			RED,
			Enum.Material.Neon
		)
	)
	light(status, RED, 6, 1)
	breaker.PrimaryPart = panel
	device(
		breaker,
		"Breaker",
		"Pool ventilation fans (breaker V-1)",
		{ On = false, Status = "OFF" }
	)
	refs.breaker = breaker
end

---------------------------------------------------------------------------
-- Shell: floor, walls, ceiling, lights
---------------------------------------------------------------------------

local function buildShell(parent: Instance)
	-- Floor around the sunken pool
	box(
		parent,
		"Floor",
		Vector3.new(X0, -1, Z0),
		Vector3.new(POOL.x0, 0, Z1),
		CONCRETE,
		Enum.Material.Concrete
	)
	box(
		parent,
		"Floor",
		Vector3.new(POOL.x0, -1, POOL.z1),
		Vector3.new(X1, 0, Z1),
		CONCRETE,
		Enum.Material.Concrete
	)
	box(
		parent,
		"Floor",
		Vector3.new(POOL.x1, -1, Z0),
		Vector3.new(X1, 0, POOL.z1),
		CONCRETE,
		Enum.Material.Concrete
	)
	box(
		parent,
		"Floor",
		Vector3.new(POOL.x0, -1, Z0),
		Vector3.new(POOL.x1, 0, POOL.z0),
		CONCRETE,
		Enum.Material.Concrete
	)
	box(
		parent,
		"Ceiling",
		Vector3.new(X0 - 1, CEILING, Z0 - 1),
		Vector3.new(X1 + 1, CEILING + 1, Z1 + 1),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	wallX(parent, X0 - 0.5, Z0 - 1, Z1 + 1, -1, CEILING, {}, CONCRETE, Enum.Material.Concrete)
	wallX(parent, X1 + 0.5, Z0 - 1, Z1 + 1, -7, CEILING, {}, CONCRETE, Enum.Material.Concrete)
	wallZ(parent, Z0 - 0.5, X0 - 1, X1 + 1, -7, CEILING, {}, CONCRETE, Enum.Material.Concrete)
	wallZ(parent, Z1 + 0.5, X0 - 1, X1 + 1, -1, CEILING, {}, CONCRETE, Enum.Material.Concrete)

	-- Ceiling lights (the ward is left dark: it's the blackout block)
	for _, x in { -14, 14, 42 } do
		for _, z in { -28, 2, 32 } do
			lamp(parent, Vector3.new(x, CEILING - 0.4, z), LAMP, 46, 0.9)
		end
	end
	lamp(parent, Vector3.new(-52, CEILING - 0.4, 30), LAMP, 40, 0.7)

	-- Floor lane markings
	for z = -4, 44, 8 do
		decor(
			box(
				parent,
				"Stripe",
				Vector3.new(-0.2, 0, z),
				Vector3.new(0.2, 0.06, z + 4),
				HAZARD,
				Enum.Material.Neon
			)
		)
	end

	sign(
		parent,
		facing(Vector3.new(0, 26, Z1 - 0.2), Vector3.new(0, 26, 0)),
		Vector2.new(34, 4),
		"JUNCTION 9 // DRONE TEST RANGE",
		CYAN
	)
	sign(
		parent,
		facing(Vector3.new(0, 22.5, Z1 - 0.2), Vector3.new(0, 22.5, 0)),
		Vector2.new(34, 2),
		"Every mechanic in one hall  ·  [Log] for the checklist",
		Color3.fromRGB(200, 200, 200),
		Enum.Font.Code
	)
end

---------------------------------------------------------------------------
-- South: dock + module racks
---------------------------------------------------------------------------

local function buildDockArea(parent: Instance, refs: Refs)
	buildDock(parent, refs, "Range Dock R-0", Vector3.new(0, 0, 36))
	refs.spawn = CFrame.lookAt(Vector3.new(0, 3, 36), Vector3.new(0, 3, 0))
	for index, module in Config.MODULE_ORDER do
		local x = -14 + index * 6
		box(
			parent,
			"Rack",
			Vector3.new(x - 2.4, 0, 44.5),
			Vector3.new(x + 2.4, 4, 47.5),
			METAL_DARK,
			Enum.Material.Metal
		)
		decor(
			box(
				parent,
				"RackGlow",
				Vector3.new(x - 2.4, 4, 44.5),
				Vector3.new(x + 2.4, 4.3, 44.7),
				Config.MODULES[module].color,
				Enum.Material.Neon
			)
		)
		sign(
			parent,
			facing(Vector3.new(x, 6, 47.8), Vector3.new(x, 6, 0)),
			Vector2.new(5, 1.2),
			Config.MODULES[module].label,
			Config.MODULES[module].color,
			Enum.Font.Code
		)
	end
	buildJunctionBox(parent, Vector3.new(18, 5, Z1 - 0.6), Vector3.new(0, 0, -1), "Dock power feed")
end

---------------------------------------------------------------------------
-- North-east: sewer pool (water samples, valves, drain, gas, fans)
---------------------------------------------------------------------------

local function buildPool(parent: Instance, refs: Refs)
	-- Pit
	box(
		parent,
		"PoolBottom",
		Vector3.new(POOL.x0, POOL.bottom - 1, POOL.z0),
		Vector3.new(POOL.x1, POOL.bottom, POOL.z1),
		SEWER,
		Enum.Material.Slate
	)
	box(
		parent,
		"PoolWall",
		Vector3.new(POOL.x0 - 1, POOL.bottom - 1, POOL.z0),
		Vector3.new(POOL.x0, 0, POOL.z1),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	box(
		parent,
		"PoolWall",
		Vector3.new(POOL.x1, POOL.bottom - 1, POOL.z0),
		Vector3.new(POOL.x1 + 1, 0, POOL.z1),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	box(
		parent,
		"PoolWall",
		Vector3.new(POOL.x0, POOL.bottom - 1, POOL.z0 - 1),
		Vector3.new(POOL.x1, 0, POOL.z0),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	box(
		parent,
		"PoolWall",
		Vector3.new(POOL.x0, POOL.bottom - 1, POOL.z1),
		Vector3.new(POOL.x1, 0, POOL.z1 + 1),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	-- Hazard edge + rails on the open sides
	decor(
		box(
			parent,
			"Edge",
			Vector3.new(POOL.x0 - 1, 0, POOL.z1),
			Vector3.new(POOL.x1 + 1, 0.06, POOL.z1 + 1),
			HAZARD,
			Enum.Material.SmoothPlastic
		)
	)
	decor(
		box(
			parent,
			"Edge",
			Vector3.new(POOL.x0 - 1, 0, POOL.z0),
			Vector3.new(POOL.x0, 0.06, POOL.z1),
			HAZARD,
			Enum.Material.SmoothPlastic
		)
	)
	rail(
		parent,
		Vector3.new(POOL.x0 - 0.5, 0, POOL.z1 + 0.5),
		Vector3.new(POOL.x1, 0, POOL.z1 + 0.5)
	)
	rail(
		parent,
		Vector3.new(POOL.x0 - 0.5, 0, POOL.z0),
		Vector3.new(POOL.x0 - 0.5, 0, POOL.z1 + 0.5)
	)

	-- Inflow culvert (north wall) and the drain grate (pit floor, east end)
	decor(
		cylinder(
			parent,
			"Culvert",
			1,
			5,
			Vector3.new(30, -2.5, Z0 + 0.1),
			"Z",
			Color3.fromRGB(20, 22, 20),
			Enum.Material.Metal
		)
	)
	decor(
		box(
			parent,
			"DrainGrate",
			Vector3.new(56, POOL.bottom, -31),
			Vector3.new(60, POOL.bottom + 0.15, -27),
			Color3.fromRGB(26, 26, 26),
			Enum.Material.DiamondPlate
		)
	)
	buildDebris(
		parent,
		Vector3.new(57.2, POOL.bottom + 0.9, -29.6),
		Vector3.new(2.2, 1.8, 2),
		"RDrain",
		"Collapsed brick"
	)
	buildDebris(
		parent,
		Vector3.new(58.6, POOL.bottom + 0.8, -27.8),
		Vector3.new(2, 1.6, 2.4),
		"RDrain",
		"Waste sack"
	)

	-- Flood control valves on the north wall
	buildValve(
		parent,
		refs,
		Vector3.new(36, 5, Z0 + 1.2),
		1,
		"Drain gate D-1 (open to drain the pool)",
		true,
		false
	)
	buildValve(
		parent,
		refs,
		Vector3.new(48, 5, Z0 + 1.2),
		1,
		"Inflow gate IN-2 (close to stop the inflow)",
		false,
		true
	)
	sign(
		parent,
		facing(Vector3.new(42, 10.5, Z0 + 0.2), Vector3.new(42, 10.5, 0)),
		Vector2.new(22, 1.6),
		"SEWER POOL S-3 // FLOOD CONTROL",
		HAZARD,
		Enum.Font.Code
	)

	-- Outflow pipes on the east wall
	buildSamplePoint(
		parent,
		Vector3.new(X1 - 0.6, 2.5, -38),
		Vector3.new(-1, 0, 0),
		"Outflow 1 (residential L8)",
		{
			Contaminated = true,
			PH = 6.1,
			Coliform = 2400,
			Lead = 4,
		}
	)
	buildSamplePoint(
		parent,
		Vector3.new(X1 - 0.6, 2.5, -20),
		Vector3.new(-1, 0, 0),
		"Outflow 2 (recycler return)",
		{
			Contaminated = false,
			PH = 7.2,
			Coliform = 0,
			Lead = 2,
		}
	)

	-- Toxic gas over the water (invisible except in CHEM vision)
	buildGas(parent, refs, "H2S", Vector3.new(42, 1.5, -29), 11, 170, "Sewer")
	buildGas(parent, refs, "CH4", Vector3.new(54, 2.5, -40), 7, 40, "Sewer")

	-- Ceiling fans over the pool, on breaker V-1 (east wall)
	refs.fans = {}
	for _, x in { 34, 50 } do
		decor(
			cylinder(
				parent,
				"FanHousing",
				1,
				7,
				Vector3.new(x, CEILING - 0.7, -29),
				"Y",
				METAL_DARK,
				Enum.Material.Metal
			)
		)
		local blades = newPart(
			parent,
			"FanBlades",
			Vector3.new(6, 0.2, 1),
			CFrame.new(x, CEILING - 1.4, -29),
			METAL,
			Enum.Material.Metal
		)
		decor(blades)
		table.insert(refs.fans, blades)
	end
	buildBreaker(parent, refs, Vector3.new(X1 - 0.3, 5, -6), Vector3.new(-1, 0, 0))
	sign(
		parent,
		facing(Vector3.new(X1 - 0.2, 8.4, -6), Vector3.new(0, 8.4, -6)),
		Vector2.new(6, 1),
		"VENT BREAKER V-1",
		HAZARD,
		Enum.Font.Code
	)

	-- Water (level driven by the Environment system)
	local water = box(
		parent,
		"PoolWater",
		Vector3.new(POOL.x0, POOL.bottom, POOL.z0),
		Vector3.new(POOL.x1, WATER_HIGH, POOL.z1),
		Color3.fromRGB(55, 70, 40),
		Enum.Material.Glass
	)
	water.Transparency = 0.35
	decor(water)
	refs.water = water
end

---------------------------------------------------------------------------
-- East: plant equipment (early warning)
---------------------------------------------------------------------------

local function buildTransformer(parent: Instance)
	local model = newModel(parent, "Transformer")
	local body = box(
		model,
		"Body",
		Vector3.new(54, 0, 2),
		Vector3.new(60, 7, 8),
		Color3.fromRGB(70, 78, 70),
		Enum.Material.Metal
	)
	for i = 0, 5 do
		decor(
			box(
				model,
				"Fin",
				Vector3.new(53.4, 1, 2.6 + i),
				Vector3.new(54, 6, 2.8 + i),
				METAL_DARK,
				Enum.Material.Metal
			)
		)
	end
	for _, z in { 3.5, 5, 6.5 } do
		decor(
			cylinder(
				model,
				"Bushing",
				2,
				0.6,
				Vector3.new(57, 8, z),
				"Y",
				Color3.fromRGB(150, 110, 80),
				Enum.Material.Granite
			)
		)
	end
	sign(
		model,
		facing(Vector3.new(53.1, 5, 5), Vector3.new(0, 5, 5)),
		Vector2.new(4.5, 1),
		"TX-4  11kV",
		HAZARD,
		Enum.Font.Code
	)
	model.PrimaryPart = body
	device(model, "Equipment", "Transformer TX-4 (feeds the ward)", {
		Temperature = 96,
		Diagnostic = "Oil 205°F / 96°C (limit 221°F / 105°C), rising 2.5°F / 1.4°C per day. Cooling fins clogged.\nFORECAST: thermal trip in ~6 days → ward blackout.\nACTION: clean fins, shed 18% load tonight.",
		Verdict = "TRIP IN ~6 DAYS",
		Severity = "danger",
		Objective = "RInspect",
		Status = "NOT SURVEYED",
	})
end

---------------------------------------------------------------------------
-- North: mesh network (jammer, terminal A, beacon)
---------------------------------------------------------------------------

local function buildMesh(parent: Instance, refs: Refs)
	-- Jammer J-8 in a mesh cage against the north wall
	local jammer = newModel(parent, "Jammer")
	local body = newPart(
		jammer,
		"Body",
		Vector3.new(3.4, 5, 2),
		CFrame.new(4, 2.5, Z0 + 2),
		Color3.fromRGB(30, 28, 34),
		Enum.Material.Metal
	)
	for _, x in { 3, 5 } do
		decor(
			cylinder(
				jammer,
				"Antenna",
				6,
				0.3,
				Vector3.new(x, 8, Z0 + 2),
				"Y",
				METAL,
				Enum.Material.Metal
			)
		)
	end
	local strip = decor(
		newPart(
			jammer,
			"Glow",
			Vector3.new(3, 0.3, 0.2),
			CFrame.new(4, 4.2, Z0 + 3.05),
			MAGENTA,
			Enum.Material.Neon
		)
	)
	light(strip, MAGENTA, 18, 1.2)
	newPart(
		jammer,
		"Cable",
		Vector3.new(0.6, 0.6, 6),
		CFrame.new(6.2, 0.3, Z0 + 4),
		Color3.fromRGB(20, 20, 20),
		Enum.Material.Rubber
	)
	jammer.PrimaryPart = body
	device(jammer, "Jammer", "Directorate signal jammer J-8", {
		Active = true,
		Status = "JAMMING ALL BANDS",
		Temperature = 52,
		JamRadius = 22,
		JamFactor = 0.15,
	})
	CollectionService:AddTag(jammer, "Jammer")
	refs.jammer = jammer
	sign(
		parent,
		facing(Vector3.new(4, 11, Z0 + 0.2), Vector3.new(4, 11, 0)),
		Vector2.new(12, 1.6),
		"MESH // DIRECTORATE JAMMER",
		MAGENTA,
		Enum.Font.Code
	)

	-- Terminal A sits inside the jammed zone; B is across the hall (shelter)
	buildTerminal(
		parent,
		refs,
		Vector3.new(-14, 0, Z0 + 3),
		math.pi,
		"Range Terminal A",
		"PKT-RANGE-ROLL",
		""
	)
	buildBeacon(
		parent,
		refs,
		Vector3.new(16, 9, Z0 + 0.6),
		Vector3.new(0, 0, 1),
		"Family SOS beacon"
	)
	buildCamera(
		parent,
		Vector3.new(-22, CEILING - 4, Z0 + 2),
		Vector3.new(0, 0, -20),
		"Directorate cam R-1"
	)
	buildJunctionBox(parent, Vector3.new(-6, 5, Z0 + 0.6), Vector3.new(0, 0, 1), "Jammer mains")
	-- Dim red work light over the jammer cage
	lamp(parent, Vector3.new(4, CEILING - 0.4, Z0 + 6), EMERGENCY, 24, 0.5)
end

---------------------------------------------------------------------------
-- North-west: the ward (outbreak + care), sealed and blacked out
---------------------------------------------------------------------------

local function buildWard(parent: Instance, refs: Refs)
	-- East wall: barricaded door + observation windows
	wallX(
		parent,
		WARD.x1,
		WARD.z0,
		WARD.z1,
		0,
		WARD.roof,
		{ rect(-24, -18, 0, 9), rect(-44, -30, 4, 8) },
		CONCRETE,
		Enum.Material.Concrete
	)
	glass(parent, Vector3.new(WARD.x1 - 0.2, 4, -44), Vector3.new(WARD.x1 + 0.2, 8, -30))
	-- South wall with a window
	wallZ(
		parent,
		WARD.z1,
		WARD.x0,
		WARD.x1 + 0.5,
		0,
		WARD.roof,
		{ rect(-60, -40, 4, 8) },
		CONCRETE,
		Enum.Material.Concrete
	)
	glass(parent, Vector3.new(-60, 4, WARD.z1 - 0.2), Vector3.new(-40, 8, WARD.z1 + 0.2))
	box(
		parent,
		"WardRoof",
		Vector3.new(WARD.x0, WARD.roof, WARD.z0),
		Vector3.new(WARD.x1 + 0.5, WARD.roof + 1, WARD.z1 + 0.5),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	sign(
		parent,
		facing(Vector3.new(WARD.x1 + 0.6, 11.5, -21), Vector3.new(0, 11.5, -21)),
		Vector2.new(14, 2),
		"WARD W-1 // QUARANTINE",
		MED
	)
	sign(
		parent,
		facing(Vector3.new(WARD.x1 + 0.6, 9.8, -21), Vector3.new(0, 9.8, -21)),
		Vector2.new(14, 1.2),
		"Sealed since the blackout. Official count: 1 sick.",
		Color3.fromRGB(200, 200, 200),
		Enum.Font.Code
	)

	-- Barricade in the doorway (outside face)
	buildDebris(
		parent,
		Vector3.new(WARD.x1 + 1.4, 2, -21),
		Vector3.new(1.4, 4, 6.4),
		"RDoor",
		"Fallen locker"
	)
	buildDebris(
		parent,
		Vector3.new(WARD.x1 + 1.4, 6.5, -21),
		Vector3.new(1.2, 5, 6.4),
		"RDoor",
		"Plywood barricade"
	)

	-- Beds along the west wall, pillows toward the wall
	local yaw = CFrame.Angles(0, -math.pi / 2, 0)
	local people = {
		{
			z = -42,
			name = "Amara Osei, 34",
			condition = "Fever",
			shirt = Color3.fromRGB(150, 70, 80),
			blanket = Color3.fromRGB(70, 90, 120),
		},
		{
			z = -30,
			name = "Tomas Reyes, 61",
			condition = "Fever",
			shirt = Color3.fromRGB(90, 110, 90),
			blanket = Color3.fromRGB(120, 100, 70),
		},
		{
			z = -18,
			name = "Ivo Petrov, 45",
			condition = "Dehydrated",
			shirt = Color3.fromRGB(110, 110, 130),
			blanket = Color3.fromRGB(80, 80, 86),
		},
	}
	for _, spec in people do
		local hips = bed(parent, CFrame.new(-60, 0, spec.z) * yaw, spec.blanket)
		buildResident(parent, refs, {
			name = spec.name,
			condition = spec.condition,
			cf = hips,
			pose = "Lie",
			shirt = spec.shirt,
		})
	end
	-- A visitor sitting by Tomas (healthy: a thermal false alarm)
	local chair = seat(parent, CFrame.new(-53, 0, -27.5) * CFrame.Angles(0, math.pi / 2, 0), 2.2)
	buildResident(parent, refs, {
		name = "Nadia Reyes, 58",
		condition = "Healthy",
		cf = chair,
		pose = "Sit",
		shirt = Color3.fromRGB(170, 120, 60),
	})

	-- Space heater: hot on thermal, but not a person
	local heater = newModel(parent, "SpaceHeater")
	local heaterBody = newPart(
		heater,
		"Body",
		Vector3.new(2, 2.4, 1),
		CFrame.new(-36, 1.2, -45),
		METAL_DARK,
		Enum.Material.Metal
	)
	decor(
		newPart(
			heater,
			"Coils",
			Vector3.new(1.6, 1.6, 0.1),
			heaterBody.CFrame * CFrame.new(0, 0, 0.52) * CFrame.Angles(0, math.pi, 0),
			Color3.fromRGB(255, 90, 20),
			Enum.Material.Neon
		)
	)
	heater.PrimaryPart = heaterBody
	device(
		heater,
		"HeatSource",
		"Unknown heat signature",
		{ Temperature = 61, Status = "UNIDENTIFIED" }
	)

	-- Stale, spore-laden air
	buildGas(parent, nil, "Spores", Vector3.new(-50, 5, -30), 10, 45, "Quarantine")
	local zone = volume(
		parent,
		"AirZone",
		Vector3.new(WARD.x0, 0, WARD.z0),
		Vector3.new(WARD.x1, WARD.roof, WARD.z1)
	)
	for key, value in
		{
			Label = "WARD W-1",
			O2 = 19.6,
			CO2 = 2600,
			PM = 64,
			Temp = 31,
			Verdict = "Stale, crowded air: CO2 high, spores present. Ventilate before anyone else goes in.",
			Objective = "RAir",
		} :: { [string]: any }
	do
		zone:SetAttribute(key, value)
	end
	CollectionService:AddTag(zone, "AirZone")

	-- One dim emergency light: the ward is a blackout block (thermal / NV)
	local bulb = decor(
		ball(
			parent,
			"EmergencyBulb",
			0.5,
			Vector3.new(-48, WARD.roof - 0.4, -30),
			EMERGENCY,
			Enum.Material.Neon
		)
	)
	light(bulb, EMERGENCY, 16, 0.25)
	bulb:SetAttribute("FlickerMode", "Pulse")
	CollectionService:AddTag(bulb, "Flicker")
end

---------------------------------------------------------------------------
-- South-west: mezzanine + ramp (guide mode start)
---------------------------------------------------------------------------

local function buildMezzanine(parent: Instance)
	box(
		parent,
		"Mezzanine",
		Vector3.new(MEZZ.x0, MEZZ.top - 1, MEZZ.z0),
		Vector3.new(MEZZ.x1, MEZZ.top, MEZZ.z1),
		METAL_DARK,
		Enum.Material.DiamondPlate
	)
	for _, x in { MEZZ.x1 - 1, -53 } do
		for _, z in { MEZZ.z0 + 1, 30 } do
			box(
				parent,
				"Column",
				Vector3.new(x - 0.6, 0, z - 0.6),
				Vector3.new(x + 0.6, MEZZ.top - 1, z + 0.6),
				METAL,
				Enum.Material.Metal
			)
		end
	end
	-- Rails: north edge, east edge (open where the ramp joins)
	rail(
		parent,
		Vector3.new(MEZZ.x0, MEZZ.top, MEZZ.z0 + 0.3),
		Vector3.new(MEZZ.x1, MEZZ.top, MEZZ.z0 + 0.3)
	)
	rail(
		parent,
		Vector3.new(MEZZ.x1 - 0.3, MEZZ.top, MEZZ.z0),
		Vector3.new(MEZZ.x1 - 0.3, MEZZ.top, RAMP.top.Z - RAMP.width / 2)
	)
	ramp(parent, RAMP.top, RAMP.bottom, RAMP.width)
	lamp(parent, Vector3.new(-56, MEZZ.top + 8, 36), Color3.fromRGB(255, 196, 130), 22, 0.5)
	sign(
		parent,
		facing(Vector3.new(MEZZ.x1 - 0.6, MEZZ.top + 5, 26), Vector3.new(0, MEZZ.top + 5, 26)),
		Vector2.new(12, 1.4),
		"MEZZANINE // L8 ACCESS",
		HAZARD,
		Enum.Font.Code
	)
	-- Storage under the mezzanine
	local rng = Random.new(87)
	for _ = 1, 6 do
		local x = rng:NextNumber(-63, -48)
		local z = rng:NextNumber(18, 44)
		local s = rng:NextNumber(2.5, 4)
		box(
			parent,
			"Crate",
			Vector3.new(x, 0, z),
			Vector3.new(x + s, s, z + s),
			Color3.fromRGB(70, 74, 60),
			Enum.Material.WoodPlanks
		)
	end
	-- Ada: lost up here since the blackout
	civilian(
		parent,
		"Ada Mensah, 27",
		CFrame.lookAt(Vector3.new(-56, MEZZ.top + 1.95, 24), Vector3.new(-40, MEZZ.top + 1.95, 24)),
		Color3.fromRGB(180, 120, 60),
		{
			Lost = true,
			ReuniteWith = "Kofi Mensah",
			Route = "down the mezzanine ramp and across the hall",
			Objective = "RReunite",
			Status = "LOST · CAN'T FIND THE WAY DOWN IN THE DARK",
		}
	)
end

---------------------------------------------------------------------------
-- South-east: shelter (family, terminal B, med rack)
---------------------------------------------------------------------------

local function buildShelter(parent: Instance, refs: Refs)
	sign(
		parent,
		facing(Vector3.new(44, 12, Z1 - 0.2), Vector3.new(44, 12, 0)),
		Vector2.new(16, 2),
		"SHELTER // MED SUPPLY",
		GREEN
	)
	-- Benches
	for _, x in { 32, 40 } do
		seat(parent, CFrame.new(x, 0, 41), 6)
	end
	bystander(
		parent,
		CFrame.new(40, 0, 41) * CFrame.new(1.2, 1.05, 0.05),
		"Sit",
		Color3.fromRGB(70, 90, 120)
	)
	-- Kofi waits here for Ada
	civilian(
		parent,
		"Kofi Mensah, 59",
		CFrame.lookAt(Vector3.new(44, 1.95, 30), Vector3.new(30, 1.95, 30)),
		Color3.fromRGB(70, 90, 120),
		{
			Family = "Kofi Mensah",
			Place = "the shelter corner",
			Status = "WAITING FOR ADA",
		}
	)
	buildTerminal(
		parent,
		refs,
		Vector3.new(26, 0, Z1 - 3),
		0,
		"Shelter Terminal B",
		"",
		"PKT-RANGE-ROLL"
	)

	-- Med supply rack on the east wall (far side of the hall from the ward)
	local rack = newModel(parent, "MedRack")
	local cf = CFrame.lookAt(Vector3.new(X1 - 0.8, 3, 34), Vector3.new(0, 3, 34))
	local frame =
		newPart(rack, "Frame", Vector3.new(4, 6, 1.2), cf, METAL_DARK, Enum.Material.Metal)
	for row = 0, 2 do
		for col = -1, 1 do
			local kit = newPart(
				rack,
				"Kit",
				Vector3.new(1, 0.8, 0.9),
				cf * CFrame.new(col * 1.2, -2 + row * 1.8, -0.5),
				WHITE
			)
			decor(
				newPart(
					rack,
					"Cross",
					Vector3.new(0.5, 0.15, 0.05),
					kit.CFrame * CFrame.new(0, 0, -0.47),
					RED,
					Enum.Material.Neon
				)
			)
		end
	end
	light(frame, Color3.fromRGB(255, 200, 210), 8, 0.6)
	rack.PrimaryPart = frame
	device(rack, "MedRack", "Field med supplies", { Status = "STOCKED", Temperature = 18 })
end

---------------------------------------------------------------------------
-- Registration with the generic simulation
---------------------------------------------------------------------------

local function register(refs: Refs)
	local root = refs.root
	root:SetAttribute("Site", "Range")
	Registry.roots.Range = root
	Registry.spawns.Range = refs.spawn

	for _, valve in refs.valves do
		valve:SetAttribute("FloodGroup", "R1")
	end
	for _, instance in root:GetDescendants() do
		local deviceType = instance:GetAttribute("DeviceType")
		if deviceType == "Debris" and instance:GetAttribute("Objective") == "RDrain" then
			instance:SetAttribute("FloodGroup", "R1")
		elseif deviceType == "SamplePoint" then
			instance:SetAttribute("Objective", "RSamples")
		end
	end
	for _, cloud in refs.sewerGas do
		cloud:SetAttribute("VentGroup", "R1")
	end
	for _, fan in refs.fans do
		fan:SetAttribute("VentGroup", "R1")
		fan:SetAttribute("Running", false)
		CollectionService:AddTag(fan, "Fan")
	end
	refs.breaker:SetAttribute("VentGroup", "R1")
	refs.jammer:SetAttribute("Objective", "RJammer")
	refs.jammer:SetAttribute("CutText", "Jammer J-8 is offline. Terminal A has a clean link again.")
	for _, beacon in refs.beacons do
		beacon:SetAttribute("Objective", "RBeacon")
		beacon:SetAttribute(
			"Message",
			"Mensah family: Kofi is safe in the shelter corner. Ada, where are you?"
		)
	end
	for _, resident in refs.residents do
		resident:SetAttribute("LocateObjective", "RLocated")
		resident:SetAttribute("TreatObjective", "RTreated")
	end

	-- A relay at the ward door is what gets a usable link inside the sealed ward
	local zone = volume(
		root,
		"RelayZone",
		Vector3.new(WARD.x0, 0, WARD.z0),
		Vector3.new(WARD.x1 + 8, WARD.roof, WARD.z1)
	)
	zone:SetAttribute("Objective", "RRelay")
	CollectionService:AddTag(zone, "RelayZone")

	local water = refs.water
	local bottom = POOL.bottom
	Registry.floods.R1 = {
		valves = (refs.valves :: any) :: { Instance },
		valveObjective = "RValves",
		debrisObjective = "RDrain",
		debrisTotal = 2,
		apply = function(progress: number): number
			local level = WATER_HIGH + (WATER_LOW - WATER_HIGH) * progress
			local height = math.max(0.2, level - bottom)
			TweenService:Create(water, TweenInfo.new(6, Enum.EasingStyle.Sine), {
				Size = Vector3.new(water.Size.X, height, water.Size.Z),
				CFrame = CFrame.new(water.Position.X, bottom + height / 2, water.Position.Z),
			}):Play()
			return level
		end,
		describe = function(level: number): string
			return ("Pool water heading to %.1fm deep."):format(
				(level - bottom) * Config.STUDS_TO_METERS
			)
		end,
	}
	Registry.vents.R1 = {
		breaker = refs.breaker,
		objective = "RGas",
		onText = "Ventilation fans ON. The gas over the pool will clear over ~20s. Check it in CHEM vision.",
		offText = "Ventilation fans OFF. Gas will build back up.",
	}
end

function WorldBuilder.get(): Refs
	if built then
		return built
	end

	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local root = Instance.new("Folder")
	root.Name = "Junction9"
	local refs = {
		root = root,
		docks = {},
		sewerGas = {},
		valves = {},
		fans = {},
		beacons = {},
		terminals = {},
		residents = {},
	} :: any

	local function zone(name: string): Folder
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		return folder
	end

	buildShell(zone("Hall"))
	buildDockArea(zone("Dock"), refs)
	buildPool(zone("SewerPool"), refs)
	buildTransformer(zone("Plant"))
	buildMesh(zone("Mesh"), refs)
	buildWard(zone("Ward"), refs)
	buildMezzanine(zone("Mezzanine"))
	buildShelter(zone("Shelter"), refs)

	if not Workspace:FindFirstChild("Drones") then
		local drones = Instance.new("Folder")
		drones.Name = "Drones"
		drones.Parent = Workspace
	end

	local relays = Instance.new("Folder")
	relays.Name = "Relays"
	relays.Parent = root

	register(refs :: Refs)
	root.Parent = Workspace
	built = refs :: Refs
	return refs :: Refs
end

function WorldBuilder.init()
	WorldBuilder.get()
end

return WorldBuilder
