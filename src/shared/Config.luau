--!strict
-- Every tunable number for the simulator. Replicated to clients: nothing secret.

local Types = require(script.Parent.Types)

local MODULES: { [string]: Types.ModuleSpec } = {
	Sensor = {
		label = "SENSOR POD",
		short = "SNS",
		description = "Gas sniffer, water probe and vitals reader. Unlocks CHEM vision.",
		color = Color3.fromRGB(120, 255, 140),
	},
	Arm = {
		label = "MANIPULATOR ARM",
		short = "ARM",
		description = "Grab debris, turn valves, flip breakers, cut cables.",
		color = Color3.fromRGB(255, 176, 0),
	},
	DataJack = {
		label = "DATA JACK / RELAY",
		short = "JCK",
		description = "Jack into terminals, ping beacons, deploy mesh relay nodes.",
		color = Color3.fromRGB(0, 230, 255),
	},
	Payload = {
		label = "PAYLOAD BAY",
		short = "PLD",
		description = "Carry and drop medical supplies.",
		color = Color3.fromRGB(255, 90, 130),
	},
}

local DEVICES: { [string]: Types.DeviceSpec } = {
	Valve = { label = "FLOW VALVE", prefix = "VLV", category = "Infrastructure" },
	Debris = { label = "LOOSE DEBRIS", prefix = "OBJ", category = "Infrastructure" },
	Breaker = { label = "VENT BREAKER", prefix = "BRK", category = "Infrastructure" },
	SamplePoint = { label = "OUTFLOW PIPE", prefix = "OUT", category = "Infrastructure" },
	Junction = { label = "JUNCTION BOX", prefix = "PWR", category = "Infrastructure" },
	Terminal = { label = "DATA TERMINAL", prefix = "TRM", category = "Network" },
	Beacon = { label = "EMERGENCY BEACON", prefix = "SOS", category = "Network" },
	RelayNode = { label = "MESH RELAY NODE", prefix = "MSH", category = "Network" },
	Dock = { label = "DRONE DOCK", prefix = "DCK", category = "Network" },
	Antenna = { label = "MESH ANTENNA", prefix = "MSH", category = "Network" },
	Jammer = { label = "SIGNAL JAMMER", prefix = "DIR", category = "Directorate" },
	Surveillance = { label = "SURVEILLANCE CAM", prefix = "DIR", category = "Directorate" },
	MedRack = { label = "MED SUPPLY RACK", prefix = "MED", category = "Medical" },
	Resident = { label = "LIFESIGN", prefix = "BIO", category = "Life" },
	HeatSource = { label = "HEAT SOURCE", prefix = "HTR", category = "Life" },
	Civilian = { label = "RESIDENT", prefix = "CIV", category = "Life" },
	Equipment = { label = "PLANT EQUIPMENT", prefix = "EQP", category = "Infrastructure" },
	PublicScreen = { label = "PUBLIC SCREEN", prefix = "DIR", category = "Directorate" },
}

local CATEGORY_COLORS: { [string]: Color3 } = {
	Infrastructure = Color3.fromRGB(255, 176, 0),
	Network = Color3.fromRGB(0, 230, 255),
	Directorate = Color3.fromRGB(255, 40, 120),
	Medical = Color3.fromRGB(255, 150, 180),
	Life = Color3.fromRGB(120, 255, 140),
}

local GASES: { [string]: Types.GasSpec } = {
	H2S = { label = "H2S", unit = "ppm", danger = 50, color = Color3.fromRGB(170, 255, 60) },
	CH4 = { label = "CH4", unit = "%LEL", danger = 10, color = Color3.fromRGB(255, 140, 40) },
	Spores = { label = "SPORES", unit = "k/m3", danger = 20, color = Color3.fromRGB(230, 80, 255) },
	CO2 = { label = "CO2", unit = "ppm", danger = 5000, color = Color3.fromRGB(120, 200, 255) },
}

-- Two sites in one place: the full Hollow showcase and the original test range.
local SITES: { [string]: Types.SiteSpec } = {
	Hollow = {
		name = "THE HOLLOW // SECTOR 9",
		subtitle = "Showcase: a deep-level district in 2087",
		origin = Vector3.new(0, 0, 2000),
		min = Vector3.new(-260, -80, 1760),
		max = Vector3.new(260, 520, 2280),
		datum = 0,
		lighting = {
			brightness = 2.2,
			clockTime = 12.1,
			ambient = Color3.fromRGB(22, 22, 26),
			outdoorAmbient = Color3.fromRGB(46, 46, 52),
			density = 0.36,
			haze = 2.2,
			glare = 0.3,
			atmosphereColor = Color3.fromRGB(150, 140, 125),
			decay = Color3.fromRGB(60, 52, 44),
			exposure = 0.45,
		},
	},
	Range = {
		name = "JUNCTION 9 // TEST RANGE",
		subtitle = "One hall, every mechanic: pool, mesh, ward, guide",
		origin = Vector3.zero,
		min = Vector3.new(-90, -20, -70),
		max = Vector3.new(90, 60, 70),
		datum = 0,
		lighting = {
			brightness = 0,
			clockTime = 0,
			ambient = Color3.fromRGB(14, 14, 17),
			outdoorAmbient = Color3.fromRGB(8, 8, 10),
			density = 0.3,
			haze = 1.2,
			glare = 0,
			atmosphereColor = Color3.fromRGB(60, 60, 66),
			decay = Color3.fromRGB(20, 20, 24),
			exposure = 0.3,
		},
	},
}

-- Data packets a courier drone can carry between terminals.
local PACKETS: { [string]: Types.PacketSpec } = {
	["PKT-L9-FAMILY"] = {
		name = "214 family check-in messages from the L9 shelter",
		destination = "Community Board 7-N (Level 7, north gallery)",
		objective = "HFamily",
	},
	["PKT-RANGE-ROLL"] = {
		name = "Ward roll-call (test packet)",
		destination = "Shelter Terminal B (south-east corner)",
		objective = "RPacket",
	},
	["PKT-SURFACE-LOG"] = {
		name = "Surface Met Station 4: 30 years of air logs",
		destination = "Resistance Uplink (Ops Hub, Level 8 east)",
		objective = "HBroadcast",
		event = "Broadcast",
	},
}

local OBJECTIVES: { Types.ObjectiveGroup } = {
	{
		site = "Hollow",
		zone = "OP-1 FLOODLINE // COLLECTOR C-2",
		problems = { 4, 5 },
		brief = "Sewage is backing up under Level 9 and the Underpass Market is flooding.",
		items = {
			{ key = "HSamples", label = "Sample the outfall pipes", total = 3 },
			{ key = "HGas", label = "Start the methane exhaust", total = 1 },
			{ key = "HSluice", label = "Set the sluice gates", total = 2 },
			{ key = "HRack", label = "Clear the trash rack", total = 3 },
		},
	},
	{
		site = "Hollow",
		zone = "OP-2 DARK MESH // THE WELL",
		problems = { 7, 8 },
		brief = "The Directorate jammed the network. Families below the deck are cut off.",
		items = {
			{ key = "HJammer", label = "Cut the Spire jammer cable", total = 1 },
			{ key = "HRelays", label = "Mesh relays below the deck", total = 3 },
			{ key = "HBeacons", label = "Ping family SOS beacons", total = 3 },
			{ key = "HFamily", label = "Carry L9 messages to L7", total = 1 },
			{ key = "HReunite", label = "Beep-guide Ada down to her family", total = 1 },
		},
	},
	{
		site = "Hollow",
		zone = "OP-3 FEVER WARD // QUARANTINE Q-9",
		problems = { 9, 10 },
		brief = "Lung sickness behind a sealed, blacked-out block. Official count: 3.",
		items = {
			{ key = "HLocated", label = "Find residents (thermal + vitals)", total = 5 },
			{ key = "HBarricade", label = "Clear the barricaded door", total = 2 },
			{ key = "HTreated", label = "Drop med kits to the sick", total = 4 },
		},
	},
	{
		site = "Hollow",
		zone = "OP-4 GRID WATCH // EARLY WARNING",
		problems = { 1, 3, 4, 12 },
		brief = "Predict the next blackout and air cut before it hits.",
		items = {
			{ key = "HSurvey", label = "Inspect failing plant equipment", total = 4 },
			{ key = "HScrubber", label = "Restart the backup CO2 scrubber", total = 1 },
		},
	},
	{
		site = "Hollow",
		zone = "OP-5 THE WAY UP // LIFT SHAFT ZERO",
		problems = { 13, 7 },
		brief = "Is the surface air really lethal? Fly up and find out.",
		items = {
			{ key = "HSurfaceAir", label = "Sample air at the surface", total = 1 },
			{ key = "HWeatherLog", label = "Download Met Station logs", total = 1 },
			{ key = "HBroadcast", label = "Broadcast the truth (Ops uplink)", total = 1 },
		},
	},
	-- Test range: one hall, one checklist (counts kept to the minimum that
	-- still shows each mechanic working)
	{
		site = "Range",
		zone = "R-1 WATER + AIR // NE POOL",
		problems = { 4, 5 },
		brief = "Sunken sewer pool: samples, valves, drain, gas.",
		items = {
			{ key = "RSamples", label = "Sample both outflow pipes", total = 2 },
			{ key = "RValves", label = "Set both pool gates", total = 2 },
			{ key = "RDrain", label = "Clear the drain grate", total = 2 },
			{ key = "RGas", label = "Vent the gas (breaker V-1)", total = 1 },
		},
	},
	{
		site = "Range",
		zone = "R-2 MESH + FAMILIES // N WALL, MEZZANINE",
		problems = { 7, 8 },
		brief = "Jammer, relay, beacon, data courier, guide mode.",
		items = {
			{ key = "RJammer", label = "Cut the jammer cable", total = 1 },
			{ key = "RPacket", label = "Carry the packet A -> B", total = 1 },
			{ key = "RBeacon", label = "Ping the SOS beacon", total = 1 },
			{ key = "RRelay", label = "Relay at the ward door", total = 1 },
			{ key = "RReunite", label = "Beep-guide Ada to Kofi", total = 1 },
		},
	},
	{
		site = "Range",
		zone = "R-3 CARE + WARNING // NW WARD",
		problems = { 9, 10, 1 },
		brief = "Sealed ward: find, assess and treat; inspect the transformer.",
		items = {
			{ key = "RDoor", label = "Clear the ward door", total = 2 },
			{ key = "RLocated", label = "Read everyone's vitals", total = 4 },
			{ key = "RTreated", label = "Med kits to the sick", total = 3 },
			{ key = "RAir", label = "Sample the ward air", total = 1 },
			{ key = "RInspect", label = "Inspect transformer TX-4", total = 1 },
		},
	},
}

local Config = {
	DRONE = table.freeze({
		SPEED = 26,
		BOOST_SPEED = 46,
		VERTICAL_SPEED = 18,
		LOW_POWER_SPEED = 8,
		ACCELERATION = 5,
		LOOK_SPEED_GAMEPAD = 3.2, -- radians/second at full stick
		MOUSE_SENSITIVITY = 0.0035,
		MAX_PITCH = math.rad(80),
		TILT = math.rad(14),
		FOV = 80,
		MAX_FORCE = 25000,
		BATTERY_IDLE = 0.05, -- %/s  (~25 min endurance, a big inspection pack)
		BATTERY_MOVE = 0.12, -- %/s at full speed
		BATTERY_VISION = 0.02, -- %/s for thermal/night/chem/lidar
		BATTERY_RECHARGE = 8, -- %/s on a dock
		DOCK_RANGE = 9,
		INTERACT_RANGE = 14,
		MAX_RELAYS = 6,
		TEMPERATURE = 48, -- motors show up warm on thermal
		-- Flight model (inspection quad, ~2.1 kg class, 6S battery)
		MAX_ACCEL = 34, -- studs/s^2 the motors can produce horizontally
		DRAG = 0.9, -- linear air drag (1/s)
		BRAKE = 2.6, -- active braking when sticks centre (1/s)
		TURBULENCE = 0.9, -- studs/s of random gust at rest
		PROPWASH = 1.6, -- extra wobble near walls/floor
		GROUND_EFFECT_HEIGHT = 5, -- studs: extra lift + bounce below this
		WIND_RESPONSE = 0.65, -- how much a wind field pushes the airframe
		CELL_FULL = 25.2, -- volts, 6S pack full
		CELL_EMPTY = 19.8, -- volts at 0%
		SAG = 1.4, -- volts of sag at full throttle
		OBSTACLE_RANGE = 12, -- studs, proximity sensors
		GUIDE_RANGE = 40, -- a follower loses the beeping beyond this
		GUIDE_SPEED = 7, -- studs/s walking pace of someone following
		REUNITE_RANGE = 9,
		LIDAR_RATE = 1100, -- points per second
		LIDAR_POINTS = 7000,
		LIDAR_RANGE = 70,
	}),

	SCAN = table.freeze({
		RANGE = 110,
		WAVE_SECONDS = 1.1,
		HOLD_SECONDS = 9,
		MAX_HIGHLIGHTS = 24,
		COOLDOWN = 2.5,
	}),

	THERMAL = table.freeze({
		RANGE = 90,
		THROUGH_WALL_RANGE = 55,
		MAX_HIGHLIGHTS = 6,
	}),

	-- Body temperature bands (°C). Every person rolls their own value inside
	-- their band and drifts a little around it; treated patients cool back
	-- into the healthy band.
	VITALS = table.freeze({
		Healthy = table.freeze({ 36.3, 37.2 }),
		Fever = table.freeze({ 38.4, 40.1 }),
		Dehydrated = table.freeze({ 37.5, 38.3 }),
		FEVER_LINE = 38.0, -- at or above: febrile
		DRIFT = 0.15, -- ± live wobble around each person's own value
		RECOVERY_RATE = 0.03, -- °C per second once treated
		COUGH_INTERVAL = table.freeze({ 3.5, 9 }), -- seconds between coughs (fever)
	}),
	-- Optional cough sound (rbxassetid://…). Empty = visual cough only.
	COUGH_SOUND = "",

	LINK = table.freeze({
		LOST = 0.05,
		WEAK = 0.35,
		DOCK_RANGE = 248, -- +50% over the first build (165 / 90 / 50)
		RELAY_RANGE = 135,
		BEACON_RANGE = 75,
		JAMMER_RADIUS = 45,
		JAMMER_FACTOR = 0.15,
		OCCLUSION = 0.45, -- range multiplier when rock/walls block the path
	}),

	-- Air quality when the drone isn't inside a tagged AirZone
	AIR_DEFAULT = table.freeze({ O2 = 20.3, CO2 = 1150, PM = 38, Temp = 27 }),

	WATER = table.freeze({ HIGH = 2, LOW = -4.5 }),
	DEBRIS_CLEAR_DISTANCE = 10,
	MED_DROP_RADIUS = 10,
	GAS_VENTED_SCALE = 0.06,
	GAS_VENT_RATE = 0.025, -- scale lost per half second while vented

	MODULES = MODULES,
	MODULE_ORDER = { "Sensor", "Arm", "DataJack", "Payload" },
	DEFAULT_LOADOUT = table.freeze({ A = "Sensor", B = "Arm" }),

	DEVICES = DEVICES,
	CATEGORY_COLORS = CATEGORY_COLORS,
	GASES = GASES,
	CAMERA_MODES = { "Normal", "Thermal", "Night", "Chem", "Lidar" },
	OBJECTIVES = OBJECTIVES,
	SITES = SITES,
	SITE_ORDER = { "Hollow", "Range" },
	DEFAULT_SITE = "Hollow",
	PACKETS = PACKETS,
	PROBLEMS = {
		[1] = "Blackout early warning",
		[3] = "Heat in the deep levels",
		[4] = "Catch bad water",
		[5] = "Sewage-safe tunnels",
		[7] = "Network without the Directorate",
		[8] = "Reconnect families",
		[9] = "Track the real outbreak",
		[10] = "Get care to the deep levels",
		[12] = "Neighbourhood food",
		[13] = "Prove the surface is safe",
	},

	STUDS_TO_METERS = 0.28,
}

return table.freeze(Config)
